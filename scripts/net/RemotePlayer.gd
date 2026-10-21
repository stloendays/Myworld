class_name RemotePlayer
extends Node3D
## 房间里另一位玩家在本机的样子：一个方块人物（CharacterModel，用对方自己的外观），没有碰撞、不读输入。
## 位置和朝向由 Net 收到的姿态驱动，在两次更新之间平滑插值；离得太远（> SNAP_DISTANCE）直接跳过去（对方传送）。

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
	model.animate(delta, _speed, _on_floor, _pitch)


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
