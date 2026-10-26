class_name Cutscene
extends CanvasLayer
## 过场动画：上下电影黑边，镜头一段一段移动，每段可带一两行字幕或一个居中大标题，段与段之间短暂黑场；
## 任意键或鼠标键跳过。开场过场（IntroCutscene）和剧情过场（data/story/cutscenes.json）共用这一套。
## 一段镜头（shot）的字段：
##   seconds、fov；
##   anchor：锚点名，由播放方的 resolver 给出位置（Vector3）或带朝向的变换（Transform3D）；
##   from → to：镜头位置，look_from → look_to：视线目标。数组 = 相对 anchor 的偏移（anchor 是 Transform3D 时按它的朝向转），
##     没有 anchor 时就是世界坐标；字符串 = 另一个锚点（每帧重新取，跟得住会动的东西，例如天鲸）；
##     "player" / "player_look" = 玩家的眼睛 / 视线前方 20 m；
##   captions：[{text, text_en}] 这一段里依次出现的字幕；title：{text, text_en, sub, sub_en} 居中的大标题；
##   cue：这一段开始时发 cue 信号（例如让新星座一颗一颗亮起来）；cut：true = 和上一段之间不黑场。
## 过场整体可以带 music（一段写好的配乐，MusicDirector.play_theme）。
## 过场期间隐藏其他界面、人物站定、锁住鼠标环视，结束后全部恢复，发 finished。

signal finished
signal cue(name: String)

const DATA_PATH := "res://data/story/cutscenes.json"
const BAR := 0.11            ## 黑边高度（占屏幕高度）
const SKIP_DELAY := 0.6      ## 开始多久后才接受“跳过”（避免触发时残留的按键直接跳过）

var playing := false
var skipped := false
var shot_index := -1         ## 正在放第几段（自动检查、截图工具读）
var shot_t := 0.0            ## 这一段放了几秒
var caption_text := ""       ## 现在屏幕上的字幕
var text_vars: Dictionary = {}   ## 字幕里 {名字} 换成的文字
var music_theme := ""            ## 配乐（data/audio/music.json → themes），过场开始时放、结束时淡出
var missing := PackedStringArray()   ## 找不到的锚点（自动检查读）

var _cam: Camera3D
var _top: ColorRect
var _bottom: ColorRect
var _title: Label
var _subtitle: Label
var _caption: Label
var _hint: Label
var _elapsed := 0.0
var _hidden_layers: Array[CanvasLayer] = []
var _player: FirstPersonController = null
var _resolver := Callable()

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func shots_of(id: String) -> Array:
	return (data().get(id, {}) as Dictionary).get("shots", [])


## 有没有过场正在放（其他界面据此不弹出、剧情不再触发）。
static func any_playing(tree: SceneTree) -> bool:
	for c in tree.get_nodes_in_group("cutscene"):
		if (c as Cutscene).playing:
			return true
	return false


## 在 root 下放一段剧情过场（cutscenes.json 里的 id），放完自己删掉；返回节点，可 await 它的 finished。
## resolver(name) 返回锚点的 Vector3 / Transform3D；on_cue(name) 接每段开头的 cue。vars 填进字幕里的 {名字}（例如新星座那行字）。
static func run(root: Node, id: String, resolver := Callable(), on_cue := Callable(), vars := {}) -> Cutscene:
	var cs := Cutscene.new()
	cs.text_vars = vars
	cs.music_theme = str((data().get(id, {}) as Dictionary).get("music", ""))
	cs.name = "Cutscene_" + id
	root.add_child(cs)
	if on_cue.is_valid():
		cs.cue.connect(on_cue)
	cs.finished.connect(cs.queue_free)
	cs.play_shots(root, shots_of(id), resolver)
	return cs


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("cutscene")
	_build()
	visible = false


## 放一组镜头（可 await）。main 为当前世界的根节点；没有玩家或没有镜头时直接结束。
func play_shots(main: Node, list: Array, resolver := Callable()) -> void:
	_player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if _player == null or list.is_empty():
		finished.emit()
		return
	_resolver = resolver
	playing = true
	skipped = false
	_elapsed = 0.0
	PlayerHold.set_held(self, get_tree(), true)
	_player.input_locked = true
	if music_theme != "":
		Sound.music.play_theme(music_theme)
	if not Fade.is_black():
		await Fade.fade_out(0.4)
	visible = true
	_hide_other_layers(main)
	_cam = Camera3D.new()
	_cam.name = "CutsceneCamera"
	_cam.near = 0.1
	_cam.far = 2000.0
	_cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
	main.add_child(_cam)
	_cam.current = true

	for i in list.size():
		if skipped:
			break
		var shot: Dictionary = list[i]
		shot_index = i
		shot_t = 0.0
		_cam.fov = float(shot.get("fov", 65.0))
		_place(shot, 0.0)
		if shot.has("cue"):
			cue.emit(str(shot["cue"]))
		if i == 0:
			Fade.fade_in(1.2)
		elif not shot.get("cut", false):
			Fade.fade_in(0.5)
		var seconds := float(shot.get("seconds", 6.0))
		while shot_t < seconds and not skipped:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			shot_t += dt
			_elapsed += dt
			_place(shot, clampf(shot_t / seconds, 0.0, 1.0))
			_bars(minf(_elapsed / 1.2, 1.0))
			_text(shot, shot_t, seconds)
		var next_cut: bool = i + 1 < list.size() and (list[i + 1] as Dictionary).get("cut", false)
		if not skipped and i < list.size() - 1 and not next_cut:
			await Fade.fade_out(0.35)
	await _finish()


## 镜头在这一段里的位置与朝向（k = 0..1，两头缓动）。
func _place(shot: Dictionary, k: float) -> void:
	var anchor: Variant = null
	if shot.has("anchor"):
		anchor = _anchor(str(shot["anchor"]))
	var e := smoothstep(0.0, 1.0, k)
	var eye := _point(shot["from"], anchor).lerp(_point(shot["to"], anchor), e)
	var look := _point(shot["look_from"], anchor).lerp(_point(shot["look_to"], anchor), e)
	_cam.global_position = eye
	if eye.distance_to(look) > 0.01:
		var up := Vector3.UP if absf((look - eye).normalized().y) < 0.995 else Vector3.FORWARD
		_cam.look_at(look, up)


func _point(v: Variant, anchor: Variant) -> Vector3:
	if v is String:
		var a: Variant = _anchor(v)
		return (a as Transform3D).origin if a is Transform3D else a
	var off := Vector3(float(v[0]), float(v[1]), float(v[2]))
	if anchor is Transform3D:
		return (anchor as Transform3D) * off
	if anchor is Vector3:
		return (anchor as Vector3) + off
	return off


func _anchor(id: String) -> Variant:
	if id == "player" or id == "player_look":
		var cam := _player.camera
		return cam.global_position if id == "player" else cam.global_position - cam.global_basis.z * 20.0
	if _resolver.is_valid():
		var a: Variant = _resolver.call(id)
		if a is Vector3 or a is Transform3D:
			return a
	if not id in missing:
		missing.append(id)
		push_warning("Cutscene: 找不到锚点 %s" % id)
	return Vector3.ZERO


func _finish() -> void:
	if not Fade.is_black():
		await Fade.fade_out(0.45)
	if music_theme != "":
		Sound.music.end_theme()
	_bars(0.0)
	for l in [_title, _subtitle, _caption, _hint]:
		(l as Label).modulate.a = 0.0
	caption_text = ""
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if is_instance_valid(_player):
		_player.camera.current = true
		_player.input_locked = false
	PlayerHold.set_held(self, get_tree(), false)
	_restore_layers()
	visible = false
	playing = false
	shot_index = -1
	Fade.fade_in(0.8)
	finished.emit()


func _input(event: InputEvent) -> void:
	if not playing:
		return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if press:
		get_viewport().set_input_as_handled()
		if _elapsed >= SKIP_DELAY:
			skip()
	elif event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func skip() -> void:
	skipped = true


# ---------------------------------------------------------------- 界面

func _bars(k: float) -> void:
	var h := BAR * k
	_top.anchor_bottom = h
	_bottom.anchor_top = 1.0 - h


## 标题在这一段 1.5 秒后淡入、结束前淡出；字幕把这一段平分，每行在自己那一份里淡入淡出。
func _text(shot: Dictionary, t: float, seconds: float) -> void:
	var a := 0.0
	var title: Dictionary = shot.get("title", {})
	if not title.is_empty():
		_title.text = QuestLog.text(title, "text")
		_subtitle.text = QuestLog.text(title, "sub")
		a = clampf((t - 1.5) / 1.6, 0.0, 1.0) * clampf((seconds - t) / 1.2, 0.0, 1.0)
	_title.modulate.a = a
	_subtitle.modulate.a = clampf(a * 1.2 - 0.2, 0.0, 1.0)
	var captions: Array = shot.get("captions", [])
	caption_text = ""
	var ca := 0.0
	if not captions.is_empty():
		var part := seconds / captions.size()
		var i := mini(int(t / part), captions.size() - 1)
		var local := t - part * i
		caption_text = QuestLog.text(captions[i], "text").format(text_vars)
		ca = clampf((local - 0.25) / 0.6, 0.0, 1.0) * clampf((part - local) / 0.5, 0.0, 1.0)
	_caption.text = caption_text
	_caption.modulate.a = ca
	_hint.modulate.a = clampf((_elapsed - 1.0) / 0.8, 0.0, 0.75)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameSettings.ui_theme()
	add_child(root)
	_top = _bar_rect()
	_top.anchor_top = 0.0
	_top.anchor_bottom = 0.0
	root.add_child(_top)
	_bottom = _bar_rect()
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	root.add_child(_bottom)

	_title = _label(84, Color(1.0, 0.93, 0.82), 10)
	_center(_title, 0.40)
	root.add_child(_title)
	_subtitle = _label(26, Color(1.0, 0.88, 0.76), 6)
	_center(_subtitle, 0.50)
	root.add_child(_subtitle)
	# 字幕：下黑边上方，太宽时自动换行
	_caption = _label(30, Color(1.0, 0.95, 0.88), 8)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.anchor_left = 0.12
	_caption.anchor_right = 0.88
	_caption.anchor_top = 0.8
	_caption.anchor_bottom = 0.8
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_caption)

	_hint = Label.new()
	_hint.text = "按任意键跳过"
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.92, 0.88, 0.84))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -360.0
	_hint.offset_right = -28.0
	_hint.offset_top = -64.0
	_hint.offset_bottom = -30.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_hint)
	for l in [_title, _subtitle, _caption, _hint]:
		(l as Label).modulate.a = 0.0
		(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE


## 标题、字幕的文字已经按界面语言取好，不再自动翻译。
func _label(size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.12, 0.55))
	return l


func _bar_rect() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _center(l: Label, y: float) -> void:
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = y
	l.anchor_bottom = y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_vertical = Control.GROW_DIRECTION_BOTH


## 过场期间把世界根节点下的其他界面（HUD、小地图、聊天框……）藏起来，结束后按原样恢复。
func _hide_other_layers(main: Node) -> void:
	_hidden_layers.clear()
	for c in main.get_children():
		if c is CanvasLayer and c != self and (c as CanvasLayer).visible:
			(c as CanvasLayer).visible = false
			_hidden_layers.append(c)


func _restore_layers() -> void:
	for c in _hidden_layers:
		if is_instance_valid(c):
			c.visible = true
	_hidden_layers.clear()
