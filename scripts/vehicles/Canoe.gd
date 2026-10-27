class_name Canoe
extends Interactable
## 可以划的独木舟（Kenney canoe 模型，红色）。停在码头南侧，从码头上看着它按 E 上船。
## 划船：W 向前划、S 倒划、A / D 转向，Shift 划得更快；E 下船（靠近码头或岸边时，会落到码头板上或最近的岸上）。
## 运动是自己算的（不走物理引擎，结果可复现）：
##   - 划桨推力按桨的节奏一下一下地给，水的阻力让速度收敛到约 3 m/s，转向有惯性；
##   - 参考开源浮力插件（WaterBox、FloatableBody）的做法，在船头、船尾、左右舷四个点取水面高度，
##     得到起伏、俯仰和横摇，风越大、雨越大浪越高；
##   - 船身四个点下面的水比吃水浅就算搁浅，码头桩区也挡船；无人划时随风慢慢漂。
## 位置和朝向每秒写进 WorldState.vehicles（存档用，M4 读档时恢复）。

const MODEL := "res://assets/imported/kenney/nature/canoe.glb"
const PADDLE := "res://assets/imported/kenney/nature/canoe_paddle.glb"
const MODEL_SCALE := 3.9
const HALF_LENGTH := 2.15
const HALF_WIDTH := 0.55
const DRAFT := 0.22                       ## 吃水：船底在水面下多深，水比这浅就搁浅
const SEAT := Vector3(0.0, 0.10, 0.55)    ## 船里坐的位置（臀部，本地坐标），略靠船尾
const THRUST := 1.7
const DRAG := 0.5
const TURN_RATE := 0.9
const STROKE_TIME := 1.15                 ## 一桨的时间（秒），Shift 时 0.85

var heading := 0.0          ## 等于 rotation.y：0 = 船头朝北（-Z）
var speed := 0.0            ## 沿船头方向的速度（m/s，倒划为负）
var yaw_rate := 0.0
var stroke_phase := 0.0
var throttle := 0.0         ## 由乘客每帧设置：-1..1
var steer := 0.0            ## -1..1，正 = 右转
var sprint := false
var grounded := false
var rider: Node = null
var paddle_side := 1.0

var _xz := Vector2.ZERO
var _hull: Node3D
var _paddle_pivot: Node3D
var _save_timer := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("vehicles")
	var cfg := WorldLayout.section("canoe")
	var saved: Dictionary = WorldState.vehicles.get(String(uid), {})
	var p: Array = saved.get("pos", cfg["pos"])
	_xz = Vector2(float(p[0]), float(p[1]))
	heading = -deg_to_rad(float(saved.get("yaw_deg", cfg.get("heading", 0.0))))
	_hull = ArtMaterials.kenney_prop(MODEL, Vector3(0.0, -DRAFT, 0.0), 0.0, MODEL_SCALE)
	add_child(_hull)
	_paddle_pivot = Node3D.new()
	_paddle_pivot.name = "PaddlePivot"
	_paddle_pivot.position = Vector3(0.0, 0.62, SEAT.z - 0.4)
	add_child(_paddle_pivot)
	var paddle := ArtMaterials.kenney_prop(PADDLE, Vector3.ZERO, 0.0, 3.2)
	# 桨模型沿 Z 平放；转成竖直（桨叶朝下），中点挂在双手处
	var holder := Node3D.new()
	holder.rotation.x = deg_to_rad(90.0)
	holder.position = Vector3(0.0, -0.3, 0.0)
	holder.add_child(paddle)
	_paddle_pivot.add_child(holder)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_WIDTH * 2.0, 0.7, HALF_LENGTH * 2.0)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.15, 0.0)
	body.add_child(cs)
	add_child(body)
	super()
	_place(0.0)


func get_prompt(_actor: Node) -> String:
	return "E  上独木舟" if rider == null else ""


func can_interact(actor: Node) -> bool:
	return rider == null and actor.has_method("board")


func interact(actor: Node) -> void:
	actor.board(self)


func get_state() -> String:
	return "riding" if rider != null else "moored"


## 乘客臀部所在的世界坐标。
func seat_position() -> Vector3:
	return global_transform * SEAT


func forward() -> Vector2:
	return Vector2(-sin(heading), -cos(heading))


func world_position_2d() -> Vector2:
	return _xz


## 直接放到某处（读档、测试用）。
func place_at(xz: Vector2, heading_deg: float) -> void:
	_xz = xz
	heading = -deg_to_rad(heading_deg)
	speed = 0.0
	yaw_rate = 0.0
	_place(_time)


func _physics_process(delta: float) -> void:
	_time += delta
	if rider == null:
		throttle = 0.0
		steer = 0.0
		sprint = false
	var paddling := absf(throttle) > 0.05 or absf(steer) > 0.05
	if paddling:
		var before := int(stroke_phase / PI)
		stroke_phase += delta * TAU / (0.85 if sprint else STROKE_TIME)
		if int(stroke_phase / PI) != before:
			Sound.play("paddle", global_position)   # 每一桨入水
	# 一桨一桨的推力：桨入水时推得最狠，出水时几乎不推
	var push := 0.55 + 0.45 * sin(stroke_phase * 2.0)
	var accel := throttle * THRUST * (1.35 if sprint else 1.0) * push
	if throttle < 0.0:
		accel *= 0.6
	speed += accel * delta
	speed -= speed * DRAG * delta
	var turn_target := -steer * TURN_RATE * (0.55 + 0.45 * clampf(absf(speed) / 1.5, 0.0, 1.0))
	yaw_rate = lerpf(yaw_rate, turn_target, 1.0 - exp(-3.0 * delta))
	var new_heading := wrapf(heading + yaw_rate * delta, -PI, PI)
	var new_fwd := Vector2(-sin(new_heading), -cos(new_heading))
	var step := new_fwd * speed * delta + _wind_drift() * delta
	# 搁浅后只要这一步让船下面的水变深（倒划、掉头离岸），就允许走，免得卡死在岸边
	var now_depth := hull_depth(_xz, heading)
	if _acceptable(_xz + step, new_heading, now_depth):
		_xz += step
		heading = new_heading
		grounded = now_depth < DRAFT
	else:
		if _acceptable(_xz, new_heading, now_depth):
			heading = new_heading
		else:
			yaw_rate = 0.0
		if step.length() > 0.0001:
			grounded = true
			speed *= -0.15
	_place(_time)
	_animate_paddle(delta, paddling)
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 1.0
		WorldState.set_vehicle(uid, _xz, -rad_to_deg(heading))


## 有人坐着时被风吹着轻轻漂；没人时船算系在原地（不然几分钟后就漂到岸边搁浅了）。
func _wind_drift() -> Vector2:
	if rider == null:
		return Vector2.ZERO
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	if env == null:
		return Vector2.ZERO
	return env.wind_direction.normalized() * env.wind_strength * 0.06


## 新位置可以走：船身下面的水够深，或者至少比现在深（正在离开浅滩）。
func _acceptable(xz: Vector2, yaw: float, now_depth: float) -> bool:
	var d := hull_depth(xz, yaw)
	return d >= DRAFT or d > now_depth + 0.0005


## 船身四个点里最浅处的水深（米）；碰到码头算 -1。
func hull_depth(xz: Vector2, yaw: float) -> float:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var water := WorldLayout.water_level()
	var shallowest := INF
	for p in [xz + fwd * HALF_LENGTH, xz - fwd * HALF_LENGTH, xz + right * HALF_WIDTH, xz - right * HALF_WIDTH]:
		if _in_dock(p):
			return -1.0
		shallowest = minf(shallowest, water - WorldTerrain.height_at(p.x, p.y))
	return shallowest


## 船身四个点下面的水都够深（> 吃水），并且不在码头桩区里。
func _hull_clear(xz: Vector2, yaw: float) -> bool:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var water := WorldLayout.water_level()
	for p in [xz + fwd * HALF_LENGTH, xz - fwd * HALF_LENGTH, xz + right * HALF_WIDTH, xz - right * HALF_WIDTH]:
		if WorldTerrain.height_at(p.x, p.y) > water - DRAFT:
			return false
		if _in_dock(p):
			return false
	return true


static func _in_dock(p: Vector2) -> bool:
	var dock := WorldLayout.section("dock")
	if dock.is_empty():
		return false
	var a := WorldLayout.v2(dock["from"])
	var b := WorldLayout.v2(dock["to"])
	var half := float(dock["width"]) * 0.5 + 0.05
	return p.x >= minf(a.x, b.x) - 0.3 and p.x <= maxf(a.x, b.x) + 0.3 and absf(p.y - a.y) <= half


## 水面高度（相对静水面）：两组慢波叠加，风和雨让浪变高。
func wave_height(p: Vector2, t: float) -> float:
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var wind := env.wind_strength if env != null else 0.2
	var rain := float(WeatherController.blended()["rain"])
	var amp := 0.025 + 0.09 * wind + 0.05 * rain
	return amp * (sin(0.9 * p.x + 1.3 * t) * 0.6 + sin(0.75 * p.y - 1.1 * t + 1.7) * 0.4)


func _place(t: float) -> void:
	var fwd := forward()
	var right := Vector2(-fwd.y, fwd.x)
	var hb := wave_height(_xz + fwd * HALF_LENGTH, t)
	var hs := wave_height(_xz - fwd * HALF_LENGTH, t)
	var hr := wave_height(_xz + right * HALF_WIDTH, t)
	var hl := wave_height(_xz - right * HALF_WIDTH, t)
	var heave := (hb + hs + hr + hl) * 0.25
	var pitch := atan2(hb - hs, HALF_LENGTH * 2.0)
	var roll := atan2(hr - hl, HALF_WIDTH * 2.0) + (deg_to_rad(1.5) * sin(stroke_phase) * paddle_side if rider != null else 0.0)
	global_transform = Transform3D(Basis.from_euler(Vector3(pitch, heading, roll)), Vector3(_xz.x, WorldLayout.water_level() + heave, _xz.y))


## 桨：在船的一侧从前往后划，转向时换到外侧，直行时每划两下换一次边。
func _animate_paddle(delta: float, paddling: bool) -> void:
	if steer > 0.3:
		paddle_side = -1.0
	elif steer < -0.3:
		paddle_side = 1.0
	elif paddling:
		paddle_side = 1.0 if fmod(stroke_phase, 4.0 * PI) < 2.0 * PI else -1.0
	var sweep := sin(stroke_phase) * deg_to_rad(38.0) if paddling else 0.0
	var target := Vector3(sweep, 0.0, deg_to_rad(32.0) * paddle_side if paddling else deg_to_rad(70.0))
	_paddle_pivot.rotation = _paddle_pivot.rotation.lerp(target, 1.0 - exp(-10.0 * delta))
	_paddle_pivot.visible = rider != null


## 下船的落脚点：先找码头板，再在船周围一圈找干燥、不太陡的岸；都没有返回 null。
func find_exit() -> Variant:
	var dock := WorldLayout.section("dock")
	if not dock.is_empty():
		var a := WorldLayout.v2(dock["from"])
		var b := WorldLayout.v2(dock["to"])
		var q := Geometry2D.get_closest_point_to_segment(_xz, a, b)
		if q.distance_to(_xz) < float(dock["width"]) * 0.5 + 2.4:
			# 码头入水段之前（岸上那头）是平台，入水段两侧有栏杆：落在中线上
			return Vector3(clampf(q.x, minf(a.x, b.x) + 0.8, maxf(a.x, b.x) - 0.6), float(dock["deck_height"]) + 0.05, q.y)
	var water := WorldLayout.water_level()
	var best: Variant = null
	var best_d := INF
	for r in [1.4, 2.0, 2.6, 3.2, 3.8]:
		for i in 24:
			var p: Vector2 = _xz + Vector2.from_angle(TAU * float(i) / 24.0) * r
			var h := WorldTerrain.height_at(p.x, p.y)
			if h >= water + 0.08 and WorldTerrain.slope_at(p.x, p.y) < 0.75 and not Vegetation.in_keepout(p):
				var d := p.distance_to(_xz)
				if d < best_d:
					best_d = d
					best = Vector3(p.x, h + 0.05, p.y)
		if best != null:
			return best
	return null
