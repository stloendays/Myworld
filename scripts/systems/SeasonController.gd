class_name SeasonController
extends Node
## 季节：由世界日数推出（每季 12 个游戏日），或由 season_override 覆盖（开发测试 / 玩家手动）。
## 只负责“现在是什么季节”，写入 WorldState.season_id，变化时发 EventBus.season_changed。
## 季节的视觉表现由 EnvironmentDirector 根据季节配置执行，本模块不碰任何树木或材质节点。


func _ready() -> void:
	add_to_group("season_controller")
	EventBus.time_changed.connect(func(_h: float) -> void: refresh())
	refresh()


func current() -> StringName:
	if WorldState.season_override != null:
		return StringName(WorldState.season_override)
	return ClimateData.season_for_day(WorldState.world_day)


func refresh() -> void:
	var now := current()
	if now != WorldState.season_id:
		var from := WorldState.season_id
		WorldState.season_id = now
		EventBus.season_changed.emit(from, now)


## 覆盖季节（传 null 取消覆盖，恢复按日期计算）。
func set_override(season: Variant) -> void:
	WorldState.season_override = season
	refresh()
