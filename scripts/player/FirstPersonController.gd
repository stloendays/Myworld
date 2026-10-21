class_name FirstPersonController
extends CharacterBody3D
## 第一人称角色（CharacterBody3D）。与地图解耦：不引用场景中的任何固定路径。
## WASD 移动、鼠标环视、Shift 奔跑、空格跳跃、E 交互（眼睛位置的视线射线 2.5 m）、V 切换第一/第三人称。
## 身体是方块人物（CharacterModel，外观来自 PlayerProfile）；第一人称时身体只投影子、不进画面。
## 游泳：身体进入 WaterVolume（泳池、玻璃水管、下潜池）后切换为游泳——WASD 朝视线方向游、空格上浮、
## C / Ctrl 下潜；有水面的水体里自动浮起让头露出水面，在池边按空格爬上岸。湖不是 WaterVolume，只能涉水。
## 第一人称能看到自己的双手（FirstPersonArms，挂在相机下）。
## 开发者模式（F2）下按 F 飞行（空格上升、C / Ctrl 下降、Shift 加速），按 N 穿墙；关闭开发者模式自动落地。
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
@export var third_person_distance := 3.2
@export var third_person_offset := Vector3(0.45, 0.25, 0.0)
@export var swim_speed := 2.2
@export var swim_sprint_speed := 3.4

@onready var head: Node3D = $Head
@onready var camera_boom: SpringArm3D = $Head/CameraBoom
@onready var camera: Camera3D = $Head/CameraBoom/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var body: CharacterModel = $Body

const BODY_LAYER := 4   ## 渲染层 3（player_body）

var third_person := false
var swimming := false
var current_water: WaterVolume = null
var flying := false
var noclip := false
var arms: FirstPersonArms = null
var seat: Seat = null       ## 坐着时所在的座位（沙发、长椅、躺椅）
var boat: Canoe = null      ## 在独木舟上时所乘的船

var autopilot_enabled := false
var autopilot_direction := Vector3.ZERO
var autopilot_run := false

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _focused: Interactable = null
var _collision_mask := 0
var _bob_phase := 0.0
var _bob_amount := 0.0
var _head_base := Vector3.ZERO
var _ride_prompt := ""


func _ready() -> void:
	add_to_group("actors")
	_collision_mask = collision_mask
	_head_base = head.position
	if is_local_controlled:
		add_to_group("local_player")
		camera.current = true
		arms = FirstPersonArms.new()
		arms.name = "Arms"
		camera.add_child(arms)
	interact_ray.target_position = Vector3(0.0, 0.0, -interact_distance)
	interact_ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	interact_ray.add_exception(self)
	camera_boom.add_excluded_object(get_rid())
	set_third_person(GameSettings.third_person_default)
	GameSettings.changed.connect(_apply_settings)
	GameSettings.developer_mode_changed.connect(_on_developer_mode)
	_apply_settings()


func _apply_settings() -> void:
	camera.fov = GameSettings.fov
	third_person_distance = GameSettings.third_person_distance
	third_person_offset.x = absf(third_person_offset.x) * (-1.0 if GameSettings.shoulder_left else 1.0)
	if arms != null:
		arms.set_mode(GameSettings.first_person_arms)


func _on_developer_mode(enabled: bool) -> void:
	if not enabled:
		set_flying(false)
		set_noclip(false)


## 飞行（开发者模式）：不受重力，空格上升、C / Ctrl 下降。
func set_flying(enabled: bool) -> void:
	if enabled and is_riding():
		return
	flying = enabled
	if not enabled:
		set_noclip(false)
	velocity = Vector3.ZERO


## 穿墙（开发者模式，只在飞行时有效）：关掉与世界的碰撞。
func set_noclip(enabled: bool) -> void:
	noclip = enabled and flying
	collision_mask = 0 if noclip else _collision_mask


## 开发者传送：直接放到某点（读档、调试用；正常游玩进屋不走这里）。
func teleport_to(pos: Vector3, yaw_deg := INF) -> void:
	_leave_ride()
	global_position = pos
	velocity = Vector3.ZERO
	if yaw_deg < INF:
		rotation.y = deg_to_rad(-yaw_deg)
		head.rotation.x = 0.0


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
	elif event.is_action_pressed("toggle_view"):
		set_third_person(not third_person)
	elif event.is_action_pressed("toggle_fly") and GameSettings.developer_mode:
		set_flying(not flying)
	elif event.is_action_pressed("toggle_noclip") and GameSettings.developer_mode and flying:
		set_noclip(not noclip)


func _physics_process(delta: float) -> void:
	if is_riding():
		_ride(delta)
		_update_focus()
		body.animate(delta, 0.0, true, head.rotation.x, run_speed)
		if arms != null:
			arms.visible = not third_person
			arms.animate(delta, 0.0, true, boat != null and (absf(boat.throttle) > 0.05 or absf(boat.steer) > 0.05), run_speed)
		var ride_boom := third_person_distance if third_person else 0.0
		camera_boom.spring_length = lerpf(camera_boom.spring_length, ride_boom, 1.0 - exp(-12.0 * delta))
		_update_bob(delta, 0.0)
		return
	current_water = null if flying else WaterVolume.find(get_tree(), global_position + Vector3(0.0, 0.9, 0.0))
	swimming = current_water != null
	if flying:
		_fly(delta)
	elif swimming:
		_swim(delta)
	else:
		_walk(delta)
	move_and_slide()
	_update_focus()
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor() and not flying
	body.animate(delta, flat_speed + (absf(velocity.y) if swimming else 0.0), grounded or swimming, head.rotation.x, run_speed)
	if arms != null:
		arms.visible = not third_person
		arms.animate(delta, flat_speed, grounded, swimming, run_speed)
	var boom_target := third_person_distance if third_person else 0.0
	camera_boom.spring_length = lerpf(camera_boom.spring_length, boom_target, 1.0 - exp(-12.0 * delta))
	camera_boom.position = camera_boom.position.lerp(third_person_offset if third_person else Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	_update_bob(delta, flat_speed if grounded else 0.0)


## 走路时镜头轻微上下左右晃动（设置里可关）；只在第一人称。
func _update_bob(delta: float, speed: float) -> void:
	var target := clampf(speed / run_speed, 0.0, 1.0) if GameSettings.view_bob and not third_person else 0.0
	_bob_amount = lerpf(_bob_amount, target, 1.0 - exp(-8.0 * delta))
	_bob_phase += delta * speed * 2.4
	# 晃头节点而不是相机：相机挂在 SpringArm3D 下，位置每帧被弹簧臂改写
	head.position = _head_base + Vector3(cos(_bob_phase) * 0.025, -absf(sin(_bob_phase)) * 0.045, 0.0) * _bob_amount


func _fly(delta: float) -> void:
	var dir: Vector3
	if autopilot_enabled:
		dir = autopilot_direction.normalized() if autopilot_direction.length_squared() > 1e-6 else Vector3.ZERO
	elif is_local_controlled:
		dir = _wish_direction()
		if Input.is_action_pressed("jump"):
			dir.y += 1.0
		if Input.is_action_pressed("swim_down"):
			dir.y -= 1.0
		dir = dir.normalized() if dir.length_squared() > 1.0 else dir
	var running := autopilot_run if autopilot_enabled else Input.is_action_pressed("sprint")
	var target := dir * GameSettings.fly_speed * (3.0 if running else 1.0)
	velocity = velocity.lerp(target, 1.0 - exp(-6.0 * delta))


func _swim(delta: float) -> void:
	var dir := _swim_direction()
	var running := autopilot_run if autopilot_enabled else Input.is_action_pressed("sprint")
	var target := dir * (swim_sprint_speed if running else swim_speed)
	var surface := current_water.surface_y()
	var diving := dir.y < -0.2
	if surface < INF and not diving:
		# 浮力：把身体推向“眼睛露出水面约 0.35 m”的漂浮高度
		var float_y := surface - 1.3
		target.y += clampf((float_y - global_position.y) * 2.2, -0.8, 1.4)
	velocity = velocity.lerp(target, 1.0 - exp(-3.5 * delta))
	var head_y := global_position.y + 1.65
	var wants_up := (autopilot_enabled and autopilot_direction.y > 0.5) or (is_local_controlled and not autopilot_enabled and Input.is_action_just_pressed("jump"))
	if wants_up and surface < INF and head_y > surface - 0.2 and is_on_wall():
		# 在池边爬上岸
		velocity.y = 5.2
		velocity += -global_basis.z * 1.2


func _swim_direction() -> Vector3:
	if autopilot_enabled:
		return autopilot_direction.normalized() if autopilot_direction.length_squared() > 1e-6 else Vector3.ZERO
	if not is_local_controlled:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	var d := right * input.x - forward * input.y
	if Input.is_action_pressed("jump"):
		d.y += 1.0
	if Input.is_action_pressed("swim_down"):
		d.y -= 1.0
	return d.normalized() if d.length_squared() > 1.0 else d


func _walk(delta: float) -> void:
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


## 第一人称：相机在眼睛处，身体不进画面（仍投影子）；第三人称：相机退到肩后，身体可见。
func set_third_person(enabled: bool) -> void:
	third_person = enabled
	if enabled:
		camera.cull_mask = 0xFFFFF & ~FirstPersonArms.FP_ARMS_LAYER
	else:
		camera.cull_mask = 0xFFFFF & ~BODY_LAYER
	body.render_layers = BODY_LAYER
	if arms != null:
		arms.visible = not enabled


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
	if interact_ray.is_colliding():
		var hit := InteractionSystem.find_target(interact_ray.get_collider())
		if hit != null:
			return hit
	return _nearby_vehicle()


## 码头栏杆会挡住看向船的射线：离船 3.2 m 以内、视线大致朝着船（40° 以内）也算对准了它。
func _nearby_vehicle() -> Interactable:
	var eye := camera.global_position
	var look := -camera.global_basis.z
	for v in get_tree().get_nodes_in_group("vehicles"):
		var canoe := v as Canoe
		if canoe == null or canoe.rider != null:
			continue
		var to := canoe.global_position + Vector3(0.0, 0.2, 0.0) - eye
		if to.length() < 3.2 and look.angle_to(to) < deg_to_rad(40.0):
			return canoe
	return null


func _update_focus() -> void:
	if is_riding():
		var text := "E  站起来（或按移动键）" if seat != null else "E  下船（靠近码头或岸边）  ·  W/S 划  A/D 转向  Shift 用力划"
		if text != _ride_prompt and is_local_controlled:
			_ride_prompt = text
			EventBus.interaction_prompt_changed.emit(text)
		return
	if _ride_prompt != "":
		_ride_prompt = ""
		_focused = null
		if is_local_controlled:
			EventBus.interaction_prompt_changed.emit("")
	var target := _current_target()
	if target != _focused:
		_focused = target
		if is_local_controlled:
			EventBus.interaction_prompt_changed.emit(target.get_prompt(self) if target != null else "")


func focused_target() -> Interactable:
	return _focused


## 对准星所指的对象执行交互；返回是否成功。
func try_interact() -> bool:
	if seat != null:
		stand_up()
		return true
	if boat != null:
		return disembark()
	interact_ray.force_raycast_update()
	var target := _current_target()
	if not InteractionSystem.interact(self, target):
		return false
	if arms != null:
		arms.reach()
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


# ---------------------------------------------------------------- 坐下与划船

func is_riding() -> bool:
	return seat != null or boat != null


## 坐到座位上：关掉碰撞，定在坐垫上，腿向前伸；身体朝座位方向，头仍可自由环顾。
func sit(target: Seat) -> void:
	if is_riding() or target.occupant != null:
		return
	set_flying(false)
	seat = target
	target.occupant = self
	target._publish_state()
	_enter_ride("sit")
	rotation.y = target.global_rotation.y
	global_position = target.occupant_origin()


func stand_up() -> void:
	if seat == null:
		return
	var s := seat
	var p := s.exit_point()
	_leave_ride()
	global_position = p


## 上独木舟：坐到船里的座位，身体跟船走，按 W/S/A/D 划。
func board(canoe: Canoe) -> void:
	if is_riding() or canoe.rider != null:
		return
	set_flying(false)
	boat = canoe
	canoe.rider = self
	canoe._publish_state()
	_enter_ride("paddle")
	rotation.y = canoe.heading
	global_position = canoe.seat_position() - Vector3(0.0, 12.0 * Wardrobe.px(), 0.0)


## 下船：落到码头或最近的岸上；离岸太远时留在船上并提示。
func disembark() -> bool:
	if boat == null:
		return false
	var exit: Variant = boat.find_exit()
	if exit == null:
		EventBus.toast_requested.emit("离岸太远：划到岸边或码头再下船")
		return false
	_leave_ride()
	global_position = exit
	return true


func _enter_ride(pose: String) -> void:
	velocity = Vector3.ZERO
	collision_mask = 0
	body.pose = pose
	_focused = null


## 离开座位或船（不移动位置），恢复碰撞与站姿。
func _leave_ride() -> void:
	if seat != null:
		seat.occupant = null
		seat._publish_state()
		seat = null
	if boat != null:
		boat.rider = null
		boat.throttle = 0.0
		boat.steer = 0.0
		boat._publish_state()
		boat = null
	if body.pose != "stand":
		body.pose = "stand"
		body.rotation.y = 0.0
		collision_mask = 0 if noclip else _collision_mask
		velocity = Vector3.ZERO


## 坐着 / 划船时每帧：位置跟着座位或船，身体朝向座位或船头。
func _ride(_delta: float) -> void:
	velocity = Vector3.ZERO
	if seat != null:
		global_position = seat.occupant_origin()
		body.rotation.y = seat.global_rotation.y - rotation.y
		var moving := is_local_controlled and not autopilot_enabled and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5
		if moving or (autopilot_enabled and autopilot_direction.length_squared() > 0.01):
			stand_up()
		return
	var throttle := 0.0
	var steer := 0.0
	var sprint := false
	if autopilot_enabled:
		var d := Vector2(autopilot_direction.x, autopilot_direction.z)
		if d.length() > 0.01:
			var want := atan2(-d.x, -d.y)
			var diff := wrapf(want - boat.heading, -PI, PI)
			steer = clampf(-diff * 2.0, -1.0, 1.0)
			throttle = 1.0 if absf(diff) < 0.8 else 0.2
		sprint = autopilot_run
	elif is_local_controlled:
		throttle = Input.get_axis("move_back", "move_forward")
		steer = Input.get_axis("move_left", "move_right")
		sprint = Input.is_action_pressed("sprint")
	boat.throttle = throttle
	boat.steer = steer
	boat.sprint = sprint
	global_position = boat.seat_position() - Vector3(0.0, 12.0 * Wardrobe.px(), 0.0)
	body.rotation.y = boat.heading - rotation.y
	body.paddle_phase = boat.stroke_phase
