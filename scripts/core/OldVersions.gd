class_name OldVersions
extends RefCounted
## 认出电脑上的旧版本游戏（DuskLake.exe），交给 Updater 移到回收站。
##   · 只认官方发布过的文件：data/releases.json 里有每个版本 exe 的大小和 SHA-256，大小对上了才算哈希，
##     哈希对上、而且版本比现在运行的旧，才算旧版本。别的文件（同名但内容不同的、改过的、新版本）一概不碰。
##   · 去哪找：现在这个 exe 所在的文件夹、下载文件夹、桌面里名字以 DuskLake 开头的 .exe（浏览器重复下载会存成
##     “DuskLake (1).exe”），加上以前运行过的位置（user://installs.json，每次启动记一笔）。
##   · scan() 只读文件、不改任何东西，可以放在后台线程里跑；真正移到回收站在主线程（Updater）。

const DATA_PATH := "res://data/releases.json"
static var installs_path := "user://installs.json"   ## 自动检查改到别处，不碰真的运行记录
const NAME_PREFIX := "dusklake"
const MAX_RECORDS := 12


static func releases() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return (parsed as Dictionary).get("releases", []) if parsed is Dictionary else []


## 以前运行过的 exe（路径、版本）。
static func recorded() -> Array:
	if not FileAccess.file_exists(installs_path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(installs_path))
	return (parsed as Dictionary).get("installs", []) if parsed is Dictionary else []


## 记下这次运行的 exe；forget 里的路径（已经移到回收站的）从记录里去掉。
static func record(exe: String, version: String, forget: PackedStringArray = []) -> void:
	var keep := [{"path": exe, "version": version}]
	for r: Dictionary in recorded():
		var p := str(r.get("path", ""))
		if _same(p, exe) or forget.has(p) or keep.size() >= MAX_RECORDS:
			continue
		keep.append(r)
	var f := FileAccess.open(installs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"installs": keep}, "  "))


## 要检查的文件：dirs 里名字以 DuskLake 开头的 .exe，加上 extra（记录里的路径）；去掉现在运行的这个、去重。
static func candidates(dirs: PackedStringArray, extra: PackedStringArray, current_exe: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in dirs:
		if d == "" or not DirAccess.dir_exists_absolute(d):
			continue
		for name in DirAccess.get_files_at(d):
			var low := name.to_lower()
			if low.begins_with(NAME_PREFIX) and low.ends_with(".exe"):
				_add(out, d.path_join(name), current_exe)
	for p in extra:
		if FileAccess.file_exists(p):
			_add(out, p, current_exe)
	return out


## 这个文件是哪个比 current_version 旧的官方版本；不是返回空字典。
static func match_release(path: String, known: Array, current_version: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var size := f.get_length()
	f.close()
	var sha := ""
	for r: Dictionary in known:
		if int(r.get("size", -1)) != size or not _older(str(r["version"]), current_version):
			continue
		if sha == "":
			sha = FileAccess.get_sha256(path).to_lower()
		if sha == str(r["sha256"]).to_lower():
			return r
	return {}


## 找出所有旧版本：[{path, version}]。只读，可以在后台线程里调用。
static func scan(dirs: PackedStringArray, extra: PackedStringArray, current_exe: String, current_version: String, known: Array) -> Array:
	var out := []
	for p in candidates(dirs, extra, current_exe):
		var r := match_release(p, known, current_version)
		if not r.is_empty():
			out.append({"path": p, "version": str(r["version"])})
	return out


## a 比 b 旧（和 Updater.compare_versions 一样逐位比；放在这里，后台线程里不用碰 Autoload）。
static func _older(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() and pa[i].is_valid_int() else 0
		var y := pb[i].to_int() if i < pb.size() and pb[i].is_valid_int() else 0
		if x != y:
			return x < y
	return false


static func _add(out: PackedStringArray, p: String, current_exe: String) -> void:
	if _same(p, current_exe):
		return
	for q in out:
		if _same(p, q):
			return
	out.append(p)


static func _same(a: String, b: String) -> bool:
	return a.replace("\\", "/").to_lower() == b.replace("\\", "/").to_lower()
