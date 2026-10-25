class_name CabinLife
extends Node3D
## 木屋生活：铸铁炉生火 / 熄火（炉膛火苗、火光闪烁、烟囱冒烟）、落地灯 / 台灯 / 吊灯 / 门廊灯开关、
## 沙发 / 扶手椅 / 门廊长椅可以坐下、床可以睡到第二天早上、茶几上可以下国际象棋（ChessTable）。
## 挂在 Cabin/Generated 下，用木屋局部坐标（地板顶面 y = 0，+X 朝湖）。状态按 uid 记在 WorldState。
## 只在运行时生成（编辑器里只看木屋本体）。

const STOVE := Vector3(-3.9, 0.0, -1.0)        ## 铸铁炉底面中心（与 build_cabin.py 一致）
const CHIMNEY_TOP := Vector3(-3.9, 7.48, -1.0)

var stove: InteractableToggle
var lamps := {}                 ## uid -> InteractableToggle
var seats: Array[Seat] = []
var bed: Bed
var chess: ChessTable
var pot: CookPot
var cabinet: TrophyCabinet

var _lights := {}               ## 名称 -> [OmniLight3D, 亮着时的能量]
var _fire: GPUParticles3D
var _smoke: CPUParticles3D
var _fire_mat: StandardMaterial3D
var _porch_glow: StandardMaterial3D
var _flicker_t := 0.0


## lights：Cabin 生成的灯（名称 -> OmniLight3D）；model：木屋模型（找炉膛和门廊灯的发光材质）。
func setup(lights: Dictionary, model: Node) -> void:
	for k in lights:
		_lights[k] = [lights[k], (lights[k] as OmniLight3D).light_energy]
	_find_glow_materials(model)
	_build_stove()
	_build_lamps()
	_build_seats()
	bed = Bed.create(&"cabin_bed", Vector3(-3.77, 0.0, 2.08), Vector3(2.3, 0.85, 1.95), Vector3(1.6, 0.05, -0.1))
	add_child(bed)
	# 茶几上的国际象棋（白方靠沙发一侧）
	chess = ChessTable.create(&"cabin_chess", Vector3(1.08, 0.47, 1.3), 0.0)
	add_child(chess)
	# 北墙书架和边桌之间的收藏柜（面朝屋里）
	cabinet = TrophyCabinet.create(Vector3(1.25, 0.0, -3.0))
	add_child(cabinet)


func _find_glow_materials(model: Node) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			if src.resource_name == "M_FireGlow":
				if _fire_mat == null:
					_fire_mat = (ArtMaterials.named("M_FireGlow") as StandardMaterial3D).duplicate()
				mi.set_surface_override_material(s, _fire_mat)
			elif src.resource_name == "M_LampGlow":
				if _porch_glow == null:
					_porch_glow = (ArtMaterials.named("M_LampGlow") as StandardMaterial3D).duplicate()
				mi.set_surface_override_material(s, _porch_glow)


# ---------------------------------------------------------------- 铸铁炉

func _build_stove() -> void:
	stove = InteractableToggle.create(&"cabin_stove", "铸铁炉", true, "E  熄灭炉火", "E  生火", Vector3(0.9, 1.15, 0.75), Vector3(0.0, 0.57, 0.0))
	stove.position = STOVE
	add_child(stove)
	_fire = _make_fire()
	_fire.position = STOVE + Vector3(0.40, 0.5, 0.0)
	add_child(_fire)
	_smoke = _make_smoke()
	_smoke.position = CHIMNEY_TOP
	add_child(_smoke)
	stove.toggled.connect(_on_stove)
	pot = CookPot.create(&"cabin_pot", STOVE + Vector3(0.0, 1.16, 0.0), stove)
	add_child(pot)
	_on_stove(stove.on)


func _on_stove(on: bool) -> void:
	_fire.emitting = on
	_smoke.emitting = on
	if _fire_mat != null:
		_fire_mat.emission_energy_multiplier = 5.0 if on else 0.05
		_fire_mat.albedo_color = Color(1.0, 0.42, 0.10) if on else Color(0.08, 0.06, 0.05)
	_set_light("stove", on)


func _process(delta: float) -> void:
	if stove == null or not stove.on:
		return
	# 炉火闪烁：两组不同频率的正弦叠一点随机
	_flicker_t += delta
	var light: OmniLight3D = _lights["stove"][0]
	var base: float = _lights["stove"][1]
	light.light_energy = base * (0.82 + 0.12 * sin(_flicker_t * 9.3) * sin(_flicker_t * 3.7 + 1.1) + 0.06 * randf())


func _make_fire() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.02, 0.04, 0.14)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 0.95), Color(1.0, 0.5, 0.12, 0.9), Color(0.85, 0.18, 0.05, 0.5), Color(0.3, 0.05, 0.02, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.09)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.name = "StoveFire"
	p.emitting = false
	p.amount = 48
	p.lifetime = 0.55
	p.process_material = pm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-0.5, -0.2, -0.5), Vector3(1.0, 1.0, 1.0))
	return p


func _make_smoke() -> CPUParticles3D:
	# 只有 40 个粒子，用 CPU 粒子：同样参数的 GPUParticles3D 在这里只停在发射点不动（原因未查明）
	var p := CPUParticles3D.new()
	p.name = "ChimneySmoke"
	p.emitting = false
	p.amount = 40
	p.lifetime = 7.0
	p.local_coords = false
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 12.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.25, 0.1, 0.15)
	var grow := Curve.new()
	grow.max_value = 2.0
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(0.75, 0.74, 0.72, 0.0), Color(0.72, 0.71, 0.70, 0.4), Color(0.8, 0.8, 0.8, 0.0)])
	p.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true
	mat.albedo_texture = _soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


# ---------------------------------------------------------------- 灯

func _build_lamps() -> void:
	_lamp(&"cabin_floor_lamp", "落地灯", "floor_lamp", Vector3(2.35, 0.0, 2.6), Vector3(0.5, 1.9, 0.5), Vector3(0.0, 0.95, 0.0))
	_lamp(&"cabin_table_lamp", "台灯", "table_lamp", Vector3(1.75, 0.47, 1.35), Vector3(0.36, 0.5, 0.36), Vector3(0.0, 0.25, 0.0))
	# 吊灯与门廊灯用门边的墙上开关（室内一个、门廊一个）
	_lamp(&"cabin_ceiling_light", "吊灯", "ceiling", Vector3(4.86, 1.25, -0.95), Vector3(0.14, 0.3, 0.24), Vector3.ZERO, true)
	_lamp(&"cabin_porch_light", "门廊灯", "porch", Vector3(5.14, 1.25, -0.95), Vector3(0.14, 0.3, 0.24), Vector3.ZERO, true)


func _lamp(id: StringName, label: String, light_name: String, pos: Vector3, size: Vector3, offset: Vector3, wall_switch := false) -> void:
	var t := InteractableToggle.create(id, label, true, "E  关%s" % label, "E  开%s" % label, size, offset)
	t.position = pos
	add_child(t)
	if wall_switch:
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.14, 0.09)
		plate.mesh = box
		plate.material_override = ArtMaterials.flat(Color(0.92, 0.9, 0.85), 0.6)
		t.add_child(plate)
	t.toggled.connect(_on_lamp.bind(light_name))
	lamps[id] = t


func _on_lamp(on: bool, light_name: String) -> void:
	_set_light(light_name, on)
	if light_name == "porch" and _porch_glow != null:
		_porch_glow.emission_energy_multiplier = 2.2 if on else 0.0
		_porch_glow.albedo_color = Color(1.0, 0.78, 0.50) if on else Color(0.25, 0.23, 0.2)


func _set_light(light_name: String, on: bool) -> void:
	if not _lights.has(light_name):
		return
	var light: OmniLight3D = _lights[light_name][0]
	light.visible = on
	light.light_energy = _lights[light_name][1]


func light_on(light_name: String) -> bool:
	return _lights.has(light_name) and (_lights[light_name][0] as OmniLight3D).visible


# ---------------------------------------------------------------- 座位

func _build_seats() -> void:
	# 沙发长边两个位子（面朝茶几，-Z），转角那段一个位子（面朝 +X）
	for item in [
		[&"cabin_sofa_left", "沙发", Vector3(1.45, 0.48, 2.45), 0.0],
		[&"cabin_sofa_right", "沙发", Vector3(0.75, 0.48, 2.45), 0.0],
		[&"cabin_sofa_corner", "沙发", Vector3(0.2, 0.48, 1.45), -90.0],
		[&"cabin_armchair", "扶手椅", Vector3(-2.35, 0.45, 0.55), 70.0],
		[&"cabin_porch_bench", "门廊长椅", Vector3(6.35, 0.47, -2.2), -90.0],
	]:
		var s := Seat.create(item[0], item[1], item[2], item[3])
		add_child(s)
		seats.append(s)
