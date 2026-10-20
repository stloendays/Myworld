class_name InteractableDoor
extends Interactable
## 铰链门：门板是 AnimatableBody3D，绕铰链（本节点原点）转动，会推开挡路的物体。
## 门板沿本地 +Z 方向展开，宽 1.2 m；open_angle_deg 为负时向本地 -X 一侧（室内）打开。

@export var open_angle_deg := -100.0
@export var swing_time := 0.7
@export var start_open := false

@onready var leaf: AnimatableBody3D = $Leaf

var _open := false
var _tween: Tween = null


func _ready() -> void:
	ArtMaterials.restyle_named(leaf)
	_open = start_open
	leaf.rotation.y = deg_to_rad(open_angle_deg) if _open else 0.0
	super()


func is_open() -> bool:
	return _open


func get_prompt(_actor: Node) -> String:
	return "E  关上木门" if _open else "E  打开木门"


func interact(_actor: Node) -> void:
	set_open(not _open)


func set_open(value: bool, instant := false) -> void:
	_open = value
	var target := deg_to_rad(open_angle_deg) if value else 0.0
	if _tween != null:
		_tween.kill()
	if instant:
		leaf.rotation.y = target
	else:
		_tween = create_tween()
		_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_tween.tween_property(leaf, "rotation:y", target, swing_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_publish_state()


func get_state() -> String:
	return "open" if _open else "closed"


func apply_state(state: String) -> void:
	set_open(state == "open", true)
