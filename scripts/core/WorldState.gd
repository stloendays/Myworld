extends Node
## 世界状态的唯一权威（Autoload，内存版）。
## M1 已实现：可交互物状态（按稳定 uid）、角色所在区域（按 entity_id）。
## M2 会加入日期/时间/季节/天气；M4 由 SaveManager 序列化为 user://saves/ 的版本化 JSON。
## 改动存档字段时必须同时升级 SCHEMA_VERSION 并写迁移。

const SCHEMA_VERSION := 1

var world_seed: int = 0
var interactables: Dictionary = {}   ## uid -> state 字符串
var flags: Dictionary = {}

var _actor_zones: Dictionary = {}    ## actor_id -> { zone_id: is_indoor }


func _ready() -> void:
	world_seed = int(WorldLayout.section("terrain").get("seed", 0))


func register_interactable(uid: StringName, state: String) -> void:
	if uid == &"":
		push_warning("WorldState: 可交互物缺少 uid，无法存档。")
		return
	interactables[uid] = state


func set_interactable_state(uid: StringName, state: String) -> void:
	if uid == &"" or str(interactables.get(uid, "")) == state:
		return
	interactables[uid] = state
	EventBus.interactable_state_changed.emit(uid, state)


func get_interactable_state(uid: StringName) -> String:
	return str(interactables.get(uid, ""))


func enter_zone(actor_id: StringName, zone_id: StringName, is_indoor: bool) -> void:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	zones[zone_id] = is_indoor
	_actor_zones[actor_id] = zones
	EventBus.zone_entered.emit(zone_id, actor_id)


func exit_zone(actor_id: StringName, zone_id: StringName) -> void:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	if zones.erase(zone_id):
		EventBus.zone_exited.emit(zone_id, actor_id)


func zones_of(actor_id: StringName) -> Array:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	return zones.keys()


func is_indoors(actor_id: StringName) -> bool:
	var zones: Dictionary = _actor_zones.get(actor_id, {})
	for indoor in zones.values():
		if indoor:
			return true
	return false
