class_name ClimateSystem
extends Node
## 时间 / 季节 / 天气三个模块的容器（Main/Systems）。对外提供调试与预设入口，
## 内部只是按顺序调用 WorldClock、SeasonController、WeatherController，不另存状态。

@onready var clock: WorldClock = $WorldClock
@onready var seasons: SeasonController = $SeasonController
@onready var weather: WeatherController = $WeatherController


func _ready() -> void:
	add_to_group("climate_system")


## 预设见 data/weather/weather.json → presets（Autumn_Dusk_Clear 等）。立即生效，用于测试与调试面板。
func apply_preset(preset: String) -> bool:
	var p: Dictionary = ClimateData.weather().get("presets", {}).get(preset, {})
	if p.is_empty():
		return false
	WorldState.season_override = null
	clock.set_time(ClimateData.first_day_of(StringName(p["season"])), ClimateData.parse_time(str(p["time"])))
	seasons.refresh()
	# 预设代表“已经持续了一段时间”的天气，所以地面积雪与湿润度直接给到稳定值
	WorldState.ground_snow = float(p.get("ground_snow", WorldState.ground_snow))
	WorldState.ground_wetness = float(p.get("wetness", WorldState.ground_wetness))
	WorldState.rain_recent = float(p.get("rain_recent", 0.0))
	return weather.request_weather(StringName(p["weather"]), 0.0)


## 跳到某季节的第一天（保留当天时刻），按日期推算季节。
func jump_to_season(season: StringName) -> void:
	WorldState.season_override = null
	clock.set_time(ClimateData.first_day_of(season), WorldState.time_minutes)
	seasons.refresh()
	# 跳季相当于时间快进了很多天：非冬季时积雪早已化完
	if season != &"WINTER":
		WorldState.ground_snow = 0.0


func next_season() -> void:
	var order := ClimateData.season_order()
	var i := order.find(String(WorldState.season_id))
	jump_to_season(StringName(order[(i + 1) % order.size()]))


func set_hour(hour: float) -> void:
	clock.set_time(WorldState.world_day, hour * 60.0)


func skip_hours(hours: float) -> void:
	clock.advance(hours * 60.0)


func set_weather(id: StringName, seconds := 8.0) -> bool:
	return weather.request_weather(id, seconds)
