extends Node
## 开发工具：在真实渲染窗口中按预设机位截图，输出到 docs/screenshots/。
##   Godot_console.exe --path . --resolution 1600x900 res://devtools/CaptureShots.tscn
## 机位 eye/look 为世界坐标；"ground": true 表示 eye.y 为离地高度。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const OUT_DIR := "res://docs/screenshots"

const SHOTS := [
	{"name": "m1_01_spawn_dusk", "eye": [-50, 1.65, 29], "ground": true, "look": [35, 2, -2]},
	{"name": "m1_02_lake_to_cabin", "eye": [-8, 1.0 + 1.65, 25], "look": [-69, 4, 37]},
	{"name": "m1_03_cabin_front", "eye": [-53, 1.65, 40], "ground": true, "look": [-66, 4.0, 37]},
	{"name": "m1_04_cabin_interior", "eye": [-72.2, 2.4 + 1.65, 37.6], "look": [-60, 4.0, 36.5]},
	{"name": "m1_05_interior_stove", "eye": [-65.6, 2.4 + 1.65, 38.2], "look": [-73, 3.0, 35.8]},
	{"name": "m1_06_north_trail", "eye": [-80, 1.65, -50], "ground": true, "look": [-78, 2, -28]},
	{"name": "m1_07_viewpoint", "eye": [-93, 1.8, -101], "ground": true, "look": [20, -5, 10]},
	{"name": "m1_08_aerial", "eye": [-40, 190, 175], "look": [-10, 0, 0]},
	{"name": "m1_09_lake_reflection", "eye": [-3, 1.0 + 1.65, 25], "look": [70, 2, -30]},
]

var _camera: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	for layer_name in ["HUD", "DebugOverlay"]:
		(main.get_node(layer_name) as CanvasLayer).visible = false
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	player.set_physics_process(false)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 1500.0
	add_child(_camera)
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _wait(120)
	for shot in SHOTS:
		var e := WorldLayout.v2([shot["eye"][0], shot["eye"][2]])
		var y := float(shot["eye"][1])
		if shot.get("ground", false):
			y += WorldTerrain.height_at(e.x, e.y)
		_camera.global_position = Vector3(e.x, y, e.y)
		_camera.look_at(Vector3(float(shot["look"][0]), float(shot["look"][1]), float(shot["look"][2])), Vector3.UP)
		await _wait(20)
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot["name"]])
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
