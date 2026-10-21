extends CanvasLayer
## F4 天气调试面板（开发用，与正式设置入口分开）：显示时间/季节/天气，强制切换预设、季节、天气、时刻与时间流速。
## 打开时释放鼠标，关闭后重新锁定；不暂停世界，方便看过渡效果。

var _panel: PanelContainer
var _status: Label
var _weather_buttons := {}
var _open := false


func _ready() -> void:
	layer = 15
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_weather_panel"):
		_open = not _open
		_panel.visible = _open
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _open else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _open:
		return
	var w := ClimateData.weather_profile(WorldState.weather_id)
	var s := ClimateData.season_profile(WorldState.season_id)
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var text := "%s 第 %d 天 %s  ·  %s" % [s.get("name", ""), WorldState.world_day, ClimateData.format_time(WorldState.time_minutes), w.get("name", "")]
	if WorldState.weather_progress < 1.0:
		text += "（由 %s 过渡中 %d%%）" % [ClimateData.weather_profile(WorldState.weather_from).get("name", ""), int(WorldState.weather_progress * 100.0)]
	if env != null:
		text += "\n太阳高度 %.1f°  方位 %.0f°  夜 %.2f" % [env.sun_elevation, env.sun_azimuth, env.night]
	text += "\n地面湿润 %.2f  积雪 %.2f  时间流速 ×%d%s" % [WorldState.ground_wetness, WorldState.ground_snow, int(WorldState.time_scale), "（暂停）" if WorldState.time_paused else ""]
	_status.text = text
	for id in _weather_buttons:
		(_weather_buttons[id] as Button).disabled = not ClimateData.is_allowed(WorldState.season_id, id)


func _climate() -> ClimateSystem:
	return get_tree().get_first_node_in_group("climate_system") as ClimateSystem


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.theme = GameSettings.ui_theme()
	_panel.position = Vector2(12, 150)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.82)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "天气调试（F4 关闭）"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	box.add_child(_status)

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
	var speed := HBoxContainer.new()
	for s in [1, 60, 600]:
		speed.add_child(_button("×%d" % s, func() -> void: WorldState.time_scale = float(s)))
	speed.add_child(_button("暂停/继续时间", func() -> void: WorldState.time_paused = not WorldState.time_paused))
	box.add_child(speed)


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
