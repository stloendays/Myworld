class_name StoneCottage
extends Node3D
## 南部草地上的石头小屋（world_layout.json → cottage；地形 pads 里的 cottage_pad 把地压平）：前一位旅人“划船的人”的家。
## 外面：毛石墙、木门（三环转锁，CottageDoor）、三扇玻璃窗、石板坡屋顶、烟囱、门前两级石阶（碰撞是一道缓坡）和一盏挂灯。
## 三封信都读过以后门能打开（PaddlerStory）。屋里：木地板、靠后墙的书桌和椅子、桌上没画完的星图（能看）和台灯（能开关）、
## 靠左墙的床、右墙书架、左墙挂着一把船桨、中间一块地毯。屋里是室内区域 cottage_interior（不下雨）。
## 本地坐标：原点在地面中心，门在 +Z 面（yaw 让门朝向西边的步道），地板顶面 y = FLOOR。

const SIZE := Vector3(6.4, 3.0, 5.2)       ## 墙体外廓（宽、檐口高、深）
const ROOF_RISE := 1.9
const WALL := 0.3                         ## 墙厚
const FLOOR := 0.4                        ## 地板顶面（勒脚平台的高度）
const DOOR := Vector2(1.1, 2.05)
const DOOR_X := -0.9                      ## 门洞中心
const FURNITURE := "res://assets/imported/kenney/furniture/"
## 窗：所在墙（front = +Z、left = -X、right = +X）、沿墙的中心、宽、窗台高、窗高
const WINDOWS := [
	{"wall": "front", "u": 1.55, "w": 1.1, "y": 1.275, "h": 0.95},
	{"wall": "right", "u": 0.6, "w": 1.0, "y": 1.3, "h": 0.9},
	{"wall": "left", "u": -0.4, "w": 1.0, "y": 1.3, "h": 0.9},
]
## 屋里的家具：asset、底面中心（本地 x, y, z）、朝向、缩放
const PROPS := [
	{"asset": "desk", "center": [1.6, FLOOR, -1.89], "yaw": 0.0, "scale": 2.0},
	{"asset": "chairDesk", "center": [1.6, FLOOR, -1.15], "yaw": 180.0, "scale": 1.8},
	{"asset": "lampRoundTable", "center": [2.12, FLOOR + 0.77, -2.02], "yaw": 0.0, "scale": 1.6},
	{"asset": "bedSingle", "center": [-2.31, FLOOR, -1.15], "yaw": 0.0, "scale": 2.0},
	{"asset": "bookcaseOpen", "center": [2.655, FLOOR, 1.55], "yaw": -90.0, "scale": 1.8},
	{"asset": "books", "center": [2.66, FLOOR + 0.42, 1.5], "yaw": -90.0, "scale": 2.4},
	{"asset": "books", "center": [2.66, FLOOR + 1.2, 1.65], "yaw": 90.0, "scale": 2.4},
	{"asset": "rugRectangle", "center": [0.1, FLOOR + 0.005, 0.1], "yaw": 0.0, "scale": 1.5},
]
const CHART := Vector3(1.32, FLOOR + 0.775, -1.86)   ## 桌上星图的中心

var door: CottageDoor = null
var lamp: InteractableToggle = null
var chart: LetterSpot = null
var bed: Bed = null
var seat: Seat = null
var _lamp_light: OmniLight3D = null
var _stone: Material


func _enter_tree() -> void:
	var cfg := WorldLayout.section("cottage")
	var c := WorldLayout.v2(cfg["center"])
	position = Vector3(c.x, WorldTerrain.height_at(c.x, c.y), c.y)
	rotation.y = deg_to_rad(float(cfg.get("yaw_deg", 0.0)))


func _ready() -> void:
	add_to_group("stone_cottage")
	_stone = ArtMaterials.snowable(ArtMaterials.pbr("rustic_stone_wall", Color(0.92, 0.88, 0.82), "world"))
	var trim := ArtMaterials.named("M_Frame")
	var slate := ArtMaterials.named("M_RoofSlate")
	var hw := SIZE.x * 0.5
	var hd := SIZE.z * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	# 勒脚平台 = 地板（比墙略宽一圈），上面铺一层木地板
	_box(Vector3(SIZE.x + 0.3, FLOOR, SIZE.z + 0.3), Vector3(0.0, FLOOR * 0.5, 0.0), _stone)
	_shape(body, Vector3(SIZE.x + 0.3, FLOOR, SIZE.z + 0.3), Vector3(0.0, FLOOR * 0.5, 0.0))
	_box(Vector3(SIZE.x - 2.0 * WALL, 0.02, SIZE.z - 2.0 * WALL), Vector3(0.0, FLOOR + 0.005, 0.0), ArtMaterials.named("M_Floor"))
	# 四面墙：前后墙通长，两侧墙夹在中间；门洞、窗洞处留空
	var front: Array = [Rect2(DOOR_X - DOOR.x * 0.5, FLOOR, DOOR.x, DOOR.y)]
	var left: Array = []
	var right: Array = []
	for w: Dictionary in WINDOWS:
		var r := Rect2(float(w["u"]) - float(w["w"]) * 0.5, float(w["y"]), float(w["w"]), float(w["h"]))
		match str(w["wall"]):
			"front":
				front.append(r)
			"left":
				left.append(r)
			_:
				right.append(r)
	_wall(body, SIZE.x, Vector3(0.0, 0.0, hd - WALL * 0.5), true, front)
	_wall(body, SIZE.x, Vector3(0.0, 0.0, -hd + WALL * 0.5), true, [])
	_wall(body, SIZE.z - 2.0 * WALL, Vector3(-hw + WALL * 0.5, 0.0, 0.0), false, left)
	_wall(body, SIZE.z - 2.0 * WALL, Vector3(hw - WALL * 0.5, 0.0, 0.0), false, right)
	# 山墙：两个三角（前后），用棱柱
	for z: float in [-1.0, 1.0]:
		var gable := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(SIZE.x, ROOF_RISE, 0.4)
		gable.mesh = prism
		gable.material_override = _stone
		gable.position = Vector3(0.0, SIZE.y + ROOF_RISE * 0.5, z * (hd - 0.2))
		add_child(gable)
	# 屋顶两坡
	var slope_len := sqrt(hw * hw + ROOF_RISE * ROOF_RISE) + 0.5
	var angle := atan2(ROOF_RISE, hw)
	for side: float in [-1.0, 1.0]:
		var roof := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(slope_len, 0.16, SIZE.z + 0.9)
		roof.mesh = bm
		roof.material_override = slate
		roof.position = Vector3(side * hw * 0.5, SIZE.y + ROOF_RISE * 0.5 + 0.1, 0.0)
		roof.rotation.z = -side * angle
		add_child(roof)
	_box(Vector3(0.24, 0.24, SIZE.z + 1.0), Vector3(0.0, SIZE.y + ROOF_RISE + 0.12, 0.0), trim)   # 屋脊
	# 烟囱：从屋面上长出来（底面埋在石板下，不伸进屋里），顶到 SIZE.y + 2.5
	_box(Vector3(0.75, 1.75, 0.75), Vector3(hw * 0.5, SIZE.y + 2.5 - 0.875, -hd * 0.35), _stone)
	_box(Vector3(0.9, 0.16, 0.9), Vector3(hw * 0.5, SIZE.y + 2.5, -hd * 0.35), trim)
	# 门框和门（铰链在门洞左边、墙厚中间，向屋里开）
	var top := FLOOR + DOOR.y
	_box(Vector3(DOOR.x + 0.24, 0.12, 0.1), Vector3(DOOR_X, top + 0.06, hd + 0.04), trim)
	for x: float in [-1.0, 1.0]:
		_box(Vector3(0.12, DOOR.y, 0.1), Vector3(DOOR_X + x * (DOOR.x * 0.5 + 0.06), FLOOR + DOOR.y * 0.5, hd + 0.04), trim)
	door = CottageDoor.create(&"cottage_door", DOOR, ArtMaterials.named("M_Door"))
	door.position = Vector3(DOOR_X - DOOR.x * 0.5, FLOOR, hd - WALL * 0.5)
	add_child(door)
	# 门前两级石阶；碰撞是一道 22° 的缓坡（人物没有自动上台阶）
	_box(Vector3(DOOR.x + 0.8, 0.2, 0.5), Vector3(DOOR_X, 0.1, hd + 0.9), _stone)
	_box(Vector3(DOOR.x + 0.8, FLOOR, 0.5), Vector3(DOOR_X, FLOOR * 0.5, hd + 0.4), _stone)
	# 坡顶正好接在平台边缘（不高出地板，否则出门时会被一道棱挡住），多出来的长度埋进地下
	var run := 1.0
	var slope := atan2(FLOOR, run)
	var ramp_len := run / cos(slope) + 0.3
	var upper := Vector3(DOOR_X, FLOOR, hd + 0.15)
	var down := Vector3(0.0, -sin(slope), cos(slope))
	var up := Vector3(0.0, cos(slope), sin(slope))
	_shape(body, Vector3(DOOR.x + 0.8, 0.1, ramp_len), upper + down * ramp_len * 0.5 - up * 0.05, Basis(Vector3.RIGHT, slope))
	# 三扇窗：玻璃嵌在墙洞里，外面一圈木框和窗台
	for w: Dictionary in WINDOWS:
		_window(w, hw, hd, trim)
	# 门边一盏没点的挂灯
	_box(Vector3(0.05, 0.05, 0.35), Vector3(-1.75, 2.45, hd + 0.18), ArtMaterials.named("M_Metal"))
	_box(Vector3(0.22, 0.3, 0.22), Vector3(-1.75, 2.25, hd + 0.33), ArtMaterials.flat(Color(0.25, 0.27, 0.25), 0.4, false, 0.6))
	_build_interior(body)
	add_child(Precipitation.leaf_blocker(Vector3(SIZE.x + 1.0, 0.6, SIZE.z + 1.2), Transform3D(Basis(), Vector3(0.0, SIZE.y + ROOF_RISE * 0.5, 0.0))))
	add_child(ZoneArea.create_box(&"cottage", Vector3(SIZE.x + 6.0, 4.0, SIZE.z + 6.0), Vector3(0.0, 2.0, 0.0), false))
	add_child(ZoneArea.create_box(&"cottage_interior", Vector3(SIZE.x - 2.0 * WALL, 2.6, SIZE.z - 2.0 * WALL), Vector3(0.0, FLOOR + 1.3, 0.0), true))


## 屋里能走到的地面范围（本地 xz），自动检查用。
static func interior_rect() -> Rect2:
	var inner := Vector2(SIZE.x, SIZE.z) * 0.5 - Vector2(WALL, WALL)
	return Rect2(-inner, inner * 2.0)


func is_lamp_on() -> bool:
	return lamp != null and lamp.on


# ---------------------------------------------------------------- 屋里

func _build_interior(body: StaticBody3D) -> void:
	for p: Dictionary in PROPS:
		var c := Vector3(float(p["center"][0]), float(p["center"][1]), float(p["center"][2]))
		add_child(ArtMaterials.kenney_prop(FURNITURE + str(p["asset"]) + ".glb", c, float(p["yaw"]), float(p["scale"])))
	_shape(body, Vector3(1.47, 0.77, 0.78), Vector3(1.6, FLOOR + 0.385, -1.89))       # 书桌
	_shape(body, Vector3(1.14, 0.55, 2.25), Vector3(-2.31, FLOOR + 0.275, -1.15))     # 床
	_shape(body, Vector3(0.45, 1.58, 0.72), Vector3(2.655, FLOOR + 0.79, 1.55))       # 书架
	seat = Seat.create(&"cottage_chair", "椅子", Vector3(1.6, FLOOR + 0.5, -1.2), 0.0)
	add_child(seat)
	bed = Bed.create(&"cottage_bed", Vector3(-2.31, FLOOR, -1.15), Vector3(1.14, 0.75, 2.25), Vector3(1.1, 0.05, 0.0))
	add_child(bed)
	# 桌上那张没画完的星图：用读信界面的 ChartView 画在一张贴图上
	var vp := SubViewport.new()
	vp.name = "ChartViewport"
	vp.size = Vector2i(512, 352)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var view := LetterPanel.ChartView.new()
	view.size = Vector2(512.0, 352.0)
	vp.add_child(view)
	add_child(vp)
	var paper := MeshInstance3D.new()
	paper.name = "StarChart"
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.58, 0.4)
	paper.mesh = pm
	paper.material_override = ArtMaterials.picture(vp.get_texture())
	paper.position = CHART + Vector3(0.0, 0.004, 0.0)
	paper.rotation.y = deg_to_rad(6.0)
	add_child(paper)
	chart = LetterSpot.create("chart", "chart")
	chart.position = CHART
	add_child(chart)
	# 左墙挂着一把船桨（斜挂）
	var paddle := Node3D.new()
	paddle.name = "Paddle"
	paddle.position = Vector3(-SIZE.x * 0.5 + WALL + 0.05, FLOOR + 1.55, 1.25)
	paddle.rotation.x = deg_to_rad(24.0)
	add_child(paddle)
	var wood := ArtMaterials.named("M_Deck")
	_box(Vector3(0.045, 1.25, 0.045), Vector3(0.0, 0.2, 0.0), wood, paddle)
	_box(Vector3(0.04, 0.55, 0.18), Vector3(0.0, -0.66, 0.0), wood, paddle)
	_box(Vector3(0.06, 0.07, 0.14), Vector3(0.0, 0.84, 0.0), wood, paddle)
	_box(Vector3(0.05, 0.06, 0.05), Vector3(-0.02, 0.35, -0.1), ArtMaterials.named("M_Metal"))     # 挂钩
	# 台灯：能开关，亮了从窗外也看得见
	lamp = InteractableToggle.create(&"cottage_lamp", "台灯", false, "E  关台灯", "E  开台灯", Vector3(0.4, 0.6, 0.4), Vector3(0.0, 0.3, 0.0))
	lamp.position = Vector3(2.12, FLOOR + 0.77, -2.02)
	add_child(lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "LampLight"
	_lamp_light.light_color = Color(1.0, 0.78, 0.52)
	_lamp_light.light_energy = 1.6
	_lamp_light.omni_range = 5.0
	_lamp_light.shadow_enabled = true      # 不开阴影光会穿墙，夜里屋外地上一块亮斑
	_lamp_light.position = Vector3(2.12, FLOOR + 1.2, -1.9)
	add_child(_lamp_light)
	lamp.toggled.connect(_on_lamp)
	_on_lamp(lamp.on)


func _on_lamp(on: bool) -> void:
	_lamp_light.visible = on


# ---------------------------------------------------------------- 搭建工具

## 一面墙：沿墙方向 u（-length/2 .. length/2），竖直 v（0 .. 檐口）；openings 是墙面上的洞（Rect2，u 与 v）。
## 按洞的左右边把墙切成竖条，有洞的竖条只补洞的上下两块。
func _wall(body: StaticBody3D, length: float, center: Vector3, along_x: bool, openings: Array) -> void:
	var cuts: Array[float] = [-length * 0.5, length * 0.5]
	for o: Rect2 in openings:
		cuts.append(o.position.x)
		cuts.append(o.end.x)
	cuts.sort()
	for i in cuts.size() - 1:
		var u0 := cuts[i]
		var u1 := cuts[i + 1]
		if u1 - u0 < 0.001:
			continue
		var mid := (u0 + u1) * 0.5
		var spans: Array[Vector2] = [Vector2(0.0, SIZE.y)]
		for o: Rect2 in openings:
			if mid > o.position.x and mid < o.end.x:
				spans = [Vector2(0.0, o.position.y), Vector2(o.end.y, SIZE.y)]
		for s: Vector2 in spans:
			if s.y - s.x < 0.001:
				continue
			var size := Vector3(u1 - u0, s.y - s.x, WALL) if along_x else Vector3(WALL, s.y - s.x, u1 - u0)
			var pos := center + (Vector3(mid, (s.x + s.y) * 0.5, 0.0) if along_x else Vector3(0.0, (s.x + s.y) * 0.5, mid))
			_box(size, pos, _stone)
			_shape(body, size, pos)


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _window(w: Dictionary, hw: float, hd: float, trim: Material) -> void:
	var size := Vector2(float(w["w"]), float(w["h"]))
	var u := float(w["u"])
	var cy := float(w["y"]) + size.y * 0.5
	var node := Node3D.new()
	match str(w["wall"]):
		"front":
			node.transform = Transform3D(Basis(), Vector3(u, cy, hd))
		"right":
			node.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(hw, cy, u))
		_:
			node.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-hw, cy, u))
	add_child(node)
	# 本地 +Z 朝屋外，墙的外表面在 z = 0
	_box(Vector3(size.x, size.y, 0.03), Vector3(0.0, 0.0, -WALL * 0.5), ArtMaterials.glass(), node)
	for y: float in [-1.0, 1.0]:
		_box(Vector3(size.x + 0.16, 0.08, 0.08), Vector3(0.0, y * size.y * 0.5, 0.06), trim, node)
	for x: float in [-1.0, 0.0, 1.0]:
		_box(Vector3(0.07, size.y, 0.07), Vector3(x * size.x * 0.5, 0.0, 0.06), trim, node)
	_box(Vector3(size.x + 0.3, 0.08, 0.22), Vector3(0.0, -size.y * 0.5 - 0.06, 0.1), trim, node)
	_box(Vector3(size.x, 0.05, 0.2), Vector3(0.0, -size.y * 0.5 - 0.02, -WALL + 0.02), trim, node)      # 屋里的窗台


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, pos)
	body.add_child(cs)
