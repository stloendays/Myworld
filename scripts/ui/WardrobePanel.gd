extends Control
## 人物外观面板（暂停菜单 → 人物外观）：左侧实时 3D 预览，右侧选择发型/帽子/上衣/下装/鞋/背饰与各部位颜色。
## 改动立即作用于 PlayerProfile.appearance（玩家身上的模型同步变化）；“保存”写入 user://appearance.json。
## 选项全部来自 data/characters/wardrobe.json，新增款式后这里自动出现。

signal closed

var _preview_model: CharacterModel
var _preview_pivot: Node3D
var _option_buttons := {}
var _color_buttons := {}
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = GameSettings.ui_theme()
	_build()
	_refresh_controls()


func _process(delta: float) -> void:
	if visible and _preview_pivot != null:
		_preview_pivot.rotate_y(delta * 0.6)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = UiStyle.DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)

	row.add_child(_build_preview())

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var title := Label.new()
	title.text = "人物外观"
	title.add_theme_font_size_override("font_size", 26)
	right.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	for slot in Wardrobe.slot_order():
		var label := Label.new()
		label.text = Wardrobe.slot_label(slot)
		grid.add_child(label)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(180, 0)
		for style_id in Wardrobe.styles(slot):
			ob.add_item(Wardrobe.style_label(slot, style_id))
			ob.set_item_metadata(ob.item_count - 1, style_id)
		ob.item_selected.connect(_on_style_selected.bind(slot))
		grid.add_child(ob)
		_option_buttons[slot] = ob

	var colors := GridContainer.new()
	colors.columns = 4
	colors.add_theme_constant_override("h_separation", 10)
	colors.add_theme_constant_override("v_separation", 6)
	right.add_child(colors)
	for key in Wardrobe.editable_colors():
		var label := Label.new()
		label.text = Wardrobe.color_label(key)
		colors.add_child(label)
		var cb := ColorPickerButton.new()
		cb.custom_minimum_size = Vector2(64, 28)
		cb.edit_alpha = false
		cb.color_changed.connect(_on_color_changed.bind(key))
		colors.add_child(cb)
		_color_buttons[key] = cb

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	right.add_child(buttons)
	buttons.add_child(_button("随机搭配", _randomize))
	buttons.add_child(_button("恢复默认", _reset))
	buttons.add_child(_button("保存", _save))
	buttons.add_child(_button("返回", closed.emit))
	_status = Label.new()
	right.add_child(_status)


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(320, 440)
	container.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.15, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.8)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_color = Color(1.0, 0.88, 0.76)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.6, 0.7, 1.0)
	vp.add_child(rim)
	_preview_pivot = Node3D.new()
	vp.add_child(_preview_pivot)
	_preview_model = CharacterModel.new()
	_preview_model.appearance = PlayerProfile.appearance
	_preview_pivot.add_child(_preview_model)
	_preview_pivot.rotation_degrees.y = 180.0
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 1.05, 4.4)
	cam.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
	vp.add_child(cam)
	cam.current = true
	return container


func _refresh_controls() -> void:
	var a := PlayerProfile.appearance
	for slot in _option_buttons:
		var ob := _option_buttons[slot] as OptionButton
		for i in ob.item_count:
			if str(ob.get_item_metadata(i)) == a.style(slot):
				ob.select(i)
	for key in _color_buttons:
		(_color_buttons[key] as ColorPickerButton).color = a.color(key)


func _on_style_selected(index: int, slot: String) -> void:
	var ob := _option_buttons[slot] as OptionButton
	PlayerProfile.appearance.set_style(slot, str(ob.get_item_metadata(index)))
	_status.text = ""


func _on_color_changed(color: Color, key: String) -> void:
	PlayerProfile.appearance.set_color(key, color)
	_status.text = ""


func _reset() -> void:
	PlayerProfile.reset_appearance()
	_refresh_controls()


func _save() -> void:
	_status.text = tr("已保存（下次启动自动读取）") if PlayerProfile.save_appearance() else tr("保存失败")


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var a := PlayerProfile.appearance
	for slot in Wardrobe.slot_order():
		var options := Wardrobe.styles(slot)
		a.styles[slot] = options[rng.randi() % options.size()]
	for key in ["hair", "hat", "top", "top_accent", "bottom", "shoes", "back"]:
		a.colors[key] = Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.7), rng.randf_range(0.25, 0.9))
	a.emit_changed()
	_refresh_controls()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b
