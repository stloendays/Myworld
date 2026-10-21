class_name SnowPeak
extends Node3D
## 东北角的雪山（地形 hills 里的 snow_peak；雪线 terrain.snowline 以上终年积雪，林线 forest.treeline 以上不长树）。
## 本脚本只放山顶的东西（world_layout.json → snow_peak）：
##   · 一座石堆（玛尼堆一样层层垒起）和一根挂着小旗的旗杆，旗随风摆；
##   · 一张面朝湖的长椅（可以坐，看整片湖）；
##   · 山顶周围终年飘着小雪（CPUParticles3D，只在附近才画）。
## 立牌由 world_layout.json → signs 放。

const FURNITURE := "res://assets/imported/kenney/furniture/"

var summit := Vector2.ZERO
var seat: Seat = null
var flurry: CPUParticles3D = null
var _flag: Node3D


func _enter_tree() -> void:
	var cfg := WorldLayout.section("snow_peak")
	summit = WorldLayout.v2(cfg["summit"])
	position = Vector3(summit.x, WorldTerrain.height_at(summit.x, summit.y), summit.y)


func _ready() -> void:
	add_to_group("snow_peak")
	_build_cairn()
	_build_flag()
	_build_bench()
	_build_flurry()


func _ground(x: float, z: float) -> float:
	return WorldTerrain.height_at(position.x + x, position.z + z) - position.y


func _build_cairn() -> void:
	var stone := ArtMaterials.pbr("rock_face_03", Color(0.9, 0.9, 0.95))
	var snow := ArtMaterials.flat(Color(0.94, 0.96, 1.0), 0.6)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var base := Vector3(1.6, _ground(1.6, 0.6), 0.6)
	var y := 0.0
	var sizes := [Vector3(1.3, 0.38, 1.1), Vector3(1.0, 0.34, 0.85), Vector3(0.78, 0.3, 0.7), Vector3(0.55, 0.28, 0.5), Vector3(0.36, 0.26, 0.34)]
	for i in sizes.size():
		var s: Vector3 = sizes[i]
		var rot := Basis(Vector3.UP, i * 0.6)
		_box(self, s, base + Vector3(0.0, y + s.y * 0.5, 0.0), stone, rot)
		# 每块石头顶上一层薄雪
		_box(self, Vector3(s.x * 0.9, 0.04, s.z * 0.9), base + Vector3(0.0, y + s.y + 0.02, 0.0), snow, rot)
		y += s.y
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, y, 1.1)
	cs.shape = shape
	cs.position = base + Vector3(0.0, y * 0.5, 0.0)
	body.add_child(cs)


func _build_flag() -> void:
	var at := Vector3(2.6, _ground(2.6, -0.4), -0.4)
	var pole := ArtMaterials.pbr("stained_pine", Color(0.7, 0.5, 0.34))
	_box(self, Vector3(0.08, 3.2, 0.08), at + Vector3(0.0, 1.6, 0.0), pole)
	_box(self, Vector3(0.14, 0.08, 0.14), at + Vector3(0.0, 3.24, 0.0), ArtMaterials.flat(Color(0.86, 0.66, 0.3), 0.35, false, 0.8))
	_flag = Node3D.new()
	_flag.name = "Flag"
	_flag.position = at + Vector3(0.04, 2.85, 0.0)
	add_child(_flag)
	# 三色小旗：红、白、蓝竖条（方块画风）
	var colors := [Color(0.82, 0.24, 0.2), Color(0.95, 0.94, 0.9), Color(0.25, 0.42, 0.72)]
	for i in 3:
		_box(_flag, Vector3(0.3, 0.55, 0.02), Vector3(0.15 + i * 0.3, 0.0, 0.0), ArtMaterials.flat(colors[i], 0.9, false, 0.0, true))
	var tw := _flag.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_flag, "rotation:y", deg_to_rad(28.0), 1.4)
	tw.tween_property(_flag, "rotation:y", deg_to_rad(-12.0), 1.6)


## 面朝湖心的长椅：座位朝向由山顶指向湖心算出来。
func _build_bench() -> void:
	var lake := WorldLayout.v2(WorldLayout.section("lake")["center"])
	var dir := (lake - summit).normalized()
	var yaw := rad_to_deg(atan2(-dir.x, -dir.y))   # 座位 -Z 朝向湖心
	var at := Vector3(-1.4, 0.0, 1.0)
	at.y = _ground(at.x, at.z)
	add_child(ArtMaterials.kenney_prop(FURNITURE + "bench.glb", at, yaw + 180.0, 2.2))
	seat = Seat.create(&"snow_peak_bench", "长椅", at + Vector3(0.0, 0.48, 0.0), yaw, 0.45, 0.9)
	add_child(seat)


## 山顶的小雪：方圆约 50 m、头顶 10 m 处往下飘，跟着风斜一点。
func _build_flurry() -> void:
	flurry = CPUParticles3D.new()
	flurry.name = "Flurry"
	flurry.position = Vector3(-8.0, 10.0, 6.0)
	flurry.amount = 320
	flurry.lifetime = 9.0
	flurry.preprocess = 9.0
	flurry.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flurry.emission_box_extents = Vector3(26.0, 3.0, 26.0)
	flurry.direction = Vector3(0.3, -1.0, 0.15)
	flurry.spread = 20.0
	flurry.initial_velocity_min = 0.6
	flurry.initial_velocity_max = 1.2
	flurry.gravity = Vector3(0.25, -0.6, 0.1)
	flurry.scale_amount_min = 0.6
	flurry.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.97, 0.98, 1.0, 0.85)
	q.material = m
	flurry.mesh = q
	flurry.visibility_range_end = 140.0
	add_child(flurry)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, basis := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
