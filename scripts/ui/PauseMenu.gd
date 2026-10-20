extends CanvasLayer
## Esc 暂停菜单：释放鼠标、暂停世界；可调 FOV 与鼠标灵敏度；继续 / 退出。
## 未暂停时点击窗口会重新锁定鼠标。完整设置菜单与持久化属于 M4。

var _root: Control
var _open := false
var _fov_value: Label
var _sens_value: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	_set_open(false)


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif not _open and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _can_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_capture() -> bool:
	return DisplayServer.get_name() != "headless"


func _set_open(open: bool) -> void:
	_open = open
	_root.visible = open
	get_tree().paused = open
	if _can_capture():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Dusk Lake · 暂停"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var keys := Label.new()
	keys.text = "WASD 移动 · Shift 奔跑 · 空格 跳跃 · E 交互 · F3 坐标信息"
	box.add_child(keys)

	var resume := Button.new()
	resume.text = "继续"
	resume.pressed.connect(func() -> void: _set_open(false))
	box.add_child(resume)

	_fov_value = Label.new()
	box.add_child(_slider_row("视野 FOV", GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, GameSettings.fov,
		_fov_value, _on_fov_changed))
	_on_fov_changed(GameSettings.fov)

	_sens_value = Label.new()
	box.add_child(_slider_row("鼠标灵敏度", 0.0005, 0.008, 0.0001, GameSettings.mouse_sensitivity,
		_sens_value, _on_sensitivity_changed))
	_on_sensitivity_changed(GameSettings.mouse_sensitivity)

	var quit := Button.new()
	quit.text = "退出游戏"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func _on_fov_changed(value: float) -> void:
	GameSettings.set_fov(value)
	_fov_value.text = "%d°" % int(value)


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity(value)
	_sens_value.text = "%.4f" % value


func _slider_row(label_text: String, min_v: float, max_v: float, step: float, value: float,
		value_label: Label, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	value_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(value_label)
	return row
