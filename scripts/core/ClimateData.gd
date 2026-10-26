class_name ClimateData
extends RefCounted
## 四季与天气配置的读取入口（data/seasons/seasons.json、data/weather/weather.json）。
## 只读数据；运行时状态在 WorldState。

const SEASONS_PATH := "res://data/seasons/seasons.json"
const WEATHER_PATH := "res://data/weather/weather.json"
const WEATHER_IDS := [&"CLEAR", &"OVERCAST", &"LIGHT_RAIN", &"HEAVY_RAIN", &"THUNDERSTORM", &"FOG", &"SNOW"]
const MINUTES_PER_DAY := 1440.0

static var _seasons: Dictionary = {}
static var _weather: Dictionary = {}


static func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("ClimateData: 无法解析 %s" % path)
	return {}


static func seasons() -> Dictionary:
	if _seasons.is_empty():
		_seasons = _load(SEASONS_PATH)
	return _seasons


static func weather() -> Dictionary:
	if _weather.is_empty():
		_weather = _load(WEATHER_PATH)
	return _weather


static func season_order() -> Array:
	return seasons().get("order", ["SPRING", "SUMMER", "AUTUMN", "WINTER"])


static func season_profile(id: StringName) -> Dictionary:
	return seasons()["seasons"].get(String(id), {})


static func weather_profile(id: StringName) -> Dictionary:
	return weather()["types"].get(String(id), {})


static func season_days() -> int:
	var rules := _rules()
	if rules != null:
		return int(rules.call("season_days"))
	return int(seasons().get("season_days", 12))


## 现实 1 秒对应的游戏分钟数（默认一天 = 现实 48 分钟 → 0.5）。
## 本局规则（GameRules）可以改一天的长度，0 = 时间静止。
static func game_minutes_per_real_second() -> float:
	var rules := _rules()
	if rules != null:
		return float(rules.call("game_minutes_per_real_second"))
	return MINUTES_PER_DAY / (float(seasons().get("day_length_real_minutes", 48.0)) * 60.0)


## 由世界日数推出季节（第 1 天 = first_day_season 的第 1 天）。
static func season_for_day(world_day: int) -> StringName:
	var order := season_order()
	var first := order.find(str(seasons().get("first_day_season", "AUTUMN")))
	var index := (first + int(floor(float(world_day - 1) / season_days()))) % order.size()
	return StringName(order[index])


## 该季节第一天对应的世界日数（在第 1 年内）。
static func first_day_of(season: StringName) -> int:
	var order := season_order()
	var first := order.find(str(seasons().get("first_day_season", "AUTUMN")))
	var offset := (order.find(String(season)) - first + order.size()) % order.size()
	return 1 + offset * season_days()


static func is_allowed(season: StringName, weather_id: StringName) -> bool:
	var weights: Dictionary = season_profile(season).get("weather_weights", {})
	return float(weights.get(String(weather_id), 0.0)) > 0.0


static func fallback_weather(season: StringName) -> StringName:
	return StringName(weather().get("fallback", {}).get(String(season), "CLEAR"))


static func parse_time(text: String) -> float:
	var parts := text.split(":")
	return float(parts[0]) * 60.0 + (float(parts[1]) if parts.size() > 1 else 0.0)


static func format_time(minutes: float) -> String:
	var m := int(fposmod(minutes, MINUTES_PER_DAY))
	return "%02d:%02d" % [m / 60, m % 60]


static func color(value: Variant, fallback := Color.WHITE) -> Color:
	if value is Array and (value as Array).size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func colors(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for c in value:
			out.append(color(c))
	return out


## 本局规则（Autoload GameRules）；编辑器里预览时没有 Autoload，返回 null 用数据文件的默认值。
static func _rules() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or Engine.is_editor_hint():
		return null
	return tree.root.get_node_or_null("GameRules")
