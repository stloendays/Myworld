class_name RailRide
extends Node3D
## 沿一条固定路线把玩家带着走（亚特兰蒂斯的洋流水渠、骑蝠鲼）。路线是世界坐标的 Curve3D。
## 开始：FirstPersonController.start_rail(self)；每物理帧往前走 speed 米，玩家的位置 = 路线上的点 + rider_offset；
## 走完把人放在 exit_point，发 finished。carrier（例如蝠鲼模型）跟着一起走，没人骑时回到起点待着。
## 可以松手的路线（蝠鲼）按 E 提前放开，人留在当前位置；洋流不能中途出去。

signal started(rider: Node)
signal finished(rider: Node, completed: bool)

var curve := Curve3D.new()
var speed := 7.0
var pose := "sit"
var prompt_text := ""
var can_release := false
var exit_point := Vector3.ZERO
var rider_offset := Vector3(0.0, 0.0, 0.0)
var carrier: Node3D = null              ## 跟着路线走的模型（可空）
var carrier_offset := Vector3.ZERO      ## 模型相对路线点的位置（人坐在模型上时，模型在人下面）

var rider: FirstPersonController = null
var progress := 0.0                     ## 已经走了多少米
var rides := 0                          ## 完整走完的次数（自动检查读）
var _length := 0.0
var _entry := Vector3.ZERO           ## 上车时人站的位置：头 0.4 秒从这里平滑挪到路线起点，不会一下跳过去
var _entry_t := 1.0


func setup(points: PackedVector3Array, ride_speed: float, exit: Vector3) -> void:
	curve.clear_points()
	for i in points.size():
		var p := points[i]
		var tangent := Vector3.ZERO
		if i > 0 and i < points.size() - 1:
			tangent = (points[i + 1] - points[i - 1]) * 0.22
		curve.add_point(p, -tangent, tangent)
	curve.bake_interval = 0.25
	_length = curve.get_baked_length()
	speed = ride_speed
	exit_point = exit
	_place_carrier(0.0)


func length() -> float:
	return _length


func begin(p: FirstPersonController) -> bool:
	if rider != null or p.is_riding():
		return false
	rider = p
	progress = 0.0
	_entry = p.global_position
	_entry_t = 0.0
	p.start_rail(self)
	if rider != p:
		return false
	started.emit(p)
	return true


func rider_position() -> Vector3:
	var on := curve.sample_baked(clampf(progress, 0.0, _length)) + rider_offset
	if _entry_t < 1.0:
		return _entry.lerp(on, smoothstep(0.0, 1.0, _entry_t))
	return on


## 路线前进方向的偏航角（人面朝前）。
func rider_yaw() -> float:
	var a := curve.sample_baked(clampf(progress, 0.0, _length))
	var b := curve.sample_baked(clampf(progress + 1.0, 0.0, _length))
	var d := b - a
	if Vector2(d.x, d.z).length() < 0.01:
		return 0.0
	return atan2(-d.x, -d.z)


func prompt() -> String:
	return prompt_text


func try_release(p: FirstPersonController) -> bool:
	if not can_release or p != rider:
		return true
	var at := rider_position()
	rider = null
	p.end_rail(at)
	finished.emit(p, false)
	_place_carrier(0.0)
	return true


## 玩家因为别的原因离开（传送、读档）：只清掉骑乘关系。
func rider_left(p: FirstPersonController) -> void:
	if p == rider:
		rider = null
		_place_carrier(0.0)


func _physics_process(delta: float) -> void:
	if rider == null:
		if carrier != null:
			# 没人骑时在起点附近轻轻上下浮动
			carrier.position = curve.sample_baked(0.0) + carrier_offset + Vector3(0.0, sin(Time.get_ticks_msec() * 0.0015) * 0.15, 0.0)
		return
	if not is_instance_valid(rider):
		rider = null
		return
	progress += speed * delta * (0.35 + 0.65 * _entry_t)
	_entry_t = minf(1.0, _entry_t + delta / 0.4)
	_place_carrier(progress)
	if progress >= _length:
		var p := rider
		rider = null
		rides += 1
		p.end_rail(exit_point)
		finished.emit(p, true)
		_place_carrier(0.0)


func _place_carrier(at: float) -> void:
	if carrier == null or _length <= 0.0:
		return
	var a := curve.sample_baked(clampf(at, 0.0, _length))
	carrier.position = a + carrier_offset
	var b := curve.sample_baked(clampf(at + 1.0, 0.0, _length))
	var d := b - a
	if d.length() > 0.01:
		carrier.rotation = Vector3(atan2(d.y, Vector2(d.x, d.z).length()) * 0.6, atan2(-d.x, -d.z), carrier.rotation.z)
