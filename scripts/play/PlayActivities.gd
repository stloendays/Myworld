class_name PlayActivities
extends Node3D
## 每个世界里的小玩法操作（Main 和 MiniWorld 各放一个，跟着世界一起卸载）：
##   · R 钓鱼：甩竿 → 鱼漂落在前方 4–11 m 的水面（准星越高甩得越远）→ 等鱼咬钩（鱼漂往下一沉）→ 1.5 秒内再按 R 收竿；
##   · Q 打水漂：按住蓄力、松开扔；石头真的在水面上一跳一跳（平着扔、用力扔、跑起来扔弹得多）；
##   · B 挖宝：按本局种子埋的宝箱（线索在旅行日志「活动」页）；挖错地方会说离得远近；
##   · 计时挑战：这个世界的挑战起点立着金环，走（游）进去开始计时，按顺序过检查点；
##   · 哪片水能钓、能扔：世界根节点的 water_at(x, z)；地面高度：世界的 height_at。
## 规则开关和联机做客的限制由 Play.blocked() 判断；记录都写进 WorldState（Play）。

const CAST_MIN := 4.0
const CAST_MAX := 11.0
const BITE_WINDOW := 1.5
const DIG_RADIUS := 2.4
const THROW_HEIGHT := 1.35
const SKIP_MAX_ANGLE := 30.0       ## 入水角度（度）小于这个才弹得起来
const SKIP_MIN_SPEED := 3.0
const SKIP_KEEP_H := 0.82          ## 每弹一次水平速度保留的比例
const SKIP_KEEP_V := 0.6           ## 每弹一次竖直速度保留的比例

var player: FirstPersonController = null
var world: Node3D = null

# 钓鱼
var fish_state := ""               ## "" / "waiting" / "bite"
var bite_wait := -1.0              ## > 0：下一次甩竿等这么久就咬钩（自动检查用）；否则随机 2.5–6 秒
var last_catch: Dictionary = {}
var _bobber: Node3D = null
var _line: MeshInstance3D = null
var _rod: MeshInstance3D = null
var _cast_from := Vector3.ZERO
var _water: Dictionary = {}
var _fish_t := 0.0
var _bite_at := 0.0
var _rng := RandomNumberGenerator.new()

# 打水漂
var charging := false
var charge := 0.0
var last_skip: Dictionary = {}
var _stone: MeshInstance3D = null
var _stone_path := PackedVector3Array()
var _stone_i := 0
var _stone_bounces: Array = []

# 寻宝
var chest: Node3D = null
var last_dig := ""

# 计时挑战
var course_id := ""
var course_index := 0
var course_time := 0.0
var _course_nodes: Dictionary = {}     ## course id -> {start: Node3D, rings: [Node3D]}
var _cool := 0.0

# 界面
var _ui: CanvasLayer
var _status: Label
var _timer_label: Label
var _charge_bar: ProgressBar


func _ready() -> void:
	add_to_group("play_activities")
	world = get_tree().get_first_node_in_group("world_root") as Node3D
	_rng.seed = hash([Play.seed_value(), Time.get_ticks_usec()])
	_build_ui()
	_build_courses.call_deferred()
	_build_found_chest.call_deferred()


func _player() -> FirstPersonController:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	return player


func world_id() -> String:
	return WorldTravel.current_world


func ground_at(x: float, z: float) -> float:
	if world != null and world.has_method("height_at"):
		return float(world.call("height_at", x, z))
	return WorldTerrain.height_at(x, z)


func water_at(x: float, z: float) -> Dictionary:
	if world != null and world.has_method("water_at"):
		return world.call("water_at", x, z)
	return {}


func _unhandled_input(event: InputEvent) -> void:
	var p := _player()
	if p == null or p.input_locked or not p.is_local_controlled:
		return
	if event.is_action_pressed("fish"):
		if fish_state == "":
			cast()
		else:
			reel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("skip_stone"):
		start_charge()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("skip_stone") and charging:
		throw_stone(charge)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dig"):
		dig()
		get_viewport().set_input_as_handled()


func _say(text: String) -> void:
	EventBus.toast_requested.emit(text)


# ---------------------------------------------------------------- 钓鱼

## 甩竿；返回是否甩出去了（落点没有水、不能钓时提示原因）。
func cast() -> bool:
	var p := _player()
	if p == null:
		return false
	var why := Play.blocked("fishing")
	if why == "":
		if p.swimming or p.is_riding() or p.flying:
			why = tr("站在岸边、码头上才能钓鱼")
	if why != "":
		_say(why)
		return false
	var spot := _cast_point(p)
	var w := water_at(spot.x, spot.z)
	if w.is_empty() or str(w.get("fish", "")) == "":
		_say(tr("前面没有能钓鱼的水，走到水边对着水面再甩竿"))
		return false
	_water = w
	_cast_from = p.global_position
	fish_state = "waiting"
	_fish_t = 0.0
	_bite_at = bite_wait if bite_wait > 0.0 else _rng.randf_range(2.5, 6.0)
	_make_bobber(Vector3(spot.x, float(w["y"]), spot.z))
	_status_text(tr("等鱼咬钩……（鱼漂沉下去时按 R 收竿）"))
	return true


## 鱼漂落点：视线方向前方，准星越往上甩得越远。
func _cast_point(p: FirstPersonController) -> Vector3:
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pitch := p.head.rotation.x
	var dist := lerpf(CAST_MIN, CAST_MAX, clampf((pitch + 0.35) / 0.7, 0.0, 1.0))
	return p.global_position + fwd * dist


## 收竿：咬钩时钓上来，否则空竿。返回钓到的鱼（{} = 没钓到）。
func reel() -> Dictionary:
	if fish_state == "":
		return {}
	var got: Dictionary = {}
	if fish_state == "bite":
		got = Play.roll_fish(str(_water["fish"]), _rng)
		if not got.is_empty():
			var first := Play.record_catch(str(got["id"]), float(got["cm"]))
			var f := Play.fish(str(got["id"]))
			last_catch = got
			_say(tr("钓到了%s，%.1f 厘米！") % [Play.text(f, "name"), float(got["cm"])] + (tr("（图鉴新增）") if first else ""))
	else:
		_say(tr("收竿了，还没有鱼咬钩"))
	_end_fishing()
	return got


func _end_fishing() -> void:
	fish_state = ""
	_status_text("")
	if _bobber != null:
		_bobber.queue_free()
		_bobber = null
	if _line != null:
		_line.queue_free()
		_line = null
	if _rod != null:
		_rod.queue_free()
		_rod = null


func _make_bobber(at: Vector3) -> void:
	_bobber = Node3D.new()
	_bobber.name = "Bobber"
	add_child(_bobber)
	_bobber.global_position = at
	var top := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	top.mesh = sm
	top.material_override = ArtMaterials.flat(Color(0.9, 0.15, 0.12), 0.4)
	top.position.y = 0.06
	_bobber.add_child(top)
	var bottom := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 0.07
	sm2.height = 0.1
	bottom.mesh = sm2
	bottom.material_override = ArtMaterials.flat(Color(0.95, 0.95, 0.92), 0.4)
	_bobber.add_child(bottom)
	_line = MeshInstance3D.new()
	_line.name = "FishingLine"
	_line.mesh = ImmediateMesh.new()
	_line.material_override = ArtMaterials.flat(Color(0.92, 0.92, 0.88), 0.5)
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	# 第一人称看得到的鱼竿（挂在相机下，右下角斜伸出去）
	var p := _player()
	if p != null:
		_rod = MeshInstance3D.new()
		_rod.name = "FishingRod"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.6)
		_rod.mesh = bm
		_rod.material_override = ArtMaterials.flat(Color(0.45, 0.3, 0.18), 0.6)
		_rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rod.position = Vector3(0.28, -0.22, -0.9)
		_rod.rotation = Vector3(deg_to_rad(28.0), deg_to_rad(-8.0), 0.0)
		p.camera.add_child(_rod)


func _update_fishing(delta: float) -> void:
	if fish_state == "":
		return
	var p := _player()
	if p == null or p.global_position.distance_to(_cast_from) > 2.5 or p.swimming or p.is_riding():
		_say(tr("走开了，收起鱼竿"))
		_end_fishing()
		return
	_fish_t += delta
	var t := Time.get_ticks_msec() * 0.001
	var base_y := float(_water["y"])
	if fish_state == "waiting":
		_bobber.global_position.y = base_y + sin(t * 2.2) * 0.02
		if _fish_t >= _bite_at:
			fish_state = "bite"
			_fish_t = 0.0
			_status_text(tr("咬钩了！快按 R 收竿！"))
	elif fish_state == "bite":
		_bobber.global_position.y = base_y - 0.12 + sin(t * 18.0) * 0.04
		if _fish_t > BITE_WINDOW:
			_say(tr("鱼跑了……再甩一竿试试"))
			_end_fishing()
			return
	# 鱼线：竿梢到鱼漂，中间往下垂一点
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var tip := p.camera.global_position + p.camera.global_basis * Vector3(0.45, 0.25, -1.6)
	var end := _bobber.global_position + Vector3(0.0, 0.1, 0.0)
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 13:
		var f := float(i) / 12.0
		im.surface_add_vertex(tip.lerp(end, f) - Vector3(0.0, sin(f * PI) * 0.6, 0.0))
	im.surface_end()


# ---------------------------------------------------------------- 打水漂

func start_charge() -> void:
	var why := Play.blocked("skipping")
	var p := _player()
	if why == "" and p != null and (p.swimming or p.is_riding()):
		why = tr("站在湖边或码头上才能打水漂")
	if why != "":
		_say(why)
		return
	charging = true
	charge = 0.0


## 扔一块石头：power 0–1（蓄力），pitch_deg 不给就用准星的俯仰。返回 {bounces, ok}；前面不是水面时不扔。
func throw_stone(power: float, pitch_deg := INF) -> Dictionary:
	charging = false
	_charge_bar.visible = false
	var p := _player()
	if p == null:
		return {}
	var why := Play.blocked("skipping")
	if why != "":
		_say(why)
		return {}
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ahead := p.global_position + fwd * 6.0
	if water_at(ahead.x, ahead.z).is_empty():
		_say(tr("前面不是水面：走到湖边，对着湖扔"))
		return {}
	var pitch := deg_to_rad(pitch_deg) if pitch_deg < INF else p.head.rotation.x
	var running := Vector2(p.velocity.x, p.velocity.z).length() > p.walk_speed + 0.5
	var speed := 8.0 + 8.0 * clampf(power, 0.0, 1.0) + (2.0 if running else 0.0)
	var start := p.global_position + Vector3(0.0, THROW_HEIGHT, 0.0) + fwd * 0.4
	var sim := simulate_skip(start, fwd, pitch, speed)
	last_skip = sim
	_launch_stone(sim)
	return sim


## 模拟一块石头：每 1/60 秒走一步，落到水面时入水角度够平、速度够快就弹起来，否则沉下去；落到岸上就停。
func simulate_skip(start: Vector3, dir: Vector3, pitch: float, speed: float) -> Dictionary:
	var pos := start
	var hv := dir * speed * cos(pitch)
	var vy := speed * sin(pitch)
	var path := PackedVector3Array([pos])
	var bounces := 0
	var splashes: Array = []
	var dt := 1.0 / 60.0
	var landed := "water"
	for i in 60 * 20:
		vy -= 9.8 * dt
		pos += hv * dt + Vector3(0.0, vy * dt, 0.0)
		var w := water_at(pos.x, pos.z)
		var surface := float(w["y"]) if not w.is_empty() else ground_at(pos.x, pos.z)
		if pos.y <= surface:
			pos.y = surface
			path.append(pos)
			if w.is_empty():
				landed = "shore"
				break
			var h := hv.length()
			var angle := rad_to_deg(atan2(-vy, h))
			if angle < SKIP_MAX_ANGLE and h > SKIP_MIN_SPEED:
				bounces += 1
				splashes.append(pos)
				vy = absf(vy) * SKIP_KEEP_V
				hv *= SKIP_KEEP_H
			else:
				splashes.append(pos)
				break
		elif i % 2 == 0:
			path.append(pos)
	return {"bounces": bounces, "path": path, "splashes": splashes, "landed": landed}


func _launch_stone(sim: Dictionary) -> void:
	if _stone != null:
		_stone.queue_free()
	_stone = MeshInstance3D.new()
	_stone.name = "SkipStone"
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.05
	_stone.mesh = sm
	_stone.material_override = ArtMaterials.flat(Color(0.55, 0.55, 0.58), 0.7)
	add_child(_stone)
	_stone_path = sim["path"]
	_stone_bounces = sim["splashes"]
	_stone_i = 0
	_stone.global_position = _stone_path[0]


func _update_stone() -> void:
	if _stone == null:
		return
	_stone_i += 1
	if _stone_i >= _stone_path.size():
		var n := int(last_skip.get("bounces", 0))
		var best := Play.record_skip(n)
		var tail := tr("（新纪录！）") if best and n > 0 else tr("（最好 %d 下）") % int(WorldState.records.get("skip_best", 0))
		if str(last_skip.get("landed", "")) == "shore":
			_say(tr("弹了 %d 下，落到岸上了") % n + tail)
		else:
			_say((tr("弹了 %d 下！") % n if n > 0 else tr("扑通——一下就沉了，扔平一点、用力一点")) + tail)
		_stone.queue_free()
		_stone = null
		return
	var at := _stone_path[_stone_i]
	_stone.global_position = at
	_stone.rotate_y(0.6)
	for s: Vector3 in _stone_bounces:
		if s.distance_to(at) < 0.01:
			_splash(s)


func _splash(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.0, -6.0, 0.0)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	p.mesh = sm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- 寻宝

## 在脚下挖：返回 "found" / "far" / "near" / "close" / "already" / "blocked"。
func dig() -> String:
	var p := _player()
	if p == null:
		return "blocked"
	var why := Play.blocked("treasure")
	var g := ground_at(p.global_position.x, p.global_position.z)
	if why == "" and (p.is_riding() or p.flying or WorldState.is_indoors(p.entity_id) or p.global_position.y - g > 1.4):
		why = tr("站在地上（或贴着海底）才能挖")
	if why != "":
		_say(why)
		last_dig = "blocked"
		return last_dig
	var spot := Play.treasure_spot(world_id())
	if spot.is_empty():
		_say(tr("这个世界没有埋宝藏"))
		last_dig = "blocked"
		return last_dig
	var me := Vector2(p.global_position.x, p.global_position.z)
	var d := me.distance_to(spot["pos"])
	_dirt(Vector3(p.global_position.x, g, p.global_position.z) + (-p.global_basis.z * 0.8))
	if Play.treasure_found(world_id()):
		_say(tr("这个世界的宝箱已经挖到了"))
		last_dig = "already"
	elif d <= DIG_RADIUS:
		_open_chest(Vector3(spot["pos"].x, ground_at(spot["pos"].x, spot["pos"].y), spot["pos"].y), true)
		Play.mark_treasure(world_id())
		_say(tr("挖到宝箱了！里面是一枚刻着「%s」的金币") % tr(str(WorldRegistry.current().get("name", ""))))
		last_dig = "found"
	elif d < 8.0:
		_say(tr("这里什么也没有……不过就在附近了！"))
		last_dig = "close"
	elif d < 25.0:
		_say(tr("这里什么也没有。线索说的地方不太远了"))
		last_dig = "near"
	else:
		_say(tr("这里什么也没有。线索说的地方还远着呢（旅行日志 → 活动）"))
		last_dig = "far"
	return last_dig


func _dirt(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 16
	p.lifetime = 0.7
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.06)
	bm.material = ArtMaterials.flat(Color(0.45, 0.34, 0.24), 0.95)
	p.mesh = bm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## 宝箱：木箱 + 铜边 + 盖子；animate = 从土里升起、打开盖子、冒出金光。
func _open_chest(at: Vector3, animate: bool) -> void:
	if chest != null:
		chest.queue_free()
	chest = Node3D.new()
	chest.name = "TreasureChest"
	add_child(chest)
	chest.global_position = at + Vector3(0.0, -0.6 if animate else 0.0, 0.0)
	var wood := ArtMaterials.pbr("weathered_planks", Color(0.72, 0.5, 0.32), "world")
	var brass := ArtMaterials.flat(Color(0.86, 0.66, 0.28), 0.35, false, 0.8)
	_part(chest, Vector3(0.9, 0.5, 0.6), Vector3(0.0, 0.25, 0.0), wood)
	_part(chest, Vector3(0.94, 0.08, 0.64), Vector3(0.0, 0.48, 0.0), brass)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0.0, 0.52, -0.3)
	chest.add_child(lid)
	_part(lid, Vector3(0.9, 0.22, 0.6), Vector3(0.0, 0.11, 0.3), wood)
	var gold := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.2
	gold.mesh = sm
	gold.material_override = ArtMaterials.glow(Color(1.0, 0.8, 0.3), 2.4)
	gold.position = Vector3(0.0, 0.5, 0.0)
	chest.add_child(gold)
	if animate:
		var tw := chest.create_tween()
		tw.tween_property(chest, "global_position", at, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(lid, "rotation:x", deg_to_rad(-75.0), 0.5)
	else:
		lid.rotation.x = deg_to_rad(-75.0)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


## 回到挖过宝箱的世界：开着的宝箱还在原处。
func _build_found_chest() -> void:
	if not Play.treasure_found(world_id()):
		return
	var spot := Play.treasure_spot(world_id())
	if not spot.is_empty():
		var v: Vector2 = spot["pos"]
		_open_chest(Vector3(v.x, ground_at(v.x, v.y), v.y), false)


# ---------------------------------------------------------------- 计时挑战

func course_point(c: Dictionary, a: Array) -> Vector3:
	if a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	var x := float(a[0])
	var z := float(a[1])
	return Vector3(x, ground_at(x, z), z)


func _is_water_course(c: Dictionary) -> bool:
	return (c.get("start", []) as Array).size() == 3


## 本世界的挑战：起点金环一直在；检查点的环在跑的时候才显示（潜水环一直显示，它就是赛道）。
func _build_courses() -> void:
	for c: Dictionary in Play.courses():
		if str(c["world"]) != world_id() or (c.get("start", []) as Array).is_empty():
			continue
		var water := _is_water_course(c)
		var gold := ArtMaterials.glow(Color(1.0, 0.78, 0.3), 2.2)
		var blue := ArtMaterials.glow(Color(0.45, 0.85, 1.0), 1.8)
		var start := _ring_node(course_point(c, c["start"]), float(c["radius"]), gold, water)
		start.name = "CourseStart_" + str(c["id"])
		var rings: Array = []
		for pt: Array in c["points"]:
			var r := _ring_node(course_point(c, pt), float(c["radius"]), blue, water)
			r.visible = water
			rings.append(r)
		_course_nodes[str(c["id"])] = {"start": start, "rings": rings}
		start.visible = GameRules.flag("challenges")


func _ring_node(at: Vector3, radius: float, mat: Material, water: bool) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at + Vector3(0.0, 0.0 if water else 0.05, 0.0)
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.12
	tm.outer_radius = radius
	tm.rings = 32
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if water:
		mi.rotation.x = PI * 0.5     # 竖着的环，游过去
	n.add_child(mi)
	if not water:
		# 地上的：一道竖着的拱门 + 地上一圈
		var arch := MeshInstance3D.new()
		var tm2 := TorusMesh.new()
		tm2.inner_radius = 1.5
		tm2.outer_radius = 1.62
		tm2.rings = 32
		arch.mesh = tm2
		arch.material_override = mat
		arch.rotation.x = PI * 0.5
		arch.position.y = 1.2
		arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(arch)
	return n


func start_course(id: String) -> bool:
	var why := Play.blocked("challenges")
	if why != "":
		return false
	var c := Play.course(id)
	if c.is_empty():
		return false
	course_id = id
	course_index = 0
	course_time = 0.0
	var nodes: Dictionary = _course_nodes.get(id, {})
	for r: Node3D in nodes.get("rings", []):
		r.visible = true
	_highlight()
	_say(tr("挑战开始：%s——按顺序经过 %d 个环") % [Play.text(c, "name"), (c["points"] as Array).size()])
	return true


func _highlight() -> void:
	var nodes: Dictionary = _course_nodes.get(course_id, {})
	var rings: Array = nodes.get("rings", [])
	for i in rings.size():
		(rings[i] as Node3D).scale = Vector3.ONE * (1.25 if i == course_index else 1.0)


func cancel_course(reason := "") -> void:
	if course_id == "":
		return
	var c := Play.course(course_id)
	var nodes: Dictionary = _course_nodes.get(course_id, {})
	for r: Node3D in nodes.get("rings", []):
		r.visible = _is_water_course(c)
		r.scale = Vector3.ONE
	course_id = ""
	_timer_label.visible = false
	if reason != "":
		_say(reason)
	_cool = 3.0


func _update_course(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	_cool = maxf(0.0, _cool - delta)
	if course_id == "":
		if _cool > 0.0 or not GameRules.flag("challenges") or Net.is_client():
			return
		for id: String in _course_nodes:
			var c := Play.course(id)
			var s := course_point(c, c["start"])
			if _reached(c, s, p):
				start_course(id)
				_cool = 2.0
				return
		return
	var c := Play.course(course_id)
	course_time += delta
	var pts: Array = c["points"]
	var target := course_point(c, pts[course_index])
	if _reached(c, target, p):
		course_index += 1
		var nodes: Dictionary = _course_nodes.get(course_id, {})
		var rings: Array = nodes.get("rings", [])
		if course_index - 1 < rings.size():
			(rings[course_index - 1] as Node3D).visible = false
		if course_index >= pts.size():
			Play.finish_course(course_id, course_time)
			cancel_course()
			return
		_highlight()
	elif course_time > 300.0 or p.global_position.distance_to(target) > 160.0:
		cancel_course(tr("挑战中断了"))
		return
	_timer_label.visible = true
	_timer_label.text = "%s   %.1f s   ·   %d / %d" % [Play.text(c, "name"), course_time, course_index, pts.size()]


func _reached(c: Dictionary, at: Vector3, p: FirstPersonController) -> bool:
	var r := float(c["radius"])
	if _is_water_course(c):
		return (p.global_position + Vector3(0.0, 0.9, 0.0)).distance_to(at) <= r
	return Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() <= r and absf(p.global_position.y - at.y) < 3.0


# ---------------------------------------------------------------- 每帧

func _physics_process(delta: float) -> void:
	_update_fishing(delta)
	_update_stone()
	_update_course(delta)
	if charging:
		charge = minf(1.0, charge + delta)
		_charge_bar.visible = true
		_charge_bar.value = charge * 100.0


func _status_text(t: String) -> void:
	_status.text = t
	_status.visible = t != ""


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 9
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameSettings.ui_theme()
	_ui.add_child(root)
	_status = _hud_label(root, 0.7, 22, Color(0.85, 0.95, 1.0))
	_timer_label = _hud_label(root, 0.1, 24, Color(1.0, 0.86, 0.45))
	_status.visible = false
	_timer_label.visible = false
	_charge_bar = ProgressBar.new()
	_charge_bar.show_percentage = false
	_charge_bar.anchor_left = 0.5
	_charge_bar.anchor_right = 0.5
	_charge_bar.anchor_top = 0.66
	_charge_bar.anchor_bottom = 0.66
	_charge_bar.offset_left = -110.0
	_charge_bar.offset_right = 110.0
	_charge_bar.offset_bottom = 10.0
	_charge_bar.visible = false
	root.add_child(_charge_bar)


func _hud_label(root: Control, y: float, size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = y
	l.anchor_bottom = y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.7)
	l.label_settings = ls
	root.add_child(l)
	return l


func status_text() -> String:
	return _status.text if _status.visible else ""


func timer_text() -> String:
	return _timer_label.text if _timer_label.visible else ""
