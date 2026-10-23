class_name WorldRegistry
extends RefCounted
## 世界注册表：读取 data/worlds/worlds.json，提供世界列表、当前世界和它们之间的连线（世界地图使用）。
## 跨世界进入（enter）：已开放或“建设中可进入”（preview）的世界交给 WorldTravel 切换；规划中的世界只提示“还在建设中”。
## 当前所在的世界由 WorldTravel.current_world 记录（worlds.json 里的 current 只是启动时的世界）。

const PATH := "res://data/worlds/worlds.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"current": "", "worlds": [], "links": []}
	return _data


static func worlds() -> Array:
	return data()["worlds"]


static func links() -> Array:
	return data().get("links", [])


static func current_id() -> String:
	return WorldTravel.current_world


static func get_world(id: String) -> Dictionary:
	for w in worlds():
		if str(w["id"]) == id:
			return w
	return {}


static func current() -> Dictionary:
	return get_world(current_id())


## open = 已开放；preview = 建设中但可以进去看看（有一个占位场景）。
static func is_open(id: String) -> bool:
	return str(get_world(id).get("status", "")) in ["open", "preview"]


## 能否从当前世界前往 id（已开放、不是当前世界）。
static func can_enter(id: String) -> bool:
	return is_open(id) and id != current_id()


## 前往另一个世界：能去就交给 WorldTravel（先卸载本世界再加载目标世界），否则给出提示并返回 false。
static func enter(id: String) -> bool:
	var w := get_world(id)
	if w.is_empty():
		return false
	if can_enter(id):
		return WorldTravel.travel(id)
	if id == current_id():
		EventBus.toast_requested.emit(TranslationServer.translate("你就在「%s」") % TranslationServer.translate(str(w["name"])))
	else:
		EventBus.toast_requested.emit(TranslationServer.translate("「%s」还在建设中，以后从传送门进入") % TranslationServer.translate(str(w["name"])))
	return false
