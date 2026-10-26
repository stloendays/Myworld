class_name LetterPanel
extends CanvasLayer
## 读信的界面：屏幕中间一张信纸（标题、正文、落款），第一次读到时记进 PaddlerStory 并提示“划船人的信 n / 3”。
## 也用来看石头小屋桌上那张没画完的星图（open_chart：上面画湖畔的五个星座，右边留三个空位）。
## E / 空格 / 回车 / 点击 / Esc 合上，打开时人物不动、鼠标可见（与 DialoguePanel 相同）。

signal closed

var showing := ""            ## 正在看的信 id；看星图时是 chart
var _player: FirstPersonController = null
var _root: Control
var _title: Label
var _body: RichTextLabel
var _sign: Label
var _chart: ChartView


func _ready() -> void:
	layer = 20
	add_to_group("letter_panel")
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open_letter(id: String, player: FirstPersonController) -> void:
	var l := PaddlerStory.letter(id)
	if l.is_empty():
		return
	var first := PaddlerStory.mark_read(id)
	_title.text = PaddlerStory.text(l, "title")
	_body.text = PaddlerStory.text(l, "text")
	_sign.text = PaddlerStory.signature()
	_sign.visible = true
	_chart.visible = false
	_open(id, player)
	if first:
		EventBus.toast_requested.emit(tr("划船人的信  %d / %d") % [PaddlerStory.read_ids().size(), PaddlerStory.letters().size()])


func open_chart(player: FirstPersonController) -> void:
	var c: Dictionary = PaddlerStory.data().get("chart", {})
	_title.text = PaddlerStory.text(c, "title")
	_body.text = PaddlerStory.text(c, "text")
	_sign.visible = false
	_chart.visible = true
	_chart.queue_redraw()
	_open("chart", player)


func _open(what: String, player: FirstPersonController) -> void:
	showing = what
	_player = player
	if _player != null:
		_player.input_locked = true
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	showing = ""
	if _player != null:
		_player.input_locked = false
	_player = null
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var done := event.is_action_pressed("pause")
	if event is InputEventKey and event.pressed and not event.echo:
		done = done or (event as InputEventKey).keycode in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		done = true
	if done:
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 界面

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -400.0
	panel.offset_right = 400.0
	panel.offset_top = -330.0
	panel.offset_bottom = 330.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.88, 0.76)
	sb.border_color = Color(0.55, 0.38, 0.22)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	sb.shadow_size = 18
	sb.content_margin_left = 46.0
	sb.content_margin_right = 46.0
	sb.content_margin_top = 34.0
	sb.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var ink := Color(0.2, 0.13, 0.08)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.45, 0.2, 0.1))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_chart = ChartView.new()
	_chart.custom_minimum_size = Vector2(0.0, 300.0)
	col.add_child(_chart)
	_body = RichTextLabel.new()
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_color_override("default_color", ink)
	_body.add_theme_constant_override("line_separation", 6)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_body)
	_sign = Label.new()
	_sign.add_theme_font_size_override("font_size", 21)
	_sign.add_theme_color_override("font_color", ink)
	_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_sign)
	var hint := Label.new()
	hint.text = tr("E / 空格 / Esc  合上")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.4, 0.3, 0.22))
	col.add_child(hint)


## 没画完的星图：深蓝纸上用浅色墨点画湖畔的五个星座（data/sky/constellations.json），右边三个虚线空位写着“？”。
## 小屋桌上的那张纸用同一个控件画在 SubViewport 里当贴图（StoneCottage）。
class ChartView extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.1, 0.13, 0.24))
		draw_rect(r.grow(-6.0), Color(0.62, 0.55, 0.4, 0.55), false, 2.0)
		var font := get_theme_default_font()
		var ink := Color(0.93, 0.9, 0.78)
		var list := StarField.constellations()
		var left := r.size.x * 0.68
		var cols := 3
		var cell := Vector2(left / cols, r.size.y / 2.0)
		var deg := minf(cell.x, cell.y) / 30.0
		for i in list.size():
			var c: Dictionary = list[i]
			var center := Vector2(cell.x * (float(i % cols) + 0.5), cell.y * (float(i / cols) + 0.45))
			var stars: Array = c["stars"]
			var pts: Array[Vector2] = []
			for s: Array in stars:
				pts.append(center + Vector2(float(s[0]), -float(s[1])) * deg)
			for ln: Array in c["lines"]:
				draw_line(pts[int(ln[0])], pts[int(ln[1])], Color(ink, 0.55), 1.5, true)
			for k in pts.size():
				draw_circle(pts[k], 1.5 + float((stars[k] as Array)[2]) * 2.2, ink)
			var name := PaddlerStory.text(c, "name")
			draw_string(font, center + Vector2(-cell.x * 0.5, cell.y * 0.47), name, HORIZONTAL_ALIGNMENT_CENTER, cell.x, 15, Color(ink, 0.85))
		for j in 3:
			var p := Vector2(left + (r.size.x - left) * 0.5, r.size.y * (0.2 + 0.3 * j))
			var rad := minf(r.size.y * 0.11, (r.size.x - left) * 0.32)
			for a in 16:
				if a % 2 == 0:
					draw_arc(p, rad, TAU * a / 16.0, TAU * (a + 1) / 16.0, 4, Color(ink, 0.6), 1.5, true)
			draw_string(font, p + Vector2(-rad, 8.0), "?", HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, 24, Color(ink, 0.7))
