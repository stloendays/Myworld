class_name JournalPanel
extends CanvasLayer
## 旅行日志（按 J 开关，Esc 关闭）：三页——「任务」列出进行中和已完成的图腾任务及目标进度；
## 「图鉴」列出见过的动物和认出的星座（没见过的显示 ？？？，数量写在标题上）。
## 「收藏」：每个世界的探索点、收集品（云珠、古代碎片）、风灯与祭坛，以及摄影清单拍到了哪些。
## 同时负责左上角的任务追踪：进行中的任务标题和当前进度（最多 3 条，没有任务时不显示）。
## 图鉴的想法参考了 GitHub 上 bitbrain/pandora 把物品、任务、角色都当数据条目管理的做法。

var _root: Control
var _tabs: TabContainer
var _quest_box: VBoxContainer
var _dex_box: VBoxContainer
var _collect_box: VBoxContainer
var _tracker: VBoxContainer
var _tracker_panel: PanelContainer
var _player: FirstPersonController = null


func _ready() -> void:
	layer = 18
	add_to_group("journal_panel")
	_build()
	_build_tracker()
	_root.visible = false
	QuestLog.changed.connect(_refresh)
	GameRules.changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open(tab := 0) -> void:
	_player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if _player != null:
		_player.input_locked = true
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tabs.current_tab = tab
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
	if event.is_action_pressed("journal"):
		var dialog := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
		var chat := get_tree().get_first_node_in_group("chat_box")
		if (dialog != null and dialog.is_open()) or (chat != null and chat.has_method("is_open") and chat.is_open()):
			return
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 内容

func _refresh() -> void:
	if _quest_box == null:
		return
	for c in _quest_box.get_children():
		c.queue_free()
	for c in _dex_box.get_children():
		c.queue_free()
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var any := false
	for q: Dictionary in QuestLog.quests():
		var id := str(q["id"])
		var st := QuestLog.state_of(id)
		if st == "":
			continue
		any = true
		var title := _label(("✓  " if st == "done" else "◆  ") + QuestLog.text(q, "title"), 22, Color(0.75, 0.95, 0.7) if st == "done" else Color(1.0, 0.85, 0.5))
		_quest_box.add_child(title)
		for o: Dictionary in q.get("objectives", []):
			var line := "      " + QuestLog.text(o, "text")
			if st == "active" and player != null:
				var p := QuestLog.objective_progress(o, player)
				line += "   %d / %d" % [p.x, p.y]
			_quest_box.add_child(_label(line, 18, Color(0.92, 0.9, 0.86)))
	var left := 0
	for q: Dictionary in QuestLog.quests():
		if QuestLog.state_of(str(q["id"])) == "":
			left += 1
	if not any:
		_quest_box.add_child(_label(tr("还没有任务。去北边山洞里找老图腾说说话。"), 20, Color(0.92, 0.9, 0.86)))
	if left > 0:
		_quest_box.add_child(_label(tr("还有 %d 个任务，老图腾会一个一个告诉你。") % left, 18, Color(0.8, 0.78, 0.74)))
	# 图鉴：动物（陆地 + 水里）与星座
	var seen: Array = WorldState.journal_list("species")
	var all_species := (FaunaData.data().get("species", {}) as Dictionary).keys()
	all_species.erase("fairy")
	_dex_box.add_child(_label(tr("动物  %d / %d") % [seen.filter(func(s: String) -> bool: return s in all_species).size(), all_species.size()], 22, Color(1.0, 0.85, 0.5)))
	_dex_box.add_child(_grid(all_species.map(func(s: String) -> String: return QuestLog.species_label(s) if s in seen else "？？？")))
	var stars: Array = WorldState.journal_list("constellations")
	var all_stars := StarField.constellations()
	_dex_box.add_child(_label(tr("星座  %d / %d") % [stars.size(), all_stars.size()], 22, Color(1.0, 0.85, 0.5)))
	_dex_box.add_child(_grid(all_stars.map(func(c: Dictionary) -> String: return QuestLog.text(c, "name") if str(c["id"]) in stars else "？？？")))
	_refresh_collection()
	_refresh_tracker(player)


func _refresh_tracker(player: FirstPersonController) -> void:
	for c in _tracker.get_children():
		c.queue_free()
	var ids := QuestLog.active_ids() if GameRules.flag("quests") and GameRules.flag("hud_tracker") else []
	_tracker_panel.visible = not ids.is_empty()
	for id: String in ids.slice(0, 3):
		var q := QuestLog.get_quest(id)
		_tracker.add_child(_label(QuestLog.text(q, "title"), 20, Color(1.0, 0.85, 0.5), true))
		for o: Dictionary in q.get("objectives", []):
			var line := QuestLog.text(o, "text")
			if player != null:
				var p := QuestLog.objective_progress(o, player)
				if p.y > 1:
					line += "  %d/%d" % [p.x, p.y]
			_tracker.add_child(_label("  " + line, 17, Color(0.95, 0.93, 0.9), true))


func _process(_delta: float) -> void:
	# 进度（比如走到哪了）随时在变：每秒刷新一次追踪栏
	if Engine.get_process_frames() % 60 == 0 and _tracker_panel.visible:
		_refresh_tracker(get_tree().get_first_node_in_group("local_player") as FirstPersonController)


func _label(text: String, size: int, color: Color, shadow := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _grid(names: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	for n: String in names:
		var l := _label(n, 18, Color(0.92, 0.9, 0.86) if n != "？？？" else Color(0.6, 0.58, 0.56))
		l.custom_minimum_size = Vector2(150.0, 0.0)
		g.add_child(l)
	return g


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900.0, 560.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(tr("旅行日志"), 28, Color(1.0, 0.92, 0.75))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_label(tr("J / Esc  关闭"), 16, Color(0.85, 0.82, 0.76)))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	_quest_box = _page(tr("任务"))
	_dex_box = _page(tr("图鉴"))
	_collect_box = _page(tr("收藏"))


func _page(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _build_tracker() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_tracker_panel = PanelContainer.new()
	_tracker_panel.position = Vector2(20.0, 110.0)
	_tracker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.45)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 10.0
	_tracker_panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(_tracker_panel)
	_tracker = VBoxContainer.new()
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.add_theme_constant_override("separation", 2)
	_tracker_panel.add_child(_tracker)


## 收藏页：各世界的探索点和收集品进度、摄影清单。
func _refresh_collection() -> void:
	for c in _collect_box.get_children():
		c.queue_free()
	var head := Color(1.0, 0.85, 0.5)
	var body := Color(0.92, 0.9, 0.86)
	_collect_box.add_child(_label(tr("探索点"), 22, head))
	var lake_found := 0
	for poi in Exploration.pois():
		if StringName(poi["id"]) in WorldState.discoveries:
			lake_found += 1
	var lines := ["%s  %d / %d" % [tr("暮色湖畔"), lake_found, Exploration.pois().size()]]
	for wid in ["world_02", "world_03"]:
		var pois: Array = MiniWorld.data_for(wid).get("pois", [])
		var found := pois.filter(func(p: Dictionary) -> bool: return StringName(p["id"]) in WorldState.discoveries).size()
		lines.append("%s  %d / %d" % [tr(str(WorldRegistry.get_world(wid).get("name", wid))), found, pois.size()])
	_collect_box.add_child(_label("      " + "      ".join(lines), 18, body))
	_collect_box.add_child(_label(tr("收集品"), 22, head))
	var lit := 0
	for uid in WorldState.interactables:
		if str(uid).begins_with("cs_beacon_") and str(WorldState.interactables[uid]) == "lit":
			lit += 1
	var altar := str(WorldState.interactables.get(&"du_altar", "placed:0"))
	var placed := int(altar.get_slice(":", 1)) if altar.begins_with("placed:") else 0
	var cs: Dictionary = MiniWorld.data_for("world_02")
	var du: Dictionary = MiniWorld.data_for("world_03")
	_collect_box.add_child(_label("      " + tr("云海浮岛：云珠 %d / %d · 风灯 %d / %d") % [WorldState.collected("world_02").size(), (cs.get("items", []) as Array).size(), lit, (cs.get("beacons", []) as Array).size()], 18, body))
	_collect_box.add_child(_label("      " + tr("琥珀沙丘：古代碎片 %d / %d · 祭坛 %d / %d") % [WorldState.collected("world_03").size(), (du.get("items", []) as Array).size(), placed, (du.get("items", []) as Array).size()], 18, body))
	var shots: Array = WorldState.journal_list("photos")
	var all := PhotoList.subjects()
	_collect_box.add_child(_label(tr("摄影清单  %d / %d（F12 拍照时画面中央的东西）") % [shots.size(), all.size()], 22, head))
	_collect_box.add_child(_grid(all.map(func(s: Dictionary) -> String: return PhotoList.label(s) if str(s["id"]) in shots else "？？？")))
