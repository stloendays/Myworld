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
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	player.set_physics_process(false)
	WorldState.time_paused = true
	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER
	cam.fov = 75.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	await _frames(120)
	var results := []
	for spot in SPOTS:
		if spot.has("preset"):
			(main.get_node("Systems") as ClimateSystem).apply_preset(str(spot["preset"]))
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else WorldTerrain.height_at(float(e[0]), float(e[2])))
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
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"vram_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		}
		print("BENCH ", JSON.stringify(r))
		results.append(r)
	var f := FileAccess.open("user://benchmark.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(), "resolution": str(get_viewport().get_visible_rect().size), "results": results}, "  "))
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame