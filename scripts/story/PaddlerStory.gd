class_name PaddlerStory
extends Node
## 划船人的信（世界观落地①，2026-10-26）：前一位旅人留下三封信，每封写着石头小屋三环锁的一个图案。
## 内容在 data/story/letters.json；读过的信 id 记在 WorldState.flags.letters（按读到的顺序），
## 开过锁记 flags.cottage_unlocked（门的状态另由 CottageDoor 按 uid 存）。
## 本节点挂在 Main 下，按 world_layout.json → letters 摆出湖边的两处信（码头木盒、湖心小岛铁盒）；
## 木屋里那本旧书是室内物件，由 CabinLife 按木屋局部坐标摆放。
## 第四封信 farewell 在暮烬之夜、老图腾讲完最后一个故事以后出现在石头小屋的书桌上（StoneCottage 摆放，StoryDirector 决定时机）。

const DATA_PATH := "res://data/story/letters.json"
const FAREWELL := "farewell"   ## 暮烬之夜以后书桌上的第四封信（不算进三封信，读过记 flags.farewell_read）

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"letters": []}
	return _data


static func letters() -> Array:
	return data().get("letters", [])


static func letter(id: String) -> Dictionary:
	if id == FAREWELL:
		return data().get(FAREWELL, {})
	for l: Dictionary in letters():
		if str(l["id"]) == id:
			return l
	return {}


## 按界面语言取文字（与 QuestLog.text 相同：英文界面取 key_en）。
static func text(d: Dictionary, key: String) -> String:
	return QuestLog.text(d, key)


static func signature() -> String:
	var s: Dictionary = data().get("signature", {})
	return str(s.get("en", "")) if TranslationServer.get_locale().begins_with("en") else str(s.get("zh", ""))


static func read_ids() -> Array:
	return WorldState.flags.get("letters", [])


static func is_read(id: String) -> bool:
	if id == FAREWELL:
		return bool(WorldState.flags.get("farewell_read", false))
	return id in read_ids()


static func all_read() -> bool:
	for l: Dictionary in letters():
		if not is_read(str(l["id"])):
			return false
	return true


## 记一封读过的信；第一次读返回 true。存一个新数组（快照只浅拷贝 flags）。
static func mark_read(id: String) -> bool:
	if letter(id).is_empty() or is_read(id):
		return false
	if id == FAREWELL:
		WorldState.flags["farewell_read"] = true
		SaveManager.request_save()
		return true
	var list: Array = read_ids().duplicate()
	list.append(id)
	WorldState.flags["letters"] = list
	SaveManager.request_save()
	return true


static func unlocked() -> bool:
	return bool(WorldState.flags.get("cottage_unlocked", false))


## 已经知道的锁上图案（按信的顺序，不按读到的顺序）。
static func known_symbols() -> PackedStringArray:
	var out := PackedStringArray()
	for l: Dictionary in letters():
		if is_read(str(l["id"])):
			out.append(text(l, "symbol_name"))
	return out


func _ready() -> void:
	add_to_group("paddler_story")
	var spots: Dictionary = WorldLayout.section("letters")
	for id: String in spots:
		if id.begins_with("_"):
			continue
		var cfg: Dictionary = spots[id]
		var l := letter(id)
		if l.is_empty():
			continue
		var p := WorldLayout.v2(cfg["pos"])
		var y := float(cfg["y"]) if cfg.has("y") else WorldTerrain.height_at(p.x, p.y)
		var spot := LetterSpot.create(id, str(l["kind"]))
		spot.position = Vector3(p.x, y, p.y)
		spot.rotation.y = deg_to_rad(float(cfg.get("yaw_deg", 0.0)))
		add_child(spot)
