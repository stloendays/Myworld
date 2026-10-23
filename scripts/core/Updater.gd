extends Node
## 自动更新（Autoload，名为 Updater）：启动时到 GitHub Releases 查最新版本，比当前版本新就提示；
## 玩家点“更新并重启”后在后台下载新的 DuskLake.exe，核对大小与 SHA-256，写一个小替换脚本（PowerShell）：
## 等本进程退出 → 用新文件替换旧 exe → 重新启动。整个过程不需要安装程序，exe 放在哪里就在哪里更新。
##   · 只在导出的游戏里自动检查（编辑器、自动检查里不联网）；设置 → 关于 可以关掉自动检查、手动检查。
##   · 发布约定：Release 标签 vX.Y.Z，附件 DuskLake.exe 和 DuskLake.exe.sha256（文件里第一个词是十六进制 SHA-256）。
##   · 命令行（测试用）：-- --pretend-version 0.0.1 假装当前版本；-- --update-now 查到新版直接下载替换；
##     -- --no-relaunch 替换后不重启。

signal status_changed(state: int, text: String)

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, READY, FAILED, DISABLED }

const REPO := "stloendays/Myworld"
const API_LATEST := "https://api.github.com/repos/%s/releases/latest"
const ASSET_NAME := "DuskLake.exe"
const CHECKSUM_NAME := "DuskLake.exe.sha256"
const RELEASES_PAGE := "https://github.com/%s/releases/latest"

var state := State.IDLE
var status_text := ""
var latest_version := ""
var latest_notes := ""
var download_progress := 0.0   ## 0–1
var _asset_url := ""
var _asset_size := 0
var _checksum_url := ""
var _expected_sha := ""
var _http: HTTPRequest
var _download_path := ""
var _args := PackedStringArray()
var _last_code := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = OS.get_cmdline_user_args()
	_cleanup_leftovers()
	if can_self_update() and (GameSettings.auto_update_check or _args.has("--update-now")):
		check.call_deferred()


## 当前版本（--pretend-version 只影响更新比较，联机仍用真实版本）。
func current_version() -> String:
	var i := _args.find("--pretend-version")
	if i >= 0 and i + 1 < _args.size():
		return _args[i + 1]
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## 只有导出的 Windows 游戏才能自己替换 exe；编辑器里运行、自动检查里一律不联网。
func can_self_update() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows"


## "v0.3.1" / "0.3.1" → [0, 3, 1]；比较时缺的位当 0。
static func parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	var numeric := v.strip_edges().trim_prefix("v").trim_prefix("V").split("-", false, 1)[0]
	for part in numeric.split("."):
		out.append(int(part.to_int()) if part.is_valid_int() else 0)
	return out


static func _is_prerelease(v: String) -> bool:
	return v.strip_edges().contains("-")


## a 比 b 新返回 1，相同 0，旧 -1。
static func compare_versions(a: String, b: String) -> int:
	var pa := parse_version(a)
	var pb := parse_version(b)
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i] if i < pa.size() else 0
		var y := pb[i] if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	if _is_prerelease(a) != _is_prerelease(b):
		return -1 if _is_prerelease(a) else 1
	return 0


## 从 GitHub API 的 release JSON 里取出版本、说明和下载地址；不合格返回空字典。
static func read_release(release: Dictionary) -> Dictionary:
	var tag := str(release.get("tag_name", ""))
	if tag == "" or release.get("draft", false) or release.get("prerelease", false):
		return {}
	var out := {"version": tag.trim_prefix("v"), "notes": str(release.get("body", "")), "url": "", "size": 0, "sha_url": ""}
	for a in release.get("assets", []):
		var asset := a as Dictionary
		if asset.get("name", "") == ASSET_NAME:
			out["url"] = str(asset.get("browser_download_url", ""))
			out["size"] = int(asset.get("size", 0))
		elif asset.get("name", "") == CHECKSUM_NAME:
			out["sha_url"] = str(asset.get("browser_download_url", ""))
	return out if out["url"] != "" else {}


func check() -> void:
	if state == State.CHECKING or state == State.DOWNLOADING:
		return
	_set_state(State.CHECKING, tr("正在检查更新…"))
	var json: Variant = await _get_json(API_LATEST % REPO)
	if _last_code == 404:
		_set_state(State.UP_TO_DATE, tr("还没有可下载的版本"))
		return
	if not json is Dictionary:
		_set_state(State.FAILED, tr("检查更新失败（网络不通或 GitHub 暂时不可用）"))
		return
	var r := read_release(json)
	if r.is_empty():
		_set_state(State.UP_TO_DATE, tr("还没有可下载的版本"))
		return
	latest_version = r["version"]
	latest_notes = r["notes"]
	_asset_url = r["url"]
	_asset_size = r["size"]
	_checksum_url = r["sha_url"]
	if compare_versions(latest_version, current_version()) <= 0:
		_set_state(State.UP_TO_DATE, tr("已是最新版本（v%s）") % current_version())
		return
	_set_state(State.AVAILABLE, tr("发现新版本 v%s") % latest_version)
	EventBus.toast_requested.emit(tr("发现新版本 v%s · 在大厅或 设置 → 关于 里一键更新") % latest_version)
	if _args.has("--update-now"):
		download_and_install()


## 下载新 exe → 核对 → 交给批处理在退出后替换并重启。
func download_and_install() -> void:
	if state != State.AVAILABLE:
		return
	if not can_self_update():
		_set_state(State.FAILED, tr("只有导出的游戏能自动更新，请到 GitHub 下载"))
		return
	var exe := OS.get_executable_path()
	_download_path = exe.get_base_dir().path_join(ASSET_NAME + ".download")
	if _checksum_url != "":
		var sha_text: Variant = await _get_text(_checksum_url)
		_expected_sha = str(sha_text).strip_edges().split(" ", false)[0].to_lower() if sha_text is String and str(sha_text).strip_edges() != "" else ""
	_set_state(State.DOWNLOADING, tr("正在下载 v%s…") % latest_version)
	_http = _new_http()
	_http.download_file = _download_path
	var err := _http.request(_asset_url)
	if err != OK:
		_set_state(State.FAILED, tr("下载失败（%d）") % err)
		return
	var result: Array = await _http.request_completed
	_http.queue_free()
	_http = null
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		_set_state(State.FAILED, tr("下载失败（%d）") % int(result[1]))
		return
	var verdict := verify_file(_download_path, _asset_size, _expected_sha)
	if verdict != "":
		DirAccess.remove_absolute(_download_path)
		_set_state(State.FAILED, verdict)
		return
	_set_state(State.READY, tr("v%s 已下载，正在重启…") % latest_version)
	install_and_restart(exe, _download_path, not _args.has("--no-relaunch"))


## 核对下载的文件：大小一致、SHA-256 一致（发布里有校验文件时）。返回空字符串表示通过，否则是原因。
static func verify_file(path: String, size: int, sha: String) -> String:
	if not FileAccess.file_exists(path):
		return TranslationServer.translate("下载的文件不见了")
	var f := FileAccess.open(path, FileAccess.READ)
	var got := f.get_length()
	f.close()
	if size > 0 and got != size:
		return TranslationServer.translate("下载不完整（%d / %d 字节）") % [got, size]
	if sha != "" and FileAccess.get_sha256(path).to_lower() != sha.to_lower():
		return TranslationServer.translate("文件校验不通过，已删除下载")
	return ""


## 写批处理并退出：等本进程结束 → 旧 exe 改名 .old → 新文件改名为 exe → （可选）重新启动 → 删掉 .old。
func install_and_restart(exe: String, new_file: String, relaunch := true) -> void:
	var script_path := exe.get_base_dir().path_join("DuskLake-update.ps1")
	var f := FileAccess.open(script_path, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))   # UTF-8 BOM：Windows PowerShell 5.1 才会按 UTF-8 读中文路径
	f.store_string(update_script(OS.get_process_id(), exe, new_file, relaunch))
	f.close()
	OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", script_path.replace("/", "\\")], false)
	get_tree().quit()


## 替换脚本（PowerShell）。不用 .cmd：路径里有中文时 cmd 按系统代码页读批处理会读错。单独成函数，方便自动检查核对。
static func update_script(pid: int, exe: String, new_file: String, relaunch: bool) -> String:
	var lines := PackedStringArray([
		"$ErrorActionPreference = 'SilentlyContinue'",
		"$exe = %s" % _ps_quote(exe),
		"$new = %s" % _ps_quote(new_file),
		"Wait-Process -Id %d -Timeout 120" % pid,
		"Start-Sleep -Milliseconds 400",
		"Remove-Item -LiteralPath ($exe + '.old') -Force",
		"Move-Item -LiteralPath $exe -Destination ($exe + '.old') -Force",
		"Move-Item -LiteralPath $new -Destination $exe -Force",
		"if (-not (Test-Path -LiteralPath $exe)) { Move-Item -LiteralPath ($exe + '.old') -Destination $exe -Force }",
	])
	if relaunch:
		lines.append("Start-Process -FilePath $exe")
	lines.append("Remove-Item -LiteralPath ($exe + '.old') -Force")
	lines.append("Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force")
	return "\r\n".join(lines) + "\r\n"


## PowerShell 单引号字符串：反斜杠路径，单引号写两次。
static func _ps_quote(p: String) -> String:
	return "'" + p.replace("/", "\\").replace("'", "''") + "'"


func open_releases_page() -> void:
	OS.shell_open(RELEASES_PAGE % REPO)


func _cleanup_leftovers() -> void:
	if not can_self_update():
		return
	var exe := OS.get_executable_path()
	for leftover in [exe + ".old", exe.get_base_dir().path_join(ASSET_NAME + ".download")]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)


func _set_state(s: int, text: String) -> void:
	state = s
	status_text = text
	print("Updater: ", text)
	status_changed.emit(s, text)


func _new_http() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = 600.0
	h.use_threads = true
	add_child(h)
	h.download_chunk_size = 262144
	return h


func _process(_delta: float) -> void:
	if _http != null and state == State.DOWNLOADING and _asset_size > 0:
		download_progress = clampf(float(_http.get_downloaded_bytes()) / _asset_size, 0.0, 1.0)


func _get_text(url: String) -> Variant:
	var h := _new_http()
	h.timeout = 20.0
	var err := h.request(url, ["User-Agent: DuskLake-Updater", "Accept: application/vnd.github+json"])
	if err != OK:
		h.queue_free()
		return null
	var result: Array = await h.request_completed
	h.queue_free()
	_last_code = int(result[1])
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return null
	return (result[3] as PackedByteArray).get_string_from_utf8()


func _get_json(url: String) -> Variant:
	var text: Variant = await _get_text(url)
	return JSON.parse_string(text) if text is String else null
