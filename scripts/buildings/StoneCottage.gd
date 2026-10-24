class_name StoneCottage
extends Node3D
## 南部草地上的石头小屋（world_layout.json → cottage；地形 pads 里的 cottage_pad 把地压平）。
## 现在只有外观：毛石墙、木门、两扇暗着的小窗、石板坡屋顶、烟囱、门前一级石阶和一盏没点的挂灯；
## 门锁着（LockedDoor，按 E 只会提示“门锁着”），整栋房子一个碰撞盒，人进不去。以后要做室内时把门换成 InteractableDoor。
## 本地坐标：原点在地面中心，门在 +Z 面（yaw 让门朝向西边的步道）。

const SIZE := Vector3(6.4, 3.0, 5.2)       ## 墙体外廓（宽、檐口高、深）
const ROOF_RISE := 1.9
const DOOR := Vector2(1.1, 2.05)

var door: LockedDoor = null


func _enter_tree() -> void:
	var cfg := WorldLayout.section("cottage")
	var c := WorldLayout.v2(cfg["center"])
	position = Vector3(c.x, WorldTerrain.height_at(c.x, c.y), c.y)
	rotation.y = deg_to_rad(float(cfg.get("yaw_deg", 0.0)))


func _ready() -> void:
	add_to_group("stone_cottage")
	var stone := ArtMaterials.snowable(ArtMaterials.pbr("rustic_stone_wall", Color(0.92, 0.88, 0.82), "world"))
	var trim := ArtMaterials.named("M_Frame")
	var slate := ArtMaterials.named("M_RoofSlate")
	var hw := SIZE.x * 0.5
	var hd := SIZE.z * 0.5
	# 墙：四面实墙（门和窗贴在外面），底下一圈略宽的勒脚
	_box(Vector3(SIZE.x + 0.3, 0.4, SIZE.z + 0.3), Vector3(0.0, 0.2, 0.0), stone)
	_box(SIZE, Vector3(0.0, SIZE.y * 0.5, 0.0), stone)
	# 山墙：两个三角（前后），用棱柱
	for z: float in [-1.0, 1.0]:
		var gable := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(SIZE.x, ROOF_RISE, 0.4)
		gable.mesh = prism
		gable.material_override = stone
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
	# 烟囱
	_box(Vector3(0.75, 2.2, 0.75), Vector3(hw * 0.5, SIZE.y + 1.35, -hd * 0.35), stone)
	_box(Vector3(0.9, 0.16, 0.9), Vector3(hw * 0.5, SIZE.y + 2.5, -hd * 0.35), trim)
	# 门：木门 + 门框 + 门把，前面一级石阶
	_box(Vector3(DOOR.x + 0.24, DOOR.y + 0.14, 0.1), Vector3(-0.9, DOOR.y * 0.5 + 0.4, hd + 0.04), trim)
	var leaf := _box(Vector3(DOOR.x, DOOR.y, 0.08), Vector3(-0.9, DOOR.y * 0.5 + 0.4, hd + 0.1), ArtMaterials.named("M_Door"))
	leaf.name = "DoorLeaf"
	_box(Vector3(0.07, 0.07, 0.08), Vector3(-0.9 + DOOR.x * 0.36, 1.35, hd + 0.17), ArtMaterials.named("M_Metal"))
	_box(Vector3(DOOR.x + 0.8, 0.22, 0.75), Vector3(-0.9, 0.11, hd + 0.45), stone)
	# 两扇窗：深色玻璃 + 木框 + 窗台（屋里没灯）
	for x: float in [1.55]:
		_window(Vector3(x, 1.75, hd + 0.04), Vector2(1.1, 0.95), Basis(), trim)
	_window(Vector3(hw + 0.04, 1.75, 0.6), Vector2(1.0, 0.9), Basis(Vector3.UP, PI * 0.5), trim)
	_window(Vector3(-hw - 0.04, 1.75, -0.4), Vector2(1.0, 0.9), Basis(Vector3.UP, -PI * 0.5), trim)
	# 门边一盏没点的挂灯
	_box(Vector3(0.05, 0.05, 0.35), Vector3(-1.75, 2.45, hd + 0.18), ArtMaterials.named("M_Metal"))
	_box(Vector3(0.22, 0.3, 0.22), Vector3(-1.75, 2.25, hd + 0.33), ArtMaterials.flat(Color(0.25, 0.27, 0.25), 0.4, false, 0.6))
	# 碰撞：整栋一个盒子 + 石阶
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	_shape(body, Vector3(SIZE.x + 0.3, SIZE.y + ROOF_RISE, SIZE.z + 0.3), Vector3(0.0, (SIZE.y + ROOF_RISE) * 0.5, 0.0))
	_shape(body, Vector3(DOOR.x + 0.8, 0.22, 0.75), Vector3(-0.9, 0.11, hd + 0.45))
	add_child(body)
	door = LockedDoor.create(&"cottage_door", Vector3(DOOR.x, DOOR.y, 0.3))
	door.position = Vector3(-0.9, DOOR.y * 0.5 + 0.4, hd + 0.2)
	add_child(door)
	add_child(Precipitation.leaf_blocker(Vector3(SIZE.x + 1.0, 0.6, SIZE.z + 1.2), Transform3D(Basis(), Vector3(0.0, SIZE.y + ROOF_RISE * 0.5, 0.0))))
	add_child(ZoneArea.create_box(&"cottage", Vector3(SIZE.x + 6.0, 4.0, SIZE.z + 6.0), Vector3(0.0, 2.0, 0.0), false))


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _window(center: Vector3, size: Vector2, basis: Basis, trim: Material) -> void:
	var w := Node3D.new()
	w.transform = Transform3D(basis, center)
	add_child(w)
	var glass := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.04)
	glass.mesh = bm
	glass.material_override = ArtMaterials.flat(Color(0.08, 0.1, 0.12), 0.15, false, 0.3)
	w.add_child(glass)
	for y: float in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(size.x + 0.16, 0.08, 0.08)
		bar.mesh = bb
		bar.material_override = trim
		bar.position = Vector3(0.0, y * size.y * 0.5, 0.02)
		w.add_child(bar)
	for x: float in [-1.0, 0.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.07, size.y, 0.07)
		post.mesh = pb
		post.material_override = trim
		post.position = Vector3(x * size.x * 0.5, 0.0, 0.02)
		w.add_child(post)
	var sill := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(size.x + 0.3, 0.08, 0.22)
	sill.mesh = sb
	sill.material_override = trim
	sill.position = Vector3(0.0, -size.y * 0.5 - 0.06, 0.08)
	w.add_child(sill)


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
