extends Node
## 任务与图鉴（Autoload）。任务内容在 data/quests/quests.json，由图腾山洞里的老图腾（CaveTotem）发出。
## 状态写在 WorldState（quests、journal，存档 v3），本节点只负责：
##   · 每 0.4 秒按当前世界状态检查进行中的任务目标（发现了哪些地方、玩家在哪、看没看到彩虹、图鉴里有几种动物……），
##     全部完成就记为完成并弹出提示；
##   · 记图鉴：玩家走近（9 m 内）的动物、鱼缸里游过身边的鱼、夜里认出的星座；
##   · 有变化时请 SaveManager 存档（v0.5 起任务与图鉴随世界存档保存；旧的 user://journal.json 由 SaveManager 迁移读取）。
## 参考了 GitHub 上 shomykohai/quest-system（任务 = 目标列表 + 状态）的结构，按本项目“内容写在 JSON、状态在 WorldState”的规则重写。

signal changed                                   ## 任务或图鉴有变化（任务追踪、日志界面刷新用）
signal quest_completed(quest_id: String)

const DATA_PATH := "res://data/quests/quests.json"
const SAVE_PATH := "user://journal.json"
const MAX_ACTIVE := 3
const SEEN_RADIUS := 9.0
const FISH_RADIUS := 6.0

var persist := true          ## false：不读写 user://journal.json（自动检查用）
var _data: Dictionary = {}
var _timer := 0.0
var _emotes: Dictionary = {}  ## 本次运行里做过的动作 id -> 最后一次做动作的位置（emote_at 目标用）
var _sat: Dictionary = {}     ## 坐过的座位 uid


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_data = parsed if parsed is Dictionary else {"quests": []}
	persist = DisplayServer.get_name() != "headless" and not _is_dev_run()
	EventBus.interactable_state_changed.connect(_on_interactable)


static func _is_dev_run() -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("res://devtools/") or a.begins_with("res://tests/"):
			return true
	return false


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return
	_record_animals(player)
	evaluate(player)


# ---------------------------------------------------------------- 数据

func quests() -> Array:
	return _data.get("quests", [])


func get_quest(id: String) -> Dictionary:
	for q: Dictionary in quests():
		if str(q["id"]) == id:
			return q
	return {}


func giver_name() -> String:
	return text(_data.get("giver", {}), "name")


## 按界面语言取文字：英文界面取 key_en，否则取 key（中文）。
static func text(d: Dictionary, key: String) -> String:
	if TranslationServer.get_locale().begins_with("en") and d.has(key + "_en"):
		return str(d[key + "_en"])
	return str(d.get(key, ""))


func line(key: String) -> String:
	var d: Dictionary = _data.get(key, {})
	return str(d.get("en", "")) if TranslationServer.get_locale().begins_with("en") else str(d.get("zh", ""))


func state_of(id: String) -> String:
	var q: Dictionary = WorldState.quests.get(id, {})
	return str(q.get("state", ""))


func active_ids() -> Array:
	var out := []
	for q: Dictionary in quests():
		if state_of(str(q["id"])) == "active":
			out.append(str(q["id"]))
	return out


func done_count() -> int:
	var n := 0
	for q: Dictionary in quests():
		if state_of(str(q["id"])) == "done":
			n += 1
	return n


## 图腾下一个能给的任务（按顺序第一个没接过的）；进行中已满 MAX_ACTIVE 个、全部接过、或下一个的前提（requires）还没满足时返回空字典。
func next_offer() -> Dictionary:
	if not GameRules.flag("quests"):
		return {}
	if active_ids().size() >= MAX_ACTIVE:
		return {}
	for q: Dictionary in quests():
		if state_of(str(q["id"])) == "":
			return q if requirements_met(q) else {}
	return {}


## 按顺序第一个没接过、但前提（requires 里的 flags）还没满足的任务：图腾先说它的 wait 那句。
func waiting_quest() -> Dictionary:
	if not GameRules.flag("quests"):
		return {}
	for q: Dictionary in quests():
		if state_of(str(q["id"])) == "":
			return {} if requirements_met(q) else q
	return {}


static func requirements_met(q: Dictionary) -> bool:
	for key in q.get("requires", []):
		if not bool(WorldState.flags.get(str(key), false)):
			return false
	return true


## 暮烬之夜图腾讲的最后一个故事（按界面语言，一页一句）。
func finale_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var en := TranslationServer.get_locale().begins_with("en")
	for d: Dictionary in _data.get("finale", []):
		out.append(str(d.get("en" if en else "zh", "")))
	return out


## 完成了但图腾还没说过谢谢的任务（对话里先说这些）。
func unthanked() -> Array:
	var out := []
	for q: Dictionary in quests():
		var s: Dictionary = WorldState.quests.get(str(q["id"]), {})
		if str(s.get("state", "")) == "done" and not bool(s.get("thanked", false)):
			out.append(q)
	return out


func accept(id: String) -> bool:
	if get_quest(id).is_empty() or state_of(id) != "":
		return false
	WorldState.quests[id] = {"state": "active", "progress": 0}
	EventBus.toast_requested.emit(tr("接到任务：%s") % text(get_quest(id), "title"))
	_changed()
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player != null:
		evaluate(player)
	return true


func mark_thanked(id: String) -> void:
	var s: Dictionary = WorldState.quests.get(id, {})
	if not s.is_empty():
		s["thanked"] = true
		_changed()


# ---------------------------------------------------------------- 目标检查

## 检查所有进行中的任务；返回这次新完成的任务 id。
func evaluate(player: FirstPersonController) -> Array:
	var finished := []
	for id: String in active_ids():
		var q := get_quest(id)
		var objs: Array = q.get("objectives", [])
		var all_ok := true
		var progress := 0
		for o: Dictionary in objs:
			var p := objective_progress(o, player)
			progress += int(p.x)
			if p.x < p.y:
				all_ok = false
		var s: Dictionary = WorldState.quests[id]
		if int(s.get("progress", 0)) != progress:
			s["progress"] = progress
			_changed()
		if all_ok:
			s["state"] = "done"
			finished.append(id)
			EventBus.toast_requested.emit(tr("任务完成：%s") % text(q, "title"))
			quest_completed.emit(id)
			_changed()
	return finished


## 一个目标的进度：Vector2i(已完成, 需要)。
func objective_progress(o: Dictionary, player: FirstPersonController) -> Vector2i:
	var pos := player.global_position
	match str(o["type"]):
		"sit":
			for uid: String in _sat:
				if uid.begins_with(str(o["prefix"])):
					return Vector2i(1, 1)
			return Vector2i(0, 1)
		"discover":
			var ids: Array = o["ids"]
			var n := 0
			for d in ids:
				if StringName(d) in WorldState.discoveries:
					n += 1
			return Vector2i(n, ids.size())
		"reach":
			var t := WorldLayout.v2(o["pos"])
			return Vector2i(1 if Vector2(pos.x, pos.z).distance_to(t) <= float(o["radius"]) else 0, 1)
		"zone_event":
			var zone := StringName(o["zone"])
			var glade := get_tree().get_first_node_in_group("fairy_glade") as FairyGlade
			var inside := zone in WorldState.zones_of(player.entity_id)
			return Vector2i(1 if inside and glade != null and glade.active else 0, 1)
		"rainbow":
			var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
			var seen := env != null and env.rainbow > 0.5 and not WorldState.is_indoors(player.entity_id)
			return Vector2i(1 if seen else 0, 1)
		"constellations":
			var need := int(o["count"])
			var stars_seen: Array = WorldState.journal_list("constellations")
			if o.has("ids"):
				stars_seen = stars_seen.filter(func(c: Variant) -> bool: return str(c) in o["ids"])
			return Vector2i(mini(stars_seen.size(), need), need)
		"species":
			var need_s := int(o["count"])
			return Vector2i(mini(WorldState.journal_list("species").size(), need_s), need_s)
		"swim":
			var w := player.current_water
			var in_it := w != null and str(w.volume_id) == str(o["volume"])
			if in_it:
				_sat["swim:" + str(o["volume"])] = true
			return Vector2i(1 if _sat.has("swim:" + str(o["volume"])) else 0, 1)
		"flag":
			return Vector2i(1 if bool(WorldState.flags.get(str(o["key"]), false)) else 0, 1)
		"letters":
			var need_l := int(o["count"])
			return Vector2i(mini(PaddlerStory.read_ids().size(), need_l), need_l)
		"emote_at":
			var key := str(o["id"])
			if player.emote == key:
				_emotes[key] = Vector2(pos.x, pos.z)
			var where: Variant = _emotes.get(key)
			var ok: bool = where != null and (where as Vector2).distance_to(WorldLayout.v2(o["pos"])) <= float(o["radius"])
			return Vector2i(1 if ok else 0, 1)
	return Vector2i(0, 1)


func _on_interactable(uid: StringName, state: String) -> void:
	# 座位被本机玩家坐下时状态变成 "occupied"
	if state == "occupied":
		_sat[String(uid)] = true


# ---------------------------------------------------------------- 图鉴

## 记一条图鉴（kind：species / constellations）；新的返回 true 并提示。
func record(kind: String, id: String, label: String) -> bool:
	if not GameRules.flag("journal"):
		return false
	if not WorldState.journal_add(kind, id):
		return false
	var fmt := tr("图鉴新增：%s") if kind == "species" else tr("认出了星座：%s")
	EventBus.toast_requested.emit(fmt % label)
	_changed()
	return true


func _record_animals(player: FirstPersonController) -> void:
	var p := player.global_position
	for a in get_tree().get_nodes_in_group("fauna"):
		var an := a as Animal
		if an == null or not an.visible or an.species_id == "":
			continue
		if an.global_position.distance_squared_to(p) <= SEEN_RADIUS * SEEN_RADIUS:
			record("species", an.species_id, species_label(an.species_id))
	for school in get_tree().get_nodes_in_group("aquatic_life"):
		for m: Dictionary in (school as FishSchool).members:
			var node := m["node"] as Node3D
			if node.global_position.distance_squared_to(p) <= FISH_RADIUS * FISH_RADIUS:
				var sid := str(m["group"])
				if sid != "":
					record("species", sid, species_label(sid))


static func species_label(id: String) -> String:
	return TranslationServer.translate(str(FaunaData.species(id).get("name", id)))


# ---------------------------------------------------------------- 读写

func _changed() -> void:
	changed.emit()
	if persist:
		SaveManager.request_save()



## 自动检查用：清空任务与图鉴（不碰磁盘）。
func reset() -> void:
	WorldState.quests = {}
	WorldState.journal = {}
	_emotes.clear()
	_sat.clear()
	changed.emit()
