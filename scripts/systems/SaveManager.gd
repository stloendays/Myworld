class_name SaveManager
extends Node
## 【M4 待实现 · 接口占位】WorldState 的版本化 JSON 存取与迁移，目录 user://saves/，临时文件 + 原子替换。
## 本文件在 M0/M1 中不参与运行：没有注册为 Autoload，也没有挂到任何场景。
## 它只固定模块边界与协议，避免后续各系统各自计时、各自算天气。
##
## 计划接口：
##   func save(slot: String) -> Error
##   func load(slot: String) -> Error      # 恢复后发出 EventBus.save_loaded(schema_version)
##   func migrate(data: Dictionary) -> Dictionary
##   可交互物按 uid 调用 Interactable.apply_state()

const MILESTONE := "M4"
const IMPLEMENTED := false
