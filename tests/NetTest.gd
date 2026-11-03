extends Node
## 联机自动检查（两个进程，本机回环）：
##   godot --headless --path . res://tests/NetTest.tscn          退出码 0 = 全部通过
## 本进程当房主（不开 UPnP），再启动无窗口的访客进程（同一场景，参数 -- --net-client 地址）：
##   1. 访客加入：名单 2 人、房主看到访客的方块人，位置跟着访客走；
##   2. 访客在木屋门口开门 → 房主那边门也开；访客隔着 90 m 开泳池馆的门 → 房主拒绝并改回；
##   3. 访客聊天 → 房主收到；访客划独木舟 → 房主那边的船跟着走；房主改天气和时间 → 访客收到；访客 /weather 被拦下；
##   4. 房主关房 → 访客收到“房主已离开”并回到单人；
##   5. 版本不一致的访客 → 被拒绝，提示两边的版本号。
## 两个进程之间的“台词”走聊天消息（CMD … / REPORT …），访客的最终结果写 user://net_test_client.json。

const PORT := 24611
const RESULT_PATH := "user://net_test_client.json"
const PORCH := Vector3(-62.4, 2.4, 37.0)
const LAKE_POINT := Vector2(10.0, 0.0)
const WALK_FROM := Vector2(-50.0, 18.0)
const WALK_TO := Vector2(-50.0, 30.0)

var _results: Array[Dictionary] = []
var _main: Node3D
var _chat: Array = []        ## 收到的 [kind, author, text]
var _role := "host"
var _client_done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--net-client"):
		_role = "client"
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(10)
	Net.chat_received.connect(func(kind: String, author: String, text: String) -> void: _chat.append([kind, author, text]))
	if _role == "client":
		await _client()
	else:
		await _host()


# ---------------------------------------------------------------- 房主

func _host() -> void:
	print("=== Dusk Lake 联机检查（房主）===")
	Net.upnp_enabled = false
	PlayerProfile.display_name = "Host"
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	climate.apply_preset("Autumn_Dusk_Clear")
	_remove_result()
	# 房主的本局规则（新建游戏页选的）：访客加入后照它走
	GameRules.set_rule("day_length", 96)
	GameRules.set_rule("animals", "few")
	var err := Net.host_room(PORT)
	_check("房主建房", err == "" and Net.is_host(), err)
	_spawn_client([])

	var joined := await _until(func() -> bool: return Net.roster.size() == 2, 120.0)
	var guest_id := 0
	for id in Net.roster:
		if id != 1:
			guest_id = id
	var rp := get_tree().get_first_node_in_group("remote_players") as RemotePlayers
	_check("访客加入：名单 2 人，名字和外观已同步", joined and guest_id != 0 and str(Net.roster[guest_id]["name"]) == "Guest" \
		and not (Net.roster[guest_id]["appearance"] as Dictionary).is_empty(), "名单：" + ", ".join(Net.roster.values().map(func(v: Dictionary) -> String: return str(v["name"]))))

	# 访客走到木屋门廊后开门、隔远开泳池馆的门、说一句话
	var at_porch := await _until(_guest_at.bind(rp, guest_id, PORCH), 60.0)
	var p := rp.get_player(guest_id)
	_check("房主看到访客的方块人，位置跟着访客（门廊）", at_porch,
		"访客人物在 %s" % (str(p.global_position) if p != null else "（无）"))
	var door_open := await _until(func() -> bool: return WorldState.get_interactable_state(&"cabin_front_door") == "open", 20.0)
	await _seconds(2.0)
	var pool_closed := WorldState.get_interactable_state(&"poolhouse_front_door") == "closed"
	_check("访客开木屋门 → 房主的门也开；隔 90 m 开泳池馆门 → 房主拒绝", door_open and pool_closed,
		"木屋门 %s · 泳池馆门 %s" % [WorldState.get_interactable_state(&"cabin_front_door"), WorldState.get_interactable_state(&"poolhouse_front_door")])
	var hello := await _until(func() -> bool: return _heard("player", "Guest", "hello from the guest"), 20.0)
	_check("访客的聊天消息到达房主", hello)

	# 访客跳舞：房主看到的方块人也在跳；然后让访客去上船
	var dancing := await _until(func() -> bool: return p != null and p.body_state == "dance", 20.0)
	_check("访客做动作（跳舞）：房主看到的方块人也在跳", dancing and p.model.gesture == "dance" and p.model.pose == "stand",
		"状态 %s，手势 %s" % [p.body_state if p != null else "?", p.model.gesture if p != null else "?"])
	_say("CMD board")

	# 访客上独木舟划到湖上：房主这边的同一条船跟过去，并且被标成有人在用
	var canoe := get_tree().get_first_node_in_group("vehicles") as Canoe
	var boat_ok := await _until(func() -> bool: return canoe != null and canoe.world_position_2d().distance_to(LAKE_POINT) < 1.5, 30.0)
	var paddling := await _until(func() -> bool: return p.body_state == "paddle" and p.model.pose == "paddle", 10.0)
	_check("访客划独木舟：房主看到船跟着走，且自己上不去", boat_ok and canoe.rider is RemotePlayer and paddling and not canoe.can_interact(get_tree().get_first_node_in_group("local_player")),
		"船在 %s，乘客 %s" % [canoe.world_position_2d() if canoe != null else "?", canoe.rider if canoe != null else null])

	# 房主改天气和时间，让访客报告它看到的
	climate.set_weather(&"OVERCAST", 0.0)
	climate.set_hour(9.0)
	await _seconds(1.5)
	_say("CMD report")
	var reported := await _until(func() -> bool: return _report() != "", 20.0)
	var r := _report()
	_check("房主的天气、时间同步到访客；访客改天气被拦下；泳池馆门在访客那边也被改回",
		reported and r.contains("weather=OVERCAST") and r.contains("blocked=true") and r.contains("pool=closed") \
			and r.contains("cabin=open") and _time_ok(r), r)
	_check("房主的本局规则同步到访客（一天 96 分钟、小动物少；协议 %d）" % Net.PROTOCOL, r.contains("rules=96/few"), r)
	_check("小玩法：访客钓鱼、挖宝被禁用并提示，房主照常能玩", r.contains("guest_play=true") and Play.blocked("fishing") == "" and Play.blocked("treasure") == "", r)

	# 访客下船沿直线走 12 m（4 m/s）：房主这边按时间戳插值，每 0.1 秒的速度都接近 4 m/s（不快一阵慢一阵、不倒退）
	_say("CMD walk")
	var walk_start := await _until(func() -> bool: return p.visible and Vector2(p.global_position.x, p.global_position.z).distance_to(WALK_FROM) < 0.6, 30.0)
	var track: Array = []   ## [时刻 s, z]
	var t_end := Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		track.append([Time.get_ticks_usec() / 1000000.0, p.global_position.z])
	var speeds := _window_speeds(track, 0.1)
	var backwards := track.size() > 1 and _went_back(track)
	var arrived := Vector2(p.global_position.x, p.global_position.z).distance_to(WALK_TO) < 0.6
	_check("访客走路：房主看到的人物匀速（每 0.1 秒 %.1f–%.1f m/s，目标 4），不倒退" % [speeds.min() if not speeds.is_empty() else 0.0, speeds.max() if not speeds.is_empty() else 0.0],
		walk_start and arrived and not backwards and speeds.size() >= 10 and speeds.min() > 3.0 and speeds.max() < 5.0,
		"开始 %s，到达 %s，%d 个窗口" % [walk_start, arrived, speeds.size()])
	var idle := await _until(func() -> bool: return _report_with("IDLE ") != "", 20.0)
	var idle_r := _report_with("IDLE ")
	var sent := idle_r.get_slice("sent=", 1).to_int() if idle else -1
	_check("站着不动 3 秒：访客只发了 %d 个姿态包（动着时每秒 20 个）" % sent, idle and sent >= 3 and sent <= 9, idle_r)
	await _until(func() -> bool: return Net.pings.has(guest_id), 5.0)
	_check("房主量到访客的延迟并广播（%d ms）" % int(Net.pings.get(guest_id, -1)), int(Net.pings.get(guest_id, -1)) >= 0 and idle_r.contains("ping_ok=true"), idle_r)

	# 一起旅行：房主穿光门去云海浮岛 → 访客跟着去，房主在新世界看到访客；访客自己不能走
	WorldTravel.travel("world_02")
	await WorldTravel.travel_finished
	var rp2 := get_tree().get_first_node_in_group("remote_players") as RemotePlayers
	var seen := await _until(func() -> bool:
		var q := rp2.get_player(guest_id) if rp2 != null else null
		return q != null and q.visible and q.world == "world_02", 90.0)
	var follow_r := ""
	if await _until(func() -> bool: return _report_with("TRAVEL ") != "", 30.0):
		follow_r = _report_with("TRAVEL ")
	_check("房主去云海浮岛，访客跟着到了，房主在那边看到 TA；访客自己穿门被拦下、天气以房主为准",
		seen and follow_r.contains("world=world_02") and follow_r.contains("blocked=true") and follow_r.contains("weather_paused=true"), follow_r)
	var mm := get_tree().get_first_node_in_group("minimap") as Minimap
	_check("小地图、罗盘、地图能拿到朋友的位置（同一个世界）", RemotePlayers.friends(get_tree()).size() == 1 and mm != null)
	WorldTravel.travel("dusk_lake")
	await WorldTravel.travel_finished
	var back := await _until(func() -> bool:
		var r3 := get_tree().get_first_node_in_group("remote_players") as RemotePlayers
		var q := r3.get_player(guest_id) if r3 != null else null
		return q != null and q.visible and q.world == "dusk_lake", 90.0)
	_check("房主回湖畔，访客也跟回来", back)
	p = (get_tree().get_first_node_in_group("remote_players") as RemotePlayers).get_player(guest_id)

	# 房主关房 → 访客回到单人
	Net.leave_room()
	var left_ok := await _until(func() -> bool: return _client_result().has("host_left"), 30.0)
	var res := _client_result()
	_check("房主关房：访客收到通知并回到自己的湖畔", left_ok and res.get("host_left", false) and res.get("offline", false), str(res))

	# 中途加入：房主在云海浮岛开房，新访客加入后直接被带到云海浮岛；房主关房后访客回到自己的湖畔
	_remove_result()
	WorldTravel.travel("world_02")
	await WorldTravel.travel_finished
	Net.host_room(PORT)
	_spawn_client(["--net-midjoin"])
	var mid_seen := await _until(func() -> bool:
		var r4 := get_tree().get_first_node_in_group("remote_players") as RemotePlayers
		if r4 != null:
			for id in Net.roster:
				var q := r4.get_player(id)
				if q != null and q.visible and q.world == "world_02":
					return true
		return false, 150.0)
	_check("房主在云海浮岛时有人加入：访客直接来到云海浮岛", mid_seen)
	await _seconds(3.0)   # 等访客的加载画面淡出（旅行没走完时关房，访客会到了以后直接再回湖畔）
	Net.leave_room()
	var mid_done := await _until(func() -> bool: return _client_result().has("world_after_leave"), 120.0)
	_check("房主关房后，在别的世界做客的访客回到自己的湖畔", mid_done and str(_client_result().get("world_after_join")) == "world_02" \
		and str(_client_result().get("world_after_leave")) == "dusk_lake", str(_client_result()))

	# 版本不一致的访客
	_remove_result()
	Net.host_room(PORT)
	_spawn_client(["--net-version", "9.9.9"])
	var rejected := await _until(func() -> bool: return _client_result().has("rejected"), 120.0)
	var res2 := _client_result()
	var msg := str(res2.get("rejected", ""))
	_check("版本不一致的访客被拒绝，提示两边的版本号", rejected and Net.roster.size() == 1 and msg.contains("9.9.9") \
		and msg.contains(Net.game_version()), msg)
	Net.leave_room(true)
	_report_and_quit()


func _spawn_client(extra: Array) -> void:
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("user://net_test_client.log"), "--path",
		ProjectSettings.globalize_path("res://"), "res://tests/NetTest.tscn", "--", "--net-client", "127.0.0.1:%d" % PORT]
	args.append_array(extra)
	var pid := OS.create_process(OS.get_executable_path(), args)
	print("访客进程 pid ", pid)


func _guest_at(rp: RemotePlayers, id: int, where: Vector3) -> bool:
	var p := rp.get_player(id)
	return p != null and p.visible and p.global_position.distance_to(where) < 1.0


func _say(text: String) -> void:
	Net.send_chat("player", text)


func _heard(kind: String, author: String, text: String) -> bool:
	for c in _chat:
		if c[0] == kind and c[1] == author and c[2] == text:
			return true
	return false


func _report() -> String:
	return _report_with("REPORT ")


func _report_with(prefix: String) -> String:
	for c in _chat:
		if str(c[2]).begins_with(prefix):
			return str(c[2])
	return ""


## 按时间窗口算速度（m/s）：只算人物已经起步、还没到终点的那一段。track = [[时刻 s, z], ...]，z 一路增大。
func _window_speeds(track: Array, w: float) -> Array:
	var out := []
	if track.size() < 2:
		return out
	var z0: float = track[0][1]
	var z1: float = track[-1][1]
	var i := 0
	var j := 0
	while i < track.size():
		var t0: float = track[i][0]
		while j < track.size() and float(track[j][0]) < t0 + w:
			j += 1
		if j >= track.size():
			break
		var a: float = track[i][1]
		var b: float = track[j][1]
		if a > z0 + 0.4 and b < z1 - 0.4:
			out.append((b - a) / (float(track[j][0]) - t0))
		i = j
	return out


func _went_back(track: Array) -> bool:
	for k in range(1, track.size()):
		if float(track[k][1]) < float(track[k - 1][1]) - 0.005:
			return true
	return false


func _ground(xz: Vector2) -> Vector3:
	return Vector3(xz.x, WorldTerrain.height_at(xz.x, xz.y) + 0.05, xz.y)


func _time_ok(r: String) -> bool:
	var i := r.find("time=")
	if i < 0:
		return false
	var minutes := r.substr(i + 5).get_slice(" ", 0).to_float()
	return absf(minutes - WorldState.time_minutes) < 3.0


# ---------------------------------------------------------------- 访客

func _client() -> void:
	var args := OS.get_cmdline_user_args()
	PlayerProfile.display_name = "Guest"
	var i := args.find("--net-version")
	if i >= 0:
		Net.version_override = args[i + 1]
	var addr: String = args[args.find("--net-client") + 1]
	var result := {}
	if args.has("--net-midjoin"):
		await _client_midjoin(addr)
		return
	Net.join_room(addr)
	var joined := await _until(func() -> bool: return Net.is_client() or (Net.state == Net.State.OFFLINE), 60.0)
	if not joined or not Net.is_client():
		result["rejected"] = Net.last_error
		_finish_client(result)
		return
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	player.global_position = PORCH
	player.velocity = Vector3.ZERO
	await _seconds(1.5)
	var cabin_door := _door(&"cabin_front_door")
	var pool_door := _door(&"poolhouse_front_door")
	if cabin_door != null and cabin_door.get_state() == "closed":
		cabin_door.interact(player)
	if pool_door != null:
		pool_door.interact(player)   # 离门 90 m：房主应该拒绝并改回
	Net.send_chat("player", "hello from the guest")
	player.do_emote("dance")
	await _until(func() -> bool: return _heard("player", "Host", "CMD board"), 60.0)
	player.end_emote()
	var canoe := get_tree().get_first_node_in_group("vehicles") as Canoe
	if canoe != null:
		player.board(canoe)
		canoe.place_at(LAKE_POINT, 90.0)
	var asked := await _until(func() -> bool: return _heard("player", "Host", "CMD report"), 60.0)
	if asked:
		await _seconds(1.0)
		var chat := get_tree().get_first_node_in_group("chat_box") as ChatBox
		var before := WorldState.weather_id
		chat.submit("/weather fog")
		var blocked: bool = WorldState.weather_id == before and chat.messages[-1]["kind"] == "error"
		# 小玩法：访客按 R 钓鱼被拦下并提示（世界是房主的，记录不存）
		var play := get_tree().get_first_node_in_group("play_activities") as PlayActivities
		var guest_blocked: bool = Play.blocked("fishing") != "" and Play.blocked("treasure") != "" and play != null and not play.cast() and play.fish_state == ""
		Net.send_chat("player", "REPORT weather=%s time=%.1f blocked=%s pool=%s cabin=%s rules=%d/%s guest_play=%s" % [WorldState.weather_id,
			WorldState.time_minutes, blocked, pool_door.get_state() if pool_door != null else "?",
			cabin_door.get_state() if cabin_door != null else "?", int(GameRules.get_rule("day_length")), str(GameRules.get_rule("animals")), guest_blocked])
	# 下船走一段直线（4 m/s），然后站着不动 3 秒，报告这段时间发了几个姿态包
	if await _until(func() -> bool: return _heard("player", "Host", "CMD walk"), 60.0):
		player.teleport_to(_ground(WALK_FROM))
		player.set_physics_process(false)
		await _seconds(1.0)
		# 和真的走路一样，每个物理步走一小段（4 m/s × 1/60 s）
		var steps := 3 * Engine.physics_ticks_per_second
		for s in steps:
			await get_tree().physics_frame
			var k := float(s + 1) / steps
			player.global_position = _ground(WALK_FROM.lerp(WALK_TO, k))
			player.velocity = Vector3(0.0, 0.0, 4.0) if k < 1.0 else Vector3.ZERO
		await _seconds(0.5)
		var before := Net.poses_sent
		await _seconds(3.0)
		player.set_physics_process(true)
		Net.send_chat("player", "IDLE sent=%d ping_ok=%s" % [Net.poses_sent - before, Net.ping_of(Net.my_id()) >= 0 and not Net.pings.is_empty()])
	# 房主带路去云海浮岛：跟过去，报告；再跟回湖畔
	if await _until(func() -> bool: return WorldTravel.current_world == "world_02" and not WorldTravel.busy, 120.0):
		await _seconds(1.0)
		var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
		Net.send_chat("player", "TRAVEL world=%s blocked=%s weather_paused=%s" % [WorldTravel.current_world, WorldTravel.blocked_reason("world_03") != "",
			climate == null or climate.weather.process_mode == Node.PROCESS_MODE_DISABLED])
		await _until(func() -> bool: return WorldTravel.current_world == "dusk_lake" and not WorldTravel.busy, 120.0)
	var left := await _until(func() -> bool: return Net.state == Net.State.OFFLINE, 60.0)
	result["host_left"] = left
	result["offline"] = Net.state == Net.State.OFFLINE and _weather_running()
	_finish_client(result)


## 中途加入的访客：房主在云海浮岛，加入后应该被带过去；房主关房后回到自己的湖畔。
func _client_midjoin(addr: String) -> void:
	var result := {}
	Net.join_room(addr)
	await _until(func() -> bool: return Net.is_client(), 60.0)
	await _until(func() -> bool: return WorldTravel.current_world == "world_02" and not WorldTravel.busy, 120.0)
	result["world_after_join"] = WorldTravel.current_world
	await _until(func() -> bool: return Net.state == Net.State.OFFLINE, 120.0)
	await _until(func() -> bool: return WorldTravel.current_world == "dusk_lake" and not WorldTravel.busy, 120.0)
	await _seconds(0.5)
	result["world_after_leave"] = WorldTravel.current_world
	_finish_client(result)


func _weather_running() -> bool:
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	return climate != null and climate.weather.process_mode != Node.PROCESS_MODE_DISABLED


func _door(uid: StringName) -> Interactable:
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Interactable).uid == uid:
			return n as Interactable
	return null


func _finish_client(result: Dictionary) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result))
		f.close()
	get_tree().quit(0)


# ---------------------------------------------------------------- 工具

func _client_result() -> Dictionary:
	if not FileAccess.file_exists(RESULT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESULT_PATH))
	return parsed if parsed is Dictionary else {}


func _remove_result() -> void:
	if FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))


func _until(cond: Callable, timeout_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _check(name: String, ok: bool, detail := "") -> void:
	_results.append({"name": name, "ok": ok})
	print(("[PASS] " if ok else "[FAIL] ") + name + ("  —  " + detail if detail != "" else ""))


func _report_and_quit() -> void:
	var failed := 0
	for r in _results:
		if not r["ok"]:
			failed += 1
	print("=== 联机检查：%d 项通过，%d 项失败 ===" % [_results.size() - failed, failed])
	get_tree().quit(1 if failed > 0 else 0)
