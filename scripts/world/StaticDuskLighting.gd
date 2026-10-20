@tool
class_name StaticDuskLighting
extends Node3D
## M1 的固定暮色光照（预设 Autumn_Dusk_Clear：秋季 17:20、晴）。
## 这是占位：M2 的 WorldClock + SeasonController + WeatherController + EnvironmentDirector
## 接管后，本节点被 EnvironmentDirector 取代。太阳方位见 world_layout.json → lighting_m1。

const GENERATED := "Generated"

var environment: Environment = null
var sun: DirectionalLight3D = null


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)
	var cfg := WorldLayout.section("lighting_m1")

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.23, 0.58)
	sky_mat.sky_horizon_color = Color(0.93, 0.56, 0.66)
	sky_mat.sky_curve = 0.13
	sky_mat.ground_horizon_color = Color(0.50, 0.36, 0.52)
	sky_mat.ground_bottom_color = Color(0.10, 0.09, 0.18)
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.04
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.56, 0.46, 0.66)
	environment.fog_density = 0.0032
	environment.fog_sky_affect = 0.2
	environment.fog_aerial_perspective = 0.35
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.63, 0.47)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0
	var el := deg_to_rad(float(cfg.get("sun_elevation_deg", 10.0)))
	var az := deg_to_rad(float(cfg.get("sun_azimuth_deg", 64.0)))
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	root.add_child(sun)
