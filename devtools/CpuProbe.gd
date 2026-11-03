extends Node
## 开发工具：主线程 CPU 探针（不看渲染，只看脚本和物理）。无窗口运行，渲染是空的，帧时 ≈ 脚本 + 物理：
##   Godot_console.exe --headless --path . res://devtools/CpuProbe.tscn
## 每个机位上把一类东西停掉 / 恢复，交替 4 轮（A-B-A-B，每段 1.2 秒），打印这类东西每帧占的 _process 与 _physics_process 时间。
## 结果打印为 CPU 行；最后一行是整个世界每帧的脚本 + 物理合计。DUSK_CPU_ONLY=项1,项2 只测这几项。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const SPOTS := [
	{"name": "湖岸出生点", "eye": [-50, 1.65, 29], "look": [35, 0, -2]},
	{"name": "北部林道", "eye": [-80, 1.65, -50], "look": [-78, 2, -28]},
	{"name": "地下水族馆", "eye": [13, -3.3, 85], "look": [1, -3.6, 83.5], "abs": true},
]
const ITEMS := ["动物", "鱼群", "卷轴", "地被", "声音", "降水", "环境导演", "界面", "探索与木屋", "剧情", "远程玩家", "性能导演"]
const ROUNDS := 4
const SEGMENT := 1.2

var _main: Node
var _cam: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	player.set_physics_process(false)
	WorldState.time_paused = true
	Engine.max_fps = 0
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	_cam.current = true
	await _frames(120)
	_census()
	var items: Array = ITEMS
	var only := OS.get_environment("DUSK_CPU_ONLY")
	if only != "":
		items = Array(only.split(","))
	for spot in SPOTS:
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else WorldTerrain.height_at(float(e[0]), float(e[2])))
		_cam.global_position = Vector3(float(e[0]), y, float(e[2]))
		_cam.look_at(Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2])), Vector3.UP)
		player.global_position = _cam.global_position - Vector3(0.0, 1.65, 0.0)
		await _frames(60)
		var total := await _measure(SEGMENT * 2.0)
		print("CPU %s | 全部 | 脚本 %.3f ms | 物理 %.3f ms | 合计 %.3f ms" % [spot["name"], total.x, total.y, total.x + total.y])
		for item in items:
			var on := Vector2.ZERO
			var off := Vector2.ZERO
			for r in ROUNDS:
				_apply(item, false)
				await _frames(10)
				on += await _measure(SEGMENT)
				_apply(item, true)
				await _frames(10)
				off += await _measure(SEGMENT)
			_apply(item, false)
			var d := (on - off) / ROUNDS
			print("CPU %s | %s | 脚本 %+.3f ms | 物理 %+.3f ms | 合计 %+.3f ms" % [spot["name"], item, d.x, d.y, d.x + d.y])
	get_tree().quit()


## 平均每帧的 _process 时间（x）和每个物理步的时间（y），毫秒。
func _measure(seconds: float) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		sum += Vector2(Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		n += 1
	return sum / maxi(n, 1)


func _apply(item: String, paused: bool) -> void:
	match item:
		"动物":
			_pause(_main.get_node("World/Fauna"), paused)
		"鱼群":
			for s in get_tree().get_nodes_in_group("aquatic_life"):
				_pause(s, paused)
		"卷轴":
			for s in get_tree().get_nodes_in_group("sign_boards"):
				_pause(s, paused)
		"地被":
			_pause(_main.get_node("World/GroundCover"), paused)
		"声音":
			_pause(get_node("/root/Sound"), paused)
		"降水":
			_pause(_main.get_node("World/Precipitation"), paused)
		"环境导演":
			_pause(_main.get_node("World/Environment"), paused)
		"界面":
			for k in _main.get_children():
				if k is CanvasLayer:
					_pause(k, paused)
		"探索与木屋":
			_pause(_main.get_node("World/Exploration"), paused)
			_pause(_main.get_node("Cabin/Generated/Life"), paused)
		"剧情":
			_pause(get_tree().get_first_node_in_group("story_director"), paused)
		"远程玩家":
			_pause(get_tree().get_first_node_in_group("remote_players"), paused)
		"性能导演":
			_pause(_main.get_node("Performance"), paused)
		"物理引擎":
			PhysicsServer3D.set_active(not paused)


## 物理世界里有多少东西：各类物体、碰撞形状、每个物理步都要跑 _physics_process 的脚本（按脚本数）。
func _census() -> void:
	var kinds := {}
	var shapes := 0
	var monitoring := 0
	var scripts := {}
	for n in get_tree().root.find_children("*", "Node", true, false):
		if n is CollisionObject3D:
			kinds[n.get_class()] = int(kinds.get(n.get_class(), 0)) + 1
			if n is Area3D and ((n as Area3D).monitoring or (n as Area3D).monitorable):
				monitoring += 1
		if n is CollisionShape3D:
			shapes += 1
		if n.is_physics_processing() and n.get_script() != null:
			var s := (n.get_script() as Script).resource_path.get_file()
			scripts[s] = int(scripts.get(s, 0)) + 1
	print("PHYS 物体 %s · 碰撞形状 %d · 监视中的区域 %d" % [kinds, shapes, monitoring])
	print("PHYS 每个物理步跑脚本的节点 %s" % scripts)


func _pause(n: Node, paused: bool) -> void:
	if n != null:
		n.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
