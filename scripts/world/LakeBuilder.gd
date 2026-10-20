@tool
class_name LakeBuilder
extends Node3D
## 湖面占位：一块水平水面（water.gdshader），湖盆形状来自地形下挖。
## MVP 不可深水游泳：沿“水深 = wade_limit_depth”的等深线生成一圈水下挡墙（WATER_LIMIT 层），
## 玩家可以走进浅水，但走不到深处。码头经过的位置把挡墙压低到码头板下方，码头照常通行。

const GENERATED := "Generated"
const WATER_SHADER := preload("res://shaders/water.gdshader")
const RING_SEGMENTS := 256
const WALL_BOTTOM := -6.0
const WALL_TOP := 1.6

var wall_points := PackedVector3Array()


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)
	root.add_child(_make_water())
	if not Engine.is_editor_hint():
		root.add_child(_make_wade_limit())


func _make_water() -> MeshInstance3D:
	var lake := WorldLayout.section("lake")
	var c := WorldLayout.v2(lake["center"])
	var r := WorldLayout.v2(lake["radii"])
	var plane := PlaneMesh.new()
	plane.size = Vector2(r.x * 2.0 + 20.0, r.y * 2.0 + 20.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("ripple_a", _ripple_texture(101, 0.02))
	mat.set_shader_parameter("ripple_b", _ripple_texture(202, 0.035))
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "WaterSurface"
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.x, WorldLayout.water_level(), c.y)
	return mi


func _ripple_texture(seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.generate_mipmaps = true
	tex.noise = noise
	return tex


func _make_wade_limit() -> StaticBody3D:
	var lake := WorldLayout.section("lake")
	var dock := WorldLayout.section("dock")
	var c := WorldLayout.v2(lake["center"])
	var r := WorldLayout.v2(lake["radii"])
	var limit := WorldLayout.water_level() - float(lake["wade_limit_depth"])
	wall_points = PackedVector3Array()
	for i in RING_SEGMENTS:
		var a := TAU * float(i) / RING_SEGMENTS
		var dir := Vector2(cos(a) * r.x, sin(a) * r.y)
		var t := 0.4
		var found := false
		while t < 1.4:
			var p := c + dir * t
			if WorldTerrain.height_at(p.x, p.y) >= limit:
				found = true
				break
			t += 0.004
		if found:
			var p := c + dir * t
			wall_points.append(Vector3(p.x, limit, p.y))

	var body := StaticBody3D.new()
	body.name = "WadeLimit"
	body.collision_layer = PhysicsLayers.WATER_LIMIT
	body.collision_mask = 0
	var d_from := WorldLayout.v2(dock["from"])
	var d_to := WorldLayout.v2(dock["to"])
	var d_half := float(dock["width"]) * 0.5 + 0.6
	var deck_bottom := float(dock["deck_height"]) - 0.25
	var n := wall_points.size()
	for i in n:
		var a3 := wall_points[i]
		var b3 := wall_points[(i + 1) % n]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var length := a.distance_to(b)
		if length < 0.01 or length > 12.0:
			continue
		var mid := (a + b) * 0.5
		var near_dock := mid.x > minf(d_from.x, d_to.x) and mid.x < maxf(d_from.x, d_to.x) \
			and absf(mid.y - d_from.y) < d_half + length * 0.5
		var top := deck_bottom if near_dock else WALL_TOP
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.4, top - WALL_BOTTOM, length + 0.3)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var forward := Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
		cs.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), Vector3(mid.x, (top + WALL_BOTTOM) * 0.5, mid.y))
		body.add_child(cs)
	return body
