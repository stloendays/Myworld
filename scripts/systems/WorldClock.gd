class_name WorldClock
extends Node
## 【M2 待实现 · 接口占位】世界时间：日期 / 分钟 / 速度 / 暂停。只有它推进时间。
## 本文件在 M0/M1 中不参与运行：没有注册为 Autoload，也没有挂到任何场景。
## 它只固定模块边界与协议，避免后续各系统各自计时、各自算天气。
##
## 计划接口：
##   var world_day: int                 # 从 1 开始；季节由 world_day 与 season_days 派生
##   var time_minutes: float            # 0..1440；初次进入 = 秋季第 1 天 17:20（1040）
##   var minutes_per_real_second: float # 默认一天 = 现实 48 分钟 → 30
##   func set_paused(paused: bool) -> void
##   func set_time(day: int, minutes: float) -> void
##   发出 EventBus.time_changed(hour_fraction)

const MILESTONE := "M2"
const IMPLEMENTED := false
