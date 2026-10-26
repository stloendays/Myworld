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
var input_locked := false   ## 打开棋盘等全屏界面时为 true：不读移动、视角和交互键
## 动作（动作栏 / 数字键）："ground_sit" 席地坐、"lie" 躺下、"wave" 挥手、"dance" 跳舞、"clap" 鼓掌；"" = 没有。
## 坐、躺、跳舞一直保持，按移动键 / 空格 / E 起身；挥手、鼓掌做完自动结束。
const EMOTES := ["ground_sit", "lie", "wave", "dance", "clap"]
const EMOTE_NAMES := {"ground_sit": "坐下", "lie": "躺下", "wave": "挥手", "dance": "跳舞", "clap": "鼓掌"}
const EMOTE_POSES := ["ground_sit", "lie"]
const GESTURE_SECONDS := {"wave": 2.6, "clap": 2.8}
var emote := ""

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
var _emote_time := 0.0
var _emote_view_forced := false
var _pose_head := Vector3.ZERO   ## 坐地 / 躺下时眼睛相对站姿的偏移


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
		arms.set_size(GameSettings.hand_size)


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
	end_emote()
	_leave_ride()
	global_position = pos
	velocity = Vector3.ZERO
	if yaw_deg < INF:
		rotation.y = deg_to_rad(-yaw_deg)
		head.rotation.x = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_controlled or input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := GameSettings.mouse_sensitivity
		var dy: float = event.relative.y * s * (-1.0 if GameSettings.invert_y else 1.0)
		rotate_y(-event.relative.x * s)
		var limit := deg_to_rad(pitch_limit_deg)
		head.rotation.x = clampf(head.rotation.x - dy, -limit, limit)
	elif event.is_action_pressed("interact"):
		try_interact()
	elif event.is_action_pressed("use_hand") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"):
		use_hand()
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
	if emote != "" and _emote_tick(delta):
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
		arms.visible = not third_person and emote != "lie"
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
	var pose_target := Vector3.ZERO
	if emote == "ground_sit":
		pose_target = Vector3(0.0, -0.72, 0.0)
	elif emote == "lie":
		pose_target = Vector3(0.0, 0.32 - _head_base.y, 0.78)
	_pose_head = _pose_head.lerp(pose_target, 1.0 - exp(-6.0 * delta))
	head.position = _head_base + _pose_head + Vector3(cos(_bob_phase) * 0.025, -absf(sin(_bob_phase)) * 0.045, 0.0) * _bob_amount


func _fly(delta: float) -> void:
	var dir: Vector3
	if autopilot_enabled:
		dir = autopilot_direction.normalized() if autopilot_direction.length_squared() > 1e-6 else Vector3.ZERO
	elif is_local_controlled and not input_locked:
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
	if not is_local_controlled or input_locked:
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
		if not autopilot_enabled and is_local_controlled and not input_locked and Input.is_action_just_pressed("jump"):
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
	if not is_local_controlled or input_locked:
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
	if is_riding() or emote in EMOTE_POSES:
		var seated_target: Interactable = null
		if seat != null:
			seated_target = _current_target()
			if seated_target is Seat:
				seated_target = null
		var text := "E  下船（靠近码头或岸边）  ·  W/S 划  A/D 转向  Shift 用力划"
		if seat != null:
			text = tr(seated_target.get_prompt(self)) + tr("    ·    E 对着别处：站起来") if seated_target != null else "E  站起来（或按移动键）"
		elif emote in EMOTE_POSES:
			text = "E  站起来（或按移动键）"
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
	if emote in EMOTE_POSES:
		end_emote()
		return true
	if seat != null:
		# 坐着也能用准星对着的东西（例如坐在沙发上下棋）；没对着东西就站起来
		interact_ray.force_raycast_update()
		var near := _current_target()
		if near != null and near != seat and not near is Seat and InteractionSystem.interact(self, near):
			return true
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


## 右键“用手”：准星对着能用的东西（门、灯、座位、船、棋盘……）就和按 E 一样去用，手往前一伸；
## 什么都没对着就挥挥右手（第一人称看得到自己的手在挥，联机时别人看到方块人挥手，不切换视角）。
func use_hand() -> bool:
	if try_interact():
		return true
	if is_riding() or swimming or flying:
		return false
	if arms != null:
		arms.wave()
	if emote == "wave":
		return true
	return do_emote("wave", false)


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
	end_emote()
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
		var moving := is_local_controlled and not autopilot_enabled and not input_locked and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5
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
	elif is_local_controlled and not input_locked:
		throttle = Input.get_axis("move_back", "move_forward")
		steer = Input.get_axis("move_left", "move_right")
		sprint = Input.is_action_pressed("sprint")
	boat.throttle = throttle
	boat.steer = steer
	boat.sprint = sprint
	global_position = boat.seat_position() - Vector3(0.0, 12.0 * Wardrobe.px(), 0.0)
	body.rotation.y = boat.heading - rotation.y
	body.paddle_phase = boat.stroke_phase


# ---------------------------------------------------------------- 动作（动作栏 / 数字键 1–5）

## 开始一个动作；正在做同一个动作时再按一次 = 结束。返回是否有变化。
func do_emote(id: String, switch_view := true) -> bool:
	if not id in EMOTES:
		return false
	if emote == id:
		end_emote()
		return true
	if is_riding() or swimming or flying or not is_on_floor():
		if is_local_controlled:
			EventBus.toast_requested.emit(tr("现在不能%s") % tr(EMOTE_NAMES[id]))
		return false
	end_emote()
	emote = id
	_emote_time = 0.0
	velocity = Vector3.ZERO
	if id in EMOTE_POSES:
		body.pose = id
		if id == "lie":
			head.rotation.x = deg_to_rad(55.0)   # 躺下就抬眼看天
	else:
		body.set_gesture(id)
		if switch_view and GameSettings.emote_third_person and not third_person and is_local_controlled:
			set_third_person(true)
			_emote_view_forced = true
	_place_body()
	return true


func end_emote() -> void:
	if emote == "":
		return
	var was_lying := emote == "lie"
	emote = ""
	body.set_gesture("")
	if body.pose in EMOTE_POSES:
		body.pose = "stand"
	_place_body()
	if was_lying:
		head.rotation.x = 0.0
	if _emote_view_forced:
		_emote_view_forced = false
		set_third_person(false)


func _place_body() -> void:
	body.transform = emote_body_transform(emote)


## 身体模型相对角色原点的摆放：坐地时臀部贴地；躺下时整个人放倒，脚朝前、头在身后。联机时别人那边的方块人也用它。
static func emote_body_transform(id: String) -> Transform3D:
	match id:
		"ground_sit":
			return Transform3D(Basis(), Vector3(0.0, -12.0 * Wardrobe.px(), 0.0))
		"lie":
			return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.2, -0.9))
	return Transform3D.IDENTITY


## 每物理帧：想走动、进了水或手势做完就结束动作。坐着 / 躺着时原地不动（仍受重力），
## 返回 true 表示本帧已处理完（不再走常规移动）。
func _emote_tick(delta: float) -> bool:
	_emote_time += delta
	var wants_move := false
	if autopilot_enabled:
		wants_move = autopilot_direction.length_squared() > 0.01
	elif is_local_controlled and not input_locked:
		wants_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5 \
			or Input.is_action_just_pressed("jump")
	var timed_out := GESTURE_SECONDS.has(emote) and _emote_time > float(GESTURE_SECONDS[emote])
	if wants_move or timed_out or WaterVolume.find(get_tree(), global_position + Vector3(0.0, 0.9, 0.0)) != null:
		var was_pose := emote in EMOTE_POSES
		end_emote()
		return was_pose   # 起身这一帧不跳
	if not emote in EMOTE_POSES:
		return false
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	_update_focus()
	body.animate(delta, 0.0, true, head.rotation.x, run_speed)
	if arms != null:
		arms.visible = not third_person and emote != "lie"
		arms.animate(delta, 0.0, true, false, run_speed)
	camera_boom.spring_length = lerpf(camera_boom.spring_length, third_person_distance if third_person else 0.0, 1.0 - exp(-12.0 * delta))
	_update_bob(delta, 0.0)
	return true
