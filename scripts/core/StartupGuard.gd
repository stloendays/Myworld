extends Node
## 启动保护（第一个 Autoload）：让显卡老旧、驱动有问题的电脑也能打开游戏。
##   · 引擎自己会在 Vulkan 起不来时依次换 D3D12、OpenGL（project.godot 的 fallback_to_* 默认开着）；
##     但有些驱动能起来、画到一半崩掉，这种情况引擎不会换。
##   · 所以每次启动先在 user://startup_guard.json 记 state = starting，世界画出来以后（BootLoader 预热完）
##     改成 ok，正常退出改成 exited。下次启动看到 starting，说明上次在加载途中崩了，自动降一级渲染：
##     标准（Vulkan / D3D12）→ 兼容（OpenGL）→ 兼容 ANGLE（OpenGL 走 Direct3D 11），并带参数重新启动自己。
##   · 设置 → 画面 → 渲染方式（GameSettings.renderer）可以手动选，下次启动生效；“Direct3D 12”和自动一样是标准画质，
##     进程内存约少一半（显卡驱动那一侧占得少），第一次见到新材质时编译着色器比 Vulkan 慢一些。
##   · 只在导出的游戏里起作用；编辑器、自动检查、开发工具、命令行自己指定了渲染方式时都不动。
##   · 每次启动把版本、渲染方式、驱动、显卡写进日志（%APPDATA%\DuskLake\logs\godot.log），方便朋友发来排查。

const GUARD_PATH := "user://startup_guard.json"
const SETTINGS_PATH := "user://settings.json"
const RENDERERS := ["auto", "d3d12", "compatibility", "angle"]   ## d3d12：标准画质走 Direct3D 12（同样的画面，进程内存约少一半）

var active := false
var state := {}
var relaunching := false


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var method := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	print("Dusk Lake v%s | %s %s | renderer %s / %s | %s" % [ProjectSettings.get_setting("application/config/version", "?"),
		OS.get_name(), OS.get_version(), method, driver, RenderingServer.get_video_adapter_name()])
	active = _enabled()
	if not active:
		return
	state = _read_json(GUARD_PATH)
	var setting := str(_read_json(SETTINGS_PATH).get("renderer", "auto"))
	var crashed := str(state.get("state", "")) == "starting"
	var want := next_renderer(setting, driver) if crashed else setting
	if want != setting:
		push_warning("StartupGuard: 上次启动没有走到游戏画面（%s / %s），这次改用 %s" % [method, driver, want])
		_write_setting(want)
		state["auto_switched"] = want
	state["state"] = "starting"
	state["method"] = method
	state["driver"] = driver
	state["adapter"] = RenderingServer.get_video_adapter_name()
	state["os"] = "%s %s" % [OS.get_name(), OS.get_version()]
	state["version"] = str(ProjectSettings.get_setting("application/config/version", "?"))
	state["time"] = Time.get_datetime_string_from_system()
	if needs_relaunch(want, driver, _has_render_override()):
		state["state"] = "relaunch"
		_write_json(GUARD_PATH, state)
		_relaunch(launch_args(want))
		return
	_write_json(GUARD_PATH, state)


func _exit_tree() -> void:
	if active and not relaunching and str(state.get("state", "")) == "starting":
		state["state"] = "exited"
		_write_json(GUARD_PATH, state)


## 世界已经画出来了（BootLoader 预热完调用）：这次启动算成功。
func mark_stable() -> void:
	if not active or str(state.get("state", "")) != "starting":
		return
	state["state"] = "ok"
	_write_json(GUARD_PATH, state)


## 上次在 driver 下崩了，这次该用哪种渲染。已经是 ANGLE 就没有再低的了，保持不变。
static func next_renderer(setting: String, driver: String) -> String:
	match driver:
		"opengl3":
			return "angle"
		"opengl3_angle":
			return setting
		_:
			return "compatibility" if setting in ["auto", "d3d12"] else ("angle" if setting == "compatibility" else setting)


## 选的渲染方式和实际跑着的驱动不一致时需要带参数重启（命令行自己指定过就不管）。
static func needs_relaunch(setting: String, driver: String, has_override: bool) -> bool:
	if has_override:
		return false
	match setting:
		"d3d12":
			return driver != "d3d12"
		"compatibility":
			return not driver.begins_with("opengl3")
		"angle":
			return driver != "opengl3_angle"
	return false


static func launch_args(setting: String) -> PackedStringArray:
	match setting:
		"d3d12":
			return PackedStringArray(["--rendering-driver", "d3d12"])
		"compatibility":
			return PackedStringArray(["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"])
		"angle":
			return PackedStringArray(["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3_angle"])
	return PackedStringArray()


## 设置里改了渲染方式后“立即重启”。
func restart_with(setting: String) -> void:
	var args := launch_args(setting)
	relaunching = true
	if active and str(state.get("state", "")) != "starting":
		state["state"] = "exited"
		_write_json(GUARD_PATH, state)
	_relaunch(args)


func _relaunch(args: PackedStringArray) -> void:
	relaunching = true
	var all := PackedStringArray(args)
	var user := OS.get_cmdline_user_args()
	if not user.is_empty():
		all.append("--")
		all.append_array(user)
	var pid := OS.create_process(OS.get_executable_path(), all)
	print("StartupGuard: relaunching with %s -> pid %d" % [" ".join(all), pid])
	if pid <= 0:
		relaunching = false
		return
	get_tree().quit.call_deferred()


func _enabled() -> bool:
	if OS.get_environment("DUSK_STARTUP_GUARD") == "1":
		return true
	if OS.get_environment("DUSK_STARTUP_GUARD") == "0" or DisplayServer.get_name() == "headless":
		return false
	return OS.has_feature("template")


func _has_render_override() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("--rendering-method") or args.has("--rendering-driver")


func _write_setting(value: String) -> void:
	var s := _read_json(SETTINGS_PATH)
	s["renderer"] = value
	_write_json(SETTINGS_PATH, s)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
