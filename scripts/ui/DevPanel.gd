extends CanvasLayer
## 开发者面板（F2 进入 / 退出开发者模式，F4 在开发者模式里收起 / 展开面板）。
## 能做：改天气（预设、季节、天气、时刻、时间流速）、飞行与穿墙、传送到各地点（world_layout.json → dev_spots）、
## 开关坐标信息与小地图。普通模式下面板与飞行都不可用。打开面板时释放鼠标，收起后重新锁定；不暂停世界。

var _panel: PanelContainer
var _status: Label
var _weather_buttons := {}
var _fly_button: Button
var _noclip_button: Button
var _speed_label: Label
var _open := false
var _scroll: ScrollContainer


func _ready() -> void:
	layer = 15
	_build()
	_panel.visible = false
	GameSettings.developer_mode_changed.connect(_on_developer_mode)


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_mode"):
		GameSettings.set_developer_mode(not GameSettings.developer_mode)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_weather_panel") and GameSettings.developer_mode:
		set_open(not _open)
		get_viewport().set_input_as_handled()


func _on_developer_mode(enabled: bool) -> void:
	set_open(enabled)


func set_open(open: bool) -> void:
	_open = open and GameSettings.developer_mode
	_panel.visible = _open
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _open else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not _open:
		return
	_scroll.custom_minimum_size.y = get_viewport().get_visible_rect().size.y - 80.0
	var w := ClimateData.weather_profile(WorldState.weather_id)
	var s := ClimateData.season_profile(WorldState.season_id)
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var text := "%s 第 %d 天 %s  ·  %s" % [s.get("name", ""), WorldState.world_day, ClimateData.format_time(WorldState.time_minutes), w.get("name", "")]
	if WorldState.weather_progress < 1.0:
		text += "（由 %s 过渡中 %d%%）" % [ClimateData.weather_profile(WorldState.weather_from).get("name", ""), int(WorldState.weather_progress * 100.0)]
	if env != null:
		text += "\n太阳高度 %.1f°  方位 %.0f°  夜 %.2f  风 %.2f" % [env.sun_elevation, env.sun_azimuth, env.night, env.wind_strength]
	text += "\n地面湿润 %.2f  积雪 %.2f  时间流速 ×%d%s" % [WorldState.ground_wetness, WorldState.ground_snow, int(WorldState.time_scale), "（暂停）" if WorldState.time_paused else ""]
	_status.text = text
	for id in _weather_buttons:
		(_weather_buttons[id] as Button).disabled = not ClimateData.is_allowed(WorldState.season_id, id)
	var p := _player()
	if p != null:
		_fly_button.text = "飞行：%s（F）" % ("开" if p.flying else "关")
		_noclip_button.text = "穿墙：%s（N）" % ("开" if p.noclip else "关")
		_noclip_button.disabled = not p.flying


func _climate() -> ClimateSystem:
	return get_tree().get_first_node_in_group("climate_system") as ClimateSystem


func _player() -> FirstPersonController:
	return get_tree().get_first_node_in_group("local_player") as FirstPersonController


## 传送到 dev_spots 里的第 index 个地点；带 fly 的地点（空中）会自动打开飞行。
func teleport(index: int) -> void:
	var spots: Array = WorldLayout.data().get("dev_spots", [])
	var p := _player()
	if p == null or index < 0 or index >= spots.size():
		return
	var spot: Dictionary = spots[index]
	if spot.get("fly", false):
		p.set_flying(true)
	p.teleport_to(spot_position(spot), float(spot.get("heading", 0.0)))


static func spot_position(spot: Dictionary) -> Vector3:
	var a: Array = spot["pos"]
	if spot.get("ground", false) or a.size() == 2:
		var x := float(a[0])
		var z := float(a[a.size() - 1])
		return Vector3(x, WorldTerrain.height_at(x, z) + 0.05, z)
	return Vector3(float(a[0]), float(a[1]) + 0.05, float(a[2]))


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.theme = GameSettings.ui_theme()
	_panel.position = Vector2(12, 56)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.84)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	# 内容多，放进滚动区：窗口矮时也能滚到最下面
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll = scroll
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "开发者模式（F4 收起面板 · F2 退出）"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	box.add_child(_status)

	box.add_child(_section("移动"))
	var move := HFlowContainer.new()
	_fly_button = _button("飞行（F）", func() -> void: _player().set_flying(not _player().flying))
	_noclip_button = _button("穿墙（N）", func() -> void: _player().set_noclip(not _player().noclip))
	move.add_child(_fly_button)
	move.add_child(_noclip_button)
	_speed_label = Label.new()
	var speed := HSlider.new()
	speed.min_value = 3.0
	speed.max_value = 40.0
	speed.step = 1.0
	speed.value = GameSettings.fly_speed
	speed.custom_minimum_size = Vector2(150, 0)
	speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed.focus_mode = Control.FOCUS_NONE
	speed.value_changed.connect(_on_fly_speed)
	_speed_label.text = "飞行速度 %d m/s" % int(GameSettings.fly_speed)
	move.add_child(_speed_label)
	move.add_child(speed)
	box.add_child(move)
	var hint := Label.new()
	hint.text = "飞行时：WASD 平移 · 空格上升 · C / Ctrl 下降 · Shift 三倍速"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.82, 0.84, 0.9))
	box.add_child(hint)

	box.add_child(_section("传送"))
	var spots := HFlowContainer.new()
	var list: Array = WorldLayout.data().get("dev_spots", [])
	for i in list.size():
		spots.add_child(_button(str(list[i]["name"]), teleport.bind(i)))
	box.add_child(spots)

	box.add_child(_section("预设"))
	var presets := HFlowContainer.new()
	for preset_name in ClimateData.weather().get("presets", {}).keys():
		presets.add_child(_button(str(preset_name), func() -> void: _climate().apply_preset(str(preset_name))))
	box.add_child(presets)

	box.add_child(_section("季节"))
	var seasons := HBoxContainer.new()
	for sid in ClimateData.season_order():
		var label: String = ClimateData.season_profile(StringName(sid)).get("name", sid)
		seasons.add_child(_button(label, func() -> void: _climate().jump_to_season(StringName(sid))))
	box.add_child(seasons)

	box.add_child(_section("天气（8 秒过渡；灰色 = 本季不出现）"))
	var weathers := HFlowContainer.new()
	for wid in ClimateData.WEATHER_IDS:
		var b := _button(str(ClimateData.weather_profile(wid).get("name", wid)), func() -> void: _climate().set_weather(wid, 8.0))
		_weather_buttons[wid] = b
		weathers.add_child(b)
	box.add_child(weathers)

	box.add_child(_section("时间"))
	var hours := HFlowContainer.new()
	for h in [6, 9, 12, 17, 19, 22, 2]:
		hours.add_child(_button("%02d:00" % h, func() -> void: _climate().set_hour(float(h))))
	hours.add_child(_button("+1 小时", func() -> void: _climate().skip_hours(1.0)))
	box.add_child(hours)
	var time_speed := HBoxContainer.new()
	for s in [1, 60, 600]:
		time_speed.add_child(_button("×%d" % s, func() -> void: WorldState.time_scale = float(s)))
	time_speed.add_child(_button("暂停/继续时间", func() -> void: WorldState.time_paused = not WorldState.time_paused))
	box.add_child(time_speed)

	box.add_child(_section("季节飘落物（data/weather/seasonal_fx.json）"))
	var fx := HFlowContainer.new()
	fx.add_child(_button("按季节", func() -> void: _set_fx_override("")))
	for pid in (Precipitation.fx_data()["profiles"] as Dictionary).keys():
		var pname := str(Precipitation.fx_profile(str(pid)).get("name", pid))
		fx.add_child(_button(pname, func() -> void: _set_fx_override(str(pid))))
	fx.add_child(_button("关闭", func() -> void: _set_fx_override("off")))
	box.add_child(fx)

	box.add_child(_section("显示"))
	var show := HFlowContainer.new()
	show.add_child(_button("坐标信息（F3）", _toggle_debug_overlay))
	show.add_child(_button("小地图（M）", func() -> void: GameSettings.set_value("minimap_enabled", not GameSettings.minimap_enabled)))
	show.add_child(_button("第一/第三人称（V）", func() -> void: _player().set_third_person(not _player().third_person)))
	box.add_child(show)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0))
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _on_fly_speed(v: float) -> void:
	GameSettings.set_value("fly_speed", v)
	_speed_label.text = "飞行速度 %d m/s" % int(v)


## 季节飘落物方案：""（按季节）/ 方案 id（如保留的“原版红点” legacy_red_motes）/ "off"。只影响本次运行。
func _set_fx_override(id: String) -> void:
	var precip := get_tree().get_first_node_in_group("precipitation") as Precipitation
	if precip != null:
		precip.profile_override = id


func _toggle_debug_overlay() -> void:
	var overlay := get_parent().get_node_or_null("DebugOverlay") as CanvasLayer
	if overlay != null:
		overlay.visible = not overlay.visible
