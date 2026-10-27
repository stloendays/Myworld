class_name UiStyle
extends RefCounted
## 全游戏界面的统一样式（暮色配色）：深夜蓝紫的半透明面板、琥珀色的强调、奶白的文字，圆角、细描边、柔和的投影。
## GameSettings.ui_theme() 用 build_theme() 建主题，所有界面（大厅、设置、日志、对话、聊天、地图、烹饪、棋盘、换装……）
## 都挂这一个主题；各界面自己的面板、药丸提示条、按键帽也从这里取，配色只在这一处改。

const BG := Color(0.075, 0.066, 0.115)          ## 面板底色
const BG_SOFT := Color(0.11, 0.098, 0.165)      ## 卡片、分组
const RAISED := Color(0.17, 0.15, 0.24)         ## 按钮
const HOVER := Color(0.24, 0.205, 0.32)
const PRESSED := Color(0.36, 0.25, 0.17)
const FIELD := Color(0.045, 0.04, 0.075)        ## 输入框、下沉区域
const ACCENT := Color(0.96, 0.74, 0.40)         ## 琥珀（标题、选中、焦点）
const ACCENT_DEEP := Color(0.86, 0.52, 0.30)    ## 落日橙（主按钮）
const MOON := Color(0.62, 0.74, 1.0)            ## 月光蓝（次要强调）
const TEXT := Color(0.97, 0.93, 0.85)
const TEXT_SOFT := Color(0.86, 0.82, 0.74)
const TEXT_DIM := Color(0.66, 0.62, 0.58)
const LINE := Color(0.96, 0.74, 0.40, 0.28)     ## 细描边
const SHADOW := Color(0.0, 0.0, 0.0, 0.42)
const DIM := Color(0.02, 0.015, 0.045, 0.58)    ## 弹窗背后压暗

## 盖住整个画面的面板（大厅、暂停、日志、世界地图、信、厨房、棋盘）进这个组并提供 is_open()；
## 它们开着时罗盘、小地图和任务追踪栏收起来，不压在面板上。
const COVER_GROUP := &"covering_ui"


static func cover_open(tree: SceneTree) -> bool:
	for n in tree.get_nodes_in_group(COVER_GROUP):
		if n.is_open():
			return true
	return false


## 罗盘、小地图、任务追踪栏进这个组、提供 sync_cover()。它们平时每帧自己看一眼；
## 暂停菜单会暂停世界（它们的 _process 停了），所以它开关时用这个主动通知一次。
const CHROME_GROUP := &"hud_chrome"


static func sync_cover(tree: SceneTree) -> void:
	tree.call_group(CHROME_GROUP, "sync_cover")


static func box(bg: Color, radius := 12, border := Color(0, 0, 0, 0), border_w := 0, margin := Vector4(14, 10, 14, 10)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 6
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	s.anti_aliasing = true
	return s


## 大面板（菜单、日志、对话框）：半透明深底、琥珀细边、投影。
static func panel(alpha := 0.94, margin := 26) -> StyleBoxFlat:
	var s := box(Color(BG, alpha), 18, LINE, 1, Vector4(margin, margin, margin, margin))
	s.shadow_color = SHADOW
	s.shadow_size = 22
	s.shadow_offset = Vector2(0, 6)
	return s


## 卡片（大厅的模式卡、设置分组）。
static func card(highlight := false) -> StyleBoxFlat:
	var s := box(Color(BG_SOFT, 0.96), 14, Color(ACCENT, 0.75) if highlight else Color(1, 1, 1, 0.07), 1, Vector4(20, 18, 20, 18))
	return s


## 屏幕上漂浮的小条（交互提示、短提示、任务追踪、聊天记录）。
static func pill(alpha := 0.62) -> StyleBoxFlat:
	var s := box(Color(0.04, 0.035, 0.07, alpha), 14, Color(1, 1, 1, 0.08), 1, Vector4(16, 8, 16, 8))
	return s


## 按键帽（交互提示里的 E、R……）。
static func keycap() -> StyleBoxFlat:
	var s := box(Color(0.96, 0.9, 0.78), 6, Color(1, 1, 1, 0.9), 1, Vector4(9, 2, 9, 3))
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	return s


static func title(text: String, size := 30, color := ACCENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func hint(text: String, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT_SOFT)
	return l


## 主按钮（落日橙）：开始、继续、更新。
static func primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", box(Color(ACCENT_DEEP, 0.92), 10, Color(1, 0.86, 0.6, 0.6), 1, Vector4(18, 10, 18, 10)))
	b.add_theme_stylebox_override("hover", box(Color(0.93, 0.6, 0.34), 10, Color(1, 0.9, 0.7, 0.9), 1, Vector4(18, 10, 18, 10)))
	b.add_theme_stylebox_override("pressed", box(Color(0.72, 0.42, 0.24), 10, Color(1, 0.86, 0.6, 0.6), 1, Vector4(18, 10, 18, 10)))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 10, Color(1, 0.95, 0.8, 0.9), 2))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color(0.12, 0.07, 0.05))
	return b


## 一条分隔线。
static func rule() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(ACCENT, 0.22)
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	return s


## 整套主题：按钮、面板、页签、输入框、下拉菜单、勾选、滑块、进度条、滚动条、提示框、文字颜色。
static func build_theme(font: Font) -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 18
	var btn_m := Vector4(16, 9, 16, 9)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(Color(RAISED, 0.92), 10, Color(1, 1, 1, 0.07), 1, btn_m))
		t.set_stylebox("hover", type, box(Color(HOVER, 0.96), 10, Color(ACCENT, 0.55), 1, btn_m))
		t.set_stylebox("pressed", type, box(Color(PRESSED, 0.96), 10, Color(ACCENT, 0.8), 1, btn_m))
		t.set_stylebox("disabled", type, box(Color(RAISED, 0.4), 10, Color(1, 1, 1, 0.03), 1, btn_m))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), 10, Color(ACCENT, 0.7), 2))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 0.97, 0.9))
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(TEXT, 0.4))
	for type in ["CheckBox", "CheckButton"]:
		var flat := box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 0, Vector4(6, 4, 6, 4))
		t.set_stylebox("normal", type, flat)
		t.set_stylebox("pressed", type, flat)
		t.set_stylebox("hover", type, box(Color(1, 1, 1, 0.05), 8, Color(0, 0, 0, 0), 0, Vector4(6, 4, 6, 4)))
		t.set_stylebox("hover_pressed", type, box(Color(1, 1, 1, 0.05), 8, Color(0, 0, 0, 0), 0, Vector4(6, 4, 6, 4)))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), 8, Color(ACCENT, 0.5), 1))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 0.97, 0.9))
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_hover_pressed_color", type, ACCENT)
		var sw: bool = type == "CheckButton"
		t.set_icon("checked", type, _toggle_icon(true, sw))
		t.set_icon("unchecked", type, _toggle_icon(false, sw))
		t.set_icon("checked_disabled", type, _toggle_icon(true, sw, true))
		t.set_icon("unchecked_disabled", type, _toggle_icon(false, sw, true))
		if not sw:
			t.set_icon("radio_checked", type, _toggle_icon(true, false))
			t.set_icon("radio_unchecked", type, _toggle_icon(false, false))
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("panel", "PopupPanel", panel(0.98, 10))
	t.set_stylebox("panel", "PopupMenu", box(Color(BG, 0.98), 10, LINE, 1, Vector4(6, 6, 6, 6)))
	t.set_stylebox("hover", "PopupMenu", box(Color(HOVER, 1.0), 6, Color(0, 0, 0, 0), 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("panel", "TooltipPanel", box(Color(BG, 0.97), 8, LINE, 1, Vector4(10, 6, 10, 6)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# 页签：选中的那一页琥珀色字、底下一道亮线
	var tab_m := Vector4(16, 8, 16, 8)
	t.set_stylebox("tab_selected", "TabContainer", box(Color(HOVER, 0.95), 10, Color(ACCENT, 0.8), 1, tab_m))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(RAISED, 0.55), 10, Color(1, 1, 1, 0.04), 1, tab_m))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(HOVER, 0.75), 10, Color(ACCENT, 0.35), 1, tab_m))
	t.set_stylebox("panel", "TabContainer", box(Color(FIELD, 0.55), 12, Color(1, 1, 1, 0.05), 1, Vector4(18, 16, 18, 16)))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_SOFT)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 4)
	# 输入框
	for type in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", type, box(Color(FIELD, 0.9), 9, Color(1, 1, 1, 0.1), 1, Vector4(12, 8, 12, 8)))
		t.set_stylebox("focus", type, box(Color(FIELD, 0.95), 9, Color(ACCENT, 0.8), 1, Vector4(12, 8, 12, 8)))
		t.set_stylebox("read_only", type, box(Color(FIELD, 0.5), 9, Color(1, 1, 1, 0.05), 1, Vector4(12, 8, 12, 8)))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_placeholder_color", type, Color(TEXT, 0.38))
		t.set_color("caret_color", type, ACCENT)
		t.set_color("selection_color", type, Color(ACCENT, 0.35))
	# 滑块：细轨道、琥珀色已走过的部分
	var track := box(Color(FIELD, 0.95), 4, Color(1, 1, 1, 0.08), 1, Vector4(0, 3, 0, 3))
	var filled := box(Color(ACCENT, 0.9), 4, Color(0, 0, 0, 0), 0, Vector4(0, 3, 0, 3))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color(1, 0.84, 0.55), 4, Color(0, 0, 0, 0), 0, Vector4(0, 3, 0, 3)))
	# 进度条
	t.set_stylebox("background", "ProgressBar", box(Color(FIELD, 0.85), 6, Color(1, 1, 1, 0.08), 1, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 6, Color(0, 0, 0, 0), 0, Vector4(0, 0, 0, 0)))
	t.set_color("font_color", "ProgressBar", TEXT)
	# 滚动条：细细一条
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color(1, 1, 1, 0.04), 5, Color(0, 0, 0, 0), 0, Vector4(4, 4, 4, 4)))
		t.set_stylebox("grabber", type, box(Color(ACCENT, 0.35), 5, Color(0, 0, 0, 0), 0, Vector4(4, 4, 4, 4)))
		t.set_stylebox("grabber_highlight", type, box(Color(ACCENT, 0.6), 5, Color(0, 0, 0, 0), 0, Vector4(4, 4, 4, 4)))
		t.set_stylebox("grabber_pressed", type, box(ACCENT, 5, Color(0, 0, 0, 0), 0, Vector4(4, 4, 4, 4)))
	t.set_stylebox("separator", "HSeparator", _line())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 10)
	return t


static func _line() -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = Color(ACCENT, 0.22)
	line.thickness = 1
	return line


## 勾选框和开关的图标：引擎默认的图标在深色面板上几乎看不见，这里按像素画一个（不多带图片文件）。
static func _toggle_icon(on: bool, switch: bool, disabled := false) -> ImageTexture:
	var w := 40 if switch else 20
	var h := 22 if switch else 20
	var size := Vector2(w, h)
	var radius := h * 0.5 if switch else 5.0
	var fill := Color(ACCENT_DEEP, 0.95) if on else Color(FIELD, 0.9)
	var edge := Color(1.0, 0.86, 0.6, 0.95) if on else Color(TEXT_DIM, 0.9)
	var mark := Color(0.12, 0.07, 0.05)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _rounded_rect_distance(p, size, radius)
			var cover := clampf(0.5 - d, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var c := fill.lerp(edge, clampf(d + 2.5, 0.0, 1.0))
			if switch:
				var knob := Vector2(w - h * 0.5, h * 0.5) if on else Vector2(h * 0.5, h * 0.5)
				var k := clampf(h * 0.5 - 4.0 - p.distance_to(knob) + 0.5, 0.0, 1.0)
				c = c.lerp(TEXT if on else TEXT_DIM, k)
			elif on:
				var a := Geometry2D.get_closest_point_to_segment(p, Vector2(5.0, 10.5), Vector2(8.5, 14.0)).distance_to(p)
				var b := Geometry2D.get_closest_point_to_segment(p, Vector2(8.5, 14.0), Vector2(15.0, 6.5)).distance_to(p)
				c = c.lerp(mark, clampf(2.0 - minf(a, b), 0.0, 1.0))
			c.a *= cover * (0.4 if disabled else 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## 点到圆角矩形边的有符号距离（里面为负）。
static func _rounded_rect_distance(p: Vector2, size: Vector2, radius: float) -> float:
	var half := size * 0.5
	var q := (p - half).abs() - (half - Vector2(radius, radius))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
