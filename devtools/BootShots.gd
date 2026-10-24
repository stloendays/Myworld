extends Node
## 开发工具：在真实窗口里走一遍启动流程（加载界面 → 开场过场 → 主菜单），按时间点截图到 docs/screenshots/。
##   Godot_console.exe --path . --resolution 1600x900 res://devtools/BootShots.tscn [-- 名称前缀]
## 截图：boot_01 加载界面、boot_02 过场第一段（标题）、boot_03 第二段（码头）、boot_04 第三段（落到玩家）、boot_05 主菜单。

const OUT_DIR := "res://docs/screenshots"
const PREFIX := "v04_"

var _boot: BootLoader


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_boot = (load("res://scenes/boot/Boot.tscn") as PackedScene).instantiate() as BootLoader
	get_tree().root.add_child(_boot)
	await _seconds(1.2)
	_save("boot_01_loading")
	# 等过场开始（或启动已结束 / 本节点已释放 / 超过 120 秒）
	var deadline := Time.get_ticks_msec() + 120000
	while _intro() == null and is_instance_valid(_boot) and not _boot.done and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var shots := IntroCutscene.shots()
	if _intro() != null:
		# 第一段标题完全显出来的时候、第二段中间、第三段快结束时
		var t0 := Time.get_ticks_msec()
		await _until_ms(t0, 5200)
		_save("boot_02_intro_title")
		await _until_ms(t0, int((float(shots[0]["seconds"]) + 0.4 + float(shots[1]["seconds"]) * 0.55) * 1000.0))
		_save("boot_03_intro_dock")
		await _until_ms(t0, int((float(shots[0]["seconds"]) + float(shots[1]["seconds"]) + 0.8 + float(shots[2]["seconds"]) * 0.7) * 1000.0))
		_save("boot_04_intro_landing")
	var lobby := get_tree().get_first_node_in_group("lobby_menu") as LobbyMenu
	while (lobby == null or not lobby.is_open()) and Time.get_ticks_msec() < deadline + 60000:
		await get_tree().process_frame
		lobby = get_tree().get_first_node_in_group("lobby_menu") as LobbyMenu
	await _seconds(1.2)
	_save("boot_05_menu")
	get_tree().quit()


func _intro() -> IntroCutscene:
	var n := get_tree().root.find_child("IntroCutscene", true, false)
	return n as IntroCutscene


func _until_ms(t0: int, ms: int) -> void:
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s%s.png" % [OUT_DIR, PREFIX, name])
	img.save_png(path)
	print("saved ", path)
