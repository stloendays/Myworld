class_name CompassBar
extends CanvasLayer
## 屏幕上方的罗盘条（本局规则“罗盘条”打开时显示）：朝向两侧各 90° 的刻度和东南西北，
## 附近 150 m 内的探索点（没发现的是问号，规则关掉问号时不显示）、收集品和光门的方向小标记，越远越淡。
## 下面一条体力条：本局开了“奔跑体力”或“游泳体力”，而且体力没满时才出现。
## 标记来自当前世界根节点的 map_markers()（湖畔 = 探索点；云海浮岛、琥珀沙丘 = 探索点 + 收集品 + 光门）。

const WIDTH := 640.0
const HEIGHT := 34.0
const SPAN_DEG := 180.0
const RANGE_M := 150.0
const INK := Color(0.97, 0.94, 0.86)

var _bar: Control
var _stamina: ProgressBar


func _ready() -> void:
	layer = 4
	add_to_group("compass_bar")
	_bar = Control.new()
	_bar.name = "Compass"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.offset_left = -WIDTH * 0.5
	_bar.offset_right = WIDTH * 0.5
	_bar.offset_top = 12.0
	_bar.offset_bottom = 12.0 + HEIGHT
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_stamina = ProgressBar.new()
	_stamina.name = "Stamina"
	_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina.show_percentage = false
	_stamina.max_value = 1.0
	_stamina.anchor_left = 0.5
	_stamina.anchor_right = 0.5
	_stamina.anchor_top = 1.0
	_stamina.anchor_bottom = 1.0
	_stamina.offset_left = -160.0
	_stamina.offset_right = 160.0
	_stamina.offset_top = -64.0
	_stamina.offset_bottom = -54.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.07, 0.6)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.85, 0.45)
	fill.set_corner_radius_all(4)
	_stamina.add_theme_stylebox_override("background", bg)
	_stamina.add_theme_stylebox_override("fill", fill)
	add_child(_stamina)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	_bar.visible = GameRules.flag("hud_compass") and player != null
	if _bar.visible:
		_bar.queue_redraw()
	var uses := GameRules.flag("stamina") or GameRules.flag("swim_stamina")
	_stamina.visible = uses and player != null and player.stamina < 0.999
	if _stamina.visible:
		_stamina.value = player.stamina
		var fill := _stamina.get_theme_stylebox("fill") as StyleBoxFlat
		fill.bg_color = Color(0.9, 0.4, 0.3) if player.exhausted else Color(0.55, 0.85, 0.45)


## 罗盘上的方位角（度，北 = 0，东 = 90）：世界 -Z 是北，+X 是东。
static func bearing(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


static func player_bearing(player: FirstPersonController) -> float:
	var f := -player.global_basis.z
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


## 当前世界的标记 [{pos: Vector2, kind: "poi" / "item" / "gate", done: bool, label}]。
static func world_markers(tree: SceneTree) -> Array:
	var root := tree.get_first_node_in_group("world_root")
	if root != null and root.has_method("map_markers"):
		return root.call("map_markers")
	return []


func _draw_bar() -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return
	var font := GameSettings.ui_theme().default_font
	var heading := player_bearing(player)
	_bar.draw_rect(Rect2(0.0, 0.0, WIDTH, HEIGHT), Color(0.05, 0.05, 0.07, 0.45))
	for step in range(0, 360, 15):
		var x := _x_for(float(step), heading)
		if x < 0.0:
			continue
		var major := step % 90 == 0
		var mid := step % 45 == 0
		_bar.draw_line(Vector2(x, HEIGHT - (14.0 if major else (9.0 if mid else 5.0))), Vector2(x, HEIGHT), Color(INK, 0.8), 1.5)
		if major or mid:
			var label: String = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"][step / 45]
			var text := tr(label)
			var size := 18 if major else 13
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var col := Color(1.0, 0.72, 0.45) if step == 0 else INK
			_bar.draw_string(font, Vector2(x - w * 0.5, 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	var me := Vector2(player.global_position.x, player.global_position.z)
	var show_unknown := GameRules.flag("poi_markers")
	for m: Dictionary in world_markers(get_tree()):
		var kind := str(m.get("kind", "poi"))
		var done := bool(m.get("done", false))
		if kind == "poi" and not done and not show_unknown:
			continue
		if kind == "item" and (done or not GameRules.flag("collectibles")):
			continue
		var p: Vector2 = m["pos"]
		var dist := me.distance_to(p)
		if dist > RANGE_M or dist < 2.0:
			continue
		var x := _x_for(bearing(me, p), heading)
		if x < 0.0:
			continue
		var a := clampf(1.2 - dist / RANGE_M, 0.35, 1.0)
		var y := HEIGHT + 8.0
		match kind:
			"item":
				_bar.draw_circle(Vector2(x, y), 4.5, Color(0.55, 0.9, 1.0, a))
			"gate":
				_bar.draw_arc(Vector2(x, y), 5.5, 0.0, TAU, 16, Color(0.85, 0.7, 1.0, a), 2.0)
			_:
				if done:
					_bar.draw_circle(Vector2(x, y), 4.5, Color(1.0, 0.82, 0.35, a))
				else:
					_bar.draw_string(font, Vector2(x - 4.0, y + 6.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.92, 0.92, a))
	_bar.draw_line(Vector2(WIDTH * 0.5, 0.0), Vector2(WIDTH * 0.5, HEIGHT), Color(1.0, 0.86, 0.55), 2.0)


## 方位角在条上的横坐标；不在视野两侧 90° 以内返回 -1。
func _x_for(b: float, heading: float) -> float:
	var d := wrapf(b - heading, -180.0, 180.0)
	if absf(d) > SPAN_DEG * 0.5:
		return -1.0
	return WIDTH * 0.5 + d / (SPAN_DEG * 0.5) * WIDTH * 0.5
