class_name FishSchool
extends Node3D
## 一个水族箱里的水生动物（鱼群、海龟、水母），只在 bounds（世界坐标 AABB）内游动。
## 鱼：随机选目标点，平滑转向游过去；同种鱼共享一个“群目标”，所以会成群结队。
## 海龟：慢慢贴着缸底游；水母：缓慢上浮下沉、一张一缩；蝠鲼在中上层慢慢滑翔；礁鲨在中层巡游。
## 玩家潜进缸里时，离得近（2.2 m）的鱼会散开躲开，过一会儿再游回来。

@export var species_list: Array = []
@export var seed_value := 1
var bounds := AABB(Vector3.ZERO, Vector3.ONE)

var members: Array[Dictionary] = []   ## {node, def, target, speed, group}
var _rng := RandomNumberGenerator.new()
var _group_targets: Dictionary = {}


func _ready() -> void:
	_rng.seed = seed_value
	add_to_group("aquatic_life")
	for sp in species_list:
		var def := FaunaData.species(str(sp))
		if def.is_empty():
			continue
		_group_targets[sp] = _random_point(def)
		for i in int(def.get("school_size", 3)):
			var m := BlockyModel.new()
			m.name = "%s_%d" % [sp, i]
			m.setup(def, FaunaData.palette(def, _rng.randi()))
			add_child(m)
			m.global_position = _random_point(def)
			members.append({"node": m, "def": def, "target": _random_point(def), "speed": float(def.get("speed", 0.6)) * _rng.randf_range(0.8, 1.2), "group": sp})


func _physics_process(delta: float) -> void:
	# 鱼缸在地下：相机离缸 45 m 以外根本看不见，不更新（省 CPU）
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(bounds.get_center()) > 45.0 * 45.0:
		return
	for sp in _group_targets:
		if _rng.randf() < delta * 0.25:
			_group_targets[sp] = _random_point(FaunaData.species(str(sp)))
	var pl := get_tree().get_first_node_in_group("local_player") as Node3D
	var player: Variant = pl.global_position + Vector3(0.0, 0.9, 0.0) if pl != null else null
	for m in members:
		var node: BlockyModel = m["node"]
		var def: Dictionary = m["def"]
		var loco := str(def.get("locomotion", "fish"))
		var pos := node.global_position
		var target: Vector3 = m["target"]
		if loco == "fish":
			target = target.lerp(_group_targets[m["group"]], 0.02)
			m["target"] = target
		var to := target - pos
		if to.length() < 0.25:
			m["target"] = _random_point(def)
			continue
		var speed: float = m["speed"]
		# 躲开潜水的玩家
		if player != null and pos.distance_to(player as Vector3) < 2.2:
			var away: Vector3 = (pos - (player as Vector3)).normalized()
			m["target"] = _clamp(pos + away * 3.0 + Vector3(0.0, _rng.randf_range(-0.5, 0.5), 0.0))
			to = m["target"] - pos
			speed *= 2.2
		var dir := to.normalized()
		if loco == "jelly":
			dir = Vector3(dir.x * 0.3, dir.y, dir.z * 0.3).normalized()
		pos += dir * speed * delta
		node.global_position = _clamp(pos)
		if loco != "jelly":
			var yaw := atan2(-dir.x, -dir.z)
			var turn := {"fish": 3.0, "shark": 1.3, "manta": 0.8}.get(loco, 1.0) as float
			node.rotation.y = lerp_angle(node.rotation.y, yaw, 1.0 - exp(-turn * delta))
		node.animate(delta, speed)


func _random_point(def: Dictionary) -> Vector3:
	var p := bounds.position + Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * bounds.size
	if str(def.get("locomotion")) == "turtle":
		p.y = bounds.position.y + bounds.size.y * _rng.randf_range(0.05, 0.35)
	elif str(def.get("locomotion")) == "manta":
		p.y = bounds.position.y + bounds.size.y * _rng.randf_range(0.45, 0.85)
	elif str(def.get("locomotion")) == "shark":
		p.y = bounds.position.y + bounds.size.y * _rng.randf_range(0.3, 0.7)
	return p


func _clamp(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, bounds.position.x, bounds.end.x),
		clampf(p.y, bounds.position.y, bounds.end.y),
		clampf(p.z, bounds.position.z, bounds.end.z))


## 测试用：所有成员是否都在缸内。
func all_inside() -> bool:
	for m in members:
		if not bounds.grow(0.01).has_point((m["node"] as Node3D).global_position):
			return false
	return true
