class_name AudioDirector
extends Node
## 【M3 待实现 · 接口占位】音频 Bus（AMB_OUTDOOR / AMB_WEATHER / AMB_INDOOR / FOLEY / MUSIC / UI）、音区与淡入淡出。
## 本文件在 M0/M1 中不参与运行：没有注册为 Autoload，也没有挂到任何场景。
## 它只固定模块边界与协议，避免后续各系统各自计时、各自算天气。
##
## 计划接口：
##   订阅 EventBus.zone_entered / zone_exited（cabin_interior 已在 M1 提供）
##   进出室内：室外雨声 1.0–2.5 秒平滑衰减 + 低通，不瞬间切断
##   没有许可证的音效用静音占位并写 TODO

const MILESTONE := "M3"
const IMPLEMENTED := false
