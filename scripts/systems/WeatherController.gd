class_name WeatherController
extends Node
## 【M2 待实现 · 接口占位】天气规则 / 过渡 / 随机种子。与季节独立，“秋季雨天”= AUTUMN + LIGHT_RAIN。
## 本文件在 M0/M1 中不参与运行：没有注册为 Autoload，也没有挂到任何场景。
## 它只固定模块边界与协议，避免后续各系统各自计时、各自算天气。
##
## 计划接口：
##   var weather_id: StringName         # CLEAR / OVERCAST / LIGHT_RAIN / HEAVY_RAIN / FOG / SNOW
##   var weather_seed: int              # 读档恢复，不重新随机
##   func request_weather(id: StringName, transition_seconds: float) -> void
##   发出 EventBus.weather_transition_started(from, to, duration) 与 weather_changed(id)
##   冬季不下雨、非冬季不下雪；室内（cabin_interior）禁止降水粒子
##   配置：data/weather/*.tres（WeatherProfile Resource）

const MILESTONE := "M2"
const IMPLEMENTED := false
