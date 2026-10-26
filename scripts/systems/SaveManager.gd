extends Node
## 世界存档（Autoload，v0.5 起真正启用）：WorldState.snapshot() 写成 user://saves/world.json（版本化 JSON，
## 先写临时文件再原子替换），里面有本局规则（GameRules）、时间天气、发现、任务与图鉴、收集品、门灯状态、船、玩家所在世界与位置。
##   · 新建游戏（大厅“新建游戏”页）：旧存档先备份成 world.bak.json，清掉进度，按规则设好开局，去出生世界；
##   · 继续：读档 → 迁移到当前版本（v1–v3 的旧档、或只有旧的 user://journal.json 时都能读）→ 恢复状态 → 回到存档时的世界和位置；
##   · 本局开始后每 60 s、换世界后、退出游戏时自动存；联机做客时不存（世界是房主的）。
## 自动检查和开发工具（headless 或 res://devtools/、res://tests/ 场景）里不读不写磁盘。

signal saved
signal loaded

const DIR := "user://saves"
const PATH := "user://saves/world.json"
const BACKUP := "user://saves/world.bak.json"
const LEGACY_JOURNAL := "user://journal.json"   ## v0.4 只存了任务与图鉴（存档 v3）
const AUTOSAVE_SECONDS := 60.0

var persist := true          ## false：不碰磁盘（自动检查、截图工具）
var active := false          ## 本局已开始（新建或继续），才自动存
var path := PATH             ## 自动检查可以改到别的文件
var last_error := ""

var _timer := AUTOSAVE_SECONDS
var _dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	persist = DisplayServer.get_name() != "headless" and not QuestLog._is_dev_run()
	WorldTravel.travel_finished.connect(_on_travel_finished)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _process(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer <= 0.0 or (_dirty and _timer < AUTOSAVE_SECONDS - 5.0):
		save()


## 有东西变了（任务、图鉴、收集品）：几秒内存一次，不必每次都写盘。
func request_save() -> void:
	_dirty = true


func has_save() -> bool:
	return FileAccess.file_exists(path) or (path == PATH and FileAccess.file_exists(LEGACY_JOURNAL))


## 读出并迁移到当前版本；没有存档返回空字典。只有旧的 journal.json 时把它当成 v3 存档。
func read() -> Dictionary:
	var raw: Variant = null
	if FileAccess.file_exists(path):
		raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	elif path == PATH and FileAccess.file_exists(LEGACY_JOURNAL):
		raw = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_JOURNAL))
		if raw is Dictionary:
			(raw as Dictionary)["schema_version"] = int((raw as Dictionary).get("schema_version", 3))
			(raw as Dictionary)["legacy"] = true
	if not raw is Dictionary:
		return {}
	return WorldState.migrate(raw)


## 大厅首页“继续”按钮上的一行：世界、第几天、季节、时刻、玩法。
func summary() -> Dictionary:
	var d := read()
	if d.is_empty():
		return {}
	var p: Dictionary = d.get("player", {})
	var r: Dictionary = d.get("rules", {})
	return {"world": str(p.get("world", "dusk_lake")), "day": int(d.get("world_day", 1)), "minutes": float(d.get("time_minutes", 0.0)),
		"mode": str(r.get("mode", "explore")), "saved_at": str(d.get("saved_at", "")), "legacy": d.get("legacy", false)}


## 当前世界的完整快照（含玩家位置）。
func snapshot() -> Dictionary:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player != null:
		var p := player.global_position
		WorldState.player_spot = {"world": WorldTravel.current_world, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
			"heading": snappedf(player.heading_degrees(), 0.1)}
	var d := WorldState.snapshot()
	d["saved_at"] = Time.get_datetime_string_from_system()
	d["game_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	return d


func save() -> bool:
	_timer = AUTOSAVE_SECONDS
	_dirty = false
	if not active or Net.is_client() or WorldTravel.busy:
		return false
	var d := snapshot()
	if not persist:
		saved.emit()
		return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "open %s: %d" % [tmp, FileAccess.get_open_error()]
		push_warning("SaveManager: " + last_error)
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		last_error = "rename: %d" % err
		push_warning("SaveManager: " + last_error)
		return false
	saved.emit()
	return true


## 新建游戏：rules 是设定页选好的整套规则。备份旧档 → 清进度 → 规则生效 → 开局时间天气 → 去出生世界的出生点。
func start_new(rules: Dictionary) -> void:
	if persist and FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(BACKUP))
	WorldState.reset_progress()
	QuestLog.reset()
	GameRules.set_all(rules)
	_reset_scene_state()
	GameRules.apply_start()
	GameRules.apply_ongoing()
	active = true
	var target := str(GameRules.get_rule("spawn_world"))
	if target != WorldTravel.current_world and WorldRegistry.is_open(target):
		WorldTravel.pending_spawn = GameRules.spawn_point(target)
		WorldTravel.travel(target)
		await WorldTravel.travel_finished
	else:
		_place_player(GameRules.spawn_point(target))
	save()


## 继续上次的世界：读档、恢复状态、回到存档时的世界与位置。没有存档返回 false。
func continue_game() -> bool:
	var d := read()
	if d.is_empty():
		return false
	# v0.4 只存了任务与图鉴（user://journal.json）：按默认设定开一局（秋季黄昏的湖畔），再把任务和图鉴接上
	if d.get("legacy", false):
		var q: Dictionary = d.get("quests", {})
		var j: Dictionary = d.get("journal", {})
		await start_new(GameRules.defaults())
		WorldState.quests = q.duplicate(true)
		WorldState.journal = j.duplicate(true)
		QuestLog.changed.emit()
		save()
		return true
	WorldState.restore(d)
	GameRules.set_all(d.get("rules", {}))
	_apply_scene_state()
	GameRules.apply_ongoing()
	QuestLog.changed.emit()
	active = true
	var spot: Dictionary = d.get("player", {})
	var world := str(spot.get("world", WorldTravel.current_world))
	if world != WorldTravel.current_world and WorldRegistry.is_open(world):
		WorldTravel.pending_spawn = spot
		WorldTravel.travel(world)
		await WorldTravel.travel_finished
	elif spot.has("pos"):
		_place_player(spot)
	loaded.emit()
	EventBus.save_loaded.emit(WorldState.SCHEMA_VERSION)
	return true


## 世界里已经存在的门、灯按 WorldState 恢复，船回到存下的位置；季节系统和变天计划跟着刷新。
func _apply_scene_state() -> void:
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		var s := WorldState.get_interactable_state(it.uid)
		if s != "" and s != it.get_state():
			it.apply_state(s)
	for v in get_tree().get_nodes_in_group("vehicles"):
		var canoe := v as Canoe
		var saved_v: Dictionary = WorldState.vehicles.get(String(canoe.uid), {})
		if not saved_v.is_empty() and canoe.rider == null:
			canoe.place_at(Vector2(float(saved_v["pos"][0]), float(saved_v["pos"][1])), float(saved_v.get("yaw_deg", 0.0)))
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	if climate != null:
		climate.clock.set_time(WorldState.world_day, WorldState.time_minutes)
		climate.seasons.refresh()
	get_tree().call_group("collectibles", "refresh")


## 新局：在场的门、灯回到初始状态（登记表清空后按现在的样子重新登记）。
func _reset_scene_state() -> void:
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it is InteractableDoor and it.get_state() == "open":
			it.apply_state("closed")
		WorldState.register_interactable(it.uid, it.get_state())
	get_tree().call_group("collectibles", "refresh")


## spot：{pos: [x, y, z] 或 Vector3, heading} 或 {id}（MiniWorld 的出生点）；空字典 = 这个世界的默认出生点。
func _place_player(spot: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return
	var root := get_tree().get_first_node_in_group("world_root")
	if spot.is_empty():
		if root is Main:
			Main.place_at_spawn(player)
		elif root is MiniWorld:
			(root as MiniWorld).place_player(player, {})
		return
	if root is MiniWorld and spot.has("id"):
		(root as MiniWorld).place_player(player, spot)
		return
	var p: Variant = spot.get("pos")
	var pos := Vector3.ZERO
	if p is Vector3:
		pos = p
	else:
		var a: Array = p
		pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
	player.teleport_to(pos + Vector3(0.0, 0.05, 0.0), float(spot.get("heading", 0.0)))


func _on_travel_finished(_id: String) -> void:
	var spot := WorldTravel.pending_spawn
	WorldTravel.pending_spawn = {}
	if not spot.is_empty():
		_place_player(spot)
	if active:
		save()
