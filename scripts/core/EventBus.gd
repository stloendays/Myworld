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
signal zone_entered(zone_id: StringName, actor_id: StringName)
@warning_ignore("unused_signal")
signal zone_exited(zone_id: StringName, actor_id: StringName)
@warning_ignore("unused_signal")
signal interactable_state_changed(uid: StringName, state: String)
@warning_ignore("unused_signal")
signal interaction_prompt_changed(text: String)
