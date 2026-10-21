class_name RemotePlayer
extends Node3D
## 房间里另一位玩家在本机的样子：一个方块人物（CharacterModel，用对方自己的外观），没有碰撞、不读输入。
## 位置和朝向由 Net 收到的姿态驱动，在两次更新之间平滑插值；离得太远（> SNAP_DISTANCE）直接跳过去（对方传送）。
## 对方在划独木舟时，本机的同一条船跟着摆过去并记为“有人在用”（本机玩家上不去，船自己的物理暂停），
## 对方下船后船停在最后的位置，恢复正常。

const SNAP_DISTANCE := 6.0
const FOLLOW_RATE := 14.0

var peer_id := 0
var entity_id: StringName = &""
var display_name := ""
var model: CharacterModel

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _pitch := 0.0
var _speed := 0.0
var _on_floor := true
var _has_pose := false
var _vehicle: Canoe = null
var _vehicle_xz := Vector2.ZERO
var _vehicle_heading := 0.0
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


func set_pose(pose: Array) -> void:
	_target_pos = pose[0]
	_target_yaw = float(pose[1])
	_pitch = float(pose[2])
	_speed = float(pose[3])
	_on_floor = bool(pose[4])
	_set_vehicle(pose[5] if pose.size() > 5 and pose[5] is Array else [])
	_set_body_state(str(pose[6]) if pose.size() > 6 else "")
	if not _has_pose or global_position.distance_to(_target_pos) > SNAP_DISTANCE:
		global_position = _target_pos
		rotation.y = _target_yaw
	_has_pose = true
	visible = true


func head_position() -> Vector3:
	return global_position + Vector3(0.0, 2.05, 0.0)


func _process(delta: float) -> void:
	if not _has_pose:
		return
	var k := 1.0 - exp(-FOLLOW_RATE * delta)
	global_position = global_position.lerp(_target_pos, k)
	rotation.y = lerp_angle(rotation.y, _target_yaw, k)
	if model.pose == "paddle":
		model.paddle_phase += delta * 4.0
	model.animate(delta, _speed, _on_floor, _pitch)
	if _vehicle != null and is_instance_valid(_vehicle):
		var xz := _vehicle.world_position_2d().lerp(_vehicle_xz, k)
		_vehicle.place_at(xz, -rad_to_deg(lerp_angle(_vehicle.heading, _vehicle_heading, k)))


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
		var canoe := _find_vehicle(StringName(str(v[0])))
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
