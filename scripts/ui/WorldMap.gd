class_name WorldMap
extends CanvasLayer
## 世界地图（Tab 打开 / 关闭，Esc 也能关）：左边是整张暮色湖畔（北朝上），右边是世界总览与世界列表。
## 左图复用小地图烘焙的底图，叠加步道、码头、建筑、探索点（未发现显示问号）、独木舟和玩家箭头。
## 右侧的世界来自 data/worlds/worlds.json（WorldRegistry）：目前只有暮色湖畔开放，其他世界显示“规划中”，
## 以后加新世界只改 JSON 和对应场景。打开地图时鼠标放出，世界照常运行。


var open := false
var _root: Control
var _map: Control
var _atlas: Control
var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	add_to_group(UiStyle.COVER_GROUP)
	layer = 15
	_build()
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map") or (open and event.is_action_pressed("pause")):
		_set_open(not open)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return open


func toggle() -> void:
	_set_open(not open)


func _set_open(on: bool) -> void:
	open = on
	_root.visible = on
	if on:
		_refresh_list()
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if open:
		_map.queue_redraw()
		_atlas.queue_redraw()   # 现在所在的世界外圈在呼吸


func _build() -> void:
	_root = Control.new()
	_root.name = "WorldMapRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(UiStyle.DIM, 0.8)
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
	_title = UiStyle.title("", 30)
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
	side.add_theme_stylebox_override("panel", UiStyle.panel(0.94, 22))
	row.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	side.add_child(col)
	var head := UiStyle.title("世界总览", 24)
	col.add_child(head)
	_atlas = Control.new()
	_atlas.custom_minimum_size = Vector2(0.0, 250.0)
	_atlas.draw.connect(_draw_atlas)
	col.add_child(_atlas)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)
	var foot := Label.new()
	foot.text = "Tab / Esc 关闭"
	foot.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	foot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	foot.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(foot)


func _refresh_list() -> void:
	var cur := WorldRegistry.current()
	_title.text = tr("世界地图 · %s") % tr(str(cur.get("name", "")))
	for c in _list.get_children():
		c.queue_free()
	for w in WorldRegistry.worlds():
		var id := str(w["id"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var state := "当前所在" if id == WorldRegistry.current_id() else ("可前往" if WorldRegistry.is_open(id) else "规划中")
		b.text = "%s  ·  %s" % [tr(str(w["name"])), tr(state)]
		b.tooltip_text = tr(str(w.get("summary", "")))
		b.pressed.connect(func() -> void: WorldRegistry.enter(id))
		if id == WorldRegistry.current_id():
			b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.HOVER, 0.9), 10, Color(UiStyle.ACCENT, 0.7), 1, Vector4(16, 9, 16, 9)))
			b.add_theme_color_override("font_color", UiStyle.ACCENT)
		_list.add_child(b)
		var s := Label.new()
		s.text = "    " + tr(str(w.get("summary", "")))
		s.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		s.add_theme_font_size_override("font_size", 15)
		_list.add_child(s)
	_atlas.queue_redraw()


# ---------------------------------------------------------------- 本世界地图

## 世界 (x, z) → 地图控件像素：北朝上，正方形居中。
func world_to_panel() -> Transform2D:
	var rect := _rect()
	var span := maxf(rect.size.x, rect.size.y)
	var side := minf(_map.size.x, _map.size.y)
	var k := side / span
	var origin := (_map.size - rect.size * k) * 0.5
	return Transform2D(0.0, Vector2(k, k), 0.0, origin - rect.position * k)


## 当前世界的地图范围：湖畔是整块地形，其他世界按它们的数据文件。
func _rect() -> Rect2:
	var w := _mini()
	if w != null:
		return w.map_rect()
	var e := WorldTerrain.extent()
	return Rect2(-e, -e, e * 2.0, e * 2.0)


func _mini() -> MiniWorld:
	return get_tree().get_first_node_in_group("world_root") as MiniWorld


func _draw_map() -> void:
	var t := world_to_panel()
	var rect := _rect()
	var font := GameSettings.ui_theme().default_font
	var screen := Rect2(t * rect.position, t.basis_xform(rect.size))
	if _mini() != null:
		_draw_mini_world(t, rect, font)
		return
	var mm := get_tree().get_first_node_in_group("minimap") as Minimap
	_map.draw_rect(screen.grow(12.0), Color(0.05, 0.04, 0.035, 0.6))
	_map.draw_set_transform_matrix(t)
	_map.draw_rect(rect, Color(0.32, 0.36, 0.24))
	if mm != null and mm.map_texture != null:
		_map.draw_texture_rect(mm.map_texture, rect, false)
	MapArt.draw_channels(_map)
	for pts in WorldLayout.path_polylines():
		MapArt.draw_path(_map, pts, 1.8)
	var dock := WorldLayout.section("dock")
	if not dock.is_empty():
		var a := WorldLayout.v2(dock["from"])
		var b := WorldLayout.v2(dock["to"])
		var wd := float(dock.get("width", 2.6))
		_map.draw_line(a, b, MapArt.INK, wd + 1.0)
		_map.draw_line(a, b, Minimap.DOCK_COLOR, wd)
	# 图腾山洞：沿洞道一条岩石带
	var cave := WorldLayout.section("cave")
	if not cave.is_empty():
		var line := PackedVector2Array()
		for p: Array in cave["centerline"]:
			line.append(Vector2(float(p[0]), float(p[1])))
		_map.draw_polyline(line, Color(0.45, 0.41, 0.36), 7.0, true)
		_map.draw_polyline(line, Color(0.12, 0.1, 0.08), 3.0, true)
	var glade := get_tree().get_first_node_in_group("fairy_glade") as FairyGlade
	if glade != null and glade.active:
		var gc := Vector2(glade.position.x, glade.position.z)
		_map.draw_circle(gc, glade.radius * 1.15, Color(0.86, 0.66, 1.0, 0.18))
		_map.draw_circle(gc, glade.radius, Color(0.86, 0.66, 1.0, 0.4))
	_map.draw_set_transform_matrix(Transform2D.IDENTITY)
	# 建筑：带投影的图标
	_building(t, WorldLayout.section("cabin"), Vector2(Cabin.LENGTH + Cabin.DECK_DEPTH, Cabin.HALF_SPAN * 2.0), Vector2(Cabin.DECK_DEPTH * 0.5, 0.0), Color(0.66, 0.36, 0.24))
	var pool := _building(t, WorldLayout.section("poolhouse"), Vector2(PoolHouse.HX * 2.0, PoolHouse.HZ * 2.0), Vector2.ZERO, Color(0.80, 0.86, 0.88), false)
	if pool.size() == 4:
		# 馆里的泳池：一块蓝
		var inner := PackedVector2Array()
		for q in pool:
			inner.append(q.lerp((pool[0] + pool[2]) * 0.5, 0.45))
		_map.draw_colored_polygon(inner, Color(0.36, 0.68, 0.86))
	_building(t, WorldLayout.section("cottage"), Vector2(StoneCottage.SIZE.x, StoneCottage.SIZE.z), Vector2.ZERO, Color(0.66, 0.64, 0.60))
	MapArt.draw_frame(_map, screen)
	# 地名
	var lake := WorldLayout.section("lake")
	if not lake.is_empty():
		MapArt.label(_map, font, t * WorldLayout.v2(lake["center"]) + Vector2(0.0, 40.0), tr("暮色湖"), 22, Color(0.88, 0.96, 1.0))
	for item in [["cabin", "木屋"], ["poolhouse", "泳池馆"], ["fairy_glade", "仙境林地"], ["snow_peak", "雪山"], ["cave", "图腾山洞"], ["cottage", "石头小屋"]]:
		var cfg := WorldLayout.section(item[0])
		if item[0] == "fairy_glade" and (glade == null or not glade.active):
			continue
		if not cfg.is_empty():
			MapArt.label(_map, font, t * WorldLayout.v2(cfg["center"]) + Vector2(0.0, -24.0), tr(item[1]), 17)
	# 光门、探索点、独木舟
	var root := get_tree().get_first_node_in_group("world_root")
	if root != null and root.has_method("map_markers"):
		for m: Dictionary in root.call("map_markers"):
			if str(m["kind"]) == "gate":
				var gp := t * (m["pos"] as Vector2)
				MapArt.draw_gate(_map, gp)
				MapArt.label(_map, font, gp + Vector2(0.0, 24.0), tr(str(m["label"])), 14, Color(0.92, 0.85, 1.0))
	for poi in Exploration.pois():
		var p := t * WorldLayout.v2(poi["center"])
		var found := StringName(poi["id"]) in WorldState.discoveries
		if found:
			MapArt.draw_pin(_map, p, true, font)
			MapArt.label(_map, font, p + Vector2(0.0, 16.0), tr(str(poi["name"])), 14, Color(1.0, 0.9, 0.66))
		elif GameRules.flag("poi_markers"):
			MapArt.draw_pin(_map, p, false, font)
	for v in get_tree().get_nodes_in_group("vehicles"):
		var canoe := v as Canoe
		if canoe != null and canoe.rider == null:
			var cp := t * canoe.world_position_2d()
			var fwd := Vector2(-sin(canoe.heading), -cos(canoe.heading))
			var side := Vector2(-fwd.y, fwd.x)
			_map.draw_colored_polygon(PackedVector2Array([cp + fwd * 9.0, cp + side * 3.2, cp - fwd * 9.0, cp - side * 3.2]), Color(0.86, 0.3, 0.2))
	_draw_player(t)
	_draw_north_and_scale(t, rect, font)


## 八角指北针（左上角）和分段比例尺（右下角，50 m）。
func _draw_north_and_scale(t: Transform2D, rect: Rect2, font: Font) -> void:
	MapArt.draw_compass(_map, t * rect.position + Vector2(42.0, 48.0), 22.0, font)
	var px_per_m := t.basis_xform(Vector2(1.0, 0.0)).x
	MapArt.draw_scale_bar(_map, t * rect.end - Vector2(50.0 * px_per_m + 52.0, 26.0), px_per_m, font)


func _draw_player(t: Transform2D) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return
	var c := t * Vector2(player.global_position.x, player.global_position.z)
	MapArt.draw_player(_map, c, -player.rotation.y, Time.get_ticks_msec() / 1000.0, t.basis_xform(Vector2(18.0, 0.0)).x)


## 建筑图标（世界坐标的布局 → 画面），返回画面上的四个角。
func _building(t: Transform2D, cfg: Dictionary, size: Vector2, offset: Vector2, color: Color, ridge := true) -> PackedVector2Array:
	if cfg.is_empty():
		return PackedVector2Array()
	var c := WorldLayout.v2(cfg["center"])
	var yaw := -deg_to_rad(float(cfg.get("yaw_deg", 0.0)))
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(t * (c + (offset + corner * size * 0.5).rotated(yaw)))
	MapArt.draw_building(_map, pts, color, ridge)
	return pts


# ---------------------------------------------------------------- 世界总览

## 世界总览：每个世界一颗发光的球，开放的世界之间用虚线连起来，现在所在的那颗外面一圈金环。
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
		_atlas.draw_dashed_line(a, b, Color(UiStyle.ACCENT, 0.45), 2.0, 7.0)
	var t := Time.get_ticks_msec() / 1000.0
	for w in WorldRegistry.worlds():
		var id := str(w["id"])
		var p: Vector2 = pos[id]
		var open_world := WorldRegistry.is_open(id)
		var col := Color.html(str(w.get("color", "#cccccc")))
		if not open_world:
			col = col.darkened(0.55)
		var r := 25.0 if open_world else 19.0
		for k in 4:
			_atlas.draw_circle(p, r + 14.0 - k * 4.0, Color(col, 0.05 + k * 0.03))
		_atlas.draw_circle(p, r, col.darkened(0.25))
		_atlas.draw_circle(p + Vector2(-r * 0.12, -r * 0.12), r * 0.82, col)
		_atlas.draw_circle(p + Vector2(-r * 0.35, -r * 0.38), r * 0.28, Color(1, 1, 1, 0.35))
		_atlas.draw_arc(p, r, 0.0, TAU, 48, Color(0, 0, 0, 0.35), 1.2, true)
		if id == WorldRegistry.current_id():
			var pulse := 0.5 + 0.5 * sin(t * 2.5)
			_atlas.draw_arc(p, r + 7.0 + pulse * 2.0, 0.0, TAU, 56, Color(UiStyle.ACCENT, 0.9), 2.5, true)
		MapArt.label(_atlas, font, p + Vector2(0.0, r + 22.0), tr(str(w["name"])), 15, UiStyle.TEXT if open_world else UiStyle.TEXT_DIM)
		if not open_world:
			MapArt.label(_atlas, font, p, "?", 20, Color(0.9, 0.9, 0.9))


## 云海浮岛、琥珀沙丘、亚特兰蒂斯：底图、桥和建筑（世界自己画）、地名、探索点、收集品、光门、玩家。
func _draw_mini_world(t: Transform2D, rect: Rect2, font: Font) -> void:
	var w := _mini()
	var screen := Rect2(t * rect.position, t.basis_xform(rect.size))
	_map.draw_rect(screen.grow(12.0), Color(0.05, 0.04, 0.035, 0.6))
	_map.draw_set_transform_matrix(t)
	_map.draw_rect(rect, Color(0.2, 0.2, 0.24))
	if w.map_texture != null:
		_map.draw_texture_rect(w.map_texture, rect, false)
	w.draw_map(_map)
	_map.draw_set_transform_matrix(Transform2D.IDENTITY)
	MapArt.draw_frame(_map, screen)
	for l: Dictionary in w.map_labels():
		MapArt.label(_map, font, t * (l["pos"] as Vector2), tr(str(l["text"])), 18)
	var pois: Dictionary = {}
	for poi: Dictionary in w.data.get("pois", []):
		pois[MiniWorld.v2(poi["center"])] = poi
	for m: Dictionary in w.map_markers():
		var p := t * (m["pos"] as Vector2)
		match str(m["kind"]):
			"item":
				if not m["done"]:
					_map.draw_circle(p, 6.0, Color(0.1, 0.15, 0.2, 0.8))
					_map.draw_circle(p, 4.2, Color(0.55, 0.9, 1.0))
			"gate":
				MapArt.draw_gate(_map, p)
				MapArt.label(_map, font, p + Vector2(0.0, 24.0), tr("光门"), 15, Color(0.92, 0.85, 1.0))
			_:
				if m["done"]:
					MapArt.draw_pin(_map, p, true, font)
					var poi: Dictionary = pois.get(m["pos"], {})
					MapArt.label(_map, font, p + Vector2(0.0, 16.0), MiniWorld._poi_label(poi) if not poi.is_empty() else "", 14, Color(1.0, 0.9, 0.66))
				elif GameRules.flag("poi_markers"):
					MapArt.draw_pin(_map, p, false, font)
	var got := WorldState.collected(w.world_id).size()
	if GameRules.flag("collectibles") and w.items_total() > 0:
		MapArt.label(_map, font, screen.position + Vector2(screen.size.x * 0.5, 26.0), tr("%s：%d / %d") % [tr(str(w.data.get("item_name", "收集品"))), got, w.items_total()], 17, Color(0.72, 0.93, 1.0))
	_draw_player(t)
	_draw_north_and_scale(t, rect, font)
