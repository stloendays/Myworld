class_name RelicAltar
extends Interactable
## 琥珀沙丘阶梯神殿顶上的祭坛：带着捡到的古代碎片走到跟前按 E，把碎片一块块嵌回石盘（状态 "placed:N" 按 uid 存档）。
## 嵌满 need 块时神殿升起一道金色光柱（World03 处理），以后读档、换世界回来光柱都还在。

signal completed

var need := 6
var placed := 0
var world_id := "world_03"
var _slots: Array[MeshInstance3D] = []
var _empty: Material
var _full: Material


static func create(id: StringName, slots: int) -> RelicAltar:
	var a := RelicAltar.new()
	a.name = "Altar"
	a.uid = id
	a.display_name = "祭坛"
	a.need = slots
	a._build()
	return a


func _build() -> void:
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.98, 0.8, 0.6), "world")
	_empty = ArtMaterials.flat(Color(0.32, 0.24, 0.18), 0.9)
	_full = ArtMaterials.glow(Color(1.0, 0.72, 0.32), 2.6)
	_box(Vector3(2.2, 0.5, 2.2), Vector3(0.0, 0.25, 0.0), stone)
	_box(Vector3(1.4, 0.6, 1.4), Vector3(0.0, 0.8, 0.0), stone)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.8
	cm.height = 0.12
	disc.mesh = cm
	disc.material_override = stone
	disc.position = Vector3(0.0, 1.16, 0.0)
	add_child(disc)
	for i in need:
		var ang := float(i) / need * TAU
		var slot := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.18, 0.3, 0.1)
		slot.mesh = pm
		slot.material_override = _empty
		slot.position = Vector3(cos(ang) * 0.5, 1.33, sin(ang) * 0.5)
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slot)
		_slots.append(slot)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.4, 2.2)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(cs)
	add_child(body)


## 身上带着、还没放上去的碎片数。
func carried() -> int:
	return maxi(WorldState.collected(world_id).size() - placed, 0)


func is_complete() -> bool:
	return placed >= need


func get_prompt(_actor: Node) -> String:
	if is_complete():
		return "神殿之光已经点亮"
	if carried() > 0:
		return TranslationServer.translate("E  放上古代碎片（带着 %d 块）") % carried()
	return TranslationServer.translate("祭坛上有 %d / %d 块碎片，去沙丘里找找") % [placed, need]


func can_interact(_actor: Node) -> bool:
	return not is_complete() and carried() > 0


func interact(_actor: Node) -> void:
	var n := carried()
	if n <= 0 or is_complete():
		return
	_set_placed(mini(placed + n, need))
	_publish_state()
	EventBus.toast_requested.emit(TranslationServer.translate("嵌回了 %d 块碎片（%d / %d）") % [n, placed, need])


func _set_placed(n: int) -> void:
	var was := is_complete()
	placed = n
	for i in _slots.size():
		_slots[i].material_override = _full if i < placed else _empty
	if is_complete() and not was:
		completed.emit()


func get_state() -> String:
	return "placed:%d" % placed


func apply_state(state: String) -> void:
	if state.begins_with("placed:"):
		_set_placed(int(state.get_slice(":", 1)))


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
