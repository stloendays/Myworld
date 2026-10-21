class_name FaunaSpawner
extends Node3D
## 按 data/animals/species.json → spawns 摆放小动物（兔子、狐狸、松鼠、鸭子、鸟、蝴蝶），
## 并在草甸与湖边放萤火虫粒子（春夏无雨的夜晚才亮）。只在运行时生成。

var animals: Array[Animal] = []
var fireflies: Array[GPUParticles3D] = []
var _firefly_timer := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var spawns: Array = FaunaData.data().get("spawns", [])
	var serial := {}
	for s in spawns:
		var sp := str(s["species"])
		for i in int(s["count"]):
			serial[sp] = int(serial.get(sp, 0)) + 1
			var a := Animal.new()
			a.name = "%s_%02d" % [sp, serial[sp]]
			add_child(a)
			a.setup(StringName("%s_%02d" % [sp, serial[sp]]), sp, WorldLayout.v2(s["center"]), float(s["radius"]), hash([sp, serial[sp]]))
			animals.append(a)
	for f in FaunaData.data().get("fireflies", []):
		var p := _make_fireflies(WorldLayout.v2(f["center"]), float(f["radius"]), int(f["amount"]))
		add_child(p)
		fireflies.append(p)


func _process(delta: float) -> void:
	_firefly_timer -= delta
	if _firefly_timer > 0.0 or fireflies.is_empty():
		return
	_firefly_timer = 1.0
	var on := FaunaData.is_active(FaunaData.data().get("firefly_active", {}))
	for p in fireflies:
		if p.emitting != on:
			p.emitting = on


func count(species: String) -> int:
	var n := 0
	for a in animals:
		if a.species_id == species:
			n += 1
	return n


func _make_fireflies(center: Vector2, radius: float, amount: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius, 0.8, radius)
	pm.emission_shape_offset = Vector3(0.0, 1.2, 0.0)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2), Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 1.0, 0.45)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Fireflies"
	p.emitting = false
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-radius - 2.0, -1.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 5.0, radius * 2.0 + 4.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(center.x, WorldTerrain.height_at(center.x, center.y), center.y)
	return p
