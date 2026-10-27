extends Node
## 开发工具：内存与卡顿探针。加载主场景计时，记录内存 / 显存 / 对象数，再沿一条走遍全图的路线
## （林道、木屋、图腾山洞、码头、泳池馆、地下水族馆、雪山、石头小屋）以步行速度移动相机，途中切换天气，
## 统计帧时分布和卡顿帧（> 33 ms），最后再记一次内存，看有没有边走边涨。
##   Godot_console.exe --path . --resolution 1600x900 res://devtools/MemProbe.tscn
## 结果打印为 MEM / HITCH / FRAMES 行，并写入 user://memprobe.json。默认设置（高画质），只关帧率上限和垂直同步。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const SPEED := 7.0
## 路线：[x, z, 绝对高度或 null（贴地 + 1.65）, 切换的天气预设]
const ROUTE := [
	[-50.0, 29.0, null, ""],
	[-62.0, 37.0, null, ""],
	[-72.2, 37.6, 4.05, ""],
	[-62.0, 37.0, null, "Autumn_Night_HeavyRain"],
	[-80.0, -50.0, null, ""],
	[-93.0, -101.0, null, "Winter_Morning_Snow"],
	[-20.0, -60.0, null, ""],
	[-8.0, -86.0, null, ""],
	[-8.0, -94.0, null, ""],
	[8.0, -98.4, null, ""],
	[26.0, -103.2, null, ""],
	[8.0, -98.4, null, ""],
	[-8.0, -86.0, null, ""],
	[40.0, -80.0, null, ""],
	[99.5, -106.5, null, "Autumn_Dusk_Clear"],
	[80.0, -20.0, null, ""],
	[-2.0, 26.0, 2.65, "Summer_Night_Thunderstorm"],
	[-9.4, 84.0, null, ""],
	[-0.3, 84.0, 3.7, ""],
	[-0.5, 87.5, -3.4, ""],
	[13.0, 85.0, -3.3, ""],
	[-0.3, 84.0, 3.7, ""],
	[62.0, 88.0, null, ""],
	[-84.0, 93.0, null, ""],
	[-50.0, 29.0, null, ""],
]


func _ready() -> void:
	_run.call_deferred()


func _snapshot(tag: String) -> Dictionary:
	var r := {
		"tag": tag,
		"static_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"static_peak_mb": snappedf(OS.get_static_memory_peak_usage() / 1048576.0, 0.1),
		"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"tex_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buf_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	# 进程实际占用（任务管理器里的“内存”约等于私有字节）
	if OS.get_name() == "Windows":
		var out := []
		OS.execute("powershell", ["-NoProfile", "-Command", "$p = Get-Process -Id %d; '{0} {1}' -f [int]($p.WorkingSet64 / 1MB), [int]($p.PrivateMemorySize64 / 1MB)" % OS.get_process_id()], out)
		var parts := str(out[0]).strip_edges().split(" ") if out.size() > 0 else PackedStringArray()
		if parts.size() == 2:
			r["working_set_mb"] = int(parts[0])
			r["private_mb"] = int(parts[1])
	for k in ["CANVAS", "MESH", "SURFACE", "DRAW", "SPECIALIZATION"]:
		r["pipe_" + k.to_lower()] = RenderingServer.get_rendering_info(ClassDB.class_get_integer_constant("RenderingServer", "RENDERING_INFO_PIPELINE_COMPILATIONS_" + k))
	print("MEM ", JSON.stringify(r))
	return r


func _run() -> void:
	var report := {"snapshots": []}
	report["snapshots"].append(_snapshot("empty"))
	var t0 := Time.get_ticks_usec()
	var packed := load(MAIN_SCENE) as PackedScene
	var main := packed.instantiate()
	var t_inst := Time.get_ticks_usec()
	add_child(main)
	await get_tree().process_frame
	var t_first := Time.get_ticks_usec()
	report["load_ms"] = {"load_instantiate": (t_inst - t0) / 1000, "to_first_frame": (t_first - t0) / 1000}
	print("LOAD ", JSON.stringify(report["load_ms"]))
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	player.set_physics_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameSettings.set_value("max_fps", 0, false)
	GameSettings.set_value("dynamic_resolution", false, false)
	Engine.max_fps = 0
	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
	cam.fov = 75.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	for i in 120:
		await get_tree().process_frame
	report["snapshots"].append(_snapshot("loaded"))
	var climate := main.get_node("Systems") as ClimateSystem
	var frames: Array[float] = []
	var hitches := []
	var script_ms := 0.0
	var phys_ms := 0.0
	var tour_start := Time.get_ticks_usec()
	var why_last := _why_state()
	var stamp_a := Stamp.new(true)
	var stamp_b := Stamp.new(false)
	stamp_b.marks = stamp_a.marks
	get_tree().root.add_child(stamp_a)
	get_tree().root.add_child(stamp_b)
	var mark_log: Array = []
	_insert_marks(mark_log)
	var last := tour_start
	if OS.get_environment("DUSK_PROBE_SHORT") != "":
		if OS.get_environment("DUSK_PROBE_SHORT") == "scale":
			get_viewport().scaling_3d_scale = 0.5
			for i in 90:
				await get_tree().process_frame
			_snapshot("scale_50")
			get_viewport().scaling_3d_scale = 1.0
			GameSettings.set_value("fullscreen", false, false)
			get_window().size = Vector2i(1280, 720)
			for i in 90:
				await get_tree().process_frame
			_snapshot("window_720p")
		get_tree().quit()
		return
	for i in ROUTE.size() - 1:
		var a: Array = ROUTE[i]
		var b: Array = ROUTE[i + 1]
		if str(b[3]) != "":
			climate.apply_preset(str(b[3]))
		var pa := _point(a)
		var pb := _point(b)
		var dur := maxf(pa.distance_to(pb) / SPEED, 0.5)
		var t := 0.0
		while t < dur:
			await get_tree().process_frame
			var why_now := _why_state()
			var why_prev := why_last
			why_last = why_now
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000.0
			last = now
			frames.append(dt)
			script_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			var m: Dictionary = stamp_a.marks
			var scripts_ms := (int(m.get("p1", 0)) - int(m.get("p0", 0))) / 1000.0
			var phys_frame_ms := int(m.get("phys_sum", 0)) / 1000.0
			m["phys_sum"] = 0
			var slowest := _slowest(mark_log)
			mark_log.clear()
			if dt > 33.0:
				var h := {"ms": snappedf(dt, 0.1), "leg": "%d→%d" % [i, i + 1], "pos": [snappedf(cam.global_position.x, 0.1), snappedf(cam.global_position.z, 0.1)], "t": snappedf((now - tour_start) / 1e6, 0.01), "why": _why(why_prev), "scripts": snappedf(scripts_ms, 0.1), "slowest": slowest, "physics": snappedf(phys_frame_ms, 0.1)}
				hitches.append(h)
				print("HITCH ", JSON.stringify(h))
			t += minf(dt / 1000.0, 0.1)
			var p := pa.lerp(pb, clampf(t / dur, 0.0, 1.0))
			if b[2] == null and a[2] == null:
				p.y = WorldTerrain.height_at(p.x, p.z) + 1.65
			var dir := pb - pa
			dir.y = 0.0
			cam.global_position = p
			if dir.length() > 0.1:
				cam.look_at(p + dir.normalized(), Vector3.UP)
			player.global_position = p - Vector3(0.0, 1.65, 0.0)
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for f in frames:
		total += f
	var stats := {
		"frames": n, "seconds": snappedf(total / 1000.0, 0.1), "avg_ms": snappedf(total / n, 0.01),
		"p50_ms": snappedf(sorted[n / 2], 0.01), "p95_ms": snappedf(sorted[int(n * 0.95)], 0.01),
		"p99_ms": snappedf(sorted[int(n * 0.99)], 0.01), "max_ms": snappedf(sorted[n - 1], 0.1),
		"hitches_33": hitches.size(), "script_ms_avg": snappedf(script_ms / n, 0.01), "physics_ms_avg": snappedf(phys_ms / n, 0.01),
	}
	print("FRAMES ", JSON.stringify(stats))
	report["frames"] = stats
	report["hitches"] = hitches
	report["snapshots"].append(_snapshot("after_tour"))
	var f := FileAccess.open("user://memprobe.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	get_tree().quit()


func _point(w: Array) -> Vector3:
	var x := float(w[0])
	var z := float(w[1])
	var y: float = float(w[2]) if w[2] != null else WorldTerrain.height_at(x, z) + 1.65
	return Vector3(x, y, z)


## 卡顿那一帧发生了什么：新编译的渲染管线、新读进来的声音、节点数的变化（和上一帧比）。
func _why_state() -> Dictionary:
	var s := {"nodes": get_tree().get_node_count(), "sounds": SoundBank._streams.size()}
	for k in ["CANVAS", "MESH", "SURFACE", "DRAW", "SPECIALIZATION"]:
		s[k] = RenderingServer.get_rendering_info(ClassDB.class_get_integer_constant("RenderingServer", "RENDERING_INFO_PIPELINE_COMPILATIONS_" + k))
	return s


func _why(prev: Dictionary) -> Dictionary:
	var now := _why_state()
	var out := {}
	for k in now:
		if int(now[k]) != int(prev.get(k, 0)):
			out[k] = int(now[k]) - int(prev.get(k, 0))
	var vp := get_viewport().get_viewport_rid()
	out["gpu"] = snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp), 0.1)
	out["cpu_r"] = snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), 0.1)
	out["phys"] = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1)
	out["proc"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1)
	out["draws"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	return out


## 量每帧所有 _process / _physics_process 一共花了多久：一个节点最先跑（优先级最低），一个最后跑。
class Stamp extends Node:
	var first := false
	var marks := {}

	func _init(is_first: bool) -> void:
		first = is_first
		process_priority = -100000 if is_first else 100000
		process_physics_priority = -100000 if is_first else 100000

	func _process(_d: float) -> void:
		marks["p0" if first else "p1"] = Time.get_ticks_usec()

	func _physics_process(_d: float) -> void:
		var k := "f0" if first else "f1"
		if first:
			marks[k] = Time.get_ticks_usec()
		else:
			marks["phys_sum"] = int(marks.get("phys_sum", 0)) + Time.get_ticks_usec() - int(marks.get("f0", Time.get_ticks_usec()))


## 插在场景树里某个节点前面的计时标记：处理顺序和树的顺序一样，相邻两个标记之间的时间就是中间那棵子树的 _process。
class Mark extends Node:
	var label := ""
	var log: Array = []

	func _process(_d: float) -> void:
		log.append([label, Time.get_ticks_usec()])


func _insert_marks(log: Array) -> void:
	var parents: Array[Node] = [get_tree().root]
	var main := get_tree().root.find_child("Main", false, false)
	for c in get_children():
		if c.name == "Main" or c is Node3D:
			main = c
	if main != null:
		parents.append(main)
		var world := main.get_node_or_null("World")
		if world != null:
			parents.append(world)
	for p in parents:
		for c in p.get_children():
			if c is Mark:
				continue
			var m := Mark.new()
			m.label = "%s/%s" % [p.name, c.name]
			m.log = log
			p.add_child(m)
			p.move_child(m, c.get_index())


## 这一帧里相邻两个标记之间最长的三段（标记名 = 它后面那棵子树）。
static func _slowest(log: Array) -> Array:
	var gaps := []
	for i in range(log.size() - 1):
		gaps.append([snappedf((int(log[i + 1][1]) - int(log[i][1])) / 1000.0, 0.1), log[i][0]])
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return gaps.slice(0, 3)
