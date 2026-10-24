class_name LoadingScreen
extends CanvasLayer
## 加载画面（启动时 BootLoader、跨世界旅行时 WorldTravel 共用）：暮色渐变背景、慢慢飘的萤火虫、
## 图标与标题、进度条、当前阶段文字、轮换的小提示、右下角版本号。
##   set_progress(0..1)  进度条平滑追上；shown_progress 是画面上实际显示到的值
##   set_stage("正在…")  阶段文字（中文原文，内部 tr）
##   set_title("…")      大标题下面的副标题（世界旅行时写“正在前往「…」”）
##   appear(秒) / vanish(秒)  整块淡入 / 淡出（可 await；无窗口时立即完成）
## 显示期间吞掉按键和鼠标点击，背后的暂停菜单、聊天框都不会被触发。

const TIP_SECONDS := 4.5
const TIPS := [
	"按 T 打开聊天，输入 /help 看看能做什么。",
	"右键：准星对着的东西直接就能用；什么都没对着时会挥挥手。",
	"按 G 打开动作轮盘：坐下、躺下、挥手、跳舞、鼓掌。",
	"独木舟停在码头南侧，湖上有四个地方等你去发现。",
	"晴朗的夜里，湖东南的林子里会出现仙境。",
	"从泳池深水区的池底潜下去，可以一路游进地下水族馆。",
	"木屋茶几上的棋盘可以下国际象棋。",
	"在“多人房间”里建房，把房间号发给朋友就能一起玩（最多 4 人）。",
	"东北角的雪山可以一直爬到山顶。",
	"按 Tab 打开世界地图，按 M 开关小地图。",
	"按 F12 拍照，照片存在“图片\\Dusk Lake”文件夹。",
]

var progress := 0.0
var shown_progress := 0.0
var stage := ""

var _root: Control
var _bar: ProgressBar
var _stage: Label
var _subtitle: Label
var _tip: Label
var _tip_index := 0
var _tip_time := 0.0
var _fireflies: Control


func _init() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_tip_index = randi() % TIPS.size()
	_build()


func set_progress(p: float) -> void:
	progress = clampf(maxf(progress, p), 0.0, 1.0)


## 重新开始（世界旅行每次用同一块画面）：进度清零、换一条提示。
func reset() -> void:
	progress = 0.0
	_root.modulate.a = 0.0
	shown_progress = 0.0
	_bar.value = 0.0
	_tip_index = (_tip_index + 1) % TIPS.size()
	_tip_time = 0.0
	_tip.text = tr(TIPS[_tip_index])


func set_stage(text: String) -> void:
	stage = text
	_stage.text = tr(text)
	print("LoadingScreen: %s (%d ms)" % [text, Time.get_ticks_msec()])


func set_title(text: String) -> void:
	_subtitle.text = text


func appear(seconds := 0.4) -> void:
	visible = true
	await _fade_root(1.0, seconds)


func vanish(seconds := 0.5) -> void:
	await _fade_root(0.0, seconds)
	visible = false


func _fade_root(target: float, seconds: float) -> void:
	if DisplayServer.get_name() == "headless" or seconds <= 0.0:
		_root.modulate.a = target
		await get_tree().process_frame
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", target, seconds)
	await tw.finished


func _process(delta: float) -> void:
	if not visible:
		return
	shown_progress = move_toward(shown_progress, progress, delta * 0.9)
	_bar.value = shown_progress * 100.0
	_tip_time += delta
	if _tip_time > TIP_SECONDS:
		_tip_time = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip.text = tr(TIPS[_tip_index])
	_tip.modulate.a = clampf(minf(_tip_time / 0.5, (TIP_SECONDS - _tip_time) / 0.5), 0.0, 1.0)
	_fireflies.queue_redraw()


func _input(event: InputEvent) -> void:
	if visible and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 界面

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = GameSettings.ui_theme()
	add_child(_root)

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 1.0])
	grad.colors = PackedColorArray([Color("140f24"), Color("3a2a5c"), Color("8e4a6e"), Color("e39a5c")])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_fireflies = Control.new()
	_fireflies.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fireflies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fireflies.draw.connect(_draw_fireflies)
	_root.add_child(_fireflies)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var icon := TextureRect.new()
	icon.texture = load("res://icon.png") as Texture2D
	icon.custom_minimum_size = Vector2(150, 150)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var title := Label.new()
	title.text = "Dusk Lake"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.8))
	box.add_child(title)
	_subtitle = Label.new()
	_subtitle.text = "暮色湖畔 · 一片属于你的湖"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", Color(1.0, 0.86, 0.74))
	box.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(520, 10)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	bg_style.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ffd38a")
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("background", bg_style)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	_stage = Label.new()
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_color_override("font_color", Color(1.0, 0.95, 0.9))
	box.add_child(_stage)

	_tip = Label.new()
	_tip.text = tr(TIPS[_tip_index])
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tip.offset_top = -110.0
	_tip.offset_bottom = -60.0
	_tip.offset_left = 120.0
	_tip.offset_right = -120.0
	_tip.add_theme_font_size_override("font_size", 20)
	_tip.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9))
	_root.add_child(_tip)

	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -160.0
	version.offset_top = -40.0
	version.offset_right = -16.0
	version.offset_bottom = -12.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8, 0.8))
	_root.add_child(version)


## 背景里慢慢飘的萤火虫：位置由序号决定，只随时间动，不存状态。
func _draw_fireflies() -> void:
	var size := _fireflies.size
	var t := Time.get_ticks_msec() * 0.001
	for i in 28:
		var seed_x := fmod(i * 0.6180339 + 0.13, 1.0)
		var seed_y := fmod(i * 0.4142135 + 0.37, 1.0)
		var p := Vector2(seed_x * size.x + sin(t * 0.21 + i) * 40.0,
			(0.45 + seed_y * 0.5) * size.y + cos(t * 0.17 + i * 1.7) * 26.0)
		var glow := 0.5 + 0.5 * sin(t * (0.8 + fmod(i * 0.37, 0.9)) + i)
		_fireflies.draw_circle(p, 7.0, Color(1.0, 0.85, 0.45, 0.08 * glow))
		_fireflies.draw_circle(p, 2.2, Color(1.0, 0.92, 0.6, 0.55 * glow))
