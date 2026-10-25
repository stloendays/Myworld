class_name World04
extends MiniWorld
## 世界四「亚特兰蒂斯」：沉在海底的古城（布局在 data/worlds/atlantis.json）。
##   · 照柏拉图写的同心环：中央岛（山铜神殿 + 尖塔）、三圈水环（能游，ShapedWater 环形水体）、两圈陆环（房子、石柱、雕像、
##     台阶广场、发光的山铜纹路）、外沿；四个方向的石堤把各环连起来；
##   · 城罩在半径 62 m 的气泡穹顶里，里面是空气；穹顶外是海（整片海的水体减去穹顶这个球），水里不浮不沉、游得快一点；
##   · 海底：焦散光、珊瑚、海带林、礁石、沉船、光束、气泡泉，水族馆的鱼、蝠鲼、礁鲨、发光水母，一头方块鲸鱼；
##   · 光照随时刻变化（这里也有时钟）：白天蓝绿透亮，夜里暗下来，水母和山铜纹路更亮；
##   · 能做的事：氧气（离开穹顶开始消耗，气泡泉补满，耗尽回最近的泉）、光束谜题（五尊捧镜雕像 → 尖塔点亮 → 神殿开门）、
##     珍珠 / 贝壳 / 石板、洋流水渠（RailRide）、骑蝠鲼（RailRide）、6 个探索点、7 幅卷轴。

const NATURE := "res://assets/imported/kenney/nature/"
const SEAFLOOR_SHADER := preload("res://shaders/seafloor.gdshader")
const DOME_SHADER := preload("res://shaders/bubble_dome.gdshader")
const FLOW_SHADER := preload("res://shaders/water_flow.gdshader")
const OXYGEN_SECONDS := 75.0
const OXYGEN_SECONDS_HARD := 45.0
const MARBLE := Color(0.9, 0.88, 0.82)

var dome_r := 62.0
var rings: Array[Dictionary] = []          ## {id, r_in, r, h, water}
var canal_surface := -0.3
var canal_floor := -2.8
var causeway_hw := 2.25
var statues: Array[LightStatue] = []
var springs: Array[Vector3] = []
var spire: MeshInstance3D = null
var spire_light: OmniLight3D = null
var spire_beam: MeshInstance3D = null
var doors: Array[Node3D] = []
var door_open := false
var puzzle_done := false
var beam_points: PackedVector3Array = []    ## 当前光路的折点（自动检查读）
var sea: ShapedWater = null
var canals: Array[ShapedWater] = []
var current_ride: RailRide = null
var manta_ride: RailRide = null
var manta: Node3D = null
var oxygen := 1.0
var oxygen_outs := 0
var houses := 0
var columns := 0

var _sf: Dictionary = {}
var _beam_root: Node3D = null
var _beam_mat: StandardMaterial3D
var _ori_mat: StandardMaterial3D           ## 山铜纹路（随时刻变亮变暗）
var _spire_mat: StandardMaterial3D
var _jelly_mats: Array[Material] = []
var _floor_mat: ShaderMaterial
var _env: Environment
var _sky: ProceduralSkyMaterial
var _clock: WorldClock
var _light_t := 0.0
var _o2_bar: ProgressBar
var _o2_label: Label
var _o2_root: Control
var _spring_note := 0.0
var _current_cool := 0.0
var _o2_out := false
var _whale: Node3D = null
var _rng := RandomNumberGenerator.new()
var _segments: Array = []                  ## 光路的线段 [[a: Vector2, b: Vector2]]（房子、石柱避开它）
var _avoid: Array = []                     ## 房子、石柱要避开的点 [Vector2, 半径]


func _init() -> void:
	world_id = "world_04"


func _enter_tree() -> void:
	super._enter_tree()
	dome_r = float(data.get("dome", {}).get("radius", 62.0))
	var r_in := 0.0
	for r: Dictionary in data.get("rings", []):
		rings.append({"id": str(r["id"]), "r_in": r_in, "r": float(r["r"]), "h": float(r.get("h", 0.0)), "water": bool(r.get("water", false))})
		r_in = float(r["r"])
	canal_surface = float(data["canal"]["surface"])
	canal_floor = float(data["canal"]["floor"])
	causeway_hw = float(data["causeway"]["half_width"])
	_sf = data.get("seafloor", {})
	for s: Array in data.get("springs", []):
		springs.append(Vector3(float(s[0]), 0.0, float(s[1])))


# ---------------------------------------------------------------- 高度

## 城里：各环的地面（水环是水道底，石堤处是从内环到外环的缓坡）；穹顶外：起伏的海床，四周升起的海底悬崖。
func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var rim: Dictionary = rings[-1]
	if r < float(rim["r"]):
		for i in rings.size():
			var ring: Dictionary = rings[i]
			if r < float(ring["r"]):
				if not ring["water"]:
					return float(ring["h"])
				if absf(x) < causeway_hw or absf(z) < causeway_hw:
					var h_in := float(rings[i - 1]["h"])
					var h_out := float(rings[i + 1]["h"])
					return lerpf(h_in, h_out, (r - float(ring["r_in"])) / (float(ring["r"]) - float(ring["r_in"])))
				return canal_floor
	var sea_h := _seafloor(x, z)
	return lerpf(float(rim["h"]), sea_h, smoothstep(float(rim["r"]), float(rim["r"]) + 10.0, r))


func _seafloor(x: float, z: float) -> float:
	var h := float(_sf.get("base", -3.0)) + 1.3 * sin(x * 0.045 + 1.0) * sin(z * 0.038 - 0.4) + 0.7 * sin(x * 0.11 - z * 0.07) + 0.25 * sin(x * 0.31) * sin(z * 0.27)
	var mr := MiniWorld.v2(data["manta"]["rock"])
	var d := Vector2(x, z).distance_to(mr) / 7.0
	h += 3.6 * exp(-d * d * 1.2)
	for s in springs:
		var ds := Vector2(x, z).distance_to(Vector2(s.x, s.z)) / 4.0
		h += 0.8 * exp(-ds * ds)
	var e := maxf(absf(x), absf(z))
	h += float(_sf.get("boundary_height", 40.0)) * smoothstep(float(_sf.get("boundary_start", 108.0)), float(_sf.get("boundary_end", 128.0)), e)
	return h


## 在第几环（ring id），城外返回 "sea"。
func ring_at(x: float, z: float) -> String:
	var r := Vector2(x, z).length()
	for ring in rings:
		if r < float(ring["r"]):
			return str(ring["id"])
	return "sea"


func inside_dome(p: Vector3) -> bool:
	return p.length() < dome_r


# ---------------------------------------------------------------- 建造

func build_world() -> void:
	_rng.seed = 4040
	_prepare_avoid()
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = SEAFLOOR_SHADER
	var sand := ArtMaterials.pbr("damp_beach_sand", Color.WHITE, "world")
	_floor_mat.set_shader_parameter("albedo_tex", sand.albedo_texture)
	_floor_mat.set_shader_parameter("normal_tex", sand.normal_texture)
	var inner := Rect2(-70.0, -70.0, 140.0, 140.0)
	build_grid_terrain(inner, 1.0, _ground_color, _floor_mat, "City")
	var m := map_rect()
	for band: Rect2 in [Rect2(m.position.x, m.position.y, m.size.x, inner.position.y - m.position.y),
			Rect2(m.position.x, inner.end.y, m.size.x, m.end.y - inner.end.y),
			Rect2(m.position.x, inner.position.y, inner.position.x - m.position.x, inner.size.y),
			Rect2(inner.end.x, inner.position.y, m.end.x - inner.end.x, inner.size.y)]:
		build_grid_terrain(band, 2.0, _ground_color, _floor_mat, "Seafloor")
	_ori_mat = ArtMaterials.glow(Color(1.0, 0.5, 0.22), 2.2).duplicate() as StandardMaterial3D
	_build_water()
	_build_dome()
	_build_ring_lines()
	_build_causeway_rails()
	_build_temple()
	_build_spire()
	_build_light_source()
	_build_statues()
	_build_plaza()
	_build_aqueduct()
	_build_colonnades()
	_build_houses()
	_build_springs()
	_build_seabed()
	_build_wreck()
	_build_life()
	_build_manta()
	_clock = WorldClock.new()
	_clock.name = "WorldClock"
	add_child(_clock)
	_env = (get_node("WorldEnvironment") as WorldEnvironment).environment
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_recompute_beam()
	_update_lighting(true)


func _ground_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var r := Vector2(x, z).length()
	if r < float(rings[-1]["r"]):
		if h < canal_floor + 0.05:
			return Color(0.55, 0.62, 0.6)
		if n.y < 0.7:
			return MARBLE.darkened(0.12)
		var tile := 0.04 * float((int(floor(x * 0.5)) + int(floor(z * 0.5))) % 2)
		var col := MARBLE.darkened(tile)
		if absf(x) < causeway_hw or absf(z) < causeway_hw:
			col = Color(0.82, 0.78, 0.7)
		return col
	var deep := Color(0.62, 0.66, 0.58).lerp(Color(0.5, 0.6, 0.6), clampf(-h / 6.0, 0.0, 1.0))
	return deep.lerp(Color(0.48, 0.5, 0.46), smoothstep(0.75, 0.5, n.y))


func _prepare_avoid() -> void:
	# 光路（光井 → 五尊雕像 → 尖塔）
	var pts: Array[Vector2] = [MiniWorld.v2(data["light_source"]["pos"])]
	for s: Dictionary in data["statues"]:
		pts.append(MiniWorld.v2(s["pos"]))
	pts.append(MiniWorld.v2(data["spire"]["pos"]))
	for i in pts.size() - 1:
		_segments.append([pts[i], pts[i + 1]])
	for c: Array in data["current"]["points"]:
		_avoid.append([Vector2(float(c[0]), float(c[2])), 4.0])
	for it: Dictionary in data.get("items", []):
		_avoid.append([MiniWorld.v2(it["pos"]), 2.5])
	for s: Dictionary in data.get("signs", []):
		_avoid.append([Vector2(float(s["pos"][0]), float(s["pos"][1])), 3.0])
	for s: Dictionary in data.get("spawns", []):
		_avoid.append([MiniWorld.v2(s["pos"]), 3.0])
	_avoid.append([MiniWorld.v2(data["plaza"]["center"]), float(data["plaza"]["radius"]) + 2.5])
	for c: Dictionary in Play.courses():
		if str(c["world"]) == world_id:
			_avoid.append([Vector2(float(c["start"][0]), float(c["start"][2])), 4.0])
	for t: Dictionary in (Play.treasure_data.get("worlds", {}) as Dictionary).get(world_id, []):
		_avoid.append([MiniWorld.v2(t["pos"]), 3.0])


## 这个点（加上半径）离光路、水渠、收集品、石堤都够远吗。
func _clear(p: Vector2, radius: float) -> bool:
	if absf(p.x) < causeway_hw + 1.5 + radius or absf(p.y) < causeway_hw + 1.5 + radius:
		return false
	for seg: Array in _segments:
		if Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < radius + 2.0:
			return false
	for a: Array in _avoid:
		if p.distance_to(a[0]) < radius + float(a[1]):
			return false
	return true


# ---------------------------------------------------------------- 水与穹顶

func _build_water() -> void:
	var sea_cfg: Dictionary = data["sea"]
	var top := float(sea_cfg["top"])
	var bottom := float(sea_cfg["bottom"])
	var m := map_rect()
	sea = ShapedWater.create_sea(&"sea", Vector3(m.get_center().x, (top + bottom) * 0.5, m.get_center().y), Vector3(m.size.x + 20.0, top - bottom, m.size.y + 20.0),
		Vector3.ZERO, dome_r, float(sea_cfg.get("speed", 1.7)))
	add_child(sea)
	# 海面（从下往上看是一层晃动的亮面）和它下面一层看不见的顶，人游不出去
	var surf := MeshInstance3D.new()
	surf.name = "SeaSurface"
	var pm := PlaneMesh.new()
	pm.size = Vector2(m.size.x + 200.0, m.size.y + 200.0)
	surf.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = FLOW_SHADER
	sm.set_shader_parameter("deep", Color(0.3, 0.75, 0.85))
	sm.set_shader_parameter("foam", Color(0.85, 1.0, 1.0))
	sm.set_shader_parameter("stripes", 60.0)
	sm.set_shader_parameter("speed", 0.08)
	surf.material_override = sm
	surf.position = Vector3(0.0, top, 0.0)
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surf)
	var ceiling := StaticBody3D.new()
	ceiling.collision_layer = PhysicsLayers.WORLD
	ceiling.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(m.size.x + 40.0, 1.0, m.size.y + 40.0)
	cs.shape = box
	cs.position = Vector3(0.0, top - 0.5, 0.0)
	ceiling.add_child(cs)
	add_child(ceiling)
	# 三圈水环：水面 + 能游的环形水体
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.2, 0.62, 0.7, 0.78)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.05
	wmat.metallic_specular = 0.8
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for ring in rings:
		if not ring["water"]:
			continue
		var r0 := float(ring["r_in"])
		var r1 := float(ring["r"])
		var mi := MeshInstance3D.new()
		mi.name = "Canal_" + str(ring["id"])
		mi.mesh = _annulus(r0 - 0.4, r1 + 0.4, 96)
		mi.material_override = wmat
		mi.position.y = canal_surface
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var v := ShapedWater.create_ring(StringName(str(ring["id"])), Vector3(0.0, (canal_surface + canal_floor) * 0.5 - 0.1, 0.0), r0, r1, canal_surface - canal_floor + 0.2)
		add_child(v)
		canals.append(v)


## 平放的圆环面（水环的水面）。
static func _annulus(r0: float, r1: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var p00 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		st.set_normal(Vector3.UP)
		for p: Vector3 in [p00, p10, p01, p10, p11, p01]:
			st.add_vertex(p)
	return st.commit()


func _build_dome() -> void:
	var dome := MeshInstance3D.new()
	dome.name = "BubbleDome"
	var sm := SphereMesh.new()
	sm.radius = dome_r
	sm.height = dome_r
	sm.is_hemisphere = true
	sm.radial_segments = 72
	sm.rings = 24
	dome.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = DOME_SHADER
	dome.material_override = mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)


## 山铜纹路：每一圈环的边上一道发红光的细线。
func _build_ring_lines() -> void:
	for i in rings.size() - 1:
		var ring: Dictionary = rings[i]
		var r := float(ring["r"])
		var h := float(ring["h"]) if not ring["water"] else float(rings[i + 1]["h"])
		var line := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.16
		tm.outer_radius = r + 0.02
		tm.rings = 128
		tm.ring_segments = 4
		line.mesh = tm
		line.material_override = _ori_mat
		line.scale = Vector3(1.0, 0.25, 1.0)
		line.position.y = h + 0.02
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)


## 石堤过水的那一段两边的矮石栏（有碰撞，人掉不进水里），两头各一盏山铜灯柱。
func _build_causeway_rails() -> void:
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.86, 0.86, 0.8), "world")
	for i in rings.size():
		var ring: Dictionary = rings[i]
		if not ring["water"]:
			continue
		var r0 := float(ring["r_in"]) - 0.3
		var r1 := float(ring["r"]) + 0.3
		var h0 := float(rings[i - 1]["h"])
		var h1 := float(rings[i + 1]["h"])
		for k in 4:
			var axis := Vector2(sin(k * PI * 0.5), -cos(k * PI * 0.5))
			var side := Vector2(-axis.y, axis.x)
			for s: float in [-1.0, 1.0]:
				var a := axis * r0 + side * s * (causeway_hw - 0.15)
				var b := axis * r1 + side * s * (causeway_hw - 0.15)
				var pa := Vector3(a.x, h0 + 0.35, a.y)
				var pb := Vector3(b.x, h1 + 0.35, b.y)
				var mid := (pa + pb) * 0.5
				var seg := pb - pa
				var basis := Basis.looking_at(seg.normalized(), Vector3.UP)
				solid_box(self, Vector3(0.3, 0.7, seg.length()), Transform3D(basis, mid), stone)
				for end: Vector3 in [pb]:
					solid_box(self, Vector3(0.4, 1.6, 0.4), Transform3D(Basis(), end + Vector3(0.0, 0.45, 0.0)), stone, false)
					var lamp := MeshInstance3D.new()
					var sp := SphereMesh.new()
					sp.radius = 0.18
					sp.height = 0.36
					lamp.mesh = sp
					lamp.material_override = _ori_mat
					lamp.position = end + Vector3(0.0, 1.45, 0.0)
					add_child(lamp)


# ---------------------------------------------------------------- 神殿、尖塔、光路

func _build_temple() -> void:
	var t: Dictionary = data["temple"]
	var r: Array = t["rect"]
	var x0 := float(r[0])
	var z0 := float(r[1])
	var w := float(r[2])
	var d := float(r[3])
	var hgt := float(t["height"])
	var dw := float(t["door_width"])
	var y := height_at(x0 + w * 0.5, z0 + d * 0.5)
	var marble := ArtMaterials.pbr("rustic_stone_wall", Color(0.95, 0.93, 0.88), "world")
	var g := Node3D.new()
	g.name = "Temple"
	add_child(g)
	var th := 0.4
	var cx := x0 + w * 0.5
	var z1 := z0 + d
	solid_box(g, Vector3(w, hgt, th), Transform3D(Basis(), Vector3(cx, y + hgt * 0.5, z0 + th * 0.5)), marble)
	for sx: float in [-1.0, 1.0]:
		solid_box(g, Vector3(th, hgt, d), Transform3D(Basis(), Vector3(cx + sx * (w * 0.5 - th * 0.5), y + hgt * 0.5, z0 + d * 0.5)), marble)
	var side_w := (w - dw) * 0.5
	for sx: float in [-1.0, 1.0]:
		solid_box(g, Vector3(side_w, hgt, th), Transform3D(Basis(), Vector3(cx + sx * (dw * 0.5 + side_w * 0.5), y + hgt * 0.5, z1 - th * 0.5)), marble)
	solid_box(g, Vector3(dw, hgt - 3.2, th), Transform3D(Basis(), Vector3(cx, y + 3.2 + (hgt - 3.2) * 0.5, z1 - th * 0.5)), marble)
	solid_box(g, Vector3(w + 1.0, 0.4, d + 1.0), Transform3D(Basis(), Vector3(cx, y + hgt + 0.2, z0 + d * 0.5)), marble)
	# 屋顶山花（三角）和一圈山铜饰带
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 1.0, 1.6, d + 1.0)
	roof.mesh = pm
	roof.material_override = marble
	roof.position = Vector3(cx, y + hgt + 1.2, z0 + d * 0.5)
	g.add_child(roof)
	solid_box(g, Vector3(w + 0.1, 0.18, d + 0.1), Transform3D(Basis(), Vector3(cx, y + hgt - 0.5, z0 + d * 0.5)), _ori_mat, false)
	# 门前六根柱子
	for k in 6:
		var px := lerpf(x0 + 0.3, x0 + w - 0.3, float(k) / 5.0)
		if absf(px - cx) < dw * 0.5 + 0.3:
			continue
		_column(g, Vector3(px, y, z1 + 0.6), hgt, marble)
	# 两扇门（铰链在门洞两边，尖塔点亮后向里打开）
	var bronze := ArtMaterials.flat(Color(0.62, 0.42, 0.26), 0.4, false, 0.7)
	for sx: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "Door%s" % ("L" if sx < 0.0 else "R")
		pivot.position = Vector3(cx + sx * dw * 0.5, y, z1 - th * 0.5)
		g.add_child(pivot)
		solid_box(pivot, Vector3(dw * 0.5, 3.15, 0.14), Transform3D(Basis(), Vector3(-sx * dw * 0.25, 1.6, 0.0)), bronze)
		solid_box(pivot, Vector3(dw * 0.5 - 0.2, 0.12, 0.16), Transform3D(Basis(), Vector3(-sx * dw * 0.25, 2.2, 0.0)), _ori_mat, false)
		pivot.set_meta("side", sx)
		doors.append(pivot)
	# 殿里：山铜之心（石座上一块发光的晶体）和暖光
	solid_box(g, Vector3(1.0, 1.0, 1.0), Transform3D(Basis(), Vector3(cx, y + 0.5, z0 + 1.6)), marble)
	var heart := MeshInstance3D.new()
	var hp := PrismMesh.new()
	hp.size = Vector3(0.5, 0.9, 0.5)
	heart.mesh = hp
	heart.material_override = _ori_mat
	heart.position = Vector3(cx, y + 1.5, z0 + 1.6)
	heart.name = "OrichalcumHeart"
	g.add_child(heart)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.35)
	lamp.light_energy = 1.4
	lamp.omni_range = 8.0
	lamp.position = Vector3(cx, y + 2.6, z0 + d * 0.5)
	g.add_child(lamp)


func _column(parent: Node3D, base: Vector3, h: float, mat: Material) -> void:
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.36
	cm.height = h
	cm.radial_segments = 10
	col.mesh = cm
	col.material_override = mat
	col.position = base + Vector3(0.0, h * 0.5, 0.0)
	parent.add_child(col)
	solid_box(parent, Vector3(0.85, 0.22, 0.85), Transform3D(Basis(), base + Vector3(0.0, h - 0.11, 0.0)), mat, false)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = h
	cs.shape = shape
	cs.position = col.position
	body.add_child(cs)
	parent.add_child(body)


func _build_spire() -> void:
	var p := MiniWorld.v2(data["spire"]["pos"])
	var h := float(data["spire"]["height"])
	var y := height_at(p.x, p.y)
	var marble := ArtMaterials.pbr("rustic_stone_wall", Color(0.9, 0.88, 0.84), "world")
	solid_box(self, Vector3(2.2, 0.6, 2.2), Transform3D(Basis(), Vector3(p.x, y + 0.3, p.y)), marble)
	_spire_mat = StandardMaterial3D.new()
	_spire_mat.albedo_color = Color(0.75, 0.42, 0.25)
	_spire_mat.metallic = 0.85
	_spire_mat.roughness = 0.3
	_spire_mat.emission_enabled = true
	_spire_mat.emission = Color(1.0, 0.45, 0.2)
	_spire_mat.emission_energy_multiplier = 0.15
	spire = MeshInstance3D.new()
	spire.name = "OrichalcumSpire"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.75
	cm.height = h
	cm.radial_segments = 4
	spire.mesh = cm
	spire.material_override = _spire_mat
	spire.position = Vector3(p.x, y + 0.6 + h * 0.5, p.y)
	spire.rotation.y = PI * 0.25
	add_child(spire)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.8
	shape.height = h
	cs.shape = shape
	cs.position = spire.position
	body.add_child(cs)
	add_child(body)
	spire_light = OmniLight3D.new()
	spire_light.light_color = Color(1.0, 0.55, 0.3)
	spire_light.light_energy = 3.0
	spire_light.omni_range = 34.0
	spire_light.position = Vector3(p.x, y + h * 0.7, p.y)
	spire_light.visible = false
	add_child(spire_light)
	spire_beam = MeshInstance3D.new()
	spire_beam.name = "SpireBeam"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.6
	bm.bottom_radius = 0.2
	bm.height = dome_r - h
	bm.cap_top = false
	bm.cap_bottom = false
	spire_beam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.6, 0.3, 0.35)
	spire_beam.material_override = mat
	spire_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spire_beam.position = Vector3(p.x, y + h + (dome_r - h) * 0.5, p.y)
	spire_beam.visible = false
	add_child(spire_beam)


## 光井：北边外沿的一根高石柱，顶上一块会发光的水晶，光从这里往南射出。
func _build_light_source() -> void:
	var p := MiniWorld.v2(data["light_source"]["pos"])
	var y := height_at(p.x, p.y)
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.85, 0.86, 0.82), "world")
	solid_box(self, Vector3(1.4, 2.0, 1.4), Transform3D(Basis(), Vector3(p.x, y + 1.0, p.y)), stone)
	var crystal := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.6, 1.0, 0.6)
	crystal.mesh = pm
	crystal.material_override = ArtMaterials.glow(Color(1.0, 0.92, 0.7), 4.0)
	crystal.position = Vector3(p.x, y + 2.5, p.y)
	add_child(crystal)
	# 从穹顶顶上落下来的一道光柱
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 0.5
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	shaft.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.9, 0.95, 1.0, 0.18)
	shaft.material_override = mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(p.x, y + 2.5 + 15.0, p.y)
	add_child(shaft)
	_beam_root = Node3D.new()
	_beam_root.name = "LightBeam"
	add_child(_beam_root)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Color(1.0, 0.85, 0.55, 0.85)


func _build_statues() -> void:
	for s: Dictionary in data["statues"]:
		var st := LightStatue.create(str(s["id"]), int(s["start"]), int(s["correct"]))
		var p := MiniWorld.v2(s["pos"])
		st.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		add_child(st)
		st.turned.connect(_on_statue_turned)
		statues.append(st)


func _on_statue_turned(_s: LightStatue) -> void:
	_recompute_beam()


## 追光路：从光井往南，碰到雕像就按它镜子的朝向拐弯；照到尖塔就点亮。
func _recompute_beam() -> void:
	if _beam_root == null or statues.is_empty():
		return
	for c in _beam_root.get_children():
		c.queue_free()
	for st in statues:
		st.set_lit(false)
	var src := MiniWorld.v2(data["light_source"]["pos"])
	var pos := Vector3(src.x, height_at(src.x, src.y) + 2.5, src.y)
	var dir := LightStatue.dir_vector(int(data["light_source"]["dir"]))
	var spire_p := MiniWorld.v2(data["spire"]["pos"])
	var pts := PackedVector3Array([pos])
	var reached := false
	var visited := {}
	for step in 8:
		var best_t := 90.0
		var hit: LightStatue = null
		var here := Vector2(pos.x, pos.z)
		for st in statues:
			if visited.has(st):
				continue
			var sp := Vector2(st.global_position.x, st.global_position.z)
			var t := (sp - here).dot(dir)
			if t > 0.5 and t < best_t and absf((sp - here).cross(dir)) < 0.8:
				best_t = t
				hit = st
		var ts := (spire_p - here).dot(dir)
		if ts > 0.5 and ts < best_t and absf((spire_p - here).cross(dir)) < 1.0:
			pos = Vector3(spire_p.x, pos.y, spire_p.y)
			pts.append(pos)
			reached = true
			break
		if hit == null:
			var end := here + dir * best_t
			pts.append(Vector3(end.x, pos.y, end.y))
			break
		visited[hit] = true
		hit.set_lit(true)
		pos = hit.global_position + Vector3(0.0, 2.0, 0.0)
		pts.append(pos)
		dir = LightStatue.dir_vector(hit.dir)
	beam_points = pts
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.09, a.distance_to(b))
		mi.mesh = bm
		mi.material_override = _beam_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5)
		_beam_root.add_child(mi)
	_set_puzzle(reached, false)


func _set_puzzle(done: bool, instant: bool) -> void:
	var was := puzzle_done
	puzzle_done = done
	_spire_mat.emission_energy_multiplier = 4.5 if done else 0.15
	spire_light.visible = done
	spire_beam.visible = done
	if done and not was:
		if not WorldState.flags.get("atlantis_spire", false):
			WorldState.flags["atlantis_spire"] = true
			EventBus.toast_requested.emit(tr("光照到了山铜尖塔——尖塔亮了，神殿的大门开了！"))
			SaveManager.request_save()
	# 门：尖塔亮过一次就一直开着（存档里的 atlantis_spire）
	set_doors(done or bool(WorldState.flags.get("atlantis_spire", false)), instant or not done)


func set_doors(open: bool, instant: bool) -> void:
	if open == door_open and not instant:
		return
	door_open = open
	for pivot in doors:
		var target := deg_to_rad(100.0) * float(pivot.get_meta("side")) * -1.0 if open else 0.0
		if instant:
			pivot.rotation.y = target
		else:
			pivot.create_tween().tween_property(pivot, "rotation:y", target, 2.5).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- 城里的东西

## 台阶广场：三层圆台（喷泉座）+ 中间的喷泉。
func _build_plaza() -> void:
	var c := MiniWorld.v2(data["plaza"]["center"])
	var y := height_at(c.x, c.y)
	var marble := ArtMaterials.pbr("rustic_stone_wall", Color(0.94, 0.92, 0.86), "world")
	var radii := [3.2, 2.4, 1.6]
	for i in 3:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radii[i]
		cm.bottom_radius = radii[i]
		cm.height = 0.32
		cm.radial_segments = 32
		mi.mesh = cm
		mi.material_override = marble
		mi.position = Vector3(c.x, y + 0.16 + i * 0.32, c.y)
		add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 3.2
	shape.height = 1.0
	cs.shape = shape
	cs.position = Vector3(c.x, y + 0.5, c.y)
	body.add_child(cs)
	add_child(body)
	var water := MeshInstance3D.new()
	var wc := CylinderMesh.new()
	wc.top_radius = 0.12
	wc.bottom_radius = 0.35
	wc.height = 2.4
	wc.cap_top = false
	wc.cap_bottom = false
	water.mesh = wc
	var fm := ShaderMaterial.new()
	fm.shader = FLOW_SHADER
	fm.set_shader_parameter("speed", -1.2)
	water.material_override = fm
	water.position = Vector3(c.x, y + 0.96 + 1.2, c.y)
	add_child(water)
	# 广场四周一圈石柱
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.9, 0.88, 0.82), "world")
	for k in 8:
		var a := float(k) / 8.0 * TAU + 0.2
		var p := c + Vector2(cos(a), sin(a)) * (float(data["plaza"]["radius"]) + 1.2)
		if _on_segment(p, 1.0):
			continue
		_column(self, Vector3(p.x, height_at(p.x, p.y), p.y), 3.0, stone)


func _on_segment(p: Vector2, margin: float) -> bool:
	for seg: Array in _segments:
		if Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < margin + 1.0:
			return true
	return false


## 洋流水渠：入口漩涡泉 → 水柱托上去 → 架在石拱上的水渠横穿全城 → 东头落进水池。人走进漩涡泉就被水流带着走（RailRide）。
func _build_aqueduct() -> void:
	var cfg: Dictionary = data["current"]
	var pts := PackedVector3Array()
	for a: Array in cfg["points"]:
		pts.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	current_ride = RailRide.new()
	current_ride.name = "CurrentRide"
	add_child(current_ride)
	var ex: Array = cfg["exit"]
	current_ride.setup(pts, float(cfg["speed"]), Vector3(float(ex[0]), float(ex[1]), float(ex[2])))
	current_ride.pose = "sit"
	current_ride.prompt_text = "被水流冲着走……"
	current_ride.rider_offset = Vector3(0.0, -0.35, 0.0)
	current_ride.finished.connect(_on_current_done)
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.82, 0.84, 0.8), "world")
	var flow := ShaderMaterial.new()
	flow.shader = FLOW_SHADER
	flow.set_shader_parameter("speed", 2.4)
	flow.set_shader_parameter("stripes", 1.0)
	# 水渠槽：沿路线每 3 m 一段（从水柱顶到落水处），下面每隔 9 m 一个石拱墩
	var curve := current_ride.curve
	var length := curve.get_baked_length()
	var start := curve.get_closest_offset(pts[1]) + 1.0
	var finish := curve.get_closest_offset(pts[pts.size() - 2])
	var step := 3.0
	var s := start
	var next_pier := start + 4.0
	var trough := SurfaceTool.new()
	trough.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := 0.0
	while s < finish:
		var a := curve.sample_baked(s)
		var b := curve.sample_baked(minf(s + step, finish))
		var mid := (a + b) * 0.5
		var seg := b - a
		if seg.length() < 0.1:
			break
		var basis := Basis.looking_at(seg.normalized(), Vector3.UP)
		# 槽底和两道槽壁、槽里的水面：都并进一个网格（几十段水渠不必各是一个节点）
		_append_box(trough, Transform3D(basis, mid - basis.y * 0.55), Vector3(1.8, 0.25, seg.length() + 0.05))
		for sx: float in [-1.0, 1.0]:
			_append_box(trough, Transform3D(basis, mid + basis.x * sx * 0.85 - basis.y * 0.2), Vector3(0.2, 0.7, seg.length() + 0.05))
		var wa := a - basis.y * 0.3
		var wb := b - basis.y * 0.3
		var side := basis.x * 0.75
		var v0 := run / 3.0
		var v1 := (run + seg.length()) / 3.0
		for vt: Array in [[wa - side, Vector2(0, v0)], [wa + side, Vector2(1, v0)], [wb - side, Vector2(0, v1)], [wa + side, Vector2(1, v0)], [wb + side, Vector2(1, v1)], [wb - side, Vector2(0, v1)]]:
			ribbon.set_uv(vt[1])
			ribbon.set_normal(Vector3.UP)
			ribbon.add_vertex(vt[0])
		run += seg.length()
		if s >= next_pier:
			next_pier += 9.0
			if absf(mid.x) < causeway_hw + 1.2 or absf(mid.z) < causeway_hw + 1.2:
				s += step
				continue
			var gy := height_at(mid.x, mid.z)
			var ph := mid.y - 0.7 - gy
			if ph > 0.5:
				solid_box(self, Vector3(1.0, ph, 1.0), Transform3D(basis, Vector3(mid.x, gy + ph * 0.5, mid.z)), stone)
		s += step
	trough.generate_normals()
	var tmi := MeshInstance3D.new()
	tmi.name = "AqueductTrough"
	tmi.mesh = trough.commit()
	tmi.material_override = stone
	add_child(tmi)
	var wmi := MeshInstance3D.new()
	wmi.name = "AqueductWater"
	wmi.mesh = ribbon.commit()
	wmi.material_override = flow
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wmi)
	# 入口：漩涡泉（一圈石沿 + 打转的水面）和往上冲的水柱
	var inlet := MiniWorld.v2(cfg["inlet"])
	var iy := height_at(inlet.x, inlet.y)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.5
	tm.outer_radius = 1.85
	ring.mesh = tm
	ring.material_override = stone
	ring.position = Vector3(inlet.x, iy + 0.1, inlet.y)
	ring.scale = Vector3(1.0, 0.6, 1.0)
	add_child(ring)
	var swirl := MeshInstance3D.new()
	swirl.name = "Swirl"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 1.5
	cm.height = 0.02
	swirl.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = FLOW_SHADER
	sm.set_shader_parameter("stripes", 3.0)
	swirl.material_override = sm
	swirl.position = Vector3(inlet.x, iy + 0.12, inlet.y)
	add_child(swirl)
	var spout := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.8
	sc.bottom_radius = 1.1
	sc.height = pts[1].y - iy
	sc.cap_top = false
	sc.cap_bottom = false
	spout.mesh = sc
	var spm := ShaderMaterial.new()
	spm.shader = FLOW_SHADER
	spm.set_shader_parameter("speed", -2.5)
	spm.set_shader_parameter("stripes", 4.0)
	spout.material_override = spm
	spout.position = Vector3(inlet.x, iy + sc.height * 0.5, inlet.y)
	add_child(spout)
	# 东头的落水池
	var last := pts[pts.size() - 1]
	var pool := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 2.2
	pc.bottom_radius = 2.2
	pc.height = 0.02
	pool.mesh = pc
	pool.material_override = sm
	pool.position = Vector3(last.x, height_at(last.x, last.z) + 0.1, last.z)
	add_child(pool)


func _on_current_done(_rider: Node, completed: bool) -> void:
	_current_cool = 3.0
	if completed and not WorldState.flags.get("current_ride", false):
		WorldState.flags["current_ride"] = true
		SaveManager.request_save()
	if completed:
		EventBus.toast_requested.emit(tr("哗——被水流一路冲到了城东头"))


## 两圈陆环上的柱廊：陆环一外沿、陆环二内沿每隔一段一根石柱，避开石堤、光路和水渠。
func _build_colonnades() -> void:
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.93, 0.91, 0.86), "world")
	var bases: Array[Vector3] = []
	for spec: Array in [[27.6, 0.6, 36], [36.4, 0.4, 44]]:
		var r := float(spec[0])
		var n := int(spec[2])
		for k in n:
			var a := float(k) / n * TAU
			var p := Vector2(cos(a), sin(a)) * r
			if _clear(p, 0.4):
				bases.append(Vector3(p.x, float(spec[1]), p.y))
	# 几十根一样的柱子：柱身、柱头各一个 MultiMesh，碰撞是一个 StaticBody 下的一串圆柱（节点少）
	var h := 3.4
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.3
	shaft.bottom_radius = 0.36
	shaft.height = h
	shaft.radial_segments = 10
	var cap := BoxMesh.new()
	cap.size = Vector3(0.85, 0.22, 0.85)
	var body := StaticBody3D.new()
	body.name = "Colonnade"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = h
	for spec: Array in [[shaft, h * 0.5], [cap, h - 0.11]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		mm.instance_count = bases.size()
		for i in bases.size():
			mm.set_instance_transform(i, Transform3D(Basis(), bases[i] + Vector3(0.0, float(spec[1]), 0.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = stone
		add_child(mmi)
	for b in bases:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = b + Vector3(0.0, h * 0.5, 0.0)
		body.add_child(cs)
	columns = bases.size()


## 城里的房子：方块石屋（白墙、平顶或三角山花、门口一道山铜饰带），沿两圈陆环摆放，避开路、光路和水渠。
func _build_houses() -> void:
	var walls := [Color(0.95, 0.93, 0.88), Color(0.9, 0.86, 0.78), Color(0.86, 0.88, 0.9), Color(0.93, 0.84, 0.76)]
	for spec: Array in [[17.5, 27.0, 0.6, 30], [37.5, 47.5, 0.4, 44]]:
		var tries := 0
		var placed := 0
		while placed < int(spec[3]) and tries < 400:
			tries += 1
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(float(spec[0]) + 2.0, float(spec[1]) - 2.0)
			var p := Vector2(cos(a), sin(a)) * r
			var size := Vector2(_rng.randf_range(3.0, 5.0), _rng.randf_range(3.5, 6.0))
			var rad := size.length() * 0.5
			if not _clear(p, rad):
				continue
			_avoid.append([p, rad + 1.2])
			var yaw := -a + PI * 0.5
			_house(p, float(spec[2]), size, _rng.randf_range(2.6, 4.2), yaw, walls[_rng.randi() % walls.size()])
			placed += 1
			houses += 1


func _house(p: Vector2, y: float, size: Vector2, h: float, yaw: float, col: Color) -> void:
	var mat := ArtMaterials.pbr("rustic_stone_wall", col, "world")
	var basis := Basis(Vector3.UP, yaw)
	var c := Vector3(p.x, y, p.y)
	solid_box(self, Vector3(size.x, h, size.y), Transform3D(basis, c + Vector3(0.0, h * 0.5, 0.0)), mat)
	solid_box(self, Vector3(size.x + 0.4, 0.25, size.y + 0.4), Transform3D(basis, c + Vector3(0.0, h + 0.12, 0.0)), mat, false)
	if _rng.randf() < 0.5:
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(size.x + 0.4, 1.0, size.y + 0.4)
		roof.mesh = pm
		roof.material_override = mat
		roof.transform = Transform3D(basis, c + Vector3(0.0, h + 0.75, 0.0))
		add_child(roof)
	# 朝外一侧：深色门洞和一道山铜饰带
	var front := basis * Vector3(0.0, 0.0, size.y * 0.5 + 0.01)
	solid_box(self, Vector3(1.0, 1.9, 0.04), Transform3D(basis, c + front + Vector3(0.0, 0.95, 0.0)), ArtMaterials.flat(Color(0.18, 0.2, 0.22), 0.9), false)
	solid_box(self, Vector3(size.x, 0.1, 0.04), Transform3D(basis, c + front + Vector3(0.0, h - 0.4, 0.0)), _ori_mat, false)


# ---------------------------------------------------------------- 穹顶外

func _build_springs() -> void:
	var rock := ArtMaterials.pbr("rock_face_03", Color(0.6, 0.66, 0.66), "world")
	var glow := ArtMaterials.glow(Color(0.55, 0.95, 1.0), 2.0)
	for i in springs.size():
		var s := springs[i]
		s.y = height_at(s.x, s.z)
		springs[i] = s
		for k in 6:
			var a := float(k) / 6.0 * TAU
			solid_box(self, Vector3(0.9, 0.7, 0.9), Transform3D(Basis(Vector3.UP, a), s + Vector3(cos(a) * 1.4, 0.2, sin(a) * 1.4)), rock)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.6
		tm.outer_radius = 0.8
		ring.mesh = tm
		ring.material_override = glow
		ring.position = s + Vector3(0.0, 0.3, 0.0)
		add_child(ring)
		var b := ReefTank._bubbles(s + Vector3(0.0, 0.3, 0.0), float(data["sea"]["top"]) - s.y)
		b.amount = 60
		b.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		b.emission_sphere_radius = 0.5
		b.scale_amount_max = 2.2
		add_child(b)


## 海底：珊瑚丛、海带林、礁石、光束、零星的冒泡口。
func _build_seabed() -> void:
	var placed := 0
	var tries := 0
	while placed < 40 and tries < 600:
		tries += 1
		var p := Vector2(_rng.randf_range(-104.0, 104.0), _rng.randf_range(-104.0, 104.0))
		if p.length() < dome_r + 6.0 or not _sea_clear(p, 4.0):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = PoolHouse._coral_mesh(_rng)
		var s := _rng.randf_range(2.2, 3.4)
		mi.scale = Vector3(s, s, s)
		mi.position = Vector3(p.x, height_at(p.x, p.y) - 0.1, p.y)
		mi.rotation.y = _rng.randf() * TAU
		add_child(mi)
		placed += 1
	for f: Array in data.get("kelp_forests", []):
		var c := Vector2(float(f[0]), float(f[1]))
		var rad := float(f[2])
		for k in 18:
			var p := c + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * rad
			if not _sea_clear(p, 1.0):
				continue
			ReefTank._kelp(self, Vector3(p.x, height_at(p.x, p.y) - 0.1, p.y), _rng.randf_range(6.0, 14.0), _rng)
	var rocks := ["rock_largeA", "rock_largeB", "rock_largeC", "rock_largeD", "rock_largeE", "rock_tallA", "rock_tallB"]
	var rock_mat := ArtMaterials.pbr("rock_face_03", Color(0.55, 0.62, 0.62), "world", -0.1)
	placed = 0
	tries = 0
	while placed < 26 and tries < 400:
		tries += 1
		var p := Vector2(_rng.randf_range(-106.0, 106.0), _rng.randf_range(-106.0, 106.0))
		if p.length() < dome_r + 8.0 or not _sea_clear(p, 6.0):
			continue
		var node := ArtMaterials.kenney_prop(NATURE + str(rocks[placed % rocks.size()]) + ".glb", Vector3(p.x, height_at(p.x, p.y) - 0.3, p.y), _rng.randf() * 360.0, _rng.randf_range(4.0, 8.0))
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = rock_mat
		add_child(node)
		placed += 1
	# 蝠鲼礁：一块平顶大礁石
	var mr := MiniWorld.v2(data["manta"]["rock"])
	var big := ArtMaterials.kenney_prop(NATURE + "rock_largeD.glb", Vector3(mr.x, height_at(mr.x, mr.y) - 1.5, mr.y), 30.0, 9.0)
	for mi: MeshInstance3D in big.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = rock_mat
	add_child(big)
	for i in 12:
		var a := float(i) / 12.0 * TAU + 0.3
		var r := _rng.randf_range(70.0, 100.0)
		var p := Vector3(cos(a) * r, 16.0, sin(a) * r)
		var sh := ReefTank._shaft(p, 40.0, i)
		sh.scale = Vector3(3.0, 1.0, 3.0)
		add_child(sh)


func _sea_clear(p: Vector2, radius: float) -> bool:
	for a: Array in _avoid:
		if p.distance_to(a[0]) < radius + float(a[1]):
			return false
	for s in springs:
		if p.distance_to(Vector2(s.x, s.z)) < radius + 3.0:
			return false
	if p.distance_to(MiniWorld.v2(data["manta"]["rock"])) < radius + 8.0 or p.distance_to(MiniWorld.v2(data["wreck"]["pos"])) < radius + 12.0:
		return false
	for c: Dictionary in Play.courses():
		if str(c["world"]) == world_id:
			for pt: Array in c["points"]:
				if p.distance_to(Vector2(float(pt[0]), float(pt[2]))) < radius + 4.0:
					return false
	return true


## 沉船：方块船身斜插在沙里，一根断了的桅杆。
func _build_wreck() -> void:
	var w: Dictionary = data["wreck"]
	var p := MiniWorld.v2(w["pos"])
	var root := Node3D.new()
	root.name = "Shipwreck"
	root.position = Vector3(p.x, height_at(p.x, p.y) - 0.6, p.y)
	root.rotation = Vector3(deg_to_rad(4.0), deg_to_rad(float(w["yaw_deg"])), deg_to_rad(14.0))
	add_child(root)
	var wood := ArtMaterials.pbr("weathered_planks", Color(0.45, 0.36, 0.3), "world")
	var dark := ArtMaterials.pbr("weathered_planks", Color(0.3, 0.24, 0.2), "world")
	solid_box(root, Vector3(4.4, 2.2, 14.0), Transform3D(Basis(), Vector3(0.0, 1.1, 0.0)), wood)
	solid_box(root, Vector3(3.4, 1.6, 3.0), Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.0, 1.6, -7.6)), wood)
	solid_box(root, Vector3(4.6, 0.2, 13.6), Transform3D(Basis(), Vector3(0.0, 2.3, 0.4)), dark)
	solid_box(root, Vector3(3.8, 1.8, 3.6), Transform3D(Basis(), Vector3(0.0, 3.2, 5.0)), wood)
	solid_box(root, Vector3(0.4, 7.0, 0.4), Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(0.6, 5.5, -1.0)), dark)
	solid_box(root, Vector3(0.3, 4.0, 0.3), Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(-1.0, 0.6, 9.0)), dark, false)


## 鱼、水母、鲸鱼。
func _build_life() -> void:
	var schools := [
		[AABB(Vector3(60.0, 1.0, -78.0), Vector3(34.0, 12.0, 34.0)), ["silver_fish", "blue_tang", "yellow_tang"]],
		[AABB(Vector3(-92.0, 0.0, 28.0), Vector3(34.0, 12.0, 34.0)), ["clownfish", "silver_fish", "turtle"]],
		[AABB(Vector3(-100.0, 4.0, -100.0), Vector3(200.0, 22.0, 200.0)), ["manta_ray", "reef_shark", "reef_shark"]],
		[AABB(Vector3(66.0, 10.0, 10.0), Vector3(22.0, 14.0, 22.0)), ["jellyfish"]],
		[AABB(Vector3(-24.0, 12.0, 68.0), Vector3(30.0, 14.0, 22.0)), ["jellyfish"]],
	]
	for i in schools.size():
		var fs := FishSchool.new()
		fs.name = "Life_%d" % i
		fs.bounds = schools[i][0]
		fs.species_list = schools[i][1]
		fs.seed_value = 7000 + i
		add_child(fs)
	# 方块鲸鱼：在城外慢慢绕大圈
	var pivot := Node3D.new()
	pivot.name = "WhalePivot"
	add_child(pivot)
	var boxes := []
	for p: Array in PoolHouse.WHALE:
		boxes.append({"box": p.slice(0, 6), "color": p[6]})
	var whale := MeshInstance3D.new()
	whale.name = "Whale"
	whale.add_to_group("atl_whale")
	whale.mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return PoolHouse.DECOR_COLORS.get(k, Color.WHITE), 0.55)
	whale.position = Vector3(96.0, 20.0, 0.0)
	whale.rotation.y = PI
	pivot.add_child(whale)
	_whale = pivot


func jelly_count() -> int:
	var n := 0
	for fs in find_children("Life_*", "FishSchool", false, false):
		for m: Dictionary in (fs as FishSchool).members:
			if str((m["def"] as Dictionary).get("locomotion", "")) == "jelly":
				n += 1
	return n


## 骑蝠鲼：大蝠鲼在蝠鲼礁上歇着，看着它按 E 抓住，沿城外一大圈游一圈再回来（RailRide，可以按 E 松手）。
func _build_manta() -> void:
	var cfg: Dictionary = data["manta"]
	var rock := MiniWorld.v2(cfg["rock"])
	var rest := Vector3(rock.x, height_at(rock.x, rock.y) + 1.4, rock.y)
	var radius := float(cfg["radius"])
	var h := float(cfg["height"])
	var start_a := atan2(rock.y, rock.x)
	var pts := PackedVector3Array([rest])
	var first := Vector3(cos(start_a) * radius, h, sin(start_a) * radius)
	pts.append(rest.lerp(first, 0.5) + Vector3(0.0, 2.0, 0.0))
	for k in range(1, 25):
		var a := start_a + float(k) / 24.0 * TAU
		pts.append(Vector3(cos(a) * radius, h + 4.0 * sin(a * 3.0), sin(a) * radius))
	pts.append(rest + Vector3(0.0, 1.5, 0.0))
	pts.append(rest)
	manta_ride = RailRide.new()
	manta_ride.name = "MantaRide"
	add_child(manta_ride)
	manta = Node3D.new()
	manta.name = "BigManta"
	manta.add_to_group("atl_manta")
	add_child(manta)
	var def := FaunaData.species("manta_ray")
	var model := BlockyModel.new()
	model.setup(def, FaunaData.palette(def, 3))
	model.scale = Vector3.ONE * 3.2
	manta.add_child(model)
	var handle := MantaHandle.new()
	handle.ride = manta_ride
	manta.add_child(handle)
	manta_ride.carrier = manta
	manta_ride.carrier_offset = Vector3(0.0, -0.3, 0.0)
	manta_ride.rider_offset = Vector3(0.0, 0.15, 0.0)
	manta_ride.can_release = true
	manta_ride.pose = "sit"
	manta_ride.prompt_text = "E  松手（骑着蝠鲼时不耗氧气）"
	manta_ride.setup(pts, float(cfg["speed"]), rest + Vector3(2.5, 1.0, 0.0))
	manta_ride.finished.connect(_on_manta_done)


func _on_manta_done(_rider: Node, completed: bool) -> void:
	if completed:
		EventBus.toast_requested.emit(tr("蝠鲼驮着你绕古城游了一圈，又回到了礁石上"))
		if not WorldState.flags.get("manta_ride", false):
			WorldState.flags["manta_ride"] = true
			SaveManager.request_save()


# ---------------------------------------------------------------- 每帧：氧气、洋流入口、光照

func in_sea() -> bool:
	return player != null and player.current_water == sea and not player.is_riding()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if player == null:
		return
	_current_cool = maxf(0.0, _current_cool - delta)
	var p := player.global_position
	# 洋流入口：走进漩涡泉就被带走
	var inlet := MiniWorld.v2(data["current"]["inlet"])
	if _current_cool <= 0.0 and not player.is_riding() and Vector2(p.x, p.z).distance_to(inlet) < 1.3 and p.y < height_at(inlet.x, inlet.y) + 1.2:
		if current_ride.begin(player):
			EventBus.toast_requested.emit(tr("水柱把你托了起来！"))
	_update_oxygen(delta)


func oxygen_seconds() -> float:
	return (OXYGEN_SECONDS_HARD if GameRules.flag("swim_stamina") else OXYGEN_SECONDS) / maxf(Play.mult("oxygen_drain"), 0.05)


func nearest_spring(p: Vector3) -> Vector3:
	var best := springs[0]
	for s in springs:
		if Vector2(s.x - p.x, s.z - p.z).length() < Vector2(best.x - p.x, best.z - p.z).length():
			best = s
	return best


func _update_oxygen(delta: float) -> void:
	if not GameRules.flag("oxygen"):
		oxygen = 1.0
		_o2_root.visible = false
		return
	var p := player.global_position
	var spring := nearest_spring(p)
	var at_spring := (p + Vector3(0.0, 0.9, 0.0)).distance_to(spring + Vector3(0.0, 1.0, 0.0)) < float(data.get("spring_radius", 3.6))
	if at_spring:
		if oxygen < 0.98 and _spring_note <= 0.0:
			EventBus.toast_requested.emit(tr("气泡泉：氧气补满了"))
			_spring_note = 6.0
		oxygen = minf(1.0, oxygen + delta * 1.5)
	elif in_sea():
		oxygen = maxf(0.0, oxygen - delta / oxygen_seconds())
	else:
		oxygen = minf(1.0, oxygen + delta * 0.5)
	_spring_note = maxf(0.0, _spring_note - delta)
	_o2_root.visible = in_sea() or oxygen < 0.999
	_o2_bar.value = oxygen * 100.0
	_o2_label.modulate = Color(1.0, 0.45, 0.4) if oxygen < 0.25 else Color.WHITE
	if oxygen <= 0.0 and not _o2_out:
		_oxygen_out()


## 氧气用完：黑幕，托回最近的气泡泉，氧气补满。
func _oxygen_out() -> void:
	_o2_out = true
	oxygen_outs += 1
	var spring := nearest_spring(player.global_position)
	await Fade.fade_out(0.3, tr("氧气用完了……气泡把你托回了泉边"))
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		player.teleport_to(spring + Vector3(0.0, 1.2, 2.2))
	oxygen = 1.0
	Fade.fade_in(0.7)
	_o2_out = false


func _process(delta: float) -> void:
	super._process(delta)
	if _whale != null:
		_whale.rotation.y -= delta * 0.02
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.5
		_update_lighting(false)
	# 穹顶里雾淡、穹顶外的海里雾浓
	var cam := get_viewport().get_camera_3d()
	if cam != null and _env != null:
		var inside := inside_dome(cam.global_position)
		_env.fog_density = lerpf(_env.fog_density, 0.004 if inside else 0.016, 1.0 - exp(-3.0 * delta))


## 白天的程度：6 点后亮起来，18 点半后暗下去（湖畔的时刻）。
func daylight() -> float:
	var hrs := WorldState.time_minutes / 60.0
	return smoothstep(5.5, 7.5, hrs) * (1.0 - smoothstep(18.0, 20.0, hrs))


func _update_lighting(_force: bool) -> void:
	if _env == null:
		return
	var d := daylight()
	_env.ambient_light_energy = lerpf(0.22, 1.0, d)
	_sky.sky_top_color = Color(0.02, 0.06, 0.12).lerp(Color(0.05, 0.24, 0.34), d)
	_sky.sky_horizon_color = Color(0.03, 0.12, 0.18).lerp(Color(0.18, 0.55, 0.6), d)
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_sky.ground_bottom_color = Color(0.01, 0.04, 0.07).lerp(Color(0.04, 0.17, 0.24), d)
	_env.fog_light_color = Color(0.03, 0.12, 0.18).lerp(Color(0.16, 0.54, 0.6), d)
	_sun.light_energy = lerpf(0.06, 0.9, d)
	_ori_mat.emission_energy_multiplier = lerpf(4.5, 1.6, d)
	_floor_mat.set_shader_parameter("caustic_strength", lerpf(0.02, 0.35, d))


# ---------------------------------------------------------------- 界面：氧气条

func _build_ui() -> void:
	super._build_ui()
	var layer := CanvasLayer.new()
	layer.name = "OxygenHUD"
	layer.layer = 8
	add_child(layer)
	_o2_root = Control.new()
	_o2_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_o2_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_o2_root.theme = GameSettings.ui_theme()
	layer.add_child(_o2_root)
	_o2_label = Label.new()
	_o2_label.text = tr("氧气")
	_o2_label.anchor_left = 0.5
	_o2_label.anchor_right = 0.5
	_o2_label.anchor_top = 0.84
	_o2_label.anchor_bottom = 0.84
	_o2_label.offset_left = -190.0
	_o2_label.offset_right = -140.0
	_o2_label.offset_top = -4.0
	_o2_label.add_theme_font_size_override("font_size", 18)
	_o2_label.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	_o2_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_o2_label.add_theme_constant_override("outline_size", 5)
	_o2_root.add_child(_o2_label)
	_o2_bar = ProgressBar.new()
	_o2_bar.show_percentage = false
	_o2_bar.anchor_left = 0.5
	_o2_bar.anchor_right = 0.5
	_o2_bar.anchor_top = 0.84
	_o2_bar.anchor_bottom = 0.84
	_o2_bar.offset_left = -130.0
	_o2_bar.offset_right = 170.0
	_o2_bar.offset_bottom = 14.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.88, 1.0)
	fill.set_corner_radius_all(7)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.1, 0.16, 0.6)
	bg.set_corner_radius_all(7)
	_o2_bar.add_theme_stylebox_override("fill", fill)
	_o2_bar.add_theme_stylebox_override("background", bg)
	_o2_root.add_child(_o2_bar)
	_o2_root.visible = false


# ---------------------------------------------------------------- 钓鱼、地图

## 钓鱼：三圈水环。
func water_at(x: float, z: float) -> Dictionary:
	var id := ring_at(x, z)
	if id.begins_with("water") and absf(x) > causeway_hw + 0.5 and absf(z) > causeway_hw + 0.5:
		return {"id": id, "y": canal_surface, "fish": "atlantis"}
	return {}


func map_color(x: float, z: float, h: float) -> Color:
	var r := Vector2(x, z).length()
	if r < float(rings[-1]["r"]):
		if h < canal_floor + 0.05:
			return Color(0.25, 0.6, 0.72)
		return Color(0.9, 0.88, 0.8) if absf(x) > causeway_hw and absf(z) > causeway_hw else Color(0.8, 0.76, 0.66)
	return Color(0.12, 0.36, 0.46).lerp(Color(0.32, 0.5, 0.5), clampf((h + 4.0) / 8.0, 0.0, 1.0))


func draw_map(canvas: CanvasItem) -> void:
	canvas.draw_arc(Vector2.ZERO, dome_r, 0.0, TAU, 96, Color(0.75, 0.95, 1.0, 0.8), 1.5)
	var t: Array = data["temple"]["rect"]
	canvas.draw_rect(Rect2(float(t[0]), float(t[1]), float(t[2]), float(t[3])), Color(0.96, 0.94, 0.88))
	canvas.draw_circle(MiniWorld.v2(data["spire"]["pos"]), 1.6, Color(1.0, 0.55, 0.3) if puzzle_done else Color(0.7, 0.45, 0.32))
	var cpts: Array = data["current"]["points"]
	for i in cpts.size() - 1:
		canvas.draw_line(Vector2(float(cpts[i][0]), float(cpts[i][2])), Vector2(float(cpts[i + 1][0]), float(cpts[i + 1][2])), Color(0.4, 0.85, 1.0), 2.0)
	for s in springs:
		canvas.draw_circle(Vector2(s.x, s.z), 2.4, Color(0.6, 0.95, 1.0))
	for st in statues:
		canvas.draw_circle(Vector2(st.global_position.x, st.global_position.z), 1.6, Color(1.0, 0.82, 0.45) if st.lit else Color(0.75, 0.72, 0.66))
	canvas.draw_circle(MiniWorld.v2(data["manta"]["rock"]), 3.0, Color(0.42, 0.5, 0.52))


## 往 SurfaceTool 里加一个盒子（12 个三角形，顺时针为正面）。
static func _append_box(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var p := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		for idx: int in [0, 2, 1, 0, 3, 2]:
			st.set_uv(Vector2(float(idx % 2), float(idx / 2)))
			st.add_vertex(xf * (p[idx] as Vector3))
