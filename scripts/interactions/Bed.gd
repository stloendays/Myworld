class_name Bed
extends Interactable
## 木屋里的床：晚上（18:00 以后或 6:00 以前）睡到第二天早上 7:00，白天小睡 1 小时。
## 画面先暗下去，时间跳过，再亮起来；醒来站在床边（wake_point）。

const WAKE_HOUR := 7.0
const NAP_HOURS := 1.0

var wake_point := Vector3.ZERO   ## 本地坐标：醒来站立的位置（床边地面）
var sleeping := false
var _fade: ColorRect


static func create(id: StringName, pos: Vector3, size: Vector3, wake_local: Vector3) -> Bed:
	var b := Bed.new()
	b.name = "Bed_" + String(id)
	b.uid = id
	b.display_name = "床"
	b.position = pos
	b.wake_point = wake_local
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(cs)
	b.add_child(body)
	return b


## 现在睡下去会睡多少小时。
static func hours_to_sleep(time_minutes: float) -> float:
	var h := time_minutes / 60.0
	if h >= 18.0:
		return 24.0 - h + WAKE_HOUR
	if h < 6.0:
		return WAKE_HOUR - h
	return NAP_HOURS


func get_prompt(_actor: Node) -> String:
	if sleeping:
		return ""
	var h := WorldState.time_minutes / 60.0
	return "E  睡觉（睡到早上 7 点）" if h >= 18.0 or h < 6.0 else "E  小睡一会儿（1 小时）"


func can_interact(_actor: Node) -> bool:
	return not sleeping


func interact(actor: Node) -> void:
	# 联机时时间以房主为准：只有房主能睡过去，访客睡了也会被同步改回
	if Net.is_client():
		EventBus.toast_requested.emit(tr("联机时只有房主能睡到早上"))
		return
	sleep(actor)


## instant = true 时不做淡入淡出（自动检查用）。返回睡了多少小时。
func sleep(actor: Node, instant := false) -> float:
	var hours := hours_to_sleep(WorldState.time_minutes)
	sleeping = true
	if not instant:
		await _fade_to(1.0, 0.9)
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	if climate != null:
		climate.skip_hours(hours)
	if actor is FirstPersonController:
		(actor as FirstPersonController).teleport_to(to_global(wake_point))
	EventBus.toast_requested.emit(tr("睡了 %.1f 小时 · 现在 %s") % [hours, ClimateData.format_time(WorldState.time_minutes)])
	if not instant:
		await get_tree().create_timer(0.4).timeout
		await _fade_to(0.0, 1.2)
	sleeping = false
	return hours


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 40
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0.0, 0.0, 0.0, 0.0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds)
	await tw.finished
