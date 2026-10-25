class_name World02
extends MiniWorld
## 世界二「云海浮岛」：黄昏的云海上一座主岛和四座小岛（布局在 data/worlds/cloudsea.json）。
##   · 主岛：起伏草地、小池塘和从岛边落进云海的瀑布、一棵开满粉花的方块古树、回湖畔的光门；
##   · 三座绳桥通往西岛（转动的风车）、北岛（石阵）、东岛（观鲸台，能坐的长椅）；
##   · 北岛尽头一条悬空跳台小路（12 块石头，一块比一块高）通向最高的灯塔岛；
##   · 能做的事：捡 8 颗云珠、点亮 4 座风灯（全部点亮后天鲸游到群岛旁边）、6 个探索点、跳台计时（挑战模式）。
## 浮岛是极坐标网格：顶面高度 = 岛面 + 小山 − 池塘 − 岛边下沉，岛边随角度起伏；岛底是往下收拢的岩锥。

const SEGMENTS := 96
const NATURE := "res://assets/imported/kenney/nature/"
const WHALE_COLORS := {"blue": Color(0.52, 0.58, 0.86), "belly": Color(0.96, 0.92, 0.98), "eye": Color(0.08, 0.06, 0.12)}
const WHALE_FAR := Vector2(88.0, 4.0)     ## 平时：绕群岛半径 88 m、高 4 m
const WHALE_NEAR := Vector2(42.0, 16.0)   ## 四座风灯都点亮后：游近到 42 m、升到 16 m

var islands: Array[Dictionary] = []
var bridges: Array[PackedVector3Array] = []   ## 每座桥的桥面点（自动检查走桥用）
var stones: PackedVector3Array = []           ## 跳台石头顶面中心
var beacons: Array[WindBeacon] = []
var whale: Node3D = null
var whale_pivot: Node3D = null
var whale_near := false
var parkour_best := 0.0                       ## 跳台挑战最好成绩（秒）

var _blades: Node3D = null
var _parkour_start := -1.0


func _init() -> void:
	world_id = "world_02"


# ---------------------------------------------------------------- 高度

func _r_edge(isl: Dictionary, theta: float) -> float:
	var s := float(isl["seed"])
	return float(isl["radius"]) * (1.0 + 0.07 * sin(3.0 * theta + s) + 0.04 * sin(7.0 * theta + 2.0 * s))


## 岛面高度（不管在不在岛上），ratio = 到中心距离 / 这个方向的岛边半径。
func _surface(isl: Dictionary, x: float, z: float, ratio: float) -> float:
	var h := float(isl["top"])
	for hl: Array in isl.get("hills", []):
		var d := Vector2(x - float(hl[0]), z - float(hl[1])).length() / float(hl[2])
		h += float(hl[3]) * exp(-d * d * 2.2)
	var pond: Array = isl.get("pond", [])
	if not pond.is_empty():
		var dp := Vector2(x - float(pond[0]), z - float(pond[1])).length() / float(pond[2])
		h -= float(pond[3]) * (1.0 - smoothstep(0.55, 1.15, dp))
	h += 0.25 * sin(x * 0.35 + float(isl["seed"])) * sin(z * 0.29)
	h -= 0.9 * smoothstep(0.82, 1.0, ratio)
	return h


func island_at(x: float, z: float) -> Dictionary:
	for isl in islands:
		var c: Vector2 = isl["c"]
		var d := Vector2(x, z) - c
		if d.length() < _r_edge(isl, atan2(d.y, d.x)):
			return isl
	return {}


func height_at(x: float, z: float) -> float:
	var best := -INF
	for isl in islands:
		var c: Vector2 = isl["c"]
		var d := Vector2(x, z) - c
		var re := _r_edge(isl, atan2(d.y, d.x))
		var l := d.length()
		if l < re:
			best = maxf(best, _surface(isl, x, z, l / re))
	return best


func _island(id: String) -> Dictionary:
	for isl in islands:
		if str(isl["id"]) == id:
			return isl
	return {}


## 从岛 a 朝岛 b 的方向、离岛边 inset 米处的点（桥头、跳台起点）。
func _rim_point(a: Dictionary, toward: Vector2, inset: float) -> Vector3:
	var c: Vector2 = a["c"]
	var dir := (toward - c).normalized()
	var re := _r_edge(a, atan2(dir.y, dir.x)) - inset
	var p := c + dir * re
	return Vector3(p.x, height_at(p.x, p.y), p.y)


# ---------------------------------------------------------------- 建造

func build_world() -> void:
	var i := 0
	for d: Dictionary in data.get("islands", []):
		var isl := d.duplicate()
		isl["c"] = MiniWorld.v2(d["center"])
		isl["seed"] = float(i) * 1.7 + 0.4
		islands.append(isl)
		i += 1
	var grass := MiniWorld.terrain_material("leafy_grass")
	var rock := MiniWorld.terrain_material("rock_face_03")
	for isl in islands:
		_build_island(isl, grass, rock)
	_build_cloud_sea()
	_build_pond_and_falls()
	for pair: Array in data.get("bridges", []):
		var a := _island(str(pair[0]))
		var b := _island(str(pair[1]))
		var from := _bridge_head(a, b["c"])
		var to := _bridge_head(b, a["c"])
		var sag := 0.3 if absf(to.y - from.y) / Vector2(to.x - from.x, to.z - from.z).length() > 0.25 else 0.5
		bridges.append(plank_bridge(from, to, 1.7, sag, "Bridge_%s_%s" % [pair[0], pair[1]]))
		_landing(a, from)
		_landing(b, to)
	_build_stones()
	for bd: Dictionary in data.get("beacons", []):
		var p := MiniWorld.v2(bd["pos"])
		var b := WindBeacon.create(str(bd["id"]))
		b.position = Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y)
		add_child(b)
		b.lit_changed.connect(_on_beacon)
		beacons.append(b)
	_build_tree(Vector2(-9.0, -7.0))
	_build_windmill(Vector2(-55.0, -6.0))
	_build_stone_ring(Vector2(6.0, -56.0))
	_build_overlook(Vector2(57.0, 10.0))
	_build_lighthouse(Vector2(10.0, -101.0))
	_build_greenery()
	_build_whale()


func _build_island(isl: Dictionary, grass: Material, rock: Material) -> void:
	var c: Vector2 = isl["c"]
	var radius := float(isl["radius"])
	var rings := int(ceil(radius / 1.2))
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := PackedVector3Array()
	# 顶面：中心一点 + rings 圈，每圈 SEGMENTS 个点
	top.set_color(_grass_color(isl, c.x, c.y, 0.0))
	top.set_uv(c)
	top.add_vertex(Vector3(c.x, _surface(isl, c.x, c.y, 0.0), c.y))
	for k in range(1, rings + 1):
		var t := float(k) / rings
		for s in SEGMENTS:
			var th := float(s) / SEGMENTS * TAU
			var r := _r_edge(isl, th) * t
			var x := c.x + cos(th) * r
			var z := c.y + sin(th) * r
			var y := _surface(isl, x, z, t)
			top.set_color(_grass_color(isl, x, z, t))
			top.set_uv(Vector2(x, z))
			top.add_vertex(Vector3(x, y, z))
			if k == rings:
				rim.append(Vector3(x, y, z))
	for s in SEGMENTS:
		var s2 := (s + 1) % SEGMENTS
		top.add_index(0)
		top.add_index(1 + s)
		top.add_index(1 + s2)
	for k in range(1, rings):
		var a0 := 1 + (k - 1) * SEGMENTS
		var b0 := 1 + k * SEGMENTS
		for s in SEGMENTS:
			var s2 := (s + 1) % SEGMENTS
			top.add_index(a0 + s)
			top.add_index(b0 + s)
			top.add_index(a0 + s2)
			top.add_index(a0 + s2)
			top.add_index(b0 + s)
			top.add_index(b0 + s2)
	top.generate_normals()
	var top_mesh := top.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Island_" + str(isl["id"])
	mi.mesh = top_mesh
	mi.material_override = grass
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "IslandBody_" + str(isl["id"])
	body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.TERRAIN
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var tri := top_mesh.create_trimesh_shape()
	tri.backface_collision = true
	cs.shape = tri
	body.add_child(cs)
	add_child(body)
	# 岛底：从岛边往下一层层收拢的岩锥，最上面一圈是草皮和泥土的边
	var under := SurfaceTool.new()
	under.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := 7
	var depth := float(isl.get("depth", 15.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(isl["seed"]) * 1000.0)
	for l in layers + 1:
		var f := float(l) / layers
		for s in SEGMENTS:
			var rp := rim[s]
			var dir := Vector2(rp.x - c.x, rp.z - c.y)
			var shrink := pow(1.0 - f, 0.75) * (0.92 + 0.16 * rng.randf()) if l > 0 else 1.0
			var y := rp.y - 0.25 - depth * pow(f, 1.25) * (0.85 + 0.3 * rng.randf()) if l > 0 else rp.y - 0.05
			var p := c + dir * maxf(shrink, 0.04)
			var col := Color(0.4, 0.3, 0.2) if l <= 1 else Color(0.5, 0.47, 0.52).lerp(Color(0.38, 0.33, 0.42), f)
			under.set_color(col)
			under.set_uv(Vector2(p.x, y))
			under.add_vertex(Vector3(p.x, y, p.y))
	for l in layers:
		for s in SEGMENTS:
			var s2 := (s + 1) % SEGMENTS
			var a := l * SEGMENTS
			var b := (l + 1) * SEGMENTS
			under.add_index(a + s)
			under.add_index(b + s)
			under.add_index(a + s2)
			under.add_index(a + s2)
			under.add_index(b + s)
			under.add_index(b + s2)
	under.generate_normals()
	var umi := MeshInstance3D.new()
	umi.name = "Underside_" + str(isl["id"])
	umi.mesh = under.commit()
	umi.material_override = rock
	add_child(umi)


func _grass_color(isl: Dictionary, x: float, z: float, ratio: float) -> Color:
	var n := 0.5 + 0.5 * sin(x * 0.21 + z * 0.17) * cos(z * 0.13 - x * 0.07)
	var col := Color(0.47, 0.66, 0.33).lerp(Color(0.6, 0.72, 0.36), n * 0.6)
	var pond: Array = isl.get("pond", [])
	if not pond.is_empty() and Vector2(x - float(pond[0]), z - float(pond[1])).length() < float(pond[2]) * 1.15:
		col = Color(0.74, 0.68, 0.52)
	return col.lerp(Color(0.5, 0.4, 0.28), smoothstep(0.9, 1.0, ratio))


func _build_cloud_sea() -> void:
	var sea := MeshInstance3D.new()
	sea.name = "CloudSea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 1400.0)
	sea.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/cloud_sea.gdshader")
	for key in ["noise_a", "noise_b"]:
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.generate_mipmaps = true
		var fn := FastNoiseLite.new()
		fn.seed = 7 if key == "noise_a" else 19
		fn.frequency = 0.012 if key == "noise_a" else 0.03
		fn.fractal_octaves = 4
		nt.noise = fn
		mat.set_shader_parameter(key, nt)
	sea.material_override = mat
	sea.position = Vector3(0.0, -24.0, -40.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# 云团：几簇低多边形的球，慢慢飘
	var puff := ArtMaterials.flat(Color(1.0, 0.93, 0.9), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2402
	for i in 22:
		var g := Node3D.new()
		g.name = "Puff%02d" % i
		var a := rng.randf() * TAU
		var r := rng.randf_range(40.0, 170.0)
		g.position = Vector3(cos(a) * r, rng.randf_range(-22.0, -8.0) if r < 90.0 else rng.randf_range(-15.0, 25.0), sin(a) * r - 40.0)
		for k in 4:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var rad := rng.randf_range(3.0, 7.0)
			sm.radius = rad
			sm.height = rad * 1.4
			sm.radial_segments = 10
			sm.rings = 5
			s.mesh = sm
			s.material_override = puff
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.position = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-1.0, 2.0), rng.randf_range(-4.0, 4.0))
			g.add_child(s)
		g.set_meta("drift", rng.randf_range(0.3, 0.9))
		g.add_to_group("cloud_puffs")
		add_child(g)


func _waterfall_material(fade_bottom: float, tiling: float, speed: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sky_waterfall.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 256
	nt.seamless = true
	nt.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.seed = 31
	fn.frequency = 0.05
	nt.noise = fn
	mat.set_shader_parameter("streaks", nt)
	mat.set_shader_parameter("fade_bottom", fade_bottom)
	mat.set_shader_parameter("tiling", tiling)
	mat.set_shader_parameter("speed", speed)
	return mat


## 池塘（能下去游两下）+ 从池塘流到岛边的小溪 + 落进云海的瀑布。
func _build_pond_and_falls() -> void:
	var main := _island("main")
	var pond: Array = main["pond"]
	var pc := Vector2(float(pond[0]), float(pond[1]))
	var surface := float(main["top"]) - 0.35
	var water := MeshInstance3D.new()
	water.name = "PondWater"
	var cm := CylinderMesh.new()
	cm.top_radius = float(pond[2]) * 0.92
	cm.bottom_radius = float(pond[2]) * 0.92
	cm.height = 0.02
	cm.radial_segments = 32
	water.mesh = cm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.36, 0.62, 0.78, 0.82)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.08
	wm.metallic_specular = 0.8
	water.material_override = wm
	water.position = Vector3(pc.x, surface, pc.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	add_child(WaterVolume.create_cylinder(&"cloudsea_pond", Vector3(pc.x, surface - 0.9, pc.y), float(pond[2]) * 0.92, 1.8))
	# 小溪：池塘东北边到岛边，贴着地面的一条水带
	var falls_dir := Vector2(24.0, 11.0).normalized()
	var start := pc + (Vector2(24.0, 11.0) - pc).normalized() * float(pond[2]) * 0.85
	var rim := _rim_point(main, Vector2(24.0, 11.0) * 3.0, 0.15)
	var end := Vector2(rim.x, rim.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var side := Vector2(-(end - start).normalized().y, (end - start).normalized().x)
	for k in n + 1:
		var t := float(k) / n
		var p := start.lerp(end, t)
		for sgn: float in [-1.0, 1.0]:
			var q := p + side * sgn * 0.7
			st.set_uv(Vector2(0.5 + sgn * 0.5, t))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, height_at(q.x, q.y) + 0.06 if height_at(q.x, q.y) > -1e6 else rim.y, q.y))
	for k in n:
		var a := k * 2
		st.add_index(a)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 3)
		st.add_index(a + 2)
	var creek := MeshInstance3D.new()
	creek.name = "Creek"
	creek.mesh = st.commit()
	creek.material_override = _waterfall_material(1.1, 2.0, 0.5)
	creek.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(creek)
	# 瀑布：岛边往下 42 m 的水帘，下端散进云海
	var fall := MeshInstance3D.new()
	fall.name = "Waterfall"
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 42.0)
	fall.mesh = q
	fall.material_override = _waterfall_material(0.7, 6.0, 1.4)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var out := Vector3(falls_dir.x, 0.0, falls_dir.y)
	fall.position = Vector3(rim.x, rim.y - 21.0, rim.z) + out * 0.9
	fall.rotation.y = atan2(out.x, out.z)
	add_child(fall)
	var mist := CPUParticles3D.new()
	mist.name = "FallsMist"
	mist.amount = 24
	mist.lifetime = 2.5
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.8
	mist.gravity = Vector3(0.0, -0.4, 0.0)
	mist.initial_velocity_min = 0.2
	mist.initial_velocity_max = 0.6
	mist.scale_amount_min = 1.0
	mist.scale_amount_max = 2.2
	var mq := QuadMesh.new()
	mq.size = Vector2(0.8, 0.8)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(1.0, 1.0, 1.0, 0.25)
	mq.material = mm
	mist.mesh = mq
	mist.position = rim + out * 1.0 + Vector3(0.0, -0.6, 0.0)
	add_child(mist)


## 跳台：从北岛边到灯塔岛边，一块比一块高，左右错开。
func _build_stones() -> void:
	var cfg: Dictionary = data.get("stones", {})
	if cfg.is_empty():
		return
	var a := _island(str(cfg["from"]))
	var b := _island(str(cfg["to"]))
	var from := _rim_point(a, b["c"], 1.0)
	var to := _rim_point(b, a["c"], 1.2)
	var n := int(cfg.get("count", 10))
	var size := float(cfg.get("size", 1.5))
	var zig := float(cfg.get("zigzag", 1.2))
	var dir := Vector2(to.x - from.x, to.z - from.z).normalized()
	var side := Vector3(-dir.y, 0.0, dir.x)
	var rock := ArtMaterials.pbr("rock_face_03", Color(0.78, 0.74, 0.82), "world")
	var moss := ArtMaterials.flat(Color(0.45, 0.62, 0.34), 0.9)
	var g := Node3D.new()
	g.name = "SkyStones"
	add_child(g)
	for i in n:
		var t := float(i + 1) / (n + 1)
		var p := from.lerp(to, t) + side * zig * (1.0 if i % 2 == 0 else -1.0)
		p.y = from.y + (to.y - from.y) * t + 0.1
		stones.append(p)
		solid_box(g, Vector3(size, 0.6, size), Transform3D(Basis(Vector3.UP, float(i) * 0.6), p - Vector3(0.0, 0.3, 0.0)), rock)
		solid_box(g, Vector3(size * 0.86, 0.06, size * 0.86), Transform3D(Basis(Vector3.UP, float(i) * 0.6), p + Vector3(0.0, 0.03, 0.0)), moss, false)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = size * 0.5
		cm.bottom_radius = 0.1
		cm.height = 1.4
		cm.radial_segments = 6
		cone.mesh = cm
		cone.material_override = rock
		cone.position = p - Vector3(0.0, 1.3, 0.0)
		g.add_child(cone)
	# 跳台上的云珠（数据里写 "stone": n）
	for it: Dictionary in data.get("items", []):
		if it.has("stone"):
			var sp := stones[clampi(int(it["stone"]), 0, stones.size() - 1)]
			it["pos"] = [sp.x, sp.z, sp.y]


## 主岛小山上的古树：方块树干、几层粉色花冠，花瓣慢慢飘落。
func _build_tree(at: Vector2) -> void:
	var g := Node3D.new()
	g.name = "AncientTree"
	g.position = Vector3(at.x, height_at(at.x, at.y) - 0.2, at.y)
	add_child(g)
	var pieces := [
		[-6, 0, -6, 6, 60, 6, "bark"], [-8, 0, -8, 8, 6, 8, "bark"], [6, 30, -2, 20, 34, 2, "bark"], [-18, 38, -2, -6, 42, 2, "bark"],
		[-2, 44, 6, 2, 48, 18, "bark"],
		[-26, 58, -26, 26, 70, 26, "leaf"], [-20, 70, -20, 20, 80, 20, "leaf2"], [-12, 80, -12, 12, 88, 12, "leaf"],
		[10, 32, -8, 28, 42, 8, "leaf2"], [-28, 40, -8, -12, 50, 8, "leaf"], [-8, 46, 12, 8, 56, 26, "leaf2"],
	]
	var boxes := []
	for p: Array in pieces:
		boxes.append({"box": p.slice(0, 6), "color": p[6]})
	var colors := {"bark": Color(0.42, 0.3, 0.24), "leaf": Color(0.98, 0.7, 0.8), "leaf2": Color(0.94, 0.58, 0.72)}
	var mi := MeshInstance3D.new()
	mi.mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return colors.get(k, Color.WHITE), 0.12)
	g.add_child(mi)
	var trunk := StaticBody3D.new()
	trunk.collision_layer = PhysicsLayers.WORLD
	trunk.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 7.2, 1.5)
	cs.shape = shape
	cs.position = Vector3(0.0, 3.6, 0.0)
	trunk.add_child(cs)
	g.add_child(trunk)
	var petals := CPUParticles3D.new()
	petals.name = "Petals"
	petals.amount = 40
	petals.lifetime = 7.0
	petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	petals.emission_box_extents = Vector3(3.0, 0.4, 3.0)
	petals.gravity = Vector3(0.25, -0.35, 0.1)
	petals.initial_velocity_min = 0.0
	petals.initial_velocity_max = 0.3
	petals.angular_velocity_min = -90.0
	petals.angular_velocity_max = 90.0
	var pq := QuadMesh.new()
	pq.size = Vector2(0.12, 0.09)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(1.0, 0.72, 0.84)
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pq.material = pmat
	petals.mesh = pq
	petals.position = Vector3(0.0, 8.0, 0.0)
	g.add_child(petals)


## 西岛风车：石塔、木顶、四片慢慢转的扇叶。
func _build_windmill(at: Vector2) -> void:
	var g := Node3D.new()
	g.name = "Windmill"
	g.position = Vector3(at.x, height_at(at.x, at.y) - 0.1, at.y)
	add_child(g)
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.95, 0.92, 0.88), "world")
	var wood := ArtMaterials.pbr("stained_pine", Color(0.7, 0.5, 0.36), "world")
	var cloth := ArtMaterials.flat(Color(0.95, 0.9, 0.82), 0.9, false, 0.0, true)
	solid_box(g, Vector3(3.0, 6.0, 3.0), Transform3D(Basis(), Vector3(0.0, 3.0, 0.0)), stone)
	for sz: float in [-1.0, 1.0]:
		var roof := solid_box(g, Vector3(3.6, 0.15, 2.4), Transform3D(Basis(Vector3.RIGHT, sz * deg_to_rad(35.0)), Vector3(0.0, 6.6, sz * 0.95)), wood, false)
		roof.name = "Roof"
	solid_box(g, Vector3(1.0, 1.9, 0.12), Transform3D(Basis(), Vector3(0.0, 0.95, 1.52)), wood, false)
	_blades = Node3D.new()
	_blades.name = "Blades"
	_blades.position = Vector3(0.0, 5.2, 1.75)
	g.add_child(_blades)
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = float(k) * PI * 0.5
		_blades.add_child(arm)
		solid_box(arm, Vector3(0.18, 4.4, 0.12), Transform3D(Basis(), Vector3(0.0, 2.2, 0.0)), wood, false)
		solid_box(arm, Vector3(1.0, 3.4, 0.04), Transform3D(Basis(), Vector3(0.55, 2.6, 0.04)), cloth, false)
	g.rotation.y = deg_to_rad(110.0)


## 北岛石阵：一圈 8 块立石，中间一块平躺的石台。
func _build_stone_ring(at: Vector2) -> void:
	var g := Node3D.new()
	g.name = "StoneRing"
	add_child(g)
	var rock := ArtMaterials.pbr("rock_face_03", Color(0.78, 0.76, 0.8), "world")
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var p := at + Vector2(cos(a), sin(a)) * 5.2
		var h := 2.2 + 0.6 * sin(float(k) * 1.9)
		solid_box(g, Vector3(0.9, h, 0.6), Transform3D(Basis(Vector3.UP, -a), Vector3(p.x, height_at(p.x, p.y) + h * 0.5 - 0.15, p.y)), rock)
	solid_box(g, Vector3(2.2, 0.5, 1.4), Transform3D(Basis(Vector3.UP, 0.4), Vector3(at.x, height_at(at.x, at.y) + 0.2, at.y)), rock)


## 东岛观鲸台：木平台、一条能坐的长椅、一架望远镜。
func _build_overlook(at: Vector2) -> void:
	var g := Node3D.new()
	g.name = "Overlook"
	add_child(g)
	var wood := ArtMaterials.pbr("weathered_planks", Color(0.9, 0.78, 0.64), "world")
	var y := height_at(at.x, at.y)
	solid_box(g, Vector3(5.0, 0.2, 3.0), Transform3D(Basis(), Vector3(at.x + 2.0, y + 0.1, at.y)), wood)
	var seat := Seat.create(&"cs_whale_bench", "长椅", Vector3(at.x + 2.0, y + 0.66, at.y + 0.6), 90.0, 0.45, 1.6)
	add_child(seat)
	solid_box(g, Vector3(0.5, 0.5, 1.8), Transform3D(Basis(), Vector3(at.x + 2.0, y + 0.45, at.y + 0.6)), wood, false)
	var brass := ArtMaterials.flat(Color(0.86, 0.66, 0.3), 0.35, false, 0.8)
	solid_box(g, Vector3(0.1, 1.3, 0.1), Transform3D(Basis(), Vector3(at.x + 3.8, y + 0.85, at.y - 0.8)), brass, false)
	var scope := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.11
	cm.height = 0.9
	scope.mesh = cm
	scope.material_override = brass
	scope.position = Vector3(at.x + 3.8, y + 1.55, at.y - 0.8)
	scope.rotation = Vector3(deg_to_rad(70.0), deg_to_rad(90.0), 0.0)
	add_child(scope)


## 灯塔岛的白塔：红白相间的圆筒，顶上一盏一直亮着的水晶灯。
func _build_lighthouse(at: Vector2) -> void:
	var g := Node3D.new()
	g.name = "Lighthouse"
	var base := height_at(at.x, at.y)
	g.position = Vector3(at.x, base - 0.2, at.y)
	add_child(g)
	var white := ArtMaterials.flat(Color(0.95, 0.93, 0.9), 0.7)
	var red := ArtMaterials.flat(Color(0.75, 0.25, 0.22), 0.7)
	for k in 6:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.9 - 0.08 * float(k + 1)
		cm.bottom_radius = 1.9 - 0.08 * float(k)
		cm.height = 1.5
		cm.radial_segments = 16
		seg.mesh = cm
		seg.material_override = red if k % 2 == 1 else white
		seg.position = Vector3(0.0, 0.75 + 1.5 * k, 0.0)
		g.add_child(seg)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	lamp.mesh = sm
	lamp.material_override = ArtMaterials.glow(Color(1.0, 0.9, 0.6), 4.0)
	lamp.position = Vector3(0.0, 9.9, 0.0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(lamp)
	var cap := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.1
	cc.bottom_radius = 1.3
	cc.height = 1.0
	cap.mesh = cc
	cap.material_override = red
	cap.position = Vector3(0.0, 11.1, 0.0)
	g.add_child(cap)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.88, 0.6)
	light.light_energy = 2.0
	light.omni_range = 18.0
	light.position = Vector3(0.0, 9.9, 0.0)
	g.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.9
	shape.height = 9.0
	cs.shape = shape
	cs.position = Vector3(0.0, 4.5, 0.0)
	body.add_child(cs)
	g.add_child(body)


## 岛上的松树、花和草（Kenney，CC0），避开桥头、地标、光门和小路。
func _build_greenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 990
	var avoid: Array[Vector3] = []   # (x, z, 半径)
	for p: Vector2 in [Vector2(-9, -7), Vector2(-55, -6), Vector2(6, -56), Vector2(57, 10), Vector2(10, -101)]:
		avoid.append(Vector3(p.x, p.y, 7.0))
	var gp := MiniWorld.v3(data["gate"]["pos"])
	avoid.append(Vector3(gp.x, gp.z, 6.0))
	avoid.append(Vector3(0.0, 13.5, 4.0))
	avoid.append(Vector3(9.0, 7.0, 6.0))
	for b in bridges:
		avoid.append(Vector3(b[0].x, b[0].z, 4.0))
		avoid.append(Vector3(b[-1].x, b[-1].z, 4.0))
	for s: Dictionary in data.get("signs", []):
		avoid.append(Vector3(float(s["pos"][0]), float(s["pos"][1]), 2.5))
	for it: Dictionary in data.get("items", []):
		avoid.append(Vector3(float(it["pos"][0]), float(it["pos"][1]), 2.0))
	for bd: Dictionary in data.get("beacons", []):
		avoid.append(Vector3(float(bd["pos"][0]), float(bd["pos"][1]), 3.0))
	var trees := ["tree_pineRoundA", "tree_pineRoundC", "tree_pineSmallA", "tree_fat", "tree_oak"]
	var small := ["flower_purpleA", "flower_redA", "flower_yellowA", "grass_large", "plant_bush", "grass_leafs"]
	var g := Node3D.new()
	g.name = "Greenery"
	add_child(g)
	for isl in islands:
		if str(isl["id"]) == "light":
			continue
		var c: Vector2 = isl["c"]
		var radius := float(isl["radius"])
		var n_tree := int(radius * 0.45)
		var n_small := int(radius * 1.6)
		for k in n_tree + n_small:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * _r_edge(isl, a) * 0.85
			var p := c + Vector2(cos(a), sin(a)) * r
			var ok := true
			for av in avoid:
				if p.distance_to(Vector2(av.x, av.y)) < av.z:
					ok = false
					break
			if not ok:
				continue
			var asset: String = trees[rng.randi() % trees.size()] if k < n_tree else small[rng.randi() % small.size()]
			var scale := rng.randf_range(2.2, 3.2) if k < n_tree else rng.randf_range(2.0, 3.0)
			g.add_child(ArtMaterials.kenney_prop(NATURE + asset + ".glb", Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y), rng.randf() * 360.0, scale))
			if k < n_tree:
				avoid.append(Vector3(p.x, p.y, 2.5))


## 天鲸：方块鲸鱼（和水族馆吊饰同一套像素盒子，放大成 20 m 长），绕着群岛慢慢游。
func _build_whale() -> void:
	whale_pivot = Node3D.new()
	whale_pivot.name = "SkyWhale"
	whale_pivot.position = Vector3(0.0, 0.0, -35.0)
	add_child(whale_pivot)
	whale = MeshInstance3D.new()
	whale.name = "Whale"
	var boxes := []
	for p: Array in PoolHouse.WHALE:
		boxes.append({"box": p.slice(0, 6), "color": p[6]})
	(whale as MeshInstance3D).mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return WHALE_COLORS.get(k, Color.WHITE), 0.5)
	whale.position = Vector3(WHALE_FAR.x, WHALE_FAR.y, 0.0)
	whale.add_to_group("sky_whale")
	whale_pivot.add_child(whale)
	_check_beacons(true)


func _on_beacon(_b: WindBeacon) -> void:
	_check_beacons(false)


func beacons_lit() -> int:
	var n := 0
	for b in beacons:
		if b.lit:
			n += 1
	return n


## 四座风灯都点亮：天鲸游近、升高，并提示一次（读档、回来时不再提示，直接在近处）。
func _check_beacons(instant: bool) -> void:
	if whale == null or beacons.is_empty():
		return
	var all := beacons_lit() == beacons.size()
	if not instant and beacons_lit() > 0 and not all:
		EventBus.toast_requested.emit(tr("风灯亮了（%d / %d）") % [beacons_lit(), beacons.size()])
	if all == whale_near:
		return
	whale_near = all
	var target := WHALE_NEAR if all else WHALE_FAR
	if instant:
		whale.position = Vector3(target.x, target.y, 0.0)
		return
	var tw := whale.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(whale, "position", Vector3(target.x, target.y, 0.0), 8.0)
	if all:
		WorldState.flags["cloudsea_beacons"] = true
		EventBus.toast_requested.emit(tr("四座风灯都亮了——天鲸游过来了！"))
		SaveManager.request_save()


func _process(delta: float) -> void:
	super._process(delta)
	if whale_pivot != null:
		whale_pivot.rotation.y += delta * (0.05 if whale_near else 0.035)
		whale_pivot.position.y = sin(Time.get_ticks_msec() * 0.0004) * 1.5
	if _blades != null:
		_blades.rotation.z += delta * 0.6
	for p in get_tree().get_nodes_in_group("cloud_puffs"):
		var n := p as Node3D
		n.position.x += delta * float(n.get_meta("drift"))
		if n.position.x > 180.0:
			n.position.x -= 360.0
	_update_parkour()


## 跳台计时（挑战模式）：踩上第一块石头开始计时，走上灯塔岛停表，记最好成绩。
func _update_parkour() -> void:
	if player == null or stones.is_empty() or GameRules.mode() != "challenge":
		return
	var p := player.global_position
	var first := stones[0]
	if _parkour_start < 0.0 and Vector2(p.x - first.x, p.z - first.z).length() < 1.0 and absf(p.y - first.y) < 0.6:
		_parkour_start = Time.get_ticks_msec() * 0.001
		EventBus.toast_requested.emit(tr("跳台计时开始！"))
	elif _parkour_start >= 0.0:
		var isl := island_at(p.x, p.z)
		if not isl.is_empty() and str(isl["id"]) == "light" and player.is_on_floor():
			var t := Time.get_ticks_msec() * 0.001 - _parkour_start
			_parkour_start = -1.0
			parkour_best = t if parkour_best <= 0.0 else minf(parkour_best, t)
			EventBus.toast_requested.emit(tr("登上灯塔岛：%.1f 秒（最好 %.1f 秒）") % [t, parkour_best])
		elif p.y < first.y - 6.0:
			_parkour_start = -1.0


# ---------------------------------------------------------------- 地图

func map_color(x: float, z: float, h: float) -> Color:
	if h < -1e6:
		var n := 0.5 + 0.5 * sin(x * 0.05 + z * 0.03)
		return Color(0.93, 0.84, 0.82).lerp(Color(0.82, 0.78, 0.9), n)
	var isl := island_at(x, z)
	var pond: Array = isl.get("pond", [])
	if not pond.is_empty() and Vector2(x - float(pond[0]), z - float(pond[1])).length() < float(pond[2]) * 0.92:
		return Color(0.4, 0.62, 0.78)
	return Color(0.45, 0.62, 0.34).lerp(Color(0.7, 0.75, 0.45), clampf((h - float(isl.get("top", 0.0))) / 3.0, 0.0, 1.0))


func draw_map(canvas: CanvasItem) -> void:
	for b in bridges:
		var line := PackedVector2Array()
		for p in b:
			line.append(Vector2(p.x, p.z))
		canvas.draw_polyline(line, Color(0.55, 0.38, 0.24), 1.8, true)
	for s in stones:
		canvas.draw_rect(Rect2(s.x - 0.8, s.z - 0.8, 1.6, 1.6), Color(0.55, 0.52, 0.58))
	canvas.draw_circle(Vector2(-9.0, -7.0), 3.0, Color(0.98, 0.7, 0.8))
	canvas.draw_circle(Vector2(10.0, -101.0), 2.0, Color(0.95, 0.93, 0.9))
	for b in beacons:
		canvas.draw_circle(Vector2(b.global_position.x, b.global_position.z), 1.3, Color(0.55, 0.85, 1.0) if b.lit else Color(0.35, 0.38, 0.45))


## 桥头正好搭在岛边上（往里 0.15 m）：桥面朝岛外往下斜，桥头要是往岛里收，桥面就会从岛边的土下面钻过去，人走到头被挡住。
func _bridge_head(isl: Dictionary, toward: Vector2) -> Vector3:
	var head := _rim_point(isl, toward, 0.15)
	head.y += 0.18   # 桥面在这 0.15 m 里往岛外降约 0.1 m，再留几厘米，桥面高过岛边那道土沿
	return head


## 桥头比岛边高出一点：往岛里接一段 1.4 m 的木板引坡，从桥头斜到地面，从岛上走上桥不会碰到一道坎。
func _landing(isl: Dictionary, head: Vector3) -> void:
	var c: Vector2 = isl["c"]
	var inward := (c - Vector2(head.x, head.z)).normalized()
	var g := Vector2(head.x, head.z) + inward * 1.4
	var foot := Vector3(g.x, height_at(g.x, g.y) - 0.03, g.y)
	var seg := foot - head
	var mid := (head + foot) * 0.5
	var yaw := atan2(seg.x, seg.z)
	var pitch := -atan2(seg.y, Vector2(seg.x, seg.z).length())
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	solid_box(self, Vector3(1.7, 0.08, seg.length()), Transform3D(basis, mid - basis.y * 0.04),
		ArtMaterials.pbr("weathered_planks", Color(0.92, 0.8, 0.66), "world"))
