class_name Aircraft
extends Interactable
## 能飞的交通工具（湖畔世界）：热气球、滑翔翼、小直升机。停放的位置在 world_layout.json → aircraft。
## 走近按 E 坐上去，落地以后按 E 下来（落在深水上下不来）。操作：
##   热气球：空格点火上升、C / Ctrl 放气下降、都不按就保持高度；W / S 慢慢往前后飘、A / D 转向，会被风推着走。
##   滑翔翼：在地上按 W 助跑，跑快了就离地（从雪山顶往下跳最好）；空中 W 俯冲加速、S 拉起减速、A / D 转弯，
##           一路慢慢往下滑；掉进深水里按 E 被送回出发点。
##   小直升机：空格升、C / Ctrl 降、W / S 前进后退、A / D 转向，Shift 更快；旋翼转起来以后才能升空。
## 运动自己算（和独木舟一样不走物理引擎，结果可复现）：地面高度取 WorldTerrain.height_at，湖面也算“地面”；
## 建筑、树干、石头用一次形状扫掠（cast_motion）挡住。没人开的时候慢慢降落，落地后什么都不算。
## 位置每秒写进 WorldState.vehicles；联机时谁在开，别人那边的同一架就跟着谁的姿态包走（RemotePlayer → place_remote）。

const KINDS := ["balloon", "glider", "heli"]
const NAMES := {"balloon": "热气球", "glider": "滑翔翼", "heli": "小直升机"}
const MAX_ALTITUDE := {"balloon": 90.0, "glider": 80.0, "heli": 100.0}   ## 离水面最高多少米
const EDGE_MARGIN := 8.0          ## 离地图边界至少这么远（边界外是远景山）
const DEEP_WATER := 0.6           ## 水比这深就下不来（湖里只能涉水）

var kind := "heli"
var home := Vector3.ZERO          ## 停放点（布局里的位置，落在地面上）
var home_heading := 0.0
var heading := 0.0                ## 等于 rotation.y：0 = 机头朝北（-Z）
var vel := Vector3.ZERO
var yaw_rate := 0.0
var speed := 0.0                  ## 滑翔翼的空速（沿机头方向）
var engine := 0.0                 ## 直升机旋翼转速 0..1；热气球是火焰大小
var landed := true
var over_water := false
var on_structure := false         ## 停在屋顶、码头这类东西上（不能下来）
var rider: Node = null
var bumps := 0                    ## 被挡住的次数（自动检查读）
## 由乘客每帧设置
var throttle := 0.0               ## W / S：-1..1
var steer := 0.0                  ## A / D：-1..1，正 = 右转
var lift := 0.0                   ## 空格 / C：-1..1
var sprint := false

var _pos := Vector3.ZERO
var _pitch := 0.0
var _roll := 0.0
var _time := 0.0
var _save_timer := 0.0
var _body: StaticBody3D
var _shape: Shape3D
var _shape_offset := Vector3.ZERO
var _query: PhysicsShapeQueryParameters3D
var _rotor: Node3D                ## 直升机主旋翼
var _tail_rotor: Node3D
var _blades: MeshInstance3D
var _disc: MeshInstance3D         ## 转快了以后的旋翼圆盘
var _disc_material: StandardMaterial3D
var _flame: Node3D                ## 热气球的火焰
var _flame_light: OmniLight3D
var _sound: SoundEmitter
var _last_pos := Vector3.ZERO
var _rise := 0.0                  ## 最近的上升速度（别人在开时用来判断火焰）


## 按 world_layout.json → aircraft 把几架飞行器摆好，放在 parent 下面。
static func spawn_all(parent: Node3D) -> Array:
	var out := []
	for e in WorldLayout.data().get("aircraft", []):
		var a := Aircraft.new()
		a.kind = str(e["kind"])
		a.uid = StringName("air_" + str(e["id"]))
		a.name = "Aircraft_" + str(e["id"])
		a.display_name = NAMES.get(a.kind, "")
		var p := WorldLayout.v2(e["pos"])
		a.home = Vector3(p.x, 0.0, p.y)
		a.home_heading = -deg_to_rad(float(e.get("heading", 0.0)))
		parent.add_child(a)
		out.append(a)
	return out


func _ready() -> void:
	add_to_group("aircraft")
	process_physics_priority = -10   # 先于乘客算：乘客这一步读到的就是飞行器这一步的位置，不会落后一帧
	home.y = floor_height(home.x, home.z)
	_build_model()
	_build_body()
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _shape
	_query.collision_mask = PhysicsLayers.WORLD
	super()
	restore()
	_exclude_terrain.call_deferred()


## 扫掠时不算地形（地面高度另外按公式算）和自己的碰撞体。
func _exclude_terrain() -> void:
	var rids: Array[RID] = [_body.get_rid()]
	for n in get_tree().get_nodes_in_group("terrain_body"):
		rids.append((n as CollisionObject3D).get_rid())
	_query.exclude = rids


func get_prompt(_actor: Node) -> String:
	if rider != null:
		return ""
	return {"balloon": "E  坐进热气球", "glider": "E  背上滑翔翼", "heli": "E  坐进小直升机"}.get(kind, "")


func can_interact(actor: Node) -> bool:
	return rider == null and actor.has_method("board_aircraft")


func interact(actor: Node) -> void:
	actor.board_aircraft(self)


## 乘客的身体姿势：热气球站在吊篮里，另外两种坐着。
func rider_pose() -> String:
	return "stand" if kind == "balloon" else "sit"


## 乘客（角色原点，即脚底）所在的世界坐标。
func rider_origin() -> Vector3:
	match kind:
		"balloon":
			return global_transform * Vector3(0.0, 0.18, 0.25)
		"glider":
			return global_transform * Vector3(0.0, 0.42 - 12.0 * Wardrobe.px(), 0.15)
	return global_transform * Vector3(0.0, 0.62 - 12.0 * Wardrobe.px(), -0.15)


## 坐在上面时屏幕下方的操作提示。
func prompt() -> String:
	match kind:
		"balloon":
			if landed:
				return "空格 点火升空  ·  E 下来"
			return "空格 点火  C 放气  W/S 飘  A/D 转向  ·  落地后 E 下来"
		"glider":
			if landed and over_water:
				return "E  落水了：回到出发点"
			if landed and on_structure:
				return "E  下来（下不去就回到出发点）"
			if landed:
				return "W 助跑起飞  A/D 转向  ·  E 下来"
			return "W 俯冲  S 拉起  A/D 转弯  ·  落地后 E 下来"
	if landed:
		return "空格 起飞  ·  E 下来" if engine >= 0.8 else "旋翼转起来了……  ·  E 下来"
	return "空格 升  C 降  W/S 前后  A/D 转向  Shift 快  ·  落地后 E 下来"


## 下不来时的提示（没落地、落在水上或屋顶上）。
func exit_hint() -> String:
	if not landed:
		return "先降落到地面上再下来"
	if over_water:
		return "下面是深水：飞到岸边再下来"
	return "这里下不去：落到空地上再下来"


func forward() -> Vector2:
	return Vector2(-sin(heading), -cos(heading))


func world_position() -> Vector3:
	return _pos


func world_position_2d() -> Vector2:
	return Vector2(_pos.x, _pos.z)


## 第三人称时镜头至少离多远（看得见整架）。
func camera_distance() -> float:
	return {"balloon": 9.5, "glider": 6.5, "heli": 8.5}.get(kind, 6.0)


func body_rid() -> RID:
	return _body.get_rid()


## 地面高度：地形和湖面取高的那个（湖面上也能停，只是下不来）。
static func floor_height(x: float, z: float) -> float:
	return maxf(WorldTerrain.height_at(x, z), WorldLayout.water_level())


## 停到某处的地面上（读档、测试用）；altitude > 0 时放在离地这么高的空中（截图用：滑翔翼带上巡航速度，旋翼已经转起来）。
func place_at(xz: Vector2, heading_deg: float, altitude := 0.0) -> void:
	_pos = Vector3(xz.x, floor_height(xz.x, xz.y) + maxf(altitude, 0.0), xz.y)
	heading = -deg_to_rad(heading_deg)
	vel = Vector3.ZERO
	speed = 10.0 if altitude > 0.0 and kind == "glider" else 0.0
	engine = 1.0 if altitude > 0.0 and kind == "heli" else engine
	yaw_rate = 0.0
	landed = altitude <= 0.0
	on_structure = false
	_update_water()
	_last_pos = _pos
	_place()


## 别人在开（联机）：位置和朝向直接用对方的。
func place_remote(pos: Vector3, h: float) -> void:
	_pos = pos
	heading = h
	landed = pos.y <= floor_height(pos.x, pos.z) + 0.05
	_update_water()
	_place()


## 回到停放点。
func return_home() -> void:
	place_at(Vector2(home.x, home.z), -rad_to_deg(home_heading))


## 按存档摆放；存下的位置在深水上（或没存过）就回停放点。
func restore() -> void:
	var saved: Dictionary = WorldState.vehicles.get(String(uid), {})
	if saved.is_empty():
		return_home()
		return
	var p := Vector2(float(saved["pos"][0]), float(saved["pos"][1]))
	place_at(p, float(saved.get("yaw_deg", 0.0)))
	if over_water:
		return_home()


func _update_water() -> void:
	over_water = WorldLayout.water_level() - WorldTerrain.height_at(_pos.x, _pos.z) > DEEP_WATER


func _physics_process(delta: float) -> void:
	_time += delta
	if rider == null:
		throttle = 0.0
		steer = 0.0
		lift = 0.0
		sprint = false
		if landed and vel.length_squared() < 1e-6 and speed == 0.0:
			return   # 停着：什么都不算
	match kind:
		"balloon":
			_fly_balloon(delta)
		"glider":
			_fly_glider(delta)
		_:
			_fly_heli(delta)
	heading = wrapf(heading + yaw_rate * delta, -PI, PI)
	_move(delta)
	_place()
	_save_timer -= delta
	if _save_timer <= 0.0 and rider != null:
		_save_timer = 1.0
		WorldState.set_vehicle(uid, world_position_2d(), -rad_to_deg(heading))


## 热气球：竖直方向靠火（空格）和放气（C），水平方向慢慢飘，风把它推着走。
func _fly_balloon(delta: float) -> void:
	yaw_rate = lerpf(yaw_rate, -steer * 0.45, 1.0 - exp(-2.0 * delta))
	var vy := 2.8 * lift if lift > 0.0 else 2.2 * lift
	if rider == null and not landed:
		vy = -1.0   # 没人：慢慢落下来
	vel.y = lerpf(vel.y, vy, 1.0 - exp(-0.9 * delta))
	var hv := Vector2.ZERO
	if not landed:
		hv = forward() * throttle * (4.0 if sprint else 2.5) + _wind() * 1.4
	var cur := Vector2(vel.x, vel.z).lerp(hv, 1.0 - exp(-0.8 * delta))
	vel.x = cur.x
	vel.z = cur.y
	_pitch = lerpf(_pitch, -0.03 * throttle, 1.0 - exp(-1.5 * delta))
	_roll = 0.02 * sin(_time * 0.9) if not landed else 0.0


## 滑翔翼：在地上助跑起飞；空中按滑翔比一路往下沉，俯冲快、拉起慢。
func _fly_glider(delta: float) -> void:
	if landed:
		var run := 7.8 * maxf(throttle, 0.0) if not over_water else 0.0
		speed = move_toward(speed, run, (2.6 if run > speed else 5.0) * delta)
		yaw_rate = lerpf(yaw_rate, -steer * 0.8, 1.0 - exp(-4.0 * delta))
		var f := forward() * speed
		vel = Vector3(f.x, 0.0, f.y)
		if speed >= 7.0:
			vel.y = 2.2   # 跑起来了：离地
		_roll = lerpf(_roll, 0.0, 1.0 - exp(-4.0 * delta))
		_pitch = lerpf(_pitch, 0.0, 1.0 - exp(-4.0 * delta))
		return
	var dive := maxf(throttle, 0.0)
	var flare := maxf(-throttle, 0.0)
	speed = move_toward(speed, 10.0 + 5.5 * dive - 3.5 * flare, 2.2 * delta)
	var sink := 1.15 + 1.6 * dive - 0.55 * flare
	if rider == null:
		sink = 3.0
	vel.y = lerpf(vel.y, -sink, 1.0 - exp(-1.5 * delta))
	yaw_rate = lerpf(yaw_rate, -steer * 0.75, 1.0 - exp(-2.5 * delta))
	var f := forward() * speed + _wind() * 0.5
	vel.x = f.x
	vel.z = f.y
	_roll = lerpf(_roll, -steer * 0.45, 1.0 - exp(-3.0 * delta))
	_pitch = lerpf(_pitch, -0.25 * dive + 0.15 * flare, 1.0 - exp(-3.0 * delta))


## 小直升机：旋翼转起来以后能升空，空中前后左右都能控制，松开就悬停。
func _fly_heli(delta: float) -> void:
	engine = move_toward(engine, 1.0 if rider != null else 0.0, delta * (0.6 if rider != null else 0.3))
	yaw_rate = lerpf(yaw_rate, -steer * 1.3 if (not landed or engine > 0.5) else 0.0, 1.0 - exp(-4.0 * delta))
	var hv := Vector2.ZERO
	if not landed:
		hv = forward() * throttle * (15.0 if sprint else 9.0)
	var before := Vector2(vel.x, vel.z)
	var cur := before.lerp(hv, 1.0 - exp(-1.4 * delta))
	vel.x = cur.x
	vel.z = cur.y
	var vy := lift * (5.0 if sprint else 3.5)
	if engine < 0.8:
		vy = minf(vy, 0.0)
	if rider == null and not landed:
		vy = -2.0
	vel.y = lerpf(vel.y, vy, 1.0 - exp(-2.5 * delta))
	# 机身随加速前倾、随转弯侧倾
	var accel := (cur - before).dot(forward()) / maxf(delta, 1e-4)
	_pitch = lerpf(_pitch, clampf(-accel * 0.05, -0.25, 0.25) if not landed else 0.0, 1.0 - exp(-3.0 * delta))
	_roll = lerpf(_roll, clampf(yaw_rate * 0.15, -0.2, 0.2) if not landed else 0.0, 1.0 - exp(-3.0 * delta))


## 按速度走一步：先扫掠看会不会撞到东西，再贴地面、限高度、限地图范围。
func _move(delta: float) -> void:
	var motion := vel * delta
	if motion.length_squared() > 1e-10:
		motion = _sweep(motion)
	_pos += motion
	var lim := WorldLayout.world_max() - EDGE_MARGIN
	var low := WorldLayout.world_min() + EDGE_MARGIN
	_pos.x = clampf(_pos.x, low, lim)
	_pos.z = clampf(_pos.z, low, lim)
	var ground := floor_height(_pos.x, _pos.z)
	var was_landed := landed
	if _pos.y <= ground + 0.001:
		_pos.y = ground
		vel.y = maxf(vel.y, 0.0)
		landed = true
		on_structure = false
	elif on_structure and vel.y <= 0.05:
		landed = true
	else:
		landed = false
		on_structure = false
	var ceiling := WorldLayout.water_level() + float(MAX_ALTITUDE.get(kind, 90.0))
	if _pos.y > ceiling:
		_pos.y = ceiling
		vel.y = minf(vel.y, 0.0)
	_update_water()
	if landed and not was_landed:
		_touch_down()


func _touch_down() -> void:
	vel.x *= 0.3
	vel.z *= 0.3
	if kind == "glider":
		speed *= 0.4
	if kind != "glider" or over_water:
		vel.x = 0.0
		vel.z = 0.0
	Sound.play("splash_small" if over_water else "land", global_position)


## 形状扫掠：碰到建筑、树干、石头就停在碰上之前。一开始就卡在东西里（比如停放时被树枝罩着）只许往上走。
func _sweep(motion: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis(Vector3.UP, heading), _pos + _shape_offset)
	_query.motion = motion
	var r := space.cast_motion(_query)
	if r[1] >= 1.0:
		return motion
	if r[0] <= 0.0 and r[1] <= 0.0:
		return Vector3(0.0, maxf(motion.y, 0.0), 0.0)
	bumps += 1
	var safe := motion * r[0]
	# 往下落时碰到的是屋顶、码头一类：停在上面
	if motion.y < 0.0 and absf(motion.y) > Vector2(motion.x, motion.z).length() * 0.5:
		on_structure = true
		vel.y = 0.0
	vel.x *= 0.2
	vel.z *= 0.2
	speed *= 0.3
	return safe


func _wind() -> Vector2:
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	if env == null:
		return Vector2.ZERO
	return env.wind_direction.normalized() * env.wind_strength


func _place() -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, heading, _roll)), _pos)


## 下来的落脚点：飞行器旁边一圈干燥（或浅水）、不太陡、没被东西占着的地面；落在深水、屋顶上或还在空中返回 null。
func find_exit() -> Variant:
	if not landed or over_water:
		return null
	if on_structure and _pos.y - WorldTerrain.height_at(_pos.x, _pos.z) > 6.0:
		return null   # 停在高高的屋顶上：下不去
	var water := WorldLayout.water_level()
	var r0 := {"balloon": 1.7, "glider": 1.4, "heli": 1.9}.get(kind, 1.8) as float
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	q.shape = cap
	q.collision_mask = PhysicsLayers.WORLD
	q.exclude = _query.exclude
	for r: float in [r0, r0 + 0.8, r0 + 1.6]:
		for i in 12:
			# 先试右手边，再一圈
			var a := heading + PI + TAU * float(i) / 12.0
			var p := world_position_2d() + Vector2(cos(a), -sin(a)) * r
			var h := WorldTerrain.height_at(p.x, p.y)
			if h < water - DEEP_WATER * 0.8 or WorldTerrain.slope_at(p.x, p.y) > 0.75 or Vegetation.in_keepout(p):
				continue
			var y := maxf(h, water - DEEP_WATER * 0.8)
			q.transform = Transform3D(Basis(), Vector3(p.x, y + 1.0, p.y))
			if not space.intersect_shape(q, 1).is_empty():
				continue
			return Vector3(p.x, y + 0.05, p.y)
	return null


## 滑翔翼飞不起来了（掉进深水里、挂在陡坡的树上，旁边没处下）：可以直接回到出发点。
func can_reset() -> bool:
	return kind == "glider" and landed and (over_water or find_exit() == null)


# ---------------------------------------------------------------- 画面与声音

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved := _pos - _last_pos
	_last_pos = _pos
	_rise = lerpf(_rise, moved.y / delta, 1.0 - exp(-4.0 * delta))
	if rider == null and landed and engine <= 0.0 and (_sound == null or not _sound.on):
		return   # 停着没人：旋翼不转、没有火、没有声音，什么都不用动
	match kind:
		"heli":
			if rider != null and not is_physics_processing():
				engine = move_toward(engine, 1.0, delta * 0.6)   # 别人在开：本机不跑物理，旋翼照样转
			elif rider == null and not is_physics_processing():
				engine = move_toward(engine, 0.0, delta * 0.3)
			if engine > 0.0:
				_rotor.rotate_y(engine * 28.0 * delta)
				_tail_rotor.rotate_x(engine * 40.0 * delta)
			var blur := clampf((engine - 0.35) / 0.4, 0.0, 1.0)
			_blades.visible = blur < 0.75
			_disc.visible = blur > 0.0
			_disc_material.albedo_color.a = 0.28 * blur
			_sound_on(engine > 0.05, 0.6 + 0.5 * engine)
		"balloon":
			var burning := (lift > 0.1) if is_physics_processing() else (_rise > 0.4)
			engine = move_toward(engine, 1.0 if burning else 0.0, delta * 4.0)
			_flame.visible = engine > 0.02
			_flame.scale = Vector3(0.7 + 0.3 * engine, 0.4 + 0.8 * engine + 0.1 * sin(_time * 23.0), 0.7 + 0.3 * engine)
			_flame_light.light_energy = 2.2 * engine
			_sound_on(engine > 0.05, 0.9 + 0.2 * engine)
		"glider":
			var flying := not landed and rider != null
			_sound_on(flying, 0.7 + clampf(speed / 15.0, 0.0, 1.0) * 0.6)


func _sound_on(on: bool, pitch: float) -> void:
	if _sound == null:
		return
	if on != _sound.on:
		_sound.set_on(on)
	_sound.pitch_scale = pitch


# ---------------------------------------------------------------- 模型（方块风格，和人物、小动物同一种材质）

const PX := 0.1


func _build_model() -> void:
	var sound_id := ""
	match kind:
		"balloon":
			_build_balloon()
			sound_id = "burner"
		"glider":
			_build_glider()
			sound_id = "air_rush"
		_:
			_build_heli()
			sound_id = "rotor"
	if SoundBank.has(sound_id):
		_sound = SoundEmitter.create(sound_id, false)
		_sound.position = Vector3(0.0, 1.5, 0.0)
		add_child(_sound)


## boxes：[[lo, hi, color], ...]（米，本地坐标）。
func _mesh(node_name: String, boxes: Array, parent: Node3D = self) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		BlockyMesh.add_box(st, b[0], b[1], b[2])
	var mesh := st.commit()
	mesh.surface_set_material(0, BlockyMesh.material(PX))
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _build_balloon() -> void:
	var wicker := Color(0.62, 0.42, 0.22)
	var rim := Color(0.42, 0.27, 0.14)
	var rope := Color(0.85, 0.8, 0.68)
	var metal := Color(0.3, 0.3, 0.33)
	var boxes := [
		[Vector3(-0.8, 0.0, -0.8), Vector3(0.8, 1.05, 0.8), wicker],
		[Vector3(-0.86, 0.95, -0.86), Vector3(0.86, 1.12, 0.86), rim],
		[Vector3(-0.25, 2.55, -0.25), Vector3(0.25, 2.85, 0.25), metal],
	]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			boxes.append([Vector3(sx * 0.72 - 0.04, 1.1, sz * 0.72 - 0.04), Vector3(sx * 0.72 + 0.04, 3.7, sz * 0.72 + 0.04), rope])
	# 球囊：一层一层的方块叠成一个倒水滴，红、奶白、黄、蓝四色横条
	var profile := [[3.6, 1.0], [4.3, 1.8], [5.0, 2.6], [5.8, 3.2], [6.7, 3.6], [7.8, 3.85], [8.9, 3.75], [9.9, 3.35], [10.8, 2.7], [11.5, 1.8], [12.0, 0.9]]
	var bands := [Color(0.86, 0.26, 0.2), Color(0.96, 0.9, 0.78), Color(0.98, 0.78, 0.3), Color(0.3, 0.5, 0.8)]
	for i in profile.size() - 1:
		var y0: float = profile[i][0]
		var y1: float = profile[i + 1][0]
		var r: float = maxf(profile[i][1], profile[i + 1][1]) if i < 5 else profile[i][1]
		var c: Color = bands[i % bands.size()]
		boxes.append([Vector3(-r, y0, -r * 0.72), Vector3(r, y1, r * 0.72), c])
		boxes.append([Vector3(-r * 0.72, y0, -r), Vector3(r * 0.72, y1, r), c])
	_mesh("Balloon", boxes)
	_flame = _mesh("Flame", [[Vector3(-0.16, 0.0, -0.16), Vector3(0.16, 0.9, 0.16), Color(1.0, 0.62, 0.15)],
		[Vector3(-0.08, 0.1, -0.08), Vector3(0.08, 0.6, 0.08), Color(1.0, 0.95, 0.6)]])
	_flame.position = Vector3(0.0, 2.85, 0.0)
	_flame.material_override = BlockyMesh.material(PX, "glow")
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.65, 0.3)
	_flame_light.omni_range = 9.0
	_flame_light.light_energy = 0.0
	_flame_light.position = Vector3(0.0, 3.4, 0.0)
	add_child(_flame_light)
	var cap := CapsuleShape3D.new()
	cap.radius = 2.6
	cap.height = 11.0
	_shape = cap
	_shape_offset = Vector3(0.0, 6.6, 0.0)


func _build_glider() -> void:
	var sail_a := Color(0.2, 0.62, 0.62)
	var sail_b := Color(0.95, 0.93, 0.86)
	var tube := Color(0.55, 0.57, 0.6)
	var harness := Color(0.25, 0.3, 0.42)
	var boxes := [
		[Vector3(-0.05, 1.95, -1.7), Vector3(0.05, 2.05, 1.6), tube],                 # 龙骨
		[Vector3(-0.62, 0.0, -0.36), Vector3(0.62, 0.06, -0.28), tube],              # 操纵杆横杆
		[Vector3(-0.62, 0.0, -0.36), Vector3(-0.56, 1.95, -0.28), tube],
		[Vector3(0.56, 0.0, -0.36), Vector3(0.62, 1.95, -0.28), tube],
		[Vector3(-0.03, 0.55, 0.12), Vector3(0.03, 1.95, 0.18), tube],               # 吊带
		[Vector3(-0.32, 0.3, -0.1), Vector3(0.32, 0.45, 0.45), harness],              # 坐兜
		[Vector3(-0.32, 0.3, 0.38), Vector3(0.32, 0.95, 0.48), harness],
	]
	# 三角翼：从机头往后一排排变宽，两色相间
	var rows := 7
	for i in rows:
		var z0 := -1.6 + 3.2 * float(i) / rows
		var z1 := -1.6 + 3.2 * float(i + 1) / rows
		var half := 0.45 + 3.1 * float(i + 1) / rows
		var c: Color = sail_a if i % 2 == 0 else sail_b
		boxes.append([Vector3(-half, 2.05, z0), Vector3(-0.05, 2.12, z1), c])
		boxes.append([Vector3(0.05, 2.05, z0), Vector3(half, 2.12, z1), sail_b if i % 2 == 0 else sail_a])
	_mesh("Glider", boxes)
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 1.4, 2.6)
	_shape = box
	_shape_offset = Vector3(0.0, 1.4, 0.0)


func _build_heli() -> void:
	var paint := Color(0.96, 0.74, 0.22)
	var dark := Color(0.22, 0.23, 0.26)
	var glass := Color(0.62, 0.8, 0.9)
	var seat := Color(0.45, 0.2, 0.18)
	var boxes := [
		[Vector3(-0.75, 0.0, -1.25), Vector3(-0.62, 0.1, 1.2), dark],                 # 滑橇
		[Vector3(0.62, 0.0, -1.25), Vector3(0.75, 0.1, 1.2), dark],
		[Vector3(-0.72, 0.1, -0.7), Vector3(-0.64, 0.4, -0.6), dark],
		[Vector3(0.64, 0.1, -0.7), Vector3(0.72, 0.4, -0.6), dark],
		[Vector3(-0.72, 0.1, 0.55), Vector3(-0.64, 0.4, 0.65), dark],
		[Vector3(0.64, 0.1, 0.55), Vector3(0.72, 0.4, 0.65), dark],
		[Vector3(-0.8, 0.4, -1.3), Vector3(0.8, 0.55, 0.9), paint],                   # 机舱地板
		[Vector3(-0.8, 0.55, 0.5), Vector3(0.8, 1.9, 0.9), paint],                    # 后壁
		[Vector3(-0.8, 1.75, -1.0), Vector3(0.8, 1.95, 0.9), paint],                   # 顶
		[Vector3(-0.8, 0.55, -1.3), Vector3(0.8, 0.95, -1.05), paint],                # 机头下半
		[Vector3(-0.8, 0.55, -1.05), Vector3(-0.7, 1.0, 0.5), paint],                 # 两侧下半
		[Vector3(0.7, 0.55, -1.05), Vector3(0.8, 1.0, 0.5), paint],
		[Vector3(-0.8, 1.0, -1.05), Vector3(-0.72, 1.75, -0.95), dark],               # 前立柱
		[Vector3(0.72, 1.0, -1.05), Vector3(0.8, 1.75, -0.95), dark],
		[Vector3(-0.35, 0.55, -0.05), Vector3(0.35, 0.75, 0.45), seat],               # 座椅
		[Vector3(-0.35, 0.75, 0.38), Vector3(0.35, 1.35, 0.5), seat],
		[Vector3(-0.15, 1.15, 0.9), Vector3(0.15, 1.45, 4.2), paint],                 # 尾梁
		[Vector3(-0.06, 1.45, 3.85), Vector3(0.06, 2.2, 4.25), paint],                # 尾翼
		[Vector3(-0.1, 1.95, -0.1), Vector3(0.1, 2.25, 0.1), dark],                   # 旋翼轴
	]
	_mesh("Heli", boxes)
	# 挡风玻璃：半透明（不进合批，第一人称从里面往外看得见）
	var windshield := _mesh("Windshield", [[Vector3(-0.72, 0.95, -1.12), Vector3(0.72, 1.75, -1.04), glass]])
	var gm := ArtMaterials.clear_glass()
	windshield.material_override = gm
	_rotor = Node3D.new()
	_rotor.name = "Rotor"
	_rotor.position = Vector3(0.0, 2.27, 0.0)
	add_child(_rotor)
	_blades = _mesh("Blades", [[Vector3(-2.6, -0.03, -0.12), Vector3(2.6, 0.03, 0.12), dark],
		[Vector3(-0.12, -0.03, -2.6), Vector3(0.12, 0.03, 2.6), dark]], _rotor)
	# 转快了桨叶每帧跳半圈，看着像不动或倒转：换成一片淡淡的圆盘
	_disc = MeshInstance3D.new()
	_disc.name = "RotorDisc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.6
	cyl.bottom_radius = 2.6
	cyl.height = 0.02
	cyl.radial_segments = 32
	cyl.rings = 1
	_disc.mesh = cyl
	_disc_material = ArtMaterials.flat(Color(0.18, 0.19, 0.22), 0.9, false, 0.0, true).duplicate() as StandardMaterial3D
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc.material_override = _disc_material
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.position = Vector3(0.0, 2.27, 0.0)
	_disc.visible = false
	add_child(_disc)
	_tail_rotor = Node3D.new()
	_tail_rotor.name = "TailRotor"
	_tail_rotor.position = Vector3(0.12, 1.85, 4.05)
	add_child(_tail_rotor)
	_mesh("TailBlades", [[Vector3(0.0, -0.5, -0.05), Vector3(0.04, 0.5, 0.05), dark],
		[Vector3(0.0, -0.05, -0.5), Vector3(0.04, 0.05, 0.5), dark]], _tail_rotor)
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.9, 2.8)
	_shape = box
	_shape_offset = Vector3(0.0, 1.05, -0.15)


## 交互用的碰撞体（挡人、让准星能对上）。热气球只有吊篮，滑翔翼是坐兜一圈，直升机是机舱。
func _build_body() -> void:
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	match kind:
		"balloon":
			b.size = Vector3(1.7, 1.15, 1.7)
			cs.position = Vector3(0.0, 0.58, 0.0)
		"glider":
			b.size = Vector3(1.3, 1.0, 1.0)
			cs.position = Vector3(0.0, 0.5, 0.05)
		_:
			b.size = Vector3(1.6, 1.6, 2.2)
			cs.position = Vector3(0.0, 1.1, -0.2)
	cs.shape = b
	_body.add_child(cs)
	add_child(_body)


## 地图上的小图标（小地图、世界地图）：热气球是红色圆球带吊篮，直升机是黄色圆点带旋翼十字，滑翔翼是指向机头的青色三角。
## screen_fwd：机头在地图上的方向（单位向量）；s：大小（像素，约等于半径）。
static func draw_icon(ci: CanvasItem, p: Vector2, kind_id: String, screen_fwd: Vector2, s: float) -> void:
	var ink := Color(0.12, 0.09, 0.06)
	match kind_id:
		"balloon":
			ci.draw_rect(Rect2(p + Vector2(-s * 0.3, s * 0.55), Vector2(s * 0.6, s * 0.45)), Color(0.55, 0.36, 0.18))
			ci.draw_circle(p - Vector2(0.0, s * 0.2), s * 0.75, Color(0.88, 0.28, 0.2))
			ci.draw_arc(p - Vector2(0.0, s * 0.2), s * 0.75, 0.0, TAU, 20, ink, 1.0, true)
		"glider":
			var side := Vector2(-screen_fwd.y, screen_fwd.x)
			var tri := PackedVector2Array([p + screen_fwd * s, p - screen_fwd * s * 0.5 + side * s, p - screen_fwd * s * 0.5 - side * s])
			ci.draw_colored_polygon(tri, Color(0.22, 0.66, 0.66))
			ci.draw_polyline(tri + PackedVector2Array([tri[0]]), ink, 1.0, true)
		_:
			ci.draw_circle(p, s * 0.6, Color(0.97, 0.76, 0.24))
			ci.draw_arc(p, s * 0.6, 0.0, TAU, 18, ink, 1.0, true)
			ci.draw_line(p - Vector2(s, 0.0), p + Vector2(s, 0.0), ink, 1.4)
			ci.draw_line(p - Vector2(0.0, s), p + Vector2(0.0, s), ink, 1.4)
