class_name WorldRegistry
extends RefCounted
## 世界注册表：读取 data/worlds/worlds.json，提供世界列表、当前世界和它们之间的连线（世界地图使用）。
## 跨世界进入（enter）是为以后的“传送门进入其他世界”预留的接口：第二个世界做出来之前，
## 规划中的世界一律返回 false 并提示“还在建设中”。真正切换世界时再接入场景加载与存档（不属于本次改动）。

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
	return str(data()["current"])


static func get_world(id: String) -> Dictionary:
	for w in worlds():
		if str(w["id"]) == id:
			return w
	return {}


static func current() -> Dictionary:
	return get_world(current_id())


static func is_open(id: String) -> bool:
	return str(get_world(id).get("status", "")) == "open"


## 能否从当前世界前往 id（已开放、不是当前世界）。
static func can_enter(id: String) -> bool:
	return is_open(id) and id != current_id()


## 预留：前往另一个世界。目前没有第二个已开放的世界，所以只给出提示并返回 false。
static func enter(id: String) -> bool:
	var w := get_world(id)
	if w.is_empty():
		return false
	if id == current_id():
		EventBus.toast_requested.emit(TranslationServer.translate("你就在「%s」") % TranslationServer.translate(str(w["name"])))
	else:
		EventBus.toast_requested.emit(TranslationServer.translate("「%s」还在建设中，以后从传送门进入") % TranslationServer.translate(str(w["name"])))
	return false
