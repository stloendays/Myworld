extends Node
## 玩家设置与按键表（Autoload）。按键在运行时注册，方便以后做改键。
## 设置的持久化属于 M4（SaveManager / 设置菜单），目前只在本次运行内有效。

signal changed

const FOV_MIN := 65.0
const FOV_MAX := 95.0

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"pause": [KEY_ESCAPE],
	"toggle_debug": [KEY_F3],
	"toggle_weather_panel": [KEY_F4],
	"toggle_view": [KEY_V],
}

var fov := 75.0
var mouse_sensitivity := 0.0025   ## 弧度 / 像素
var invert_y := false

var _theme: Theme = null


func _enter_tree() -> void:
	_register_inputs()


func _register_inputs() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func set_fov(value: float) -> void:
	fov = clampf(value, FOV_MIN, FOV_MAX)
	changed.emit()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.0005, 0.008)
	changed.emit()


## 所有 UI 共用的主题：系统中文字体回退，避免中文显示为方框。
func ui_theme() -> Theme:
	if _theme == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
			"Noto Sans CJK SC", "Noto Sans SC", "sans-serif"])
		_theme = Theme.new()
		_theme.default_font = font
		_theme.default_font_size = 18
	return _theme
