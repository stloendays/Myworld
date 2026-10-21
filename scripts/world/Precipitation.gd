@tool
class_name Precipitation
extends Node3D
## 雨雪粒子：只在当前相机周围约 60 m 范围内生成（节省性能），粒子留在世界坐标里下落。
## 室内不下雨雪：一个跟随相机的 GPUParticlesCollisionHeightField3D 记录俯视高度（地形、树冠、
## 木屋屋顶都在里面），粒子碰到即消失，所以屋顶下面、屋檐下面不会出现雨雪；窗外的雨照常可见。
## 强度由 EnvironmentDirector 通过 set_amounts() 平滑设置（amount_ratio），不重启粒子。

const RAIN_MAX := 9000
const SNOW_MAX := 5000

var rain: GPUParticles3D = null
var snow: GPUParticles3D = null
var heightfield: GPUParticlesCollisionHeightField3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("precipitation")
	rain = _make_rain()
	snow = _make_snow()
	add_child(rain)
	add_child(snow)
	heightfield = GPUParticlesCollisionHeightField3D.new()
	heightfield.name = "RoofAndGround"
	heightfield.size = Vector3(90.0, 70.0, 90.0)
	heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	heightfield.follow_camera_enabled = true
	heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(heightfield)
	set_amounts(0.0, 0.0, 0.0)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = cam.global_position


func set_amounts(rain_amount: float, snow_amount: float, wind: float) -> void:
	if rain == null:
		return
	_set_layer(rain, rain_amount)
	_set_layer(snow, snow_amount)
	(rain.process_material as ParticleProcessMaterial).direction = Vector3(wind * 0.25, -1.0, wind * 0.1).normalized()
	(snow.process_material as ParticleProcessMaterial).gravity = Vector3(wind * 0.8, -1.1, wind * 0.3)


## 只在数值变化时写入：反复设置 emitting 会让带 preprocess 的粒子重新预热，雪停后残留不散。
func _set_layer(p: GPUParticles3D, amount: float) -> void:
	var ratio := clampf(amount, 0.0, 1.0)
	if absf(p.amount_ratio - ratio) > 0.002:
		p.amount_ratio = ratio
	var on := amount > 0.01
	if p.emitting != on:
		p.emitting = on


func _make_rain() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 2.0, 30.0)
	pm.emission_shape_offset = Vector3(0.0, 16.0, 0.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 19.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.particle_flag_align_y = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.78, 0.88, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.6)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.emitting = false
	p.amount_ratio = 0.0
	p.amount = RAIN_MAX
	p.lifetime = 1.3
	p.preprocess = 1.3
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.collision_base_size = 0.02
	p.visibility_aabb = AABB(Vector3(-40.0, -30.0, -40.0), Vector3(80.0, 60.0, 80.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_snow() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 3.0, 30.0)
	pm.emission_shape_offset = Vector3(0.0, 12.0, 0.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.0, -1.1, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Snow"
	p.emitting = false
	p.amount_ratio = 0.0
	p.amount = SNOW_MAX
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.collision_base_size = 0.05
	p.visibility_aabb = AABB(Vector3(-40.0, -30.0, -40.0), Vector3(80.0, 60.0, 80.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
