@tool
class_name CharacterModel
extends Node3D
## 方块风格人物模型：头、躯干、双臂、双腿六个部位（每个部位一个转轴节点），身高 1.8 m、面朝 -Z。
## 外观完全由 CharacterAppearance + 衣橱目录（Wardrobe）决定：
##   每个部位下有 Base（皮肤）和七个插槽节点 face / hair / hat / top / bottom / shoes / back，
##   换发型、换衣服只替换对应插槽的网格；插槽节点一直存在，以后也可以直接挂 GLB 饰品。
## 另有挂点（socket）：hand_r、hand_l、head_top、back，用于手持物、帽饰、背包等。
## animate() 做简单的走跑摆臂摆腿、空中姿态和抬头低头，不需要骨骼动画。

const PART_ORDER := ["leg_r", "leg_l", "torso", "arm_r", "arm_l", "head"]
const SOCKETS := {
	"hand_r": ["arm_r", Vector3(0.0, -10.0, 0.0)],
	"hand_l": ["arm_l", Vector3(0.0, -10.0, 0.0)],
	"head_top": ["head", Vector3(0.0, 8.5, 0.0)],
	"back": ["torso", Vector3(0.0, 6.0, 2.5)],
}

## 为空时使用 PlayerProfile 的外观（本地玩家）；NPC / 其他玩家给自己的外观。
@export var appearance: CharacterAppearance = null:
	set(value):
		if appearance != null and appearance.changed.is_connected(rebuild):
			appearance.changed.disconnect(rebuild)
		appearance = value
		if appearance != null and is_inside_tree():
			appearance.changed.connect(rebuild)
			rebuild()
## 渲染层（第一人称时把自身放在 player_body 层，相机不画但仍投影子）。
@export_flags_3d_render var render_layers := 1:
	set(value):
		render_layers = value
		_apply_layers()

var parts: Dictionary = {}       ## 部位名 -> 转轴 Node3D
var sockets: Dictionary = {}     ## 挂点名 -> Node3D

var _material: StandardMaterial3D = null
var _phase := 0.0
var _swing := 0.0


func _ready() -> void:
	if appearance == null and not Engine.is_editor_hint():
		appearance = PlayerProfile.appearance
	elif appearance == null:
		appearance = CharacterAppearance.from_file("res://data/characters/default_appearance.json")
	else:
		appearance = appearance


func get_socket(socket_name: String) -> Node3D:
	return sockets.get(socket_name)


func slot_node(part: String, slot: String) -> Node3D:
	var p: Node3D = parts.get(part)
	return p.get_node_or_null(slot) if p != null else null


func rebuild() -> void:
	if appearance == null:
		return
	_ensure_skeleton()
	var buckets := {}   # part -> slot -> Array[piece]
	for part in PART_ORDER:
		buckets[part] = {"Base": []}
		for slot in Wardrobe.slot_order():
			buckets[part][slot] = []
	for piece in Wardrobe.body():
		_sort_piece(buckets, piece, "Base")
	for slot in Wardrobe.slot_order():
		for piece in Wardrobe.pieces(slot, appearance.style(slot)):
			_sort_piece(buckets, piece, slot)
	for part in PART_ORDER:
		for slot in buckets[part]:
			var holder := parts[part].get_node(String(slot)) as Node3D
			var mi := holder.get_node_or_null("Mesh") as MeshInstance3D
			var list: Array = buckets[part][slot]
			if list.is_empty():
				if mi != null:
					mi.mesh = null
				continue
			if mi == null:
				mi = MeshInstance3D.new()
				mi.name = "Mesh"
				holder.add_child(mi)
			mi.mesh = _build_mesh(list)
			mi.layers = render_layers
	_apply_layers()


func _sort_piece(buckets: Dictionary, piece: Dictionary, slot: String) -> void:
	var targets: Array = piece["part"] if piece["part"] is Array else [piece["part"]]
	for part in targets:
		if buckets.has(part):
			buckets[part][slot].append(piece)


func _ensure_skeleton() -> void:
	if not parts.is_empty():
		return
	var px := Wardrobe.px()
	var defs := Wardrobe.parts()
	for part in PART_ORDER:
		var pivot := Node3D.new()
		pivot.name = part
		var p: Array = defs[part]["pivot"]
		pivot.position = Vector3(float(p[0]), float(p[1]), float(p[2])) * px
		add_child(pivot)
		var base := Node3D.new()
		base.name = "Base"
		pivot.add_child(base)
		for slot in Wardrobe.slot_order():
			var holder := Node3D.new()
			holder.name = slot
			pivot.add_child(holder)
		parts[part] = pivot
	for socket_name in SOCKETS:
		var s := Node3D.new()
		s.name = "Socket_" + socket_name
		s.position = (SOCKETS[socket_name][1] as Vector3) * px
		(parts[SOCKETS[socket_name][0]] as Node3D).add_child(s)
		sockets[socket_name] = s


## 把一组像素盒子合成一个网格（顶点色 = 颜色键对应的颜色）。
func _build_mesh(pieces: Array) -> ArrayMesh:
	var px := Wardrobe.px()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in pieces:
		var b: Array = piece["box"]
		var lo := Vector3(float(b[0]), float(b[1]), float(b[2])) * px
		var hi := Vector3(float(b[3]), float(b[4]), float(b[5])) * px
		_add_box(st, lo, hi, _resolve_color(str(piece["color"])))
	var mesh := st.commit()
	mesh.surface_set_material(0, _shared_material())
	return mesh


func _resolve_color(key: String) -> Color:
	if key.begins_with("#"):
		return Color.html(key)
	return appearance.color(key)


static func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3, color: Color) -> void:
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [
		[[0, 3, 2, 1], Vector3.FORWARD], [[4, 5, 6, 7], Vector3.BACK],
		[[0, 4, 7, 3], Vector3.LEFT], [[1, 2, 6, 5], Vector3.RIGHT],
		[[3, 7, 6, 2], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN],
	]
	st.set_color(color)
	for f in faces:
		var q: Array = f[0]
		var n: Vector3 = f[1]
		MeshUtil.add_tri(st, c[q[0]], c[q[1]], c[q[2]], n)
		MeshUtil.add_tri(st, c[q[0]], c[q[2]], c[q[3]], n)


## 共用材质：顶点色 × 16×16 像素噪点贴图（最近邻采样，1 个贴图像素 = 1 个模型像素），呈现方块像素质感。
func _shared_material() -> StandardMaterial3D:
	if _material == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1717
		for y in 16:
			for x in 16:
				var v := rng.randf_range(0.86, 1.0)
				img.set_pixel(x, y, Color(v, v, v))
		_material = StandardMaterial3D.new()
		_material.albedo_texture = ImageTexture.create_from_image(img)
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_material.uv1_triplanar = true
		_material.uv1_scale = Vector3.ONE / (16.0 * Wardrobe.px())
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.9
	return _material


func _apply_layers() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = render_layers


## 每帧由角色控制器调用：speed 为水平速度（m/s），look_pitch 为抬头角（弧度）。
func animate(delta: float, speed: float, on_floor: bool, look_pitch: float, run_speed := 5.2) -> void:
	if parts.is_empty():
		return
	var target := clampf(speed / run_speed, 0.0, 1.0) if on_floor else 0.0
	_swing = lerpf(_swing, target, 1.0 - exp(-10.0 * delta))
	_phase += delta * speed * 2.4
	var amp := deg_to_rad(lerpf(0.0, 55.0, _swing))
	var s := sin(_phase) * amp
	(parts["leg_r"] as Node3D).rotation.x = s
	(parts["leg_l"] as Node3D).rotation.x = -s
	var arm_lift := 0.0 if on_floor else deg_to_rad(-35.0)
	var idle := sin(Time.get_ticks_msec() * 0.0021) * deg_to_rad(2.0) * (1.0 - _swing)
	(parts["arm_r"] as Node3D).rotation = Vector3(-s * 0.85 + arm_lift, 0.0, deg_to_rad(3.0) + idle)
	(parts["arm_l"] as Node3D).rotation = Vector3(s * 0.85 + arm_lift, 0.0, -deg_to_rad(3.0) - idle)
	(parts["head"] as Node3D).rotation.x = clampf(look_pitch, deg_to_rad(-60.0), deg_to_rad(60.0))


## 当前腿部摆动角（测试读取）。
func leg_swing_degrees() -> float:
	if parts.is_empty():
		return 0.0
	return rad_to_deg(absf((parts["leg_r"] as Node3D).rotation.x))
