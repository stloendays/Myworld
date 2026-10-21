class_name WorldClock
extends Node
## 世界时间：只有它推进时间。默认游戏内一天 = 现实 48 分钟（data/seasons/seasons.json）。
## 写入 WorldState.world_day / time_minutes，每过一个游戏分钟发一次 EventBus.time_changed。
## WorldState.time_paused 暂停计时，time_scale 用于调试加速；暂停菜单打开时整个场景树暂停，时钟也停。

var _last_minute := -1


func _ready() -> void:
	add_to_group("world_clock")


func _process(delta: float) -> void:
	if WorldState.time_paused:
		return
	advance(delta * ClimateData.game_minutes_per_real_second() * WorldState.time_scale)


## 推进若干游戏分钟（可跨天）。
func advance(game_minutes: float) -> void:
	var t := WorldState.time_minutes + game_minutes
	while t >= ClimateData.MINUTES_PER_DAY:
		t -= ClimateData.MINUTES_PER_DAY
		WorldState.world_day += 1
	WorldState.time_minutes = t
	_emit_if_new_minute()


func set_time(world_day: int, minutes: float) -> void:
	WorldState.world_day = maxi(world_day, 1)
	WorldState.time_minutes = fposmod(minutes, ClimateData.MINUTES_PER_DAY)
	_last_minute = -1
	_emit_if_new_minute()


func _emit_if_new_minute() -> void:
	var m := int(WorldState.absolute_minutes())
	if m != _last_minute:
		_last_minute = m
		EventBus.time_changed.emit(WorldState.hour_fraction())
