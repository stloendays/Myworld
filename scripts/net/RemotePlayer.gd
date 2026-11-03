class_name RemotePlayer
extends Node3D
## 房间里另一位玩家在本机的样子：一个方块人物（CharacterModel，用对方自己的外观），没有碰撞、不读输入。
## 收到的姿态带对方算出这个位置时的物理时刻（Net.sim_ms）：按时刻排进缓冲，画面比对方晚 INTERP_DELAY 播放，在前后两个姿态之间插值
## （网络抖动、包到得忽快忽慢都看不出来，站着不动时对方 2 Hz 发包也不会一顿一顿）；缓冲播完了就按速度往前推一小段。
## 两个相邻姿态隔得太远（> SNAP_DISTANCE，对方传送了）直接跳过去。
## 对方在划独木舟时，本机的同一条船跟着摆过去并记为“有人在用”（本机玩家上不去，船自己的物理暂停），
## 对方下船后船停在最后的位置，恢复正常。
## 不在镜头里、离得远时动画降频（和小动物一样，跳过的时间攒起来一起算）。

const SNAP_DISTANCE := 6.0
const INTERP_DELAY := 0.1      ## 秒：比对方晚这么多播放，留出两个包之间的空当
const MAX_EXTRAPOLATE := 0.25  ## 秒：包断了最多按速度往前推这么久，然后停住等
const BUFFER_SECONDS := 1.5

var peer_id := 0
var entity_id: StringName = &""
var display_name := ""
var model: CharacterModel
var world := ""                ## 对方所在的世界（不在本机这个世界时不显示）

var _snaps: Array[Dictionary] = []   ## 按对方物理时刻排好的姿态：{t, pos, yaw, pitch, speed, floor, vel, state, vehicle}
var _offset := 0.0             ## 本机时钟 − 对方时钟（秒），取见过的最小值，慢慢往上漂以跟上时钟漂移
var _has_offset := false
var _pitch := 0.0
var _speed := 0.0
var _on_floor := true
var _has_pose := false
var _vehicle: Canoe = null
var _vehicle_xz := Vector2.ZERO
var _vehicle_heading := 0.0
var _anim_accum := 0.0
var _anim_frame := 0
var body_state := ""      ## 对方的身体状态（见 Net.body_state）：坐、躺、划船、挥手、跳舞、鼓掌


func setup(id: int, info: Dictionary) -> void:
	peer_id = id
	entity_id = StringName("player_%d" % id)
	name = "Remote_%d" % id
	model = CharacterModel.new()
	model.name = "Body"
	model.appearance = _appearance_from(info)
	add_child(model)
	update_info(info)
	visible = false   # 收到第一个姿态之前不显示（避免在原点闪一下）


func update_info(info: Dictionary) -> void:
	display_name = str(info.get("name", "?"))
	if model != null and model.is_inside_tree():
		model.appearance = _appearance_from(info)


## 收到一个姿态（协议 4：[位置, 朝向, 俯仰, 水平速度, 着地, 船, 身体状态, 世界, 物理时刻 ms, 速度向量]）。
func set_pose(pose: Array) -> void:
	world = str(pose[7])
	if world != WorldTravel.current_world:
		# 对方还在别的世界（刚穿门、还在加载）：先藏起来，到了再出现
		_snaps.clear()
		_has_pose = false
		visible = false
		return
	var t := float(pose[8]) / 1000.0
	var now := Time.get_ticks_msec() / 1000.0
	var obs := now - t
	if not _has_offset or obs < _offset:
		_offset = obs
		_has_offset = true
	else:
		_offset += (obs - _offset) * 0.03   # 对方物理掉帧时它的模拟时钟会慢下来：一两秒内跟上
	if not _snaps.is_empty() and t <= float(_snaps[-1]["t"]):
		return   # 乱序的旧包
	var snap := {"t": t, "pos": pose[0], "yaw": float(pose[1]), "pitch": float(pose[2]), "speed": float(pose[3]),
		"floor": bool(pose[4]), "vehicle": pose[5] if pose[5] is Array else [], "state": str(pose[6]), "vel": pose[9]}
	if not _snaps.is_empty() and (snap["pos"] as Vector3).distance_to(_snaps[-1]["pos"]) > SNAP_DISTANCE:
		_snaps.clear()   # 对方传送了：不要从旧位置一路滑过去
	_snaps.append(snap)
	while _snaps.size() > 2 and float(_snaps[1]["t"]) < t - BUFFER_SECONDS:
		_snaps.pop_front()
	if not _has_pose or _snaps.size() == 1 and global_position.distance_to(snap["pos"]) > SNAP_DISTANCE:
		global_position = snap["pos"]
		rotation.y = snap["yaw"]
	_has_pose = true
	visible = true


func head_position() -> Vector3:
	return global_position + Vector3(0.0, 2.05, 0.0)


## 插值后的姿态：本机时刻减去时钟差、再往回 INTERP_DELAY，就是“现在该播对方哪一刻”。
func sample(now: float) -> Dictionary:
	if _snaps.is_empty():
		return {}
	var rt := now - _offset - INTERP_DELAY
	var last: Dictionary = _snaps[-1]
	if rt >= float(last["t"]):
		var ahead := minf(rt - float(last["t"]), MAX_EXTRAPOLATE)
		var out := last.duplicate()
		var vel: Vector3 = last["vel"]
		if str(last["state"]) == "" and (last["vehicle"] as Array).is_empty():
			out["pos"] = (last["pos"] as Vector3) + Vector3(vel.x, 0.0, vel.z) * ahead
		return out
	var i := _snaps.size() - 2
	while i > 0 and float(_snaps[i]["t"]) > rt:
		i -= 1
	var a: Dictionary = _snaps[i]
	var b: Dictionary = _snaps[i + 1]
	var span := float(b["t"]) - float(a["t"])
	var k := clampf((rt - float(a["t"])) / span, 0.0, 1.0) if span > 0.0001 else 1.0
	var out := a.duplicate()
	out["pos"] = (a["pos"] as Vector3).lerp(b["pos"], k)
	out["yaw"] = lerp_angle(float(a["yaw"]), float(b["yaw"]), k)
	out["pitch"] = lerpf(float(a["pitch"]), float(b["pitch"]), k)
	out["speed"] = lerpf(float(a["speed"]), float(b["speed"]), k)
	var va: Array = a["vehicle"]
	var vb: Array = b["vehicle"]
	if va.size() == 3 and vb.size() == 3 and va[0] == vb[0]:
		out["vehicle"] = [va[0], (va[1] as Vector3).lerp(vb[1], k), lerp_angle(float(va[2]), float(vb[2]), k)]
	if k > 0.5:
		out["state"] = b["state"]
		out["floor"] = b["floor"]
	return out


func _process(delta: float) -> void:
	if not _has_pose:
		return
	var s := sample(Time.get_ticks_msec() / 1000.0)
	if s.is_empty():
		return
	global_position = s["pos"]
	rotation.y = float(s["yaw"])
	_pitch = float(s["pitch"])
	_speed = float(s["speed"])
	_on_floor = bool(s["floor"])
	_set_vehicle(s["vehicle"])
	_set_body_state(str(s["state"]))
	if _vehicle != null and is_instance_valid(_vehicle):
		_vehicle.place_at(_vehicle_xz, -rad_to_deg(_vehicle_heading))
	# 动画降频：镜头背后、离得远的人每几帧才摆一次胳膊腿（位置照常每帧更新，不会一顿一顿地挪）
	_anim_accum += delta
	_anim_frame += 1
	if _anim_frame % _anim_interval() != 0:
		return
	var d := minf(_anim_accum, 0.25)
	_anim_accum = 0.0
	if model.pose == "paddle":
		model.paddle_phase += d * 4.0
	model.animate(d, _speed, _on_floor, _pitch)


func _anim_interval() -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1
	var d2 := cam.global_position.distance_squared_to(global_position)
	if d2 > 12.0 * 12.0 and not cam.is_position_in_frustum(global_position + Vector3(0.0, 1.0, 0.0)):
		return 8
	return 4 if d2 > 70.0 * 70.0 else (2 if d2 > 30.0 * 30.0 else 1)


## 按对方的身体状态摆姿势：坐 / 躺 / 划船换姿势，挥手 / 跳舞 / 鼓掌换手势。
func _set_body_state(state: String) -> void:
	if state == body_state or model == null:
		return
	body_state = state
	model.pose = state if state in ["sit", "paddle", "ground_sit", "lie"] else "stand"
	model.set_gesture(state if state in ["wave", "dance", "clap"] else "")
	model.transform = FirstPersonController.emote_body_transform(state)


func _exit_tree() -> void:
	_release_vehicle()


func _set_vehicle(v: Array) -> void:
	if v.size() == 3 and v[1] is Vector3:
		var keep := _vehicle != null and is_instance_valid(_vehicle) and String(_vehicle.uid) == str(v[0])
		var canoe := _vehicle if keep else _find_vehicle(StringName(str(v[0])))
		if canoe == null or (canoe.rider != null and canoe.rider != self):
			return
		if canoe != _vehicle:
			_release_vehicle()
			canoe.rider = self
			canoe.set_physics_process(false)
			_vehicle = canoe
			_vehicle_xz = canoe.world_position_2d()
			_vehicle_heading = canoe.heading
		var p: Vector3 = v[1]
		_vehicle_xz = Vector2(p.x, p.z)
		_vehicle_heading = float(v[2])
	elif _vehicle != null:
		_release_vehicle()


func _release_vehicle() -> void:
	if _vehicle != null and is_instance_valid(_vehicle):
		_vehicle.place_at(_vehicle_xz, -rad_to_deg(_vehicle_heading))
		_vehicle.rider = null
		_vehicle.set_physics_process(true)
	_vehicle = null


func riding() -> Canoe:
	return _vehicle


func _find_vehicle(uid: StringName) -> Canoe:
	for n in get_tree().get_nodes_in_group("vehicles"):
		if n is Canoe and (n as Canoe).uid == uid:
			return n as Canoe
	return null


static func _appearance_from(info: Dictionary) -> CharacterAppearance:
	var a := PlayerProfile.default_appearance()
	var d: Variant = info.get("appearance", {})
	if d is Dictionary and not (d as Dictionary).is_empty():
		var other := CharacterAppearance.from_dict(d)
		for slot in other.styles:
			a.styles[slot] = other.styles[slot]
		for key in other.colors:
			a.colors[key] = other.colors[key]
	return a
