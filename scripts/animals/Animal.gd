class_name Animal
extends Node3D
## 一只陆地/水面/天空的小动物（不参与物理，只做视觉与简单行为）。
## 行为：在活动范围内闲逛 → 停下 → 再选目标；玩家靠太近就跑开（兔子、松鼠、狐狸、鸭子）；
## 鸭子只在湖面上；鸟在空中盘旋；蝴蝶贴近地面乱飞。不该出现的时候（夜里、下雨、季节不对）
## 缩小消失，条件恢复后再出现。每只动物有稳定的 entity_id，为以后的存档/联机预留。

var entity_id: StringName = &""
var species_id := ""
var def: Dictionary = {}
var center := Vector2.ZERO
var radius := 10.0
var model: BlockyModel = null
var active := true
var fleeing := false
var _lod_accum := 0.0
var _lod_frame := 0

var _rng := RandomNumberGenerator.new()
var _target := Vector3.ZERO
var _wait := 0.0
var _speed := 0.0
var _appear := 1.0
var _rule_timer := 0.0
var _season: StringName = &""
var _orbit := 0.0
var _variant := 0


func setup(id: StringName, species: String, zone_center: Vector2, zone_radius: float, seed_value: int) -> void:
	entity_id = id
	species_id = species
	def = FaunaData.species(species)
	center = zone_center
	radius = zone_radius
	_rng.seed = seed_value
	_variant = _rng.randi()
	model = BlockyModel.new()
	model.name = "Model"
	add_child(model)
	_season = WorldState.season_id
	model.setup(def, FaunaData.palette(def, _variant))
	var p := _random_point()
	global_position = p
	_target = p
	_orbit = _rng.randf() * TAU
	add_to_group("fauna")


## 更新降频（大作里的“AI LOD”）：离相机 70 m 外每 4 帧更新一次，150 m 外每 12 帧一次，
## 跳过的帧把时间攒起来一起算，所以走动速度不变，只是远处的动画没那么细。
func _lod_interval() -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1
	var d := cam.global_position.distance_squared_to(global_position)
	return 12 if d > 150.0 * 150.0 else (4 if d > 70.0 * 70.0 else 1)


func _physics_process(delta: float) -> void:
	_lod_accum += delta
	_lod_frame += 1
	if _lod_frame % _lod_interval() != 0:
		return
	delta = minf(_lod_accum, 0.25)
	_lod_accum = 0.0
	_rule_timer -= delta
	if _rule_timer <= 0.0:
		_rule_timer = 1.0 + _rng.randf() * 0.5
		active = FaunaData.is_active(def.get("active", {}))
		if WorldState.season_id != _season:
			_season = WorldState.season_id
			model.recolor(FaunaData.palette(def, _variant))
	_appear = move_toward(_appear, 1.0 if active else 0.0, delta * 1.2)
	visible = _appear > 0.01
	model.scale = Vector3.ONE * maxf(_appear, 0.01)
	if not visible:
		return
	match str(def.get("locomotion", "walk")):
		"walk", "hop":
			_ground(delta)
		"swim_surface":
			_duck(delta)
		"fly":
			_fly(delta)
		"flutter":
			_flutter(delta)
	model.animate(delta, _speed)


func _player_pos() -> Variant:
	var p := get_tree().get_first_node_in_group("local_player") as Node3D
	return p.global_position if p != null else null


func _ground(delta: float) -> void:
	var pos := global_position
	var player: Variant = _player_pos()
	var flee_r := float(def.get("flee_radius", 0.0))
	fleeing = player != null and Vector2(pos.x - player.x, pos.z - player.z).length() < flee_r
	if fleeing:
		var away := Vector2(pos.x - player.x, pos.z - player.z).normalized()
		var t := Vector2(pos.x, pos.z) + away * 6.0
		if _valid(t):
			_target = Vector3(t.x, 0.0, t.y)
		_wait = 0.0
	var to := Vector2(_target.x - pos.x, _target.z - pos.z)
	var max_speed := float(def.get("flee_speed", 3.0)) if fleeing else float(def.get("speed", 1.0))
	if to.length() < 0.2:
		_speed = move_toward(_speed, 0.0, delta * 6.0)
		_wait -= delta
		if _wait <= 0.0:
			_wait = _rng.randf_range(1.5, 6.0)
			_target = _random_point()
	else:
		_speed = move_toward(_speed, max_speed, delta * 5.0)
		var step := to.normalized() * minf(_speed * delta, to.length())
		pos.x += step.x
		pos.z += step.y
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), 1.0 - exp(-8.0 * delta))
	var ground := WorldTerrain.height_at(pos.x, pos.z)
	var hop := 0.0
	if str(def.get("locomotion")) == "hop" and _speed > 0.1:
		hop = absf(sin(Time.get_ticks_msec() * 0.001 * (6.0 + _speed * 3.0) + float(_variant % 7))) * 0.16
	pos.y = ground + hop
	global_position = pos


func _duck(delta: float) -> void:
	var pos := global_position
	var player: Variant = _player_pos()
	fleeing = player != null and Vector2(pos.x - player.x, pos.z - player.z).length() < float(def.get("flee_radius", 4.0))
	if fleeing:
		var away := Vector2(pos.x - player.x, pos.z - player.z).normalized()
		var t := Vector2(pos.x, pos.z) + away * 5.0
		if _valid(t):
			_target = Vector3(t.x, 0.0, t.y)
	var to := Vector2(_target.x - pos.x, _target.z - pos.z)
	var max_speed := float(def.get("flee_speed", 1.2)) if fleeing else float(def.get("speed", 0.4))
	if FaunaData.is_night():
		max_speed *= 0.2
	if to.length() < 0.3:
		_speed = move_toward(_speed, 0.0, delta)
		_wait -= delta
		if _wait <= 0.0:
			_wait = _rng.randf_range(3.0, 10.0)
			_target = _random_point()
	else:
		_speed = move_toward(_speed, max_speed, delta)
		var step := to.normalized() * minf(_speed * delta, to.length())
		pos.x += step.x
		pos.z += step.y
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), 1.0 - exp(-3.0 * delta))
	pos.y = WorldLayout.water_level()
	global_position = pos


func _fly(delta: float) -> void:
	var spd := float(def.get("speed", 6.0))
	_speed = spd
	_orbit += delta * spd / maxf(radius, 1.0)
	var r := radius * (0.75 + 0.25 * sin(_orbit * 0.7 + float(_variant % 13)))
	var p := center + Vector2(cos(_orbit), sin(_orbit)) * r
	var alt := float(def.get("altitude", 15.0)) + sin(_orbit * 2.3 + float(_variant % 5)) * 2.5
	var target := Vector3(p.x, WorldTerrain.height_at(p.x, p.y) + alt, p.y)
	var d := target - global_position
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)
	global_position = target


func _flutter(delta: float) -> void:
	var pos := global_position
	var to := _target - pos
	_speed = float(def.get("speed", 1.2))
	if to.length() < 0.3:
		_target = _random_point()
		var fh: Array = def.get("fly_height", [0.4, 1.8])
		_target.y += _rng.randf_range(float(fh[0]), float(fh[1]))
	var wobble := Vector3(sin(Time.get_ticks_msec() * 0.007 + _variant), cos(Time.get_ticks_msec() * 0.011 + _variant) * 0.6, 0.0) * 0.6
	var v := to.normalized() * _speed + wobble
	pos += v * delta
	pos.y = maxf(pos.y, WorldTerrain.height_at(pos.x, pos.z) + 0.25)
	if v.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), 1.0 - exp(-6.0 * delta))
	global_position = pos


func _random_point() -> Vector3:
	for i in 30:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius
		var p := center + Vector2(cos(a), sin(a)) * r
		if _valid(p):
			var y := WorldLayout.water_level() if str(def.get("locomotion")) == "swim_surface" else WorldTerrain.height_at(p.x, p.y)
			return Vector3(p.x, y, p.y)
	return Vector3(center.x, WorldTerrain.height_at(center.x, center.y), center.y)


## 位置是否适合这种动物：陆地动物不进水、不进建筑；鸭子只在够深的湖面上。
func _valid(p: Vector2) -> bool:
	var loco := str(def.get("locomotion", "walk"))
	var h := WorldTerrain.height_at(p.x, p.y)
	if loco == "swim_surface":
		return h < WorldLayout.water_level() - 0.5 and p.distance_to(center) < radius * 1.2
	if loco == "fly":
		return true
	if h < WorldLayout.water_level() + 0.4 or Vegetation.in_keepout(p) or WorldTerrain.channel_distance(p.x, p.y) < 0.5:
		return false
	var mx := WorldLayout.world_max() - 18.0
	return absf(p.x) < mx and absf(p.y) < mx and p.distance_to(center) < radius * 1.3
