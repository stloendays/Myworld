@tool
class_name Cabin
extends Node3D
## A 字形木屋：与室外处于同一世界坐标系的真实建筑。进屋不切场景、不传送、不黑屏。
## 局部坐标：+X 朝湖（正立面 = 三角玻璃窗 + 正门），屋脊沿 X 轴，地板顶面 y = 0。
## 世界位置取自 world_layout.json → cabin（地形在此处有一块压平的地基平台）。
## 灰盒几何均为程序生成；正式美术阶段可以用 Blender 导出的 GLB 替换 Generated 下的可见网格，
## 碰撞与 FrontDoor / 室内区域保持不变。

const GENERATED := "Generated"
const LENGTH := 10.0       ## x: -5 .. 5
const HALF_SPAN := 4.4     ## z: -4.4 .. 4.4（屋檐落在地板边缘）
const RIDGE := 7.0         ## 屋脊高度
const DOOR_HALF := 0.6     ## 门洞 z: -0.6 .. 0.6
const DOOR_H := 2.2
const DECK_DEPTH := 3.0    ## 门廊 x: 5 .. 8
const GROUND_DROP := 0.4   ## 地板比地基平台高 0.4 m（由坡道连接）

var _m: Dictionary = {}


## 必须在子节点进入场景树之前定位：门板 AnimatableBody3D 进树后不会跟随父节点的后续移动。
func _enter_tree() -> void:
	_snap_to_layout()


func _ready() -> void:
	rebuild()


func _snap_to_layout() -> void:
	var cfg := WorldLayout.section("cabin")
	var c := WorldLayout.v2(cfg["center"])
	position = Vector3(c.x, float(cfg["floor_height"]), c.y)
	rotation = Vector3(0.0, deg_to_rad(float(cfg.get("yaw_deg", 0.0))), 0.0)


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var g := Node3D.new()
	g.name = GENERATED
	add_child(g)
	_make_materials()
	var body := StaticBody3D.new()
	body.name = "Structure"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	g.add_child(body)
	_build_floor(g, body)
	_build_roof(g, body)
	_build_gables(g, body)
	_build_deck(g, body)
	_build_interior(g, body)
	_build_lights(g)
	if not Engine.is_editor_hint():
		g.add_child(ZoneArea.create_box(&"cabin_interior", Vector3(9.7, 3.6, 7.8), Vector3(0.0, 1.8, 0.0), true))


func _make_materials() -> void:
	_m = {
		"floor": MeshUtil.material(Color(0.55, 0.37, 0.22), 0.7),
		"lining": MeshUtil.material(Color(0.66, 0.47, 0.29), 0.75),
		"roof": MeshUtil.material(Color(0.17, 0.13, 0.11), 0.9),
		"beam": MeshUtil.material(Color(0.40, 0.25, 0.14), 0.8),
		"frame": MeshUtil.material(Color(0.14, 0.11, 0.09), 0.6),
		"stone": MeshUtil.material(Color(0.36, 0.35, 0.35), 0.95),
		"deck": MeshUtil.material(Color(0.45, 0.31, 0.20), 0.85),
		"fabric": MeshUtil.material(Color(0.62, 0.55, 0.47), 0.95),
		"cushion": MeshUtil.material(Color(0.55, 0.36, 0.25), 0.95),
		"rug": MeshUtil.material(Color(0.84, 0.79, 0.70), 1.0),
		"metal": MeshUtil.material(Color(0.07, 0.07, 0.07), 0.5),
		"fire": MeshUtil.emissive(Color(1.0, 0.45, 0.12), 4.0),
		"lamp": MeshUtil.emissive(Color(1.0, 0.78, 0.5), 1.6),
		"candle": MeshUtil.emissive(Color(1.0, 0.85, 0.6), 1.2),
	}
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.72, 0.82, 0.14)
	glass.roughness = 0.04
	glass.metallic_specular = 0.8
	_m["glass"] = glass


# ---------------------------------------------------------------- 结构

func _build_floor(g: Node3D, body: StaticBody3D) -> void:
	_box(g, body, Vector3(LENGTH, 0.3, HALF_SPAN * 2.0), Vector3(0.0, -0.15, 0.0), _m.floor)
	_box(g, body, Vector3(LENGTH + 0.2, 1.2, HALF_SPAN * 2.0 + 0.2), Vector3(0.0, -0.9, 0.0), _m.stone)


func _build_roof(g: Node3D, body: StaticBody3D) -> void:
	var slope_len := Vector2(HALF_SPAN, RIDGE).length()
	for side in [-1.0, 1.0]:
		var eave := Vector3(0.0, 0.0, side * HALF_SPAN)
		var ridge := Vector3(0.0, RIDGE, 0.0)
		var up_dir := (ridge - eave).normalized()
		var out := Vector3(0.0, HALF_SPAN, side * RIDGE).normalized()
		var basis := Basis(Vector3.RIGHT, up_dir, Vector3.RIGHT.cross(up_dir))
		var mid := (eave + ridge) * 0.5
		_box(g, null, Vector3(LENGTH + 0.1, slope_len, 0.06), mid + out * 0.03, _m.lining, basis)
		_box(g, body, Vector3(LENGTH + 0.8, slope_len + 0.5, 0.22), mid + out * 0.17, _m.roof, basis)
		for x in [-4.6, -2.3, 0.0, 2.3, 4.6]:
			_box(g, null, Vector3(0.16, slope_len, 0.22), mid - out * 0.11 + Vector3(x, 0.0, 0.0), _m.beam, basis)
	for x in [-2.3, 0.0, 2.3]:
		var w := 2.0 * HALF_SPAN * (1.0 - 4.3 / RIDGE)
		_box(g, null, Vector3(0.14, 0.2, w), Vector3(x, 4.3, 0.0), _m.beam)
	_box(g, null, Vector3(LENGTH + 0.8, 0.25, 0.25), Vector3(0.0, RIDGE + 0.1, 0.0), _m.beam)


func _roof_height_at(z: float) -> float:
	return RIDGE * (1.0 - absf(z) / HALF_SPAN)


func _build_gables(g: Node3D, body: StaticBody3D) -> void:
	var front_x := LENGTH * 0.5
	var y_door_edge := _roof_height_at(DOOR_HALF)
	# 正立面：玻璃分三块，中间留门洞（门洞上方为一整块玻璃）。
	var left := PackedVector2Array([Vector2(-HALF_SPAN, 0.0), Vector2(-DOOR_HALF, 0.0), Vector2(-DOOR_HALF, y_door_edge)])
	var right := PackedVector2Array([Vector2(DOOR_HALF, 0.0), Vector2(HALF_SPAN, 0.0), Vector2(DOOR_HALF, y_door_edge)])
	var top := PackedVector2Array([Vector2(-DOOR_HALF, DOOR_H), Vector2(DOOR_HALF, DOOR_H),
		Vector2(DOOR_HALF, y_door_edge), Vector2(0.0, RIDGE), Vector2(-DOOR_HALF, y_door_edge)])
	for poly in [left, right, top]:
		_prism(g, body, poly, front_x, 0.06, _m.glass)
	# 窗框
	for z in [-(DOOR_HALF + 0.06), DOOR_HALF + 0.06]:
		_box(g, null, Vector3(0.16, y_door_edge, 0.12), Vector3(front_x, y_door_edge * 0.5, z), _m.frame)
	for z in [-2.4, 2.4]:
		var h := _roof_height_at(z)
		_box(g, null, Vector3(0.16, h, 0.12), Vector3(front_x, h * 0.5, z), _m.frame)
	for y: float in [DOOR_H + 0.05, 4.5]:
		var w := 2.0 * HALF_SPAN * (1.0 - y / RIDGE)
		_box(g, null, Vector3(0.16, 0.12, w), Vector3(front_x, y, 0.0), _m.frame)
	_box(g, null, Vector3(0.18, 0.1, HALF_SPAN * 2.0), Vector3(front_x, 0.05, 0.0), _m.frame)
	# 背立面：整块木墙
	var back := PackedVector2Array([Vector2(-HALF_SPAN, 0.0), Vector2(HALF_SPAN, 0.0), Vector2(0.0, RIDGE)])
	_prism(g, body, back, -LENGTH * 0.5, 0.18, _m.lining)


func _build_deck(g: Node3D, body: StaticBody3D) -> void:
	var x0 := LENGTH * 0.5
	_box(g, body, Vector3(DECK_DEPTH, 0.25, 6.0), Vector3(x0 + DECK_DEPTH * 0.5, -0.125, 0.0), _m.deck)
	_box(g, null, Vector3(DECK_DEPTH, GROUND_DROP + 0.4, 6.0), Vector3(x0 + DECK_DEPTH * 0.5, -0.45 - GROUND_DROP * 0.5, 0.0), _m.stone)
	# 坡道：门廊边缘 (x=8, y=0) 斜向下，末端埋入地面，保证与地面无台阶。
	var run := 3.6
	var drop := GROUND_DROP + 0.12
	var angle := atan2(drop, run)
	var basis := Basis(Vector3.BACK, -angle)
	var top_mid := Vector3(x0 + DECK_DEPTH + run * 0.5, -drop * 0.5, 0.0)
	var normal := basis * Vector3.UP
	_box(g, body, Vector3(Vector2(run, drop).length(), 0.2, 2.2), top_mid - normal * 0.1, _m.deck, basis)
	# 门廊灯柱
	_box(g, null, Vector3(0.12, 2.6, 0.12), Vector3(x0 + 0.15, 1.3, 1.25), _m.beam)
	_box(g, null, Vector3(0.18, 0.26, 0.18), Vector3(x0 + 0.3, 2.45, 1.25), _m.lamp)


# ---------------------------------------------------------------- 室内

func _build_interior(g: Node3D, body: StaticBody3D) -> void:
	_box(g, null, Vector3(3.2, 0.02, 2.4), Vector3(0.6, 0.011, 0.5), _m.rug)
	# 茶几 + 蜡烛
	_box(g, null, Vector3(1.1, 0.06, 0.6), Vector3(0.6, 0.42, 0.4), _m.beam)
	for lx in [0.12, 1.08]:
		for lz in [0.15, 0.65]:
			_box(g, null, Vector3(0.06, 0.39, 0.06), Vector3(lx, 0.195, lz), _m.beam)
	_collider(body, Vector3(1.1, 0.45, 0.6), Vector3(0.6, 0.225, 0.4))
	for c in [Vector3(0.45, 0.5, 0.35), Vector3(0.62, 0.52, 0.45), Vector3(0.78, 0.49, 0.3)]:
		_box(g, null, Vector3(0.07, (c.y - 0.45) * 2.0, 0.07), Vector3(c.x, c.y, c.z), _m.candle)
	# 沙发（面向 -Z，背靠右侧斜墙）
	_box(g, body, Vector3(2.4, 0.42, 0.9), Vector3(0.6, 0.21, 2.4), _m.fabric)
	_box(g, null, Vector3(2.4, 0.55, 0.22), Vector3(0.6, 0.62, 2.88), _m.fabric)
	for ax in [-0.6, 1.8]:
		_box(g, null, Vector3(0.22, 0.62, 0.9), Vector3(ax, 0.31, 2.4), _m.fabric)
	for cx in [0.1, 1.1]:
		_box(g, null, Vector3(0.5, 0.4, 0.16), Vector3(cx, 0.62, 2.7), _m.cushion, Basis(Vector3.RIGHT, 0.25))
	_collider(body, Vector3(2.65, 0.85, 1.0), Vector3(0.6, 0.425, 2.45))
	# 书架（左侧斜墙下）
	_box(g, body, Vector3(2.0, 1.5, 0.35), Vector3(-1.6, 0.75, -3.05), _m.beam)
	var book_colors := [Color(0.45, 0.16, 0.12), Color(0.18, 0.28, 0.35), Color(0.62, 0.52, 0.32), Color(0.2, 0.3, 0.2)]
	for shelf in 3:
		var bx := -2.5
		var i := 0
		while bx < -0.75:
			var w := 0.06 + 0.04 * float((i * 7) % 3)
			var h := 0.26 + 0.04 * float((i * 5) % 3)
			_box(g, null, Vector3(w, h, 0.24), Vector3(bx + w * 0.5, 0.15 + shelf * 0.45 + h * 0.5, -2.86), MeshUtil.material(book_colors[i % 4], 0.8))
			bx += w + 0.015
			i += 1
	# 铸铁炉 + 烟囱 + 石质炉台
	var stove := Vector3(-3.9, 0.0, -1.0)
	_box(g, null, Vector3(1.5, 0.05, 1.3), stove + Vector3(0.1, 0.025, 0.0), _m.stone)
	_box(g, null, Vector3(0.55, 0.18, 0.42), stove + Vector3(0.0, 0.14, 0.0), _m.metal)
	_box(g, null, Vector3(0.7, 0.72, 0.56), stove + Vector3(0.0, 0.59, 0.0), _m.metal)
	_box(g, null, Vector3(0.02, 0.34, 0.42), stove + Vector3(0.36, 0.6, 0.0), _m.fire)
	_collider(body, Vector3(0.75, 0.95, 0.6), stove + Vector3(0.0, 0.475, 0.0))
	var flue := CylinderMesh.new()
	flue.top_radius = 0.09
	flue.bottom_radius = 0.09
	flue.height = 6.4
	flue.radial_segments = 10
	flue.material = _m.metal
	var flue_mi := MeshInstance3D.new()
	flue_mi.mesh = flue
	flue_mi.position = stove + Vector3(0.0, 0.95 + 3.2, 0.0)
	g.add_child(flue_mi)
	# 落地灯
	var lamp := Vector3(2.3, 0.0, 2.55)
	_box(g, null, Vector3(0.3, 0.03, 0.3), lamp + Vector3(0.0, 0.015, 0.0), _m.metal)
	_box(g, null, Vector3(0.04, 1.4, 0.04), lamp + Vector3(0.0, 0.72, 0.0), _m.metal)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.15
	shade.bottom_radius = 0.24
	shade.height = 0.3
	shade.radial_segments = 12
	shade.material = _m.lamp
	var shade_mi := MeshInstance3D.new()
	shade_mi.mesh = shade
	shade_mi.position = lamp + Vector3(0.0, 1.5, 0.0)
	g.add_child(shade_mi)


func _build_lights(g: Node3D) -> void:
	_omni(g, Vector3(2.3, 1.45, 2.55), Color(1.0, 0.72, 0.45), 1.6, 6.5, false)
	_omni(g, Vector3(-3.4, 0.65, -1.0), Color(1.0, 0.5, 0.2), 2.2, 6.0, true)
	_omni(g, Vector3(0.0, 3.4, 0.0), Color(1.0, 0.78, 0.55), 0.5, 7.5, false)
	_omni(g, Vector3(LENGTH * 0.5 + 0.5, 2.4, 1.25), Color(1.0, 0.7, 0.42), 1.3, 7.0, false)


# ---------------------------------------------------------------- 工具

func _box(parent: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material, basis := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	if body != null:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = mi.transform
		body.add_child(cs)


func _collider(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _prism(parent: Node3D, body: StaticBody3D, poly: PackedVector2Array, x_center: float, thickness: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshUtil.add_prism_x(st, poly, x_center, thickness)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	var shape := ConvexPolygonShape3D.new()
	shape.points = MeshUtil.prism_x_points(poly, x_center, thickness)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	parent.add_child(light)
