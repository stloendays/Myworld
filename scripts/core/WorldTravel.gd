extends Node
## 跨世界旅行（Autoload）。世界之间不同时加载：先把当前世界整个卸掉、清掉只有它用的材质与模型缓存，
## 再在后台线程读下一个世界的场景，读完才实例化。中间一层渐黑的加载画面（不随世界卸载）。
## 世界在 data/worlds/worlds.json 里登记（scene、status、arrivals）；“当前世界”记在这里，WorldRegistry 读它。
## 不调用引擎的切场景函数：当前世界根节点（group "world_root"）在原父节点下被换掉，
## 所以在自动检查里（世界挂在 TestRunner 下）和游戏里（世界是主场景）走的是同一条路。
## 联机时不能离开（房间里的人都在同一个世界）。

signal travel_started(to_id: String)
signal travel_finished(world_id: String)

const FADE_SECONDS := 0.6

var current_world := "dusk_lake"
var arriving_from := ""          ## 刚从哪个世界过来（新世界按 worlds.json → arrivals 摆放玩家；也用来跳过开始菜单）
var busy := false
var progress := 0.0
var last_report: Dictionary = {}  ## 最近一次旅行的内存与时间记录（自动检查读）

var _overlay: CanvasLayer
var _fade: ColorRect
var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	current_world = str(WorldRegistry.data().get("current", "dusk_lake"))
	_build_overlay()


## 能不能去：返回空字符串表示可以，否则是原因。
func blocked_reason(id: String) -> String:
	if busy:
		return tr("正在前往别的世界")
	if id == current_world:
		return tr("你就在这里")
	if not WorldRegistry.is_open(id):
		return tr("那个世界还在建设中")
	if Net.is_online():
		return tr("联机时暂时不能去别的世界")
	return ""


func travel(id: String) -> bool:
	var why := blocked_reason(id)
	if why != "":
		EventBus.toast_requested.emit(why)
		return false
	_do_travel(id)
	return true


func _do_travel(id: String) -> void:
	busy = true
	progress = 0.0
	travel_started.emit(id)
	var w := WorldRegistry.get_world(id)
	var path := str(w["scene"])
	_label.text = tr("正在前往「%s」……") % TranslationServer.translate(str(w["name"]))
	_overlay.visible = true
	await _fade_to(1.0)
	var t0 := Time.get_ticks_msec()
	var report := {"from": current_world, "to": id, "static_before": Performance.get_monitor(Performance.MEMORY_STATIC),
		"objects_before": Performance.get_monitor(Performance.OBJECT_COUNT), "nodes_before": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	# 1. 卸载当前世界
	var root := get_tree().get_first_node_in_group("world_root")
	var parent: Node = root.get_parent() if root != null else get_tree().root
	var was_current := root != null and get_tree().current_scene == root
	if root != null:
		root.queue_free()
		await root.tree_exited
	await get_tree().process_frame
	await get_tree().process_frame
	_release_caches()
	report["static_unloaded"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	report["nodes_unloaded"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	# 2. 后台线程读新世界
	ResourceLoader.load_threaded_request(path, "PackedScene", true)
	var prog: Array = [0.0]
	while true:
		var st := ResourceLoader.load_threaded_get_status(path, prog)
		progress = float(prog[0]) * 0.8
		_bar.value = progress * 100.0
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	arriving_from = current_world
	current_world = id
	var inst := packed.instantiate()
	parent.add_child(inst)
	if was_current:
		get_tree().current_scene = inst
	progress = 1.0
	_bar.value = 100.0
	await get_tree().process_frame
	await get_tree().process_frame
	report["static_after"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	report["nodes_after"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	report["ms"] = Time.get_ticks_msec() - t0
	last_report = report
	await _fade_to(0.0)
	_overlay.visible = false
	busy = false
	travel_finished.emit(id)


## 新世界里玩家该站的地方：worlds.json → 本世界 arrivals[来时的世界]（{pos: [x, y, z], heading}）；没有就返回空。
func arrival() -> Dictionary:
	if arriving_from == "":
		return {}
	var arr: Dictionary = WorldRegistry.get_world(current_world).get("arrivals", {})
	return arr.get(arriving_from, {})


## 只属于上一个世界的静态缓存（贴图材质、Kenney 模型）。下一个世界用到时会重新读。
func _release_caches() -> void:
	ArtMaterials.clear_cache()


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, FADE_SECONDS)
	_label.modulate.a = alpha
	_bar.modulate.a = alpha
	await tw.finished


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.visible = false
	add_child(_overlay)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.03, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_fade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520.0, 0.0)
	box.position = Vector2(-260.0, -30.0)
	box.add_theme_constant_override("separation", 14)
	_fade.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520.0, 10.0)
	_bar.show_percentage = false
	box.add_child(_bar)
