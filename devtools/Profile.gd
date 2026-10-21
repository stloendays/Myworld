extends Node
## 开发工具：性能剖析。在几个最慢的机位上逐项关掉一个渲染特性，测帧时变化，找出真正花时间的地方。
##   Godot_console.exe --path . --resolution 1920x1080 res://devtools/Profile.tscn
## 结果打印为 PROFILE 行。垂直同步强制关闭；每项先等 40 帧稳定再测 2.5 秒。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const SPOTS := [
	{"name": "北部林道", "eye": [-80, 1.65, -50], "look": [-78, 2, -28]},
	{"name": "码头望木屋", "eye": [-8, 2.65, 25], "look": [-69, 4, 37], "abs": true},
	{"name": "地下水族馆", "eye": [13, -3.3, 85], "look": [1, -3.6, 83.5], "abs": true},
]
const CONFIGS := ["基线", "停动物", "停小地图", "停环境导演", "停降水", "停鱼群", "停探索与木屋生活", "停性能导演", "停玩家"]

var _main: Node
var _env: EnvironmentDirector
var _cam: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	player.set_physics_process(false)
	WorldState.time_paused = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 测渲染能力：不限帧率、不用动态分辨率
	GameSettings.set_value("max_fps", 0, false)
	GameSettings.set_value("dynamic_resolution", false, false)
	Engine.max_fps = 0
	_env = _main.get_node("World/Environment") as EnvironmentDirector
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
	_cam.fov = 75.0
	_cam.far = 1500.0
	add_child(_cam)
	_cam.current = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _frames(150)
	for spot in SPOTS:
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else WorldTerrain.height_at(float(e[0]), float(e[2])))
		_cam.global_position = Vector3(float(e[0]), y, float(e[2]))
		_cam.look_at(Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2])), Vector3.UP)
		player.global_position = _cam.global_position - Vector3(0.0, 1.65, 0.0)
		var base := 0.0
		for c in CONFIGS:
			_apply(c, true)
			await _frames(40)
			var ms := await _measure(2.5)
			if c == "基线":
				base = ms
			var vp := get_viewport().get_viewport_rid()
			print("PROFILE %s | %s | %.2f ms | %+.2f ms | CPU 渲染 %.2f ms | GPU %.2f ms | 脚本 %.2f ms | 物理 %.2f ms | 绘制 %d | 图元 %d" % [spot["name"], c, ms, ms - base,
				RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(vp),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			_apply(c, false)
	get_tree().quit()


func _apply(c: String, on: bool) -> void:
	var env := _env.environment
	match c:
		"关 SSR":
			env.ssr_enabled = not on
		"关 SSAO":
			env.ssao_enabled = not on
		"关辉光":
			env.glow_enabled = not on
		"太阳阴影 2 级 / 80 m":
			_env.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if on else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_env.sun.directional_shadow_max_distance = 80.0 if on else 160.0
		"停动物":
			_pause(_main.get_node("World/Fauna"), on)
		"停小地图":
			_pause(_main.get_node("Minimap"), on)
		"停环境导演":
			_pause(_main.get_node("World/Environment"), on)
		"停降水":
			_pause(_main.get_node("World/Precipitation"), on)
		"停鱼群":
			for s in get_tree().get_nodes_in_group("aquatic_life"):
				_pause(s, on)
		"停探索与木屋生活":
			_pause(_main.get_node("World/Exploration"), on)
			_pause(_main.get_node("Cabin/Generated/Life"), on)
		"停性能导演":
			_pause(_main.get_node("Performance"), on)
		"停玩家":
			_pause(get_tree().get_first_node_in_group("local_player"), on)
		"关地被（隐藏）":
			(_main.get_node("World/GroundCover") as Node3D).visible = not on
		"关地被投影":
			for mmi: MultiMeshInstance3D in _main.get_node("World/GroundCover").find_children("*", "MultiMeshInstance3D", true, false):
				if on:
					mmi.set_meta("cs", mmi.cast_shadow)
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				else:
					mmi.cast_shadow = mmi.get_meta("cs")
		"关树木投影":
			for mmi: MultiMeshInstance3D in _main.get_node("World/Forest").find_children("*", "MultiMeshInstance3D", true, false):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"关 MSAA":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED if on else Viewport.MSAA_2X
		"渲染 75%":
			get_viewport().scaling_3d_scale = 0.75 if on else 1.0
		"关所有局部灯":
			for l in _main.find_children("*", "OmniLight3D", true, false) + _main.find_children("*", "SpotLight3D", true, false):
				(l as Light3D).visible = not on if on else (l as Light3D).get_meta("v", true)


func _measure(seconds: float) -> float:
	var start := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - start < int(seconds * 1_000_000):
		await get_tree().process_frame
		frames += 1
	return (Time.get_ticks_usec() - start) / 1000.0 / frames


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _pause(n: Node, on: bool) -> void:
	n.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
