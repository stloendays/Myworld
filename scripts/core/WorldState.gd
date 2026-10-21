extends Node
## 世界状态的唯一权威（Autoload，内存版）。
## 已实现：世界日期与时间、季节覆盖、天气及其过渡进度、地面积雪与湿润度、可交互物状态（按 uid）、
## 角色所在区域（按 entity_id）。M4 由 SaveManager 把 snapshot() 写成 user://saves/ 的版本化 JSON。
## 改动存档字段时必须同时升级 SCHEMA_VERSION 并写迁移。

const SCHEMA_VERSION := 1

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
	}


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
