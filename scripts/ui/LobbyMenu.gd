class_name LobbyMenu
extends CanvasLayer
## 大厅（Main 启动时创建；湖畔在背后照常运行）：
##   · 首页：左边一列——标题、名字；「单人游戏」两张模式卡：剧情模式（老图腾的故事、任务、信、过场和结局）和休闲模式
##     （没有任务，随便玩），各自一个存档，卡上写着进度、有“继续”和“新开始”；「多人游戏 · 休闲模式」创建 / 加入房间；
##     设置、语言、退出。右下角是版本与自动更新（正在检查 / 已是最新 / 发现新版本一键更新并重启 / 下载进度 / 失败重试）。
##   · 新的旅程（剧情）：一句开场和“会先备份”的提醒；新的休闲世界：一键预设 + 全部设定（剧情模式不在这里选）。
##   · 加入页：输入房间号（或 IP），显示连接进度与失败原因；房间页：房间号（可复制）、端口状态、玩家名单、离开房间。
## 联机只开休闲模式：创建房间时如果正在玩剧情模式，先存好剧情进度，再切到休闲世界（没有就先开一个）再建房。
## 打开时释放鼠标、人物站定；不暂停世界（联机时世界不能停）。
## 只在 Main 是当前主场景时自动弹出（自动检查、截图工具里不弹）；命令行 -- --skip-menu 也可跳过，
## -- --host 直接建房，-- --join <房间号> 直接加入。

enum Page { HOME, JOIN, ROOM, NEWGAME, STORY }

const CARD_W := 380.0

var _root: Control
var _home: Control
var _sheet: CenterContainer
var _pages := {}
var _page := Page.HOME
var _open := false

var _name_edit: LineEdit
var _lang: OptionButton
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
var _cards := {}             ## "story" / "casual" -> {info: Label, go: Button, fresh: Button}
var _story_warn: Label
## 新的休闲世界：正在编辑的整套规则、每个选项的控件、是否开局后建房
var _draft: Dictionary = {}
var _widgets := {}
var _new_for_host := false
var _mode_hint: Label
var _start_button: Button
var _new_title: Label
var _new_scroll: ScrollContainer
var _last_state := 0


func _ready() -> void:
	add_to_group(UiStyle.COVER_GROUP)
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
	var auto := get_tree().current_scene == get_parent() and not args.has("--skip-menu") and WorldTravel.arriving_from == ""
	if args.has("--host"):
		_host_casual()
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
	if not _root.visible:
		return   # 设置页开着（大厅藏起来了），Esc 交给设置页
	if _open and event.is_action_pressed("pause"):
		# 首页没有“返回”：Esc 等于接着玩（没在玩就继续最近的存档，没有存档就开始剧情模式）；其他页 Esc 回首页
		if _page in [Page.NEWGAME, Page.STORY] or (_page == Page.JOIN and Net.state == Net.State.OFFLINE):
			_show(Page.HOME)
		elif _page == Page.HOME and not SaveManager.active and not Net.is_online():
			_quick_start()
		else:
			close()
		get_viewport().set_input_as_handled()


func _show(page: int) -> void:
	_page = page
	_home.visible = page == Page.HOME
	_sheet.visible = page != Page.HOME
	for p in _pages:
		(_pages[p] as Control).visible = p == page
	match page:
		Page.HOME:
			_name_edit.text = PlayerProfile.display_name
			_name_edit.placeholder_text = PlayerProfile.player_name()
			_refresh_cards()
		Page.NEWGAME:
			_refresh_new_game()
		Page.STORY:
			_refresh_story_page()
		Page.JOIN:
			_join_status.text = ""
			_join_button.disabled = false
			_code_edit.grab_focus.call_deferred()
	_refresh_room()


# ---------------------------------------------------------------- 动作

func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	if n != "" and n != PlayerProfile.display_name:
		PlayerProfile.set_display_name(n)


## 继续某个模式的存档；正在玩的就是这个模式时直接回到游戏。
func _continue(slot: String) -> void:
	_apply_name()
	close()
	if SaveManager.active and SaveManager.slot == slot:
		return
	if SaveManager.active:
		SaveManager.save()
	await SaveManager.continue_game(slot)


## 首页按 Esc：继续最近存过的那个模式；一个存档都没有就开始剧情模式。
func _quick_start() -> void:
	var best := ""
	var best_at := ""
	for s in ["story", "casual"]:
		var sm := SaveManager.summary(s)
		if not sm.is_empty() and (best == "" or str(sm.get("saved_at", "")) > best_at):
			best = s
			best_at = str(sm.get("saved_at", ""))
	if best != "":
		_continue(best)
		return
	_apply_name()
	close()
	await SaveManager.start_new(GameRules.story_defaults())


func _start_story() -> void:
	_apply_name()
	if SaveManager.active and SaveManager.slot != "story":
		SaveManager.save()
	close()
	await SaveManager.start_new(GameRules.story_defaults())


## 联机只开休闲模式：正在玩休闲就直接建房；否则先存好剧情进度，继续休闲存档（没有就先去新建一个休闲世界）再建房。
func _host_casual() -> void:
	_apply_name()
	if not (SaveManager.active and not GameRules.is_story()):
		if SaveManager.active:
			SaveManager.save()
		if not SaveManager.has_save_in("casual") and SaveManager.persist:
			open_new_game(true)
			return
		var was_open := _open
		close()
		if SaveManager.has_save_in("casual"):
			await SaveManager.continue_game("casual")
		else:
			await SaveManager.start_new(GameRules.casual_defaults())
		if was_open:
			open(Page.ROOM)
	_host()


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
	if SaveManager.active:
		SaveManager.save()
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


## 换语言后，自己拼出来的文字（卡上的进度、右下角的更新状态）按新语言重写一遍。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _update_label != null:
		_sync_update()
		_refresh_cards()


## 设置：大厅先藏起来，打开暂停菜单的设置页；关掉设置回到大厅。
func _open_settings() -> void:
	var pause := get_parent().get_node_or_null("PauseMenu")
	if pause == null:
		return
	_root.visible = false
	pause.call("open_settings", 0, true)
	if not pause.is_connected("closed", _on_settings_closed):
		pause.connect("closed", _on_settings_closed, CONNECT_ONE_SHOT)


func _on_settings_closed() -> void:
	if _open:
		_root.visible = true
		PlayerHold.set_held(self, get_tree(), true)
		if GameSettings.can_grab_mouse():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_show(_page)


func _on_net_state(s: int) -> void:
	# 进出别人的房间时世界（时间、天气、门）会一下子跳变：用黑幕盖住这一下
	if s == Net.State.CLIENT and _last_state != Net.State.CLIENT:
		Fade.flash(tr("来到 %s 的湖畔") % Net.roster.get(1, {}).get("name", "?"))
	elif s == Net.State.OFFLINE and _last_state == Net.State.CLIENT:
		Fade.flash(tr("回到你自己的湖畔"))
	_last_state = s
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


# ---------------------------------------------------------------- 首页

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	# 左边压暗、往右渐渐透出背后的湖（标题和按钮在左边，画面在右边）
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.03, 0.02, 0.06, 0.9), Color(0.03, 0.02, 0.06, 0.72), Color(0.03, 0.02, 0.06, 0.25), Color(0.03, 0.02, 0.06, 0.1)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	_root.add_child(shade)

	_home = _build_home()
	_root.add_child(_home)

	_sheet = CenterContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_sheet)
	var panel := PanelContainer.new()
	_sheet.add_child(panel)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(600, 0)
	panel.add_child(stack)
	_pages[Page.JOIN] = _build_join()
	_pages[Page.ROOM] = _build_room()
	_pages[Page.NEWGAME] = _build_new_game()
	_pages[Page.STORY] = _build_story_page()
	for p in _pages.values():
		stack.add_child(p)
	_root.add_child(_build_update_strip())


func _build_home() -> Control:
	var margin := MarginContainer.new()
	margin.anchor_top = 0.0
	margin.anchor_bottom = 1.0
	margin.anchor_left = 0.0
	margin.anchor_right = 0.0
	margin.offset_right = 900.0
	margin.add_theme_constant_override("margin_left", 84)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	# 窗口太矮（或英文说明较长）放不下时可以上下滚动，底下那排按钮不会被挤出屏幕
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "Dusk Lake"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size", 66)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.84))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.12, 0.6))
	col.add_child(title)
	var sub := UiStyle.title("暮色湖畔 · 一片属于你的湖", 24, UiStyle.ACCENT)
	col.add_child(sub)
	col.add_child(_spacer(8))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	var nl := Label.new()
	nl.text = "你的名字"
	nl.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.max_length = PlayerProfile.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(300, 0)
	name_row.add_child(_name_edit)
	col.add_child(name_row)

	col.add_child(_section("单人游戏"))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	cards.add_child(_mode_card("story", "剧情模式", "跟着老图腾的托付，去门后的世界把熄了的光送回去。有任务、信、过场动画和结局。",
		"继续旅程", "新的旅程", _show.bind(Page.STORY)))
	cards.add_child(_mode_card("casual", "休闲模式", "没有任务，想怎么玩就怎么玩：钓鱼、看星星、换季节，还能和朋友联机。",
		"继续", "新的世界…", open_new_game.bind(false)))
	col.add_child(cards)

	col.add_child(_section("多人游戏 · 休闲模式"))
	var mp := HBoxContainer.new()
	mp.add_theme_constant_override("separation", 12)
	var host := _button("创建房间", _host_casual)
	host.custom_minimum_size = Vector2(CARD_W, 46)
	mp.add_child(host)
	var join := _button("加入房间", open.bind(Page.JOIN))
	join.custom_minimum_size = Vector2(CARD_W, 46)
	mp.add_child(join)
	col.add_child(mp)

	col.add_child(_spacer(6))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.add_child(_button("设置", _open_settings))
	_lang = OptionButton.new()
	_lang.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for n in GameSettings.LANGUAGE_NAMES:
		_lang.add_item(n)
	_lang.select(maxi(GameSettings.LANGUAGES.find(GameSettings.language), 0))
	_lang.item_selected.connect(_on_language)
	_lang.custom_minimum_size = Vector2(220, 46)
	_lang.tooltip_text = "语言 / Language"
	bottom.add_child(_lang)
	bottom.add_child(_button("退出游戏", func() -> void: get_tree().quit()))
	col.add_child(bottom)
	return margin


## 一张模式卡：名字、一句说明、存档进度；“继续”（有存档时是主按钮）和“新开始”。
func _mode_card(slot: String, title_text: String, desc: String, go_text: String, fresh_text: String, fresh: Callable) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_" + slot
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.add_theme_stylebox_override("panel", UiStyle.card(slot == "story"))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(UiStyle.title(title_text, 26, UiStyle.ACCENT if slot == "story" else UiStyle.MOON))
	var d := UiStyle.hint(desc, 16)
	d.custom_minimum_size = Vector2(CARD_W - 40.0, 0)
	v.add_child(d)
	var info := UiStyle.hint("", 15)
	info.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	v.add_child(info)
	var go := _button(go_text, _continue.bind(slot))
	go.name = "Continue_" + slot
	UiStyle.primary(go)
	v.add_child(go)
	var again := _button(fresh_text, fresh)
	again.name = "New_" + slot
	v.add_child(again)
	_cards[slot] = {"info": info, "go": go, "fresh": again}
	return card


## 卡上的进度：正在玩 / 世界、第几天、时刻、完成了几个任务；没有存档时“还没有开始”。
func _refresh_cards() -> void:
	for slot: String in _cards:
		var c: Dictionary = _cards[slot]
		var s := SaveManager.summary(slot)
		var playing := SaveManager.active and SaveManager.slot == slot and not Net.is_client()
		(c["go"] as Button).visible = not s.is_empty() or playing
		(c["go"] as Button).text = tr("回到游戏") if playing else (tr("继续旅程") if slot == "story" else tr("继续"))
		var info := c["info"] as Label
		if s.is_empty():
			info.text = tr("还没有开始")
		elif s.get("legacy", false):
			info.text = tr("接着 v0.4 的任务和图鉴，从秋天黄昏的湖畔开始")
		else:
			var w := WorldRegistry.get_world(str(s["world"]))
			var m := int(s["minutes"])
			info.text = tr("%s · 第 %d 天 %02d:%02d") % [tr(str(w.get("name", s["world"]))), int(s["day"]), m / 60, m % 60]
			if slot == "story":
				info.text += "  ·  " + tr("任务 %d / %d") % [int(s.get("quests_done", 0)), QuestLog.quests().size()]
			else:
				info.text += "  ·  " + tr(_choice_label("mode", s["mode"]))
		if playing:
			info.text = tr("正在玩") + "  ·  " + info.text


func _section(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_spacer(6))
	var l := UiStyle.title(text, 19, UiStyle.TEXT_SOFT)
	v.add_child(l)
	v.add_child(UiStyle.rule())
	return v


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# ---------------------------------------------------------------- 版本与自动更新

## 右下角：版本号和更新状态（正在检查 / 已是最新 / 发现新版本 → 更新并重启 / 下载进度 / 失败重试）。
func _build_update_strip() -> Control:
	var strip := PanelContainer.new()
	strip.name = "UpdateStrip"
	strip.add_theme_stylebox_override("panel", UiStyle.pill(0.78))
	strip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_right = -24.0
	strip.offset_bottom = -20.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	strip.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_update_label = Label.new()
	_update_label.add_theme_font_size_override("font_size", 16)
	_update_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	_update_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_update_label)
	_update_button = Button.new()
	_update_button.name = "UpdateButton"
	_update_button.pressed.connect(_on_update_button)
	row.add_child(_update_button)
	_update_bar = ProgressBar.new()
	_update_bar.max_value = 1.0
	_update_bar.show_percentage = false
	_update_bar.custom_minimum_size = Vector2(0, 8)
	v.add_child(_update_bar)
	Updater.status_changed.connect(func(_s: int, _t: String) -> void: _sync_update())
	Updater.old_versions_removed.connect(func(_l: Array) -> void: _sync_update())
	_sync_update()
	return strip


func _sync_update() -> void:
	var s := Updater.state
	var ver := "v%s" % Updater.current_version()
	var text := ""
	var action := ""
	match s:
		Updater.State.CHECKING:
			text = tr("正在检查更新…")
		Updater.State.UP_TO_DATE:
			text = tr("已是最新版本")
			action = "check"
		Updater.State.AVAILABLE:
			text = tr("发现新版本 v%s") % Updater.latest_version
			action = "update"
		Updater.State.DOWNLOADING:
			text = tr("正在下载新版本…")
		Updater.State.READY:
			text = Updater.status_text
		Updater.State.FAILED:
			text = Updater.status_text
			action = "check"
		_:
			if not Updater.can_self_update():
				text = tr("开发版本，不检查更新")
			elif not GameSettings.auto_update_check:
				text = tr("自动检查更新已关闭")
				action = "check"
			else:
				text = tr("即将检查更新")
	if Updater.old_versions_note() != "":
		text += "  ·  " + Updater.old_versions_note()
	_update_label.text = "Dusk Lake " + ver + "  ·  " + text
	_update_button.visible = action != ""
	_update_button.set_meta("action", action)
	_update_button.text = tr("更新并重启") if action == "update" else (tr("重试") if s == Updater.State.FAILED else tr("检查更新"))
	if action == "update":
		UiStyle.primary(_update_button)
	_update_bar.visible = s == Updater.State.DOWNLOADING


func _on_update_button() -> void:
	match str(_update_button.get_meta("action", "")):
		"update":
			Updater.download_and_install()
		"check":
			Updater.check()


func _process(_delta: float) -> void:
	if _update_bar != null and _update_bar.visible:
		_update_bar.value = Updater.download_progress


# ---------------------------------------------------------------- 加入 / 房间

func _build_join() -> Control:
	var box := _vbox(14)
	box.add_child(UiStyle.title("加入房间"))
	var hint := UiStyle.hint("输入朋友发来的房间号（例如 K7Q-3MXA），也可以直接输入 IP 地址。联机都在休闲模式里玩。", 17)
	box.add_child(hint)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "房间号"
	_code_edit.add_theme_font_size_override("font_size", 30)
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	box.add_child(_code_edit)
	_join_button = UiStyle.primary(_button("加入", _join))
	box.add_child(_join_button)
	_join_status = Label.new()
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.add_theme_color_override("font_color", UiStyle.ACCENT)
	box.add_child(_join_status)
	box.add_child(_button("返回", _show.bind(Page.HOME)))
	return box


func _build_room() -> Control:
	var box := _vbox(12)
	_room_title = UiStyle.title("多人房间")
	box.add_child(_room_title)

	_room_offline = _vbox(12)
	_room_offline.add_child(UiStyle.hint("现在是单人游戏。可以创建房间请朋友来，或加入朋友的房间。联机只开休闲模式：正在玩剧情模式的话，会先存好剧情进度，再换到你的休闲世界。", 17))
	_room_offline.add_child(UiStyle.primary(_button("创建房间", _host_casual)))
	_room_offline.add_child(_button("加入房间", _show.bind(Page.JOIN)))
	box.add_child(_room_offline)

	_room_online = _vbox(10)
	var code_caption := Label.new()
	code_caption.text = "房间号"
	code_caption.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	_room_online.add_child(code_caption)
	_primary_code = Label.new()
	_primary_code.add_theme_font_size_override("font_size", 46)
	_primary_code.add_theme_color_override("font_color", UiStyle.ACCENT)
	_primary_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_primary_code.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_room_online.add_child(_primary_code)
	_copy_button = UiStyle.primary(_button("复制房间号", _copy_primary))
	_room_online.add_child(_copy_button)
	_codes_box = _vbox(4)
	_room_online.add_child(_codes_box)
	_upnp_label = UiStyle.hint("", 16)
	_upnp_label.custom_minimum_size = Vector2(560, 0)
	_room_online.add_child(_upnp_label)
	var fw := UiStyle.hint("第一次建房时 Windows 可能会问是否允许 Dusk Lake 访问网络，请选择“允许”。", 15)
	fw.custom_minimum_size = Vector2(560, 0)
	_room_online.add_child(fw)
	_players_label = Label.new()
	_players_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_players_label.custom_minimum_size = Vector2(560, 0)
	_room_online.add_child(_players_label)
	_room_online.add_child(_button("离开房间", _leave))
	box.add_child(_room_online)

	box.add_child(_button("回到湖畔", close))
	return box


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


func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- 新的旅程（剧情）

func _build_story_page() -> Control:
	var box := _vbox(14)
	box.add_child(UiStyle.title("新的旅程"))
	var intro := UiStyle.hint("秋天的黄昏，你来到一片湖边。北边的山洞里，守着篝火的老图腾在等一个旅人。", 18)
	intro.custom_minimum_size = Vector2(580, 0)
	box.add_child(intro)
	_story_warn = UiStyle.hint("", 16)
	_story_warn.custom_minimum_size = Vector2(580, 0)
	_story_warn.add_theme_color_override("font_color", UiStyle.ACCENT)
	box.add_child(_story_warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := _button("返回", _show.bind(Page.HOME))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	var go := UiStyle.primary(_button("开始新的旅程", _start_story))
	go.name = "StartStory"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)
	box.add_child(row)
	return box


func _refresh_story_page() -> void:
	var s := SaveManager.summary("story")
	_story_warn.visible = not s.is_empty()
	if not s.is_empty():
		_story_warn.text = tr("剧情模式已经有一段进度（第 %d 天，任务 %d / %d）。开始新的旅程会先把它备份，再从头开始。") % [int(s.get("day", 1)),
			int(s.get("quests_done", 0)), QuestLog.quests().size()]


# ---------------------------------------------------------------- 新的休闲世界

## 打开新的休闲世界页；for_host = 开局后直接建房（联机房间目前都在暮色湖畔）。
func open_new_game(for_host: bool) -> void:
	_apply_name()
	_new_for_host = for_host
	_draft = GameRules.casual_defaults()
	if not _open:
		open(Page.NEWGAME)
	else:
		_show(Page.NEWGAME)


func _start_new() -> void:
	var rules := _draft.duplicate()
	rules["play"] = "casual"
	if _new_for_host:
		rules["spawn_world"] = "dusk_lake"
	if SaveManager.active and SaveManager.slot != "casual":
		SaveManager.save()
	close()
	await SaveManager.start_new(rules)
	if _new_for_host:
		_host()


static func _choice_label(key: String, value: Variant) -> String:
	for c: Array in GameRules.option(key).get("choices", []):
		if str(c[0]) == str(value):
			return str(c[1])
	return str(value)


## 设定页上不列的：游戏模式（模式卡已经选了）、图腾任务（休闲模式没有任务）。
static func _listed(o: Dictionary) -> bool:
	return not str(o["key"]) in ["play", "quests"]


func _build_new_game() -> Control:
	var box := _vbox(10)
	box.custom_minimum_size = Vector2(900, 0)
	_new_title = UiStyle.title("新的休闲世界")
	box.add_child(_new_title)
	var presets_label := UiStyle.title("一键预设", 18, UiStyle.TEXT_SOFT)
	box.add_child(presets_label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for p: Dictionary in GameRules.PRESETS:
		var b := Button.new()
		b.name = "Preset_" + str(p["id"])
		b.text = str(p["name"])
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(_apply_preset.bind(str(p["id"])))
		flow.add_child(b)
	box.add_child(flow)
	_mode_hint = UiStyle.hint("", 16)
	_mode_hint.custom_minimum_size = Vector2(880, 0)
	box.add_child(_mode_hint)
	# 选项：按分组排两列
	_new_scroll = ScrollContainer.new()
	_new_scroll.custom_minimum_size = Vector2(900, 440)
	_new_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_new_scroll)
	var groups := _vbox(6)
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_scroll.add_child(groups)
	for g: String in GameRules.GROUPS:
		var head := UiStyle.title(g, 20, UiStyle.ACCENT)
		groups.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 6)
		groups.add_child(grid)
		for o: Dictionary in GameRules.OPTIONS:
			if o["group"] != g or not _listed(o):
				continue
			var l := Label.new()
			l.text = str(o["label"])
			l.custom_minimum_size = Vector2(170, 0)
			l.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
			grid.add_child(l)
			grid.add_child(_option_widget(o))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := _button("返回", _show.bind(Page.HOME))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	_start_button = UiStyle.primary(_button("开始游戏", _start_new))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_start_button)
	box.add_child(row)
	return box


func _option_widget(o: Dictionary) -> Control:
	var key: String = o["key"]
	var w: Control
	match str(o["kind"]):
		"toggle":
			var cb := CheckButton.new()
			cb.toggled.connect(func(on: bool) -> void: _set_draft(key, on))
			w = cb
		"seed":
			var h := HBoxContainer.new()
			var sb := SpinBox.new()
			sb.min_value = 0
			sb.max_value = 999999
			sb.step = 1
			sb.tooltip_text = tr("0 = 世界自带的种子")
			sb.value_changed.connect(func(v: float) -> void: _set_draft(key, int(v), false))
			h.add_child(sb)
			var rb := Button.new()
			rb.text = "随机"
			rb.pressed.connect(func() -> void: _set_draft(key, randi_range(1, 999999)))
			h.add_child(rb)
			w = h
		_:
			var ob := OptionButton.new()
			ob.custom_minimum_size = Vector2(190, 0)
			ob.item_selected.connect(func(i: int) -> void: _set_draft(key, ob.get_item_metadata(i)))
			w = ob
	w.name = "Rule_" + key
	_widgets[key] = w
	return w


func _apply_preset(id: String) -> void:
	_draft = GameRules.preset_rules(id)
	_refresh_new_game()


func _set_draft(key: String, value: Variant, refresh := true) -> void:
	if key == "mode":
		_draft = GameRules.with_mode(_draft, str(value))
	else:
		_draft[key] = value
		if key == "spawn_world":
			_draft["spawn_point"] = "default"
	_draft["play"] = "casual"
	_draft = GameRules.sanitize(_draft)
	if refresh:
		_refresh_new_game.call_deferred()


## 控件跟着草稿走（模式、预设会一下改很多项；出生点的下拉随出生世界换内容；玩法风格里没有“任务冒险”）。
func _refresh_new_game() -> void:
	if _draft.is_empty():
		_draft = GameRules.casual_defaults()
	_new_title.text = tr("新的休闲世界 · 开局后创建房间") if _new_for_host else tr("新的休闲世界")
	_start_button.text = tr("开始并创建房间") if _new_for_host else tr("开始游戏")
	_mode_hint.text = tr(str(GameRules.MODE_HINTS.get(str(_draft["mode"]), "")))
	if SaveManager.has_save_in("casual"):
		_mode_hint.text += "  " + tr("（上次的休闲世界会先备份再开新的）")
	for o: Dictionary in GameRules.OPTIONS:
		if not _listed(o):
			continue
		var key: String = o["key"]
		var w: Control = _widgets[key]
		var v: Variant = _draft.get(key)
		match str(o["kind"]):
			"toggle":
				(w as CheckButton).set_pressed_no_signal(bool(v))
			"seed":
				(w.get_child(0) as SpinBox).set_value_no_signal(float(v))
			_:
				var ob := w as OptionButton
				var choices: Array = o.get("choices", [])
				if str(o["kind"]) == "spawn":
					choices = GameRules.spawn_choices(str(_draft["spawn_world"]))
				if key == "mode":
					choices = choices.filter(func(c: Array) -> bool: return str(c[0]) != "adventure")
				ob.clear()
				for c: Array in choices:
					ob.add_item(str(c[1]))
					ob.set_item_metadata(ob.item_count - 1, c[0])
					if str(c[0]) == str(v):
						ob.select(ob.item_count - 1)
				ob.disabled = key == "spawn_world" and _new_for_host
	if _new_for_host:
		(_widgets["spawn_world"] as OptionButton).tooltip_text = tr("联机房间目前都在暮色湖畔")
