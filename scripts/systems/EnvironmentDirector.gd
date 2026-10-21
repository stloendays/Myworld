@tool
class_name EnvironmentDirector
extends Node3D
## 环境导演：把时间（WorldClock）、季节（SeasonController）、天气（WeatherController）的状态
## 合成为画面——太阳与月亮、天空颜色与云、雾、环境光、地表湿润与积雪、降水强度、植被季节色。
## 只读 WorldState（状态以它为准）并响应 EventBus；不保存任何状态，不读写存档。
## 编辑器里按 seasons.json 的开局时刻（秋季第 1 天 17:20、晴）显示，方便预览。

const GENERATED := "Generated"
const SKY_SHADER := preload("res://shaders/sky.gdshader")

## 按太阳高度（度）插值的天空与光照关键帧
const KEYS := [-18.0, -8.0, -2.0, 4.0, 12.0, 30.0, 60.0]
const TOP := [Color(0.015, 0.02, 0.06), Color(0.04, 0.05, 0.14), Color(0.10, 0.10, 0.30), Color(0.16, 0.18, 0.48), Color(0.20, 0.24, 0.58), Color(0.24, 0.42, 0.80), Color(0.22, 0.45, 0.86)]
const HORIZON := [Color(0.03, 0.035, 0.08), Color(0.20, 0.16, 0.30), Color(0.62, 0.36, 0.46), Color(0.93, 0.52, 0.55), Color(0.93, 0.60, 0.66), Color(0.74, 0.80, 0.92), Color(0.70, 0.82, 0.95)]
const SUN_COLOR := [Color(0.5, 0.4, 0.6), Color(0.8, 0.4, 0.4), Color(1.0, 0.45, 0.35), Color(1.0, 0.55, 0.40), Color(1.0, 0.66, 0.50), Color(1.0, 0.90, 0.80), Color(1.0, 0.97, 0.92)]
const SUN_ENERGY := [0.0, 0.0, 0.0, 0.6, 1.15, 1.6, 1.8]
const AMBIENT := [0.16, 0.28, 0.55, 0.75, 0.85, 1.0, 1.05]
const CLOUD_LIT := [Color(0.10, 0.11, 0.18), Color(0.30, 0.25, 0.40), Color(0.80, 0.50, 0.60), Color(0.98, 0.66, 0.66), Color(0.98, 0.72, 0.74), Color(0.97, 0.97, 1.0), Color(0.98, 0.98, 1.0)]
const CLOUD_SHADE := [Color(0.04, 0.05, 0.09), Color(0.10, 0.10, 0.20), Color(0.30, 0.24, 0.40), Color(0.38, 0.33, 0.55), Color(0.42, 0.38, 0.58), Color(0.62, 0.66, 0.75), Color(0.66, 0.70, 0.80)]

var environment: Environment = null
var sun: DirectionalLight3D = null
var moon: DirectionalLight3D = null
var sky_material: ShaderMaterial = null

## 最近一次计算结果（调试面板、测试读取）
var sun_elevation := 0.0
var sun_azimuth := 0.0
var night := 0.0
var wind_strength := 0.0
var wind_direction := Vector2(0.8, 0.6)   ## 风吹向的方向（世界 XZ），独木舟漂流用
var rainbow := 0.0
var lightning_count := 0
var flash := 0.0

var flash_light: DirectionalLight3D = null
var _flash_timer := 0.0
var _flash_t := -1.0
var _flash_rng := RandomNumberGenerator.new()

var _last_season: StringName = &""
var _snow_overlay_on := false
var _last_reflection_el := 999.0
var _last_reflection_weather: StringName = &""
var _reflection_cooldown := 0.0


func _ready() -> void:
	add_to_group("environment_director")
	_build()
	if Engine.is_editor_hint():
		var start: Dictionary = ClimateData.seasons().get("start", {})
		var season := ClimateData.season_for_day(int(start.get("world_day", 1)))
		_apply(season, ClimateData.parse_time(str(start.get("time", "17:20"))), ClimateData.weather_profile(&"CLEAR"))
		return
	EventBus.season_changed.connect(func(_f: StringName, _t: StringName) -> void: _apply_season_visuals())
	_apply_season_visuals.call_deferred()
	_update(0.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update(delta)


func _build() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)

	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_noise", _cloud_noise())
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ssr_enabled = true
	environment.ssr_max_steps = 128
	environment.ssr_fade_in = 0.1
	environment.ssr_fade_out = 2.5
	environment.ssr_depth_tolerance = 4.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.05
	environment.fog_enabled = true
	environment.fog_sky_affect = 0.15
	environment.fog_aerial_perspective = 0.35
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0
	root.add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.directional_shadow_max_distance = 120.0
	root.add_child(moon)
	flash_light = DirectionalLight3D.new()
	flash_light.name = "LightningFlash"
	flash_light.light_color = Color(0.78, 0.84, 1.0)
	flash_light.light_energy = 0.0
	flash_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	root.add_child(flash_light)
	_flash_rng.seed = 90210


func _update(delta: float) -> void:
	var w := WeatherController.blended()
	_integrate_ground(delta, w)
	_update_wind(w)
	_update_lightning(delta, w)
	_apply(WorldState.season_id, WorldState.time_minutes, w)
	RenderingServer.global_shader_parameter_set("rain_amount", float(w["rain"]))
	RenderingServer.global_shader_parameter_set("snow_fall", float(w["snow"]))
	RenderingServer.global_shader_parameter_set("wetness", WorldState.ground_wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", WorldState.ground_snow)
	RenderingServer.global_shader_parameter_set("wind_strength", wind_strength)
	RenderingServer.global_shader_parameter_set("lightning_flash", flash)
	var overlay := WorldState.ground_snow > 0.01
	if overlay != _snow_overlay_on:
		_snow_overlay_on = overlay
		ArtMaterials.set_snow_overlay(overlay)
	get_tree().call_group("precipitation", "set_amounts", float(w["rain"]), float(w["snow"]), wind_strength)
	get_tree().call_group("precipitation", "set_seasonal", WorldState.season_id, night, float(w["rain"]) + float(w["snow"]), wind_strength)
	_maybe_refresh_reflection(delta)


## 地表湿润与积雪随游戏时间变化：下雨变湿、雨停慢慢变干；下雪积雪，冬季缓慢、其他季节很快融化。
func _integrate_ground(delta: float, w: Dictionary) -> void:
	if WorldState.time_paused:
		return
	var dm := delta * ClimateData.game_minutes_per_real_second() * WorldState.time_scale
	var target_wet := float(w["wetness"])
	if target_wet > WorldState.ground_wetness:
		WorldState.ground_wetness = minf(target_wet, WorldState.ground_wetness + dm / 30.0)
	else:
		WorldState.ground_wetness = maxf(target_wet, WorldState.ground_wetness - dm / 240.0)
	if float(w["rain"]) > 0.2:
		WorldState.rain_recent = 1.0
	else:
		WorldState.rain_recent = maxf(0.0, WorldState.rain_recent - dm / 40.0)
	var snowing := float(w["snow"])
	if snowing > 0.05:
		WorldState.ground_snow = minf(1.0, WorldState.ground_snow + snowing * dm / 120.0)
	else:
		var melt := 1.0 / 1440.0 if WorldState.season_id == &"WINTER" else 1.0 / 90.0
		WorldState.ground_snow = maxf(0.0, WorldState.ground_snow - melt * dm)


func _apply(season: StringName, minutes: float, w: Dictionary) -> void:
	var profile := ClimateData.season_profile(season)
	var angles := sun_angles(profile, minutes)
	sun_elevation = angles.x
	sun_azimuth = angles.y
	night = 1.0 - smoothstep(-12.0, -2.0, sun_elevation)
	var overcast := float(w["overcast"])
	var darkness := float(w["cloud_darkness"])
	var tint := ClimateData.color(profile.get("sky_tint"))

	var top := _key(TOP, sun_elevation) * tint
	var horizon := _key(HORIZON, sun_elevation) * tint
	var grey_top := Color(top.get_luminance(), top.get_luminance(), top.get_luminance()) * (1.0 - 0.45 * darkness) * 1.1
	var grey_hor := Color(horizon.get_luminance(), horizon.get_luminance(), horizon.get_luminance()) * (1.0 - 0.4 * darkness)
	top = top.lerp(grey_top, overcast)
	horizon = horizon.lerp(grey_hor, overcast)
	var cloud_lit := _key(CLOUD_LIT, sun_elevation).lerp(grey_hor * 1.05, overcast) * (1.0 - 0.5 * darkness)
	var cloud_shade := _key(CLOUD_SHADE, sun_elevation) * (1.0 - 0.5 * darkness)

	sky_material.set_shader_parameter("top_color", top)
	sky_material.set_shader_parameter("horizon_color", horizon)
	sky_material.set_shader_parameter("ground_color", horizon * 0.25)
	sky_material.set_shader_parameter("cloud_coverage", float(w["cloud_coverage"]))
	sky_material.set_shader_parameter("cloud_lit", cloud_lit)
	sky_material.set_shader_parameter("cloud_shade", cloud_shade)
	sky_material.set_shader_parameter("overcast", overcast)
	sky_material.set_shader_parameter("night", night)
	sky_material.set_shader_parameter("sun_visibility", (1.0 - overcast * 0.9) * smoothstep(-6.0, 0.0, sun_elevation))
	sky_material.set_shader_parameter("sun_tint", _key(SUN_COLOR, sun_elevation))
	# 彩虹：刚下过雨、已经放晴、太阳不高（低于 40°）时出现
	rainbow = 0.0 if Engine.is_editor_hint() else WorldState.rain_recent * (1.0 - overcast) * smoothstep(2.0, 8.0, sun_elevation) * (1.0 - smoothstep(32.0, 40.0, sun_elevation))
	sky_material.set_shader_parameter("rainbow", rainbow)

	var to_sun := _direction(sun_elevation, sun_azimuth)
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.light_color = _key(SUN_COLOR, sun_elevation)
	sun.light_energy = _keyf(SUN_ENERGY, sun_elevation) * float(w["sun"])
	sun.shadow_enabled = sun_elevation > -2.0
	sun.shadow_opacity = 1.0 - overcast * 0.75
	var moon_el := clampf(-sun_elevation, 12.0, 50.0)
	moon.basis = Basis.looking_at(-_direction(moon_el, sun_azimuth + 180.0), Vector3.UP)
	moon.light_energy = 0.22 * night * (1.0 - overcast * 0.7)
	moon.shadow_enabled = night > 0.6

	environment.ambient_light_energy = _keyf(AMBIENT, sun_elevation) * lerpf(1.0, 0.85, overcast) + flash * 0.8
	environment.tonemap_exposure = lerpf(1.05, 1.35, night)
	environment.fog_light_color = horizon.lerp(top, 0.35) * 0.8
	environment.fog_density = 0.0024 + float(w["fog"])
	environment.fog_sun_scatter = 0.25 * (1.0 - overcast)
	RenderingServer.global_shader_parameter_set("season_tint", ClimateData.color(profile.get("terrain_tint")))


## 风：天气给出基础风力，叠加缓慢的阵风；风向缓慢转动。供植被摆动、雨雪漂移使用。
func _update_wind(w: Dictionary) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var gust := 0.8 + 0.2 * sin(t * 0.37) * sin(t * 0.91 + 1.3)
	wind_strength = float(w["wind"]) * gust
	var a := 0.65 + 0.25 * sin(t * 0.021)
	wind_direction = Vector2(cos(a), sin(a))
	RenderingServer.global_shader_parameter_set("wind_direction", wind_direction)


## 闪电：雷雨时每 3–12 秒一次，双闪；发出 EventBus.lightning_strike（M3 据距离延迟播放雷声）。
func _update_lightning(delta: float, w: Dictionary) -> void:
	var strength := float(w["lightning"])
	if _flash_t >= 0.0:
		_flash_t += delta
		var a := exp(-_flash_t * 9.0)
		var b := exp(-maxf(0.0, _flash_t - 0.14) * 7.0) * (0.75 if _flash_t > 0.14 else 0.0)
		flash = maxf(a, b) * strength
		if _flash_t > 0.9:
			_flash_t = -1.0
			flash = 0.0
	flash_light.light_energy = flash * 2.6
	if strength < 0.5:
		_flash_timer = _flash_rng.randf_range(2.0, 6.0)
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = _flash_rng.randf_range(3.0, 12.0)
		_flash_t = 0.0
		lightning_count += 1
		var az := _flash_rng.randf() * TAU
		flash_light.basis = Basis.looking_at(-Vector3(cos(az) * 0.5, 0.85, sin(az) * 0.5), Vector3.UP)
		EventBus.lightning_strike.emit(_flash_rng.randf_range(300.0, 3000.0))


## 太阳高度角与方位角（度）。白天从日出到日落按正弦弧线，夜间在地平线下；
## 方位从日出处转 180° 到 sun_set_azimuth_deg（本世界日落在湖对岸，见 seasons.json）。
static func sun_angles(profile: Dictionary, minutes: float) -> Vector2:
	var rise := ClimateData.parse_time(str(profile.get("sunrise", "06:00")))
	var set_t := ClimateData.parse_time(str(profile.get("sunset", "18:00")))
	var noon := float(profile.get("noon_elevation_deg", 40.0))
	var set_az := float(ClimateData.seasons().get("sun_set_azimuth_deg", 64.0))
	var day_len := set_t - rise
	var el: float
	var az: float
	if minutes >= rise and minutes <= set_t:
		var f := (minutes - rise) / day_len
		el = noon * sin(PI * f)
		az = set_az - 180.0 * (1.0 - f)
	else:
		var night_len := ClimateData.MINUTES_PER_DAY - day_len
		var since_set := fposmod(minutes - set_t, ClimateData.MINUTES_PER_DAY)
		var n := since_set / night_len
		el = -35.0 * sin(PI * n)
		az = set_az + 180.0 * n
	return Vector2(el, az)


static func _direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	var el := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func _segment(el: float) -> Vector2:
	if el <= KEYS[0]:
		return Vector2(0, 0.0)
	for i in range(KEYS.size() - 1):
		if el <= KEYS[i + 1]:
			return Vector2(i, (el - KEYS[i]) / (KEYS[i + 1] - KEYS[i]))
	return Vector2(KEYS.size() - 2, 1.0)


static func _key(table: Array, el: float) -> Color:
	var s := _segment(el)
	var i := int(s.x)
	return (table[i] as Color).lerp(table[i + 1], s.y)


static func _keyf(table: Array, el: float) -> float:
	var s := _segment(el)
	var i := int(s.x)
	return lerpf(float(table[i]), float(table[i + 1]), s.y)


func _apply_season_visuals() -> void:
	_last_season = WorldState.season_id
	get_tree().call_group("seasonal", "apply_season", WorldState.season_id)
	_reflection_cooldown = 0.0
	_last_reflection_el = 999.0


## 湖面反射探针只拍一次；太阳高度变化较大或天气过渡结束后重拍（最多每 3 秒一次）。
func _maybe_refresh_reflection(delta: float) -> void:
	_reflection_cooldown -= delta
	if _reflection_cooldown > 0.0:
		return
	var weather_done := WorldState.weather_progress >= 1.0 and WorldState.weather_id != _last_reflection_weather
	if absf(sun_elevation - _last_reflection_el) > 2.5 or weather_done:
		_last_reflection_el = sun_elevation
		if WorldState.weather_progress >= 1.0:
			_last_reflection_weather = WorldState.weather_id
		_reflection_cooldown = 3.0
		get_tree().call_group("lake_reflection", "refresh_reflection")


func _cloud_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	return tex
