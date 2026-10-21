class_name CharacterAppearance
extends Resource
## 人物外观：每个插槽选哪一款（styles），以及各颜色键的颜色（colors）。
## 玩家、将来的 NPC 和其他玩家都用同一种数据，可序列化为 JSON（存档、联机同步只需传这个字典）。
## 修改后发出 Resource.changed，使用它的 CharacterModel 会自动重建外观。

const SCHEMA_VERSION := 1

@export var styles: Dictionary = {}   ## slot -> style id
@export var colors: Dictionary = {}   ## color key -> Color


func style(slot: String) -> String:
	return str(styles.get(slot, ""))


func color(key: String, fallback := Color.MAGENTA) -> Color:
	var c: Variant = colors.get(key, fallback)
	return c if c is Color else fallback


func set_style(slot: String, style_id: String) -> void:
	if styles.get(slot, "") == style_id:
		return
	styles[slot] = style_id
	emit_changed()


func set_color(key: String, value: Color) -> void:
	colors[key] = value
	emit_changed()


## 把另一份外观的内容复制过来（用于“恢复默认”）。
func assign(other: CharacterAppearance) -> void:
	styles = other.styles.duplicate()
	colors = other.colors.duplicate()
	emit_changed()


func to_dict() -> Dictionary:
	var c := {}
	for key in colors:
		c[key] = "#" + (colors[key] as Color).to_html(false)
	return {"schema_version": SCHEMA_VERSION, "styles": styles.duplicate(), "colors": c}


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	for slot in d.get("styles", {}):
		a.styles[str(slot)] = str(d["styles"][slot])
	for key in d.get("colors", {}):
		a.colors[str(key)] = Color.html(str(d["colors"][key]))
	return a


static func from_file(path: String) -> CharacterAppearance:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(parsed if parsed is Dictionary else {})
