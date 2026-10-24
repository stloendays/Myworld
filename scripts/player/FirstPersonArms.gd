class_name FirstPersonArms
extends Node3D
## 第一人称看到的双手：挂在相机下的第二个方块人模型，只显示两条手臂（袖子、皮肤随外观实时变化）。
## 整体缩小到 0.4 倍、离相机更近，透视上和正常大小一样，但手永远在角色碰撞体以内，贴墙也不会插进墙里。
## 大小（GameSettings.hand_size，默认 0.5）：每只手以手尖为中心整体缩小（0.5 = 原来的一半），手在画面上的
## 落点不变、占的画面少了；手尖离相机仍约 0.25 m，在碰撞体以内，贴墙不会插进墙里。
## 右键没对着东西时右手挥一挥（wave）。
## 单独的渲染层 FP_ARMS_LAYER：第一人称相机画它，第三人称相机、截图相机不画；不投影子、不接受阴影
## （否则会被自己身体的影子罩住）。走路摆动、跳起抬手、按 E 时右手前伸、游泳时划水。

const FP_ARMS_LAYER := 16   ## 渲染层 5（first_person_arms）
const SCALE := 0.4
## 相机空间（未缩放）里的肩膀位置与手臂朝向（度，YXZ 欧拉角）：手臂沿 -Y 长；肩膀在画面右下角外，
## 由目标反推：右手末端落在约 (0.37, -0.21, -0.45)，即 16:9、FOV 75° 画面右侧 60%、下方 62% 处（左手镜像）
const SHOULDER := Vector3(0.537, -0.58, -0.056)
const POSE := Vector3(130.5, 23.3, 0.0)
## 挥手时右手的肩位与姿势：手尖落在 (0.22, 0.055, -0.45)，即画面横向 68%、竖向 42% 处，手臂几乎竖直、从画面底边伸上来
const WAVE_SHOULDER := Vector3(0.304, -0.475, -0.298)
const WAVE_POSE := Vector3(160.0, 26.0, 0.0)
const WAVE_TIP := Vector3(0.22, 0.055, -0.45)

var model: CharacterModel
var mode := "both"

var _material: StandardMaterial3D
var _fist_material: StandardMaterial3D
var _phase := 0.0
var _move := 0.0
var _reach := 0.0
var _swim := 0.0
var _air := 0.0
var _wave := 0.0
var size := 1.0
var _tip := Vector3.ZERO    ## 静止姿势下右手末端（左手 x 取反）；缩小时以它为中心
var shoulder := SHOULDER   ## 实例上的肩位与姿势（默认取常量；截图工具调参时可改）
var pose := POSE


func _ready() -> void:
	scale = Vector3.ONE * SCALE
	model = CharacterModel.new()
	model.name = "ArmsModel"
	add_child(model)
	model.render_layers = FP_ARMS_LAYER
	set_size(GameSettings.hand_size)
	_restyle()
	if model.appearance != null:
		model.appearance.changed.connect(_restyle, CONNECT_DEFERRED)


## 只留两条手臂，换上不投影、不受影的材质。外观改变（重建网格）后再做一次。
func _restyle() -> void:
	if _material == null:
		_material = BlockyMesh.material(Wardrobe.px()).duplicate() as StandardMaterial3D
		_material.disable_receive_shadows = true
	for part in model.parts:
		(model.parts[part] as Node3D).visible = part in ["arm_r", "arm_l"]
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name != "Fist":
			mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = FP_ARMS_LAYER
	_add_fists()
	_apply_mode()


## 袖子（外套、卫衣）一直盖到手腕，第一人称几乎看不到手：在两条手臂末端各加一个皮肤色的方块拳头
## （只在第一人称手上有，第三人称的方块人不变）。肤色随外观变化。
func _add_fists() -> void:
	if _fist_material == null:
		_fist_material = StandardMaterial3D.new()
		_fist_material.disable_receive_shadows = true
		_fist_material.roughness = 0.9
	_fist_material.albedo_color = model.appearance.color("skin") if model.appearance != null else Color("e0b494")
	var px := Wardrobe.px()
	for part in ["arm_r", "arm_l"]:
		var pivot: Node3D = model.parts[part]
		if pivot.get_node_or_null("Fist") != null:
			continue
		var fist := MeshInstance3D.new()
		fist.name = "Fist"
		var box := BoxMesh.new()
		box.size = Vector3(3.8, 2.6, 3.8) * px
		fist.mesh = box
		fist.position = Vector3(0.0, -11.1, 0.0) * px
		fist.material_override = _fist_material
		fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fist.layers = FP_ARMS_LAYER
		pivot.add_child(fist)


func set_mode(value: String) -> void:
	mode = value
	_apply_mode()


func _apply_mode() -> void:
	if model == null or model.parts.is_empty():
		return
	(model.parts["arm_r"] as Node3D).visible = mode != "none"
	(model.parts["arm_l"] as Node3D).visible = mode == "both"


## 按 E 交互时右手往前一伸。
func reach() -> void:
	_reach = 1.0


## 右键没对着东西：右手抬起挥一挥（约 1.2 秒）。
func wave() -> void:
	_wave = 1.0


func is_waving() -> bool:
	return _wave > 0.0


## 画面上的大小（0.4–1.0）：每只手以手尖为中心整体缩小，手在画面上的落点不变，手离相机不变远（不会穿墙）。
func set_size(value: float) -> void:
	size = clampf(value, 0.4, 1.0)
	_tip = hand_tip()


## 静止姿势下右手末端在本节点（未缩放）坐标里的位置：肩位 + 手臂（沿 -Y 长 10 像素）按姿势旋转。
func hand_tip() -> Vector3:
	var b := Basis.from_euler(Vector3(deg_to_rad(pose.x), deg_to_rad(pose.y), deg_to_rad(pose.z)), EULER_ORDER_YXZ)
	return shoulder + b * Vector3(0.0, -10.0 * Wardrobe.px(), 0.0)


## 由控制器每帧调用：speed = 水平速度，on_floor、swimming 为当前状态。
func animate(delta: float, speed: float, on_floor: bool, swimming: bool, run_speed: float) -> void:
	if model == null or model.parts.is_empty():
		return
	_move = lerpf(_move, clampf(speed / run_speed, 0.0, 1.0) if on_floor and not swimming else 0.0, 1.0 - exp(-8.0 * delta))
	_swim = lerpf(_swim, 1.0 if swimming else 0.0, 1.0 - exp(-5.0 * delta))
	_air = lerpf(_air, 0.0 if on_floor or swimming else 1.0, 1.0 - exp(-8.0 * delta))
	_reach = maxf(0.0, _reach - delta * 3.2)
	_wave = maxf(0.0, _wave - delta / 1.2)
	_phase += delta * (speed * 2.4 if not swimming else 3.0)
	var t := Time.get_ticks_msec() * 0.001
	for side in [1.0, -1.0]:
		var part: Node3D = model.parts["arm_r" if side > 0.0 else "arm_l"]
		var swing := sin(_phase + (0.0 if side > 0.0 else PI))
		var bob := Vector3(cos(_phase) * 0.02 * side, -absf(sin(_phase)) * 0.035, 0.0) * _move
		var breath := Vector3(0.0, sin(t * 1.6) * 0.006, 0.0) * (1.0 - _move)
		var stroke := Vector3(0.0, 0.0, -0.08 * (0.5 + 0.5 * sin(_phase * 2.0))) * _swim
		var pitch := pose.x + swing * 6.0 * _move + 22.0 * _air - 12.0 * _swim
		var yaw := pose.y + sin(_phase * 2.0) * 28.0 * _swim
		if side > 0.0:
			pitch += sin(_reach * PI) * 24.0
		# 以手尖为中心按 size 缩小：手尖留在原处（离相机约 0.25 m，在碰撞体以内），手臂和拳头变短变细
		var base := Vector3(shoulder.x * side, shoulder.y, shoulder.z)
		var tip_side := Vector3(_tip.x * side, _tip.y, _tip.z)
		var sway := bob + breath + stroke + Vector3(0.0, 0.0, -0.16 * sin(_reach * PI)) * (1.0 if side > 0.0 else 0.0)
		part.position = base.lerp(tip_side, 1.0 - size) + sway * size
		part.scale = Vector3.ONE * size
		var roll := pose.z
		if side > 0.0 and _wave > 0.0:
			# 挥手：右手举到画面右侧偏上（WAVE_*，同样以手尖为中心缩放），手掌左右摆三下
			var lift := sin(minf(_wave * 4.0, 1.0) * PI * 0.5) * minf(_wave * 5.0, 1.0)
			part.position = part.position.lerp(WAVE_SHOULDER.lerp(WAVE_TIP, 1.0 - size), lift)
			pitch = lerpf(pitch, WAVE_POSE.x, lift)
			yaw = lerpf(yaw, WAVE_POSE.y, lift)
			roll = lerpf(roll, sin(_wave * PI * 6.0) * 24.0, lift)
		part.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw * side), deg_to_rad(roll * side))
