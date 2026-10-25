class_name ReefTank
extends RefCounted
## 地下水族馆北侧的海洋大缸（PoolHouse 的一部分，用它的局部坐标和几何工具）。
##   - 24 × 4.9 m，缸底沙面在 y = -9.8（比大厅地面低 2.8 m），水一直满到顶板 y = -4.1；
##   - z = -3.1 处一整面落地玻璃（大厅这一侧），每 4 m 一根细竖框，玻璃下沿以下是混凝土缸壁；
##   - 缸壁底部在通道处开口，接下潜池的水下通道（CHANNEL），人可以游进来；
##   - 布景：后壁“深海背景”、礁石与拱门、海带林、珊瑚、沉没的独木舟、冒泡的出气口、从上面斜射下来的光束；
##   - 灯：缸顶一排青色灯 + 两盏沙底补光；
##   - tank_bounds[0] = 鱼可以游的范围（PoolHouse._populate_tanks 用它放 REEF_LIFE）。

const NATURE := "res://assets/imported/kenney/nature/"
const KELP_SHADER := preload("res://shaders/kelp.gdshader")
const BACKDROP_SHADER := preload("res://shaders/ocean_backdrop.gdshader")


static func build(h: PoolHouse, g: Node3D) -> void:
	var r := PoolHouse.REEF
	var sand_y := PoolHouse.REEF_SAND
	var top := PoolHouse.REEF_TOP
	var glass_z := r.end.y
	var root := Node3D.new()
	root.name = "ReefTank"
	g.add_child(root)

	# 缸底沙、顶板
	h._slab(root, r, sand_y - 0.3, sand_y, h._m.sand)
	h._slab(root, r, top, PoolHouse.CEIL_B, h._m.aq_ceiling)
	# 大厅地面以下的缸壁：北、东、西三面 + 玻璃下方的南壁（通道处开口）
	var below := PoolHouse.FLOOR_B - 0.3
	var wall_h := below - (sand_y - 0.3)
	var wy := (below + sand_y - 0.3) * 0.5
	h._box(root, Vector3(r.size.x + 0.6, wall_h, 0.3), Vector3(r.get_center().x, wy, r.position.y - 0.15), h._m.aq_wall)
	h._box(root, Vector3(0.3, wall_h, r.size.y), Vector3(r.position.x - 0.15, wy, r.get_center().y), h._m.aq_wall)
	h._box(root, Vector3(0.3, wall_h, r.size.y), Vector3(r.end.x + 0.15, wy, r.get_center().y), h._m.aq_wall)
	var ch := PoolHouse.CHANNEL
	var south_z := glass_z + 0.15
	var l_w := ch.position.x - r.position.x
	var r_w := r.end.x - ch.end.x
	h._box(root, Vector3(l_w, wall_h, 0.3), Vector3(r.position.x + l_w * 0.5, wy, south_z), h._m.aq_wall)
	h._box(root, Vector3(r_w, wall_h, 0.3), Vector3(ch.end.x + r_w * 0.5, wy, south_z), h._m.aq_wall)
	# 通道：底、两侧壁（顶就是大厅地板底面）
	h._slab(root, ch, sand_y - 0.3, sand_y, h._m.basin_tiles)
	for x: float in [ch.position.x - 0.15, ch.end.x + 0.15]:
		h._box(root, Vector3(0.3, PoolHouse.CHANNEL_TOP - sand_y, ch.size.y), Vector3(x, (PoolHouse.CHANNEL_TOP + sand_y) * 0.5, ch.get_center().y), h._m.basin_tiles)
	# 落地玻璃与竖框、顶框
	var gh := top - PoolHouse.FLOOR_B
	h._box(root, Vector3(r.size.x, gh, 0.06), Vector3(r.get_center().x, (PoolHouse.FLOOR_B + top) * 0.5, glass_z), h._m.clear)
	var n := int(r.size.x / 4.0)
	for i in n + 1:
		var x := r.position.x + r.size.x * float(i) / n
		h._box(root, Vector3(0.08, gh, 0.12), Vector3(x, (PoolHouse.FLOOR_B + top) * 0.5, glass_z), h._m.frame, false)
	h._box(root, Vector3(r.size.x, 0.14, 0.16), Vector3(r.get_center().x, top - 0.07, glass_z), h._m.frame, false)
	h._box(root, Vector3(r.size.x, 0.1, 0.16), Vector3(r.get_center().x, PoolHouse.FLOOR_B + 0.05, glass_z), h._m.frame, false)
	# 大厅顶上沿玻璃的一条灯带
	h._box(root, Vector3(r.size.x - 0.6, 0.05, 0.12), Vector3(r.get_center().x, PoolHouse.CEIL_B - 0.03, glass_z + 0.25), h._m.strip, false)
	# 水体（从大厅看是一缸蓝色的水）
	var water := BoxMesh.new()
	water.size = Vector3(r.size.x, top - sand_y, r.size.y)
	water.material = h._m.tank_water
	var wmi := MeshInstance3D.new()
	wmi.mesh = water
	wmi.position = Vector3(r.get_center().x, (sand_y + top) * 0.5, r.get_center().y)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wmi)
	_backdrop(h, root, r, sand_y, top)
	_decor(h, root, r, sand_y, top)
	_lights(h, root, r, sand_y, top)
	var inner := AABB(Vector3(r.position.x + 0.5, sand_y + 0.35, r.position.y + 0.4), Vector3(r.size.x - 1.0, top - sand_y - 0.7, r.size.y - 0.8))
	h.tank_bounds.append(AABB(h.to_global(inner.position), inner.size))


## 后壁与两端的“深海背景”板（贴在缸壁内侧）
static func _backdrop(h: PoolHouse, root: Node3D, r: Rect2, sand_y: float, top: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	mat.set_shader_parameter("y_bottom", h.position.y + sand_y)
	mat.set_shader_parameter("y_top", h.position.y + top)
	var hgt := top - sand_y
	for spec in [[Vector2(r.size.x, hgt), Vector3(r.get_center().x, (sand_y + top) * 0.5, r.position.y + 0.02), 0.0],
			[Vector2(r.size.y, hgt), Vector3(r.position.x + 0.02, (sand_y + top) * 0.5, r.get_center().y), 90.0],
			[Vector2(r.size.y, hgt), Vector3(r.end.x - 0.02, (sand_y + top) * 0.5, r.get_center().y), -90.0]]:
		var q := QuadMesh.new()
		q.size = spec[0]
		q.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = spec[1]
		mi.rotation.y = deg_to_rad(spec[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func _decor(h: PoolHouse, root: Node3D, r: Rect2, sand_y: float, top: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	var back := r.position.y + 0.9
	# 礁石：沿后壁一排大石头，左边一座拱门
	for i in 9:
		var x := lerpf(r.position.x + 1.5, r.end.x - 1.5, float(i) / 8.0) + rng.randf_range(-0.8, 0.8)
		if absf(x - -6.0) < 1.8:
			continue
		_rock(h, root, ["rock_largeA", "rock_largeB", "rock_largeC", "rock_largeD", "rock_largeE"][i % 5], Vector3(x, sand_y, back + rng.randf_range(0.0, 1.0)), rng.randf() * 360.0, rng.randf_range(2.6, 4.2), rng)
	_rock(h, root, "rock_tallA", Vector3(-7.4, sand_y, back + 0.8), 20.0, 3.4, rng)
	_rock(h, root, "rock_tallB", Vector3(-4.6, sand_y, back + 0.9), 200.0, 3.4, rng)
	var arch := ArtMaterials.kenney_prop(NATURE + "rock_largeB.glb", Vector3(-6.0, sand_y + 2.2, back + 0.8), 90.0, 3.0)
	arch.scale.x *= 1.6
	h._underwater_restyle(arch, "rock_largeB", rng)
	root.add_child(arch)
	# 珊瑚与水草（沙面上散布，留出通道入口和玻璃前的一条游动空间）
	for i in 46:
		var p := Vector3(rng.randf_range(r.position.x + 0.6, r.end.x - 0.6), sand_y, rng.randf_range(r.position.y + 0.5, r.end.y - 1.2))
		if absf(p.x - PoolHouse.CHANNEL.get_center().x) < 1.6:
			continue
		if absf(p.x - float(WorldLayout.section("atlantis_ring").get("local", [99.0])[0])) < 1.8:
			continue
		var asset: String = ["plant_bush", "plant_bushSmall", "plant_bushDetailed", "mushroom_redGroup", "mushroom_tanGroup", "grass_large"][rng.randi() % 6]
		var node := ArtMaterials.kenney_prop(NATURE + asset + ".glb", p, rng.randf() * 360.0, rng.randf_range(1.6, 3.2))
		h._underwater_restyle(node, asset, rng)
		root.add_child(node)
	# 海带林：东西两头各一片
	for i in 30:
		var cx := -9.5 if i < 15 else 9.0
		var p := Vector3(cx + rng.randf_range(-2.2, 2.2), sand_y, rng.randf_range(r.position.y + 0.5, r.position.y + 3.4))
		if absf(p.x - float(WorldLayout.section("atlantis_ring").get("local", [99.0])[0])) < 1.0:
			continue
		_kelp(root, p, rng.randf_range(2.6, 5.2), rng)
	# 沉没的独木舟：半埋在东侧沙里，船头翘起
	var wreck := ArtMaterials.kenney_prop(NATURE + "canoe.glb", Vector3(5.5, sand_y - 0.15, back + 1.6), 63.0, 3.9)
	wreck.rotate_object_local(Vector3.FORWARD, deg_to_rad(18.0))
	wreck.rotate_object_local(Vector3.RIGHT, deg_to_rad(-9.0))
	for mi: MeshInstance3D in wreck.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = ArtMaterials.flat(Color(0.30, 0.20, 0.16), 0.95)
	root.add_child(wreck)
	# 冒泡的出气口（三处），光束（五道）
	for x: float in [-3.5, 2.6, 8.2]:
		root.add_child(_bubbles(Vector3(x, sand_y + 0.1, r.position.y + rng.randf_range(1.2, 2.6)), top - sand_y))
	for i in 5:
		root.add_child(_shaft(Vector3(lerpf(r.position.x + 3.0, r.end.x - 3.0, float(i) / 4.0), (sand_y + top) * 0.5 + 0.4, r.get_center().y - 0.4), top - sand_y, i))


static func _rock(h: PoolHouse, root: Node3D, asset: String, pos: Vector3, yaw: float, s: float, rng: RandomNumberGenerator) -> void:
	var node := ArtMaterials.kenney_prop(NATURE + asset + ".glb", pos, yaw, s)
	h._underwater_restyle(node, asset, rng)
	root.add_child(node)


## 一株海带：两片交叉的细长条带（分段的竖直面），着色器让它随水摇。
static func _kelp(root: Node3D, base: Vector3, height: float, rng: RandomNumberGenerator) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = KELP_SHADER
	mat.set_shader_parameter("height", height)
	mat.set_shader_parameter("phase", rng.randf() * TAU)
	mat.set_shader_parameter("sway", rng.randf_range(0.25, 0.45))
	for k in 2:
		var q := PlaneMesh.new()
		q.orientation = PlaneMesh.FACE_Z
		q.size = Vector2(rng.randf_range(0.18, 0.32), height)
		q.subdivide_depth = 10
		q.center_offset = Vector3(0.0, height * 0.5, 0.0)
		q.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = base
		mi.rotation.y = deg_to_rad(90.0 * k + rng.randf() * 40.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func _bubbles(pos: Vector3, rise: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Bubbles"
	p.position = pos
	p.amount = 24
	p.lifetime = rise / 0.9
	p.preprocess = p.lifetime
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.7
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0.0, 0.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.5, 0.6)
	mat.roughness = 0.1
	var s := SphereMesh.new()
	s.radius = 0.04
	s.height = 0.08
	s.radial_segments = 8
	s.rings = 4
	s.material = mat
	p.mesh = s
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 一道从缸顶斜射下来的光：上亮下淡的半透明叠加面，慢慢明暗起伏。
static func _shaft(pos: Vector3, height: float, idx: int) -> MeshInstance3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var across := GradientTexture2D.new()
	across.gradient = g
	across.width = 64
	across.height = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = across
	mat.albedo_color = Color(0.35, 0.7, 0.85, 0.22 + 0.06 * (idx % 2))
	mat.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(1.4, height * 1.1)
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "LightShaft"
	mi.mesh = q
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(8.0), deg_to_rad(18.0 + 9.0 * idx), deg_to_rad(-12.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _lights(h: PoolHouse, root: Node3D, r: Rect2, sand_y: float, top: float) -> void:
	for i in 5:
		var x := lerpf(r.position.x + 2.4, r.end.x - 2.4, float(i) / 4.0)
		h._omni(root, Vector3(x, top - 0.35, r.get_center().y), Color(0.35, 0.78, 1.0), 2.2, 7.5)
	h._omni(root, Vector3(-6.0, sand_y + 1.0, r.get_center().y), Color(0.5, 0.75, 1.0), 0.9, 6.0)
	h._omni(root, Vector3(6.0, sand_y + 1.0, r.get_center().y), Color(0.5, 0.75, 1.0), 0.9, 6.0)
