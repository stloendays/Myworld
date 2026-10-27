@tool
class_name DockBuilder
extends Node3D
## 木质码头：从湖岸平台延伸入水，可行走。码头入水段两侧与末端有栏杆（碰撞略高于可见栏杆，
## 防止跳过），因为 MVP 不允许深水游泳。

const GENERATED := "Generated"
const PLANK_PITCH := 0.3
const PILE_SPACING := 3.0
const RAIL_HEIGHT := 1.0
const RAIL_COLLISION_HEIGHT := 1.45


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)

	var cfg := WorldLayout.section("dock")
	var a := WorldLayout.v2(cfg["from"])
	var b := WorldLayout.v2(cfg["to"])
	var width := float(cfg["width"])
	var top := float(cfg["deck_height"])
	var rail_x := float(cfg.get("rail_start_x", a.x))
	var length := b.x - a.x
	var z := a.y
	var wood := ArtMaterials.snowable(ArtMaterials.pbr("weathered_planks", Color(1.0, 0.9, 0.8), "world"))
	var wood_dark := ArtMaterials.pbr("stained_pine", Color(0.45, 0.33, 0.27), "world")

	# 甲板木板（MultiMesh）
	var plank := BoxMesh.new()
	plank.size = Vector3(PLANK_PITCH - 0.03, 0.07, width)
	plank.material = wood
	var count := int(length / PLANK_PITCH)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plank
	mm.instance_count = count
	for i in count:
		var x := a.x + (float(i) + 0.5) * PLANK_PITCH
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, top - 0.035, z)))
	var planks := MultiMeshInstance3D.new()
	planks.name = "Planks"
	planks.multimesh = mm
	root.add_child(planks)

	# 纵梁
	for side in [-1.0, 1.0]:
		_box(root, Vector3(length, 0.18, 0.16), Vector3(a.x + length * 0.5, top - 0.16, z + side * (width * 0.5 - 0.2)), wood_dark)

	# 桩与栏杆柱
	var x := a.x + 1.0
	while x <= b.x + 0.01:
		var railed := x >= rail_x
		for side in [-1.0, 1.0]:
			var y_top := top + (RAIL_HEIGHT if railed else 0.0)
			var y_bot := -4.0
			var pile := CylinderMesh.new()
			pile.top_radius = 0.1
			pile.bottom_radius = 0.12
			pile.height = y_top - y_bot
			pile.radial_segments = 8
			pile.material = wood_dark
			var mi := MeshInstance3D.new()
			mi.mesh = pile
			mi.position = Vector3(x, (y_top + y_bot) * 0.5, z + side * (width * 0.5 + 0.02))
			root.add_child(mi)
		x += PILE_SPACING

	# 可见栏杆横木
	var rail_len := b.x - rail_x
	for side in [-1.0, 1.0]:
		for h in [RAIL_HEIGHT - 0.05, RAIL_HEIGHT * 0.5]:
			_box(root, Vector3(rail_len, 0.07, 0.07), Vector3(rail_x + rail_len * 0.5, top + h, z + side * (width * 0.5 + 0.02)), wood)
	_box(root, Vector3(0.07, 0.07, width), Vector3(b.x, top + RAIL_HEIGHT - 0.05, z), wood)

	_add_canoe(root)

	if Engine.is_editor_hint():
		return
	var body := StaticBody3D.new()
	body.name = "DockCollision"
	body.set_meta("surface", "wood")
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	root.add_child(body)
	_shape(body, Vector3(length, 0.25, width), Vector3(a.x + length * 0.5, top - 0.125, z))
	for side in [-1.0, 1.0]:
		_shape(body, Vector3(rail_len, RAIL_COLLISION_HEIGHT, 0.12),
			Vector3(rail_x + rail_len * 0.5, top + RAIL_COLLISION_HEIGHT * 0.5, z + side * (width * 0.5 + 0.02)))
	_shape(body, Vector3(0.12, RAIL_COLLISION_HEIGHT, width), Vector3(b.x, top + RAIL_COLLISION_HEIGHT * 0.5, z))


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


## 停在码头南侧水面上的独木舟（可以划，见 Canoe.gd）；位置在 world_layout.json → canoe。只在运行时生成。
func _add_canoe(root: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	var canoe := Canoe.new()
	canoe.name = "Canoe"
	canoe.uid = &"lake_canoe"
	canoe.display_name = "独木舟"
	root.add_child(canoe)
