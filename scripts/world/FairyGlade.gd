class_name FairyGlade
extends Node3D
## 仙境林地——夜里的特殊事件（world_layout.json → fairy_glade；地形 pads 里有一块平台把林地压平）。
## 白天这里只是一片林间空地和一块立牌；晴朗的夜里（20:00 – 次日 4:30，没有雨、雪、雾、雷暴）仙境从地里长出来，
## 屏幕上提示一句；天亮或变天时缩回地下消失，碰撞和传送门也一起关掉。
##   · 中间偏北一棵会发光的仙树：扭转的树干、粉紫青三色的方块树冠，枝下挂着发光的小灯；
##   · 外圈一环大大小小的发光蘑菇（西边留出步道入口、东边留给传送门）；
##   · 几簇半透明的发光水晶；地上一片会发光的小花；
##   · 头顶三座漂浮小岛，慢慢上下浮动、转动，岛边有小瀑布落下；
##   · 东端一座月光石门（FairyPortal），门面是旋转的光，按 E 走进去（其他世界还在建设中）；
##   · 林间飘着粉色、青色的光点；小仙子由 FaunaSpawner 按 species.json 生成（同样只在夜里出来）。
## 全部按方块画风程序生成，材质走 ArtMaterials。

signal event_changed(active: bool)

const PORTAL_SHADER := preload("res://shaders/fairy_portal.gdshader")
const PASTELS := [Color(1.0, 0.62, 0.84), Color(0.72, 0.6, 1.0), Color(0.5, 0.92, 0.95), Color(1.0, 0.86, 0.5)]
const TREE_OFFSET := Vector2(0.0, -6.0)
const TREE_PX := 0.14   ## 仙树每个方块像素的边长（米）
const MUSHROOM_RING := 11.5
const NIGHT_START := 20.0 * 60.0
const NIGHT_END := 4.5 * 60.0
const BAD_WEATHER := [&"LIGHT_RAIN", &"HEAVY_RAIN", &"THUNDERSTORM", &"SNOW", &"FOG"]
const GROW_SECONDS := 2.6

var radius := 15.0
var active := false            ## 仙境现在是否出现
var portal: FairyPortal = null
var islands: Array[Node3D] = []
var mushrooms: Array[Node3D] = []
var _chimes: SoundEmitter = null   ## 仙境出现时的铃声（M3）
var _magic: Node3D             ## 仙境里所有会出现 / 消失的东西都挂在这下面
var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _particles: Array[CPUParticles3D] = []
var _tween: Tween = null
var _check_timer := 0.0


func _enter_tree() -> void:
	var cfg := WorldLayout.section("fairy_glade")
	var c := WorldLayout.v2(cfg["center"])
	position = Vector3(c.x, WorldTerrain.height_at(c.x, c.y), c.y)
	radius = float(cfg.get("radius", 15.0))


func _ready() -> void:
	add_to_group("fairy_glade")
	_rng.seed = 2024
	_magic = Node3D.new()
	_magic.name = "Magic"
	add_child(_magic)
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	_magic.add_child(_body)
	_chimes = SoundEmitter.create("fairy", false)
	_chimes.position = Vector3(0.0, 3.0, 0.0)
	add_child(_chimes)
	_build_tree()
	_build_mushrooms()
	_build_crystals()
	_build_flowers()
	_build_islands()
	_build_portal()
	_build_motes()
	add_child(ZoneArea.create_box(&"fairy_glade", Vector3(radius * 2.0, 8.0, radius * 2.0), Vector3(0.0, 3.0, 0.0), false))
	_apply(false, true)


## 现在该不该出现：晴朗（或多云）的夜里。
static func should_appear(time_minutes: float, weather: StringName) -> bool:
	var t := fposmod(time_minutes, 1440.0)
	# 本局规则：从不 / 晴朗的夜晚（默认）/ 每个夜晚
	return (t >= NIGHT_START or t < NIGHT_END) and GameRules.fairy_allows(weather, not weather in BAD_WEATHER)


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.5
	var want := should_appear(WorldState.time_minutes, WorldState.weather_id)
	if want != active:
		_apply(want, false)


## 出现：从地里长出来（整体从 0.05 倍放大，带一点回弹）并亮起；消失：缩回去后隐藏，碰撞和传送门关掉。
func _apply(on: bool, instant: bool) -> void:
	active = on
	if _chimes != null:
		_chimes.set_on(on, instant)
	if _tween != null:
		_tween.kill()
	_body.collision_layer = PhysicsLayers.WORLD if on else 0
	if portal != null:
		(portal.get_child(0) as StaticBody3D).collision_layer = PhysicsLayers.INTERACTABLE if on else 0
	for p in _particles:
		p.emitting = on
	if on:
		_magic.visible = true
		if instant:
			_magic.scale = Vector3.ONE
		else:
			_magic.scale = Vector3.ONE * 0.05
			_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_magic, "scale", Vector3.ONE, GROW_SECONDS)
			EventBus.toast_requested.emit(tr("东南方的林子里亮起了奇异的光……仙境林地出现了"))
	else:
		if instant:
			_magic.visible = false
		else:
			_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_tween.tween_property(_magic, "scale", Vector3.ONE * 0.05, GROW_SECONDS * 0.6)
			_tween.tween_callback(func() -> void: _magic.visible = false)
	event_changed.emit(on)


## 本地 (x, z) 处的地面高度（相对林地中心）。
func _ground(x: float, z: float) -> float:
	return WorldTerrain.height_at(position.x + x, position.z + z) - position.y


# ---------------------------------------------------------------- 仙树

func _build_tree() -> void:
	var root := Node3D.new()
	root.name = "FairyTree"
	root.position = Vector3(TREE_OFFSET.x, _ground(TREE_OFFSET.x, TREE_OFFSET.y), TREE_OFFSET.y)
	_magic.add_child(root)
	var bark := {"bark": Color(0.42, 0.3, 0.36), "bark_hi": Color(0.55, 0.42, 0.5)}
	var pieces := []
	# 树干：一节节往上、略微扭转；根部向四周伸出
	var x := 0.0
	var z := 0.0
	for i in 10:
		var w := 9.0 - i * 0.4
		pieces.append({"box": [x - w * 0.5, i * 5.0, z - w * 0.5, x + w * 0.5, i * 5.0 + 5.0, z + w * 0.5], "color": "bark" if i % 3 else "bark_hi"})
		x += sin(i * 0.9) * 0.8
		z += cos(i * 0.7) * 0.6
	for a in 6:
		var ang := a * TAU / 6.0 + 0.3
		var d := Vector2(cos(ang), sin(ang))
		pieces.append({"box": [d.x * 4.0 - 2.0, 0, d.y * 4.0 - 2.0, d.x * 9.0 + 2.0, 3.0, d.y * 9.0 + 2.0], "color": "bark"})
	# 四根主枝
	for b in 4:
		var ang := b * TAU / 4.0 + 0.6
		var d := Vector2(cos(ang), sin(ang))
		for s in 4:
			var cx := x + d.x * (4.0 + s * 4.0)
			var cz := z + d.y * (4.0 + s * 4.0)
			pieces.append({"box": [cx - 2.0, 42.0 + s * 3.0, cz - 2.0, cx + 2.0, 46.0 + s * 3.0, cz + 2.0], "color": "bark"})
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = BlockyMesh.build(pieces, func(k: String) -> Color: return bark.get(k, Color.WHITE), TREE_PX)
	root.add_child(trunk)
	_collide_box(Vector3(9.0, 50.0, 9.0) * TREE_PX, root.position + Vector3(0.0, 25.0 * TREE_PX, 0.0))
	# 树冠：一团团粉、紫、青的方块
	var canopy := []
	var leaf_colors := {"a": Color(1.0, 0.7, 0.88), "b": Color(0.78, 0.66, 1.0), "c": Color(0.62, 0.92, 0.95), "d": Color(1.0, 0.86, 0.95)}
	var keys := leaf_colors.keys()
	for i in 72:
		var ang := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 30.0
		var cy := 56.0 + _rng.randf_range(-5.0, 13.0) - r * 0.3
		var s := _rng.randf_range(5.0, 10.0) * (1.0 - r / 40.0)
		var cx := x + cos(ang) * r
		var cz := z + sin(ang) * r
		canopy.append({"box": [cx - s, cy - s * 0.7, cz - s, cx + s, cy + s * 0.7, cz + s], "color": keys[_rng.randi() % keys.size()]})
	var crown := MeshInstance3D.new()
	crown.name = "Canopy"
	crown.mesh = BlockyMesh.build(canopy, func(k: String) -> Color: return leaf_colors.get(k, Color.WHITE), TREE_PX)
	root.add_child(crown)
	# 枝下的小灯：细线吊着发光的小方块，慢慢晃
	for i in 14:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(8.0, 24.0) * TREE_PX
		var hang := Node3D.new()
		hang.position = Vector3(cos(ang) * r, _rng.randf_range(44.0, 52.0) * TREE_PX, sin(ang) * r)
		root.add_child(hang)
		var hang_len := _rng.randf_range(0.3, 0.9)
		_mesh_box(hang, Vector3(0.012, hang_len, 0.012), Vector3(0.0, -hang_len * 0.5, 0.0), ArtMaterials.flat(Color(0.85, 0.8, 0.7), 0.6))
		_mesh_box(hang, Vector3(0.12, 0.12, 0.12), Vector3(0.0, -hang_len - 0.06, 0.0), ArtMaterials.glow(PASTELS[i % PASTELS.size()], 3.0))
		_sway(hang, _rng.randf_range(2.5, 4.0), deg_to_rad(_rng.randf_range(4.0, 9.0)))
	_light(root.position + Vector3(0.0, 40.0 * TREE_PX, 0.0), Color(1.0, 0.7, 0.9), 1.6, 13.0)


# ---------------------------------------------------------------- 蘑菇圈

func _build_mushrooms() -> void:
	var n := 13
	for i in n:
		var ang := float(i) / n * TAU
		# 西边（步道入口，约 180°）和东边（传送门，约 0°）留空
		var deg := fposmod(rad_to_deg(ang), 360.0)
		if deg < 22.0 or deg > 338.0 or (deg > 158.0 and deg < 202.0):
			continue
		var r := MUSHROOM_RING + _rng.randf_range(-1.2, 1.2)
		var p := Vector2(cos(ang), sin(ang)) * r
		var big := _rng.randf() < 0.45
		_mushroom(p, _rng.randf_range(2.2, 3.4) if big else _rng.randf_range(0.9, 1.6), PASTELS[_rng.randi() % 3])
		# 大蘑菇脚下再长两三朵小的
		for k in _rng.randi_range(1, 3):
			var q := p + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
			_mushroom(q, _rng.randf_range(0.35, 0.7), PASTELS[_rng.randi() % 3])


func _mushroom(p: Vector2, h: float, cap: Color) -> void:
	var m := Node3D.new()
	m.name = "Mushroom%d" % mushrooms.size()
	m.position = Vector3(p.x, _ground(p.x, p.y), p.y)
	m.rotation.y = _rng.randf() * TAU
	_magic.add_child(m)
	mushrooms.append(m)
	var px := h / 20.0
	var cols := {"stem": Color(0.96, 0.92, 0.84), "cap": cap, "spot": Color(1.0, 0.98, 0.94), "rim": cap.darkened(0.15)}
	var pieces := [
		{"box": [-2.2, 0, -2.2, 2.2, 13, 2.2], "color": "stem"},
		{"box": [-3.0, 0, -3.0, 3.0, 2, 3.0], "color": "stem"},
		{"box": [-8, 13, -8, 8, 16, 8], "color": "rim"},
		{"box": [-6.5, 16, -6.5, 6.5, 19, 6.5], "color": "cap"},
		{"box": [-4, 19, -4, 4, 20.5, 4], "color": "cap"},
		{"box": [-5.5, 19.0, -2, -3.5, 19.6, 0], "color": "spot"},
		{"box": [2, 19.0, 3, 4, 19.6, 5], "color": "spot"},
		{"box": [-1, 20.5, -1, 1, 21.0, 1], "color": "spot"},
		{"box": [3.5, 16.0, -5, 5.5, 16.6, -3], "color": "spot"},
	]
	var mi := MeshInstance3D.new()
	mi.mesh = BlockyMesh.build(pieces, func(k: String) -> Color: return cols.get(k, Color.WHITE), px)
	m.add_child(mi)
	# 菌褶发光：伞下面一块薄薄的发光板
	_mesh_box(m, Vector3(15.0 * px, 0.4 * px, 15.0 * px), Vector3(0.0, 12.8 * px, 0.0), ArtMaterials.glow(cap, 2.2))
	if h > 1.8:
		_collide_box(Vector3(4.4 * px, 13.0 * px, 4.4 * px), m.position + Vector3(0.0, 6.5 * px, 0.0))
		_light(m.position + Vector3(0.0, 11.0 * px, 0.0), cap, 0.7, 5.0)


# ---------------------------------------------------------------- 水晶与花

func _build_crystals() -> void:
	for spot: Vector2 in [Vector2(-7.0, 4.5), Vector2(6.0, 6.5), Vector2(-5.5, -9.5), Vector2(7.5, -6.0)]:
		var color: Color = PASTELS[_rng.randi() % PASTELS.size()]
		var base := Vector3(spot.x, _ground(spot.x, spot.y), spot.y)
		for i in _rng.randi_range(3, 5):
			var h := _rng.randf_range(0.6, 1.7)
			var mi := MeshInstance3D.new()
			mi.name = "Crystal%d" % _magic.get_child_count()
			mi.mesh = _prism(h * 0.16, h)
			mi.material_override = ArtMaterials.crystal(color)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.rotation = Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf() * TAU, _rng.randf_range(-0.35, 0.35))
			mi.position = base + Vector3(_rng.randf_range(-0.4, 0.4), h * 0.42, _rng.randf_range(-0.4, 0.4))
			_magic.add_child(mi)
		_collide_box(Vector3(0.9, 1.2, 0.9), base + Vector3(0.0, 0.6, 0.0))


## 六棱尖晶体（底宽 r、高 h，尖朝上；down = true 时尖朝下）。
func _prism(r: float, h: float, down := false) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.radial_segments = 6
	cm.rings = 1
	cm.bottom_radius = 0.0 if down else r
	cm.top_radius = r if down else 0.0
	cm.height = h
	return cm


## 地上的发光小花：三种颜色各一个 MultiMesh，避开中间的空地和西边入口的步道。
func _build_flowers() -> void:
	for ci in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 0.07)
		mm.mesh = bm
		var xforms: Array[Transform3D] = []
		for i in 110:
			var ang := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, radius - 0.5)
			var p := Vector2(cos(ang), sin(ang)) * r
			if p.x < -6.0 and absf(p.y) < 2.2:
				continue
			var y := _ground(p.x, p.y) + _rng.randf_range(0.06, 0.22)
			xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, y, p.y)))
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flowers%d" % ci
		mmi.multimesh = mm
		mmi.material_override = ArtMaterials.glow(PASTELS[ci], 2.6)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_magic.add_child(mmi)


# ---------------------------------------------------------------- 漂浮小岛

func _build_islands() -> void:
	var specs := [[Vector2(-6.0, 6.0), 11.0, 3.2], [Vector2(7.0, -8.0), 14.5, 4.2], [Vector2(3.0, 9.0), 17.5, 2.6]]
	var stone := ArtMaterials.pbr("rock_face_03", Color(1.0, 0.95, 1.1))
	for i in specs.size():
		var s: Array = specs[i]
		var p: Vector2 = s[0]
		var size := float(s[2])
		var island := Node3D.new()
		island.name = "FloatingIsland%d" % i
		island.position = Vector3(p.x, float(s[1]), p.y)
		_magic.add_child(island)
		islands.append(island)
		# 倒置的阶梯岩体：一层层往下收成尖，每层错开一点，像块天然的岩石；底尖挂一颗发光水晶
		var depth := 0.0
		for k in 6:
			var w := size * (1.0 - k * 0.15)
			var off := Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12)) * size
			var h := 0.5 + k * 0.08
			_mesh_box(island, Vector3(w, h, w * _rng.randf_range(0.75, 0.95)), Vector3(off.x, -depth - h * 0.5, off.z), stone)
			depth += h
		var tip := MeshInstance3D.new()
		tip.mesh = _prism(size * 0.08, size * 0.35, true)
		tip.material_override = ArtMaterials.crystal(PASTELS[(i + 1) % PASTELS.size()])
		tip.position = Vector3(0.0, -depth - size * 0.17, 0.0)
		island.add_child(tip)
		# 垂下来的藤蔓
		for v in 7:
			var a := _rng.randf() * TAU
			var vl := _rng.randf_range(0.6, 1.8)
			_mesh_box(island, Vector3(0.06, vl, 0.06), Vector3(cos(a) * size * 0.46, -0.1 - vl * 0.5, sin(a) * size * 0.4), ArtMaterials.flat(Color(0.4, 0.66, 0.38), 0.9))
		_mesh_box(island, Vector3(size * 1.04, 0.22, size * 0.9), Vector3(0.0, 0.08, 0.0), ArtMaterials.flat(Color(0.48, 0.74, 0.46), 0.9))
		# 岛上一朵发光蘑菇或一簇水晶
		if i % 2 == 0:
			var m := MeshInstance3D.new()
			var cols := {"stem": Color(0.96, 0.92, 0.84), "cap": PASTELS[i % 3]}
			m.mesh = BlockyMesh.build([{"box": [-2, 0, -2, 2, 12, 2], "color": "stem"}, {"box": [-7, 12, -7, 7, 17, 7], "color": "cap"}], func(k: String) -> Color: return cols.get(k, Color.WHITE), 0.06)
			m.position = Vector3(size * 0.15, 0.18, -size * 0.1)
			island.add_child(m)
		else:
			for c in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = _prism(0.14, 0.9 - c * 0.2)
				mi.material_override = ArtMaterials.crystal(PASTELS[(i + c) % PASTELS.size()])
				mi.position = Vector3(c * 0.25 - 0.25, 0.6, c * 0.15)
				mi.rotation.z = (c - 1) * 0.3
				island.add_child(mi)
		# 小瀑布：从岛的一边落下的水珠
		var fall := _waterfall(Vector3(size * 0.5, -0.05, 0.0), float(s[1]))
		island.add_child(fall)
		_particles.append(fall)
		# 慢慢上下浮动、转动（相位错开）
		var bob := island.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		bob.tween_property(island, "position:y", island.position.y + 0.5, 3.5 + i)
		bob.tween_property(island, "position:y", island.position.y, 3.5 + i)
		var spin := island.create_tween().set_loops()
		spin.tween_property(island, "rotation:y", TAU * (1.0 if i % 2 == 0 else -1.0), 80.0 + i * 20.0).as_relative()


func _waterfall(at: Vector3, height: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Waterfall"
	p.position = at
	p.emitting = false
	p.amount = 48
	p.lifetime = clampf(sqrt(2.0 * height / 7.0), 1.0, 2.6)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.05, 0.02, 0.35)
	p.direction = Vector3(1.0, -0.2, 0.0)
	p.spread = 8.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.92, 1.0, 0.6)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	p.mesh = q
	return p


# ---------------------------------------------------------------- 传送门

func _build_portal() -> void:
	var cfg: Dictionary = WorldLayout.section("fairy_glade").get("portal", {})
	var off := WorldLayout.v2(cfg.get("offset", [10.0, 0.0]))
	var gate := Node3D.new()
	gate.name = "MoonGate"
	gate.position = Vector3(off.x, _ground(off.x, off.y), off.y)
	gate.rotation.y = deg_to_rad(float(cfg.get("yaw_deg", -90.0)))
	_magic.add_child(gate)
	var moonstone := ArtMaterials.pbr("rustic_stone_wall", Color(0.88, 0.9, 1.0))
	var ring_r := 2.0
	var center_y := 2.5
	var n := 22
	for i in n:
		var a := float(i) / n * TAU
		var pos := Vector3(cos(a) * ring_r, center_y + sin(a) * ring_r, 0.0)
		var b := Basis(Vector3.FORWARD, a)
		_mesh_box(gate, Vector3(0.42, 0.62, 0.5), pos, moonstone, b)
		_collide_box(Vector3(0.42, 0.62, 0.5), gate.position + gate.basis * pos, gate.basis * b)
		if i % 4 == 0:
			_mesh_box(gate, Vector3(0.12, 0.12, 0.08), pos + Vector3(0.0, 0.0, 0.27), ArtMaterials.glow(Color(0.7, 0.9, 1.0), 3.0))
	for sx: float in [-1.0, 1.0]:
		_mesh_box(gate, Vector3(0.9, 0.45, 0.9), Vector3(sx * ring_r, 0.22, 0.0), moonstone)
	var face := MeshInstance3D.new()
	face.name = "PortalFace"
	var q := QuadMesh.new()
	q.size = Vector2(ring_r * 2.0 - 0.3, ring_r * 2.0 - 0.3)
	face.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	face.material_override = mat
	face.position = Vector3(0.0, center_y, 0.0)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(face)
	portal = FairyPortal.create(&"fairy_portal", str(cfg.get("world", "world_02")), Vector2(ring_r * 1.6, ring_r * 1.6))
	portal.position = Vector3(0.0, center_y, 0.0)
	gate.add_child(portal)
	_light(gate.position + Vector3(0.0, center_y, 0.0), Color(0.65, 0.88, 1.0), 1.6, 9.0)


# ---------------------------------------------------------------- 光点

func _build_motes() -> void:
	for ci in 2:
		var p := CPUParticles3D.new()
		p.name = "Motes%d" % ci
		p.emitting = false
		p.position = Vector3(0.0, 1.5, 0.0)
		p.amount = 45
		p.lifetime = 7.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(radius * 0.9, 1.2, radius * 0.9)
		p.direction = Vector3(0.0, 1.0, 0.0)
		p.spread = 35.0
		p.initial_velocity_min = 0.15
		p.initial_velocity_max = 0.4
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var q := QuadMesh.new()
		q.size = Vector2(0.09, 0.09)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_color = PASTELS[ci] * Color(1, 1, 1, 0.9)
		q.material = m
		p.mesh = q
		var fade := Gradient.new()
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		p.color_ramp = fade
		_magic.add_child(p)
		_particles.append(p)


# ---------------------------------------------------------------- 工具

func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


## 碰撞盒（林地本地坐标）。仙境消失时整个碰撞体的碰撞层清零。
func _collide_box(size: Vector3, pos: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, pos)
	_body.add_child(cs)


func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	_magic.add_child(l)


func _sway(node: Node3D, seconds: float, angle: float) -> void:
	var tw := node.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:z", angle, seconds)
	tw.tween_property(node, "rotation:z", -angle, seconds)
