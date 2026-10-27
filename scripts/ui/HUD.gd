extends CanvasLayer
## 轻量 HUD：屏幕中心的准星点 + 交互提示（例如“E  打开木门”：按键画成一个键帽，后面是动作，衬一条半透明的药丸）
## + 屏幕中上方的短提示（同样的药丸，停留几秒后淡出）。不常驻大型界面。

var _prompt: Label
var _prompt_key: Label
var _prompt_pill: PanelContainer
var _dev: Label
var _toast: Label
var _toast_pill: PanelContainer
var _toast_time := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameSettings.ui_theme()
	add_child(root)

	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 1.0, 0.7)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -2.0
	dot.offset_right = 2.0
	dot.offset_top = -2.0
	dot.offset_bottom = 2.0
	root.add_child(dot)

	# 交互提示：居中、准星下方；“E  打开木门”拆成键帽 E 和“打开木门”
	var prompt_row := CenterContainer.new()
	prompt_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_row.anchor_left = 0.0
	prompt_row.anchor_right = 1.0
	prompt_row.anchor_top = 0.6
	prompt_row.anchor_bottom = 0.6
	root.add_child(prompt_row)
	_prompt_pill = PanelContainer.new()
	_prompt_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_pill.add_theme_stylebox_override("panel", UiStyle.pill(0.6))
	prompt_row.add_child(_prompt_pill)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_pill.add_child(h)
	_prompt_key = Label.new()
	_prompt_key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_prompt_key.add_theme_stylebox_override("normal", UiStyle.keycap())
	_prompt_key.add_theme_font_size_override("font_size", 18)
	_prompt_key.add_theme_color_override("font_color", Color(0.15, 0.1, 0.07))
	_prompt_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_prompt_key)
	_prompt = Label.new()
	_prompt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 21)
	_prompt.add_theme_color_override("font_color", UiStyle.TEXT)
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_prompt)
	_prompt_pill.visible = false

	# 开发者模式角标（左上，飞行 / 穿墙时一起显示）
	_dev = Label.new()
	_dev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dev.anchor_left = 0.5
	_dev.anchor_right = 0.5
	_dev.offset_left = -260.0
	_dev.offset_right = 260.0
	_dev.offset_top = 10.0
	_dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dev_settings := LabelSettings.new()
	dev_settings.font_size = 17
	dev_settings.font_color = Color(1.0, 0.85, 0.45)
	dev_settings.outline_size = 5
	dev_settings.outline_color = Color(0.0, 0.0, 0.0, 0.7)
	_dev.label_settings = dev_settings
	root.add_child(_dev)

	# 短提示（发现新地点、睡醒、下不了船等），屏幕中上方停留几秒后淡出
	var toast_row := CenterContainer.new()
	toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_row.anchor_left = 0.0
	toast_row.anchor_right = 1.0
	toast_row.anchor_top = 0.17
	toast_row.anchor_bottom = 0.17
	root.add_child(toast_row)
	_toast_pill = PanelContainer.new()
	_toast_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := UiStyle.pill(0.66)
	ts.border_color = Color(UiStyle.ACCENT, 0.35)
	ts.content_margin_left = 24.0
	ts.content_margin_right = 24.0
	ts.content_margin_top = 10.0
	ts.content_margin_bottom = 10.0
	_toast_pill.add_theme_stylebox_override("panel", ts)
	toast_row.add_child(_toast_pill)
	_toast = Label.new()
	_toast.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size = Vector2(0, 0)
	_toast.add_theme_font_size_override("font_size", 23)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	_toast_pill.add_child(_toast)
	_toast_pill.modulate.a = 0.0
	EventBus.toast_requested.connect(show_toast)

	EventBus.interaction_prompt_changed.connect(_on_prompt)


## “E  打开木门” → 键帽 E + “打开木门”；没有按键开头的提示只显示文字。
func _on_prompt(text: String) -> void:
	_prompt_pill.visible = text != ""
	var cut := text.find("  ")
	var key := text.substr(0, cut) if cut > 0 else ""
	if key != "" and key.length() <= 6 and key.is_valid_ascii_identifier() or key in ["E", "R", "Q", "B", "F", "G", "T"]:
		_prompt_key.text = key
		_prompt_key.visible = true
		_prompt.text = text.substr(cut).strip_edges()
	else:
		_prompt_key.visible = false
		_prompt.text = text


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast_pill.modulate.a = clampf(_toast_time / 0.6, 0.0, 1.0)
	_dev.visible = GameSettings.developer_mode
	if not _dev.visible:
		return
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var parts := PackedStringArray([tr("开发者模式（F2 退出）")])
	if player != null and player.flying:
		parts.append(tr("飞行中") + (tr("  ·  穿墙") if player.noclip else ""))
	else:
		parts.append(tr("F 飞行"))
	_dev.text = "  ·  ".join(parts)


func show_toast(text: String) -> void:
	_toast.text = text
	# 长的提示换行，不要横贯整个屏幕
	var font := _toast.get_theme_font("font")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x if font != null else 600.0
	_toast.custom_minimum_size = Vector2(minf(w + 4.0, 860.0), 0)
	_toast_time = 4.0
	_toast_pill.modulate.a = 1.0


func toast_text() -> String:
	return _toast.text if _toast_time > 0.0 else ""
