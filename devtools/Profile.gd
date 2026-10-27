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
## DUSK_PROFILE=全部：再测投影、地被、声音、卷轴、界面、剧情；DUSK_PROFILE=项1,项2 只测这几项（“基线”总是先测）
const MORE := ["停声音", "停卷轴", "停界面", "停剧情", "停天气系统", "关地被投影", "关树木投影", "太阳阴影 2 级 / 80 m", "关地被（隐藏）", "关所有局部灯"]

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
	print("BATCH ", _main.get("batch_stats"))
	for path in ["PoolHouse", "World/Signs", "Cabin", "Streams", "StoneCottage", "Cave"]:
		print("WHY %s %s" % [path, _why_not_batched(_main.get_node(path))])
	_census()
	_vram()
	var configs: Array = CONFIGS
	var want := OS.get_environment("DUSK_PROFILE")
	if want == "全部":
		configs = CONFIGS + MORE
	elif want != "":
		configs = ["基线"] + Array(want.split(","))
	for spot in SPOTS:
		var e: Array = spot["eye"]
		var y := float(e[1]) + (0.0 if spot.get("abs", false) else WorldTerrain.height_at(float(e[0]), float(e[2])))
		_cam.global_position = Vector3(float(e[0]), y, float(e[2]))
		_cam.look_at(Vector3(float(spot["look"][0]), float(spot["look"][1]), float(spot["look"][2])), Vector3.UP)
		player.global_position = _cam.global_position - Vector3(0.0, 1.65, 0.0)
		var base := 0.0
		for c in configs:
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
		"停声音":
			_pause(get_node("/root/Sound"), on)
		"停卷轴":
			for s in get_tree().get_nodes_in_group("sign_boards"):
				_pause(s, on)
		"停界面":
			for k in _main.get_children():
				if k is CanvasLayer:
					_pause(k, on)
		"停剧情":
			_pause(get_tree().get_first_node_in_group("story_director"), on)
		"停天气系统":
			_pause(_main.get_node("Systems"), on)
		_ when c.begins_with("隐藏:"):
			# 隐藏:节点路径（相对 Main）——看这一类东西占多少绘制调用
			var n := _main.get_node_or_null(c.trim_prefix("隐藏:")) as Node3D
			if n != null:
				n.visible = not on
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


## 每帧在跑 _process / _physics_process 的节点，按脚本数一数（谁在吃主线程）。
func _census() -> void:
	var counts := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n.is_processing() or n.is_physics_processing()) or not n.can_process():
			continue
		var s: Script = n.get_script()
		var key := s.resource_path.get_file() if s != null else n.get_class()
		counts[key] = int(counts.get(key, 0)) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	for k in keys:
		print("CENSUS %s %d" % [k, counts[k]])


## 显存里的贴图：按大小列出前 25 张，再按来源（路径的文件夹 / 运行时生成）汇总。
func _vram() -> void:
	print("VRAM total texture %.1f MB · buffers %.1f MB · video %.1f MB" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	if not RenderingServer.has_method("texture_debug_usage"):
		return
	var list: Array = RenderingServer.call("texture_debug_usage")
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bytes"]) > int(b["bytes"]))
	var groups := {}
	var total := 0
	for d: Dictionary in list:
		var p := str(d.get("path", ""))
		var g := p.get_base_dir() if p != "" else "（运行时）%dx%d" % [int(d["width"]), int(d["height"])]
		groups[g] = int(groups.get(g, 0)) + int(d["bytes"])
		total += int(d["bytes"])
	for i in mini(25, list.size()):
		var d: Dictionary = list[i]
		print("TEX %.2f MB %dx%dx%d fmt %d %s" % [int(d["bytes"]) / 1048576.0, int(d["width"]), int(d["height"]), int(d["depth"]), int(d["format"]), str(d.get("path", ""))])
	var gk := groups.keys()
	gk.sort_custom(func(a: String, b: String) -> bool: return groups[a] > groups[b])
	for k in gk.slice(0, 20):
		print("TEXGROUP %.1f MB %s" % [groups[k] / 1048576.0, k])
	print("TEXSUM %d 张 %.1f MB" % [list.size(), total / 1048576.0])


## 静态合批（StaticBatch）以后，这棵子树里还剩哪些几何体没并，按原因数一数。
func _why_not_batched(root: Node3D) -> Dictionary:
	var referenced := StaticBatch._referenced_nodes(get_tree())
	var out := {}
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var why := ""
		var m := node as MeshInstance3D
		if node.name.begins_with(StaticBatch.BATCH_PREFIX):
			why = "合并后的"
		elif m == null or m.get_class() != "MeshInstance3D":
			why = "类型 " + node.get_class()
		elif not m.is_visible_in_tree():
			why = "隐藏"
		elif m.get_script() != null:
			why = "有脚本"
		elif m.get_child_count() > 0:
			why = "有子节点"
		elif referenced.has(m.get_instance_id()):
			why = "被变量引用"
		elif m.mesh == null:
			why = "没有网格"
		else:
			for si in m.mesh.get_surface_count():
				var mat := StaticBatch._material(m, si)
				if not StaticBatch._static_material(mat):
					why = "材质 " + (mat.get_class() if mat != null else "?")
					var b := mat as BaseMaterial3D
					if b != null and b.transparency != 0:
						why += " 透明"
					if b != null and b.uv1_triplanar and not b.uv1_world_triplanar:
						why += " 物体三平面"
					break
			if why == "":
				why = "其他（组 / 祖先类型）"
		out[why] = int(out.get(why, 0)) + 1
	return out
