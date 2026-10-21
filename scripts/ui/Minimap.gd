class_name Minimap
extends CanvasLayer
## 右上角圆形小地图：玩家在圆心，默认随朝向旋转（设置里可改成北朝上），M 键或设置里开关。
## 底图由地形高度函数、植被密度烘焙成 256×256 贴图（后台线程，结果缓存在 user://，布局不变就直接读缓存）；
## 步道、码头、建筑、玩家箭头、北方标记每帧用矢量画，放大也清楚。下面一行显示当前区域名。

const SIZE := 210.0
const MARGIN := 18.0
const BAKE_RES := 256
const CACHE_PATH := "user://minimap_%s.png"
const MAP_VERSION := 1

const WATER_SHALLOW := Color(0.40, 0.66, 0.74)
const WATER_DEEP := Color(0.13, 0.31, 0.47)
const SAND := Color(0.80, 0.74, 0.58)
const GRASS := Color(0.50, 0.60, 0.34)
const FOREST := Color(0.18, 0.34, 0.21)
const ROCK := Color(0.56, 0.53, 0.49)
const PATH_COLOR := Color(0.88, 0.80, 0.62)
const DOCK_COLOR := Color(0.55, 0.38, 0.24)

var map_texture: Texture2D = null
var world_rect := Rect2()

var _root: Control
var _mask: Control
var _canvas: Control
var _overlay: Control
var _zone_label: Label
var _task := -1
var _image: Image = null
var _zone_names := {}


func _ready() -> void:
	layer = 4
	var e := WorldTerrain.extent()
	world_rect = Rect2(-e, -e, e * 2.0, e * 2.0)
	for z in WorldLayout.zones():
		_zone_names[StringName(z["zone_id"])] = str(z.get("name", z["zone_id"]))
	_build()
	_load_or_bake()
	GameSettings.changed.connect(_sync_visibility)
	_sync_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_minimap"):
		GameSettings.set_value("minimap_enabled", not GameSettings.minimap_enabled)
		get_viewport().set_input_as_handled()


func _sync_visibility() -> void:
	_root.visible = GameSettings.minimap_enabled


func is_ready() -> bool:
	return map_texture != null


func _build() -> void:
	_root = Control.new()
	_root.name = "MinimapRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = GameSettings.ui_theme()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -SIZE - MARGIN
	_root.offset_right = -MARGIN
	_root.offset_top = MARGIN
	_root.offset_bottom = MARGIN + SIZE + 30.0
	add_child(_root)
	_mask = Control.new()
	_mask.name = "Mask"
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_mask.size = Vector2(SIZE, SIZE)
	_mask.draw.connect(func() -> void: _mask.draw_circle(Vector2(SIZE, SIZE) * 0.5, SIZE * 0.5, Color.WHITE))
	_root.add_child(_mask)
	_canvas = Control.new()
	_canvas.name = "Map"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.size = Vector2(SIZE, SIZE)
	_canvas.draw.connect(_draw_map)
	_mask.add_child(_canvas)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = Vector2(SIZE, SIZE)
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)
	_zone_label = Label.new()
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.position = Vector2(0.0, SIZE + 4.0)
	_zone_label.size = Vector2(SIZE, 24.0)
	var ls := LabelSettings.new()
	ls.font_size = 16
	ls.outline_size = 5
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.7)
	_zone_label.label_settings = ls
	_root.add_child(_zone_label)


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		map_texture = ImageTexture.create_from_image(_image)
		_image.save_png(_cache_path())
	if not _root.visible:
		return
	_canvas.queue_redraw()
	_overlay.queue_redraw()
	var player := _player()
	if player != null:
		_zone_label.text = _zone_text(player)


func _player() -> FirstPersonController:
	return get_tree().get_first_node_in_group("local_player") as FirstPersonController


## 区域名：取最具体的一个（室内优先，其次是非湖泊的小区域）。
func _zone_text(player: FirstPersonController) -> String:
	var zones := WorldState.zones_of(player.entity_id)
	var best := ""
	for z in zones:
		var n: String = _zone_names.get(z, "")
		if n == "":
			n = {&"cabin_interior": "木屋室内", &"poolhouse": "泳池馆大厅", &"aquarium": "地下水族馆"}.get(z, "")
		if n != "" and (best == "" or z in [&"cabin_interior", &"poolhouse", &"aquarium"]):
			best = n
	return best


# ---------------------------------------------------------------- 坐标变换

## 世界 (x, z) → 小地图像素的变换：玩家在圆心，旋转模式下玩家朝向朝上。
func world_to_map() -> Transform2D:
	var player := _player()
	var center := Vector2(SIZE, SIZE) * 0.5
	var k := (SIZE * 0.5) / GameSettings.minimap_range
	var at := Vector2.ZERO
	var rot := 0.0
	if player != null:
		at = Vector2(player.global_position.x, player.global_position.z)
		if GameSettings.minimap_rotate:
			rot = player.rotation.y
	return Transform2D(rot, Vector2(k, k), 0.0, center) * Transform2D(0.0, Vector2.ONE, 0.0, -at)


func _draw_map() -> void:
	var t := world_to_map()
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.12, 0.16, 0.12))
	_canvas.draw_set_transform_matrix(t)
	if map_texture != null:
		_canvas.draw_texture_rect(map_texture, world_rect, false)
	for pts in WorldLayout.path_polylines():
		_canvas.draw_polyline(pts, PATH_COLOR, 2.4, true)
	var dock := WorldLayout.section("dock")
	if not dock.is_empty():
		_canvas.draw_line(WorldLayout.v2(dock["from"]), WorldLayout.v2(dock["to"]), DOCK_COLOR, float(dock.get("width", 2.6)))
	_draw_building(WorldLayout.section("cabin"), Vector2(Cabin.LENGTH + Cabin.DECK_DEPTH, Cabin.HALF_SPAN * 2.0), Vector2(Cabin.DECK_DEPTH * 0.5, 0.0), Color(0.62, 0.33, 0.22))
	_draw_building(WorldLayout.section("poolhouse"), Vector2(PoolHouse.HX * 2.0, PoolHouse.HZ * 2.0), Vector2.ZERO, Color(0.55, 0.74, 0.84))
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_building(cfg: Dictionary, size: Vector2, offset: Vector2, color: Color) -> void:
	if cfg.is_empty():
		return
	var c := WorldLayout.v2(cfg["center"])
	var yaw := -deg_to_rad(float(cfg.get("yaw_deg", 0.0)))
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(c + (offset + corner * size * 0.5).rotated(yaw))
	_canvas.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	_canvas.draw_polyline(pts, Color(0.12, 0.10, 0.08), 0.6)


func _draw_overlay() -> void:
	var center := Vector2(SIZE, SIZE) * 0.5
	var r := SIZE * 0.5
	_overlay.draw_arc(center, r - 1.5, 0.0, TAU, 96, Color(0.08, 0.07, 0.06, 0.9), 3.0, true)
	_overlay.draw_arc(center, r - 4.0, 0.0, TAU, 96, Color(0.95, 0.92, 0.84, 0.55), 1.2, true)
	var player := _player()
	var rot := player.rotation.y if player != null and GameSettings.minimap_rotate else 0.0
	# 北方标记：世界 -Z 方向在圆周上的位置
	var north := center + Vector2(0.0, -(r - 13.0)).rotated(rot)
	_overlay.draw_circle(north, 9.0, Color(0.12, 0.10, 0.09, 0.85))
	var font := GameSettings.ui_theme().default_font
	_overlay.draw_string(font, north + Vector2(-5.0, 5.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.86, 0.55))
	# 玩家箭头：旋转模式下永远朝上，北朝上模式下按朝向转
	var heading := 0.0 if GameSettings.minimap_rotate or player == null else -player.rotation.y
	var arrow := PackedVector2Array([Vector2(0, -9), Vector2(6.5, 7), Vector2(0, 3.5), Vector2(-6.5, 7)])
	var pts := PackedVector2Array()
	for p in arrow:
		pts.append(center + p.rotated(heading))
	_overlay.draw_colored_polygon(pts, Color(1.0, 0.97, 0.9))
	pts.append(pts[0])
	_overlay.draw_polyline(pts, Color(0.1, 0.08, 0.06), 1.5, true)


# ---------------------------------------------------------------- 底图烘焙

func _cache_path() -> String:
	var key := "%d_%d_%s" % [MAP_VERSION, BAKE_RES, FileAccess.get_md5(WorldLayout.PATH).substr(0, 12)]
	return CACHE_PATH % key


func _load_or_bake() -> void:
	var path := _cache_path()
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			map_texture = ImageTexture.create_from_image(img)
			return
	_image = Image.create(BAKE_RES, BAKE_RES, false, Image.FORMAT_RGB8)
	_task = WorkerThreadPool.add_task(_bake.bind(_image), true, "minimap bake")


## 在后台线程里按地形高度、坡度、植被密度上色，并按西北光做山体阴影。
func _bake(img: Image) -> void:
	var n := BAKE_RES
	var cell := world_rect.size.x / n
	var water := WorldLayout.water_level()
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			var x := world_rect.position.x + (i + 0.5) * cell
			var z := world_rect.position.y + (j + 0.5) * cell
			heights[j * n + i] = WorldTerrain.height_at(x, z)
	var light := Vector3(-0.6, 1.2, -0.6).normalized()
	for j in n:
		for i in n:
			var h := heights[j * n + i]
			var x := world_rect.position.x + (i + 0.5) * cell
			var z := world_rect.position.y + (j + 0.5) * cell
			var col: Color
			if h < water:
				col = WATER_SHALLOW.lerp(WATER_DEEP, clampf((water - h) / 3.0, 0.0, 1.0))
			else:
				var hx := heights[j * n + mini(i + 1, n - 1)] - heights[j * n + maxi(i - 1, 0)]
				var hz := heights[mini(j + 1, n - 1) * n + i] - heights[maxi(j - 1, 0) * n + i]
				var normal := Vector3(-hx, 2.0 * cell, -hz).normalized()
				var slope := Vector2(hx, hz).length() / (2.0 * cell)
				col = GRASS.lerp(FOREST, clampf(Vegetation.tree_density(x, z) * 1.3, 0.0, 1.0))
				if h < water + 0.45:
					col = SAND
				col = col.lerp(ROCK, smoothstep(0.7, 1.2, slope))
				col *= clampf(0.55 + normal.dot(light) * 0.55, 0.45, 1.15)
			img.set_pixel(i, j, Color(col.r, col.g, col.b))
