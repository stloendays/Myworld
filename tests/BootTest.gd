extends Node
## 启动流程自动检查（无窗口）：
##   godot --headless --path . res://tests/BootTest.tscn          退出码 0 = 全部通过
## 走一遍真实的启动：加载画面 → 世界加进根节点并成为 current_scene → 开场过场（开始 1 秒后模拟按键跳过）
## → 主菜单弹出；检查每一步都在时限内完成（“卡在加载”会在这里超时失败），过场藏起来的界面都恢复了、
## 玩家相机重新接管、鼠标环视解锁、黑幕褪去。另外检查过场镜头的路径不穿地形、不穿建筑。

const LOAD_LIMIT_S := 90.0

var _results: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== Dusk Lake 启动流程检查 ===")
	_check_intro_paths()
	GameSettings.play_intro = true
	var t0 := Time.get_ticks_msec()
	var boot := (load("res://scenes/boot/Boot.tscn") as PackedScene).instantiate() as BootLoader
	get_tree().root.add_child(boot)
	var stages: Array[String] = []
	var screen := boot.screen
	var loaded := false
	while Time.get_ticks_msec() - t0 < LOAD_LIMIT_S * 1000.0:
		if is_instance_valid(screen) and (stages.is_empty() or stages[-1] != screen.stage):
			stages.append(screen.stage)
		if _intro() != null or (is_instance_valid(boot) and boot.done) or not is_instance_valid(boot):
			loaded = true
			break
		await get_tree().process_frame
	var world := get_tree().current_scene
	_check("加载画面在 %d 秒内走完，世界成为 current_scene" % int(LOAD_LIMIT_S),
		loaded and world != null and world.is_in_group("world_root"),
		"用时 %.1f s，阶段：%s" % [(Time.get_ticks_msec() - t0) / 1000.0, " → ".join(stages)])
	_check("加载阶段按顺序出现", stages.has("正在加载湖畔…") and stages.has("正在搭建世界…") and stages.has("正在点亮暮色…"),
		" → ".join(stages))
	if not loaded:
		_finish()
		return

	# 过场：1 秒后按一个键跳过
	var intro := _intro()
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var hud := world.get_node_or_null("HUD") as CanvasLayer
	var during_ok := intro != null and intro.playing and player.input_locked and hud != null and not hud.visible \
		and not player.camera.current
	_check("过场期间：独立镜头、界面隐藏、玩家不能环视", during_ok,
		"intro %s · 锁定 %s · HUD 可见 %s" % [intro != null, player.input_locked, hud.visible if hud != null else null])
	await get_tree().create_timer(1.0).timeout
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SPACE
	k.keycode = KEY_SPACE
	k.pressed = true
	Input.parse_input_event(k)
	var t_skip := Time.get_ticks_msec()
	var lobby := world.get_node_or_null("LobbyMenu") as LobbyMenu
	while Time.get_ticks_msec() - t_skip < 10000 and not (lobby != null and lobby.is_open()):
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	_check("按键跳过过场后弹出主菜单", lobby != null and lobby.is_open() and (Time.get_ticks_msec() - t_skip) < 6000,
		"跳过后 %.1f s" % ((Time.get_ticks_msec() - t_skip) / 1000.0))
	_check("过场结束：玩家相机接管、环视解锁、界面恢复、黑幕褪去、加载画面已释放",
		player.camera.current and not player.input_locked and hud.visible and Fade.alpha < 0.01 \
			and not is_instance_valid(boot) and not BootLoader.active and _intro() != null and not _intro().playing,
		"相机 %s · 锁定 %s · HUD %s · 黑幕 %.2f · BootLoader %s" % [player.camera.current, player.input_locked, hud.visible,
			Fade.alpha, is_instance_valid(boot)])
	_finish()


## 过场每段路径上取 40 个点：离地面至少 1.5 m；低于 12 m 时不在建筑占地（keepouts）里。
func _check_intro_paths() -> void:
	var bad := PackedStringArray()
	var keepouts: Array = WorldLayout.data().get("keepouts", [])
	var shots := IntroCutscene.shots()
	for i in shots.size():
		var s: Dictionary = shots[i]
		if not s["from"] is Array:
			continue
		var a := Vector3(float(s["from"][0]), float(s["from"][1]), float(s["from"][2]))
		var b := a
		if s["to"] is Array:
			b = Vector3(float(s["to"][0]), float(s["to"][1]), float(s["to"][2]))
		else:
			var sp := WorldLayout.v2(WorldLayout.section("spawn")["position"])
			b = Vector3(sp.x, WorldTerrain.height_at(sp.x, sp.y) + 1.65, sp.y)
		for n in 40:
			var p := a.lerp(b, smoothstep(0.0, 1.0, n / 39.0))
			var ground := WorldTerrain.height_at(p.x, p.z)
			var clearance := 1.2 if n == 39 and not s["to"] is Array else 1.5
			if p.y - ground < clearance:
				bad.append("第 %d 段 (%.0f, %.1f, %.0f) 离地 %.1f m" % [i + 1, p.x, p.y, p.z, p.y - ground])
				break
			if p.y < 12.0:
				for k in keepouts:
					var r: Array = k["rect"]
					if p.x >= r[0] and p.x <= r[2] and p.z >= r[1] and p.z <= r[3]:
						bad.append("第 %d 段穿过建筑 %s" % [i + 1, k["id"]])
						break
	_check("开场镜头 %d 段路径不穿地形、不穿建筑" % shots.size(), bad.is_empty() and shots.size() >= 2, "；".join(bad))


func _intro() -> IntroCutscene:
	return get_tree().root.find_child("IntroCutscene", true, false) as IntroCutscene


func _check(name: String, ok: bool, detail := "") -> void:
	_results.append({"name": name, "ok": ok})
	print(("[PASS] " if ok else "[FAIL] ") + name + ("  —  " + detail if detail != "" else ""))


func _finish() -> void:
	var failed := 0
	for r in _results:
		if not r["ok"]:
			failed += 1
	print("=== 启动流程检查：%d 项通过，%d 项失败 ===" % [_results.size() - failed, failed])
	get_tree().quit(1 if failed > 0 else 0)
