class_name WindBeacon
extends Interactable
## 云海浮岛的风灯：石座上一只黄铜灯碗和一块水晶。看着它按 E 点亮（点亮后不再熄灭），水晶亮起、灯碗里冒出火苗。
## 状态 "lit" / "unlit" 按 uid 记进 WorldState（存档、换世界回来都还亮着）。四座都点亮时世界会让天鲸游过来（World02）。

signal lit_changed(beacon: WindBeacon)

var lit := false
var _crystal: MeshInstance3D
var _flame: CPUParticles3D
var _light: OmniLight3D
var _dim: Material
var _bright: Material


static func create(id: String) -> WindBeacon:
	var b := WindBeacon.new()
	b.name = "Beacon_" + id
	b.uid = StringName("cs_beacon_" + id)
	b.display_name = "风灯"
	b._build()
	return b


func _build() -> void:
	var stone := ArtMaterials.pbr("rustic_stone_wall", Color(0.86, 0.84, 0.9), "world")
	var brass := ArtMaterials.flat(Color(0.86, 0.66, 0.3), 0.35, false, 0.8)
	_dim = ArtMaterials.flat(Color(0.45, 0.55, 0.7), 0.15)
	_bright = ArtMaterials.glow(Color(0.55, 0.85, 1.0), 3.0)
	_box(Vector3(1.0, 0.3, 1.0), Vector3(0.0, 0.15, 0.0), stone)
	_box(Vector3(0.6, 0.9, 0.6), Vector3(0.0, 0.75, 0.0), stone)
	var bowl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.48
	cm.bottom_radius = 0.26
	cm.height = 0.26
	bowl.mesh = cm
	bowl.material_override = brass
	bowl.position = Vector3(0.0, 1.33, 0.0)
	add_child(bowl)
	_crystal = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.32, 0.6, 0.32)
	_crystal.mesh = pm
	_crystal.material_override = _dim
	_crystal.position = Vector3(0.0, 1.75, 0.0)
	_crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crystal)
	_flame = CPUParticles3D.new()
	_flame.emitting = false
	_flame.amount = 32
	_flame.lifetime = 0.9
	_flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flame.emission_sphere_radius = 0.2
	_flame.direction = Vector3.UP
	_flame.spread = 12.0
	_flame.gravity = Vector3(0.0, 1.2, 0.0)
	_flame.initial_velocity_min = 0.3
	_flame.initial_velocity_max = 0.7
	_flame.scale_amount_min = 0.6
	_flame.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(0.6, 0.9, 1.0, 0.85)
	q.material = fm
	_flame.mesh = q
	_flame.position = Vector3(0.0, 1.45, 0.0)
	add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.88, 1.0)
	_light.light_energy = 1.6
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 2.0, 0.0)
	_light.visible = false
	add_child(_light)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.0, 1.0)
	cs.shape = shape
	cs.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(cs)
	add_child(body)


func get_prompt(_actor: Node) -> String:
	return "风灯已经亮了" if lit else "E  点亮风灯"


func can_interact(_actor: Node) -> bool:
	return not lit


func interact(_actor: Node) -> void:
	if lit:
		return
	set_lit(true)
	_publish_state()


func set_lit(on: bool) -> void:
	if lit == on:
		return
	lit = on
	_crystal.material_override = _bright if on else _dim
	_flame.emitting = on
	_light.visible = on
	lit_changed.emit(self)


func get_state() -> String:
	return "lit" if lit else "unlit"


func apply_state(state: String) -> void:
	set_lit(state == "lit")


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
