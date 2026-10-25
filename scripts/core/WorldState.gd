extends Node
## 世界状态的唯一权威（Autoload，内存版）。
## 已实现：世界日期与时间、季节覆盖、天气及其过渡进度、地面积雪与湿润度、可交互物状态（按 uid）、
## 角色所在区域（按 entity_id）、探索发现的地点、载具（独木舟）位置。M4 由 SaveManager 把 snapshot() 写成 user://saves/ 的版本化 JSON。
## 改动存档字段时必须同时升级 SCHEMA_VERSION 并写迁移。

const SCHEMA_VERSION := 5   ## v2：加入 discoveries 与 vehicles；v3：加入 quests（图腾任务）与 journal（图鉴）；
                            ## v4：加入 rules（新建游戏的玩法与设定）、collections（各世界的收集品）、player（所在世界、位置、朝向）
                            ## v5：加入 achievements（成就）、records（打水漂、计时挑战的最好成绩）、catches（钓到的鱼：条数与最大尺寸）、
                            ##     pantry（鱼和做过的菜）、treasures（各世界挖到的宝箱）

var world_seed: int = 0

# --- 时间与季节（WorldClock / SeasonController 写入）
var world_day: int = 1
var time_minutes: float = 1040.0
var time_paused := false
var time_scale := 1.0                  ## 调试加速倍率（不存档）
var season_override: Variant = null    ## null 或 季节 id（开发测试/玩家手动覆盖）
var season_id: StringName = &"AUTUMN"

# --- 天气（WeatherController 写入）
var weather_id: StringName = &"CLEAR"       ## 当前（过渡完成后）天气
var weather_from: StringName = &"CLEAR"     ## 过渡起点
var weather_progress: float = 1.0           ## 0..1，1 = 已完全变成 weather_id
var weather_transition_seconds: float = 0.0
var weather_seed: int = 0
var weather_change_count: int = 0
var weather_next_change: float = 0.0        ## 下一次可变天的绝对游戏分钟

# --- 地表状态（EnvironmentDirector 写入）
var ground_snow: float = 0.0
var ground_wetness: float = 0.0
var rain_recent: float = 0.0              ## 1 = 刚下过雨，雨停后约 40 游戏分钟衰减到 0（彩虹用）

var interactables: Dictionary = {}   ## uid -> state 字符串
var flags: Dictionary = {}
var discoveries: Array[StringName] = []   ## 已发现的探索点 id（world_layout.json → lake_pois），按发现顺序
var vehicles: Dictionary = {}             ## 载具 id -> {"pos": [x, z], "yaw_deg": 角度}
var quests: Dictionary = {}               ## 任务 id -> {state: active / done, progress: 已完成目标数, thanked: 图腾说过谢谢}
var journal: Dictionary = {}              ## 图鉴：kind（species / constellations）-> 按记录顺序的 id 列表
var collections: Dictionary = {}          ## 收集品：世界 id -> 按收集顺序的 id 列表（云珠、古代碎片……）
var player_spot: Dictionary = {}          ## 存档时玩家所在：{world, pos: [x, y, z], heading}（SaveManager 写入，读档时用来放人）
var achievements: Array = []              ## 已解锁的成就 id（按解锁顺序）
var records: Dictionary = {}              ## 纪录：skip_best（打水漂最多弹几下）、course:<id>（计时挑战最好成绩，秒）、dishes（做过几道菜）……
var catches: Dictionary = {}              ## 鱼 id -> {count, best_cm}
var pantry: Dictionary = {}               ## 食材与菜：fish:<鱼 id> -> 条数
var treasures: Dictionary = {}            ## 世界 id -> 挖到宝箱时的游戏日

var _actor_zones: Dictionary = {}    ## actor_id -> { zone_id: is_indoor }


func _ready() -> void:
	world_seed = int(WorldLayout.section("terrain").get("seed", 0))
	weather_seed = world_seed * 31 + 7
	var start: Dictionary = ClimateData.seasons().get("start", {})
	world_day = int(start.get("world_day", 1))
	time_minutes = ClimateData.parse_time(str(start.get("time", "17:20")))
	season_id = ClimateData.season_for_day(world_day)
	weather_id = StringName(start.get("weather", "CLEAR"))
	weather_from = weather_id


## 绝对游戏分钟（跨天连续）。
func absolute_minutes() -> float:
	return float(world_day - 1) * ClimateData.MINUTES_PER_DAY + time_minutes


func hour_fraction() -> float:
	return time_minutes / ClimateData.MINUTES_PER_DAY


## 可存档的稳定快照（M4 SaveManager 使用；不保存粒子、雨滴等可由种子重建的内容）。
func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"world_seed": world_seed,
		"world_day": world_day,
		"time_minutes": time_minutes,
		"season_override": season_override,
		"weather_id": String(weather_id),
		"weather_from": String(weather_from),
		"weather_progress": weather_progress,
		"weather_seed": weather_seed,
		"weather_change_count": weather_change_count,
		"weather_next_change": weather_next_change,
		"ground_snow": ground_snow,
		"ground_wetness": ground_wetness,
		"rain_recent": rain_recent,
		"interactables": interactables.duplicate(),
		"flags": flags.duplicate(),
		"discoveries": discoveries.map(func(d: StringName) -> String: return String(d)),
		"vehicles": vehicles.duplicate(true),
		"quests": quests.duplicate(true),
		"journal": journal.duplicate(true),
		"collections": collections.duplicate(true),
		"rules": GameRules.to_dict(),
		"player": player_spot.duplicate(true),
		"achievements": achievements.duplicate(),
		"records": records.duplicate(true),
		"catches": catches.duplicate(true),
		"pantry": pantry.duplicate(true),
		"treasures": treasures.duplicate(true),
	}


## 旧版本存档升级到当前版本（M4 的 SaveManager 读档前调用）。
static func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var v := int(d.get("schema_version", 1))
	if v < 2:
		d["discoveries"] = []
		d["vehicles"] = {}
	if v < 3:
		d["quests"] = {}
		d["journal"] = {}
	if v < 4:
		d["rules"] = GameRules.defaults()
		d["collections"] = {}
		d["player"] = {}
	if v < 5:
		d["achievements"] = []
		d["records"] = {}
		d["catches"] = {}
		d["pantry"] = {}
		d["treasures"] = {}
	d["rules"] = GameRules.sanitize(d.get("rules", {}))
	d["schema_version"] = SCHEMA_VERSION
	return d


## 记一个新发现；已经发现过返回 false。
func discover(poi_id: StringName) -> bool:
	if poi_id in discoveries:
		return false
	discoveries.append(poi_id)
	EventBus.discovered.emit(poi_id)
	return true


func set_vehicle(vehicle_id: StringName, pos: Vector2, yaw_deg: float) -> void:
	vehicles[String(vehicle_id)] = {"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "yaw_deg": snappedf(yaw_deg, 0.1)}


func register_interactable(uid: StringName, state: String) -> void:
	if uid == &"":
		push_warning("WorldState: 可交互物缺少 uid，无法存档。")
		return
	interactables[uid] = state


func set_interactable_state(uid: StringName, state: String) -> void:
	if uid == &"" or str(interactables.get(uid, "")) == state:
		return
	interactables[uid] = state
	EventBus.interactable_state_changed.emit(uid, state)


func get_interactable_state(uid: StringName) -> String:
	return str(interactables.get(uid, ""))


func enter_zone(actor_id: StringName, zone_id: StringName, is_indoor: bool) -> void:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	zones[zone_id] = is_indoor
	_actor_zones[actor_id] = zones
	EventBus.zone_entered.emit(zone_id, actor_id)


func exit_zone(actor_id: StringName, zone_id: StringName) -> void:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	if zones.erase(zone_id):
		EventBus.zone_exited.emit(zone_id, actor_id)


func zones_of(actor_id: StringName) -> Array:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	return zones.keys()


func is_indoors(actor_id: StringName) -> bool:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	for indoor in zones.values():
		if indoor:
			return true
	return false


## 图鉴加一条（kind：species / constellations）；已经有了返回 false。
func journal_add(kind: String, id: String) -> bool:
	var list: Array = journal.get(kind, [])
	if id in list:
		return false
	list.append(id)
	journal[kind] = list
	return true


func journal_list(kind: String) -> Array:
	return journal.get(kind, [])


## 读档：把迁移到当前版本的存档写回各字段（世界里已有的门、灯等由 SaveManager 随后逐个恢复）。
func restore(data: Dictionary) -> void:
	var d := migrate(data)
	world_seed = int(d.get("world_seed", world_seed))
	world_day = maxi(int(d.get("world_day", world_day)), 1)
	time_minutes = float(d.get("time_minutes", time_minutes))
	season_override = d.get("season_override")
	weather_id = StringName(str(d.get("weather_id", weather_id)))
	weather_from = StringName(str(d.get("weather_from", weather_id)))
	weather_progress = float(d.get("weather_progress", 1.0))
	weather_seed = int(d.get("weather_seed", weather_seed))
	weather_change_count = int(d.get("weather_change_count", 0))
	weather_next_change = float(d.get("weather_next_change", 0.0))
	ground_snow = float(d.get("ground_snow", 0.0))
	ground_wetness = float(d.get("ground_wetness", 0.0))
	rain_recent = float(d.get("rain_recent", 0.0))
	interactables = (d.get("interactables", {}) as Dictionary).duplicate()
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	discoveries.clear()
	for x in d.get("discoveries", []):
		discoveries.append(StringName(str(x)))
	vehicles = (d.get("vehicles", {}) as Dictionary).duplicate(true)
	quests = (d.get("quests", {}) as Dictionary).duplicate(true)
	journal = (d.get("journal", {}) as Dictionary).duplicate(true)
	collections = (d.get("collections", {}) as Dictionary).duplicate(true)
	player_spot = (d.get("player", {}) as Dictionary).duplicate(true)
	achievements = (d.get("achievements", []) as Array).duplicate()
	records = (d.get("records", {}) as Dictionary).duplicate(true)
	catches = (d.get("catches", {}) as Dictionary).duplicate(true)
	pantry = (d.get("pantry", {}) as Dictionary).duplicate(true)
	treasures = (d.get("treasures", {}) as Dictionary).duplicate(true)


## 新局：清掉上一局的进度（发现、任务、图鉴、收集品、门灯状态、船、标记）。时间天气由 GameRules.apply_start 设。
func reset_progress() -> void:
	interactables.clear()
	flags.clear()
	discoveries.clear()
	vehicles.clear()
	quests.clear()
	journal.clear()
	collections.clear()
	player_spot.clear()
	achievements.clear()
	records.clear()
	catches.clear()
	pantry.clear()
	treasures.clear()


## 收集一件收集品；已经收过返回 false。
func collect(world_id: String, item_id: String) -> bool:
	var list: Array = collections.get(world_id, [])
	if item_id in list:
		return false
	list.append(item_id)
	collections[world_id] = list
	EventBus.collected.emit(world_id, item_id)
	return true


func collected(world_id: String) -> Array:
	return collections.get(world_id, [])
