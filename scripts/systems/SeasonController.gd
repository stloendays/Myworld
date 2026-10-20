class_name SeasonController
extends Node
## 【M2 待实现 · 接口占位】季节计算与对应视觉参数请求（树叶色、地表、色温）。不直接引用具体树木节点。
## 本文件在 M0/M1 中不参与运行：没有注册为 Autoload，也没有挂到任何场景。
## 它只固定模块边界与协议，避免后续各系统各自计时、各自算天气。
##
## 计划接口：
##   var season_id: StringName          # SPRING / SUMMER / AUTUMN / WINTER
##   var season_override: Variant       # 仅开发测试或玩家手动覆盖；默认 null
##   func season_for_day(world_day: int) -> StringName
##   发出 EventBus.season_changed(from_id, to_id)
##   配置：data/seasons/*.tres（SeasonProfile Resource）

const MILESTONE := "M2"
const IMPLEMENTED := false
