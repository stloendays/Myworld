class_name InteractionSystem
extends RefCounted
## 统一交互契约：interact(actor, target)。不依赖某个具体木屋或 NPC。


## 从射线命中的碰撞体向上查找所属的 Interactable。
static func find_target(collider: Object) -> Interactable:
	var node := collider as Node
	while node != null:
		if node is Interactable:
			return node as Interactable
		node = node.get_parent()
	return null


static func interact(actor: Node, target: Interactable) -> bool:
	if target == null or not target.can_interact(actor):
		return false
	target.interact(actor)
	return true
