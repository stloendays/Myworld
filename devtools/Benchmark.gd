extends Node
## 开发工具：在固定机位各停 4 秒，记录平均帧率、帧时、绘制调用与显存，结果打印并写入 user://benchmark.json。
##   Godot_console.exe --path . --resolution 1920x1080 res://devtools/Benchmark.tscn
## 只是给出当前机器上的实测数，不代表性能目标已达成（QA-09 属于 M4）。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const SPOTS := [
	{"name": "湖岸出生点", "eye": [-50, 1.65, 29], "look": [35, 2, -2]},
	{"name": "码头望木屋", "eye": [-8, 2.65, 25], "look": [-69, 4, 37], "abs": true},
	{"name": "木屋室内", "eye": [-72.2, 4.05, 37.6], "look": [-60, 4.0, 36.5], "abs": true},
	{"name": "北部林道", "eye": [-80, 1.65, -50], "look": [-78, 2, -28]},
	{"name": "秋夜大雨·木屋外", "eye": [-53, 1.65, 40], "look": [-66, 4.0, 37], "preset": "Autumn_Night_HeavyRain"},
	{"name": "冬日下雪·湖岸", "eye": [-50, 1.65, 29], "look": [35, 2, -2], "preset": "Winter_Morning_Snow"},
	{"name": "泳池馆大厅·秋日暮色", "eye": [-0.5, 3.7, 77.8], "look": [14, 1.5, 85.5], "abs": true, "preset": "Autumn_Dusk_Clear"},
	{"name": "地下水族馆", "eye": [13, -3.3, 85], "look": [1, -3.6, 83.5], "abs": true},
	{"name": "夏夜雷雨·湖岸", "eye": [-50, 1.65, 29], "look": [35, 8, -2], "preset": "Summer_Night_Thunderstorm"},
	{"name": "仙境林地·夏夜", "eye": [62, 1.7, 86.5], "look": [82, 9.0, 86], "night": true},
	{"name": "雪山顶·望湖", "eye": [100.5, 1.7, -105.0], "look": [35, 4.0, -2], "preset": "Autumn_Dusk_Clear"},
	{"name": "码头望雪山", "eye": [-2, 2.65, 26], "look": [96, 26.0, -104], "abs": true, "preset": "Autumn_Dusk_Clear"},
	{"name": "山洞口", "eye": [-5.5, 1.7, -80.5], "look": [-7.5, 4.0, -96]},
	{"name": "图腾石厅", "eye": [-0.5, 3.9, -100.6], "look": [8.0, 3.2, -103.0], "abs": true},
	{"name": "石头小屋", "eye": [-83, 1.7, 91], "look": [-70, 3.0, 96]},
	{"name": "石头小屋室内", "eye": [-71.7, 4.05, 95.0], "look": [-68.1, 3.0, 97.6], "abs": true},
	{"name": "西岭小瀑布", "eye": [-93.2, 1.25, 2.2], "look": [-99.6, 4.4, 2.8]},
	{"name": "北岭裂谷", "eye": [-79.0, 1.7, -92.0], "look": [-90.0, 11.0, -89.2]},
	{"name": "沙之门", "eye": [-84.0, 1.7, 89.0], "look": [-94.0, 3.0, 86.0]},
	# 暮烬之夜（湖面暮烬 + 原版红点）与同一机位不开暮烬的对照
	{"name": "码头望湖·秋日暮色", "eye": [-2, 2.65, 26], "look": [35, 3, -2], "abs": true, "preset": "Autumn_Dusk_Clear"},
	{"name": "暮烬之夜·码头望湖", "eye": [-2, 2.65, 26], "look": [35, 3, -2], "abs": true, "preset": "Autumn_Dusk_Clear", "embers": true},
]
## v0.5 的两个新世界和亚特兰蒂斯（world：那个世界的 id；eye.y 为离地高度，abs 时为绝对高度）
const WORLD_SPOTS := [
	{"name": "云海浮岛·主岛", "world": "world_02", "eye": [0.0, 1.65, 13.5], "look": [-9.0, 4.0, -7.0]},
	{"name": "云海浮岛·全景", "world": "world_02", "eye": [46.0, 26.0, 52.0], "look": [-4.0, -2.0, -26.0], "abs": true},
	{"name": "云海浮岛·跳台望灯塔", "world": "world_02", "eye": [2.0, 10.5, -64.0], "look": [10.0, 13.0, -96.0], "abs": true},
	{"name": "琥珀沙丘·光门", "world": "world_03", "eye": [0.0, 1.65, 70.5], "look": [10.0, 3.0, 20.0]},
	{"name": "琥珀沙丘·绿洲", "world": "world_03", "eye": [3.0, 1.65, 33.0], "look": [27.0, 1.0, 22.0]},
	{"name": "琥珀沙丘·全景", "world": "world_03", "eye": [55.0, 34.0, 95.0], "look": [-5.0, 2.0, 0.0], "abs": true},
	{"name": "亚特兰蒂斯·穹顶全景", "world": "world_04", "eye": [38.0, 26.0, 36.0], "look": [-4.0, 0.0, -6.0], "abs": true},
	{"name": "亚特兰蒂斯·神殿前", "world": "world_04", "eye": [5.0, 1.65, 19.5], "look": [0.0, 4.0, -4.0]},
	{"name": "亚特兰蒂斯·穹顶外海底", "world": "world_04", "eye": [16.0, 7.0, 98.0], "look": [0.0, 16.0, 30.0], "abs": true},
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	player.set_physics_process(false)
	WorldState.time_paused = true
	# 测的是渲染能力，不受显示器刷新率封顶（否则 165 Hz 屏幕上帧率会卡在 165）
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 测渲染能力：不限帧率、不用动态分辨率
	GameSettings.set_value("max_fps", 0, false)
	GameSettings.set_value("dynamic_resolution", false, false)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.get_environment("DUSK_BENCH_NO_MINIMAP") != "":
		GameSettings.set_value("minimap_enabled", false, false)
	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
	cam.fov = 75.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	await _frames(120)
	var results := []
	# -- worlds：只测湖岸出生点（对照）和两个新世界
	var only_worlds := OS.get_cmdline_user_args().has("worlds")
	# DUSK_BENCH_ONLY=机位1,机位2：只测这几个湖畔机位（看某个机位单独测时多快）
	var only := OS.get_environment("DUSK_BENCH_ONLY").split(",", false)
	for spot in SPOTS:
		if only_worlds and str(spot["name"]) != "湖岸出生点":
			continue
		if not only.is_empty() and not str(spot["name"]) in only:
			continue
		if spot.has("preset"):
			(main.get_node("Systems") as ClimateSystem).apply_preset(str(spot["preset"]))
		if spot.get("night", false):
			var sys := main.get_node("Systems") as ClimateSystem
			sys.jump_to_season(&"SUMMER")
			sys.set_weather(&"CLEAR", 0.0)
			sys.set_hour(22.0)
			await _frames(60)
			var glade := get_tree().get_first_node_in_group("fairy_glade") as FairyGlade
			if glade != null:
				glade._apply(true, true)
		var story := main.get_node("StoryDirector") as StoryDirector
		story.set_process(false)    # 暮烬由机位决定，不按剧情标记自己开关
		story._set_embers(spot.get("embers", false), true)
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else WorldTerrain.height_at(float(e[0]), float(e[2])))
		cam.global_position = Vector3(float(e[0]), y, float(e[2]))
		cam.look_at(Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2])), Vector3.UP)
		# 玩家也站到机位上（所在区域会影响渲染，例如在地下时不算太阳阴影）
		player.global_position = cam.global_position - Vector3(0.0, 1.65, 0.0)
		await _frames(30)
		var start := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - start < 4_000_000:
			await get_tree().process_frame
			frames += 1
		var seconds := (Time.get_ticks_usec() - start) / 1_000_000.0
		var r := {
			"spot": spot["name"],
			"fps": snappedf(frames / seconds, 0.1),
			"frame_ms": snappedf(1000.0 * seconds / frames, 0.01),
			"gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), 0.01),
			"cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu(), 0.01),
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"vram_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		}
		print("BENCH ", JSON.stringify(r))
		results.append(r)
	if only.is_empty():
		results.append_array(await _bench_worlds(main, cam))
	var f := FileAccess.open("user://benchmark.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(), "resolution": str(get_viewport().get_visible_rect().size), "results": results}, "  "))
	get_tree().quit()


## 换到云海浮岛、琥珀沙丘各测几个机位（世界直接加在本节点下，和湖畔不同时存在）。
func _bench_worlds(main: Node, cam: Camera3D) -> Array:
	var out := []
	main.queue_free()
	await _frames(5)
	var world: MiniWorld = null
	var world_id := ""
	for spot: Dictionary in WORLD_SPOTS:
		if str(spot["world"]) != world_id:
			if world != null:
				world.queue_free()
				await _frames(5)
			world_id = str(spot["world"])
			world = (load(str(WorldRegistry.get_world(world_id)["scene"])) as PackedScene).instantiate() as MiniWorld
			add_child(world)
			await _frames(90)
			world.player.set_physics_process(false)
			cam.current = true
			# 新世界的界面节点会按玩家设置重新套一遍显示设置：再关一次垂直同步，否则帧率卡在屏幕刷新率
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else world.height_at(float(e[0]), float(e[2])))
		cam.global_position = Vector3(float(e[0]), y, float(e[2]))
		cam.look_at(Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2])), Vector3.UP)
		await _frames(30)
		var start := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - start < 4_000_000:
			await get_tree().process_frame
			frames += 1
		var seconds := (Time.get_ticks_usec() - start) / 1_000_000.0
		var r := {
			"spot": spot["name"],
			"fps": snappedf(frames / seconds, 0.1),
			"frame_ms": snappedf(1000.0 * seconds / frames, 0.01),
			"gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), 0.01),
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"vram_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		}
		print("BENCH ", JSON.stringify(r))
		out.append(r)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame