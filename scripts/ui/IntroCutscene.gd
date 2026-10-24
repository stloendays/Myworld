class_name IntroCutscene
extends CanvasLayer
## 开场过场：启动加载完成后，镜头先从高处越过湖面看落日（出现标题），再贴着水面沿码头滑向木屋，
## 最后落到玩家眼睛的位置、交还给玩家相机。上下有电影黑边，段与段之间短暂黑场；任意键或鼠标键跳过。
## 镜头数据在 world_layout.json → intro（"player" 表示玩家当前的眼睛 / 视线）。
## 过场期间隐藏其他界面、人物站定、锁住鼠标环视，结束后全部恢复，发 finished。

signal finished

const BAR := 0.11            ## 黑边高度（占屏幕高度）
const SKIP_DELAY := 0.6      ## 开始多久后才接受“跳过”（避免启动时残留的按键直接跳过）

var playing := false
var skipped := false

var _cam: Camera3D
var _top: ColorRect
var _bottom: ColorRect
var _title: Label
var _subtitle: Label
var _hint: Label
var _elapsed := 0.0
var _hidden_layers: Array[CanvasLayer] = []


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


static func shots() -> Array:
	return WorldLayout.section("intro").get("shots", [])


## 播放过场（可 await）。main 为主场景；没有玩家时直接结束。
func play(main: Node) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var list := shots()
	if player == null or list.is_empty():
		finished.emit()
		return
	playing = true
	skipped = false
	_elapsed = 0.0
	visible = true
	_hide_other_layers(main)
	PlayerHold.set_held(self, get_tree(), true)
	player.input_locked = true
	_cam = Camera3D.new()
	_cam.name = "IntroCamera"
	_cam.near = 0.1
	_cam.far = 1500.0
	_cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
	main.add_child(_cam)
	_cam.current = true
	var title_shot := int(WorldLayout.section("intro").get("title_shot", 0))

	for i in list.size():
		if skipped:
			break
		var shot: Dictionary = list[i]
		var eye_to := _point(shot["to"], player, true)
		var look_to := _point(shot["look_to"], player, false)
		var eye_from := _point(shot["from"], player, true)
		var look_from := _point(shot["look_from"], player, false)
		_cam.fov = float(shot.get("fov", 65.0))
		_place(eye_from, look_from, 0.0, eye_to, look_to)
		if i == 0:
			Fade.fade_in(1.4)
		else:
			Fade.fade_in(0.5)
		var seconds := float(shot.get("seconds", 6.0))
		var t := 0.0
		while t < seconds and not skipped:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			t += dt
			_elapsed += dt
			var k := clampf(t / seconds, 0.0, 1.0)
			_place(eye_from, look_from, k, eye_to, look_to)
			_bars(minf(_elapsed / 1.2, 1.0))
			_text(i == title_shot, t, seconds)
		if not skipped and i < list.size() - 1:
			await Fade.fade_out(0.35)
	await _finish(player)


func _point(v: Variant, player: FirstPersonController, eye: bool) -> Vector3:
	if v is String and v == "player":
		var cam := player.camera
		return cam.global_position if eye else cam.global_position - cam.global_basis.z * 20.0
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


func _place(eye_from: Vector3, look_from: Vector3, k: float, eye_to: Vector3, look_to: Vector3) -> void:
	var e := smoothstep(0.0, 1.0, k)
	var eye := eye_from.lerp(eye_to, e)
	var look := look_from.lerp(look_to, e)
	_cam.global_position = eye
	if eye.distance_to(look) > 0.01:
		_cam.look_at(look, Vector3.UP)


func _finish(player: FirstPersonController) -> void:
	if not Fade.is_black():
		await Fade.fade_out(0.45)
	_bars(0.0)
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_hint.modulate.a = 0.0
	if _cam != null:
		_cam.queue_free()
		_cam = null
	player.camera.current = true
	player.input_locked = false
	PlayerHold.set_held(self, get_tree(), false)
	_restore_layers()
	visible = false
	playing = false
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


func _text(title_shot: bool, t: float, seconds: float) -> void:
	var a := 0.0
	if title_shot:
		a = clampf((t - 1.5) / 1.6, 0.0, 1.0) * clampf((seconds - t) / 1.2, 0.0, 1.0)
	_title.modulate.a = a
	_subtitle.modulate.a = clampf(a * 1.2 - 0.2, 0.0, 1.0)
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

	_title = Label.new()
	_title.text = "Dusk Lake"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_size_override("font_size", 84)
	_title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.82))
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.12, 0.55))
	_center(_title, 0.40)
	root.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = "暮色湖畔 · 一片属于你的湖"
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", Color(1.0, 0.88, 0.76))
	_subtitle.add_theme_constant_override("outline_size", 6)
	_subtitle.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.12, 0.5))
	_center(_subtitle, 0.50)
	root.add_child(_subtitle)

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
	for l in [_title, _subtitle, _hint]:
		(l as Label).modulate.a = 0.0
		(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE


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


## 过场期间把主场景里的其他界面（HUD、小地图、聊天框……）藏起来，结束后按原样恢复。
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
