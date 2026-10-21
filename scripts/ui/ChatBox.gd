class_name ChatBox
extends CanvasLayer
## 聊天框：左下角消息记录 + 输入行。T 或 Enter 打开，/ 直接以命令开头打开；Enter 发送，Esc 取消，↑↓ 翻输入历史。
## 普通消息以玩家名字显示；以 / 开头的是命令（ChatCommands，/help 列出）；天气、季节变化作为系统消息写进来。
## 打开时释放鼠标、人物原地站定（借用 autopilot：方向为零，重力照常），关闭后恢复。
## 关闭时只显示最近 VISIBLE_SECONDS 秒内的消息并渐隐；打开时显示全部记录（最多 MAX_MESSAGES 条，可滚动）。
## 聊天名字存在 user://chat.json。由 Main 在启动时创建，不依赖场景里的固定路径。

signal message_added(entry: Dictionary)

const MAX_MESSAGES := 200
const MAX_LENGTH := 200
const MAX_NAME_LENGTH := 16
const VISIBLE_SECONDS := 10.0
const FADE_SECONDS := 1.5
const RECENT_LINES := 8
const DEFAULT_NAME := "旅人"
const SAVE_PATH := "user://chat.json"
const ACTIONS := {
	"chat_open": [KEY_T, KEY_ENTER, KEY_KP_ENTER],
	"chat_command": [KEY_SLASH],
}
const COLORS := {
	"player": Color(1.0, 1.0, 1.0),
	"emote": Color(0.95, 0.8, 1.0),
	"system": Color(1.0, 0.86, 0.45),
	"error": Color(1.0, 0.5, 0.45),
}
const NAME_COLOR := Color(0.55, 0.85, 1.0)
const WIDTH := 640.0

var player_name := DEFAULT_NAME
var messages: Array[Dictionary] = []   ## {kind, author, text, time}

var _open := false
var _history := PackedStringArray()
var _history_index := -1
var _held_player: FirstPersonController = null
var _log: RichTextLabel
var _log_bg: Panel
var _field: LineEdit
var _shown_text := ""


func _enter_tree() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in ACTIONS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)


func _ready() -> void:
	layer = 12
	add_to_group("chat_box")
	_load()
	_build()
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.season_changed.connect(_on_season_changed)
	post_system("欢迎来到暮色湖畔。按 T 聊天，输入 /help 查看命令。")


func is_open() -> bool:
	return _open


func open(prefix := "") -> void:
	if _open or get_tree().paused:
		return
	_open = true
	_history_index = -1
	_field.text = prefix
	_field.visible = true
	_log_bg.visible = true
	_log.mouse_filter = Control.MOUSE_FILTER_STOP   # 打开时可用滚轮翻看记录
	_field.grab_focus()
	_field.caret_column = prefix.length()
	_hold_player(true)
	if _can_capture():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_field.release_focus()
	_field.visible = false
	_log_bg.visible = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_player(false)
	if _can_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh()


## 发送一行输入：/ 开头交给 ChatCommands，否则作为玩家消息。
func submit(text: String) -> void:
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	if _history.is_empty() or _history[_history.size() - 1] != text:
		_history.append(text)
	if text.begins_with("/"):
		ChatCommands.run(self, text)
	else:
		post("player", player_name, text)


func post(kind: String, author: String, text: String) -> void:
	var entry := {"kind": kind, "author": author, "text": text, "time": _now()}
	messages.append(entry)
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()
	message_added.emit(entry)
	_refresh()


func post_system(text: String) -> void:
	post("system", "", text)


func post_error(text: String) -> void:
	post("error", "", text)


func clear() -> void:
	messages.clear()
	_refresh()


func set_player_name(new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name.length() > MAX_NAME_LENGTH:
		return false
	player_name = new_name
	_save()
	return true


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if _open:
		# 点输入框以外的地方等于取消
		if event is InputEventMouseButton and event.pressed:
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat_command"):
		open("/")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat_open") and not (event is InputEventWithModifiers and (event as InputEventWithModifiers).alt_pressed):
		# Alt + Enter 留给全屏切换（GameSettings）
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	if event.is_action("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP:
		_recall(-1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN:
		_recall(1)
		get_viewport().set_input_as_handled()


func _on_text_submitted(text: String) -> void:
	submit(text)
	close()


## 翻输入历史：-1 往前，+1 往后；翻过最新一条回到空行。
func _recall(step: int) -> void:
	if _history.is_empty():
		return
	var i := _history.size() if _history_index < 0 else _history_index
	i = clampi(i + step, 0, _history.size())
	_history_index = -1 if i == _history.size() else i
	_field.text = "" if _history_index < 0 else _history[_history_index]
	_field.caret_column = _field.text.length()


func _hold_player(hold: bool) -> void:
	if hold:
		var p := get_tree().get_first_node_in_group("local_player") as FirstPersonController
		if p != null and not p.autopilot_enabled:
			p.autopilot_direction = Vector3.ZERO
			p.autopilot_run = false
			p.autopilot_enabled = true
			_held_player = p
	elif _held_player != null:
		if is_instance_valid(_held_player):
			_held_player.autopilot_enabled = false
		_held_player = null


func _can_capture() -> bool:
	return DisplayServer.get_name() != "headless"


# ---------------------------------------------------------------- 系统消息

func _on_weather_changed(weather_id: StringName) -> void:
	post_system("天气转为%s。" % ClimateData.weather_profile(weather_id).get("name", String(weather_id)))


func _on_season_changed(from_id: StringName, to_id: StringName) -> void:
	if from_id != &"":
		post_system("进入%s季。" % ClimateData.season_profile(to_id).get("name", String(to_id)))


# ---------------------------------------------------------------- 显示

func _process(_delta: float) -> void:
	if not _open and not messages.is_empty() and _now() - float(messages[-1]["time"]) < VISIBLE_SECONDS + 0.1:
		_refresh()


## 重建消息文本。关闭时只取最近 RECENT_LINES 条、VISIBLE_SECONDS 秒内的消息，最后 FADE_SECONDS 秒渐隐。
func _refresh() -> void:
	if _log == null:
		return
	var lines := PackedStringArray()
	var now := _now()
	var first := 0 if _open else maxi(messages.size() - RECENT_LINES, 0)
	for i in range(first, messages.size()):
		var m: Dictionary = messages[i]
		var alpha := 1.0
		if not _open:
			var age := now - float(m["time"])
			if age > VISIBLE_SECONDS:
				continue
			alpha = clampf((VISIBLE_SECONDS - age) / FADE_SECONDS, 0.0, 1.0)
		lines.append(format_line(m, alpha))
	var text := "\n".join(lines)
	if text != _shown_text:
		_shown_text = text
		_log.text = text
	if _open:
		_log.scroll_to_line(maxi(_log.get_line_count() - 1, 0))


static func format_line(m: Dictionary, alpha := 1.0) -> String:
	var color: Color = COLORS.get(m["kind"], Color.WHITE)
	color.a = alpha
	var body := escape(str(m["text"]))
	if m["kind"] == "player":
		var name_color := NAME_COLOR
		name_color.a = alpha
		body = "[color=#%s]<%s>[/color] %s" % [name_color.to_html(), escape(str(m["author"])), body]
	return "[color=#%s]%s[/color]" % [color.to_html(), body]


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameSettings.ui_theme()
	add_child(root)

	_log_bg = Panel.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.03, 0.06, 0.55)
	bg.set_corner_radius_all(6)
	_log_bg.add_theme_stylebox_override("panel", bg)
	_log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom_left(_log_bg, 16.0, -66.0 - 286.0, -60.0)
	_log_bg.visible = false
	root.add_child(_log_bg)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 18)
	_log.add_theme_constant_override("outline_size", 5)
	_log.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	_log.add_theme_constant_override("line_separation", 2)
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_anchor_bottom_left(_log, 26.0, -66.0 - 280.0, -66.0)
	_log.offset_right -= 10.0
	root.add_child(_log)

	_field = LineEdit.new()
	_field.max_length = MAX_LENGTH
	_field.placeholder_text = "说点什么…（/help 查看命令，Esc 取消）"
	_field.context_menu_enabled = false
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.03, 0.03, 0.06, 0.78)
	field.set_corner_radius_all(6)
	field.content_margin_left = 10.0
	field.content_margin_right = 10.0
	_field.add_theme_stylebox_override("normal", field)
	_field.add_theme_stylebox_override("focus", field)
	_anchor_bottom_left(_field, 16.0, -56.0, -16.0)
	_field.visible = false
	_field.text_submitted.connect(_on_text_submitted)
	root.add_child(_field)


func _anchor_bottom_left(c: Control, left: float, top: float, bottom: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 0.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = left
	c.offset_right = left + WIDTH
	c.offset_top = top
	c.offset_bottom = bottom


# ---------------------------------------------------------------- 存档

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		var saved := str(parsed.get("name", "")).strip_edges()
		if not saved.is_empty() and saved.length() <= MAX_NAME_LENGTH:
			player_name = saved


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"name": player_name}, "  "))
