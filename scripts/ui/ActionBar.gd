class_name ActionBar
extends CanvasLayer
## 动作轮盘：平时屏幕上不显示任何按钮，按 G 才在屏幕中央弹出（参考 GTA / 堡垒之夜的表情轮盘）。
##   按住 G、把鼠标往某个方向一推、松开 G = 选中；轻点 G 则轮盘留着，用鼠标点选，再按 G 或 Esc 收起。
## 四格：休息（第一次坐下、再选躺下、再选起身）、挥手、跳舞、鼓掌。数字键 1–4 是不弹轮盘的快捷键。
## 拍照单独用 F12：隐藏界面拍一张当前画面，存到“图片\Dusk Lake”文件夹。

const ITEMS := [
	["rest", "休息", "坐下 / 躺下 / 起身"],
	["wave", "挥手", ""],
	["dance", "跳舞", ""],
	["clap", "鼓掌", ""],
]
const RADIUS := 150.0
const INNER := 58.0
const DEAD_ZONE := 36.0
const HOLD_SECONDS := 0.25
const PHOTO_DIR := "Dusk Lake"

var wheel_open := false
var hovered := -1
var last_photo := ""
var _root: Control
var _wheel: Control
var _flash: ColorRect
var _opened_at := 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.name = "ActionWheelRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)
	_wheel = Control.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.draw.connect(_draw_wheel)
	_root.add_child(_wheel)
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_set_wheel(false)


func _unhandled_input(event: InputEvent) -> void:
	var me := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if me != null and me.input_locked:
		return   # 下棋等全屏界面打开时不响应
	if event.is_action_pressed("toggle_actions"):
		if wheel_open:
			_choose_or_close()
		else:
			_set_wheel(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("toggle_actions") and wheel_open:
		# 按住后松开：推了方向就执行；按得久但没选就收起；轻点则留着等鼠标点选
		if hovered >= 0:
			_choose_or_close()
		elif Time.get_ticks_msec() / 1000.0 - _opened_at > HOLD_SECONDS:
			_set_wheel(false)
		get_viewport().set_input_as_handled()
		return
	if wheel_open and event.is_action_pressed("pause"):
		_set_wheel(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("photo"):
		take_photo()
		get_viewport().set_input_as_handled()
		return
	for i in ITEMS.size():
		if event.is_action_pressed("action_%d" % (i + 1)):
			trigger(String(ITEMS[i][0]))
			get_viewport().set_input_as_handled()
			return


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_choose_or_close()
		_root.accept_event()


func _choose_or_close() -> void:
	var pick := hovered
	_set_wheel(false)
	if pick >= 0:
		trigger(String(ITEMS[pick][0]))


func _set_wheel(on: bool) -> void:
	wheel_open = on
	hovered = -1
	_root.visible = on
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		_opened_at = Time.get_ticks_msec() / 1000.0
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
		if on:
			Input.warp_mouse(_root.get_viewport_rect().size * 0.5)
	_wheel.queue_redraw()


## 执行一个动作（快捷键、轮盘、测试都走这里）。rest 依次：坐下 → 躺下 → 起身。
func trigger(id: String) -> bool:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return false
	match id:
		"photo":
			take_photo()
			return true
		"rest":
			match player.emote:
				"ground_sit":
					return player.do_emote("lie")
				"lie":
					player.end_emote()
					return true
				_:
					return player.do_emote("ground_sit")
		_:
			return player.do_emote(id)


## 指向某个方向时选中的格子：0 上、1 右、2 下、3 左；离中心太近不选。
static func slice_at(offset: Vector2) -> int:
	if offset.length() < DEAD_ZONE:
		return -1
	var a := fposmod(atan2(offset.x, -offset.y) + PI / 4.0, TAU)
	return int(a / (PI / 2.0)) % 4


func _process(_delta: float) -> void:
	if not wheel_open:
		return
	# 打开暂停菜单或点了别处、鼠标被收回：轮盘也收起
	if DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_set_wheel(false)
		return
	var center := _root.get_viewport_rect().size * 0.5
	var h := slice_at(_root.get_local_mouse_position() - center)
	if h != hovered:
		hovered = h
		_wheel.queue_redraw()


func _draw_wheel() -> void:
	if not wheel_open:
		return
	var center := _wheel.size * 0.5
	var font := GameSettings.ui_theme().default_font
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var current := player.emote if player != null else ""
	for i in ITEMS.size():
		var mid := -PI / 2.0 + i * PI / 2.0
		var pts := PackedVector2Array()
		var steps := 16
		for s in steps + 1:
			var a := mid - PI / 4.0 + 0.04 + (PI / 2.0 - 0.08) * s / steps
			pts.append(center + Vector2(cos(a), sin(a)) * RADIUS)
		for s in steps + 1:
			var a := mid + PI / 4.0 - 0.04 - (PI / 2.0 - 0.08) * s / steps
			pts.append(center + Vector2(cos(a), sin(a)) * INNER)
		var id := String(ITEMS[i][0])
		var active := id == current or (id == "rest" and current in FirstPersonController.EMOTE_POSES)
		var fill := Color(0.95, 0.78, 0.42, 0.92) if i == hovered else Color(0.08, 0.09, 0.11, 0.78)
		_wheel.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		_wheel.draw_polyline(pts, Color(1.0, 0.86, 0.5) if active else Color(1.0, 1.0, 1.0, 0.25), 2.5 if active else 1.2, true)
		var label := tr(String(ITEMS[i][1]))
		var p := center + Vector2(cos(mid), sin(mid)) * (INNER + RADIUS) * 0.5
		var ink := Color(0.1, 0.08, 0.05) if i == hovered else Color(0.96, 0.94, 0.88)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_wheel.draw_string(font, p + Vector2(-w * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
		var key := "%d" % (i + 1)
		_wheel.draw_string(font, p + Vector2(-4.0, 26.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink * Color(1, 1, 1, 0.7))
	_wheel.draw_circle(center, INNER - 6.0, Color(0.06, 0.07, 0.09, 0.85))
	# 中央写选中后会做什么（休息格按当前状态显示坐下 / 躺下 / 起身），字号按圆的宽度缩小，英文也放得下
	var hint := tr("动作")
	if hovered == 0:
		hint = tr({"ground_sit": "躺下", "lie": "起身"}.get(current, "坐下"))
	elif hovered > 0:
		hint = tr(String(ITEMS[hovered][1]))
	var fit := (INNER - 14.0) * 2.0
	var hs := mini(17, int(17.0 * fit / maxf(1.0, font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)))
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	_wheel.draw_string(font, center + Vector2(-hw * 0.5, hs * 0.35), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.96, 0.94, 0.88))
	var foot := tr("松开 G 确认") + "  ·  " + tr("拍照 F12  ·  G / Esc 收起") if hovered >= 0 else tr("拍照 F12  ·  G / Esc 收起")
	var fw := font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_wheel.draw_string_outline(font, center + Vector2(-fw * 0.5, RADIUS + 34.0), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.7))
	_wheel.draw_string(font, center + Vector2(-fw * 0.5, RADIUS + 34.0), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.96, 0.94, 0.88))


## 拍照：隐藏界面一帧，截下画面存成 PNG，白光一闪。返回保存路径（无窗口时返回 ""）。
func take_photo() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var hidden: Array[CanvasLayer] = []
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.visible and cl.name != "UnderwaterOverlay":
			cl.visible = false
			hidden.append(cl)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for cl in hidden:
		cl.visible = true
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join(PHOTO_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := dir.path_join("DuskLake_%s.png" % stamp)
	if img == null or img.save_png(path) != OK:
		EventBus.toast_requested.emit(tr("照片没存下来"))
		return ""
	last_photo = path
	_flash.color.a = 0.75
	create_tween().tween_property(_flash, "color:a", 0.0, 0.45)
	EventBus.toast_requested.emit(tr("已拍照，存在图片文件夹的 %s 里") % PHOTO_DIR)
	return path
