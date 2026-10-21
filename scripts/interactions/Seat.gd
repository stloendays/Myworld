class_name Seat
extends Interactable
## 可以坐下的位置：沙发、扶手椅、门廊长椅、泳池躺椅、水族馆长椅。
## 本节点原点 = 坐垫表面中心（臀部位置），-Z = 坐着时面朝的方向（摆件朝向 + 180°）。
## 按 E 坐下：玩家关掉碰撞、定在这里、腿向前伸；再按 E 或任意移动键站起，落在座位前方的地面上。
## 交互盒比坐垫高出一截，准星从上方看过来时先命中它，而不是家具本身的碰撞体。

@export var hip_height := 0.45   ## 坐垫离地高度（站起时落回地面用）

var occupant: Node = null


static func create(id: StringName, label: String, hip_pos: Vector3, yaw_deg: float, hip := 0.45, width := 0.7) -> Seat:
	var s := Seat.new()
	s.name = "Seat_" + String(id)
	s.uid = id
	s.display_name = label
	s.hip_height = hip
	s.position = hip_pos
	s.rotation.y = deg_to_rad(yaw_deg)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.6, 0.6)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.25, 0.05)
	body.add_child(cs)
	s.add_child(body)
	return s


func get_prompt(_actor: Node) -> String:
	return "E  坐下" if occupant == null else ""


func can_interact(actor: Node) -> bool:
	return occupant == null and actor.has_method("sit")


func interact(actor: Node) -> void:
	actor.sit(self)


func get_state() -> String:
	return "occupied" if occupant != null else "free"


## 站起来落脚的位置：座位正前方 0.75 m 的地面。
func exit_point() -> Vector3:
	return global_transform * Vector3(0.0, -hip_height + 0.05, -0.75)


## 坐着时角色原点（脚底）的位置：臀部对准坐垫，模型臀高 12 像素。
func occupant_origin() -> Vector3:
	return global_position - Vector3(0.0, 12.0 * Wardrobe.px(), 0.0)
