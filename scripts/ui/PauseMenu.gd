extends CanvasLayer
## Esc 暂停菜单：释放鼠标、暂停世界（联机时不暂停，只让人物站定）。主菜单：继续 / 多人房间 / 设置 / 人物外观 / 退出。
## 设置分页：画面、视角、操作、小地图、开发者；每项改动立刻生效并保存到 user://settings.json。
## 未暂停时点击窗口会重新锁定鼠标。

const FPS_CHOICES := [0, 30, 60, 120, 144, 165, 240]
const ARMS_CHOICES := ["both", "right", "none"]

var _root: Control
var _open := false
var _menu: Control
var _settings: Control
var _wardrobe = null   ## WardrobePanel（带 closed 信号）
var _controls := {}    ## 设置键 -> [控件, 数值标签或 null]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	_set_open(false)
	GameSettings.changed.connect(_refresh)


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _open and _settings.visible:
			_show_menu()
		else:
			_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif not _open and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _can_capture() and not _dev_panel_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_capture() -> bool:
	return GameSettings.can_grab_mouse()


func _dev_panel_open() -> bool:
	var panel := get_parent().get_node_or_null("DevPanel")
	return panel != null and panel.is_open()


func _set_open(open: bool) -> void:
	_open = open
	_root.visible = open
	if not open:
		_show_menu()
	else:
		_refresh()
	# 联机时世界不能停（房主一停，大家的时间天气都停了）：只让自己的人物站定
	get_tree().paused = open and not Net.is_online()
	PlayerHold.set_held(self, get_tree(), open)
	if _can_capture():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or _dev_panel_open() else Input.MOUSE_MODE_CAPTURED


func open_settings(tab := 0) -> void:
	if not _open:
		_set_open(true)
	_menu.visible = false
	_wardrobe.visible = false
	_settings.visible = true
	(_settings.find_child("Tabs", true, false) as TabContainer).current_tab = tab


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_menu = _centered(_build_main_menu())
	_settings = _centered(_build_settings())
	_wardrobe = preload("res://scripts/ui/WardrobePanel.gd").new()
	_wardrobe.visible = false
	_wardrobe.closed.connect(_show_menu)
	_root.add_child(_wardrobe)


func _centered(content: Control) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	margin.add_child(content)
	return center


func _build_main_menu() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "Dusk Lake · 暂停"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var keys := Label.new()
	keys.text = "WASD 移动 · Shift 奔跑 · 空格 跳跃/上浮 · C 下潜 · E 或右键 交互 · V 视角\nG 动作轮盘（1 休息 · 2 挥手 · 3 跳舞 · 4 鼓掌）· F12 拍照 · T 聊天\nM 小地图 · Tab 世界地图 · F11 全屏 · F3 坐标 · F2 开发者模式（F 飞行 · N 穿墙 · F4 面板）"
	box.add_child(keys)
	for item in [["继续", _close], ["多人房间", _open_room], ["全屏 / 窗口（F11）", func() -> void: GameSettings.set_value("fullscreen", not GameSettings.fullscreen)], ["设置", open_settings.bind(0)], ["人物外观", _show_wardrobe], ["退出游戏", _quit]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		box.add_child(b)
	return box


func _build_settings() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	tabs.custom_minimum_size = Vector2(620, 330)
	box.add_child(tabs)

	var display := _tab(tabs, "画面")
	_option(display, "graphics_quality", "画质", ["低（轻薄本）", "中", "高（推荐）", "极高"], ["low", "medium", "high", "ultra"])
	_check(display, "dynamic_resolution", "动态分辨率（GPU 忙时自动降低渲染比例，用 FSR 放大）")
	_slider(display, "fov", "视野 FOV", GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, "%d°")
	_slider(display, "render_scale", "渲染比例", 0.5, 1.0, 0.05, "%d%%", 100.0)
	_option(display, "max_fps", "帧率上限", ["不限", "30", "60", "120", "144", "165", "240"], FPS_CHOICES)
	_check(display, "vsync", "垂直同步")
	_check(display, "fullscreen", "全屏（F11 或 Alt + Enter 随时切换）")

	var view := _tab(tabs, "视角")
	_option(view, "third_person_default", "启动时视角", ["第一人称", "第三人称"], [false, true])
	_option(view, "first_person_arms", "第一人称的手", ["显示双手", "只显示右手", "不显示"], ARMS_CHOICES)
	_slider(view, "hand_size", "手的大小", 0.4, 1.0, 0.05, "%d%%", 100.0)
	_check(view, "play_intro", "启动时播放开场动画")
	_check(view, "view_bob", "走路时镜头晃动")
	_slider(view, "third_person_distance", "第三人称距离", 1.5, 8.0, 0.1, "%.1f m")
	_option(view, "shoulder_left", "第三人称肩位", ["右肩", "左肩"], [false, true])
	var v_hint := Label.new()
	v_hint.text = "游戏中按 V 随时切换第一 / 第三人称"
	view.add_child(v_hint)

	var control := _tab(tabs, "操作")
	_slider(control, "mouse_sensitivity", "鼠标灵敏度", 0.0005, 0.008, 0.0001, "%.4f")
	_check(control, "invert_y", "鼠标 Y 轴反转")
	_check(control, "emote_third_person", "挥手 / 跳舞 / 鼓掌时自动切到第三人称")
	_option(control, "language", "语言 / Language", GameSettings.LANGUAGE_NAMES, GameSettings.LANGUAGES)

	var minimap := _tab(tabs, "小地图")
	_check(minimap, "minimap_enabled", "显示小地图（M）")
	_check(minimap, "minimap_rotate", "随朝向旋转（关闭 = 北朝上）")
	_slider(minimap, "minimap_range", "显示范围（半径）", 25.0, 150.0, 5.0, "%d m")

	var about := _tab(tabs, "关于")
	var ver := Label.new()
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ver.text = "Dusk Lake v%s" % Updater.current_version()
	ver.add_theme_font_size_override("font_size", 22)
	about.add_child(ver)
	_check(about, "auto_update_check", "启动时自动检查更新")
	var upd_status := Label.new()
	upd_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_child(upd_status)
	var upd_row := HBoxContainer.new()
	upd_row.add_theme_constant_override("separation", 10)
	about.add_child(upd_row)
	var check_btn := Button.new()
	check_btn.text = "检查更新"
	check_btn.pressed.connect(Updater.check)
	upd_row.add_child(check_btn)
	var install_btn := Button.new()
	install_btn.text = "更新并重启"
	install_btn.pressed.connect(Updater.download_and_install)
	upd_row.add_child(install_btn)
	var page_btn := Button.new()
	page_btn.text = "打开发布页"
	page_btn.pressed.connect(Updater.open_releases_page)
	upd_row.add_child(page_btn)
	var sync_update := func(_s: int = 0, _t: String = "") -> void:
		upd_status.text = Updater.status_text if Updater.status_text != "" else tr("还没检查过更新")
		install_btn.visible = Updater.state == Updater.State.AVAILABLE
		check_btn.disabled = Updater.state == Updater.State.CHECKING or Updater.state == Updater.State.DOWNLOADING
	Updater.status_changed.connect(sync_update)
	sync_update.call()

	var dev := _tab(tabs, "开发者")
	var dev_check := CheckBox.new()
	dev_check.text = "开发者模式（F2）"
	dev_check.toggled.connect(GameSettings.set_developer_mode)
	dev.add_child(dev_check)
	_controls["developer_mode"] = [dev_check, null]
	var dev_hint := Label.new()
	dev_hint.text = "开发者模式：左侧出现开发者面板，可改天气、季节、时间，传送到各地点；\n按 F 飞行（空格上升、C 下降、Shift 加速），飞行时按 N 穿墙。退出开发者模式会自动落地。\n开发者模式不保存，每次启动都是普通模式。"
	dev.add_child(dev_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var reset := Button.new()
	reset.text = "恢复默认"
	reset.pressed.connect(_reset_defaults)
	row.add_child(reset)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_show_menu)
	row.add_child(back)
	box.add_child(row)
	return box


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	tabs.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	return box


func _row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)
	parent.add_child(row)
	return row


func _slider(parent: Control, key: String, label_text: String, min_v: float, max_v: float, step: float, fmt: String, display_scale := 1.0) -> void:
	var row := _row(parent, label_text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(280, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.set_meta("fmt", fmt)
	value_label.set_meta("scale", display_scale)
	row.add_child(value_label)
	slider.value_changed.connect(_on_slider.bind(key))
	_controls[key] = [slider, value_label]


func _check(parent: Control, key: String, label_text: String) -> void:
	var c := CheckBox.new()
	c.text = label_text
	c.toggled.connect(_on_check.bind(key))
	parent.add_child(c)
	_controls[key] = [c, null]


func _option(parent: Control, key: String, label_text: String, names: Array, values: Array) -> void:
	var row := _row(parent, label_text)
	var o := OptionButton.new()
	for n in names:
		o.add_item(str(n))
	o.set_meta("values", values)
	o.item_selected.connect(_on_option.bind(key))
	row.add_child(o)
	_controls[key] = [o, null]


func _on_slider(value: float, key: String) -> void:
	GameSettings.set_value(key, value)


func _on_check(pressed: bool, key: String) -> void:
	GameSettings.set_value(key, pressed)


func _on_option(index: int, key: String) -> void:
	var values: Array = (_controls[key][0] as OptionButton).get_meta("values")
	GameSettings.set_value(key, values[index])


## 控件跟随当前设置（按 M、F2 等快捷键改了设置时，菜单里也同步）。
func _refresh() -> void:
	for key in _controls:
		var c: Control = _controls[key][0]
		var value: Variant = GameSettings.developer_mode if key == "developer_mode" else GameSettings.get(key)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(value))
			var l: Label = _controls[key][1]
			var shown := float(value) * float(l.get_meta("scale"))
			var fmt: String = l.get_meta("fmt")
			l.text = fmt % (int(round(shown)) if fmt.contains("%d") else shown)
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(value))
		elif c is OptionButton:
			var values: Array = (c as OptionButton).get_meta("values")
			var i := values.find(value)
			(c as OptionButton).select(maxi(i, 0))


func _reset_defaults() -> void:
	GameSettings.reset_defaults()
	GameSettings.save_to(GameSettings.SETTINGS_PATH)


func _close() -> void:
	_set_open(false)


func _open_room() -> void:
	_set_open(false)
	var lobby := get_parent().get_node_or_null("LobbyMenu") as LobbyMenu
	if lobby != null:
		lobby.open_room()


func _quit() -> void:
	get_tree().quit()


func _show_wardrobe() -> void:
	_menu.visible = false
	_settings.visible = false
	_wardrobe.visible = true


func _show_menu() -> void:
	_wardrobe.visible = false
	_settings.visible = false
	_menu.visible = true
