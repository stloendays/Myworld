extends Node
## Detect first successful rendered frames and record local diagnostics.
## The launcher supplies --startup-ready-file. No data leaves this PC.

const DIAGNOSTIC_DIR := "user://diagnostics"
const LAST_STATUS := DIAGNOSTIC_DIR + "/last_startup.json"


func _ready() -> void:
	var full_dir := ProjectSettings.globalize_path(DIAGNOSTIC_DIR)
	var err := DirAccess.make_dir_recursive_absolute(full_dir)
	if err != OK:
		push_warning("StartupDiagnostics: cannot create directory (%d)" % err)
		return
	_write_status("engine_initialized")


func mark_world_ready() -> void:
	# Only mark healthy AFTER actual rendering, not on process creation.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await get_tree().create_timer(2.0).timeout
	_write_status("first_frame_ok")
	var args := OS.get_cmdline_user_args()
	var at := args.find("--startup-ready-file")
	if at < 0 or at + 1 >= args.size():
		return
	var path := args[at + 1]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("StartupDiagnostics: cannot write ready marker (%d)" % FileAccess.get_open_error())
		return
	file.store_string("ready\n")
	file.close()


func _write_status(phase: String) -> void:
	var data := {
		"phase": phase,
		"version": ProjectSettings.get_setting("application/config/version", "unknown"),
		"engine": Engine.get_version_info().get("string", "unknown"),
		"os": OS.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"time_local": Time.get_datetime_string_from_system(),
	}
	var file := FileAccess.open(LAST_STATUS, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
	print("DuskLake startup: ", JSON.stringify(data))
