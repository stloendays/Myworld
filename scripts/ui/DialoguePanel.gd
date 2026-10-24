class_name DialoguePanel
extends CanvasLayer
## 和老图腾说话的对话框：屏幕下方一块半透明面板，上面是说话人的名字，字一个一个打出来；
## 没有选项的一页按 E / 空格 / 回车 / 点击继续，有选项时按 1–3 或点按钮。Esc 随时离开。
## 对话内容由 QuestLog 决定：第一次见面先打招呼 → 谢谢你完成的任务 → 给下一个任务（接 / 稍后）→ 道别。
## 参考了 GitHub 上 nathanhoad/godot_dialogue_manager 的“台词页 + 选项”结构，只保留本项目用得到的部分。

signal closed

const CHARS_PER_SEC := 38.0

var pages: Array[Dictionary] = []     ## {text, choices: [{label, action, quest}]}
var page_index := 0
var _player: FirstPersonController = null
var _totem: CaveTotem = null
var _root: Control
var _name_label: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _hint: Label
var _shown := 0.0


func _ready() -> void:
	layer = 20
	add_to_group("dialogue_panel")
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open_totem(totem: CaveTotem, player: FirstPersonController) -> void:
	_totem = totem
	_player = player
	pages = build_pages()
	page_index = 0
	if _player != null:
		_player.input_locked = true
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _totem != null:
		_totem.set_talking(true)
	_name_label.text = QuestLog.giver_name()
	visible = true
	_show_page()


## 按现在的任务进度排出这次对话的各页。
func build_pages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not WorldState.flags.get("met_totem", false):
		WorldState.flags["met_totem"] = true
		out.append({"text": QuestLog.line("greeting"), "choices": []})
	for q: Dictionary in QuestLog.unthanked():
		out.append({"text": QuestLog.text(q, "done"), "choices": [], "thank": str(q["id"])})
	var offer := QuestLog.next_offer()
	if not offer.is_empty():
		out.append({"text": QuestLog.text(offer, "offer"), "choices": [
			{"label": tr("好，我这就去。"), "action": "accept", "quest": str(offer["id"])},
			{"label": tr("等会儿再说。"), "action": "close"},
		]})
	elif QuestLog.done_count() >= QuestLog.quests().size():
		out.append({"text": QuestLog.line("all_done"), "choices": [{"label": tr("再见。"), "action": "close"}]})
	else:
		var names := PackedStringArray()
		for id: String in QuestLog.active_ids():
			names.append(QuestLog.text(QuestLog.get_quest(id), "title"))
		out.append({"text": tr("先把手上的事做完吧：%s。按 J 看任务日志。") % tr("、").join(names), "choices": [{"label": tr("好。"), "action": "close"}]})
	return out


func close() -> void:
	if not visible:
		return
	visible = false
	if _totem != null:
		_totem.set_talking(false)
	if _player != null:
		_player.input_locked = false
	_player = null
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## 继续到下一页（没有选项的页）；最后一页之后关闭。
func advance() -> void:
	var p: Dictionary = pages[page_index]
	if _shown < str(p["text"]).length():
		_shown = str(p["text"]).length()     # 先把这一页的字一次显示完
		_text.visible_characters = -1
		return
	if not (p["choices"] as Array).is_empty():
		return
	if p.has("thank"):
		QuestLog.mark_thanked(str(p["thank"]))
	page_index += 1
	if page_index >= pages.size():
		close()
	else:
		_show_page()


func choose(i: int) -> void:
	var p: Dictionary = pages[page_index]
	var choices: Array = p["choices"]
	if i < 0 or i >= choices.size():
		return
	var c: Dictionary = choices[i]
	match str(c["action"]):
		"accept":
			QuestLog.accept(str(c["quest"]))
			close()
		_:
			close()


func _process(delta: float) -> void:
	if not visible:
		return
	var total := str(pages[page_index]["text"]).length()
	if _shown < total:
		_shown = minf(total, _shown + delta * CHARS_PER_SEC)
		_text.visible_characters = int(_shown)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_3:
			choose(k - KEY_1)
			get_viewport().set_input_as_handled()
		elif k in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (pages[page_index]["choices"] as Array).is_empty():
			advance()


# ---------------------------------------------------------------- 界面

func _show_page() -> void:
	var p: Dictionary = pages[page_index]
	_text.text = str(p["text"])
	_shown = 0.0
	_text.visible_characters = 0
	for c in _choices.get_children():
		c.queue_free()
	var choices: Array = p["choices"]
	for i in choices.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, str((choices[i] as Dictionary)["label"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(choose.bind(i))
		_choices.add_child(b)
	_hint.visible = choices.is_empty()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -470.0
	panel.offset_right = 470.0
	panel.offset_top = -300.0
	panel.offset_bottom = -40.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.05, 0.86)
	sb.border_color = Color(0.85, 0.66, 0.38, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	col.add_child(_name_label)
	_text = RichTextLabel.new()
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0.0, 84.0)
	_text.add_theme_font_size_override("normal_font_size", 22)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	col.add_child(_choices)
	_hint = Label.new()
	_hint.text = tr("E / 空格  继续        Esc  离开")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
	col.add_child(_hint)
