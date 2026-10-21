class_name PlayerHold
extends RefCounted
## 让本地人物原地站定：借用 autopilot（方向为零，重力照常），键盘不再驱动人物。
## 聊天框、大厅菜单、联机时的暂停菜单共用；任一持有者还在就保持站定，全部松开后才交还键盘。
## 如果 autopilot 已被别人（自动测试、回放）占用，就不接管。

static var _holders := {}
static var _player: FirstPersonController = null


static func set_held(holder: Object, tree: SceneTree, hold: bool) -> void:
	if hold:
		_holders[holder.get_instance_id()] = true
	else:
		_holders.erase(holder.get_instance_id())
	if not _holders.is_empty():
		var p := tree.get_first_node_in_group("local_player") as FirstPersonController
		if p != null and _player == null and not p.autopilot_enabled:
			p.autopilot_direction = Vector3.ZERO
			p.autopilot_run = false
			p.autopilot_enabled = true
			_player = p
	elif _player != null:
		if is_instance_valid(_player):
			_player.autopilot_enabled = false
		_player = null


static func is_held() -> bool:
	return not _holders.is_empty()
