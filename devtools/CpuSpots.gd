extends Node
## 开发工具：真实玩法下的 CPU 占用。玩家（物理照常开着）依次站到几个机位，按玩家自己的设置跑（默认 60 帧上限），
## 每个机位先等 4 秒稳定，再打印开始、结束时刻；外面的 devtools/cpu_usage.ps1 每 0.5 秒读一次进程 CPU 时间，按这些时刻算占用。
##   pwsh -File devtools/cpu_usage.ps1 [-Label 改前]
## 打印：CPUSPOT 开始|结束 机位名 Unix 毫秒。DUSK_CPU_SECONDS 改每个机位测多久（默认 12 秒）。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const SPOTS := [
	{"name": "湖岸出生点", "eye": [-50, 0.0, 29], "look": [35, 2, -2]},
	{"name": "码头望木屋", "eye": [-8, 1.0, 25], "look": [-69, 4, 37], "abs": true},
	{"name": "木屋室内", "eye": [-72.2, 2.4, 37.6], "look": [-60, 4.0, 36.5], "abs": true},
	{"name": "北部林道", "eye": [-80, 0.0, -50], "look": [-78, 2, -28]},
	{"name": "地下水族馆", "eye": [13, -4.95, 85], "look": [1, -3.6, 83.5], "abs": true},
	{"name": "石头小屋室内", "eye": [-71.7, 2.4, 95.0], "look": [-68.1, 3.0, 97.6], "abs": true},
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	WorldState.time_paused = true
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	if climate != null:
		climate.apply_preset("Autumn_Dusk_Clear")
	var seconds := float(OS.get_environment("DUSK_CPU_SECONDS")) if OS.get_environment("DUSK_CPU_SECONDS") != "" else 12.0
	await get_tree().create_timer(3.0).timeout
	print("CPUSPOT 帧率上限 %d" % Engine.max_fps)
	_switch_off(main, OS.get_environment("DUSK_CPU_OFF"))
	# DUSK_CPU_SET=键:值,键:值 临时改设置（不存盘），例如 graphics_quality:low、vsync:false、render_scale:0.5
	for kv in OS.get_environment("DUSK_CPU_SET").split(",", false):
		var key := kv.get_slice(":", 0)
		var raw := kv.get_slice(":", 1)
		var v: Variant = raw
		if raw in ["true", "false"]:
			v = raw == "true"
		elif raw.is_valid_float():
			v = float(raw) if "." in raw else int(raw)
		GameSettings.set_value(key, v, false)
		print("CPUSPOT 设置 %s = %s" % [key, v])
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var only := OS.get_environment("DUSK_CPU_SPOTS")
	for spot in SPOTS:
		if only != "" and not str(spot["name"]) in only.split(","):
			continue
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else WorldTerrain.height_at(float(e[0]), float(e[2])) + 0.1)
		var at := Vector3(float(e[0]), y, float(e[2]))
		var look := Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2]))
		var d := look - at
		player.teleport_to(at, -rad_to_deg(atan2(-d.x, -d.z)))
		await get_tree().create_timer(4.0).timeout
		print("CPUSPOT 开始 %s %d" % [spot["name"], int(Time.get_unix_time_from_system() * 1000.0)])
		await get_tree().create_timer(seconds).timeout
		print("CPUSPOT 结束 %s %d" % [spot["name"], int(Time.get_unix_time_from_system() * 1000.0)])
	get_tree().quit()


## 找 CPU 花在哪：DUSK_CPU_OFF=项1,项2 关掉这几类再测（动物 / 鱼 / 地被 / 树林 / 卷轴 / 声音 / 物理 / 三维 / 界面）。
func _switch_off(main: Node, what: String) -> void:
	for w in what.split(",", false):
		print("CPUSPOT 关掉 %s" % w)
		match w:
			"动物":
				_off(main.get_node("World/Fauna"))
			"鱼":
				for s in get_tree().get_nodes_in_group("aquatic_life"):
					_off(s)
			"地被":
				_off(main.get_node("World/GroundCover"))
			"树林":
				_off(main.get_node("World/Forest"))
			"卷轴":
				for s in get_tree().get_nodes_in_group("sign_boards"):
					_off(s)
			"声音":
				_off(get_node("/root/Sound"))
				AudioServer.set_bus_mute(0, true)
			"物理":
				PhysicsServer3D.set_active(false)
			"三维":
				get_viewport().disable_3d = true
			"界面":
				for k in main.get_children():
					if k is CanvasLayer:
						_off(k)
						(k as CanvasLayer).visible = false


func _off(n: Node) -> void:
	if n == null:
		return
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is Node3D:
		(n as Node3D).visible = false
