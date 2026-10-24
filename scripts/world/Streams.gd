class_name Streams
extends Node3D
## 自然景观里的“东西”：小溪水面、瀑布水雾、溪边石头和芦苇、桥（world_layout.json → terrain.channels、nature.bridges）。
## 河床和裂谷本身是地形（WorldTerrain 的沟槽），这里只放地形之上的部分：
##   · 小溪：沿河床中线一条水带（stream_water.gdshader），每个点的水面宽度按两岸的实际地面算到“刚好没过岸边”，
##     流进湖里的地方结束；陡处顶点色标记成瀑布（白沫、流得快）；跌水底下一团水雾和溅起的水花；
##   · 溪边每隔几米一两块小石头，平缓处和入湖口长几丛芦苇；
##   · 桥：plank 木板桥（微拱、两侧栏杆）/ log 原木桥（两根原木做梁、木板桥面、原木扶手）；
##     桥面高度按两端地面自动定，桥面和栏杆都有碰撞，走在上面掉不下去。
## 节点放在原点，几何都是世界坐标。

const NATURE := "res://assets/imported/kenney/nature/"
const WATER_PROBE_STEP := 0.15

var bridges: Array[Node3D] = []
var water_meshes: Array[MeshInstance3D] = []
var mists: Array[CPUParticles3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("streams")
	_rng.seed = 4242
	for c in WorldTerrain.channels():
		if c["kind"] == "creek":
			_build_creek(c)
	for b: Dictionary in WorldLayout.section("nature").get("bridges", []):
		_build_bridge(b)


# ---------------------------------------------------------------- 小溪

func _build_creek(c: Dictionary) -> void:
	var pts: PackedVector2Array = c["pts"]
	var water: PackedFloat64Array = c["water"]
	var s: PackedFloat64Array = c["s"]
	var end: int = mini(int(c["wet_end"]) + 1, pts.size() - 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var steep := PackedFloat32Array()
	for i in end + 1:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var f := (b - a).normalized()
		var r := Vector2(-f.y, f.x)
		var y := float(water[i])
		var wl := _edge(pts[i], -r, y, float(c["outer"]))
		var wr := _edge(pts[i], r, y, float(c["outer"]))
		left.append(Vector3(pts[i].x - r.x * wl, y, pts[i].y - r.y * wl))
		right.append(Vector3(pts[i].x + r.x * wr, y, pts[i].y + r.y * wr))
		var drop := 0.0
		if i > 0:
			drop = (float(water[i - 1]) - y) / maxf(float(s[i] - s[i - 1]), 0.1)
		steep.append(clampf(drop / 0.6, 0.0, 1.0))
	for i in end:
		var v0 := float(s[i])
		var v1 := float(s[i + 1])
		var k0 := maxf(steep[i], steep[i + 1])
		_vert(st, left[i], Vector2(0.0, v0), k0)
		_vert(st, left[i + 1], Vector2(0.0, v1), k0)
		_vert(st, right[i + 1], Vector2(1.0, v1), k0)
		_vert(st, left[i], Vector2(0.0, v0), k0)
		_vert(st, right[i + 1], Vector2(1.0, v1), k0)
		_vert(st, right[i], Vector2(1.0, v0), k0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Water_" + str(c["id"])
	mi.mesh = st.commit()
	mi.material_override = ArtMaterials.stream_water()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	water_meshes.append(mi)
	# 瀑布底下的水雾和水花
	for fall: Array in c["falls"]:
		var j := s.bsearch(float(fall[0]))
		var k := mini(j + 1, end)
		var at := Vector3(pts[k].x, float(water[k]) + 0.1, pts[k].y)
		_mist(at)
		_lip_rocks(pts, water, j)
	_bank_dressing(c, end)


## 从中线沿 dir 往外找水面和岸边地面相交的地方（再往地里多伸 0.15 m，边缘埋进岸里看不见缝）。
func _edge(center: Vector2, dir: Vector2, y: float, outer: float) -> float:
	var d := 0.3
	while d < outer:
		var q := center + dir * d
		if WorldTerrain.height_at(q.x, q.y) > y + 0.02:
			return d + WATER_PROBE_STEP
		d += WATER_PROBE_STEP
	return outer


func _vert(st: SurfaceTool, p: Vector3, uv: Vector2, steep: float) -> void:
	st.set_color(Color(steep, 0.0, 0.0))
	st.set_uv(uv)
	st.add_vertex(p)


func _mist(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.name = "FallMist"
	p.position = at
	p.amount = 40
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.7
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0.0, -0.6, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	p.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# 圆形软边的雾团（不是方块）
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	puff.gradient = g
	mat.albedo_texture = puff
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = mat
	p.mesh = quad
	p.visibility_range_end = 70.0
	add_child(p)
	mists.append(p)


## 瀑布顶上两侧各一块大石头，夹住跌水口。
func _lip_rocks(pts: PackedVector2Array, water: PackedFloat64Array, j: int) -> void:
	var i := clampi(j - 1, 1, pts.size() - 2)
	var f := (pts[i + 1] - pts[i - 1]).normalized()
	var r := Vector2(-f.y, f.x)
	for side: float in [-1.0, 1.0]:
		var q := pts[i] + r * side * 1.9
		var rock := ArtMaterials.kenney_prop(NATURE + ("rock_largeA.glb" if side < 0.0 else "rock_largeC.glb"),
			Vector3(q.x, WorldTerrain.height_at(q.x, q.y) - 0.3, q.y), _rng.randf() * 360.0, 1.6)
		add_child(rock)


## 溪边的小石头和芦苇（不挡路：只放在水边，不放在桥头）。
func _bank_dressing(c: Dictionary, end: int) -> void:
	var pts: PackedVector2Array = c["pts"]
	var water: PackedFloat64Array = c["water"]
	var stones := ["rock_smallA", "rock_smallC", "rock_smallE", "rock_smallFlatA", "rock_smallFlatB"]
	for i in range(2, end, 3):
		var f := (pts[mini(i + 1, pts.size() - 1)] - pts[i - 1]).normalized()
		var r := Vector2(-f.y, f.x)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var y := float(water[i])
		var d := _edge(pts[i], r * side, y, float(c["outer"])) - 0.1
		var q := pts[i] + r * side * d + f * _rng.randf_range(-0.8, 0.8)
		if _near_bridge(q):
			continue
		var rock := ArtMaterials.kenney_prop(NATURE + "%s.glb" % stones[_rng.randi() % stones.size()],
			Vector3(q.x, WorldTerrain.height_at(q.x, q.y) - 0.05, q.y), _rng.randf() * 360.0, _rng.randf_range(1.6, 2.8))
		add_child(rock)
		# 平缓处、靠近湖的下游长芦苇
		if i > end * 0.45 and _rng.randf() < 0.55:
			var q2 := pts[i] - r * side * (_edge(pts[i], -r * side, y, float(c["outer"])) + 0.2)
			if not _near_bridge(q2):
				var reed := ArtMaterials.kenney_prop(NATURE + "plant_flatTall.glb",
					Vector3(q2.x, WorldTerrain.height_at(q2.x, q2.y) - 0.05, q2.y), _rng.randf() * 360.0, _rng.randf_range(2.8, 3.8))
				add_child(reed)


func _near_bridge(q: Vector2) -> bool:
	for b: Dictionary in WorldLayout.section("nature").get("bridges", []):
		var a := WorldLayout.v2(b["from"])
		var e := WorldLayout.v2(b["to"])
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, e)) < float(b.get("width", 1.6)) + 0.8:
			return true
	return false


# ---------------------------------------------------------------- 桥

## 桥面中线上 t（0..1）处的高度：两端正好贴着地面（人物不会迈台阶，桥头不能高出地面），
## 中间按两端地面直线过渡再拱起一点（木板桥拱得多些）。
static func deck_height(b: Dictionary, t: float) -> float:
	var a := WorldLayout.v2(b["from"])
	var e := WorldLayout.v2(b["to"])
	var ya := WorldTerrain.height_at(a.x, a.y)
	var ye := WorldTerrain.height_at(e.x, e.y)
	var arch := 0.45 if str(b.get("kind", "plank")) == "plank" else 0.25
	return lerpf(ya, ye, t) + arch * sin(PI * t)


func _build_bridge(b: Dictionary) -> void:
	var a := WorldLayout.v2(b["from"])
	var e := WorldLayout.v2(b["to"])
	var length := a.distance_to(e)
	var dir := (e - a) / length
	var width := float(b.get("width", 1.6))
	var kind := str(b.get("kind", "plank"))
	var root := Node3D.new()
	root.name = "Bridge_" + str(b["id"])
	add_child(root)
	bridges.append(root)
	var deck := ArtMaterials.named("M_Deck")
	var frame := ArtMaterials.named("M_Frame")
	var bark := ArtMaterials.pbr("pine_bark", Color(0.62, 0.52, 0.46), "world")
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	root.add_child(body)
	var yaw := atan2(dir.x, dir.y)
	var basis := Basis(Vector3.UP, yaw)
	var right := basis.x
	# 桥面：一块块横板 + 分段碰撞（跟着拱和坡度）
	var planks := int(ceil(length / 0.28))
	for i in planks:
		var t := (float(i) + 0.5) / planks
		var p2 := a.lerp(e, t)
		var y := deck_height(b, t)
		var slope := (deck_height(b, minf(t + 0.02, 1.0)) - deck_height(b, maxf(t - 0.02, 0.0))) / (0.04 * length)
		# basis 的本地 +Z 指向桥的前进方向，往前抬高要绕 X 轴转负角
		var pb := basis * Basis(Vector3.RIGHT, -atan(slope))
		_box(root, Vector3(width, 0.07, 0.25), Vector3(p2.x, y, p2.y), deck, pb)
	var segs := 8
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		_ramp(body, a.lerp(e, t0), deck_height(b, t0), a.lerp(e, t1), deck_height(b, t1), width, basis)
	# 桥头引坡：从桥头斜着接到外面 1.5 m 处的实际地面（地面高低不平也不会出现台阶）
	for end_pt: Array in [[a, -dir, deck_height(b, 0.0)], [e, dir, deck_height(b, 1.0)]]:
		var p_end: Vector2 = end_pt[0]
		var out: Vector2 = end_pt[1]
		var q := p_end + out * 1.5
		_ramp(body, q, WorldTerrain.height_at(q.x, q.y) - 0.04, p_end, float(end_pt[2]), width, basis)
	# 梁：木板桥两根方木，原木桥两根原木
	for side: float in [-1.0, 1.0]:
		for i in segs:
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			var p0 := a.lerp(e, t0) + Vector2(right.x, right.z) * side * (width * 0.5 - 0.12)
			var p1 := a.lerp(e, t1) + Vector2(right.x, right.z) * side * (width * 0.5 - 0.12)
			var y0 := deck_height(b, t0) - (0.22 if kind == "log" else 0.14)
			var y1 := deck_height(b, t1) - (0.22 if kind == "log" else 0.14)
			var mid := Vector3((p0.x + p1.x) * 0.5, (y0 + y1) * 0.5, (p0.y + p1.y) * 0.5)
			var seg_len := Vector2(p0.distance_to(p1), y1 - y0).length()
			var sb := basis * Basis(Vector3.RIGHT, -atan2(y1 - y0, p0.distance_to(p1)))
			if kind == "log":
				_log(root, mid, sb, seg_len + 0.02, 0.2, bark)
			else:
				_box(root, Vector3(0.12, 0.16, seg_len + 0.02), mid, frame, sb)
	# 栏杆：立柱 + 扶手（原木桥用细原木），两侧都有碰撞
	var posts := maxi(2, int(ceil(length / 1.4)) + 1)
	for side: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for i in posts:
			var t := float(i) / (posts - 1)
			var p2 := a.lerp(e, t) + Vector2(right.x, right.z) * side * (width * 0.5 - 0.05)
			var top := deck_height(b, t) + 0.95
			var post := Vector3(p2.x, top - 0.47, p2.y)
			if kind == "log":
				_log(root, post, Basis(Vector3.RIGHT, PI * 0.5), 0.95, 0.06, bark)
			else:
				_box(root, Vector3(0.08, 0.95, 0.08), post, frame, basis)
			var rail_pt := Vector3(p2.x, top, p2.y)
			if i > 0:
				var mid := (prev + rail_pt) * 0.5
				var seg := rail_pt - prev
				var rb := Basis.looking_at(seg.normalized(), Vector3.UP)
				if kind == "log":
					_log(root, mid, rb, seg.length() + 0.08, 0.05, bark)
				else:
					_box(root, Vector3(0.07, 0.07, seg.length() + 0.08), mid, frame, rb)
				_shape(body, Vector3(0.12, 1.1, seg.length()), mid - Vector3(0.0, 0.45, 0.0), rb)
			prev = rail_pt


## 一段桥面碰撞：从 (p0, y0) 到 (p1, y1) 的斜板，板面就在这条线上（厚 0.2 m，往下长）。
func _ramp(body: StaticBody3D, p0: Vector2, y0: float, p1: Vector2, y1: float, width: float, yaw_basis: Basis) -> void:
	var run := p0.distance_to(p1)
	var mid := Vector3((p0.x + p1.x) * 0.5, (y0 + y1) * 0.5, (p0.y + p1.y) * 0.5)
	var seg_len := Vector2(run, y1 - y0).length()
	# 板的前进方向：p0 → p1；yaw_basis 的本地 -Z 是 to → from 的反方向，所以按实际方向重算
	var fwd := Vector3(p1.x - p0.x, y1 - y0, p1.y - p0.y).normalized()
	var side := yaw_basis.x
	var up := side.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var bb := Basis(side, up, -fwd)
	_shape(body, Vector3(width, 0.2, seg_len + 0.05), mid - up * 0.1, bb)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, basis := Basis()) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)


## 原木：沿本地 -Z（basis 的前方）放倒的圆柱。
func _log(parent: Node3D, pos: Vector3, basis: Basis, length: float, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.08
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), pos)
	parent.add_child(mi)


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, pos)
	body.add_child(cs)
