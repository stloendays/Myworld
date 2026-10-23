class_name Cave
extends Node3D
## 北缘岩脊里的图腾山洞（world_layout.json → cave；地形 pads 里的 cave_pad 把这一片压平，洞底就是地形）。
##   · 洞道沿 centerline 弯曲：洞口朝南对着雪山步道，进去后向东拐，中段是图腾石厅，尽头是传送门；
##   · 每个中线点的截面是一道拱（半宽、拱高来自 profile），内壁朝里、外壳朝外，外壳加噪声起伏成一座岩丘；
##     内外两层都做成三角网碰撞（双面），洞外爬不进石头里，洞里撞墙不穿；
##   · 石厅北墙下立着会说话的图腾（CaveTotem，按 E 对话、接任务），厅中一堆篝火（按 E 点燃 / 熄灭，三根原木可以坐）；
##   · 洞道两侧几簇发光水晶照路；尽头一圈岩石围着一道光门（FairyPortal），按 E 前往下一个世界（WorldTravel 先卸载本世界再加载）。
## 洞里属于室内区域（zone_id = cave），所以雨雪落叶都进不来。几何全部在世界坐标里生成（节点放在原点）。

const KENNEY := "res://assets/imported/kenney/nature/"
const PORTAL_SHADER := preload("res://shaders/fairy_portal.gdshader")
const RING_SIDES := 13          ## 每道拱截面的点数（含两端落地点）
const STEP := 0.8               ## 沿中线的取样间距（米）
const SHELL := Vector2(4.6, 5.2)  ## 外壳比内壁多出的半宽 / 拱高（米）
const FLIP_WINDING := false

var floor_y := 2.2
var centerline := PackedVector2Array()
var profile := PackedVector2Array()
var chamber := Vector2.ZERO
var totem: CaveTotem = null
var bonfire: InteractableToggle = null
var portal: FairyPortal = null
var seats: Array[Seat] = []
var samples: Array[Dictionary] = []   ## 沿洞道的取样：{p: 中心（地面）, f: 前进方向, r: 右方向, w: 半宽, h: 拱高}
var _outer_rings: Array[PackedVector3Array] = []

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _fire: GPUParticles3D
var _embers: CPUParticles3D
var _fire_light: OmniLight3D
var _flicker_t := 0.0


func _ready() -> void:
	add_to_group("cave")
	var cfg := WorldLayout.section("cave")
	for p: Array in cfg["centerline"]:
		centerline.append(Vector2(float(p[0]), float(p[1])))
	for p: Array in cfg["profile"]:
		profile.append(Vector2(float(p[0]), float(p[1])))
	chamber = WorldLayout.v2(cfg["chamber"])
	floor_y = WorldTerrain.height_at(chamber.x, chamber.y)
	_rng.seed = 5150
	_noise.seed = 77
	_noise.frequency = 0.16
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	add_child(_body)
	_sample_centerline()
	_build_shell()
	_build_floor()
	_build_outcrop_rocks()
	_build_crystals()
	_build_totem(WorldLayout.v2(cfg["totem"]))
	_build_bonfire(WorldLayout.v2(cfg["bonfire"]))
	_build_portal(cfg["portal"])
	_build_zone()


func _process(delta: float) -> void:
	if _fire_light == null or not bonfire.on:
		return
	_flicker_t += delta
	_fire_light.light_energy = 2.6 + sin(_flicker_t * 13.0) * 0.25 + sin(_flicker_t * 7.3) * 0.2


## 洞里（世界坐标 xz）这一点到中线最近处的取样；用于测试和区域判断。
func nearest_sample(xz: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in samples:
		var p: Vector3 = s["p"]
		var d := Vector2(p.x, p.z).distance_squared_to(xz)
		if d < best_d:
			best_d = d
			best = s
	return best


# ---------------------------------------------------------------- 洞道取样

func _sample_centerline() -> void:
	# Catmull-Rom 曲线穿过每个中线点；半宽和拱高按点间位置平滑插值
	var n := centerline.size()
	for i in n - 1:
		var p0 := centerline[maxi(i - 1, 0)]
		var p1 := centerline[i]
		var p2 := centerline[i + 1]
		var p3 := centerline[mini(i + 2, n - 1)]
		var seg := p1.distance_to(p2)
		var steps := maxi(1, int(ceil(seg / STEP)))
		for k in steps:
			var t := float(k) / steps
			var xz := _catmull(p0, p1, p2, p3, t)
			var wh := profile[i].lerp(profile[i + 1], smoothstep(0.0, 1.0, t))
			samples.append({"xz": xz, "w": wh.x, "h": wh.y})
	var last := centerline[n - 1]
	samples.append({"xz": last, "w": profile[n - 1].x, "h": profile[n - 1].y})
	for i in samples.size():
		var a: Vector2 = samples[maxi(i - 1, 0)]["xz"]
		var b: Vector2 = samples[mini(i + 1, samples.size() - 1)]["xz"]
		var f2 := (b - a).normalized()
		var f := Vector3(f2.x, 0.0, f2.y)
		var xz: Vector2 = samples[i]["xz"]
		samples[i]["p"] = Vector3(xz.x, floor_y, xz.y)
		samples[i]["f"] = f
		samples[i]["r"] = f.cross(Vector3.UP).normalized()


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## 一道拱：k = 0 在右侧地面，k = RING_SIDES - 1 在左侧地面。outer = 外壳（更宽更高、起伏更大，两脚埋进地里）。
func _ring(s: Dictionary, outer: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var c: Vector3 = s["p"]
	var r: Vector3 = s["r"]
	var w: float = s["w"]
	var h: float = s["h"]
	if outer:
		w += SHELL.x
		h += SHELL.y
	for k in RING_SIDES:
		var th := PI * float(k) / float(RING_SIDES - 1)
		var base := c + r * cos(th) * w + Vector3.UP * sin(th) * h
		var amp := (0.42 if outer else 0.11) * sin(th) + (0.22 if outer else 0.0)
		var jitter := 1.0 + _noise.get_noise_3dv(base * (0.7 if outer else 1.0)) * amp * 2.0
		var p := c + (base - c) * jitter
		if k == 0 or k == RING_SIDES - 1:
			p.y = c.y - (1.6 if outer else 0.45)
			if outer:
				p += r * cos(th) * 1.2
		pts.append(p)
	return pts


# ---------------------------------------------------------------- 岩壁

func _build_shell() -> void:
	var inner: Array[PackedVector3Array] = []
	var outer: Array[PackedVector3Array] = []
	for s in samples:
		inner.append(_ring(s, false))
		outer.append(_ring(s, true))
	_outer_rings = outer
	var tris_in := PackedVector3Array()
	var tris_out := PackedVector3Array()
	for i in samples.size() - 1:
		var axis_a: Vector3 = samples[i]["p"] + Vector3.UP * float(samples[i]["h"]) * 0.4
		for k in RING_SIDES - 1:
			_quad(tris_in, inner[i][k], inner[i][k + 1], inner[i + 1][k + 1], inner[i + 1][k], axis_a, true)
			_quad(tris_out, outer[i][k], outer[i][k + 1], outer[i + 1][k + 1], outer[i + 1][k], axis_a, false)
	# 洞口一圈：内壁和外壳在第一道拱处接上，面朝洞外
	var mouth: Vector3 = samples[0]["p"] - (samples[0]["f"] as Vector3) * 3.0 + Vector3.UP
	for k in RING_SIDES - 1:
		_quad(tris_out, inner[0][k], inner[0][k + 1], outer[0][k + 1], outer[0][k], mouth, true)
	# 尽头封死：内壁一片（朝洞里）、外壳一片（朝外）
	var li := samples.size() - 1
	var end_c: Vector3 = samples[li]["p"] + Vector3.UP * float(samples[li]["h"]) * 0.45
	var inside_pt: Vector3 = samples[li]["p"] - (samples[li]["f"] as Vector3) * 3.0 + Vector3.UP
	var end_out: Vector3 = samples[li]["p"] + Vector3.UP * (float(samples[li]["h"]) + SHELL.y) * 0.45
	for k in RING_SIDES - 1:
		_tri(tris_in, inner[li][k], inner[li][k + 1], end_c, inside_pt, true)
		_tri(tris_out, outer[li][k], outer[li][k + 1], end_out, inside_pt, false)
	var rock_in := ArtMaterials.pbr("rock_face_03", Color(0.36, 0.31, 0.27), "world")
	var rock_out := ArtMaterials.snowable(ArtMaterials.pbr("rock_face_03", Color(0.78, 0.74, 0.7), "world"))
	_add_mesh("InnerWall", tris_in, rock_in, GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
	_add_mesh("Outcrop", tris_out, rock_out, GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
	# 遮挡体：用内壁本身（就在看得见的岩壁上，不会多挡）。洞里看不到外面的树林，洞外也不画山丘背后的东西
	var occ := ArrayOccluder3D.new()
	var idx := PackedInt32Array()
	for i in tris_in.size():
		idx.append(i)
	occ.set_arrays(tris_in, idx)
	var oi := OccluderInstance3D.new()
	oi.name = "Occluder"
	oi.occluder = occ
	add_child(oi)
	for tris in [tris_in, tris_out]:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(tris)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_body.add_child(cs)
	# 落叶挡板：盖住整条洞道（雨雪由相机高度场挡住）
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for s in samples:
		var p: Vector3 = s["p"]
		lo = lo.min(p - Vector3(7.0, 1.0, 7.0))
		hi = hi.max(p + Vector3(7.0, 8.0, 7.0))
	add_child(Precipitation.leaf_blocker(hi - lo, Transform3D(Basis(), (lo + hi) * 0.5)))


## 四边形 = 两个三角形；toward 为希望法线朝向的参考点（inward = 朝向它，否则背离它）。
func _quad(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ref: Vector3, toward: bool) -> void:
	_tri(out, a, b, c, ref, toward)
	_tri(out, a, c, d, ref, toward)


func _tri(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, ref: Vector3, toward: bool) -> void:
	var n := (b - a).cross(c - a)
	var to_ref := ref - (a + b + c) / 3.0
	var facing := n.dot(to_ref) > 0.0
	# Godot 的正面是顺时针：从正面看过去 (b-a)×(c-a) 背离观看者。要正面朝 ref，叉积就得背离 ref，否则交换两点
	if (facing == toward) != FLIP_WINDING:
		out.append_array([a, c, b])
	else:
		out.append_array([a, b, c])


func _add_mesh(mesh_name: String, tris: PackedVector3Array, mat: Material, shadow: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)      # 每个面单独法线：低多边形的硬边石头
	for v in tris:
		st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = shadow
	add_child(mi)
	return mi


## 洞底铺一层碎石泥地（只是外观，踩的是地形本身）。
func _build_floor() -> void:
	var tris := PackedVector3Array()
	for i in samples.size() - 1:
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		var lift := Vector3.UP * 0.03
		var al: Vector3 = a["p"] - (a["r"] as Vector3) * float(a["w"]) * 1.02 + lift
		var ar: Vector3 = a["p"] + (a["r"] as Vector3) * float(a["w"]) * 1.02 + lift
		var bl: Vector3 = b["p"] - (b["r"] as Vector3) * float(b["w"]) * 1.02 + lift
		var br: Vector3 = b["p"] + (b["r"] as Vector3) * float(b["w"]) * 1.02 + lift
		var up_ref: Vector3 = (a["p"] as Vector3) + Vector3.UP * 3.0
		_quad(tris, al, ar, br, bl, up_ref, true)
	var mi := _add_mesh("Floor", tris, ArtMaterials.pbr("brown_mud_rocks_01", Color(0.55, 0.45, 0.36), "world"), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mi.name = "Floor"


## 岩丘上散几块大石头，打破外壳的轮廓：贴在外壳表面的点上，再往外推一点（不会穿进洞里）。
func _build_outcrop_rocks() -> void:
	var kinds := ["rock_largeA", "rock_largeB", "rock_largeC", "rock_largeD", "rock_largeE", "rock_largeF"]
	for i in range(2, _outer_rings.size() - 2, 4):
		var ring := _outer_rings[i]
		var axis: Vector3 = samples[i]["p"]
		for k in range(2, RING_SIDES - 2, 3):
			if _rng.randf() < 0.45:
				continue
			var p := ring[k]
			var out := (p - axis - Vector3.UP * 0.5).normalized()
			var rock := ArtMaterials.kenney_prop(KENNEY + "%s.glb" % kinds[_rng.randi() % kinds.size()], p + out * 1.1, _rng.randf() * 360.0, _rng.randf_range(2.0, 3.6))
			add_child(rock)


# ---------------------------------------------------------------- 水晶与光

func _build_crystals() -> void:
	var tints := [Color(0.45, 0.85, 1.0), Color(0.6, 0.7, 1.0), Color(0.4, 1.0, 0.85)]
	var idx := 0
	for i in range(4, samples.size() - 3, 7):
		var s: Dictionary = samples[i]
		if float(s["w"]) > 4.0:
			continue   # 石厅里有篝火照着
		var side := -1.0 if idx % 2 == 0 else 1.0
		var base: Vector3 = s["p"] + (s["r"] as Vector3) * side * (float(s["w"]) - 0.55)
		var tint: Color = tints[idx % tints.size()]
		var cluster := Node3D.new()
		cluster.name = "Crystals_%d" % idx
		cluster.position = base
		add_child(cluster)
		for j in 4:
			var mi := MeshInstance3D.new()
			var prism := CylinderMesh.new()
			prism.top_radius = 0.0
			prism.bottom_radius = _rng.randf_range(0.09, 0.17)
			prism.height = _rng.randf_range(0.45, 1.0)
			prism.radial_segments = 5
			prism.rings = 1
			mi.mesh = prism
			mi.material_override = ArtMaterials.crystal(tint)
			mi.position = Vector3(_rng.randf_range(-0.25, 0.25), prism.height * 0.4, _rng.randf_range(-0.25, 0.25))
			mi.rotation = Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf() * TAU, _rng.randf_range(-0.35, 0.35) + side * -0.25)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cluster.add_child(mi)
		var l := OmniLight3D.new()
		l.position = Vector3(0.0, 0.7, 0.0) - (s["r"] as Vector3) * side * 0.4
		l.light_color = tint
		l.light_energy = 1.4
		l.omni_range = 6.5
		l.shadow_enabled = false
		cluster.add_child(l)
		idx += 1


# ---------------------------------------------------------------- 图腾

func _build_totem(at: Vector2) -> void:
	totem = CaveTotem.create(&"cave_totem")
	totem.position = Vector3(at.x, floor_y, at.y)
	# 面朝石厅中心
	var to_c := Vector2(chamber.x - at.x, chamber.y - at.y)
	totem.rotation.y = atan2(to_c.x, to_c.y)
	add_child(totem)


# ---------------------------------------------------------------- 篝火

func _build_bonfire(at: Vector2) -> void:
	var root := Node3D.new()
	root.name = "Bonfire"
	root.position = Vector3(at.x, floor_y, at.y)
	add_child(root)
	root.add_child(ArtMaterials.kenney_prop(KENNEY + "campfire_stones.glb", Vector3.ZERO, 0.0, 2.4))
	root.add_child(ArtMaterials.kenney_prop(KENNEY + "campfire_logs.glb", Vector3.ZERO, 30.0, 2.4))
	_fire = _make_fire()
	_fire.position = Vector3(0.0, 0.25, 0.0)
	root.add_child(_fire)
	_embers = _make_embers()
	_embers.position = Vector3(0.0, 0.5, 0.0)
	root.add_child(_embers)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "FireLight"
	_fire_light.position = Vector3(0.0, 1.1, 0.0)
	_fire_light.light_color = Color(1.0, 0.6, 0.3)
	_fire_light.light_energy = 2.6
	_fire_light.omni_range = 13.0
	_fire_light.shadow_enabled = true
	root.add_child(_fire_light)
	bonfire = InteractableToggle.create(&"cave_bonfire", "篝火", true, "E  熄灭篝火", "E  点燃篝火", Vector3(1.4, 1.0, 1.4), Vector3(0.0, 0.5, 0.0))
	root.add_child(bonfire)
	bonfire.toggled.connect(_on_bonfire)
	_on_bonfire(bonfire.on)
	# 三根原木围着火堆，可以坐
	for i in 3:
		var a := deg_to_rad(200.0 + i * 70.0)
		var pos := Vector3(cos(a) * 2.3, 0.0, sin(a) * 2.3)
		var log := ArtMaterials.kenney_prop(KENNEY + "log.glb", pos, rad_to_deg(-a) + 90.0, 2.2)
		root.add_child(log)
		var face := atan2(-pos.x, -pos.z)   # 面朝火堆
		var seat := Seat.create(StringName("cave_log_%d" % i), "原木", pos + Vector3(0.0, 0.42, 0.0), rad_to_deg(face) + 180.0, 0.42, 0.9)
		root.add_child(seat)
		seats.append(seat)


func _on_bonfire(on: bool) -> void:
	_fire.emitting = on
	_embers.emitting = on
	_fire_light.visible = on


func _make_fire() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.28
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 0.95), Color(1.0, 0.5, 0.12, 0.9), Color(0.85, 0.18, 0.05, 0.5), Color(0.3, 0.05, 0.02, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.34)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Fire"
	p.emitting = false
	p.amount = 64
	p.lifetime = 0.8
	p.process_material = pm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1.0, -0.3, -1.0), Vector3(2.0, 2.5, 2.0))
	return p


## 火星：少量粒子，用 CPU 粒子（同参数的 GPU 粒子在本项目里出过停在发射点不动的问题）。
func _make_embers() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Embers"
	p.emitting = false
	p.amount = 28
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0.0, 0.2, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = mat
	p.mesh = quad
	return p


# ---------------------------------------------------------------- 传送门

func _build_portal(cfg: Dictionary) -> void:
	var at := WorldLayout.v2(cfg["pos"])
	var gate := Node3D.new()
	gate.name = "Gate"
	gate.position = Vector3(at.x, floor_y, at.y)
	gate.rotation.y = deg_to_rad(float(cfg.get("yaw_deg", -90.0)))
	add_child(gate)
	var stone := ArtMaterials.pbr("rock_face_03", Color(0.55, 0.52, 0.5), "world")
	var ring_r := 1.55
	var center_y := 1.75
	var n := 16
	for i in n:
		var a := float(i) / n * TAU
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.7, 0.55) * _rng.randf_range(0.9, 1.15)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = stone
		mi.transform = Transform3D(Basis(Vector3.FORWARD, a), Vector3(cos(a) * ring_r, center_y + sin(a) * ring_r, 0.0))
		gate.add_child(mi)
		if i % 3 == 0:
			var rune := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(0.12, 0.12, 0.06)
			rune.mesh = rb
			rune.material_override = ArtMaterials.glow(Color(0.55, 0.95, 1.0), 3.0)
			rune.position = mi.position + Vector3(0.0, 0.0, 0.3)
			gate.add_child(rune)
	var face := MeshInstance3D.new()
	face.name = "PortalFace"
	var q := QuadMesh.new()
	q.size = Vector2(ring_r * 2.0 - 0.3, ring_r * 2.0 - 0.3)
	face.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	face.material_override = mat
	face.position = Vector3(0.0, center_y, 0.0)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(face)
	portal = FairyPortal.create(&"cave_portal", str(cfg.get("world", "world_02")), Vector2(ring_r * 1.6, ring_r * 1.6))
	portal.position = Vector3(0.0, center_y, 0.0)
	gate.add_child(portal)
	var l := OmniLight3D.new()
	l.position = Vector3(0.0, center_y, 0.8)
	l.light_color = Color(0.6, 0.9, 1.0)
	l.light_energy = 2.0
	l.omni_range = 8.0
	l.shadow_enabled = false
	gate.add_child(l)


# ---------------------------------------------------------------- 区域

## 一个 ZoneArea 挂多个沿洞道旋转的盒子（同一区域只进出一次，不会因为盒子重叠而误报“离开”）。
func _build_zone() -> void:
	var zone := ZoneArea.new()
	zone.name = "Zone_cave"
	zone.zone_id = &"cave"
	zone.is_indoor = true
	for i in range(1, samples.size(), 3):
		var s: Dictionary = samples[i]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(s["w"]) * 2.0, float(s["h"]) + 0.5, STEP * 3.4)
		cs.shape = box
		var f: Vector3 = s["f"]
		cs.transform = Transform3D(Basis.looking_at(f, Vector3.UP), (s["p"] as Vector3) + Vector3.UP * (float(s["h"]) + 0.5) * 0.5)
		zone.add_child(cs)
	add_child(zone)
