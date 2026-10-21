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

var _phase := 0.0
var _swing := 0.0
## 姿势："stand" 站立 / 走跑；"sit" 坐着（双腿向前平伸，手放膝上）；"paddle" 坐着划桨（双手前伸、随桨摆动）；
## "ground_sit" 席地而坐（腿前伸、双手撑在身后）；"lie" 躺平（四肢伸直，整体由控制器放倒）。
var pose := "stand"
var paddle_phase := 0.0
## 站立时叠加的手势：""、"wave" 挥手、"clap" 鼓掌、"dance" 跳舞（走动时自动淡出）。
var gesture := ""
var _gesture_t := 0.0


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


## 把一组像素盒子合成一个网格（顶点色 = 颜色键对应的颜色），画风与小动物一致（BlockyMesh）。
func _build_mesh(pieces: Array) -> ArrayMesh:
	return BlockyMesh.build(pieces, _resolve_color, Wardrobe.px())


func _resolve_color(key: String) -> Color:
	if key.begins_with("#"):
		return Color.html(key)
	return appearance.color(key)

func _apply_layers() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = render_layers


## 每帧由角色控制器调用：speed 为水平速度（m/s），look_pitch 为抬头角（弧度）。
func animate(delta: float, speed: float, on_floor: bool, look_pitch: float, run_speed := 5.2) -> void:
	if parts.is_empty():
		return
	if pose == "lie":
		_animate_lying()
		return
	if pose != "stand":
		_animate_seated(look_pitch)
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
	(parts["head"] as Node3D).rotation.z = 0.0
	if gesture != "":
		_gesture_t += delta
		_animate_gesture(1.0 - _swing)


## 手势叠加在站姿上：weight 随走动减弱（走起来就自然放下手）。
func _animate_gesture(weight: float) -> void:
	var t := _gesture_t
	var arm_r := parts["arm_r"] as Node3D
	var arm_l := parts["arm_l"] as Node3D
	match gesture:
		"wave":
			arm_r.rotation = arm_r.rotation.lerp(Vector3(0.0, 0.0, deg_to_rad(150.0 + sin(t * 9.0) * 22.0)), weight)
		"clap":
			var inward := deg_to_rad(16.0 + sin(t * 14.0) * 8.0)
			arm_r.rotation = arm_r.rotation.lerp(Vector3(deg_to_rad(80.0), inward, 0.0), weight)
			arm_l.rotation = arm_l.rotation.lerp(Vector3(deg_to_rad(80.0), -inward, 0.0), weight)
		"dance":
			var s := sin(t * 7.0)
			arm_r.rotation = arm_r.rotation.lerp(Vector3(0.0, 0.0, deg_to_rad(110.0 + s * 45.0)), weight)
			arm_l.rotation = arm_l.rotation.lerp(Vector3(0.0, 0.0, deg_to_rad(-110.0 + s * 45.0)), weight)
			(parts["leg_r"] as Node3D).rotation.x = lerpf((parts["leg_r"] as Node3D).rotation.x, deg_to_rad(maxf(s, 0.0) * 30.0), weight)
			(parts["leg_l"] as Node3D).rotation.x = lerpf((parts["leg_l"] as Node3D).rotation.x, deg_to_rad(maxf(-s, 0.0) * 30.0), weight)
			(parts["head"] as Node3D).rotation.z = deg_to_rad(s * 10.0) * weight


func set_gesture(id: String) -> void:
	gesture = id
	_gesture_t = 0.0


## 躺平：四肢伸直贴身，头放正（整体放倒与抬高由控制器设置本节点的旋转和位置）。
func _animate_lying() -> void:
	_swing = 0.0
	for leg in ["leg_r", "leg_l"]:
		(parts[leg] as Node3D).rotation = Vector3.ZERO
	(parts["arm_r"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(8.0))
	(parts["arm_l"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(-8.0))
	(parts["head"] as Node3D).rotation = Vector3.ZERO


func _animate_seated(look_pitch: float) -> void:
	_swing = 0.0
	(parts["leg_r"] as Node3D).rotation = Vector3(deg_to_rad(88.0), 0.0, deg_to_rad(-4.0))
	(parts["leg_l"] as Node3D).rotation = Vector3(deg_to_rad(88.0), 0.0, deg_to_rad(4.0))
	if pose == "ground_sit":
		# 双手撑在身后的地上
		(parts["arm_r"] as Node3D).rotation = Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(12.0))
		(parts["arm_l"] as Node3D).rotation = Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(-12.0))
	elif pose == "paddle":
		var s := sin(paddle_phase)
		(parts["arm_r"] as Node3D).rotation = Vector3(deg_to_rad(62.0 + 22.0 * s), deg_to_rad(-12.0), deg_to_rad(8.0))
		(parts["arm_l"] as Node3D).rotation = Vector3(deg_to_rad(62.0 - 22.0 * s), deg_to_rad(12.0), deg_to_rad(-8.0))
	else:
		(parts["arm_r"] as Node3D).rotation = Vector3(deg_to_rad(38.0), 0.0, deg_to_rad(4.0))
		(parts["arm_l"] as Node3D).rotation = Vector3(deg_to_rad(38.0), 0.0, deg_to_rad(-4.0))
	(parts["head"] as Node3D).rotation.x = clampf(look_pitch, deg_to_rad(-60.0), deg_to_rad(60.0))


## 当前腿部摆动角（测试读取）。
func leg_swing_degrees() -> float:
	if parts.is_empty():
		return 0.0
	return rad_to_deg(absf((parts["leg_r"] as Node3D).rotation.x))
