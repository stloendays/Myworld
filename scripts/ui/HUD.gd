extends CanvasLayer
## 轻量 HUD：屏幕中心的准星点 + 交互提示（例如“E  打开木门”）。不常驻大型界面。

var _prompt: Label
var _dev: Label


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

	EventBus.interaction_prompt_changed.connect(_on_prompt)


func _on_prompt(text: String) -> void:
	_prompt.text = text


func _process(_delta: float) -> void:
	_dev.visible = GameSettings.developer_mode
	if not _dev.visible:
		return
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var parts := PackedStringArray(["开发者模式（F2 退出）"])
	if player != null and player.flying:
		parts.append("飞行中" + ("  ·  穿墙" if player.noclip else ""))
	else:
		parts.append("F 飞行")
	_dev.text = "  ·  ".join(parts)
