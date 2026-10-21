extends Node
## 本地玩家的个人资料（Autoload）：人物外观与玩家名字。
## 默认外观来自 data/characters/default_appearance.json；玩家在“外观”面板保存后写入 user://appearance.json，
## 下次启动自动读回。外观对象被本地玩家的 CharacterModel 与外观面板共用，改动实时生效。
## 名字（聊天和联机里显示）存 user://profile.json；没起名时按当前语言显示默认名（Traveler / 旅人）。

signal name_changed

const DEFAULT_PATH := "res://data/characters/default_appearance.json"
const SAVE_PATH := "user://appearance.json"
const PROFILE_PATH := "user://profile.json"
const LEGACY_CHAT_PATH := "user://chat.json"   ## 早期聊天框单独存名字的位置，读到后迁移
const MAX_NAME_LENGTH := 16

var appearance: CharacterAppearance
var display_name := ""


func _init() -> void:
	appearance = default_appearance()
	if FileAccess.file_exists(SAVE_PATH):
		var saved := CharacterAppearance.from_file(SAVE_PATH)
		for slot in saved.styles:
			appearance.styles[slot] = saved.styles[slot]
		for key in saved.colors:
			appearance.colors[key] = saved.colors[key]
	for path in [PROFILE_PATH, LEGACY_CHAT_PATH]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if parsed is Dictionary and _valid_name(str(parsed.get("name", ""))):
			display_name = str(parsed["name"]).strip_edges()
			break


static func default_appearance() -> CharacterAppearance:
	return CharacterAppearance.from_file(DEFAULT_PATH)


func save_appearance() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(appearance.to_dict(), "  "))
	return true


func reset_appearance() -> void:
	appearance.assign(default_appearance())


## 显示用的名字：起过名就用起的名，否则用当前语言的默认名。
func player_name() -> String:
	return display_name if not display_name.is_empty() else tr("旅人")


func set_display_name(new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if not _valid_name(new_name):
		return false
	display_name = new_name
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"name": display_name}, "  "))
	name_changed.emit()
	return true


static func _valid_name(n: String) -> bool:
	n = n.strip_edges()
	return not n.is_empty() and n.length() <= MAX_NAME_LENGTH
