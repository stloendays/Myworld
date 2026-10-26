class_name EmberField
extends GPUParticles3D
## 暮烬：暮烬之夜从湖面升起来的火星（StoryDirector 开关）。一层贴着水面的发光小方块，慢慢往上飘、随风斜、
## 越飘越暗，十几秒后在十来米高处熄掉。不受光照（夜里也亮）、叠加混合，配合原版红点（legacy_red_motes，
## 跟着镜头飘落的那一层）一起出现。位置取 world_layout.json → lake 的中心与半径。

const AMOUNT := 1800
const LIFETIME := 16.0

var active := false
var _ratio := 0.0


func _ready() -> void:
	add_to_group("ember_field")
	var lake := WorldLayout.section("lake")
	var c := WorldLayout.v2(lake["center"])
	var radii: Array = lake["radii"]
	var inner := float(lake.get("inner", 0.82))
	position = Vector3(c.x, WorldLayout.water_level() + 0.2, c.y)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(radii[0]) * inner * 0.85, 0.2, float(radii[1]) * inner * 0.85)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.45
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.25, 0.04, 0.12)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	# 刚冒出来是亮橙黄，飘高了变红、变暗，最后熄掉
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.45, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 0.0), Color(1.0, 0.7, 0.28, 1.0), Color(1.0, 0.42, 0.16, 0.9),
		Color(0.85, 0.2, 0.1, 0.45), Color(0.6, 0.12, 0.06, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(2.2, 1.5, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = mat
	name = "Embers"
	amount = AMOUNT
	lifetime = LIFETIME
	preprocess = LIFETIME
	local_coords = false
	process_material = pm
	draw_pass_1 = quad
	visibility_aabb = AABB(Vector3(-90.0, -2.0, -75.0), Vector3(180.0, 40.0, 150.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = false
	amount_ratio = 0.0


## 开关：开的时候几秒内飘满，关的时候不再冒新的，已经在空中的自己熄掉。instant 用于读档、截图。
func set_active(on: bool, instant := false) -> void:
	active = on
	if instant:
		_ratio = 1.0 if on else 0.0
		amount_ratio = _ratio
		if on:
			restart()
	if on and not emitting:
		emitting = true


func _process(delta: float) -> void:
	_ratio = move_toward(_ratio, 1.0 if active else 0.0, delta * 0.25)
	if amount_ratio != _ratio:
		amount_ratio = _ratio
	if not active and _ratio <= 0.0 and emitting:
		emitting = false
