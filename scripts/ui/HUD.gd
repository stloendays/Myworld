extends CanvasLayer
## 轻量 HUD：屏幕中心的准星点 + 交互提示（例如“E  打开木门”）。不常驻大型界面。

var _prompt: Label


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

	_prompt = Label.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.6
	_prompt.anchor_bottom = 0.6
	var settings := LabelSettings.new()
	settings.font_size = 22
	settings.outline_size = 6
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.6)
	_prompt.label_settings = settings
	root.add_child(_prompt)

	EventBus.interaction_prompt_changed.connect(_on_prompt)


func _on_prompt(text: String) -> void:
	_prompt.text = text
