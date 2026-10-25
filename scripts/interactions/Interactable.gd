class_name Interactable
extends Node3D
## 可交互对象基类。玩家与未来的 NPC 都通过 InteractionSystem.interact(actor, target) 调用，
## 具体动作由子类提供。uid 必须稳定，用于存档与以后的多人同步（不要用节点路径存档）。

@export var uid: StringName = &""
@export var display_name := ""


func _ready() -> void:
	add_to_group("interactables")
	# 读过档或从别的世界回来：按存下的状态摆（门开着、灯亮着）；第一次出现就登记现在的状态
	if uid != &"" and WorldState.interactables.has(uid):
		_adopt_saved.call_deferred()
	else:
		WorldState.register_interactable(uid, get_state())


func _adopt_saved() -> void:
	var saved := WorldState.get_interactable_state(uid)
	if saved != "" and saved != get_state():
		apply_state(saved)


func get_prompt(_actor: Node) -> String:
	return ""


func can_interact(_actor: Node) -> bool:
	return true


func interact(_actor: Node) -> void:
	pass


## 可序列化的状态字符串，例如门的 "open" / "closed"。
func get_state() -> String:
	return ""


## 读档时恢复状态（无动画）。M4 的 SaveManager 调用。
func apply_state(_state: String) -> void:
	pass


## 联机时别的玩家改了这个物体（由 Net 调用）。默认同读档；有动画的子类（门）可以改成带动画。
func apply_remote_state(state: String) -> void:
	apply_state(state)


func _publish_state() -> void:
	WorldState.set_interactable_state(uid, get_state())
