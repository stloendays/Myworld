class_name BootLoader
extends Node
## 启动流程（工程的主场景 scenes/boot/Boot.tscn）：引擎自带的启动图之后出现加载画面（LoadingScreen），
##   1. 后台线程读当前世界的场景（worlds.json → current，一般是暮色湖畔 Main.tscn；进度 0–70%）；
##   2. 实例化并加到根节点下、设为 current_scene（生成地形、森林、建筑在主线程，画面会停一下，阶段文字先写好）；
##   3. 让世界在加载画面后面渲染几十帧，把着色器编译完（85–100%），进游戏时不卡；
##   4. 暮色湖畔放开场过场（设置里可关，命令行 -- --skip-intro 跳过），然后弹出主菜单。
## 不切换场景：世界直接加在根节点下（WorldTravel 换世界时按 current_scene 接着换），本节点随后释放。
## 每一步都打印到日志（带毫秒），后台读取超过 STALL_WARN_S 秒没有进展会报错，方便查“卡在加载”。

const WARMUP_FRAMES := 40
const STALL_WARN_S := 20.0
const FALLBACK_SCENE := "res://scenes/main/Main.tscn"

## 正在由本流程启动（大厅菜单据此不自己弹出，等过场结束由这里打开）
static var active := false

var screen: LoadingScreen
var world: Node = null
var done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = true
	screen = LoadingScreen.new()
	screen.name = "LoadingScreen"
	add_child(screen)
	_run.call_deferred()


static func world_scene_path() -> String:
	var path := str(WorldRegistry.get_world(WorldTravel.current_world).get("scene", ""))
	return path if path != "" and ResourceLoader.exists(path) else FALLBACK_SCENE


func _run() -> void:
	var path := world_scene_path()
	screen.set_stage("正在加载湖畔…")
	screen.set_progress(0.02)
	var err := ResourceLoader.load_threaded_request(path, "PackedScene", false)
	if err != OK:
		_fail("load_threaded_request %s -> %d" % [path, err])
		return
	var prog: Array = [0.0]
	var last_p := -1.0
	var last_change := Time.get_ticks_msec()
	var warned := false
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, prog)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_fail("load %s failed (status %d)" % [path, status])
			return
		var p := float(prog[0])
		if p != last_p:
			last_p = p
			last_change = Time.get_ticks_msec()
		elif not warned and Time.get_ticks_msec() - last_change > STALL_WARN_S * 1000.0:
			warned = true
			push_error("BootLoader: 后台读取 %s 已 %d 秒没有进展（停在 %.0f%%）" % [path, int(STALL_WARN_S), p * 100.0])
		screen.set_progress(0.02 + p * 0.68)
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		_fail("%s is not a PackedScene" % path)
		return
	screen.set_stage("正在搭建世界…")
	screen.set_progress(0.72)
	# 让文字和进度先画出来，再做主线程上的大块生成
	for i in 3:
		await get_tree().process_frame
	world = packed.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	screen.set_stage("正在点亮暮色…")
	for i in WARMUP_FRAMES:
		screen.set_progress(0.85 + 0.15 * float(i + 1) / WARMUP_FRAMES)
		await get_tree().process_frame
	screen.set_stage("准备好了")
	while screen.shown_progress < 0.999:
		await get_tree().process_frame
	await _hand_over()


func _fail(why: String) -> void:
	push_error("BootLoader: " + why)
	screen.set_stage("加载失败")


func _hand_over() -> void:
	# 黑幕先盖住，加载画面淡出露出黑幕，再由过场（或直接）从黑幕里淡入
	Fade.set_black()
	await screen.vanish(0.5)
	var args := OS.get_cmdline_user_args()
	var direct := args.has("--host") or args.has("--join")
	if want_intro(args):
		var intro := IntroCutscene.new()
		intro.name = "IntroCutscene"
		world.add_child(intro)
		await intro.play(world)
	else:
		Fade.fade_in(0.8)
	active = false
	done = true
	var lobby := world.get_node_or_null("LobbyMenu") as LobbyMenu
	if lobby != null and not direct and not args.has("--skip-menu") and not lobby.is_open() and not Net.is_online():
		lobby.open()
	print("BootLoader: done (%d ms)" % Time.get_ticks_msec())
	queue_free()


## 开场过场只在暮色湖畔放（镜头写在它的 world_layout.json 里）；设置可关；直接建房 / 加入时不放。
static func want_intro(args: PackedStringArray) -> bool:
	return GameSettings.play_intro and WorldTravel.current_world == "dusk_lake" and not args.has("--skip-intro") \
		and not args.has("--host") and not args.has("--join")
