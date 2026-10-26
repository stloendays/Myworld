class_name CookingPanel
extends CanvasLayer
## 烹饪面板（看着铁锅按 E 打开，Esc / E 关闭）：鱼篓里有哪些鱼、三道菜要什么、做得了的可以点“做”（也可以按 1 / 2 / 3），
## 下面一行是正在生效的效果。打开时人物不动、鼠标放出来。

var _root: Control
var _box: VBoxContainer
var _player: FirstPersonController = null
var _opened_ms := 0


func _ready() -> void:
	layer = 18
	add_to_group("cooking_panel")
	_build()
	_root.visible = false
	Play.changed.connect(_refresh)


func is_open() -> bool:
	return _root.visible


func open(p: FirstPersonController) -> void:
	_player = p
	_opened_ms = Time.get_ticks_msec()
	if _player != null:
		_player.input_locked = true
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_root.visible = true


func close() -> void:
	_root.visible = false
	if _player != null:
		_player.input_locked = false
	_player = null
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("pause") or (event.is_action_pressed("interact") and Time.get_ticks_msec() - _opened_ms > 250):
		close()
		get_viewport().set_input_as_handled()
		return
	for i in 3:
		if event.is_action_pressed("action_%d" % (i + 1)) and i < Play.recipes().size():
			Play.cook(str(Play.recipes()[i]["id"]))
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	var have := Play.fish_in_pantry()
	var names := PackedStringArray()
	for id: String in have:
		names.append("%s ×%d" % [Play.text(Play.fish(id), "name"), int(have[id])])
	_box.add_child(_label(tr("鱼篓：") + ("、".join(names) if not names.is_empty() else tr("空的（按 R 去钓几条）")), 19, Color(0.92, 0.9, 0.86)))
	var i := 0
	for r: Dictionary in Play.recipes():
		i += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_box.add_child(row)
		var b: Dictionary = (Play.fish_data.get("buffs", {}) as Dictionary).get(str(r["buff"]), {})
		var need := tr("%d 条鱼") % int(r["fish"]) + (tr("（%d 种不同的）") % int(r["kinds"]) if int(r["kinds"]) > 1 else "")
		var l := _label("%d  %s   ·   %s   ·   %s：%s" % [i, Play.text(r, "name"), need, Play.text(b, "name"), Play.text(b, "desc")], 20, Color(1.0, 0.88, 0.6), true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var btn := Button.new()
		var problem := Play.cook_problem(str(r["id"]))
		btn.text = tr("做") if problem == "" else tr("不够")
		btn.disabled = problem != ""
		btn.tooltip_text = problem
		btn.pressed.connect(Play.cook.bind(str(r["id"])))
		row.add_child(btn)
	var active := Play.active_buffs()
	if not active.is_empty():
		var parts := PackedStringArray()
		for a: Dictionary in active:
			parts.append(tr("%s 还有 %d 秒") % [a["name"], int(a["seconds_left"])])
		_box.add_child(_label(tr("正在生效：") + "、".join(parts), 18, Color(0.75, 0.95, 0.7)))


func _label(text: String, size: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 300.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(tr("炉火烹饪"), 28, Color(1.0, 0.92, 0.75))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_label(tr("1 / 2 / 3 做菜   ·   E / Esc 关闭"), 16, Color(0.85, 0.82, 0.76)))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	col.add_child(_box)
