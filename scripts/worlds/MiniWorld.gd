class_name MiniWorld
extends Node3D
## 湖畔以外的世界（云海浮岛、琥珀沙丘）的共用底座。每个世界是一个独立的根场景（group "world_root"），
## 和湖畔不会同时加载——WorldTravel 先卸载当前世界、清缓存，再在后台线程读它。
## 位置与内容写在数据文件里（worlds.json → data，例如 data/worlds/cloudsea.json）：出生点、光门、探索点、收集品、卷轴、小地图范围。
## 这里负责大家都一样的部分：
##   · 天空、雾、太阳（方向固定，阴影不会随时间爬动）；
##   · 玩家、HUD、暂停菜单、小地图、世界地图（Tab）、罗盘条、旅行日志、聊天框、动作轮盘、画质管理；
##   · 探索点（走进半径算发现）、收集品（走近自动捡起，按世界记进 WorldState.collections）、卷轴、回湖畔的光门；
##   · 掉出世界（掉进云海、走出边界）时黑幕一闪，回到最后站稳的地方。
## 子类实现 height_at()（地面高度，没有地面返回 -INF）、build_world()（地形与地标）、map_color()（小地图底色）、
## draw_map()（小地图和世界地图上的桥、建筑等矢量图形）。

const DATA_KEY := "data"
const PORTAL_SHADER := preload("res://shaders/fairy_portal.gdshader")
const PICKUP_RADIUS := 1.7
const MAP_RES := 192

@export var world_id := ""

var data: Dictionary = {}
var player: FirstPersonController = null
var portal: FairyPortal = null
var items: Array[Dictionary] = []      ## 收集品：{id, node, pos}
var safe_spot := Vector3.ZERO          ## 最后一次稳稳站在地上的位置（掉出世界时回到这里）
var falls := 0                         ## 掉出世界的次数（自动检查读）
var map_texture: Texture2D = null

var _poi_timer := 0.0
var _safe_timer := 0.0
var _respawning := false
var _sun: DirectionalLight3D = null

static var _data_cache: Dictionary = {}


## 某个世界的数据文件（worlds.json 里这个世界的 data 字段）。
static func data_for(id: String) -> Dictionary:
	if _data_cache.has(id):
		return _data_cache[id]
	var path := str(WorldRegistry.get_world(id).get(DATA_KEY, ""))
	var d: Dictionary = {}
	if path != "" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			d = parsed
	_data_cache[id] = d
	return d


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _enter_tree() -> void:
	add_to_group("world_root")
	Main.anchor_to_origin(self)
	data = data_for(world_id)


func _ready() -> void:
	_build_environment()
	build_world()
	_build_signs()
	_build_items()
	_build_gate()
	_spawn_player()
	map_texture = ImageTexture.create_from_image(bake_map())
	_build_ui()
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- 子类实现

## 地面高度（世界坐标）；这里没有地面（虚空、云海）返回 -INF。
func height_at(_x: float, _z: float) -> float:
	return -INF


func build_world() -> void:
	pass


## 小地图底色；h = height_at 的结果。
func map_color(_x: float, _z: float, h: float) -> Color:
	return Color(0.4, 0.5, 0.35) if h > -1e6 else Color(0.75, 0.78, 0.86)


## 在小地图 / 世界地图上画桥、建筑等（canvas 已经设好世界 → 像素的变换，单位是米）。
func draw_map(_canvas: CanvasItem) -> void:
	pass


## 世界地图上的地名 [{pos: Vector2, text}]。
func map_labels() -> Array:
	return data.get("labels", []).map(func(l: Dictionary) -> Dictionary: return {"pos": v2(l["pos"]), "text": str(l["text"])})


# ---------------------------------------------------------------- 地图与标记

func map_rect() -> Rect2:
	var r: Array = data.get("map_rect", [-100, -100, 200, 200])
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## 小地图底图：按高度和 map_color 上色，再按西北光做一点山体明暗。
func bake_map() -> Image:
	var rect := map_rect()
	var n := MAP_RES
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cell := rect.size / float(n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = height_at(rect.position.x + (i + 0.5) * cell.x, rect.position.y + (j + 0.5) * cell.y)
	for j in n:
		for i in n:
			var x := rect.position.x + (i + 0.5) * cell.x
			var z := rect.position.y + (j + 0.5) * cell.y
			var h := hs[j * n + i]
			var col := map_color(x, z, h)
			if h > -1e6:
				var hx := hs[j * n + mini(i + 1, n - 1)] - hs[j * n + maxi(i - 1, 0)]
				var hz := hs[mini(j + 1, n - 1) * n + i] - hs[maxi(j - 1, 0) * n + i]
				if not (is_finite(hx) and is_finite(hz)):
					hx = 0.0
					hz = 0.0
				var normal := Vector3(-hx, 2.0 * cell.x, -hz).normalized()
				col *= clampf(0.6 + normal.dot(Vector3(-0.6, 1.2, -0.6).normalized()) * 0.5, 0.5, 1.15)
			img.set_pixel(i, j, Color(col.r, col.g, col.b))
	return img


## 罗盘、小地图、世界地图共用的标记：探索点、收集品、光门。
func map_markers() -> Array:
	var out := []
	for poi: Dictionary in data.get("pois", []):
		out.append({"pos": v2(poi["center"]), "kind": "poi", "done": StringName(poi["id"]) in WorldState.discoveries, "label": str(poi["name"])})
	if GameRules.flag("collectibles"):
		var got := WorldState.collected(world_id)
		for it in items:
			var p: Vector3 = it["pos"]
			out.append({"pos": Vector2(p.x, p.z), "kind": "item", "done": str(it["id"]) in got, "label": ""})
	var g: Dictionary = data.get("gate", {})
	if not g.is_empty():
		var gp := v3(g["pos"])
		out.append({"pos": Vector2(gp.x, gp.z), "kind": "gate", "done": false, "label": "光门"})
	return out


# ---------------------------------------------------------------- 环境

func _build_environment() -> void:
	var sky_cfg: Dictionary = data.get("sky", {})
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = _col(sky_cfg.get("top"), Color(0.3, 0.42, 0.7))
	sm.sky_horizon_color = _col(sky_cfg.get("horizon"), Color(0.85, 0.75, 0.75))
	sm.ground_horizon_color = _col(sky_cfg.get("ground_horizon"), sm.sky_horizon_color)
	sm.ground_bottom_color = _col(sky_cfg.get("ground_bottom"), Color(0.45, 0.45, 0.55))
	sm.sun_angle_max = 30.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(sky_cfg.get("ambient", 1.0))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(sky_cfg.get("exposure", 1.0))
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_bloom = 0.05
	env.glow_intensity = 0.7
	env.fog_enabled = true
	env.fog_light_color = _col(sky_cfg.get("fog_color"), Color(0.8, 0.75, 0.8))
	env.fog_density = float(sky_cfg.get("fog_density", 0.004))
	env.fog_sky_affect = 0.2
	env.fog_aerial_perspective = 0.4
	env.fog_height = float(sky_cfg.get("fog_height", -10.0))
	env.fog_height_density = float(sky_cfg.get("fog_height_density", 0.0))
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	var el := deg_to_rad(float(sky_cfg.get("sun_elevation", 25.0)))
	var az := deg_to_rad(float(sky_cfg.get("sun_azimuth", 240.0)))
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	_sun.light_color = _col(sky_cfg.get("sun_color"), Color(1.0, 0.85, 0.7))
	_sun.light_energy = float(sky_cfg.get("sun_energy", 1.2))
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 120.0
	_sun.shadow_blur = 1.5
	add_child(_sun)


static func _col(v: Variant, fallback: Color) -> Color:
	if v is String:
		return Color.html(v)
	if v is Array:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


# ---------------------------------------------------------------- 地形工具

## 按 height_at 建一块方格地形（网格 + 高度场碰撞）。rect 世界范围，step 网格边长；
## color_fn(x, z, h, normal) -> Color 给顶点色。材质用 ArtMaterials 的贴图（三平面投影）× 顶点色。
func build_grid_terrain(rect: Rect2, step: float, color_fn: Callable, mat: Material, name_ := "Terrain") -> MeshInstance3D:
	var nx := int(ceil(rect.size.x / step)) + 1
	var nz := int(ceil(rect.size.y / step)) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for j in nz:
		for i in nx:
			hs[j * nx + i] = height_at(rect.position.x + i * step, rect.position.y + j * step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var x := rect.position.x + i * step
			var z := rect.position.y + j * step
			var h := hs[j * nx + i]
			var hx := hs[j * nx + mini(i + 1, nx - 1)] - hs[j * nx + maxi(i - 1, 0)]
			var hz := hs[mini(j + 1, nz - 1) * nx + i] - hs[maxi(j - 1, 0) * nx + i]
			var n := Vector3(-hx, 2.0 * step, -hz).normalized()
			st.set_normal(n)
			st.set_color(color_fn.call(x, z, h, n))
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, h, z))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + nx)
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	# 碰撞：高度场（每格 step 米）
	var body := StaticBody3D.new()
	body.name = name_ + "Body"
	body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.TERRAIN
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = hs
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, 1.0, step)
	cs.position = Vector3(rect.position.x + (nx - 1) * step * 0.5, 0.0, rect.position.y + (nz - 1) * step * 0.5)
	body.add_child(cs)
	add_child(body)
	return mi


## 地形材质：ArtMaterials 的 PBR 贴图（世界三平面投影）乘顶点色。
static func terrain_material(texture_id: String) -> StandardMaterial3D:
	var m := (ArtMaterials.pbr(texture_id, Color.WHITE, "world") as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


## 一个带碰撞的盒子（桥板、台阶、栏杆）。
func solid_box(parent: Node3D, size: Vector3, xform: Transform3D, mat: Material, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xform
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = PhysicsLayers.WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.transform = xform
		parent.add_child(body)
	return mi


## 一座木板桥（from → to，两端在桥面高度），两侧绳栏（有碰撞），桥面下垂一点。返回桥面采样点（测试走桥用）。
func plank_bridge(from: Vector3, to: Vector3, width: float, sag: float, name_: String) -> PackedVector3Array:
	var g := Node3D.new()
	g.name = name_
	add_child(g)
	var plank := ArtMaterials.pbr("weathered_planks", Color(0.92, 0.8, 0.66), "world")
	var rope := ArtMaterials.flat(Color(0.62, 0.5, 0.34), 0.9)
	var post_mat := ArtMaterials.pbr("stained_pine", Color(0.6, 0.42, 0.3), "world")
	var length := Vector2(to.x - from.x, to.z - from.z).length()
	var n := maxi(int(length / 0.55), 2)
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var yaw := atan2(dir.x, dir.z)
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(from.lerp(to, t) + Vector3(0.0, -sag * 4.0 * t * (1.0 - t), 0.0))
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var seg := b - a
		var pitch := -atan2(seg.y, Vector2(seg.x, seg.z).length())
		var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
		solid_box(g, Vector3(width, 0.08, seg.length() + 0.04), Transform3D(basis, mid - Vector3(0.0, 0.04, 0.0)), plank)
	# 两侧扶绳（碰撞是一道 1 m 高的薄墙，人掉不下去）和每隔几米一根立柱
	for s: float in [-1.0, 1.0]:
		for i in n:
			var a := pts[i] + side * s * (width * 0.5 + 0.05)
			var b := pts[i + 1] + side * s * (width * 0.5 + 0.05)
			var mid := (a + b) * 0.5 + Vector3(0.0, 0.95, 0.0)
			var seg := b - a
			var pitch := -atan2(seg.y, Vector2(seg.x, seg.z).length())
			var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
			solid_box(g, Vector3(0.05, 0.05, seg.length() + 0.02), Transform3D(basis, mid), rope, false)
			var wall := StaticBody3D.new()
			wall.collision_layer = PhysicsLayers.WORLD
			wall.collision_mask = 0
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.1, 1.2, seg.length() + 0.05)
			cs.shape = shape
			wall.add_child(cs)
			wall.transform = Transform3D(basis, (a + b) * 0.5 + Vector3(0.0, 0.6, 0.0))
			g.add_child(wall)
		for i in range(0, n + 1, 4):
			var p := pts[i] + side * s * (width * 0.5 + 0.05)
			solid_box(g, Vector3(0.1, 1.1, 0.1), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.0, 0.5, 0.0)), post_mat, false)
	return pts


# ---------------------------------------------------------------- 卷轴、光门、收集品、探索点

func _build_signs() -> void:
	for s: Dictionary in data.get("signs", []):
		var sign := SignBoard.create(str(s["text"]), str(s.get("style", "stand")), float(s.get("width", 1.4)), float(s.get("scale", 1.4)))
		var p: Array = s["pos"]
		var pos := Vector3(float(p[0]), 0.0, float(p[1]))
		pos.y = float(p[2]) if p.size() > 2 else height_at(pos.x, pos.z)
		sign.position = pos
		sign.rotation.y = deg_to_rad(float(s.get("yaw_deg", 0.0)))
		add_child(sign)


func _build_gate() -> void:
	var g: Dictionary = data.get("gate", {})
	if g.is_empty():
		return
	var gate := Node3D.new()
	gate.name = "ReturnGate"
	gate.position = v3(g["pos"])
	gate.rotation.y = deg_to_rad(float(g.get("yaw_deg", 0.0)))
	add_child(gate)
	var stone := ArtMaterials.pbr(str(g.get("stone", "rock_face_03")), _col(g.get("tint"), Color(0.66, 0.62, 0.7)), "world")
	for i in 18:
		var a := float(i) / 18.0 * TAU
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.75, 0.6)
		mi.mesh = bm
		mi.material_override = stone
		mi.transform = Transform3D(Basis(Vector3.FORWARD, a), Vector3(cos(a) * 1.7, 1.95 + sin(a) * 1.7, 0.0))
		gate.add_child(mi)
	for sx: float in [-1.0, 1.0]:
		solid_box(gate, Vector3(0.7, 0.5, 0.8), Transform3D(Basis(), Vector3(sx * 1.75, 0.25, 0.0)), stone)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0)
	face.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	face.material_override = mat
	face.position = Vector3(0.0, 1.95, 0.0)
	gate.add_child(face)
	portal = FairyPortal.create(StringName(world_id + "_return"), str(g.get("to", "dusk_lake")), Vector2(2.6, 2.6))
	portal.position = Vector3(0.0, 1.95, 0.0)
	gate.add_child(portal)


func _build_items() -> void:
	var glow := ArtMaterials.glow(_col(data.get("item_color"), Color(0.6, 0.9, 1.0)), 2.6)
	var shell := ArtMaterials.flat(_col(data.get("item_shell"), Color(0.95, 0.95, 1.0)), 0.2)
	for it: Dictionary in data.get("items", []):
		var root := Node3D.new()
		root.name = "Item_" + str(it["id"])
		root.add_to_group("collectibles")
		var p: Array = it["pos"]
		var pos := Vector3(float(p[0]), 0.0, float(p[1]))
		pos.y = (float(p[2]) if p.size() > 2 else height_at(pos.x, pos.z)) + 0.9
		root.position = pos
		add_child(root)
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.radial_segments = 16
		sm.rings = 8
		if str(data.get("item_shape", "pearl")) == "shard":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.3, 0.55, 0.16)
			core.mesh = pm
		else:
			core.mesh = sm
		core.material_override = glow
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(core)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.34
		tm.outer_radius = 0.4
		ring.mesh = tm
		ring.material_override = shell
		ring.rotation.x = PI * 0.5
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		items.append({"id": str(it["id"]), "node": root, "pos": pos})
	refresh()


## 收集品显示与否：已经捡过、或这一局关掉了收集品，就不显示。
func refresh() -> void:
	var got := WorldState.collected(world_id)
	var on := GameRules.flag("collectibles")
	for it in items:
		(it["node"] as Node3D).visible = on and not str(it["id"]) in got


func items_total() -> int:
	return items.size()


## 捡起一件（走近自动调用；测试也直接调用）。
func pick(item_id: String) -> bool:
	if not GameRules.flag("collectibles") or not WorldState.collect(world_id, item_id):
		return false
	for it in items:
		if str(it["id"]) == item_id:
			var n := it["node"] as Node3D
			var tw := n.create_tween()
			tw.tween_property(n, "scale", Vector3.ONE * 1.6, 0.15)
			tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.25)
			tw.tween_callback(n.hide)
	var got := WorldState.collected(world_id).size()
	EventBus.toast_requested.emit(tr("捡到%s（%d / %d）") % [tr(str(data.get("item_name", "收集品"))), got, items.size()])
	on_collected(item_id, got)
	SaveManager.request_save()
	return true


## 子类：捡到第 n 件时（例如集齐后的奖励）。
func on_collected(_item_id: String, _count: int) -> void:
	pass


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for it in items:
		var n := it["node"] as Node3D
		if n.visible:
			n.rotation.y = t * 1.4
			n.position.y = (it["pos"] as Vector3).y + sin(t * 2.0 + n.position.x) * 0.12
	_poi_timer -= delta
	if _poi_timer > 0.0 or player == null:
		return
	_poi_timer = 0.25
	var me := player.global_position
	for it in items:
		var n := it["node"] as Node3D
		if n.visible and me.distance_to(it["pos"]) < PICKUP_RADIUS + 0.9:
			pick(str(it["id"]))
	var pois: Array = data.get("pois", [])
	for poi: Dictionary in pois:
		if Vector2(me.x, me.z).distance_to(v2(poi["center"])) <= float(poi["radius"]) and WorldState.discover(StringName(poi["id"])):
			var found := 0
			for q: Dictionary in pois:
				if StringName(q["id"]) in WorldState.discoveries:
					found += 1
			EventBus.toast_requested.emit(tr("发现：%s（%d / %d）") % [_poi_label(poi), found, pois.size()])
			SaveManager.request_save()


static func _poi_label(poi: Dictionary) -> String:
	if TranslationServer.get_locale().begins_with("en") and str(poi.get("name_en", "")) != "":
		return str(poi["name_en"])
	return "%s %s" % [poi["name"], poi.get("name_en", "")]


# ---------------------------------------------------------------- 玩家

func _spawn_player() -> void:
	player = (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as FirstPersonController
	add_child(player)
	var a := WorldTravel.arrival()
	place_player(player, {} if a.is_empty() else {"arrival": a})


## spot：{} = 光门前（默认出生点）；{"id": 出生点 id}；{"arrival": {pos, heading}}；{"pos": [...], "heading"}。
func place_player(p: FirstPersonController, spot: Dictionary) -> void:
	var pos := Vector3.ZERO
	var heading := 0.0
	var def: Dictionary = data.get("spawn", {})
	if spot.has("id"):
		for s: Dictionary in data.get("spawns", []):
			if str(s["id"]) == str(spot["id"]):
				def = s
	elif spot.has("arrival"):
		def = spot["arrival"]
	elif spot.has("pos"):
		def = spot
	if def.has("pos"):
		var a: Array = def["pos"]
		pos = Vector3(float(a[0]), 0.0, float(a[a.size() - 1]))
		pos.y = float(a[1]) if a.size() == 3 else height_at(pos.x, pos.z)
		heading = float(def.get("heading", 0.0))
	if not is_finite(pos.y) or pos.y < -1e6:
		pos.y = 0.0
	p.teleport_to(pos + Vector3(0.0, 0.15, 0.0), heading)
	safe_spot = pos + Vector3(0.0, 0.15, 0.0)


func _physics_process(delta: float) -> void:
	if player == null or _respawning:
		return
	var p := player.global_position
	if p.y < float(data.get("void_y", -40.0)) or not map_rect().grow(40.0).has_point(Vector2(p.x, p.z)):
		_fall_back()
		return
	_safe_timer -= delta
	if _safe_timer <= 0.0:
		_safe_timer = 0.5
		if player.is_on_floor() and not player.swimming and not player.flying:
			safe_spot = p


## 掉出世界：黑幕一闪，回到最后站稳的地方。
func _fall_back() -> void:
	_respawning = true
	falls += 1
	await Fade.fade_out(0.25, tr("被风托回了岸上"))
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		player.teleport_to(safe_spot + Vector3(0.0, 0.1, 0.0))
	Fade.fade_in(0.6)
	_respawning = false


# ---------------------------------------------------------------- 界面

func _build_ui() -> void:
	add_child((load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate())
	add_child((load("res://scenes/ui/PauseMenu.tscn") as PackedScene).instantiate())
	for item: Array in [["Minimap", Minimap], ["WorldMap", WorldMap], ["CompassBar", CompassBar], ["JournalPanel", JournalPanel],
			["ChatBox", ChatBox], ["ActionBar", ActionBar], ["Performance", PerformanceDirector], ["UnderwaterOverlay", preload("res://scripts/ui/UnderwaterOverlay.gd")]]:
		var n: Node = (item[1] as GDScript).new()
		n.name = item[0]
		add_child(n)
