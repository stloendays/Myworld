class_name Wardrobe
extends RefCounted
## 衣橱目录（data/characters/wardrobe.json）：身体部位、各插槽（脸/发型/帽子/上衣/下装/鞋/背饰）的款式。
## 只读数据。新增款式 = 在 JSON 对应 slot 下加条目，代码不用改。

const PATH := "res://data/characters/wardrobe.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Wardrobe: 无法解析 %s" % PATH)
	return _data


static func px() -> float:
	return float(data().get("px_meters", 0.05625))


static func parts() -> Dictionary:
	return data().get("parts", {})


static func slot_order() -> Array:
	return data().get("slot_order", [])


static func slot_label(slot: String) -> String:
	return str(data().get("slot_labels", {}).get(slot, slot))


static func color_label(key: String) -> String:
	return str(data().get("color_labels", {}).get(key, key))


static func editable_colors() -> Array:
	return data().get("color_labels", {}).keys()


static func styles(slot: String) -> Array:
	return data().get("slots", {}).get(slot, {}).keys()


static func style_label(slot: String, style: String) -> String:
	return str(data().get("slots", {}).get(slot, {}).get(style, {}).get("label", style))


static func pieces(slot: String, style: String) -> Array:
	return data().get("slots", {}).get(slot, {}).get(style, {}).get("pieces", [])


static func body() -> Array:
	return data().get("body", [])
