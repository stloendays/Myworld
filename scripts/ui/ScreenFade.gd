extends CanvasLayer
## 转场黑幕（Autoload，名为 Fade）：盖在所有界面之上的一块全屏黑色，可以带一行居中的说明文字。
##   await Fade.fade_out(0.4, "正在前往…")   变黑（文字一起淡入）
##   await Fade.fade_in(0.6)                  黑幕褪去
##   Fade.flash("说明")                       一下子黑掉再慢慢亮起（传送、进出房间都用这个）
## 暂停时也照常淡入淡出；无窗口的自动检查里时长压到一帧，不拖慢测试。

const LAYER := 90

var alpha := 0.0
var _rect: ColorRect
var _label: Label
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER
	_rect = ColorRect.new()
	_rect.color = Color(0.02, 0.015, 0.04, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.theme = GameSettings.ui_theme()
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.78))
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_apply(0.0)


func is_black() -> bool:
	return alpha > 0.99


func fade_out(seconds := 0.4, caption := "") -> void:
	_label.text = caption
	await _to(1.0, seconds)


func fade_in(seconds := 0.6) -> void:
	await _to(0.0, seconds)
	_label.text = ""


## 一下子黑掉再慢慢亮起来（传送、进出房间：位置或世界状态已经跳变，用黑幕盖住这一下）。不用 await。
func flash(caption := "", in_s := 0.9) -> void:
	set_black(caption)
	fade_in(in_s)


## 立刻全黑（启动加载界面交接给开场过场时用）。
func set_black(caption := "") -> void:
	if _tween != null:
		_tween.kill()
	_label.text = caption
	_apply(1.0)


func _to(target: float, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	if DisplayServer.get_name() == "headless":
		seconds = 0.0
	if seconds <= 0.0:
		_apply(target)
		await get_tree().process_frame
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_apply, alpha, target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished


func _apply(a: float) -> void:
	alpha = a
	_rect.color.a = a
	_label.modulate.a = clampf(a * 1.4 - 0.4, 0.0, 1.0)
	visible = a > 0.001
