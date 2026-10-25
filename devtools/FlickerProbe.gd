extends Node
## 开发工具：找画面闪动。每个机位相机不动，世界时间照常走（太阳、风、水面都在动），按固定 30 fps 连续存 60 帧 PNG，
## 交给 devtools/flicker_report.py 逐像素找“突然变了一下又变回去”的点，画成热力图（区分正常的缓慢运动和闪烁）。
##   Godot_console.exe --path . --resolution 1280x720 --position 100000,100000 --fixed-fps 30 res://devtools/FlickerProbe.tscn -- [out=目录] [前缀] [move]
## move：相机每帧沿视线横向平移 3 cm（走路时的闪动：远处植被淡出、Z 冲突、阴影抖动）。
## jiggle：相机左右来回转 1/3 像素（画面内容不变）：前后两帧差得越多，锯齿闪烁越重（flicker_report.py --jiggle 统计）。
## smaa / taa：对比用的抗锯齿方案（单帧 SMAA / Godot 自带 TAA）。
## 画质按玩家默认（高），只关动态分辨率和帧率上限（动态分辨率另有自动检查）。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const FRAMES := 60
const SPOTS := [
	{"name": "f01_shore", "climate": {"preset": "Autumn_Dusk_Clear"}, "eye": [-40, 2.6, 18], "look": [10, 0.5, 0]},
	{"name": "f02_dock_cabin", "climate": {"preset": "Autumn_Dusk_Clear"}, "eye": [-8, 2.65, 25], "look": [-69, 4, 37]},
	{"name": "f03_cabin_rugs", "climate": {"preset": "Autumn_Dusk_Clear"}, "eye": [-72.2, 4.6, 37.6], "look": [-63, 2.4, 37.5]},
	{"name": "f04_forest", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-80, 3.6, -50], "look": [-78, 2.5, -20]},
	{"name": "f05_far_shore", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-2, 2.65, 26], "look": [80, 1.0, -30]},
	{"name": "f06_cave_mouth", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-5.5, 3.9, -80.5], "look": [-7.5, 4.0, -96]},
	{"name": "f07_meadow", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-84, 3.8, 82], "look": [-70, 2.5, 100]},
	{"name": "f08_poolhouse", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-20, 3.8, 66], "look": [4, 2.0, 84]},
	{"name": "fb1_creek_bridge", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-77.5, 3.2, -8.5], "look": [-84.0, 2.6, -1.5]},
	{"name": "fb2_gorge_bridge", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-83.5, 15.5, -93.5], "look": [-89.8, 11.5, -89.0]},
]

var _camera: Camera3D
var _main: Node
var _out := "res://flicker_out"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefix := ""
	var move := false
	var jiggle := false
	var smaa := false
	var taa := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a == "move":
			move = true
		elif a == "jiggle":
			jiggle = true
		elif a == "smaa":
			smaa = true
		elif a == "taa":
			taa = true
		else:
			prefix = a
	GameSettings.set_value("fullscreen", false, false)
	GameSettings.set_value("dynamic_resolution", false, false)
	GameSettings.set_value("max_fps", 0, false)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	for layer_name in ["HUD", "DebugOverlay", "Minimap"]:
		(_main.get_node(layer_name) as CanvasLayer).visible = false
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	player.set_physics_process(false)
	player.global_position.y -= 300.0
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 1500.0
	_camera.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
	add_child(_camera)
	_camera.current = true
	await _wait(120)
	if smaa:
		var perf := _main.get_node("Performance") as PerformanceDirector
		perf.temporal = false
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		perf._apply_scale()
	if taa:
		get_viewport().use_taa = true
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var chat := _main.get_node_or_null("ChatBox") as CanvasLayer
	if chat != null:
		chat.visible = false
	for spot: Dictionary in SPOTS:
		if not str(spot["name"]).begins_with(prefix):
			continue
		var climate := _main.get_node("Systems") as ClimateSystem
		var c: Dictionary = spot["climate"]
		if c.has("preset"):
			climate.apply_preset(str(c["preset"]))
		else:
			climate.jump_to_season(StringName(c["season"]))
			climate.set_hour(float(c["hour"]))
			climate.set_weather(StringName(c["weather"]), 0.0)
		WorldState.time_paused = false
		var eye := Vector3(float(spot["eye"][0]), float(spot["eye"][1]), float(spot["eye"][2]))
		var look := Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2]))
		_camera.global_position = eye
		_camera.look_at(look, Vector3.UP)
		await _wait(90)
		var dir := "%s/%s%s" % [_out, spot["name"], "_move" if move else ("_jiggle" if jiggle else "")]
		DirAccess.make_dir_recursive_absolute(dir)
		var side := _camera.global_basis.x
		for i in FRAMES:
			if move:
				_camera.global_position = eye + side * 0.03 * i
			elif jiggle:
				_camera.look_at(look, Vector3.UP)
				_camera.rotate_y(0.0004 if i % 2 == 0 else -0.0004)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [dir, i])
		print("FLICKER spot ", spot["name"])
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
