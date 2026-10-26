extends Node
## 本局的玩法与设定（Autoload）：新建游戏时在大厅的“新建游戏”页选，存进世界存档（WorldState 存档 v4 → rules），
## 联机时以房主的为准（欢迎包里发给访客，房主改了再广播）。
## 只记规则、回答“现在规则怎么说”；真正生效在各系统里读它：
##   时钟（一天长度 / 时间静止）、季节（季节长度 / 锁定）、天气（变天频率 / 锁定）、小动物（数量、亲人）、仙境（出现频率）、
##   任务与图鉴开关、HUD（小地图、罗盘、任务追踪、问号标记）、体力、夜晚亮度、世界种子。
## 起始季节、时刻、天气、出生世界与出生点只在开局时用一次（apply_start）。

signal changed

const MODES := ["stroll", "explore", "adventure", "photo", "challenge"]

## 设定页上的选项（按分组顺序显示）。kind：choice = 下拉；toggle = 开关；seed = 数字 + 随机按钮。
## 名字和选项文字都是中文原文，界面显示时 tr()（英文在 locale/en.po）。
const OPTIONS := [
	{"key": "mode", "group": "玩法", "label": "玩法模式", "kind": "choice", "default": "explore",
		"choices": [["stroll", "悠闲漫步"], ["explore", "探索收集"], ["adventure", "任务冒险"], ["photo", "摄影"], ["challenge", "挑战"]]},
	{"key": "spawn_world", "group": "世界与出生", "label": "出生世界", "kind": "choice", "default": "dusk_lake",
		"choices": [["dusk_lake", "暮色湖畔"], ["world_02", "云海浮岛"], ["world_03", "琥珀沙丘"]]},
	{"key": "spawn_point", "group": "世界与出生", "label": "出生点", "kind": "spawn", "default": "default"},
	{"key": "seed", "group": "世界与出生", "label": "世界种子", "kind": "seed", "default": 0},
	{"key": "start_season", "group": "时间与天气", "label": "起始季节", "kind": "choice", "default": "AUTUMN",
		"choices": [["SPRING", "春"], ["SUMMER", "夏"], ["AUTUMN", "秋"], ["WINTER", "冬"]]},
	{"key": "start_time", "group": "时间与天气", "label": "起始时刻", "kind": "choice", "default": "dusk",
		"choices": [["dawn", "清晨 6:30"], ["noon", "正午 12:00"], ["dusk", "黄昏 17:20"], ["night", "夜晚 22:00"], ["random", "随机"]]},
	{"key": "start_weather", "group": "时间与天气", "label": "起始天气", "kind": "choice", "default": "CLEAR",
		"choices": [["CLEAR", "晴"], ["OVERCAST", "多云"], ["LIGHT_RAIN", "小雨"], ["FOG", "雾"], ["SNOW", "雪（冬季）"], ["THUNDERSTORM", "雷雨"], ["random", "随机"]]},
	{"key": "day_length", "group": "时间与天气", "label": "一天长度", "kind": "choice", "default": 48,
		"choices": [[12, "12 分钟"], [24, "24 分钟"], [48, "48 分钟"], [96, "96 分钟"], [0, "时间静止"]]},
	{"key": "season_length", "group": "时间与天气", "label": "每季天数", "kind": "choice", "default": 12,
		"choices": [[3, "3 天"], [6, "6 天"], [12, "12 天"], [0, "锁定季节"]]},
	{"key": "weather_change", "group": "时间与天气", "label": "天气变化", "kind": "choice", "default": "normal",
		"choices": [["frequent", "频繁"], ["normal", "正常"], ["rare", "很少"], ["locked", "锁定不变"]]},
	{"key": "animals", "group": "生物与事件", "label": "小动物数量", "kind": "choice", "default": "normal",
		"choices": [["none", "没有"], ["few", "少"], ["normal", "正常"], ["many", "多"]]},
	{"key": "friendly_animals", "group": "生物与事件", "label": "动物亲人（不躲人）", "kind": "toggle", "default": false},
	{"key": "fairy", "group": "生物与事件", "label": "仙境林地出现", "kind": "choice", "default": "clear",
		"choices": [["never", "从不"], ["clear", "晴朗的夜晚"], ["every", "每个夜晚"]]},
	{"key": "quests", "group": "生物与事件", "label": "图腾任务", "kind": "toggle", "default": true},
	{"key": "journal", "group": "生物与事件", "label": "图鉴记录", "kind": "toggle", "default": true},
	{"key": "collectibles", "group": "生物与事件", "label": "收集品（云珠、古代碎片）", "kind": "toggle", "default": true},
	{"key": "hud_minimap", "group": "界面与难度", "label": "小地图", "kind": "toggle", "default": true},
	{"key": "hud_compass", "group": "界面与难度", "label": "罗盘条", "kind": "toggle", "default": true},
	{"key": "hud_tracker", "group": "界面与难度", "label": "任务追踪", "kind": "toggle", "default": true},
	{"key": "poi_markers", "group": "界面与难度", "label": "未发现地点的问号", "kind": "toggle", "default": true},
	{"key": "stamina", "group": "界面与难度", "label": "奔跑体力", "kind": "toggle", "default": false},
	{"key": "swim_stamina", "group": "界面与难度", "label": "游泳体力", "kind": "toggle", "default": false},
	{"key": "bright_nights", "group": "界面与难度", "label": "夜晚更亮", "kind": "toggle", "default": false},
]

const GROUPS := ["玩法", "世界与出生", "时间与天气", "生物与事件", "界面与难度"]

## 选了某种玩法模式后，这些选项跟着变（之后仍可单独改）。
const MODE_RULES := {
	"stroll": {"quests": false, "hud_tracker": false, "poi_markers": false, "hud_compass": false, "stamina": false, "swim_stamina": false,
		"friendly_animals": true, "collectibles": true, "hud_minimap": true},
	"explore": {"quests": true, "hud_tracker": true, "poi_markers": true, "hud_compass": true, "stamina": false, "swim_stamina": false,
		"friendly_animals": false, "collectibles": true, "hud_minimap": true},
	"adventure": {"quests": true, "hud_tracker": true, "poi_markers": true, "hud_compass": true, "stamina": false, "swim_stamina": false,
		"friendly_animals": false, "collectibles": true, "hud_minimap": true},
	"photo": {"quests": false, "hud_tracker": false, "poi_markers": false, "hud_compass": false, "hud_minimap": false, "stamina": false,
		"swim_stamina": false, "friendly_animals": true, "day_length": 96, "weather_change": "rare"},
	"challenge": {"quests": true, "hud_tracker": true, "poi_markers": false, "hud_compass": true, "hud_minimap": false, "stamina": true,
		"swim_stamina": true, "friendly_animals": false, "weather_change": "frequent", "animals": "few"},
}

## 每种模式在设定页上的一句说明。
const MODE_HINTS := {
	"stroll": "没有任务和体力，小动物不怕人，适合散步、看风景。",
	"explore": "罗盘和问号指路，找齐每个世界的探索点和收集品。",
	"adventure": "图腾的任务、风灯和古代碎片一个接一个，任务追踪一直开着。",
	"photo": "界面最简，时间走得慢；按 F12 拍下摄影清单上的东西。",
	"challenge": "奔跑和游泳都要体力，没有小地图和问号，浮岛跳台计时。",
}

## 一键预设：在默认值上覆盖这些（先套模式，再套其余）。
const PRESETS := [
	{"id": "vacation", "name": "悠闲度假", "rules": {"mode": "stroll", "start_season": "SUMMER", "start_time": "noon", "start_weather": "CLEAR",
		"weather_change": "locked", "day_length": 96, "animals": "many"}},
	{"id": "explorer", "name": "探险家", "rules": {"mode": "explore", "start_season": "AUTUMN", "start_time": "dusk", "start_weather": "CLEAR"}},
	{"id": "winter", "name": "冬日仙境", "rules": {"mode": "stroll", "start_season": "WINTER", "start_time": "dawn", "start_weather": "SNOW",
		"season_length": 0, "weather_change": "rare"}},
	{"id": "stargaze", "name": "观星之夜", "rules": {"mode": "explore", "start_season": "SUMMER", "start_time": "night", "start_weather": "CLEAR",
		"weather_change": "locked", "day_length": 96, "fairy": "every", "bright_nights": true}},
	{"id": "rainy", "name": "雨季", "rules": {"mode": "stroll", "start_season": "SPRING", "start_time": "dusk", "start_weather": "LIGHT_RAIN",
		"weather_change": "frequent"}},
	{"id": "photographer", "name": "摄影师", "rules": {"mode": "photo", "start_season": "AUTUMN", "start_time": "dusk", "start_weather": "CLEAR"}},
	{"id": "cloud", "name": "云端旅人", "rules": {"mode": "explore", "spawn_world": "world_02", "start_time": "dusk"}},
	{"id": "dunes", "name": "沙海寻宝", "rules": {"mode": "adventure", "spawn_world": "world_03", "start_season": "SUMMER", "start_time": "noon"}},
	{"id": "hardcore", "name": "硬核挑战", "rules": {"mode": "challenge", "start_season": "AUTUMN", "start_time": "dusk", "start_weather": "random"}},
]

## 起始时刻对应的游戏分钟
const START_MINUTES := {"dawn": 390.0, "noon": 720.0, "dusk": 1040.0, "night": 1320.0}

## 每个世界的出生点：id → [名字, 位置]（湖畔用 world_layout.json → dev_spots 的名字；别的世界用它们数据文件里的 spawns）
const LAKE_SPAWNS := [["default", "林道出生点"], ["码头尽头", "码头尽头"], ["木屋门廊", "木屋门廊"], ["湖心小岛", "湖心小岛"],
	["雪山顶", "雪山顶"], ["南部草甸", "南部草甸"], ["山洞口", "山洞口"]]

var rules: Dictionary = {}


func _ready() -> void:
	rules = defaults()


static func defaults() -> Dictionary:
	var d := {}
	for o: Dictionary in OPTIONS:
		d[o["key"]] = o["default"]
	return d


static func option(key: String) -> Dictionary:
	for o: Dictionary in OPTIONS:
		if o["key"] == key:
			return o
	return {}


## 合法化：未知的键丢掉，缺的补默认，下拉选项不在列表里的换回默认。
static func sanitize(d: Dictionary) -> Dictionary:
	var out := defaults()
	for o: Dictionary in OPTIONS:
		var k: String = o["key"]
		if not d.has(k):
			continue
		var v: Variant = d[k]
		match str(o["kind"]):
			"toggle":
				out[k] = bool(v)
			"seed":
				out[k] = int(v)
			"spawn":
				out[k] = str(v)
			_:
				for c: Array in o["choices"]:
					if str(c[0]) == str(v):
						out[k] = c[0]
	return out


func get_rule(key: String) -> Variant:
	return rules.get(key, option(key).get("default"))


func flag(key: String) -> bool:
	return bool(get_rule(key))


## 整套换掉（读档、联机收到房主的规则、开新局）。
func set_all(d: Dictionary) -> void:
	rules = sanitize(d)
	changed.emit()


func set_rule(key: String, value: Variant) -> void:
	var d := rules.duplicate()
	d[key] = value
	if key == "spawn_world":
		d["spawn_point"] = "default"
	set_all(d)


## 某个玩法模式下的整套规则（在 base 上覆盖模式自带的开关）。
static func with_mode(base: Dictionary, mode: String) -> Dictionary:
	var d := base.duplicate()
	d["mode"] = mode
	for k in MODE_RULES.get(mode, {}):
		d[k] = MODE_RULES[mode][k]
	return sanitize(d)


static func preset_rules(id: String) -> Dictionary:
	for p: Dictionary in PRESETS:
		if p["id"] == id:
			var r: Dictionary = p["rules"]
			var d := with_mode(defaults(), str(r.get("mode", "explore")))
			for k in r:
				d[k] = r[k]
			return sanitize(d)
	return defaults()


func to_dict() -> Dictionary:
	return rules.duplicate()


# ---------------------------------------------------------------- 各系统来问

## 每现实秒走多少游戏分钟（0 = 时间静止）。
func game_minutes_per_real_second() -> float:
	var dl := int(get_rule("day_length"))
	return 0.0 if dl <= 0 else ClimateData.MINUTES_PER_DAY / (float(dl) * 60.0)


func season_days() -> int:
	var n := int(get_rule("season_length"))
	return n if n > 0 else 12


func season_locked() -> bool:
	return int(get_rule("season_length")) <= 0


## 变天的驻留时长倍率；锁定返回 INF（不再自动变天）。
func weather_dwell_scale() -> float:
	match str(get_rule("weather_change")):
		"frequent":
			return 0.3
		"rare":
			return 3.0
		"locked":
			return INF
	return 1.0


func animal_factor() -> float:
	return {"none": 0.0, "few": 0.5, "normal": 1.0, "many": 2.0}.get(str(get_rule("animals")), 1.0)


## 仙境今晚会不会出现（夜里的时段由 FairyGlade 判断，这里只管频率）。
func fairy_allows(weather: StringName, clear_weather: bool) -> bool:
	match str(get_rule("fairy")):
		"never":
			return false
		"every":
			return true
	return clear_weather


func mode() -> String:
	return str(get_rule("mode"))


## 本局的世界种子（0 = 用世界自带的）。
func world_seed() -> int:
	return int(get_rule("seed"))


# ---------------------------------------------------------------- 开局

## 起始时刻（游戏分钟），随机时按种子挑一个。
func start_minutes() -> float:
	var t := str(get_rule("start_time"))
	if t == "random":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed(), "time"])
		return float(rng.randi_range(5 * 60, 23 * 60))
	return float(START_MINUTES.get(t, 1040.0))


## 起始天气（季节不允许时换成该季的后备天气，随机时按种子和季节权重抽）。
func start_weather(season: StringName) -> StringName:
	var w := str(get_rule("start_weather"))
	if w == "random":
		return WeatherController.pick(season, hash([world_seed(), "weather"]), 0)
	var id := StringName(w)
	if not ClimateData.is_allowed(season, id):
		return ClimateData.fallback_weather(season)
	return id


## 新局：把时间、季节、天气、种子按规则设好（湖畔的气候系统在场时）。返回实际用的 {season, minutes, weather}。
func apply_start() -> Dictionary:
	var season := StringName(str(get_rule("start_season")))
	var minutes := start_minutes()
	var weather := start_weather(season)
	if world_seed() != 0:
		WorldState.weather_seed = world_seed() * 31 + 7
	WorldState.weather_change_count = 0
	WorldState.season_override = season if season_locked() else null
	WorldState.ground_snow = 0.85 if season == &"WINTER" and weather == &"SNOW" else 0.0
	WorldState.ground_wetness = 0.8 if weather in [&"LIGHT_RAIN", &"HEAVY_RAIN", &"THUNDERSTORM"] else 0.0
	WorldState.rain_recent = 0.0
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	if climate != null:
		climate.clock.set_time(ClimateData.first_day_of(season), minutes)
		climate.seasons.refresh()
		climate.weather.request_weather(weather, 0.0)
	else:
		WorldState.world_day = ClimateData.first_day_of(season)
		WorldState.time_minutes = minutes
		WorldState.season_id = season
		WorldState.weather_id = weather
		WorldState.weather_from = weather
		WorldState.weather_progress = 1.0
	WorldState.weather_next_change = 0.0
	if climate != null:
		climate.weather._schedule_next()
	return {"season": season, "minutes": minutes, "weather": weather}


## 规则改了以后让在场的系统马上跟上（小动物数量、季节锁定、变天计划、HUD）。
func apply_ongoing() -> void:
	if season_locked() and WorldState.season_override == null:
		WorldState.season_override = WorldState.season_id
	elif not season_locked() and WorldState.season_override != null and str(get_rule("start_season")) == str(WorldState.season_override):
		WorldState.season_override = null
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	if climate != null:
		climate.seasons.refresh()
		climate.weather._schedule_next()
	for f in get_tree().get_nodes_in_group("fauna_spawner"):
		(f as FaunaSpawner).apply_density(animal_factor(), world_seed())
	changed.emit()


## 出生点：返回 {pos: Vector3, heading}；没有特别指定就用该世界的默认出生方式（空字典）。
func spawn_point(world_id: String) -> Dictionary:
	var sp := str(get_rule("spawn_point"))
	if sp == "default" or sp == "":
		return {}
	if world_id == "dusk_lake":
		for s: Dictionary in WorldLayout.data().get("dev_spots", []):
			if str(s["name"]) == sp:
				var a: Array = s["pos"]
				var pos := Vector3(float(a[0]), 0.0, float(a[1]))
				if a.size() == 3:
					pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
				elif s.get("ground", false):
					pos.y = WorldTerrain.height_at(pos.x, pos.z) + 0.1
				return {"pos": pos, "heading": float(s.get("heading", 0.0))}
		return {}
	for s: Dictionary in MiniWorld.data_for(world_id).get("spawns", []):
		if str(s["id"]) == sp:
			return {"id": sp, "heading": float(s.get("heading", 0.0))}
	return {}


## 某世界可选的出生点 [[id, 名字], ...]（设定页的下拉）。
static func spawn_choices(world_id: String) -> Array:
	if world_id == "dusk_lake":
		return LAKE_SPAWNS
	var out := [["default", "光门前"]]
	for s: Dictionary in MiniWorld.data_for(world_id).get("spawns", []):
		out.append([str(s["id"]), str(s["name"])])
	return out
