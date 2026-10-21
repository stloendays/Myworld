extends Node
## 本地玩家的个人资料（Autoload）：目前保存人物外观。
## 默认外观来自 data/characters/default_appearance.json；玩家在“外观”面板保存后写入 user://appearance.json，
## 下次启动自动读回。外观对象被本地玩家的 CharacterModel 与外观面板共用，改动实时生效。

const DEFAULT_PATH := "res://data/characters/default_appearance.json"
const SAVE_PATH := "user://appearance.json"

var appearance: CharacterAppearance


func _init() -> void:
	appearance = default_appearance()
	if FileAccess.file_exists(SAVE_PATH):
		var saved := CharacterAppearance.from_file(SAVE_PATH)
		for slot in saved.styles:
			appearance.styles[slot] = saved.styles[slot]
		for key in saved.colors:
			appearance.colors[key] = saved.colors[key]


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
