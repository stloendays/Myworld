extends Node
## 联机（Autoload，名为 Net）：玩家自建房间，房主本机兼任服务器（Godot ENet，UDP）。
##   房主：host_room() → 监听端口，按 UPnP 尝试在路由器上开端口，生成房间号（公网 / 局域网 / 虚拟局域网）。
##   访客：join_room(房间号或地址) → 握手核对版本与人数 → 收到房间名单与世界快照 → 进入同一个湖畔。
## 同步内容：
##   · 玩家：每人自己模拟自己的人物，20 Hz 把位置、朝向、速度发给房主，房主转发给其他人（RemotePlayers 显示）；
##   · 世界：时间、季节、天气、地面积雪湿润以房主为准，4 Hz 广播；访客本地不再自行变天；
##   · 可交互物（门等）：访客改了先本地生效，再请房主核对距离后广播；不通过就按房主的状态改回来；
##   · 聊天与 /me：经房主转发；进出房间、房主离开等写成系统通知。
## 房主退出或断线：访客收到通知，回到自己的单人湖畔（世界停在最后同步的状态）。
## 不经过任何外部服务器；跨网络需要房主路由器支持 UPnP（或手动转发 UDP 端口），或双方在同一个虚拟局域网里。

signal state_changed(state: int)
signal roster_changed
signal room_codes_changed
signal notice(text: String)                                   ## 已翻译的系统通知
signal chat_received(kind: String, author: String, text: String)

enum State { OFFLINE, HOSTING, CONNECTING, CLIENT }

const DEFAULT_PORT := RoomCode.DEFAULT_PORT
const MAX_PLAYERS := 4
const PROTOCOL := 3   ## 2：姿态里加了身体状态（坐、躺、划船、手势）；3：欢迎包带房主的本局规则（GameRules），房主改规则再广播
const BODY_STATES := ["", "sit", "paddle", "ground_sit", "lie", "wave", "dance", "clap"]
const POSE_HZ := 20.0
const WORLD_HZ := 4.0
const JOIN_TIMEOUT := 10.0
const INTERACT_RANGE := 5.0
const MAX_CHAT := 200

var state := State.OFFLINE
var port := DEFAULT_PORT
var roster := {}            ## peer_id -> {"name": String, "appearance": Dictionary}
var room_codes: Array = []  ## [{"kind": "internet" | "lan" | "vpn", "code": String, "address": String}]
var upnp_status := ""       ## "" / "working" / "open" / "none" / "cgnat" / "failed"
var last_error := ""        ## 最近一次失败的原因（已翻译）
var version_override := ""  ## 测试用：假装成别的版本
var upnp_enabled := true    ## 测试里关掉，不去动路由器

var _peer: ENetMultiplayerPeer = null
var _upnp: UPNP = null
var _upnp_thread: Thread = null
var _pose_timer := 0.0
var _world_timer := 0.0
var _join_timer := 0.0
var _poses := {}            ## peer_id -> 最近一次位置（房主核对交互距离）
var _applying_remote := false
var _announced_weather: StringName = &""
var _weather_paused_node: Node = null
var _own_rules: Dictionary = {}   ## 做客前自己的规则（离开房间时换回来）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	EventBus.interactable_state_changed.connect(_on_local_interactable)
	PlayerProfile.name_changed.connect(_send_profile)
	PlayerProfile.appearance.changed.connect(_send_profile)
	GameRules.changed.connect(_on_rules_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_remove_port_mapping()


func game_version() -> String:
	if version_override != "":
		return version_override
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func is_online() -> bool:
	return state == State.HOSTING or state == State.CLIENT


func is_host() -> bool:
	return state == State.HOSTING


func is_client() -> bool:
	return state == State.CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if _peer != null else 1


func player_count() -> int:
	return roster.size()


# ---------------------------------------------------------------- 建房 / 加入 / 离开

## 创建房间；返回空串表示成功，否则是已翻译的失败原因。
func host_room(listen_port := DEFAULT_PORT) -> String:
	leave_room(true)
	_peer = ENetMultiplayerPeer.new()
	# 多留一个名额：第 5 个人能连上并收到“房间已满”，而不是莫名其妙地连不上
	var err := _peer.create_server(listen_port, MAX_PLAYERS)
	if err != OK:
		_peer = null
		last_error = tr("无法在端口 %d 上建房（可能已被占用）") % listen_port
		return last_error
	multiplayer.multiplayer_peer = _peer
	port = listen_port
	roster = {1: _my_info()}
	_set_state(State.HOSTING)
	_refresh_local_codes()
	_start_upnp()
	notice.emit(tr("房间已创建。把房间号发给朋友，他们就能加入。"))
	roster_changed.emit()
	return ""


## 加入房间；code 可以是房间号，也可以是 IP、IP:端口、主机名:端口。返回空串表示已开始连接。
func join_room(code: String) -> String:
	var addr := RoomCode.decode(code)
	if not addr["ok"]:
		last_error = tr(str(addr["error"]))
		return last_error
	leave_room(true)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(str(addr["host"]), int(addr["port"]))
	if err != OK:
		_peer = null
		last_error = tr("无法连接到 %s") % addr["host"]
		return last_error
	multiplayer.multiplayer_peer = _peer
	port = int(addr["port"])
	_join_timer = JOIN_TIMEOUT
	_set_state(State.CONNECTING)
	return ""


## 离开房间（房主离开即关闭房间）。quiet = true 时不发通知（切换房间时用）。
func leave_room(quiet := false) -> void:
	if state == State.OFFLINE and _peer == null:
		return
	var was := state
	_remove_port_mapping()
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	roster.clear()
	_poses.clear()
	room_codes.clear()
	upnp_status = ""
	_resume_local_weather()
	if was == State.CLIENT and not _own_rules.is_empty():
		GameRules.set_all(_own_rules)
		GameRules.apply_ongoing()
		_own_rules = {}
	_set_state(State.OFFLINE)
	_remote_players_call("clear")
	roster_changed.emit()
	room_codes_changed.emit()
	if not quiet and was != State.OFFLINE:
		notice.emit(tr("已离开房间，回到你自己的湖畔。"))


func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func _my_info() -> Dictionary:
	return {"name": PlayerProfile.player_name(), "appearance": PlayerProfile.appearance.to_dict()}


# ---------------------------------------------------------------- 房间号

func _refresh_local_codes() -> void:
	var codes: Array = []
	var lan := ""
	var vpn := ""
	for ip in IP.get_local_addresses():
		var kind := RoomCode.classify(ip)
		if kind == "lan" and (lan == "" or ip.begins_with("192.168.")):
			lan = ip
		elif kind == "vpn" and vpn == "":
			vpn = ip
	for c in room_codes:
		if c["kind"] == "internet":
			codes.append(c)
	if lan != "":
		codes.append({"kind": "lan", "code": RoomCode.encode(lan, port), "address": "%s:%d" % [lan, port]})
	if vpn != "":
		codes.append({"kind": "vpn", "code": RoomCode.encode(vpn, port), "address": "%s:%d" % [vpn, port]})
	room_codes = codes
	room_codes_changed.emit()


## 最适合发给朋友的房间号：公网 > 虚拟局域网 > 局域网。
func primary_code() -> Dictionary:
	for kind in ["internet", "vpn", "lan"]:
		for c in room_codes:
			if c["kind"] == kind:
				return c
	return {}


func _start_upnp() -> void:
	if not upnp_enabled or OS.get_cmdline_user_args().has("--no-upnp"):
		upnp_status = "none"
		return
	upnp_status = "working"
	room_codes_changed.emit()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(p: int) -> void:
	var u := UPNP.new()
	var result := {"status": "none", "ip": ""}
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null \
			and u.get_gateway().is_valid_gateway():
		var ext := u.query_external_address()
		if RoomCode.classify(ext) != "public":
			result["status"] = "cgnat"
		elif u.add_port_mapping(p, p, "Dusk Lake", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			result = {"status": "open", "ip": ext}
		else:
			result["status"] = "failed"
	_upnp_done.call_deferred(u, result, p)


func _upnp_done(u: UPNP, result: Dictionary, p: int) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if state != State.HOSTING or p != port:
		# 等 UPnP 的时候房间已经关了：把刚开的端口关掉
		if result["status"] == "open":
			u.delete_port_mapping(p, "UDP")
		return
	upnp_status = result["status"]
	if upnp_status == "open":
		_upnp = u
		room_codes.push_front({"kind": "internet", "code": RoomCode.encode(result["ip"], port), "address": "%s:%d" % [result["ip"], port]})
	room_codes_changed.emit()


func _remove_port_mapping() -> void:
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null


# ---------------------------------------------------------------- 连接事件

func _process(delta: float) -> void:
	if state == State.CONNECTING:
		_join_timer -= delta
		if _join_timer <= 0.0:
			_fail_join(tr("连接超时：找不到这个房间（房主没开房，或网络不通）"))
		return
	if not is_online():
		return
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = 1.0 / POSE_HZ
		_send_pose()
	if is_host():
		_world_timer -= delta
		if _world_timer <= 0.0:
			_world_timer = 1.0 / WORLD_HZ
			if roster.size() > 1:
				_world.rpc(world_snapshot())


func _on_peer_connected(_id: int) -> void:
	pass   # 等对方发 _hello 再登记


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not roster.has(id):
		return
	var who: String = roster[id]["name"]
	roster.erase(id)
	_poses.erase(id)
	_roster_remove.rpc(id)
	_roster_remove(id)
	notice.emit(tr("%s 离开了湖畔。") % who)


func _on_connected() -> void:
	_hello.rpc_id(1, PROTOCOL, game_version(), _my_info())


func _on_connection_failed() -> void:
	_fail_join(tr("连接失败：找不到这个房间（房主没开房，或网络不通）"))


func _on_server_disconnected() -> void:
	if state == State.CONNECTING:
		_fail_join(last_error if last_error != "" else tr("房主拒绝了连接"))
		return
	leave_room(true)
	notice.emit(tr("房主已离开，房间关闭了。你回到了自己的湖畔。"))


func _fail_join(reason: String) -> void:
	last_error = reason
	leave_room(true)
	notice.emit(reason)


# ---------------------------------------------------------------- 握手

## 房主判断能否接纳一名访客；返回空串表示可以，否则是拒绝原因的中文原文（对方按自己的语言翻译）。
func admit_reason(protocol: int, version: String) -> String:
	if protocol != PROTOCOL or version != game_version():
		return "版本不一致"
	if roster.size() >= MAX_PLAYERS:
		return "房间已满"
	return ""


@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int, version: String, info: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := admit_reason(protocol, version)
	if reason != "":
		_rejected.rpc_id(id, reason, game_version())
		get_tree().create_timer(0.5).timeout.connect(_kick.bind(id))
		return
	info = _clean_info(info)
	for other in roster:
		if other != 1:
			_roster_add.rpc_id(other, id, info)
	_roster_add(id, info)
	# 欢迎包里的名单已经包括这位访客自己
	_welcome.rpc_id(id, roster, world_snapshot(), WorldState.interactables, GameRules.to_dict())
	notice.emit(tr("%s 来到了湖畔。") % info["name"])


func _kick(id: int) -> void:
	if _peer != null:
		_peer.disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String, host_version: String) -> void:
	if reason == "版本不一致":
		last_error = tr("版本不一致：房主是 %s，你是 %s。请双方安装同一版本。") % [host_version, game_version()]
	else:
		last_error = tr(reason)


@rpc("authority", "call_remote", "reliable")
func _welcome(host_roster: Dictionary, world: Dictionary, interactables: Dictionary, rules: Dictionary) -> void:
	roster = host_roster
	_own_rules = GameRules.to_dict()
	_set_state(State.CLIENT)
	_apply_rules(rules)
	_pause_local_weather()
	_apply_world(world)
	_applying_remote = true
	for uid in interactables:
		var target := _find_interactable(StringName(uid))
		if target != null:
			target.apply_state(str(interactables[uid]))
	_applying_remote = false
	for id in roster:
		if id != my_id():
			_remote_players_call("add", [id, roster[id]])
	roster_changed.emit()
	notice.emit(tr("已加入 %s 的房间。") % roster.get(1, {}).get("name", "?"))


@rpc("authority", "call_remote", "reliable")
func _roster_add(id: int, info: Dictionary) -> void:
	roster[id] = info
	if id != my_id():
		_remote_players_call("add", [id, info])
	if is_client():
		notice.emit(tr("%s 来到了湖畔。") % info["name"])
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _roster_remove(id: int) -> void:
	if is_client() and roster.has(id):
		notice.emit(tr("%s 离开了湖畔。") % roster[id]["name"])
	roster.erase(id)
	_remote_players_call("remove", [id])
	roster_changed.emit()


func _clean_info(info: Dictionary) -> Dictionary:
	var n := str(info.get("name", "")).strip_edges().left(PlayerProfile.MAX_NAME_LENGTH)
	var a: Variant = info.get("appearance", {})
	return {"name": n if n != "" else "?", "appearance": a if a is Dictionary else {}}


## 名字或外观改了：告诉房间里其他人。
func _send_profile() -> void:
	if not is_online():
		return
	var info := _my_info()
	if is_host():
		roster[1] = info
		_profile_from.rpc(1, info)
	else:
		_profile.rpc_id(1, info)


@rpc("any_peer", "call_remote", "reliable")
func _profile(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or not roster.has(id):
		return
	info = _clean_info(info)
	roster[id] = info
	_profile_from.rpc(id, info)
	_profile_from(id, info)


@rpc("authority", "call_remote", "reliable")
func _profile_from(id: int, info: Dictionary) -> void:
	roster[id] = info
	if id != my_id():
		_remote_players_call("update_info", [id, info])
	roster_changed.emit()


# ---------------------------------------------------------------- 玩家位置

func _send_pose() -> void:
	var p := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if p == null or roster.size() < 2:
		return
	var horizontal := Vector2(p.velocity.x, p.velocity.z).length()
	var pose := [p.global_position, p.rotation.y + p.body.rotation.y, p.head.rotation.x, horizontal, p.is_on_floor() or p.swimming, _vehicle_of(p), body_state(p)]
	if is_host():
		_poses[1] = p.global_position
		_pose_from.rpc(1, pose)
	else:
		_pose.rpc_id(1, pose)


## 身体状态：动作（ground_sit / lie / wave / dance / clap）优先，其次坐在椅子上 sit、划船 paddle，平常为空。
## 朝向发的是身体的朝向（坐下、划船时身体转向座位或船头），别人那边的方块人按它摆。
static func body_state(p: FirstPersonController) -> String:
	if p.emote != "":
		return p.emote
	if p.seat != null:
		return "sit"
	if p.boat != null:
		return "paddle"
	return ""


## 正在划的船：[uid, 位置, 朝向]，没在船上是空数组。船跟着划船的人走，别人那边的同一条船按这个摆放。
func _vehicle_of(p: FirstPersonController) -> Array:
	var boat: Variant = p.get("boat")
	if boat is Canoe:
		return [String((boat as Canoe).uid), (boat as Canoe).global_position, (boat as Canoe).heading]
	return []


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pose(pose: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or not roster.has(id) or pose.size() != 7 or not pose[0] is Vector3 or not pose[5] is Array or not pose[6] is String or not str(pose[6]) in BODY_STATES:
		return
	_poses[id] = pose[0]
	_remote_players_call("set_pose", [id, pose])
	for other in roster:
		if other != 1 and other != id:
			_pose_from.rpc_id(other, id, pose)


@rpc("authority", "call_remote", "unreliable_ordered")
func _pose_from(id: int, pose: Array) -> void:
	if id != my_id():
		_remote_players_call("set_pose", [id, pose])


func _remote_players_call(method: String, args := []) -> void:
	var rp := get_tree().get_first_node_in_group("remote_players")
	if rp != null:
		rp.callv(method, args)


# ---------------------------------------------------------------- 世界状态

const WORLD_KEYS := ["world_day", "time_minutes", "season_override", "weather_id", "weather_from", "weather_progress",
	"weather_transition_seconds", "weather_seed", "weather_change_count", "weather_next_change",
	"ground_snow", "ground_wetness", "rain_recent", "time_paused"]


func world_snapshot() -> Dictionary:
	var d := {}
	for k in WORLD_KEYS:
		d[k] = WorldState.get(k)
	return d


@rpc("authority", "call_remote", "unreliable_ordered")
func _world(d: Dictionary) -> void:
	if is_client():
		_apply_world(d)


func _apply_world(d: Dictionary) -> void:
	for k in WORLD_KEYS:
		if not d.has(k):
			continue
		var v: Variant = d[k]
		if k == "time_minutes" and int(d.get("world_day", 0)) == WorldState.world_day \
				and absf(float(v) - WorldState.time_minutes) < 0.5:
			continue   # 本地时钟本来就在走，差得不多就不跳
		if k in ["weather_id", "weather_from"]:
			v = StringName(str(v))
		WorldState.set(k, v)
	var seasons := get_tree().get_first_node_in_group("season_controller") as SeasonController
	if seasons != null:
		seasons.refresh()
	# 访客的天气过渡由房主推进；过渡完成时照常发 weather_changed（聊天框等据此提示）
	if WorldState.weather_progress >= 1.0 and WorldState.weather_id != _announced_weather:
		var first := _announced_weather == &""
		_announced_weather = WorldState.weather_id
		if not first:
			EventBus.weather_changed.emit(WorldState.weather_id)


func _pause_local_weather() -> void:
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	if climate != null:
		_weather_paused_node = climate.weather
		climate.weather.process_mode = Node.PROCESS_MODE_DISABLED
	_announced_weather = &""


func _resume_local_weather() -> void:
	if _weather_paused_node != null and is_instance_valid(_weather_paused_node):
		_weather_paused_node.process_mode = Node.PROCESS_MODE_INHERIT
	_weather_paused_node = null


# ---------------------------------------------------------------- 可交互物（门等）

func _find_interactable(uid: StringName) -> Interactable:
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Interactable).uid == uid:
			return n as Interactable
	return null


func _on_local_interactable(uid: StringName, s: String) -> void:
	if _applying_remote or not is_online():
		return
	# 船不走“可交互物”同步：谁在划船，船的位置就跟着谁的姿态包走（见 _vehicle_of）
	var target := _find_interactable(uid)
	if target != null and target.is_in_group("vehicles"):
		return
	if is_host():
		_interactable.rpc(uid, s)
	else:
		_interact_request.rpc_id(1, uid, s)


@rpc("any_peer", "call_remote", "reliable")
func _interact_request(uid: StringName, s: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or not roster.has(id):
		return
	var target := _find_interactable(uid)
	if target == null:
		return
	var at: Variant = _poses.get(id)
	var ok: bool = at is Vector3 and (at as Vector3).distance_to(target.global_position) <= INTERACT_RANGE
	if ok:
		_apply_remote_interactable(uid, s)
		_interactable.rpc(uid, s)
	else:
		_interactable.rpc_id(id, uid, target.get_state())


@rpc("authority", "call_remote", "reliable")
func _interactable(uid: StringName, s: String) -> void:
	_apply_remote_interactable(uid, s)


func _apply_remote_interactable(uid: StringName, s: String) -> void:
	var target := _find_interactable(uid)
	if target == null or target.get_state() == s:
		return
	_applying_remote = true
	target.apply_remote_state(s)
	_applying_remote = false


# ---------------------------------------------------------------- 聊天

## 本地刚发出的一条消息（已在本地显示）：发给房间里其他人。
func send_chat(kind: String, text: String) -> void:
	if not is_online():
		return
	text = text.left(MAX_CHAT)
	if is_host():
		_chat_from.rpc(1, kind, text)
	else:
		_chat.rpc_id(1, kind, text)


@rpc("any_peer", "call_remote", "reliable")
func _chat(kind: String, text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or not roster.has(id) or not kind in ["player", "emote"]:
		return
	text = text.left(MAX_CHAT)
	_chat_from(id, kind, text)
	for other in roster:
		if other != 1 and other != id:
			_chat_from.rpc_id(other, id, kind, text)


@rpc("authority", "call_remote", "reliable")
func _chat_from(id: int, kind: String, text: String) -> void:
	if id == my_id():
		return
	chat_received.emit(kind, str(roster.get(id, {}).get("name", "?")), text)


# ---------------------------------------------------------------- 本局规则（房主为准）

func _on_rules_changed() -> void:
	if is_host() and roster.size() > 1 and not _applying_remote:
		_rules.rpc(GameRules.to_dict())


@rpc("authority", "call_remote", "reliable")
func _rules(rules: Dictionary) -> void:
	if is_client():
		_apply_rules(rules)


## 访客照房主的规则走（一天长度、动物数量、仙境、体力、HUD……）；开局类的（起始时刻、天气）不用，世界状态本来就跟房主同步。
func _apply_rules(rules: Dictionary) -> void:
	_applying_remote = true
	GameRules.set_all(rules)
	GameRules.apply_ongoing()
	_applying_remote = false
