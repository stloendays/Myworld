class_name InteractableToggle
extends Interactable
## 开 / 关两态的可交互物（铸铁炉、落地灯、台灯、吊灯、门廊灯）。状态 "on" / "off"，按 uid 存档。
## 自带一个 INTERACTABLE 层的碰撞盒给准星射线命中；开关时发 toggled 信号，由所属建筑去改灯光和特效。

signal toggled(on: bool)

var on := false
var prompt_on := ""     ## 开着时的提示，例如 “E  熄灭炉火”
var prompt_off := ""    ## 关着时的提示，例如 “E  生火”


## size / offset：碰撞盒大小与相对本节点的位置。
static func create(id: StringName, label: String, start_on: bool, on_text: String, off_text: String, size: Vector3, offset := Vector3.ZERO) -> InteractableToggle:
	var t := InteractableToggle.new()
	t.name = "Toggle_" + String(id)
	t.uid = id
	t.display_name = label
	t.on = start_on
	t.prompt_on = on_text
	t.prompt_off = off_text
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)
	t.add_child(body)
	return t


func get_prompt(_actor: Node) -> String:
	return prompt_on if on else prompt_off


func interact(_actor: Node) -> void:
	set_on(not on)


func set_on(value: bool) -> void:
	on = value
	toggled.emit(on)
	_publish_state()


func get_state() -> String:
	return "on" if on else "off"


func apply_state(state: String) -> void:
	set_on(state == "on")
