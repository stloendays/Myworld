@tool
class_name Cabin
extends Node3D
## A 字形木屋：与室外处于同一世界坐标系的真实建筑。进屋不切场景、不传送、不黑屏。
## 局部坐标：+X 朝湖（正立面 = 三角玻璃窗 + 正门），屋脊沿 X 轴，地板顶面 y = 0。
## 世界位置取自 world_layout.json → cabin（地形在此处有一块压平的地基平台）。
## 外观：Blender 生成的 cabin_aframe.glb（devtools/blender/build_cabin.py）+ Kenney 家具（CC0），
## 材质按名称替换为 Poly Haven PBR 材质（ArtMaterials）。碰撞在这里单独生成，与模型尺寸一致。

const GENERATED := "Generated"
const CABIN_MODEL := preload("res://assets/imported/cabin/cabin_aframe.glb")
const FURNITURE := "res://assets/imported/kenney/furniture/"
const NATURE := "res://assets/imported/kenney/nature/"
const LENGTH := 10.0       ## x: -5 .. 5
const HALF_SPAN := 4.4     ## z: -4.4 .. 4.4（屋檐落在地板边缘）
const RIDGE := 7.0         ## 屋脊高度
const DOOR_HALF := 0.6     ## 门洞 z: -0.6 .. 0.6
const DOOR_H := 2.2
const DECK_DEPTH := 3.0    ## 门廊 x: 5 .. 8
const GROUND_DROP := 0.4   ## 地板比地基平台高 0.4 m（由坡道连接）

## 摆件：asset、中心点（局部 x, y, z，y 为底面高度）、朝向（度，0 = 正面朝 +Z）、缩放。
const PROPS := [
	{"asset": "loungeSofaCorner", "center": [0.78, 0.0, 2.03], "yaw": 180.0, "scale": 2.3},
	{"asset": "tableCoffee", "center": [1.35, 0.0, 1.3], "yaw": 0.0, "scale": 2.0},
	{"asset": "rugRectangle", "center": [1.2, 0.005, 1.45], "yaw": 0.0, "scale": 2.0},
	{"asset": "lampRoundTable", "center": [1.75, 0.47, 1.35], "yaw": 0.0, "scale": 1.6},
	{"asset": "pillowLong", "center": [1.1, 0.48, 2.85], "yaw": 180.0, "scale": 2.3},
	{"asset": "pillow", "center": [0.15, 0.48, 1.9], "yaw": 90.0, "scale": 2.3},
	{"asset": "bookcaseOpen", "center": [-1.95, 0.0, -2.98], "yaw": 0.0, "scale": 1.8},
	{"asset": "bookcaseOpen", "center": [-1.2, 0.0, -2.98], "yaw": 0.0, "scale": 1.8},
	{"asset": "books", "center": [-2.05, 0.03, -2.95], "yaw": 0.0, "scale": 2.4},
	{"asset": "books", "center": [-1.85, 0.42, -2.95], "yaw": 180.0, "scale": 2.4},
	{"asset": "books", "center": [-2.0, 0.81, -2.95], "yaw": 0.0, "scale": 2.4},
	{"asset": "books", "center": [-1.3, 0.03, -2.95], "yaw": 180.0, "scale": 2.4},
	{"asset": "books", "center": [-1.1, 0.42, -2.95], "yaw": 0.0, "scale": 2.4},
	{"asset": "books", "center": [-1.25, 1.2, -2.95], "yaw": 180.0, "scale": 2.4},
	{"asset": "lampSquareFloor", "center": [2.35, 0.0, 2.6], "yaw": 0.0, "scale": 1.9},
	{"asset": "bedDouble", "center": [-3.77, 0.0, 2.08], "yaw": 90.0, "scale": 2.0},
	{"asset": "loungeChairRelax", "center": [-2.4, 0.0, 0.6], "yaw": -110.0, "scale": 2.0},
	{"asset": "sideTable", "center": [3.9, 0.0, -2.55], "yaw": 0.0, "scale": 2.0},
	{"asset": "radio", "center": [3.9, 0.76, -2.55], "yaw": 0.0, "scale": 1.8},
	{"asset": "pottedPlant", "center": [4.2, 0.0, 2.75], "yaw": 30.0, "scale": 2.2},
	{"asset": "rugDoormat", "center": [6.1, 0.005, 0.0], "yaw": 90.0, "scale": 2.4},
	{"asset": "bench", "center": [6.4, 0.0, -2.2], "yaw": 90.0, "scale": 2.2},
	{"asset": "log_stack", "center": [-5.9, -0.4, 2.6], "yaw": 0.0, "scale": 3.0, "nature": true},
	{"asset": "log_stack", "center": [-5.9, -0.4, 1.4], "yaw": 0.0, "scale": 3.0, "nature": true},
]


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
	var model := CABIN_MODEL.instantiate()
	model.name = "Model"
	ArtMaterials.restyle_named(model)
	g.add_child(model)
	for prop in PROPS:
		g.add_child(_prop(prop))
	var lights := _build_lights(g)
	if Engine.is_editor_hint():
		return
	# 木屋生活：炉火、灯的开关、座位、床（运行时）
	var life := CabinLife.new()
	life.name = "Life"
	g.add_child(life)
	life.setup(lights, model)
	var body := StaticBody3D.new()
	body.name = "Structure"
	body.set_meta("surface", "wood")
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	g.add_child(body)
	_build_collision(body)
	g.add_child(ZoneArea.create_box(&"cabin_interior", Vector3(9.7, 3.6, 7.8), Vector3(0.0, 1.8, 0.0), true))
	# 屋内的落叶挡板：A 字形内接矩形（半高处宽度正好是半跨），两侧屋面另有挡板
	g.add_child(Precipitation.leaf_blocker(Vector3(LENGTH, RIDGE * 0.5, HALF_SPAN), Transform3D(Basis(), Vector3(0.0, RIDGE * 0.25, 0.0))))


func _prop(prop: Dictionary) -> Node3D:
	var path := (NATURE if prop.get("nature", false) else FURNITURE) + str(prop["asset"]) + ".glb"
	var c := Vector3(float(prop["center"][0]), float(prop["center"][1]), float(prop["center"][2]))
	return ArtMaterials.kenney_prop(path, c, float(prop["yaw"]), float(prop["scale"]))

func _build_lights(g: Node3D) -> Dictionary:
	return {
		"floor_lamp": _omni(g, Vector3(2.35, 1.5, 2.6), Color(1.0, 0.72, 0.45), 1.6, 6.5, false),
		"table_lamp": _omni(g, Vector3(1.75, 0.85, 1.35), Color(1.0, 0.75, 0.48), 0.6, 3.0, false),
		"stove": _omni(g, Vector3(-3.4, 0.65, -1.0), Color(1.0, 0.5, 0.2), 2.4, 6.5, true),
		"ceiling": _omni(g, Vector3(0.0, 3.4, 0.0), Color(1.0, 0.78, 0.55), 0.45, 7.5, false),
		"porch": _omni(g, Vector3(LENGTH * 0.5 + 0.55, 2.4, 1.25), Color(1.0, 0.7, 0.42), 1.3, 7.0, false),
	}


# ---------------------------------------------------------------- 碰撞（与 GLB 几何一致）

func _build_collision(body: StaticBody3D) -> void:
	var slope_len := Vector2(HALF_SPAN, RIDGE).length()
	# 地板与石基
	_solid(body, Vector3(LENGTH, 0.3, HALF_SPAN * 2.0), Vector3(0.0, -0.15, 0.0))
	_solid(body, Vector3(LENGTH + 0.2, 1.2, HALF_SPAN * 2.0 + 0.2), Vector3(0.0, -0.9, 0.0))
	# 两侧屋面
	for side: float in [-1.0, 1.0]:
		var eave := Vector3(0.0, 0.0, side * HALF_SPAN)
		var ridge := Vector3(0.0, RIDGE, 0.0)
		var up_dir := (ridge - eave).normalized()
		var out := Vector3(0.0, HALF_SPAN, side * RIDGE).normalized()
		var basis := Basis(Vector3.RIGHT, up_dir, Vector3.RIGHT.cross(up_dir))
		_solid(body, Vector3(LENGTH + 0.8, slope_len + 0.5, 0.22), (eave + ridge) * 0.5 + out * 0.17, basis)
		if not Engine.is_editor_hint():
			body.get_parent().add_child(Precipitation.leaf_blocker(Vector3(LENGTH + 0.8, slope_len + 0.5, 0.6), Transform3D(basis, (eave + ridge) * 0.5 + out * 0.3)))
	# 正立面玻璃（门洞留空）与背墙
	var front_x := LENGTH * 0.5
	var y_edge := RIDGE * (1.0 - DOOR_HALF / HALF_SPAN)
	_convex(body, PackedVector2Array([Vector2(-HALF_SPAN, 0.0), Vector2(-DOOR_HALF, 0.0), Vector2(-DOOR_HALF, y_edge)]), front_x, 0.06)
	_convex(body, PackedVector2Array([Vector2(DOOR_HALF, 0.0), Vector2(HALF_SPAN, 0.0), Vector2(DOOR_HALF, y_edge)]), front_x, 0.06)
	_convex(body, PackedVector2Array([Vector2(-DOOR_HALF, DOOR_H), Vector2(DOOR_HALF, DOOR_H),
		Vector2(DOOR_HALF, y_edge), Vector2(0.0, RIDGE), Vector2(-DOOR_HALF, y_edge)]), front_x, 0.06)
	_convex(body, PackedVector2Array([Vector2(-HALF_SPAN, 0.0), Vector2(HALF_SPAN, 0.0), Vector2(0.0, RIDGE)]), -LENGTH * 0.5, 0.18)
	# 门廊与坡道
	_solid(body, Vector3(DECK_DEPTH, 0.25, 6.0), Vector3(front_x + DECK_DEPTH * 0.5, -0.125, 0.0))
	var run := 3.6
	var drop := GROUND_DROP + 0.12
	var ramp_basis := Basis(Vector3.BACK, -atan2(drop, run))
	var top_mid := Vector3(front_x + DECK_DEPTH + run * 0.5, -drop * 0.5, 0.0)
	_solid(body, Vector3(Vector2(run, drop).length(), 0.2, 2.2), top_mid - (ramp_basis * Vector3.UP) * 0.1, ramp_basis)
	# 家具：L 形沙发、茶几、书架、扶手椅、铸铁炉
	_solid(body, Vector3(2.25, 0.9, 0.92), Vector3(0.78, 0.45, 2.69))
	_solid(body, Vector3(0.92, 0.9, 1.33), Vector3(0.11, 0.45, 1.57))
	_solid(body, Vector3(1.32, 0.5, 0.8), Vector3(1.35, 0.25, 1.3))
	_solid(body, Vector3(1.5, 1.6, 0.45), Vector3(-1.58, 0.8, -2.98))
	_solid(body, Vector3(1.0, 0.9, 1.0), Vector3(-2.4, 0.45, 0.6))
	_solid(body, Vector3(0.75, 1.05, 0.6), Vector3(-3.9, 0.52, -1.0))
	_solid(body, Vector3(2.25, 0.75, 1.9), Vector3(-3.77, 0.375, 2.08))   # 床


func _solid(body: StaticBody3D, size: Vector3, pos: Vector3, basis := Basis()) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, pos)
	body.add_child(cs)


func _convex(body: StaticBody3D, poly: PackedVector2Array, x_center: float, thickness: float) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = MeshUtil.prism_x_points(poly, x_center, thickness)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	parent.add_child(light)
	return light
