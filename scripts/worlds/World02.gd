class_name World02
extends Node3D
## 第二个世界的占位场景（还在建设中）：雾海里一座小浮岛，岛上一块“建设中”的立牌和一道回暮色湖畔的光门。
## 它是一个独立的根场景（group "world_root"），和暮色湖畔不会同时加载——WorldTravel 先卸载湖畔再读它。
## 自带玩家、HUD 和暂停菜单；没有天气、季节和小动物。整个世界只有几十个节点，用来验证“换世界后内存降下来”。

const PORTAL_SHADER := preload("res://shaders/fairy_portal.gdshader")
const ISLAND_R := 14.0

var portal: FairyPortal = null


func _enter_tree() -> void:
	add_to_group("world_root")
	Main.anchor_to_origin(self)


func _ready() -> void:
	_build_environment()
	_build_island()
	_build_gate()
	var sign := SignBoard.create("world_02_wip", "stand", 1.6, 1.5)
	sign.position = Vector3(-3.2, 0.0, 3.0)
	sign.rotation.y = deg_to_rad(20.0)
	add_child(sign)
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as FirstPersonController
	add_child(player)
	add_child((load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate())
	add_child((load("res://scenes/ui/PauseMenu.tscn") as PackedScene).instantiate())
	var a := WorldTravel.arrival()
	var pos := Vector3(0.0, 0.2, 7.0)
	var heading := 0.0
	if not a.is_empty():
		pos = Vector3(float(a["pos"][0]), float(a["pos"][1]), float(a["pos"][2]))
		heading = float(a.get("heading", 0.0))
	player.teleport_to(pos, heading)
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.42, 0.62)
	sm.sky_horizon_color = Color(0.82, 0.72, 0.78)
	sm.ground_horizon_color = Color(0.8, 0.72, 0.78)
	sm.ground_bottom_color = Color(0.55, 0.55, 0.7)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.68, 0.8)
	env.fog_density = 0.0035
	env.fog_height = -2.0
	env.fog_height_density = 0.08
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.86, 0.75)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_island() -> void:
	var grass := ArtMaterials.pbr("leafy_grass", Color(0.9, 0.95, 0.85), "world")
	var rock := ArtMaterials.pbr("rock_face_03", Color(0.7, 0.68, 0.72), "world")
	var top := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = ISLAND_R
	cyl.bottom_radius = ISLAND_R * 0.86
	cyl.height = 1.0
	cyl.radial_segments = 24
	top.mesh = cyl
	top.material_override = grass
	top.position = Vector3(0.0, -0.5, 0.0)
	add_child(top)
	var under := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = ISLAND_R * 0.86
	cone.bottom_radius = 1.5
	cone.height = 9.0
	cone.radial_segments = 9
	under.mesh = cone
	under.material_override = rock
	under.position = Vector3(0.0, -5.5, 0.0)
	add_child(under)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = ISLAND_R
	shape.height = 1.0
	cs.shape = shape
	cs.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(cs)
	# 岛边一圈矮石，别掉下去
	var ring := CylinderShape3D.new()
	ring.radius = 0.5
	ring.height = 1.6
	for i in 36:
		var ang := float(i) / 36.0 * TAU
		var p := Vector3(cos(ang), 0.0, sin(ang)) * (ISLAND_R - 0.4)
		var post := CollisionShape3D.new()
		post.shape = ring
		post.position = p + Vector3(0.0, 0.8, 0.0)
		body.add_child(post)
		if i % 2 == 0:
			var stone := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 0.7, 0.8)
			stone.mesh = bm
			stone.material_override = rock
			stone.position = p + Vector3(0.0, 0.3, 0.0)
			stone.rotation.y = ang
			add_child(stone)
	add_child(body)
	# 远处几座漂浮的小岛（只是背景）
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	for i in 6:
		var far := MeshInstance3D.new()
		var fc := CylinderMesh.new()
		fc.top_radius = rng.randf_range(3.0, 7.0)
		fc.bottom_radius = 0.6
		fc.height = fc.top_radius * 1.6
		fc.radial_segments = 7
		far.mesh = fc
		far.material_override = rock
		var a := float(i) / 6.0 * TAU + rng.randf()
		far.position = Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(45.0, 80.0) + Vector3(0.0, rng.randf_range(-6.0, 10.0), 0.0)
		add_child(far)


func _build_gate() -> void:
	var gate := Node3D.new()
	gate.name = "ReturnGate"
	gate.position = Vector3(0.0, 0.0, 10.5)
	add_child(gate)
	var stone := ArtMaterials.pbr("rock_face_03", Color(0.62, 0.6, 0.66), "world")
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.7, 0.55)
		mi.mesh = bm
		mi.material_override = stone
		mi.transform = Transform3D(Basis(Vector3.FORWARD, a), Vector3(cos(a) * 1.55, 1.75 + sin(a) * 1.55, 0.0))
		gate.add_child(mi)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.8, 2.8)
	face.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	face.material_override = mat
	face.position = Vector3(0.0, 1.75, 0.0)
	gate.add_child(face)
	portal = FairyPortal.create(&"world02_return", "dusk_lake", Vector2(2.4, 2.4))
	portal.position = Vector3(0.0, 1.75, 0.0)
	gate.add_child(portal)
