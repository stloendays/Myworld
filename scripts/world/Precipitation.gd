@tool
class_name Precipitation
extends Node3D
## 雨雪粒子：只在当前相机周围约 60 m 范围内生成（节省性能），粒子留在世界坐标里下落。
## 室内不下雨雪：一个跟随相机的 GPUParticlesCollisionHeightField3D 记录俯视高度（地形、树冠、
## 木屋屋顶都在里面），粒子碰到即消失，所以屋顶下面、屋檐下面不会出现雨雪；窗外的雨照常可见。
## 强度由 EnvironmentDirector 通过 set_amounts() 平滑设置（amount_ratio），不重启粒子。
## 雨滴落地（碰到地面或屋顶）时由子发射器溅起小水花。
## set_seasonal()：秋季飘落叶、春季飘花瓣，夜里、雨雪天和冬夏不飘；数量与外观来自 data/weather/seasonal_fx.json，
## 晴天无风时只零星几片，风越大越多。profile_override 可临时指定方案（开发者面板），"" = 按季节，"off" = 关闭。

const RAIN_MAX := 7000
const SNOW_MAX := 5000
## 落叶单独放在渲染层 4：跟随相机的高度场把树冠也当成“地面”，所以落叶不接它，只接建筑各自放的挡板。
const LEAF_LAYER := 8

var rain: GPUParticles3D = null
var snow: GPUParticles3D = null
var heightfield: GPUParticlesCollisionHeightField3D = null
var splash: GPUParticles3D = null
var leaves: GPUParticles3D = null
var leaves_kind := ""
var profile_override := ""
var story_profile := ""   ## 剧情临时指定的方案（暮烬之夜 = 原版红点 legacy_red_motes，StoryDirector 设）；开发者面板的 profile_override 优先
const FX_PATH := "res://data/weather/seasonal_fx.json"
static var _fx: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("precipitation")
	rain = _make_rain()
	snow = _make_snow()
	splash = _make_splash()
	add_child(splash)
	add_child(rain)
	add_child(snow)
	rain.sub_emitter = rain.get_path_to(splash)
	leaves = _make_leaves()
	add_child(leaves)
	heightfield = GPUParticlesCollisionHeightField3D.new()
	heightfield.name = "RoofAndGround"
	heightfield.size = Vector3(90.0, 70.0, 90.0)
	heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	heightfield.follow_camera_enabled = true
	heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	heightfield.cull_mask = 0xFFFFF & ~LEAF_LAYER
	add_child(heightfield)
	set_amounts(0.0, 0.0, 0.0)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var jumped := global_position.distance_to(cam.global_position) > 25.0
		global_position = cam.global_position
		# 落叶在世界坐标里飘、寿命长；相机瞬移（读档、调试跳转）后在新位置重新预热，不然要等十几秒才飘满
		if jumped and leaves.emitting:
			leaves.restart()


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


static func fx_data() -> Dictionary:
	if _fx.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FX_PATH))
		_fx = parsed if parsed is Dictionary else {"active": {}, "profiles": {}}
	return _fx


static func fx_profile(id: String) -> Dictionary:
	return (fx_data()["profiles"] as Dictionary).get(id, {})


## 当前季节用哪个方案（"" = 不飘）。
func seasonal_profile_id(season: StringName) -> String:
	if profile_override == "off":
		return ""
	if profile_override != "":
		return profile_override
	if story_profile != "":
		return story_profile
	return str((fx_data()["active"] as Dictionary).get(String(season), ""))


## 季节飘落物：按方案设数量、颜色和形状；风越大越多、飘得越斜，雨雪天与夜里几乎不飘。
func set_seasonal(season: StringName, night: float, precipitation: float, wind: float) -> void:
	if leaves == null:
		return
	var kind := seasonal_profile_id(season)
	var prof := fx_profile(kind)
	if kind != leaves_kind:
		leaves_kind = kind
		if not prof.is_empty():
			_apply_profile(prof)
		# 换季时清掉还在空中的旧叶子，免得秋叶被染成花瓣色飘到夏天
		leaves.restart()
	var amount := 0.0
	if not prof.is_empty():
		amount = (float(prof["calm"]) + wind * float(prof["wind_gain"])) * (1.0 - smoothstep(0.1, 0.4, precipitation)) \
			* (1.0 - night * (1.0 - float(prof.get("night_keep", 0.2))))
	_set_layer(leaves, amount)
	(leaves.process_material as ParticleProcessMaterial).gravity = Vector3(1.6 * wind + 0.2, -0.14, 1.1 * wind)


func _apply_profile(prof: Dictionary) -> void:
	leaves.amount = int(prof["amount"])
	var quad := leaves.draw_pass_1 as QuadMesh
	var size: Array = prof["size"]
	quad.size = Vector2(float(size[0]), float(size[1]))
	var mat := quad.material as StandardMaterial3D
	mat.albedo_color = Color.html(str(prof["albedo"]))
	mat.albedo_texture = _shape_texture(str(prof.get("shape", "square")))
	var g := Gradient.new()
	var cols := PackedColorArray()
	var offs := PackedFloat32Array()
	var ramp: Array = prof["ramp"]
	for i in ramp.size():
		cols.append(Color.html(str(ramp[i])))
		offs.append(float(i) / maxf(1.0, ramp.size() - 1.0))
	g.colors = cols
	g.offsets = offs
	var tex := GradientTexture1D.new()
	tex.gradient = g
	(leaves.process_material as ParticleProcessMaterial).color_ramp = tex


## 飘落物的剪影（16×16 像素、最近邻，与方块画风一致）：leaf 带叶柄的尖叶，petal 圆瓣，square 整块（原版红点）。
static func _shape_texture(shape: String) -> Texture2D:
	if shape == "square":
		return null
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var u := (x + 0.5) / 8.0 - 1.0
			var v := (y + 0.5) / 8.0 - 1.0
			var inside := false
			var shade := 1.0
			if shape == "leaf":
				# 叶片沿对角线：中脉稍暗，右下角伸出叶柄
				var a := (u + v) * 0.7071
				var b := (u - v) * 0.7071
				inside = a * a / 0.72 + b * b / 0.2 < 1.0 or (a > 0.75 and a < 1.25 and absf(b) < 0.08)
				shade = 0.8 if absf(b) < 0.07 else 1.0
			else:
				inside = u * u / 0.85 + (v + 0.1) * (v + 0.1) / 0.6 < 1.0 and not (absf(u) < 0.14 and v < -0.55)
			if inside:
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex


## 建筑用的落叶挡板（局部坐标）：只作用于落叶层，雨雪仍由高度场处理。
static func leaf_blocker(size: Vector3, xform: Transform3D) -> GPUParticlesCollisionBox3D:
	var b := GPUParticlesCollisionBox3D.new()
	b.name = "LeafBlocker"
	b.size = size
	b.transform = xform
	b.cull_mask = LEAF_LAYER
	return b


func _make_splash() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.84, 0.92, 0.45)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Splash"
	p.emitting = false
	p.amount = 6000
	p.lifetime = 0.28
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-40.0, -30.0, -40.0), Vector3(80.0, 60.0, 80.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_leaves() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18.0, 3.5, 18.0)
	pm.emission_shape_offset = Vector3(0.0, 3.5, 0.0)
	pm.direction = Vector3(1.0, -0.3, 0.6)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.4, -0.14, 0.2)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 4.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -160.0
	pm.angular_velocity_max = 160.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# 只碰建筑挡板（见 LEAF_LAYER）；落到地下的叶子本来就被地形挡住
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.albedo_color = Color(0.86, 0.52, 0.2)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.09)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Leaves"
	p.layers = LEAF_LAYER
	p.collision_base_size = 0.05
	p.emitting = false
	p.amount_ratio = 0.0
	p.amount = 700
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-40.0, -30.0, -40.0), Vector3(80.0, 60.0, 80.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_rain() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 2.0, 30.0)
	pm.emission_shape_offset = Vector3(0.0, 16.0, 0.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 2.0
	# 雨滴接近终端速度匀速落下（约 8–10 m/s），不再像早先那样 25 m/s 往下砸
	pm.initial_velocity_min = 7.5
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0.0, -1.5, 0.0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.particle_flag_align_y = true
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.78, 0.88, 0.28)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.011, 0.3)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.emitting = false
	p.amount_ratio = 0.0
	p.amount = RAIN_MAX
	p.lifetime = 2.4
	p.preprocess = 2.4
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
