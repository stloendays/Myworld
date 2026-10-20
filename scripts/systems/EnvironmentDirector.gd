class_name EnvironmentDirector
extends Node
## 【M2 待实现 · 接口占位】把时钟/季节/天气状态映射为天空、太阳、雾、地表湿度与粒子参数。取代 M1 的 StaticDuskLighting。
## 本文件在 M0/M1 中不参与运行：没有注册为 Autoload，也没有挂到任何场景。
## 它只固定模块边界与协议，避免后续各系统各自计时、各自算天气。
##
## 计划接口：
##   订阅 EventBus.time_changed / season_changed / weather_transition_started / weather_changed
##   func apply_preset(name: StringName) -> void  # Autumn_Dusk_Clear / Autumn_Night_HeavyRain / Winter_Morning_Snow / Spring_Fog
##   不读写存档文件

const MILESTONE := "M2"
const IMPLEMENTED := false
