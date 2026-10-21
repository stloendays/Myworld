class_name WeatherController
extends Node
## 天气：规则、过渡与随机种子。与季节独立——“秋季雨天”= AUTUMN + LIGHT_RAIN。
## - 到达可变天的时刻（驻留 3–8 游戏小时）按当前季节权重抽下一种天气；随机数由 weather_seed 和
##   变天次数决定，所以同一存档读回来天气序列完全一致，不会“读档天气变了”。
## - 过渡 30–90 现实秒：先发 weather_transition_started，进度到 1 时发 weather_changed。
## - 季节不允许的天气（冬季下雨、非冬季下雪）一律拒绝；换季时若当前天气不合法，自动过渡到该季的后备天气。
## 只写 WorldState，不碰粒子、天空等表现节点（由 EnvironmentDirector 负责）。

const BLEND_KEYS := ["cloud_coverage", "cloud_darkness", "overcast", "fog", "sun", "rain", "snow", "wetness", "wind"]


func _ready() -> void:
	add_to_group("weather_controller")
	EventBus.time_changed.connect(_on_time_changed)
	EventBus.season_changed.connect(_on_season_changed)
	if WorldState.weather_next_change <= 0.0:
		_schedule_next()


func _process(delta: float) -> void:
	if WorldState.weather_progress >= 1.0:
		return
	var duration := maxf(WorldState.weather_transition_seconds, 0.001)
	WorldState.weather_progress = minf(1.0, WorldState.weather_progress + delta / duration)
	if WorldState.weather_progress >= 1.0:
		WorldState.weather_from = WorldState.weather_id
		EventBus.weather_changed.emit(WorldState.weather_id)


## 请求切换天气。seconds < 0 时按配置随机过渡时长；seconds = 0 立即生效。季节不允许时返回 false。
func request_weather(id: StringName, seconds := -1.0) -> bool:
	if not ClimateData.WEATHER_IDS.has(id) or not ClimateData.is_allowed(WorldState.season_id, id):
		return false
	_start_transition(id, seconds)
	_schedule_next()
	return true


func _start_transition(to: StringName, seconds: float) -> void:
	if seconds < 0.0:
		var span: Array = ClimateData.weather().get("transition_seconds", [30.0, 90.0])
		var rng := _rng(101)
		seconds = rng.randf_range(float(span[0]), float(span[1]))
	# 过渡中再次变天：以当前更接近的一端为起点
	var from := WorldState.weather_id if WorldState.weather_progress >= 0.5 else WorldState.weather_from
	WorldState.weather_from = from
	WorldState.weather_id = to
	WorldState.weather_transition_seconds = seconds
	WorldState.weather_progress = 0.0 if seconds > 0.0 else 1.0
	EventBus.weather_transition_started.emit(from, to, seconds)
	if seconds <= 0.0:
		WorldState.weather_from = to
		EventBus.weather_changed.emit(to)


func _on_time_changed(_hour: float) -> void:
	if WorldState.weather_progress < 1.0 or WorldState.absolute_minutes() < WorldState.weather_next_change:
		return
	var next := pick(WorldState.season_id, WorldState.weather_seed, WorldState.weather_change_count)
	if next != WorldState.weather_id:
		_start_transition(next, -1.0)
	_schedule_next()


func _on_season_changed(_from: StringName, to: StringName) -> void:
	if not ClimateData.is_allowed(to, WorldState.weather_id):
		_start_transition(ClimateData.fallback_weather(to), -1.0)
		_schedule_next()


func _schedule_next() -> void:
	var dwell: Array = ClimateData.weather().get("dwell_hours", [3.0, 8.0])
	var rng := _rng(202)
	WorldState.weather_next_change = WorldState.absolute_minutes() + rng.randf_range(float(dwell[0]), float(dwell[1])) * 60.0
	WorldState.weather_change_count += 1


func _rng(salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldState.weather_seed, WorldState.weather_change_count, salt])
	return rng


## 按季节权重抽一种天气（确定性：同样的种子与序号得到同样的结果）。
static func pick(season: StringName, seed_value: int, index: int) -> StringName:
	var weights: Dictionary = ClimateData.season_profile(season).get("weather_weights", {})
	var total := 0.0
	for id in ClimateData.WEATHER_IDS:
		total += maxf(0.0, float(weights.get(String(id), 0.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, index, 303])
	var roll := rng.randf() * total
	for id in ClimateData.WEATHER_IDS:
		roll -= maxf(0.0, float(weights.get(String(id), 0.0)))
		if roll <= 0.0 and float(weights.get(String(id), 0.0)) > 0.0:
			return id
	return ClimateData.fallback_weather(season)


## 当前（含过渡）天气参数：在起点与目标天气之间按平滑进度插值。
static func blended() -> Dictionary:
	var a := ClimateData.weather_profile(WorldState.weather_from)
	var b := ClimateData.weather_profile(WorldState.weather_id)
	var t := smoothstep(0.0, 1.0, WorldState.weather_progress)
	var out := {}
	for key in BLEND_KEYS:
		out[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), t)
	return out
