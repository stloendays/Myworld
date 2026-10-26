class_name AudioDirector
extends Node
## M3 声音（Autoload，名字 Sound；规格第 07 章）。声音文件全部由 devtools/audio/synth.mjs 合成（原创 CC0），声音表在 data/audio/sounds.json。
## 本节点只读世界状态（WorldState、天气混合、昼夜、区域、玩家），统一混音，不写任何状态：
##   · 总线：MUSIC、AMB_OUTDOOR、AMB_WEATHER、AMB_INDOOR、FOLEY、UI（启动时建好；户外与天气两条带低通）。
##   · 环境层（不定位的循环）：松风 / 寒风、白天树叶、夏秋夜的虫鸣、小雨 / 大雨、屋里听到的屋顶雨、山洞、泳池馆、水下；
##     其他世界各有一层（云海的风与风铃、沙丘的干风、亚特兰蒂斯穹顶的嗡鸣与鲸歌）。每层 1.5 秒淡入淡出。
##   · 进屋：户外与天气两条总线在约 1.7 秒内降 14 dB、低通压到 750 Hz（QA-05：2.5 秒内减弱、不瞬间切断）；门开着时只降一部分。
##     水下：同样压低通，叠一层水下的闷声。
##   · 定位声源：湖水从离你最近的岸边传来、小溪从最近的一段溪水传来（跟着你移动的 3D 声源）；炉火、篝火、瀑布、仙境由
##     各自的建造脚本挂 SoundEmitter；白天林子里随机方向的鸟叫，夜里的猫头鹰和湖边的青蛙。
##   · 雷：EventBus.lightning_strike 按距离延迟（声速 343 m/s），近的带炸裂声。
##   · 脚步：按地面换声音（草、砂石、木板、石头、雪、沙、浅水），走 0.75 m / 跑 1.05 m 一步；落地、入水、划水、出水。
##   · 交互：门开关、开锁、开关灯、生火熄火、坐下、风灯、雕像、祭坛（按 interactable_state_changed，世界刚建好的 2 秒内不响，
##     免得读档恢复状态时一齐响）；所有按钮的点击；发现地点、捡到东西、任务完成、拍照。
##   · 音乐：MusicDirector（子节点 music）。
## 音量：设置里的总音量、音乐、环境声、音效、界面（GameSettings.volume_*）。

const BUSES := ["MUSIC", "AMB_OUTDOOR", "AMB_WEATHER", "AMB_INDOOR", "FOLEY", "UI"]
const LAYERS := ["wind", "cold_wind", "forest", "crickets", "rain_light", "rain_heavy", "rain_roof", "underwater", "cave", "pool",
	"cloud_wind", "desert_wind", "dome"]
const ROOFED := [&"cabin_interior", &"poolhouse", &"cottage_interior"]
const INDOOR_TAU := 0.55       ## 进出室内的平滑时间常数（约 1.7 秒到 95 %）
const INDOOR_DB := -14.0
const INDOOR_CUTOFF := 750.0
const UNDERWATER_CUTOFF := 380.0
const OPEN_CUTOFF := 20500.0
const LAYER_FADE := 1.5        ## 环境层淡入淡出（秒）
const LOAD_QUIET := 2.0        ## 世界刚建好时不放交互音效（读档恢复门灯状态时）
const HEAR_RADIUS := 32.0      ## 交互音效只放听得见范围内的
const STRIDE_WALK := 0.75
const STRIDE_RUN := 1.05

var indoor := 0.0              ## 0..1：人在室内的程度（平滑过的）
var underwater := 0.0
var steps := 0                 ## 一共放了几步脚步声（自动检查读）
var last_surface := ""
var last_sound := ""           ## 最近一次放的音效 id（自动检查读）
var counts: Dictionary = {}     ## 每个音效 id 放过几次（自动检查读）
var layer_gain: Dictionary = {}
var music: MusicDirector = null

var _layers: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _pool3d_i := 0
var _lake: AudioStreamPlayer3D = null
var _creek: AudioStreamPlayer3D = null
var _creek_lines: Array[PackedVector2Array] = []
var _water_t := 0.0
var _stride := 0.0
var _airborne := false
var _fall_speed := 0.0
var _was_water := false
var _swim_t := 0.0
var _bird_t := 4.0
var _night_t := 8.0
var _quiet := LOAD_QUIET
var _world_root: Node = null
var _interactables: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	ensure_buses()
	for id: String in LAYERS:
		var p := AudioStreamPlayer.new()
		p.name = "Layer_" + id
		p.stream = SoundBank.stream(id)
		p.bus = SoundBank.bus(id)
		p.volume_db = -80.0
		add_child(p)
		_layers[id] = p
		layer_gain[id] = 0.0
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 12:
		var p3 := _player3d()
		_pool3d.append(p3)
	_lake = _player3d()
	_lake.name = "Lake"
	_lake.stream = SoundBank.stream("lake")
	_creek = _player3d()
	_creek.name = "Creek"
	_creek.stream = SoundBank.stream("creek")
	for p3 in [_lake, _creek]:
		var id := "lake" if p3 == _lake else "creek"
		p3.bus = SoundBank.bus(id)
		p3.unit_size = float(SoundBank.info(id).get("unit_size", 6.0))
		p3.max_distance = float(SoundBank.info(id).get("max_distance", 50.0))
		p3.volume_db = SoundBank.volume_db(id)
	music = MusicDirector.new()
	music.name = "Music"
	add_child(music)
	EventBus.lightning_strike.connect(_on_lightning)
	EventBus.interactable_state_changed.connect(_on_interactable)
	EventBus.discovered.connect(func(_id: StringName) -> void: play("discover"))
	EventBus.collected.connect(func(_w: String, _i: String) -> void: play("pickup"))
	EventBus.photo_taken.connect(func(_s: Array) -> void: play("shutter"))
	QuestLog.quest_completed.connect(func(_q: String) -> void: play("quest"))
	GameSettings.changed.connect(apply_volumes)
	get_tree().node_added.connect(_on_node_added)
	apply_volumes()


## 建总线（项目里没有总线布局文件，启动时按规格建）：户外、天气、音效带低通（进屋、水下用），音乐带一点混响。
static func ensure_buses() -> void:
	for bus_name: String in BUSES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, &"Master")
		if bus_name in ["AMB_OUTDOOR", "AMB_WEATHER", "FOLEY"]:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = OPEN_CUTOFF
			AudioServer.add_bus_effect(i, lp)
		if bus_name == "MUSIC":
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.65
			rv.damping = 0.4
			rv.wet = 0.22
			rv.dry = 1.0
			AudioServer.add_bus_effect(i, rv)


func _player3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	return p


# ---------------------------------------------------------------- 放声音

## 放一个音效：at 是世界坐标时在那里放（3D），否则不定位；db 叠在 sounds.json 的音量上。
func play(id: String, at: Variant = null, db := 0.0) -> void:
	var s := SoundBank.stream(id)
	if s == null:
		return
	last_sound = id
	counts[id] = int(counts.get(id, 0)) + 1
	if at is Vector3:
		var p3 := _pool3d[_pool3d_i]
		_pool3d_i = (_pool3d_i + 1) % _pool3d.size()
		var d := SoundBank.info(id)
		p3.stop()
		p3.stream = s
		p3.bus = SoundBank.bus(id)
		p3.unit_size = float(d.get("unit_size", 3.0))
		p3.max_distance = float(d.get("max_distance", 35.0))
		p3.volume_db = SoundBank.volume_db(id) + db
		p3.pitch_scale = SoundBank.pitch(id)
		p3.global_position = at
		p3.play()
	else:
		var p := _pool[_pool_i]
		_pool_i = (_pool_i + 1) % _pool.size()
		p.stop()
		p.stream = s
		p.bus = SoundBank.bus(id)
		p.volume_db = SoundBank.volume_db(id) + db
		p.pitch_scale = SoundBank.pitch(id)
		p.play()


## 设置里的音量（0..1）换成各总线的分贝；0 就静音。户外与天气两条另外叠进屋的衰减（_mix_buses）。
func apply_volumes() -> void:
	_set_bus("Master", GameSettings.volume_master, 0.0)
	_set_bus("MUSIC", GameSettings.volume_music, 0.0)
	_set_bus("AMB_INDOOR", GameSettings.volume_ambience, 0.0)
	_set_bus("FOLEY", GameSettings.volume_effects, 0.0)
	_set_bus("UI", GameSettings.volume_ui, 0.0)
	_mix_buses()


func _set_bus(bus_name: String, linear: float, extra_db: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)) + extra_db)


func _mix_buses() -> void:
	var amb := float(GameSettings.volume_ambience)
	var cut := minf(lerpf(OPEN_CUTOFF, INDOOR_CUTOFF, indoor), lerpf(OPEN_CUTOFF, UNDERWATER_CUTOFF, underwater))
	for bus_name in ["AMB_OUTDOOR", "AMB_WEATHER"]:
		_set_bus(bus_name, amb, INDOOR_DB * indoor - 6.0 * underwater)
		_set_cutoff(bus_name, cut)
	_set_cutoff("FOLEY", lerpf(OPEN_CUTOFF, UNDERWATER_CUTOFF * 2.0, underwater))


func _set_cutoff(bus_name: String, hz: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0 or AudioServer.get_bus_effect_count(i) == 0:
		return
	var lp := AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter
	if lp != null:
		lp.cutoff_hz = hz


## 户外总线现在的音量（dB，已含设置）与低通截止频率，自动检查读。
func bus_state(bus_name: String) -> Dictionary:
	var i := AudioServer.get_bus_index(bus_name)
	var lp := AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter if AudioServer.get_bus_effect_count(i) > 0 else null
	return {"db": AudioServer.get_bus_volume_db(i), "cutoff": lp.cutoff_hz if lp != null else 0.0}


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	var root := get_tree().get_first_node_in_group("world_root")
	if root != _world_root:
		_world_root = root
		_quiet = LOAD_QUIET
		_interactables.clear()
	_quiet = maxf(_quiet - delta, 0.0)
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var targets := {}
	for id: String in LAYERS:
		targets[id] = 0.0
	var in_t := 0.0
	var uw_t := 0.0
	if root != null and player != null and player.is_inside_tree():
		var zones := WorldState.zones_of(player.entity_id)
		if WorldState.is_indoors(player.entity_id):
			in_t = 0.6 if _door_open_near(player) else 1.0
		var cam := get_viewport().get_camera_3d()
		if cam != null and WaterVolume.find(get_tree(), cam.global_position) != null:
			uw_t = 1.0
		if root.has_method("in_sea") and root.call("in_sea") and player.swimming:
			uw_t = 1.0
		match WorldTravel.current_world:
			"dusk_lake":
				_lake_layers(targets, zones)
			"world_02":
				targets["cloud_wind"] = 1.0
			"world_03":
				targets["desert_wind"] = 1.0
			"world_04":
				targets["dome"] = 1.0
		targets["underwater"] = uw_t
		_water_t -= delta
		if _water_t <= 0.0:
			_water_t = 0.1
			_follow_water(player, root)
		_footsteps(delta, player)
		_wildlife(delta, player)
	else:
		_lake.stop()
		_creek.stop()
	indoor += (in_t - indoor) * (1.0 - exp(-delta / INDOOR_TAU))
	underwater += (uw_t - underwater) * (1.0 - exp(-delta / 0.2))
	for id: String in LAYERS:
		var g := move_toward(float(layer_gain[id]), float(targets[id]), delta / LAYER_FADE)
		layer_gain[id] = g
		var p := _layers[id] as AudioStreamPlayer
		if g > 0.002:
			p.volume_db = SoundBank.volume_db(id) + linear_to_db(g)
			if not p.playing and p.stream != null:
				p.play(_rng.randf() * p.stream.get_length())
		elif p.playing:
			p.stop()
	_mix_buses()


## 湖畔的环境层：风随风力（下雪时换成寒风）、白天的树叶、夏秋夜的虫鸣、雨；屋里听屋顶雨；山洞和泳池馆的底噪。
func _lake_layers(t: Dictionary, zones: Array) -> void:
	var w := WeatherController.blended()
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var night := env.night if env != null else 0.0
	var wind := clampf(float(w.get("wind", 0.3)), 0.0, 1.0)
	var rain := clampf(float(w.get("rain", 0.0)), 0.0, 1.0)
	var snow := clampf(float(w.get("snow", 0.0)), 0.0, 1.0)
	var winter := WorldState.season_id == &"WINTER"
	var cold := maxf(snow, 0.6 if winter else 0.0)
	t["wind"] = clampf(0.3 + 0.7 * wind, 0.0, 1.0) * (1.0 - cold * 0.8)
	t["cold_wind"] = cold * clampf(0.4 + 0.6 * wind, 0.0, 1.0)
	t["forest"] = (1.0 - night) * (0.5 + 0.5 * wind) * (0.0 if winter else 1.0) * (1.0 - rain * 0.7)
	var bugs: float = {&"SUMMER": 1.0, &"AUTUMN": 0.7, &"SPRING": 0.35}.get(WorldState.season_id, 0.0)
	t["crickets"] = night * bugs * (1.0 - rain) * (1.0 - snow)
	t["rain_light"] = smoothstep(0.02, 0.35, rain) * (1.0 - smoothstep(0.45, 0.85, rain))
	t["rain_heavy"] = smoothstep(0.45, 0.85, rain)
	var roofed := false
	for z in zones:
		if z in ROOFED:
			roofed = true
	t["rain_roof"] = smoothstep(0.02, 0.5, rain) if roofed else 0.0
	t["cave"] = 1.0 if &"cave" in zones else 0.0
	t["pool"] = 1.0 if &"poolhouse" in zones or &"aquarium" in zones else 0.0


## 人在屋里、门开着（6 m 内有一扇开着的门）：外面的声音透进来多一些。
func _door_open_near(player: FirstPersonController) -> bool:
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n is InteractableDoor or n is CottageDoor) and n.call("is_open") \
				and (n as Node3D).global_position.distance_to(player.global_position) < 6.0:
			return true
	return false


## 湖水声源放在离你最近的湖岸上（人在湖上时就在脚下），小溪声源放在离你最近的那段溪水上。
func _follow_water(player: FirstPersonController, root: Node) -> void:
	var p := player.global_position
	if WorldTravel.current_world != "dusk_lake" or not root is Main:
		_lake.stop()
		_creek.stop()
		return
	var lake := WorldLayout.section("lake")
	var c := WorldLayout.v2(lake["center"])
	var radii: Array = lake["radii"]
	var r := Vector2(float(radii[0]), float(radii[1])) * float(lake.get("inner", 0.82))
	var d := (Vector2(p.x, p.z) - c) / r
	var edge := c + (d.normalized() if d.length() > 1.0 else d) * r
	_lake.global_position = Vector3(edge.x, WorldLayout.water_level() + 0.3, edge.y)
	if not _lake.playing:
		_lake.play(_rng.randf() * _lake.stream.get_length())
	# 用布局里溪水的原始折点（十来个）找最近的一段，最后只算一次地面高度
	if _creek_lines.is_empty():
		for ch: Dictionary in WorldLayout.section("terrain").get("channels", []):
			if str(ch.get("kind", "")) == "creek":
				var line := PackedVector2Array()
				for q: Array in ch["points"]:
					line.append(WorldLayout.v2(q))
				_creek_lines.append(line)
	var me := Vector2(p.x, p.z)
	var best := Vector2.ZERO
	var best_d := INF
	for line: PackedVector2Array in _creek_lines:
		for i in line.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(me, line[i], line[i + 1])
			if q.distance_to(me) < best_d:
				best_d = q.distance_to(me)
				best = q
	if best_d < 60.0:
		_creek.global_position = Vector3(best.x, WorldTerrain.height_at(best.x, best.y) + 0.3, best.y)
		if not _creek.playing:
			_creek.play(_rng.randf() * _creek.stream.get_length())
	elif _creek.playing:
		_creek.stop()


# ---------------------------------------------------------------- 鸟、虫、雷

## 白天林子里随机方向的鸟叫；夜里偶尔一声猫头鹰，春夏的夜里湖边有青蛙。云海浮岛上也有零星的鸟。
func _wildlife(delta: float, player: FirstPersonController) -> void:
	var world := WorldTravel.current_world
	if world != "dusk_lake" and world != "world_02":
		return
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var night := env.night if env != null else (0.0 if world == "world_02" else 1.0)
	var w := WeatherController.blended() if world == "dusk_lake" else {}
	var rain := float(w.get("rain", 0.0))
	var season: float = {&"SPRING": 1.0, &"SUMMER": 1.0, &"AUTUMN": 0.6, &"WINTER": 0.2}.get(WorldState.season_id, 0.6) if world == "dusk_lake" else 0.4
	var p := player.global_position
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(2.5, 7.0)
		if _rng.randf() < (1.0 - night) * season * (1.0 - rain):
			var a := _rng.randf() * TAU
			play("bird", p + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(12.0, 34.0) + Vector3(0.0, _rng.randf_range(4.0, 11.0), 0.0), _rng.randf_range(-6.0, 0.0))
	_night_t -= delta
	if _night_t <= 0.0 and world == "dusk_lake":
		_night_t = _rng.randf_range(6.0, 16.0)
		if night > 0.6 and rain < 0.2:
			if _rng.randf() < 0.3:
				var a2 := _rng.randf() * TAU
				play("owl", p + Vector3(cos(a2), 0.0, sin(a2)) * _rng.randf_range(25.0, 50.0) + Vector3(0.0, 8.0, 0.0))
			elif WorldState.season_id in [&"SPRING", &"SUMMER"] and _lake.playing \
					and _lake.global_position.distance_to(p) < 35.0:
				var off := Vector3(_rng.randf_range(-8.0, 8.0), 0.0, _rng.randf_range(-8.0, 8.0))
				play("frog", _lake.global_position + off)


## 闪电以后按距离延迟打雷：近（< 900 m）的带一声炸裂，越远越小声。
func _on_lightning(distance_m: float) -> void:
	if WorldTravel.current_world != "dusk_lake":
		return
	var delay := distance_m / 343.0
	var db := -14.0 * clampf((distance_m - 300.0) / 2700.0, 0.0, 1.0)
	get_tree().create_timer(delay).timeout.connect(play.bind("thunder", null, db))


# ---------------------------------------------------------------- 脚步与水

func _footsteps(delta: float, player: FirstPersonController) -> void:
	var p := player.global_position
	var in_water := player.swimming
	if in_water != _was_water:
		_was_water = in_water
		if in_water:
			play("splash", p + Vector3(0.0, 1.0, 0.0))
		else:
			play("drip")
	if in_water:
		var v := player.velocity.length()
		_swim_t -= delta
		if v > 0.6 and _swim_t <= 0.0:
			_swim_t = 1.0
			play("swim")
		return
	if player.is_riding() or player.seat != null or player.flying:
		_airborne = false
		return
	if not player.is_on_floor():
		_airborne = true
		_fall_speed = maxf(_fall_speed, -player.velocity.y)
		return
	if _airborne:
		_airborne = false
		if _fall_speed > 3.2:
			play("land")
			_step(player, 2.0)
		_fall_speed = 0.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed < 0.4:
		_stride = STRIDE_WALK * 0.6
		return
	_stride += speed * delta
	if _stride >= (STRIDE_RUN if speed > 4.5 else STRIDE_WALK):
		_stride = 0.0
		_step(player, 0.0)


func _step(player: FirstPersonController, db: float) -> void:
	last_surface = surface_at(player)
	steps += 1
	play("step_" + last_surface, null, db)


## 脚下是什么：碰撞体上标了 surface 的按标的（码头、桥、木屋）；地形按世界和位置（湖畔：浅水、雪线以上和冬天的积雪、
## 湖边沙滩、步道砂石、其余草地；云海草地；沙丘沙子；亚特兰蒂斯城里石头、城外沙底）；室内按区域（木屋、石头小屋木地板，
## 泳池馆、水族馆、山洞石头）；其他东西（石头、台阶）算石头。
func surface_at(player: FirstPersonController) -> String:
	var p := player.global_position
	var world := WorldTravel.current_world
	var zones := WorldState.zones_of(player.entity_id)
	if world == "dusk_lake" and p.y < WorldLayout.water_level() + 0.08 and _in_lake(p):
		return "water"
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 0.3, 0.0), p - Vector3(0.0, 0.5, 0.0), PhysicsLayers.WORLD))
	var col: Object = hit.get("collider") if not hit.is_empty() else null
	if col != null and col.has_meta("surface"):
		return str(col.get_meta("surface"))
	for z in zones:
		if z in [&"cabin_interior", &"cottage_interior"]:
			return "wood"
		if z in [&"poolhouse", &"aquarium", &"cave"]:
			return "stone"
	var terrain: bool = col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & PhysicsLayers.TERRAIN) != 0
	if col != null and not terrain:
		return "stone"
	match world:
		"world_02":
			return "grass"
		"world_03":
			return "sand"
		"world_04":
			return "stone" if Vector2(p.x, p.z).length() < 62.0 else "sand"
	if WorldState.season_id == &"WINTER" and WorldState.ground_snow > 0.3 or p.y > 27.0:
		return "snow"
	if p.y < WorldLayout.water_level() + 0.6 and _in_lake(p, 1.2):
		return "sand"
	if WorldLayout.distance_to_paths(Vector2(p.x, p.z)) < 1.4:
		return "gravel"
	return "grass"


func _in_lake(p: Vector3, grow := 1.0) -> bool:
	var lake := WorldLayout.section("lake")
	var c := WorldLayout.v2(lake["center"])
	var radii: Array = lake["radii"]
	var r := Vector2(float(radii[0]), float(radii[1])) * float(lake.get("inner", 0.82)) * grow
	return ((Vector2(p.x, p.z) - c) / r).length() < 1.0


# ---------------------------------------------------------------- 交互与界面

func _on_interactable(uid: StringName, state: String) -> void:
	if _quiet > 0.0:
		return
	var node := _find_interactable(uid)
	if node == null:
		return
	var at := node.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(at) > HEAR_RADIUS:
		return
	if node is InteractableDoor or node is CottageDoor:
		match state:
			"open":
				play("door_open", at)
			"closed":
				play("door_close", at)
	elif node is InteractableToggle:
		var fire := String(uid).contains("stove") or String(uid).contains("fire")
		if fire:
			play("fire_ignite" if state == "on" else "fire_out", at)
		else:
			play("switch", at)
	elif node is Seat or node is Bed:
		if state == "occupied":
			play("cloth", at)
	elif node is WindBeacon:
		if state == "lit":
			play("beacon", at)
	elif node is LightStatue:
		play("stone_turn", at)
	elif node is RelicAltar:
		play("altar", at)


func _find_interactable(uid: StringName) -> Node3D:
	var n: Variant = _interactables.get(uid)
	if n != null and is_instance_valid(n):
		return n
	for c in get_tree().get_nodes_in_group("interactables"):
		if (c as Interactable).uid == uid:
			_interactables[uid] = c
			return c
	return null


## 所有按钮（菜单、对话选项、日志的页签……）按下时轻轻一响。
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("ui_click", null, 0.0))
