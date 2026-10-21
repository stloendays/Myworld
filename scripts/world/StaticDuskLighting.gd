@tool
class_name StaticDuskLighting
extends Node3D
## M1 的固定暮色光照（预设 Autumn_Dusk_Clear：秋季 17:20、晴）。
## 这是占位：M2 的 WorldClock + SeasonController + WeatherController + EnvironmentDirector
## 接管后，本节点被 EnvironmentDirector 取代。太阳方位见 world_layout.json → lighting_m1。

const GENERATED := "Generated"
const SKY_SHADER := preload("res://shaders/sky.gdshader")

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

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", _cloud_noise())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.85
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.05
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
	environment.fog_light_color = Color(0.56, 0.46, 0.66)
	environment.fog_density = 0.0028
	environment.fog_sky_affect = 0.15
	environment.fog_sun_scatter = 0.25
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
