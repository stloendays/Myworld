class_name CookPot
extends Interactable
## 炉火上的铁锅（木屋铸铁炉顶上、琥珀沙丘驼队营地的篝火上）：看着它按 E 打开烹饪面板（CookingPanel），
## 用钓到的鱼做烤鱼 / 鱼汤 / 海鲜拼盘，做好就吃，得到一段时间的效果。fire 不为空时要先把那堆火生起来。

var fire: InteractableToggle = null


static func create(id: StringName, at: Vector3, fire_toggle: InteractableToggle = null) -> CookPot:
	var p := CookPot.new()
	p.name = "CookPot_" + String(id)
	p.uid = id
	p.display_name = "铁锅"
	p.position = at
	p.fire = fire_toggle
	p._build()
	return p


func _build() -> void:
	var iron := ArtMaterials.flat(Color(0.16, 0.15, 0.15), 0.55, false, 0.6)
	var pot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.18
	cm.height = 0.22
	pot.mesh = cm
	pot.material_override = iron
	pot.position = Vector3(0.0, 0.11, 0.0)
	add_child(pot)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.23
	handle.mesh = tm
	handle.material_override = iron
	handle.rotation.z = PI * 0.5
	handle.position = Vector3(0.0, 0.22, 0.0)
	add_child(handle)
	var soup := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.21
	dm.bottom_radius = 0.21
	dm.height = 0.01
	soup.mesh = dm
	soup.material_override = ArtMaterials.flat(Color(0.75, 0.55, 0.3), 0.3)
	soup.position = Vector3(0.0, 0.2, 0.0)
	add_child(soup)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.4, 0.6)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.2, 0.0)
	body.add_child(cs)
	add_child(body)


func fire_lit() -> bool:
	return fire == null or fire.on


func get_prompt(_actor: Node) -> String:
	return "E  做饭（用钓到的鱼）" if fire_lit() else "先把炉火生起来，才能做饭"


func interact(actor: Node) -> void:
	var why := Play.blocked("cooking")
	if why != "":
		EventBus.toast_requested.emit(why)
		return
	if not fire_lit():
		EventBus.toast_requested.emit(tr("先把炉火生起来（看着铸铁炉按 E）"))
		return
	var panel := get_tree().get_first_node_in_group("cooking_panel") as CookingPanel
	if panel != null:
		panel.open(actor as FirstPersonController)
