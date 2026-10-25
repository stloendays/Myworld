class_name MantaHandle
extends Interactable
## 亚特兰蒂斯大蝠鲼背上的“把手”：看着蝠鲼按 E 抓住它（RailRide 带着绕城一圈）。碰撞盒罩住蝠鲼的背。

var ride: RailRide = null


func _init() -> void:
	name = "Handle"
	uid = &"atl_manta"
	display_name = "大蝠鲼"
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.6, 1.0, 3.0)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.3, 0.0)
	body.add_child(cs)
	add_child(body)


func get_prompt(_actor: Node) -> String:
	return "E  抓住蝠鲼的背" if ride != null and ride.rider == null else ""


func can_interact(_actor: Node) -> bool:
	return ride != null and ride.rider == null


func interact(actor: Node) -> void:
	var p := actor as FirstPersonController
	if p != null and ride.begin(p):
		EventBus.toast_requested.emit(tr("抓住了！蝠鲼带着你游起来了"))
