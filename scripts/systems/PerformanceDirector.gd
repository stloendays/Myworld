class_name PerformanceDirector
extends Node
## 性能管理（参考主机 / PC 大作的常见做法），挂在 Main 下，运行时生效：
##   1. 画质分级（低 / 中 / 高 / 极高）：屏幕空间反射、环境光遮蔽、太阳阴影级数与距离、阴影贴图大小、
##      MSAA、网格 LOD 阈值、小型地被是否投影。设置里一键切换。
##   2. 帧率上限（默认 60）：笔记本不必跟着 165 Hz 屏幕满负荷跑，发热和风扇都小很多。
##   3. 动态分辨率：按 GPU 实际帧时调 3D 渲染比例（60%–设定值），低于 100% 时用 FSR 1.0 放大；
##      GPU 忙就降、闲了再升，保证帧率稳定（主机游戏的标准做法）。
##   4. 局部灯（炉火、灯、泳池水下灯）按距离淡出：远处的灯和它的阴影不再计算。
## 树林与岩石按 64 m 分块（ForestBuilder）、远处动物与鱼群降频更新（Animal / FishSchool）、
## 地形遮挡体（TerrainBuilder）也是这次优化的一部分，各在自己的脚本里。

const PRESETS := {
	"low": {"ssr": 0, "ssao": false, "ssao_half": true, "splits": 2, "shadow_dist": 60.0, "atlas": 2048, "msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA, "pos_atlas": 1024, "radiance": Sky.RADIANCE_SIZE_128, "lod": 4.0, "cover_shadows": false},
	"medium": {"ssr": 32, "ssao": true, "ssao_half": true, "splits": 2, "shadow_dist": 90.0, "atlas": 2048, "msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_SMAA, "pos_atlas": 2048, "radiance": Sky.RADIANCE_SIZE_128, "lod": 2.0, "cover_shadows": false},
	"high": {"ssr": 64, "ssao": true, "ssao_half": false, "splits": 4, "shadow_dist": 120.0, "atlas": 4096, "msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_SMAA, "pos_atlas": 2048, "radiance": Sky.RADIANCE_SIZE_256, "lod": 1.0, "cover_shadows": true},
	"ultra": {"ssr": 128, "ssao": true, "ssao_half": false, "splits": 4, "shadow_dist": 160.0, "atlas": 4096, "msaa": Viewport.MSAA_2X, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED, "pos_atlas": 4096, "radiance": Sky.RADIANCE_SIZE_256, "lod": 0.5, "cover_shadows": true},
}
const LIGHT_FADE_BEGIN := 40.0
const LIGHT_SHADOW_FADE := 18.0
const LIGHT_FADE_LENGTH := 10.0
const MIN_SCALE := 0.6
## 完全封闭、照不到阳光的区域：人在这里时关掉太阳阴影（太阳阴影要把地面上整片树林画进阴影贴图）
const UNDERGROUND_ZONES := [&"aquarium"]

var dynamic_scale := 1.0
var gpu_ms := 0.0
var applied_quality := ""

var _adjust_timer := 0.0
var _gpu_samples: Array[float] = []


func _ready() -> void:
	add_to_group("performance_director")
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	GameSettings.changed.connect(apply_quality)
	# 后来才加入场景的灯（仙境、换装预览等）在加入时就设好淡出，不必定时全树搜索
	get_tree().node_added.connect(_on_node_added)
	apply_quality.call_deferred()


## 按设置里的画质档位改渲染参数。重复调用无害（只在档位或场景变化时才真正改）。
func apply_quality() -> void:
	var q := String(GameSettings.graphics_quality)
	var p: Dictionary = PRESETS.get(q, PRESETS["high"])
	# A Windows machine can fall back from Vulkan to Compatibility/OpenGL.
	# SSR is unavailable outside Forward+; keep recovery mode lightweight.
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	if env != null and env.environment != null:
		var e := env.environment
		e.ssr_enabled = forward_plus and int(p["ssr"]) > 0
		e.ssr_max_steps = maxi(int(p["ssr"]), 8)
		e.ssao_enabled = forward_plus and bool(p["ssao"])
		if forward_plus:
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, p["ssao_half"], 0.5, 2, 50.0, 300.0)
		env.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p["splits"]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		env.sun.directional_shadow_max_distance = p["shadow_dist"]
		env.moon.directional_shadow_max_distance = minf(float(p["shadow_dist"]), 120.0)
		if e.sky != null and e.sky.radiance_size != p["radiance"]:
			e.sky.radiance_size = p["radiance"]
	RenderingServer.directional_shadow_atlas_set_size(int(p["atlas"]), true)
	get_viewport().msaa_3d = p["msaa"]
	get_viewport().screen_space_aa = p["ssaa"]
	get_viewport().positional_shadow_atlas_size = p["pos_atlas"]
	get_viewport().mesh_lod_threshold = p["lod"]
	var cover := get_tree().get_first_node_in_group("ground_cover")
	if cover != null:
		for mmi: MultiMeshInstance3D in cover.find_children("*", "MultiMeshInstance3D", true, false):
			if mmi.visibility_range_end >= 100.0:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if p["cover_shadows"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	applied_quality = q
	_apply_scale()
	fade_lights()


## 所有局部灯按距离淡出。启动时扫一遍全树，之后新加入的灯由 node_added 逐个处理。
func fade_lights() -> void:
	for l in get_tree().root.find_children("*", "OmniLight3D", true, false) + get_tree().root.find_children("*", "SpotLight3D", true, false):
		_fade(l as Light3D)


func _on_node_added(n: Node) -> void:
	if n is OmniLight3D or n is SpotLight3D:
		_fade(n as Light3D)


func _fade(light: Light3D) -> void:
	if light.distance_fade_enabled:
		return
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE_BEGIN
	light.distance_fade_shadow = LIGHT_SHADOW_FADE
	light.distance_fade_length = LIGHT_FADE_LENGTH


func _process(delta: float) -> void:
	_update_underground()
	if not GameSettings.dynamic_resolution or DisplayServer.get_name() == "headless":
		if dynamic_scale != 1.0:
			dynamic_scale = 1.0
			_apply_scale()
		return
	var g := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if g > 0.0:
		_gpu_samples.append(g)
	_adjust_timer -= delta
	if _adjust_timer > 0.0 or _gpu_samples.size() < 10:
		return
	_adjust_timer = 0.5
	_gpu_samples.sort()
	gpu_ms = _gpu_samples[int(_gpu_samples.size() * 0.75)]   # 取 75 分位，少受偶发尖峰影响
	_gpu_samples.clear()
	update_dynamic_scale(gpu_ms)


## 动态分辨率的一步：GPU 帧时超过预算 90% 降 5%，低于 60% 升 5%。返回新的比例（测试也调用它）。
func update_dynamic_scale(measured_gpu_ms: float) -> float:
	var target_fps := GameSettings.max_fps if GameSettings.max_fps > 0 else 60
	var budget := 1000.0 / float(target_fps)
	if measured_gpu_ms > budget * 0.9:
		dynamic_scale = maxf(MIN_SCALE / maxf(GameSettings.render_scale, 0.01), dynamic_scale - 0.05)
	elif measured_gpu_ms < budget * 0.6:
		dynamic_scale = minf(1.0, dynamic_scale + 0.05)
	_apply_scale()
	return dynamic_scale


func effective_scale() -> float:
	return clampf(GameSettings.render_scale * dynamic_scale, MIN_SCALE, 1.0)


func _apply_scale() -> void:
	var s := effective_scale()
	var vp := get_viewport()
	vp.scaling_3d_scale = s
	# FSR 1.0 is Forward+-only; Compatibility/Mobile use bilinear.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.99 and RenderingServer.get_current_rendering_method() == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR


func _update_underground() -> void:
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if env == null or player == null:
		return
	var underground := false
	for z in WorldState.zones_of(player.entity_id):
		if z in UNDERGROUND_ZONES:
			underground = true
	env.sun_shadows_allowed = not underground
