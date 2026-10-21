class_name WorldMap
extends CanvasLayer
## 世界地图（Tab 打开 / 关闭，Esc 也能关）：左边是整张暮色湖畔（北朝上），右边是世界总览与世界列表。
## 左图复用小地图烘焙的底图，叠加步道、码头、建筑、探索点（未发现显示问号）、独木舟和玩家箭头。
## 右侧的世界来自 data/worlds/worlds.json（WorldRegistry）：目前只有暮色湖畔开放，其他世界显示“规划中”，
## 以后加新世界只改 JSON 和对应场景。打开地图时鼠标放出，世界照常运行。

const PANEL_BG := Color(0.07, 0.08, 0.1, 0.92)
const INK := Color(0.96, 0.93, 0.86)
const MUTED := Color(0.72, 0.72, 0.74)

var open := false
var _root: Control
var _map: Control
var _atlas: Control
var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	layer = 15
	_build()
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map") or (open and event.is_action_pressed("pause")):
		_set_open(not open)
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_set_open(not open)


func _set_open(on: bool) -> void:
	open = on
	_root.visible = on
	if on:
		_refresh_list()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if open:
		_map.queue_redraw()


func _build() -> void:
	_root = Control.new()
	_root.name = "WorldMapRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	_root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", INK)
	outer.add_child(_title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 22)
	outer.add_child(row)
	_map = Control.new()
	_map.name = "Map"
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_stretch_ratio = 1.6
	_map.draw.connect(_draw_map)
	row.add_child(_map)
	var side := PanelContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	side.add_theme_stylebox_override("panel", sb)
	row.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	side.add_child(col)
	var head := Label.new()
	head.text = "世界总览"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", INK)
	col.add_child(head)
	_atlas = Control.new()
	_atlas.custom_minimum_size = Vector2(0.0, 220.0)
	_atlas.draw.connect(_draw_atlas)
	col.add_child(_atlas)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)
	var foot := Label.new()
	foot.text = "Tab / Esc 关闭"
	foot.add_theme_color_override("font_color", MUTED)
	foot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	foot.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(foot)


func _refresh_list() -> void:
	var cur := WorldRegistry.current()
	_title.text = "世界地图 · %s %s" % [cur.get("name", ""), cur.get("name_en", "")]
	for c in _list.get_children():
		c.queue_free()
	for w in WorldRegistry.worlds():
		var id := str(w["id"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var state := "当前所在" if id == WorldRegistry.current_id() else ("可前往" if WorldRegistry.is_open(id) else "规划中")
		b.text = "%s  %s  ·  %s" % [w["name"], w.get("name_en", ""), state]
		b.tooltip_text = str(w.get("summary", ""))
		b.pressed.connect(func() -> void: WorldRegistry.enter(id))
		_list.add_child(b)
		var s := Label.new()
		s.text = "    " + str(w.get("summary", ""))
		s.add_theme_color_override("font_color", MUTED)
		s.add_theme_font_size_override("font_size", 15)
		_list.add_child(s)
	_atlas.queue_redraw()


# ---------------------------------------------------------------- 本世界地图

## 世界 (x, z) → 地图控件像素：北朝上，正方形居中。
func world_to_panel() -> Transform2D:
	var e := WorldTerrain.extent()
	var side := minf(_map.size.x, _map.size.y)
	var origin := (_map.size - Vector2(side, side)) * 0.5
	var k := side / (e * 2.0)
	return Transform2D(0.0, Vector2(k, k), 0.0, origin + Vector2(e, e) * k)


func _draw_map() -> void:
	var t := world_to_panel()
	var e := WorldTerrain.extent()
	var rect := Rect2(-e, -e, e * 2.0, e * 2.0)
	var font := GameSettings.ui_theme().default_font
	var mm := get_tree().get_first_node_in_group("minimap") as Minimap
	_map.draw_set_transform_matrix(t)
	_map.draw_rect(rect, Color(0.14, 0.2, 0.14))
	if mm != null and mm.map_texture != null:
		_map.draw_texture_rect(mm.map_texture, rect, false)
	for pts in WorldLayout.path_polylines():
		_map.draw_polyline(pts, Minimap.PATH_COLOR, 1.6, true)
	var dock := WorldLayout.section("dock")
	if not dock.is_empty():
		_map.draw_line(WorldLayout.v2(dock["from"]), WorldLayout.v2(dock["to"]), Minimap.DOCK_COLOR, float(dock.get("width", 2.6)))
	_building(WorldLayout.section("cabin"), Vector2(Cabin.LENGTH + Cabin.DECK_DEPTH, Cabin.HALF_SPAN * 2.0), Vector2(Cabin.DECK_DEPTH * 0.5, 0.0), Color(0.62, 0.33, 0.22))
	_building(WorldLayout.section("poolhouse"), Vector2(PoolHouse.HX * 2.0, PoolHouse.HZ * 2.0), Vector2.ZERO, Color(0.55, 0.74, 0.84))
	_map.draw_set_transform_matrix(Transform2D.IDENTITY)
	_map.draw_rect(Rect2(t * rect.position, t.basis_xform(rect.size)), Color(0.08, 0.07, 0.06), false, 3.0)
	# 地名
	var lake := WorldLayout.section("lake")
	if not lake.is_empty():
		_label(font, t * WorldLayout.v2(lake["center"]) + Vector2(0.0, 40.0), "暮色湖", 20, Color(0.9, 0.96, 1.0))
	for item in [["cabin", "木屋"], ["poolhouse", "泳池馆"]]:
		var cfg := WorldLayout.section(item[0])
		if not cfg.is_empty():
			_label(font, t * WorldLayout.v2(cfg["center"]) + Vector2(0.0, -22.0), item[1], 17, INK)
	for poi in Exploration.pois():
		var p := t * WorldLayout.v2(poi["center"])
		if StringName(poi["id"]) in WorldState.discoveries:
			_map.draw_circle(p, 6.0, Color(1.0, 0.82, 0.35))
			_map.draw_arc(p, 6.0, 0.0, TAU, 24, Color(0.15, 0.1, 0.05), 1.4, true)
			_label(font, p + Vector2(0.0, 22.0), str(poi["name"]), 15, Color(1.0, 0.9, 0.65))
		else:
			_map.draw_circle(p, 8.0, Color(0.12, 0.12, 0.14, 0.8))
			_map.draw_string(font, p + Vector2(-4.5, 6.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.9))
	for v in get_tree().get_nodes_in_group("vehicles"):
		var canoe := v as Canoe
		if canoe != null and canoe.rider == null:
			_map.draw_circle(t * canoe.world_position_2d(), 4.0, Color(0.85, 0.3, 0.2))
	_draw_player(t)
	# 指北与比例尺（50 m）
	var corner := t * rect.position + Vector2(26.0, 30.0)
	_map.draw_circle(corner, 15.0, Color(0.1, 0.09, 0.08, 0.85))
	_map.draw_string(font, corner + Vector2(-6.5, 7.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1.0, 0.86, 0.55))
	var bar_len := t.basis_xform(Vector2(50.0, 0.0)).x
	var bar := t * Vector2(rect.end.x, rect.end.y) - Vector2(bar_len + 20.0, 22.0)
	_map.draw_line(bar, bar + Vector2(bar_len, 0.0), INK, 3.0)
	_map.draw_string(font, bar + Vector2(bar_len * 0.5 - 18.0, -8.0), "50 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)


func _draw_player(t: Transform2D) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return
	var c := t * Vector2(player.global_position.x, player.global_position.z)
	var arrow := PackedVector2Array([Vector2(0, -11), Vector2(8, 8), Vector2(0, 4), Vector2(-8, 8)])
	var pts := PackedVector2Array()
	for p in arrow:
		pts.append(c + p.rotated(-player.rotation.y))
	_map.draw_colored_polygon(pts, Color(1.0, 0.97, 0.9))
	pts.append(pts[0])
	_map.draw_polyline(pts, Color(0.1, 0.08, 0.06), 1.8, true)


func _building(cfg: Dictionary, size: Vector2, offset: Vector2, color: Color) -> void:
	if cfg.is_empty():
		return
	var c := WorldLayout.v2(cfg["center"])
	var yaw := -deg_to_rad(float(cfg.get("yaw_deg", 0.0)))
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(c + (offset + corner * size * 0.5).rotated(yaw))
	_map.draw_colored_polygon(pts, color)


func _label(font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := center - Vector2(w * 0.5, -size * 0.35)
	_map.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.0, 0.0, 0.0, 0.75))
	_map.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# ---------------------------------------------------------------- 世界总览

func _draw_atlas() -> void:
	var size := _atlas.size
	var font := GameSettings.ui_theme().default_font
	var pos := {}
	for w in WorldRegistry.worlds():
		var a: Array = w.get("atlas", [0.5, 0.5])
		pos[str(w["id"])] = Vector2(float(a[0]), float(a[1])) * size
	for link in WorldRegistry.links():
		var a: Vector2 = pos.get(str(link[0]), Vector2.ZERO)
		var b: Vector2 = pos.get(str(link[1]), Vector2.ZERO)
		_atlas.draw_dashed_line(a, b, Color(0.8, 0.78, 0.7, 0.6), 2.0, 8.0)
	for w in WorldRegistry.worlds():
		var id := str(w["id"])
		var p: Vector2 = pos[id]
		var open_world := WorldRegistry.is_open(id)
		var col := Color.html(str(w.get("color", "#cccccc")))
		if not open_world:
			col = col.darkened(0.45)
		_atlas.draw_circle(p, 26.0 if open_world else 20.0, col)
		if id == WorldRegistry.current_id():
			_atlas.draw_arc(p, 32.0, 0.0, TAU, 48, Color(1.0, 0.9, 0.6), 2.5, true)
		var label_text := str(w["name"])
		var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_atlas.draw_string(font, p + Vector2(-text_w * 0.5, 48.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK if open_world else MUTED)
		if not open_world:
			_atlas.draw_string(font, p + Vector2(-5.0, 7.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.9))
