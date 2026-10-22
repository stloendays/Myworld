class_name LobbyMenu
extends CanvasLayer
## 大厅菜单（Main 启动时创建）：
##   · 启动页：名字、单人游戏 / 创建房间 / 加入房间、语言、退出；湖畔在背后照常运行；
##   · 加入页：输入房间号（或 IP），显示连接进度与失败原因；
##   · 房间页：房间号（可复制）、端口状态、玩家名单、离开房间。暂停菜单里的“多人房间”也打开这一页。
## 打开时释放鼠标、人物站定；不暂停世界（联机时世界不能停）。
## 只在 Main 是当前主场景时自动弹出（自动检查、截图工具里不弹）；命令行 -- --skip-menu 也可跳过，
## -- --host 直接建房，-- --join <房间号> 直接加入。

enum Page { HOME, JOIN, ROOM }

var _root: Control
var _panel: PanelContainer
var _pages := {}
var _page := Page.HOME
var _open := false

var _name_edit: LineEdit
var _lang: OptionButton
var _update_box: PanelContainer
var _update_label: Label
var _update_button: Button
var _update_bar: ProgressBar
var _code_edit: LineEdit
var _join_status: Label
var _join_button: Button
var _room_title: Label
var _primary_code: Label
var _copy_button: Button
var _codes_box: VBoxContainer
var _upnp_label: Label
var _players_label: Label
var _room_offline: Control
var _room_online: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	add_to_group("lobby_menu")
	_build()
	_root.visible = false
	Net.state_changed.connect(_on_net_state)
	Net.roster_changed.connect(_refresh_room)
	Net.room_codes_changed.connect(_refresh_room)
	Net.notice.connect(_on_notice)
	var args := OS.get_cmdline_user_args()
	var auto := get_tree().current_scene == get_parent() and not args.has("--skip-menu")
	if args.has("--host"):
		_host()
	elif args.has("--join") and args.find("--join") + 1 < args.size():
		_code_edit.text = args[args.find("--join") + 1]
		open(Page.JOIN)
		_join()
	elif auto:
		open(Page.HOME)


func is_open() -> bool:
	return _open


func open(page := Page.HOME) -> void:
	_open = true
	_root.visible = true
	_lang.select(maxi(GameSettings.LANGUAGES.find(GameSettings.language), 0))
	_show(page)
	PlayerHold.set_held(self, get_tree(), true)
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_room() -> void:
	open(Page.ROOM)


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	PlayerHold.set_held(self, get_tree(), false)
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("pause"):
		# 启动页没有“返回”：Esc 等于单人游戏
		if _page == Page.JOIN and Net.state == Net.State.OFFLINE:
			_show(Page.HOME)
		else:
			close()
		get_viewport().set_input_as_handled()


func _show(page: int) -> void:
	_page = page
	for p in _pages:
		(_pages[p] as Control).visible = p == page
	if page == Page.HOME:
		_name_edit.text = PlayerProfile.display_name
		_name_edit.placeholder_text = PlayerProfile.player_name()
	elif page == Page.JOIN:
		_join_status.text = ""
		_join_button.disabled = false
		_code_edit.grab_focus.call_deferred()
	_refresh_room()


# ---------------------------------------------------------------- 动作

func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	if n != "" and n != PlayerProfile.display_name:
		PlayerProfile.set_display_name(n)


func _single() -> void:
	_apply_name()
	close()


func _host() -> void:
	_apply_name()
	var err := Net.host_room()
	if err != "":
		_show(Page.HOME)
		_join_status.text = err
		return
	open(Page.ROOM)


func _join() -> void:
	_apply_name()
	var err := Net.join_room(_code_edit.text)
	if err != "":
		_join_status.text = err
		return
	_join_status.text = tr("正在连接…")
	_join_button.disabled = true


func _leave() -> void:
	Net.leave_room()
	_show(Page.ROOM)


func _copy_primary() -> void:
	var c := Net.primary_code()
	if not c.is_empty():
		DisplayServer.clipboard_set(str(c["code"]))
		_copy_button.text = tr("已复制")


func _copy(code: String) -> void:
	DisplayServer.clipboard_set(code)


func _on_language(index: int) -> void:
	GameSettings.set_value("language", GameSettings.LANGUAGES[index])
	_show(_page)


func _on_net_state(s: int) -> void:
	if s == Net.State.CLIENT and _open and _page == Page.JOIN:
		close()
	elif s == Net.State.OFFLINE and _open and _page == Page.JOIN:
		_join_button.disabled = false
		_join_status.text = Net.last_error
	_refresh_room()


func _on_notice(_text: String) -> void:
	if _open and _page == Page.JOIN and Net.state == Net.State.OFFLINE and Net.last_error != "":
		_join_status.text = Net.last_error
		_join_button.disabled = false


# ---------------------------------------------------------------- 房间页

func _refresh_room() -> void:
	if _room_title == null:
		return
	var online := Net.is_online()
	_room_offline.visible = not online
	_room_online.visible = online
	if not online:
		_room_title.text = tr("多人房间")
		return
	_room_title.text = tr("你的房间") if Net.is_host() else tr("%s 的房间") % Net.roster.get(1, {}).get("name", "?")
	var primary := Net.primary_code()
	_primary_code.text = str(primary.get("code", "—"))
	_copy_button.text = tr("复制房间号")
	_copy_button.disabled = primary.is_empty()
	for c in _codes_box.get_children():
		c.queue_free()
	if Net.is_host():
		for c in Net.room_codes:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var l := Label.new()
			l.text = "%s：%s" % [tr(_kind_label(str(c["kind"]))), c["code"]]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var b := Button.new()
			b.text = tr("复制")
			b.pressed.connect(_copy.bind(str(c["code"])))
			row.add_child(b)
			_codes_box.add_child(row)
	_upnp_label.visible = Net.is_host()
	_upnp_label.text = _upnp_text()
	var names := PackedStringArray()
	var ids := Net.roster.keys()
	ids.sort()
	for id in ids:
		var n := str(Net.roster[id].get("name", "?"))
		if id == 1:
			n += tr("（房主）")
		if id == Net.my_id():
			n += tr("（你）")
		names.append(n)
	_players_label.text = tr("玩家 %d / %d：") % [ids.size(), Net.MAX_PLAYERS] + "  ·  ".join(names)


static func _kind_label(kind: String) -> String:
	return {"internet": "公网（其他网络的朋友）", "lan": "局域网（同一个 Wi-Fi）", "vpn": "Tailscale（双方都装了 Tailscale）"}.get(kind, kind)


func _upnp_text() -> String:
	match Net.upnp_status:
		"working":
			return tr("正在尝试打开路由器端口（UPnP）…")
		"open":
			return tr("路由器端口已打开：其他网络的朋友可以用公网房间号加入。")
		"cgnat":
			return tr("你的网络没有公网 IP（运营商级 NAT），其他网络的朋友连不进来。同一个 Wi-Fi 的朋友用局域网房间号；异地朋友可以双方都装 Tailscale，再用它的房间号。")
		"failed":
			return tr("路由器拒绝打开端口。可以在路由器里手动转发 UDP %d，或改用局域网 / Tailscale 房间号。") % Net.port
		"none":
			return tr("没找到支持 UPnP 的路由器，其他网络的朋友连不进来。同一个 Wi-Fi 的朋友用局域网房间号；异地朋友可以双方都装 Tailscale，再用它的房间号。")
	return ""


# ---------------------------------------------------------------- 界面

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.86)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(30)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(560, 0)
	_panel.add_child(stack)
	_pages[Page.HOME] = _build_home()
	_pages[Page.JOIN] = _build_join()
	_pages[Page.ROOM] = _build_room()
	for p in _pages.values():
		stack.add_child(p)

	var version := Label.new()
	version.text = "Dusk Lake v%s" % Net.game_version()
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -220.0
	version.offset_top = -40.0
	version.offset_right = -16.0
	version.offset_bottom = -12.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(version)


func _build_home() -> Control:
	var box := _vbox(14)
	var title := Label.new()
	title.text = "Dusk Lake"
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "暮色湖畔 · 一片属于你的湖"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_build_update_banner())

	var name_row := _row(box, "你的名字")
	_name_edit = LineEdit.new()
	_name_edit.max_length = PlayerProfile.MAX_NAME_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)

	box.add_child(_button("单人游戏", _single))
	box.add_child(_button("创建房间", _host))
	box.add_child(_button("加入房间", open.bind(Page.JOIN)))

	var lang_row := _row(box, "语言 / Language")
	_lang = OptionButton.new()
	_lang.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for n in GameSettings.LANGUAGE_NAMES:
		_lang.add_item(n)
	_lang.select(maxi(GameSettings.LANGUAGES.find(GameSettings.language), 0))
	_lang.item_selected.connect(_on_language)
	_lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(_lang)

	box.add_child(_button("退出游戏", func() -> void: get_tree().quit()))
	return box


## 有新版本时出现在大厅首页的横幅：版本号、“更新并重启”按钮、下载进度条。
func _build_update_banner() -> Control:
	_update_box = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.32, 0.24, 0.08, 0.85)
	st.border_color = Color(0.95, 0.78, 0.4)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	_update_box.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	_update_box.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	_update_label = Label.new()
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_update_label)
	_update_button = Button.new()
	_update_button.text = "更新并重启"
	_update_button.pressed.connect(Updater.download_and_install)
	row.add_child(_update_button)
	_update_bar = ProgressBar.new()
	_update_bar.max_value = 1.0
	_update_bar.show_percentage = false
	_update_bar.custom_minimum_size = Vector2(0, 8)
	v.add_child(_update_bar)
	Updater.status_changed.connect(func(_s: int, _t: String) -> void: _sync_update())
	_sync_update()
	return _update_box


func _sync_update() -> void:
	var s := Updater.state
	_update_box.visible = s in [Updater.State.AVAILABLE, Updater.State.DOWNLOADING, Updater.State.READY] \
		or (s == Updater.State.FAILED and Updater.latest_version != "")
	_update_label.text = Updater.status_text
	_update_button.visible = s == Updater.State.AVAILABLE
	_update_bar.visible = s == Updater.State.DOWNLOADING


func _process(_delta: float) -> void:
	if _update_bar != null and _update_bar.visible:
		_update_bar.value = Updater.download_progress


func _build_join() -> Control:
	var box := _vbox(14)
	box.add_child(_title("加入房间"))
	var hint := Label.new()
	hint.text = "输入朋友发来的房间号（例如 K7Q-3MXA），也可以直接输入 IP 地址。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "房间号"
	_code_edit.add_theme_font_size_override("font_size", 28)
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	box.add_child(_code_edit)
	_join_button = _button("加入", _join)
	box.add_child(_join_button)
	_join_status = Label.new()
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55))
	box.add_child(_join_status)
	box.add_child(_button("返回", _show.bind(Page.HOME)))
	return box


func _build_room() -> Control:
	var box := _vbox(12)
	_room_title = _title("多人房间")
	box.add_child(_room_title)

	_room_offline = _vbox(12)
	var off_hint := Label.new()
	off_hint.text = "现在是单人游戏。可以创建房间请朋友来，或加入朋友的房间。"
	off_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_offline.add_child(off_hint)
	_room_offline.add_child(_button("创建房间", _host))
	_room_offline.add_child(_button("加入房间", _show.bind(Page.JOIN)))
	box.add_child(_room_offline)

	_room_online = _vbox(10)
	var code_caption := Label.new()
	code_caption.text = "房间号"
	_room_online.add_child(code_caption)
	_primary_code = Label.new()
	_primary_code.add_theme_font_size_override("font_size", 44)
	_primary_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_primary_code.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_room_online.add_child(_primary_code)
	_copy_button = _button("复制房间号", _copy_primary)
	_room_online.add_child(_copy_button)
	_codes_box = _vbox(4)
	_room_online.add_child(_codes_box)
	_upnp_label = Label.new()
	_upnp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_upnp_label.custom_minimum_size = Vector2(560, 0)
	_room_online.add_child(_upnp_label)
	var fw := Label.new()
	fw.text = "第一次建房时 Windows 可能会问是否允许 Dusk Lake 访问网络，请选择“允许”。"
	fw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fw.custom_minimum_size = Vector2(560, 0)
	fw.add_theme_font_size_override("font_size", 15)
	_room_online.add_child(fw)
	_players_label = Label.new()
	_players_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_players_label.custom_minimum_size = Vector2(560, 0)
	_room_online.add_child(_players_label)
	_room_online.add_child(_button("离开房间", _leave))
	box.add_child(_room_online)

	box.add_child(_button("回到湖畔", close))
	return box


func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


func _title(text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 30)
	return t


func _row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	parent.add_child(row)
	return row


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	return b
