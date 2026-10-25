extends Node
## 全局事件总线（Autoload）。只传通知，不保存状态；状态以 WorldState 为准。
## M0/M1 已使用：zone_entered / zone_exited / interactable_state_changed / interaction_prompt_changed。
## M2+ 预留（目前没有发送方）：time_changed / season_changed / weather_transition_started /
## weather_changed / save_loaded。

@warning_ignore("unused_signal")
signal time_changed(hour_fraction: float)
@warning_ignore("unused_signal")
signal season_changed(from_id: StringName, to_id: StringName)
@warning_ignore("unused_signal")
signal weather_transition_started(from_id: StringName, to_id: StringName, duration: float)
@warning_ignore("unused_signal")
signal weather_changed(weather_id: StringName)
@warning_ignore("unused_signal")
signal save_loaded(schema_version: int)
@warning_ignore("unused_signal")
signal lightning_strike(distance_m: float)   ## 雷声延迟由 M3 的 AudioDirector 按距离计算

@warning_ignore("unused_signal")
signal zone_entered(zone_id: StringName, actor_id: StringName)
@warning_ignore("unused_signal")
signal zone_exited(zone_id: StringName, actor_id: StringName)
@warning_ignore("unused_signal")
signal interactable_state_changed(uid: StringName, state: String)
@warning_ignore("unused_signal")
signal interaction_prompt_changed(text: String)
@warning_ignore("unused_signal")
signal discovered(poi_id: StringName)           ## 探索点第一次被发现（HUD 弹出提示，小地图标记）
@warning_ignore("unused_signal")
signal toast_requested(text: String)            ## 屏幕中上方的短提示（几秒后消失）
@warning_ignore("unused_signal")
signal collected(world_id: String, item_id: String)   ## 捡到一件收集品（云珠、古代碎片……）
@warning_ignore("unused_signal")
signal photo_taken(subjects: Array)                  ## F12 拍照时认出的摄影清单对象 id
