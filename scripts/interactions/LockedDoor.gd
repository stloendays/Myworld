class_name LockedDoor
extends Interactable
## 锁着的门（石头小屋）：准星对着它会提示“门锁着”，按 E 只弹一句话。状态固定为 "locked"。

static func create(id: StringName, size: Vector3) -> LockedDoor:
	var d := LockedDoor.new()
	d.name = "LockedDoor"
	d.uid = id
	d.display_name = "锁着的门"
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	d.add_child(body)
	return d


func get_prompt(_actor: Node) -> String:
	return "门锁着"


func interact(_actor: Node) -> void:
	EventBus.toast_requested.emit(tr("门锁着，屋里暂时进不去。"))


func get_state() -> String:
	return "locked"
