class_name FirstPersonController
extends CharacterBody3D
## 第一人称角色（CharacterBody3D）。与地图解耦：不引用场景中的任何固定路径。
## WASD 移动、鼠标环视、Shift 奔跑、空格跳跃、E 交互（相机中心射线 2.5 m）。
## autopilot_* 供自动化测试与以后的 NPC / 回放使用：开启后忽略键盘输入，按给定世界方向移动。
## 只有 is_local_controlled 的实例读取输入、拥有当前相机（为将来多人预留）。

@export var entity_id: StringName = &"player_local"
@export var is_local_controlled := true
@export var walk_speed := 3.2
@export var run_speed := 5.2
@export var acceleration := 9.0
@export var deceleration := 11.0
@export var air_control := 0.3
@export var jump_velocity := 4.2
@export var pitch_limit_deg := 85.0
@export var interact_distance := 2.5

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay

var autopilot_enabled := false
var autopilot_direction := Vector3.ZERO
var autopilot_run := false

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _focused: Interactable = null


func _ready() -> void:
	add_to_group("actors")
	if is_local_controlled:
		add_to_group("local_player")
		camera.current = true
	interact_ray.target_position = Vector3(0.0, 0.0, -interact_distance)
	interact_ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	interact_ray.add_exception(self)
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	camera.fov = GameSettings.fov


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_controlled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := GameSettings.mouse_sensitivity
		var dy: float = event.relative.y * s * (-1.0 if GameSettings.invert_y else 1.0)
		rotate_y(-event.relative.x * s)
		var limit := deg_to_rad(pitch_limit_deg)
		head.rotation.x = clampf(head.rotation.x - dy, -limit, limit)
	elif event.is_action_pressed("interact"):
		try_interact()


func _physics_process(delta: float) -> void:
	var wish := _wish_direction()
	var running := autopilot_run if autopilot_enabled else Input.is_action_pressed("sprint")
	var speed := run_speed if running else walk_speed

	if is_on_floor():
		if not autopilot_enabled and is_local_controlled and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if wish != Vector3.ZERO else deceleration
	if not is_on_floor():
		rate *= air_control
	horizontal = horizontal.lerp(wish * speed, 1.0 - exp(-rate * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_update_focus()


func _wish_direction() -> Vector3:
	if autopilot_enabled:
		var d := Vector3(autopilot_direction.x, 0.0, autopilot_direction.z)
		return d.normalized() if d.length_squared() > 1e-6 else Vector3.ZERO
	if not is_local_controlled:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var d := global_transform.basis * Vector3(input.x, 0.0, input.y)
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.ZERO


func _current_target() -> Interactable:
	if not interact_ray.is_colliding():
		return null
	return InteractionSystem.find_target(interact_ray.get_collider())


func _update_focus() -> void:
	var target := _current_target()
	if target != _focused:
		_focused = target
		if is_local_controlled:
			EventBus.interaction_prompt_changed.emit(target.get_prompt(self) if target != null else "")


func focused_target() -> Interactable:
	return _focused


## 对准星所指的对象执行交互；返回是否成功。
func try_interact() -> bool:
	interact_ray.force_raycast_update()
	var target := _current_target()
	if not InteractionSystem.interact(self, target):
		return false
	_focused = target
	if is_local_controlled:
		EventBus.interaction_prompt_changed.emit(target.get_prompt(self))
	return true


## 让视线看向世界坐标中的一点（测试、过场、出生朝向使用）。
func look_at_point(point: Vector3) -> void:
	var eye := head.global_position
	var d := point - eye
	rotation.y = atan2(-d.x, -d.z)
	var horizontal := Vector2(d.x, d.z).length()
	var limit := deg_to_rad(pitch_limit_deg)
	head.rotation.x = clampf(atan2(d.y, horizontal), -limit, limit)


## 水平朝向（度，0 = 北 / -Z，顺时针为正）。
func heading_degrees() -> float:
	return fposmod(-rad_to_deg(rotation.y), 360.0)
