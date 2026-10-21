class_name FairyPortal
extends Interactable
## 仙境林地尽头的月光石门：看着门面按 E“走进传送门”。目标世界写在 world_layout.json → fairy_glade.portal.world，
## 进不进得去由 WorldRegistry 决定（目前其他世界都在建设中，只会提示）。门只在仙境出现的夜里能用。

var target_world := ""


static func create(id: StringName, world_id: String, size: Vector2) -> FairyPortal:
	var p := FairyPortal.new()
	p.name = "Portal"
	p.uid = id
	p.display_name = "传送门"
	p.target_world = world_id
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.2)
	cs.shape = shape
	body.add_child(cs)
	p.add_child(body)
	return p


func get_prompt(_actor: Node) -> String:
	return "E  走进传送门"


func interact(_actor: Node) -> void:
	WorldRegistry.enter(target_world)
