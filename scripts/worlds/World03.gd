class_name World03
extends MiniWorld
## 世界三「琥珀沙丘」：夕阳下的沙海（布局在 data/worlds/dunes.json）。
##   · 风吹出来的沙丘（斜向的沙脊 + 细沙纹），四周的沙山围成边界；
##   · 月牙绿洲：一汪能游泳的水潭，岸边一圈草地和方块棕榈；
##   · 石柱废墟（立着的、断了的石柱，半埋的石墙和一颗方块石像头）、风蚀石拱、驼队营地（帐篷、篝火、木箱）、落日沙山；
##   · 阶梯神殿：四层石台，南侧一条坡道（看起来是台阶）通到顶上的祭坛；
##   · 能做的事：找 6 块古代碎片嵌回祭坛（嵌满后神殿升起光柱）、6 个探索点、绿洲游泳、滚来滚去的风滚草。

const NATURE := "res://assets/imported/kenney/nature/"
const SAND := Color(0.93, 0.76, 0.52)
const PALM_COLORS := {"trunk": Color(0.55, 0.4, 0.26), "trunk2": Color(0.62, 0.47, 0.3), "leaf": Color(0.36, 0.6, 0.26), "leaf2": Color(0.45, 0.68, 0.3), "nut": Color(0.42, 0.3, 0.16)}

var altar: RelicAltar = null
var beam: MeshInstance3D = null
var stone_head: Node3D = null                  ## 石柱废墟里望着落日的石像头（过场锚点）
var ramp: PackedVector3Array = []            ## 神殿坡道底端和顶端（自动检查走上去用）
var tumbleweeds: Array[Node3D] = []

var _pads: Array[Dictionary] = []
var _hills: Array = []
var _oasis: Dictionary = {}
var _bound: Dictionary = {}
var _wind := Vector2(0.86, 0.5)


func _init() -> void:
	world_id = "world_03"


func _enter_tree() -> void:
	super._enter_tree()
	for p: Dictionary in data.get("pads", []):
		_pads.append({"c": MiniWorld.v2(p["center"]), "r": float(p["radius"]), "b": float(p["blend"]), "h": float(p["height"])})
	_hills = data.get("hills", [])
	_oasis = data.get("oasis", {})
	_bound = data.get("boundary", {})


# ---------------------------------------------------------------- 高度

## 沙丘：斜向的沙脊（迎风坡缓、背风坡陡）+ 第二层起伏 + 细沙纹；压平的场地按距离平滑过渡；绿洲中间是碗形水潭；四周沙山。
func height_at(x: float, z: float) -> float:
	var a := 0.52
	var u := x * cos(a) + z * sin(a)
	var v := -x * sin(a) + z * cos(a)
	var ridge := 0.5 + 0.5 * sin(u * 0.055 + 0.9 * sin(v * 0.031))
	var h := 3.0 + 2.8 * pow(ridge, 1.7) + 1.1 * sin(v * 0.043 + 1.3) * sin(u * 0.021 + 0.4) + 0.22 * sin(x * 0.19) * sin(z * 0.15)
	for hl: Array in _hills:
		var d := Vector2(x - float(hl[0]), z - float(hl[1])).length() / float(hl[2])
		h += float(hl[3]) * exp(-d * d * 1.6)
	for p in _pads:
		var dist := Vector2(x, z).distance_to(p["c"])
		var t := 1.0 - smoothstep(float(p["r"]), float(p["r"]) + float(p["b"]), dist)
		h = lerpf(h, float(p["h"]), t)
	if not _oasis.is_empty():
		var od := Vector2(x, z).distance_to(MiniWorld.v2(_oasis["center"]))
		var rr := float(_oasis["radius"])
		h = lerpf(h, float(_oasis["floor"]), smoothstep(rr + 2.5, rr * 0.3, od))
	if not _bound.is_empty():
		var e := maxf(absf(x), absf(z))
		h += float(_bound["height"]) * smoothstep(float(_bound["start"]), float(_bound["end"]), e)
	return h


func _in_oasis_green(x: float, z: float) -> float:
	if _oasis.is_empty():
		return 0.0
	var od := Vector2(x, z).distance_to(MiniWorld.v2(_oasis["center"]))
	var rr := float(_oasis["radius"])
	return 1.0 - smoothstep(rr + 4.0, rr + 9.0, od)


# ---------------------------------------------------------------- 建造

func build_world() -> void:
	var sand := MiniWorld.terrain_material("damp_beach_sand")
	build_grid_terrain(map_rect(), 1.5, _sand_color, sand, "Dunes")
	_build_oasis()
	_build_temple()
	_build_ruins(MiniWorld.v2([-48.0, -8.0]))
	_build_arch(MiniWorld.v2([-80.0, 40.0]))
	_build_camp(MiniWorld.v2([58.0, -30.0]))
	_build_dune_flag(MiniWorld.v2([70.0, 52.0]))
	_build_cacti()
	_build_tumbleweeds()


func _sand_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var col := SAND.lerp(Color(0.86, 0.62, 0.4), smoothstep(0.75, 0.45, n.y))
	col = col.lerp(Color(0.98, 0.84, 0.62), clampf((h - 5.0) / 6.0, 0.0, 1.0) * 0.5)
	var g := _in_oasis_green(x, z)
	if g > 0.0 and h > -0.3:
		col = col.lerp(Color(0.45, 0.62, 0.3), g)
	if h < 0.05:
		col = col.lerp(Color(0.72, 0.62, 0.45), 0.6)
	return col


func _build_oasis() -> void:
	var c := MiniWorld.v2(_oasis["center"])
	var rr := float(_oasis["radius"])
	var water := MeshInstance3D.new()
	water.name = "OasisWater"
	var cm := CylinderMesh.new()
	cm.top_radius = rr + 0.5
	cm.bottom_radius = rr + 0.5
	cm.height = 0.02
	cm.radial_segments = 48
	water.mesh = cm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.62, 0.66, 0.85)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.06
	wm.metallic_specular = 0.8
	water.material_override = wm
	water.position = Vector3(c.x, -0.02, c.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	add_child(WaterVolume.create_cylinder(&"oasis", Vector3(c.x, -1.3, c.y), rr - 0.5, 2.6))
	# 岸边一圈棕榈（避开南边看水的那一段和告示）
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	for i in 11:
		var ang := float(i) / 11.0 * TAU + rng.randf_range(-0.15, 0.15)
		if absf(wrapf(ang - PI, -PI, PI)) < 0.35:
			continue
		var d := rr + rng.randf_range(3.0, 6.5)
		var p := c + Vector2(cos(ang), sin(ang)) * d
		_palm(Vector3(p.x, height_at(p.x, p.y) - 0.1, p.y), rng)


## 方块棕榈：一节节歪着长的树干，顶上八片下垂的叶子和两三颗椰子。
func _palm(at: Vector3, rng: RandomNumberGenerator) -> void:
	var pieces := []
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	var x := 0.0
	var z := 0.0
	var segs := rng.randi_range(9, 12)
	for k in segs:
		var y := k * 6
		pieces.append([x - 3, y, z - 3, x + 3, y + 6, z + 3, "trunk" if k % 2 == 0 else "trunk2"])
		x += lean.x * (0.4 + k * 0.12)
		z += lean.y * (0.4 + k * 0.12)
	var top := Vector3(x, segs * 6, z)
	for f in 8:
		var a := float(f) / 8.0 * TAU
		var d := Vector2(cos(a), sin(a))
		for s in 4:
			var cx := top.x + d.x * (4 + s * 5)
			var cz := top.z + d.y * (4 + s * 5)
			var cy := top.y - s * s * 1.2
			pieces.append([cx - 3, cy - 1, cz - 3, cx + 3, cy + 1, cz + 3, "leaf" if (f + s) % 2 == 0 else "leaf2"])
	for k in 3:
		pieces.append([top.x - 2 + k * 2, top.y - 5, top.z - 1, top.x + k * 2, top.y - 2, top.z + 2, "nut"])
	var boxes := []
	for p: Array in pieces:
		boxes.append({"box": p.slice(0, 6), "color": p[6]})
	var mi := MeshInstance3D.new()
	mi.name = "Palm"
	mi.mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return PALM_COLORS.get(k, Color.WHITE), 0.1)
	mi.position = at
	mi.rotation.y = rng.randf() * TAU
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 3.0
	cs.shape = shape
	cs.position = at + Vector3(0.0, 1.5, 0.0)
	body.add_child(cs)
	add_child(body)


## 阶梯神殿：四层石台 + 南侧坡道（碰撞是一块斜板，外观是一级级台阶）+ 顶上的祭坛 + 嵌满碎片后的光柱。
func _build_temple() -> void:
	var t: Dictionary = data["temple"]
	var c := MiniWorld.v2(t["center"])
	var base := float(t["base"])
	var th := float(t["tier_height"])
	var tiers: Array = t["tiers"]
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.98, 0.78, 0.56), "world")
	var dark := ArtMaterials.pbr("rustic_stone_wall", Color(0.78, 0.6, 0.44), "world")
	var g := Node3D.new()
	g.name = "Temple"
	add_child(g)
	for i in tiers.size():
		var s := float(tiers[i])
		solid_box(g, Vector3(s, th + 2.0, s), Transform3D(Basis(), Vector3(c.x, base + th * (i + 1) - (th + 2.0) * 0.5, c.y)), stone if i % 2 == 0 else dark)
	var top_y := base + th * tiers.size()
	var top_half := float(tiers[-1]) * 0.5
	var bottom := Vector3(c.x, base, c.y + float(tiers[0]) * 0.5 + 9.0)
	var upper := Vector3(c.x, top_y + 0.03, c.y + top_half)   # 坡顶正好落在顶层边上（往里收会在边上留一道坎，人上不去）
	ramp = PackedVector3Array([bottom, upper])
	var run := Vector2(bottom.z - upper.z, bottom.y - upper.y)
	var slope := atan2(top_y - base, bottom.z - upper.z)
	var length := Vector2(bottom.z - upper.z, top_y - base).length()
	var mid := (bottom + upper) * 0.5
	var ramp_basis := Basis(Vector3.RIGHT, slope)
	solid_box(g, Vector3(3.2, 0.3, length + 0.4), Transform3D(ramp_basis, mid - ramp_basis.y * 0.15), stone, true).visible = false
	var steps := int(ceil((top_y - base) / 0.32))
	for k in steps:
		var f0 := float(k) / steps
		var f1 := float(k + 1) / steps
		var y1 := lerpf(base, top_y, f1)
		var z0 := lerpf(bottom.z, upper.z, f0)
		var z1 := lerpf(bottom.z, upper.z, f1)
		var h := y1 - base + 0.05
		solid_box(g, Vector3(3.2, h, absf(z0 - z1) + 0.02), Transform3D(Basis(), Vector3(c.x, base + h * 0.5 - 0.04, (z0 + z1) * 0.5)), stone, false)
	for sx: float in [-1.0, 1.0]:
		solid_box(g, Vector3(0.4, 0.5, length), Transform3D(ramp_basis, mid + Vector3(sx * 1.8, 0.25, 0.0)), dark)
	# 四角的石灯台
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p: Vector2 = c + (corner as Vector2) * (float(tiers[0]) * 0.5 - 1.0)
		solid_box(g, Vector3(0.8, 1.6, 0.8), Transform3D(Basis(), Vector3(p.x, base + th + 0.8, p.y)), dark)
	altar = RelicAltar.create(&"du_altar", data.get("items", []).size())
	altar.position = Vector3(c.x, top_y, c.y - 0.6)
	add_child(altar)
	altar.completed.connect(_on_altar_complete)
	beam = MeshInstance3D.new()
	beam.name = "LightBeam"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 0.9
	cm.height = 120.0
	cm.radial_segments = 20
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.75, 0.4, 0.35)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(c.x, top_y + 60.0, c.y - 0.6)
	beam.visible = false
	add_child(beam)


func _on_altar_complete() -> void:
	beam.visible = true
	if not WorldState.flags.get("dunes_altar", false):
		WorldState.flags["dunes_altar"] = true
		EventBus.toast_requested.emit(tr("碎片全部嵌回祭坛——神殿升起了一道光！"))
		SaveManager.request_save()
		play_story("dunes_light")


## 石柱废墟：一圈石柱（有的断了半截）、两段半埋的石墙、一颗方块石像头。
func _build_ruins(c: Vector2) -> void:
	var g := Node3D.new()
	g.name = "Ruins"
	add_child(g)
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.98, 0.82, 0.62), "world")
	var y := height_at(c.x, c.y)
	for i in 10:
		var a := float(i) / 10.0 * TAU
		var p := c + Vector2(cos(a), sin(a)) * 10.0
		var h := 5.5 if i % 3 != 1 else 2.2
		var col := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.65
		cm.height = h
		cm.radial_segments = 12
		col.mesh = cm
		col.material_override = stone
		col.position = Vector3(p.x, y + h * 0.5 - 0.1, p.y)
		g.add_child(col)
		solid_box(g, Vector3(1.6, 0.4, 1.6), Transform3D(Basis(), Vector3(p.x, y + 0.1, p.y)), stone)
		if h > 3.0:
			solid_box(g, Vector3(1.5, 0.4, 1.5), Transform3D(Basis(), Vector3(p.x, y + h, p.y)), stone, false)
		var body := StaticBody3D.new()
		body.collision_layer = PhysicsLayers.WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.62
		shape.height = h
		cs.shape = shape
		cs.position = col.position
		body.add_child(cs)
		g.add_child(body)
	# 两根石柱之间搭着的一段横梁
	var a0 := c + Vector2(cos(0.0), sin(0.0)) * 10.0
	var a1 := c + Vector2(cos(TAU / 10.0), sin(TAU / 10.0)) * 10.0
	var mid := (a0 + a1) * 0.5
	solid_box(g, Vector3(a0.distance_to(a1) + 1.2, 0.6, 1.0), Transform3D(Basis(Vector3.UP, -atan2(a1.y - a0.y, a1.x - a0.x)), Vector3(mid.x, y + 5.9, mid.y)), stone, false)
	solid_box(g, Vector3(6.0, 1.6, 0.8), Transform3D(Basis(Vector3.UP, 0.3), Vector3(c.x - 4.0, y + 0.5, c.y + 4.0)), stone)
	solid_box(g, Vector3(4.0, 1.1, 0.8), Transform3D(Basis(Vector3.UP, 1.4), Vector3(c.x + 5.0, y + 0.3, c.y - 3.0)), stone)
	# 方块石像头（半埋在沙里，朝着落日）
	var face := [
		[-10, 0, -10, 10, 22, 10, "s"], [-11, 14, -11, 11, 20, 11, "s2"], [-6, 10, 10, -2, 13, 11, "eye"], [2, 10, 10, 6, 13, 11, "eye"],
		[-1, 5, 10, 1, 10, 13, "s2"], [-5, 2, 10, 5, 3, 11, "eye"],
	]
	var boxes := []
	for p: Array in face:
		boxes.append({"box": p.slice(0, 6), "color": p[6]})
	var colors := {"s": Color(0.9, 0.74, 0.54), "s2": Color(0.82, 0.66, 0.48), "eye": Color(0.36, 0.26, 0.18)}
	var head := MeshInstance3D.new()
	head.name = "StoneHead"
	head.mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return colors.get(k, Color.WHITE), 0.12)
	head.position = Vector3(c.x + 2.0, y - 0.6, c.y + 1.0)
	head.rotation.y = deg_to_rad(-80.0)
	add_child(head)
	stone_head = head
	var hb := StaticBody3D.new()
	hb.collision_layer = PhysicsLayers.WORLD
	hb.collision_mask = 0
	var hs := CollisionShape3D.new()
	var shape2 := BoxShape3D.new()
	shape2.size = Vector3(2.4, 2.6, 2.4)
	hs.shape = shape2
	hs.position = head.position + Vector3(0.0, 1.3, 0.0)
	hb.add_child(hs)
	add_child(hb)


## 风蚀石拱：两根岩柱上横着一块大岩石，人能从下面走过。
func _build_arch(c: Vector2) -> void:
	var g := Node3D.new()
	g.name = "WindArch"
	add_child(g)
	var rock := ArtMaterials.pbr("rock_face_03", Color(0.95, 0.66, 0.46), "world")
	var y := height_at(c.x, c.y)
	for sx: float in [-1.0, 1.0]:
		solid_box(g, Vector3(2.6, 7.5, 3.0), Transform3D(Basis(Vector3.UP, 0.2 * sx), Vector3(c.x + sx * 4.2, y + 3.6, c.y)), rock)
		solid_box(g, Vector3(3.4, 2.0, 3.6), Transform3D(Basis(Vector3.UP, -0.3 * sx), Vector3(c.x + sx * 4.4, y + 0.8, c.y + 0.3)), rock)
	solid_box(g, Vector3(12.0, 2.2, 3.4), Transform3D(Basis(Vector3.FORWARD, 0.05), Vector3(c.x, y + 8.2, c.y)), rock)
	solid_box(g, Vector3(6.0, 1.4, 2.8), Transform3D(Basis(Vector3.FORWARD, -0.1), Vector3(c.x - 1.0, y + 9.6, c.y + 0.2)), rock)


## 驼队营地：两顶帐篷、篝火（Kenney，CC0）、几只木箱。
func _build_camp(c: Vector2) -> void:
	var y := height_at(c.x, c.y)
	add_child(ArtMaterials.kenney_prop(NATURE + "tent_smallOpen.glb", Vector3(c.x - 3.0, y, c.y - 2.5), 30.0, 3.6))
	add_child(ArtMaterials.kenney_prop(NATURE + "tent_smallOpen.glb", Vector3(c.x + 3.5, y, c.y - 1.5), -40.0, 3.2))
	add_child(ArtMaterials.kenney_prop(NATURE + "campfire_stones.glb", Vector3(c.x, y, c.y + 1.5), 0.0, 2.6))
	add_child(ArtMaterials.kenney_prop(NATURE + "campfire_logs.glb", Vector3(c.x, y, c.y + 1.5), 20.0, 2.6))
	var crackle := SoundEmitter.create("campfire")
	crackle.position = Vector3(c.x, y + 0.5, c.y + 1.5)
	add_child(crackle)
	var fire := CPUParticles3D.new()
	fire.name = "CampFire"
	fire.amount = 30
	fire.lifetime = 0.8
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.25
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.gravity = Vector3(0.0, 1.5, 0.0)
	fire.initial_velocity_min = 0.4
	fire.initial_velocity_max = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.55, 0.2, 0.9)
	q.material = fm
	fire.mesh = q
	fire.position = Vector3(c.x, y + 0.35, c.y + 1.5)
	add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.4
	light.omni_range = 8.0
	light.position = Vector3(c.x, y + 1.0, c.y + 1.5)
	add_child(light)
	# 篝火上架着一口铁锅：用钓到的鱼做饭（CookPot）
	for k in 3:
		var a := float(k) / 3.0 * TAU
		solid_box(self, Vector3(0.06, 1.5, 0.06), Transform3D(Basis(Vector3(-sin(a), 0.0, cos(a)), 0.3), Vector3(c.x + cos(a) * 0.45, y + 0.7, c.y + 1.5 + sin(a) * 0.45)), crate_wood(), false)
	add_child(CookPot.create(&"dune_pot", Vector3(c.x, y + 0.62, c.y + 1.5)))
	var crate := ArtMaterials.pbr("weathered_planks", Color(0.86, 0.66, 0.46), "world")
	for p: Vector3 in [Vector3(-5.0, 0.4, 1.5), Vector3(-5.2, 1.2, 1.4), Vector3(5.5, 0.4, 2.5)]:
		solid_box(self, Vector3(0.8, 0.8, 0.8), Transform3D(Basis(Vector3.UP, p.x * 0.1), Vector3(c.x + p.x, y + p.y, c.y + p.z)), crate)


## 落日沙山顶上一面小旗。
func _build_dune_flag(c: Vector2) -> void:
	var y := height_at(c.x, c.y)
	var pole := ArtMaterials.pbr("stained_pine", Color(0.6, 0.42, 0.3), "world")
	solid_box(self, Vector3(0.12, 3.2, 0.12), Transform3D(Basis(), Vector3(c.x + 1.5, y + 1.5, c.y)), pole)
	var flag := ArtMaterials.flat(Color(0.82, 0.24, 0.2), 0.8, false, 0.0, true)
	solid_box(self, Vector3(1.2, 0.7, 0.03), Transform3D(Basis(), Vector3(c.x + 2.15, y + 2.7, c.y)), flag, false)


## 沙丘上的仙人掌（Kenney，CC0），避开场地、绿洲和碎片。
func _build_cacti() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var g := Node3D.new()
	g.name = "Cacti"
	add_child(g)
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 600:
		tries += 1
		var p := Vector2(rng.randf_range(-95.0, 95.0), rng.randf_range(-95.0, 95.0))
		var ok := true
		for pad in _pads:
			if p.distance_to(pad["c"]) < float(pad["r"]) + 3.0:
				ok = false
		for it: Dictionary in data.get("items", []):
			if p.distance_to(MiniWorld.v2(it["pos"])) < 4.0:
				ok = false
		if _in_oasis_green(p.x, p.y) > 0.0 or not ok:
			continue
		var asset := "cactus_tall" if rng.randf() < 0.4 else "cactus_short"
		g.add_child(ArtMaterials.kenney_prop(NATURE + asset + ".glb", Vector3(p.x, height_at(p.x, p.y) - 0.1, p.y), rng.randf() * 360.0, rng.randf_range(2.6, 3.8)))
		placed += 1


## 风滚草：几团方块枯草顺着风滚过沙丘，滚出场地就从另一边回来。
func _build_tumbleweeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	var col := {"a": Color(0.68, 0.55, 0.36), "b": Color(0.56, 0.44, 0.28)}
	for i in 7:
		var boxes := []
		for k in 14:
			var o := Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			boxes.append({"box": [o.x - 2, o.y - 2, o.z - 2, o.x + 2, o.y + 2, o.z + 2], "color": "a" if k % 2 == 0 else "b"})
		var mi := MeshInstance3D.new()
		mi.name = "Tumbleweed%d" % i
		mi.mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return col.get(k, Color.WHITE), 0.08)
		mi.position = Vector3(rng.randf_range(-90.0, 90.0), 0.0, rng.randf_range(-90.0, 90.0))
		mi.set_meta("speed", rng.randf_range(1.2, 2.6))
		add_child(mi)
		tumbleweeds.append(mi)


func _process(delta: float) -> void:
	super._process(delta)
	var t := Time.get_ticks_msec() * 0.001
	for w in tumbleweeds:
		var sp := float(w.get_meta("speed"))
		w.position.x += _wind.x * sp * delta
		w.position.z += _wind.y * sp * delta
		if w.position.x > 95.0 or w.position.z > 95.0:
			w.position.x -= 180.0 * (1.0 if w.position.x > 95.0 else 0.0)
			w.position.z -= 180.0 * (1.0 if w.position.z > 95.0 else 0.0)
		w.position.y = height_at(w.position.x, w.position.z) + 0.4 + absf(sin(t * sp * 1.7 + w.position.x)) * 0.5
		w.rotation.z -= delta * sp * 2.0
		w.rotation.x += delta * sp * 1.1
	if beam != null and beam.visible:
		beam.rotation.y += delta * 0.3


# ---------------------------------------------------------------- 地图

func map_color(x: float, z: float, h: float) -> Color:
	if h < 0.0:
		return Color(0.25, 0.6, 0.66)
	var g := _in_oasis_green(x, z)
	return SAND.lerp(Color(0.98, 0.86, 0.66), clampf((h - 4.0) / 8.0, 0.0, 1.0)).lerp(Color(0.45, 0.62, 0.3), g)


func draw_map(canvas: CanvasItem) -> void:
	var t: Dictionary = data["temple"]
	var c := MiniWorld.v2(t["center"])
	var tiers: Array = t["tiers"]
	for i in tiers.size():
		var s := float(tiers[i])
		canvas.draw_rect(Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), Color(0.86, 0.68, 0.48).darkened(0.08 * i))
	if not ramp.is_empty():
		canvas.draw_line(Vector2(ramp[0].x, ramp[0].z), Vector2(ramp[1].x, ramp[1].z), Color(0.98, 0.84, 0.62), 3.2)
	var r := MiniWorld.v2([-48.0, -8.0])
	canvas.draw_arc(r, 10.0, 0.0, TAU, 32, Color(0.75, 0.6, 0.44), 1.6)
	canvas.draw_line(MiniWorld.v2([-84.2, 40.0]), MiniWorld.v2([-75.8, 40.0]), Color(0.7, 0.42, 0.3), 3.0)
	canvas.draw_circle(MiniWorld.v2([58.0, -30.0]), 2.5, Color(0.8, 0.45, 0.3))
	if altar != null and altar.is_complete():
		canvas.draw_circle(c, 3.0, Color(1.0, 0.78, 0.4))


## 钓鱼：月牙绿洲（水面 y = 0）。
func water_at(x: float, z: float) -> Dictionary:
	if _oasis.is_empty():
		return {}
	if Vector2(x, z).distance_to(MiniWorld.v2(_oasis["center"])) < float(_oasis["radius"]) - 0.5:
		return {"id": "oasis", "y": 0.0, "fish": "oasis"}
	return {}


static func crate_wood() -> Material:
	return ArtMaterials.pbr("stained_pine", Color(0.5, 0.36, 0.24), "world")


## 过场锚点：altar 祭坛，head 石像头（带朝向，+Z 是它的脸），sunset 石像头望着的落日方向（远处 80 m），其余见 MiniWorld。
func story_anchor(name: String) -> Variant:
	match name:
		"altar":
			return altar.global_position if altar != null else null
		"head":
			return stone_head.global_transform if stone_head != null else null
		"sunset":
			if stone_head == null or _sun == null:
				return null
			return stone_head.global_position + _sun.global_basis.z * 80.0
	return super(name)
