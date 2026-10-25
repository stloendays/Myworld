extends Node
## 跨世界旅行（Autoload）。世界之间不同时加载：先把当前世界整个卸掉、清掉只有它用的材质与模型缓存，
## 再在后台线程读下一个世界的场景，读完才实例化。中间是和启动时同一套的加载画面（LoadingScreen，不随世界卸载）。
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
var pending_spawn: Dictionary = {}  ## 到了新世界以后要站的地方（新建游戏的出生点、读档的位置）；SaveManager 在到达后放人

var _screen: LoadingScreen


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
	SaveManager.save()
	_do_travel(id)
	return true


func _do_travel(id: String) -> void:
	busy = true
	progress = 0.0
	travel_started.emit(id)
	var w := WorldRegistry.get_world(id)
	var path := str(w["scene"])
	_screen.reset()
	_screen.set_title(tr("正在前往「%s」……") % TranslationServer.translate(str(w["name"])))
	_screen.set_stage("正在收拾行囊…")
	await _screen.appear(FADE_SECONDS)
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
	_screen.set_stage("正在读取新世界…")
	ResourceLoader.load_threaded_request(path, "PackedScene", true)
	var prog: Array = [0.0]
	while true:
		var st := ResourceLoader.load_threaded_get_status(path, prog)
		progress = float(prog[0]) * 0.8
		_screen.set_progress(progress)
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	arriving_from = current_world
	current_world = id
	_screen.set_stage("正在搭建世界…")
	await get_tree().process_frame
	var inst := packed.instantiate()
	parent.add_child(inst)
	if was_current:
		get_tree().current_scene = inst
	progress = 1.0
	_screen.set_progress(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	report["static_after"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	report["nodes_after"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	report["ms"] = Time.get_ticks_msec() - t0
	last_report = report
	await _screen.vanish(FADE_SECONDS)
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
	GroundCoverBuilder.clear_cache()


func _build_overlay() -> void:
	_screen = LoadingScreen.new()
	_screen.name = "TravelLoading"
	_screen.layer = 100
	_screen.visible = false
	add_child(_screen)
