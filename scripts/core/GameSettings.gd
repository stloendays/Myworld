extends Node
## 玩家设置与按键表（Autoload）。按键在运行时注册，方便以后做改键。
## 设置保存在 user://settings.json（Esc → 设置里改动后自动保存，下次启动读取）。
## 开发者模式不保存：每次启动都是普通模式，按 F2 打开。

signal changed
signal developer_mode_changed(enabled: bool)

const FOV_MIN := 65.0
const FOV_MAX := 95.0
const SETTINGS_PATH := "user://settings.json"
const LANGUAGES := ["auto", "en", "zh"]   ## auto = 跟随系统：中文系统用中文，其他用英文
const LANGUAGE_NAMES := ["跟随系统 / System", "English", "中文"]

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
	"toggle_dev_mode": [KEY_F2],
	"toggle_fly": [KEY_F],
	"toggle_noclip": [KEY_N],
	"toggle_minimap": [KEY_M],
	"toggle_view": [KEY_V],
	"swim_down": [KEY_C, KEY_CTRL],
	"toggle_fullscreen": [KEY_F11],
	"toggle_actions": [KEY_G],
	"world_map": [KEY_TAB],
	"action_1": [KEY_1],
	"action_2": [KEY_2],
	"action_3": [KEY_3],
	"action_4": [KEY_4],
	"photo": [KEY_F12],
}

## 可保存的设置及默认值；键名即属性名。
const DEFAULTS := {
	"fov": 75.0,
	"mouse_sensitivity": 0.0025,      ## 弧度 / 像素
	"invert_y": false,
	"third_person_default": false,    ## 启动时用第三人称
	"third_person_distance": 3.2,
	"shoulder_left": false,           ## 第三人称相机在左肩
	"first_person_arms": "both",      ## both / right / none
	"view_bob": true,                 ## 走路时镜头轻微晃动
	"minimap_enabled": true,
	"minimap_rotate": true,           ## true = 随朝向旋转；false = 北朝上
	"minimap_range": 60.0,            ## 小地图半径（米）
	"render_scale": 1.0,
	"vsync": true,
	"fullscreen": false,
	"max_fps": 60,                    ## 0 = 不限；默认 60，笔记本不用满负荷跑
	"graphics_quality": "high",       ## low / medium / high / ultra（PerformanceDirector）
	"dynamic_resolution": true,       ## 按 GPU 帧时自动调 3D 渲染比例
	"fly_speed": 10.0,
	"emote_third_person": true,       ## 挥手 / 跳舞 / 鼓掌时自动切到第三人称看自己，做完切回
	"auto_update_check": true,        ## 启动时到 GitHub 检查新版本（只在导出的游戏里）
	"language": "auto",               ## 界面语言：auto（默认，跟随系统）/ en / zh
}

var fov := 75.0
var mouse_sensitivity := 0.0025
var invert_y := false
var third_person_default := false
var third_person_distance := 3.2
var shoulder_left := false
var first_person_arms := "both"
var view_bob := true
var minimap_enabled := true
var minimap_rotate := true
var minimap_range := 60.0
var render_scale := 1.0
var vsync := true
var fullscreen := false
var max_fps := 60
var graphics_quality := "high"
var dynamic_resolution := true
var fly_speed := 10.0
var emote_third_person := true
var auto_update_check := true
var language := "auto"

var developer_mode := false
var _window_user_set := false   ## 只有玩家改过（或设置文件里有）才去动垂直同步与全屏，命令行 --disable-vsync 不被覆盖

var _theme: Theme = null


func _enter_tree() -> void:
	_register_inputs()
	load_from(SETTINGS_PATH)
	_apply_startup_options()
	apply_language()


## A non-persistent recovery profile for PCs that cannot run the default
## settings. Use: DuskLake.exe -- --safe-mode
## Choose the rendering backend separately with engine flags before --.
func _apply_startup_options() -> void:
	if not OS.get_cmdline_user_args().has("--safe-mode"):
		return
	graphics_quality = "low"
	render_scale = 0.6
	dynamic_resolution = false
	fullscreen = false
	max_fps = 30
	auto_update_check = false
	_window_user_set = true
	print("Dusk Lake: safe mode enabled (low, 60% scale, 30 FPS, windowed, no auto-update)")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停菜单打开时 F11 也能切全屏
	apply_display()


## 全屏切换：F11 或 Alt + Enter，任何界面下都有效，并保存。
func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	var alt_enter := k != null and k.pressed and not k.echo and k.alt_pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER)
	if event.is_action_pressed("toggle_fullscreen") or alt_enter:
		set_value("fullscreen", not fullscreen)
		get_viewport().set_input_as_handled()


func _register_inputs() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


## 统一的设置入口：改值、限幅、通知；save = true 时写入 user://settings.json。
func set_value(key: String, value: Variant, save := true) -> void:
	if not DEFAULTS.has(key):
		push_error("GameSettings: 未知设置 %s" % key)
		return
	match key:
		"fov":
			value = clampf(float(value), FOV_MIN, FOV_MAX)
		"mouse_sensitivity":
			value = clampf(float(value), 0.0005, 0.008)
		"third_person_distance":
			value = clampf(float(value), 1.5, 8.0)
		"minimap_range":
			value = clampf(float(value), 25.0, 150.0)
		"render_scale":
			value = clampf(float(value), 0.5, 1.0)
		"fly_speed":
			value = clampf(float(value), 3.0, 40.0)
		"graphics_quality":
			value = value if str(value) in ["low", "medium", "high", "ultra"] else "high"
		"first_person_arms":
			value = value if str(value) in ["both", "right", "none"] else "both"
		"language":
			value = value if str(value) in LANGUAGES else "auto"
	set(key, value)
	if key in ["vsync", "fullscreen"]:
		_window_user_set = true
	if key in ["render_scale", "vsync", "fullscreen", "max_fps"]:
		apply_display()
	if key == "language":
		apply_language()
	changed.emit()
	if save:
		save_to(SETTINGS_PATH)


func set_fov(value: float) -> void:
	set_value("fov", value, false)


func set_mouse_sensitivity(value: float) -> void:
	set_value("mouse_sensitivity", value, false)


func set_developer_mode(enabled: bool) -> void:
	if developer_mode == enabled:
		return
	developer_mode = enabled
	developer_mode_changed.emit(enabled)
	changed.emit()


func to_dict() -> Dictionary:
	var d := {}
	for key in DEFAULTS:
		d[key] = get(key)
	return d


func reset_defaults() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])
	developer_mode = false
	_window_user_set = false
	apply_display()
	apply_language()
	changed.emit()


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	return true


## 读取设置文件；缺的键保持默认，类型不对的键忽略（旧版本的文件也能读）。
func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	_window_user_set = (parsed as Dictionary).has("vsync") or (parsed as Dictionary).has("fullscreen")
	for key in DEFAULTS:
		if not (parsed as Dictionary).has(key):
			continue
		var v: Variant = parsed[key]
		var def: Variant = DEFAULTS[key]
		if typeof(def) == TYPE_FLOAT and (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT):
			set(key, float(v))
		elif typeof(def) == TYPE_INT and (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT):
			set(key, int(v))
		elif typeof(def) == typeof(v):
			set(key, v)
	changed.emit()
	return true


## 画面设置：渲染比例、垂直同步、全屏、帧率上限（无窗口的自动检查里跳过窗口相关项）。
func apply_display() -> void:
	if not is_inside_tree():
		return
	# 自动检查（无窗口）不限帧率，否则 --fixed-fps 的模拟会被拖成实时
	Engine.max_fps = 0 if DisplayServer.get_name() == "headless" else max_fps
	if DisplayServer.get_name() == "headless" or not _window_user_set:
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var mode := DisplayServer.window_get_mode()
	var want_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != want_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


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


## 界面语言：源文本是中文，locale/en.po 是英文翻译；选中文时没有对应翻译，tr() 原样返回中文。
func apply_language() -> void:
	TranslationServer.set_locale(resolved_language())


## 实际使用的语言：auto 时看系统语言（中文系统 zh，其他 en）。
func resolved_language() -> String:
	if language == "en" or language == "zh":
		return language
	return "zh" if OS.get_locale_language() == "zh" else "en"
