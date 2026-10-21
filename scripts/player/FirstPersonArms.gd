class_name FirstPersonArms
extends Node3D
## 第一人称看到的双手：挂在相机下的第二个方块人模型，只显示两条手臂（袖子、皮肤随外观实时变化）。
## 整体缩小到 0.4 倍、离相机更近，透视上和正常大小一样，但手永远在角色碰撞体以内，贴墙也不会插进墙里。
## 单独的渲染层 FP_ARMS_LAYER：第一人称相机画它，第三人称相机、截图相机不画；不投影子、不接受阴影
## （否则会被自己身体的影子罩住）。走路摆动、跳起抬手、按 E 时右手前伸、游泳时划水。

const FP_ARMS_LAYER := 16   ## 渲染层 5（first_person_arms）
const SCALE := 0.4
## 相机空间（未缩放）里的肩膀位置与手臂朝向（度）：手臂沿 -Y 长；肩膀在画面右下角外，
## pitch 122°、yaw 22° 让右手末端落在约 (0.21, -0.27, -0.41)，即 16:9 画面的右下方（左手镜像）
const SHOULDER := Vector3(0.46, -0.56, 0.0)
const POSE := Vector3(122.0, 22.0, -8.0)

var model: CharacterModel
var mode := "both"

var _material: StandardMaterial3D
var _phase := 0.0
var _move := 0.0
var _reach := 0.0
var _swim := 0.0
var _air := 0.0


func _ready() -> void:
	scale = Vector3.ONE * SCALE
	model = CharacterModel.new()
	model.name = "ArmsModel"
	add_child(model)
	model.render_layers = FP_ARMS_LAYER
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
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = FP_ARMS_LAYER
	_apply_mode()


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


## 由控制器每帧调用：speed = 水平速度，on_floor、swimming 为当前状态。
func animate(delta: float, speed: float, on_floor: bool, swimming: bool, run_speed: float) -> void:
	if model == null or model.parts.is_empty():
		return
	_move = lerpf(_move, clampf(speed / run_speed, 0.0, 1.0) if on_floor and not swimming else 0.0, 1.0 - exp(-8.0 * delta))
	_swim = lerpf(_swim, 1.0 if swimming else 0.0, 1.0 - exp(-5.0 * delta))
	_air = lerpf(_air, 0.0 if on_floor or swimming else 1.0, 1.0 - exp(-8.0 * delta))
	_reach = maxf(0.0, _reach - delta * 3.2)
	_phase += delta * (speed * 2.4 if not swimming else 3.0)
	var t := Time.get_ticks_msec() * 0.001
	for side in [1.0, -1.0]:
		var part: Node3D = model.parts["arm_r" if side > 0.0 else "arm_l"]
		var swing := sin(_phase + (0.0 if side > 0.0 else PI))
		var bob := Vector3(cos(_phase) * 0.02 * side, -absf(sin(_phase)) * 0.035, 0.0) * _move
		var breath := Vector3(0.0, sin(t * 1.6) * 0.006, 0.0) * (1.0 - _move)
		var stroke := Vector3(0.0, 0.0, -0.08 * (0.5 + 0.5 * sin(_phase * 2.0))) * _swim
		var pitch := POSE.x + swing * 6.0 * _move + 22.0 * _air - 12.0 * _swim
		var yaw := POSE.y + sin(_phase * 2.0) * 28.0 * _swim
		if side > 0.0:
			pitch += sin(_reach * PI) * 24.0
		part.position = Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z) + bob + breath + stroke \
			+ Vector3(0.0, 0.0, -0.16 * sin(_reach * PI)) * (1.0 if side > 0.0 else 0.0)
		part.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw * side), deg_to_rad(POSE.z * side))
