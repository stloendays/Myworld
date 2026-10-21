extends Node
## M0/M1 自动化检查（可 headless 运行，退出码 0 = 全部通过）。
##   godot --headless --path . --fixed-fps 60 res://tests/TestRunner.tscn
## 覆盖：脚本可加载、无切场景调用、坐标边界、地形碰撞与高度函数一致、
## QA-01 林道 → 木屋门廊连续步行、QA-02 开门进屋 / 关门 / 再出屋、
## 湖中涉水上限、码头栏杆、地图四边由地形自然封闭（暂时关闭树木碰撞单独验证地形）；
## M2：天气规则与确定性、QA-03 秋季暮色、QA-04 秋夜大雨（室内无降水）、QA-06 四季区分与“只有冬天下雪”、
## 天气过渡、时钟速率、积雪累积；人物：部位与插槽、换装、第一/第三人称、走路摆腿。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const MAX_STEP := 0.5          ## 单个物理帧允许的最大位移（米），超过视为瞬移
const MIN_CLEARANCE := -0.3    ## 脚底低于地形高度函数的容差（米），低于视为穿地

var _results: Array[Dictionary] = []
var _main: Node3D
var _player: FirstPersonController
var _cabin: Node3D
var _track := false
var _last_pos := Vector3.ZERO
var _max_step := 0.0
var _min_clearance := INF
var _path_length := 0.0
var _max_leg_swing := 0.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== Dusk Lake M0/M1 自动检查 · Godot %s ===" % Engine.get_version_info()["string"])
	_test_scripts_load()
	_test_no_scene_switching()
	_test_layout_bounds()
	_test_licenses_cover_imports()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	await _frames(10)
	_player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	_cabin = _main.get_node("Cabin")
	_test_structure()
	_test_heightmap_alignment()
	await _test_spawn_settles()
	await _test_qa01()
	await _test_qa02()
	await _test_wade_limit()
	await _test_dock_rails()
	await _test_map_edges()
	_test_climate_rules()
	await _test_climate_runtime()
	await _test_character()
	_report()


# ---------------------------------------------------------------- 静态检查

func _test_scripts_load() -> void:
	var bad := PackedStringArray()
	var files := _list_files("res://scripts", ".gd")
	for f in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			bad.append(f)
	_check("脚本全部可加载（%d 个）" % files.size(), bad.is_empty(), ", ".join(bad))


func _test_no_scene_switching() -> void:
	var hits := PackedStringArray()
	for f in _list_files("res://scripts", ".gd"):
		var text := FileAccess.get_file_as_string(f)
		if text.contains("change_scene_to"):
			hits.append(f)
	_check("全工程未调用 change_scene_to_*（室内外同一场景）", hits.is_empty(), ", ".join(hits))


func _test_layout_bounds() -> void:
	var mn := WorldLayout.world_min()
	var mx := WorldLayout.world_max()
	var out := PackedStringArray()
	var pts: Array[Vector2] = []
	for key in ["lake", "cabin"]:
		pts.append(WorldLayout.v2(WorldLayout.section(key)["center"]))
	for z in WorldLayout.zones():
		pts.append(WorldLayout.v2(z["center"]))
	for poly in WorldLayout.path_polylines():
		for p in poly:
			pts.append(p)
	for p in pts:
		if p.x < mn or p.x > mx or p.y < mn or p.y > mx:
			out.append(str(p))
	_check("布局坐标全部位于 X/Z ∈ [%d, %d]（%d 个点）" % [mn, mx, pts.size()], out.is_empty(), ", ".join(out))
	var c := WorldLayout.v2(WorldLayout.section("cabin")["center"])
	_check("木屋中心坐标 = (-69, 37)", c == Vector2(-69, 37), str(c))


## QA-10（提前）：assets/imported 下每个外部文件都必须被 assets/licenses.csv 的某一行覆盖（按路径前缀）。
func _test_licenses_cover_imports() -> void:
	var prefixes := PackedStringArray()
	var f := FileAccess.open("res://assets/licenses.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 1 and row[1] != "":
			prefixes.append(row[1])
	var missing := PackedStringArray()
	var files := _list_files("res://assets/imported", "")
	var counted := 0
	for path in files:
		if path.get_extension() in ["import", "uid", "gitkeep"]:
			continue
		counted += 1
		var rel := path.trim_prefix("res://")
		var covered := false
		for p in prefixes:
			if rel.begins_with(p):
				covered = true
				break
		if not covered:
			missing.append(rel)
	_check("QA-10 素材许可登记覆盖全部导入文件（%d 个）" % counted, missing.is_empty() and counted > 0, ", ".join(missing))


func _test_structure() -> void:
	var names := PackedStringArray()
	for child in _main.get_children():
		names.append(child.name)
	var ok := _main.has_node("World") and _main.has_node("Cabin") and _main.has_node("Player")
	_check("Main 同时常驻 World / Cabin / Player", ok, ", ".join(names))
	var forest := _main.get_node("World/Forest") as ForestBuilder
	var cover := _main.get_node("World/GroundCover") as GroundCoverBuilder
	_check("森林与地被已生成", forest.tree_count > 500 and cover.instance_count > 1000,
		"树 %d 棵，岩石 %d 块，地被 %d 个" % [forest.tree_count, forest.rock_count, cover.instance_count])
	var door := _cabin.get_node("FrontDoor") as InteractableDoor
	_check("正门 uid = cabin_front_door 且已登记", door != null and WorldState.get_interactable_state(&"cabin_front_door") == "closed",
		WorldState.get_interactable_state(&"cabin_front_door"))
	var p := _cabin.global_position
	_check("木屋位于布局坐标", Vector2(p.x, p.z).distance_to(Vector2(-69, 37)) < 0.01, "%.2f, %.2f, %.2f" % [p.x, p.y, p.z])


func _test_heightmap_alignment() -> void:
	var space := _main.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var worst := 0.0
	var samples := 0
	for i in 400:
		var x := rng.randf_range(-124.0, 124.0)
		var z := rng.randf_range(-124.0, 124.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -50.0, z), PhysicsLayers.TERRAIN)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		samples += 1
		worst = maxf(worst, absf(float(hit.position.y) - WorldTerrain.height_at(x, z)))
	_check("地形碰撞与高度函数一致", samples > 380 and worst < 0.12, "%d 个采样点，最大偏差 %.3f m" % [samples, worst])


# ---------------------------------------------------------------- 行走测试

func _test_spawn_settles() -> void:
	Main.place_at_spawn(_player)
	await _seconds(1.5)
	var p := _player.global_position
	_check("出生点落地稳定（湖岸平台）", _player.is_on_floor() and p.y > 0.5,
		"(%.1f, %.2f, %.1f)，朝向 %.0f°" % [p.x, p.y, p.z, _player.heading_degrees()])


func _test_qa01() -> void:
	var trail := WorldLayout.path_points("trail_north")
	var route: Array[Vector2] = []
	for i in range(2, trail.size()):
		route.append(trail[i])
	route.append(_cabin_xz(11.0, 0.0))
	route.append(_cabin_xz(9.0, 0.0))
	route.append(_cabin_xz(6.6, 0.0))
	await _setup_at(route[0], 0.0)
	_begin_track()
	var reached := true
	for i in range(1, route.size()):
		if not await _walk_to(route[i], 60.0):
			reached = false
			break
	_track = false
	var p := _player.global_position
	_check("QA-01 北部针叶林步道 → 木屋门廊，连续步行无卡死/穿地/瞬移",
		reached and _max_step < MAX_STEP and _min_clearance > MIN_CLEARANCE,
		"起点 (%.0f, %.0f) → 终点 (%.1f, %.2f, %.1f)，路程 %.0f m，单帧最大位移 %.3f m，最低离地 %.2f m" %
		[route[0].x, route[0].y, p.x, p.y, p.z, _path_length, _max_step, _min_clearance])
	_check("人物走路时摆臂摆腿", _max_leg_swing > 15.0, "QA-01 途中腿部最大摆角 %.1f°" % _max_leg_swing)


func _test_qa02() -> void:
	var door := _cabin.get_node("FrontDoor") as InteractableDoor
	var main_id := _main.get_instance_id()
	var scene_before := get_tree().current_scene
	_begin_track()
	var notes := PackedStringArray()

	_player.look_at_point(_cabin.to_global(Vector3(5.0, 1.3, 0.0)))
	await _frames(2)
	notes.append("门外射线：%s" % _ray_info())
	var opened := _player.try_interact()
	await _seconds(1.0)
	notes.append("门外按 E：%s → %s" % [opened, door.get_state()])
	var inside_ok := await _walk_to(_cabin_xz(2.8, 0.0), 20.0)
	await _frames(10)
	var indoors_after_enter := WorldState.is_indoors(_player.entity_id)
	notes.append("进屋后区域：%s" % ", ".join(PackedStringArray(WorldState.zones_of(_player.entity_id))))

	var hinge := _cabin.to_global(Vector3(5.0, 0.0, -0.6))
	var leaf_dir := _cabin.global_basis * Vector3(sin(deg_to_rad(door.open_angle_deg)), 0.0, cos(deg_to_rad(door.open_angle_deg)))
	_player.look_at_point(hinge + leaf_dir * 0.6 + Vector3(0.0, 1.3, 0.0))
	await _frames(2)
	notes.append("屋内射线：%s" % _ray_info())
	var closed := _player.try_interact()
	await _seconds(1.2)
	var closed_state := door.get_state()
	var still_inside := WorldState.is_indoors(_player.entity_id)
	notes.append("屋内关门：%s" % closed_state)

	_player.look_at_point(_cabin.to_global(Vector3(5.0, 1.3, 0.0)))
	await _frames(2)
	var reopened := _player.try_interact()
	await _seconds(1.0)
	var out_ok := true
	for local_x in [6.6, 10.5, 14.0]:
		if not await _walk_to(_cabin_xz(local_x, 0.0), 20.0):
			out_ok = false
	await _frames(10)
	var outdoors_after_exit := not WorldState.is_indoors(_player.entity_id)
	_track = false

	var same_scene := is_instance_valid(_main) and _main.get_instance_id() == main_id and get_tree().current_scene == scene_before
	var ok := opened and inside_ok and indoors_after_enter and closed and closed_state == "closed" and still_inside \
		and reopened and out_ok and outdoors_after_exit and same_scene and _max_step < MAX_STEP
	_check("QA-02 门外开门 → 进屋 → 屋内关门 → 再开门出屋，位置连续、场景未重载", ok,
		"%s；单帧最大位移 %.3f m；Main 实例未变 = %s" % ["；".join(notes), _max_step, same_scene])


func _test_wade_limit() -> void:
	var limit := -float(WorldLayout.section("lake")["wade_limit_depth"])
	await _setup_at(Vector2(-46.0, 18.0), 0.0)
	_begin_track()
	await _walk_for(Vector3(1.0, 0.0, -0.15), 14.0)
	_track = false
	var p := _player.global_position
	var reached_water := p.y < WorldLayout.water_level()
	_check("湖中只能涉水到深 %.1f m（MVP 不可深水游泳）" % -limit, reached_water and p.y > limit - 0.25,
		"向湖心走 14 s 后停在 (%.1f, %.2f, %.1f)" % [p.x, p.y, p.z])


func _test_dock_rails() -> void:
	var dock := WorldLayout.section("dock")
	var a := WorldLayout.v2(dock["from"])
	var b := WorldLayout.v2(dock["to"])
	var top := float(dock["deck_height"])
	await _setup_at(Vector2(a.x + 1.0, a.y), 0.0)
	_begin_track()
	var walked := await _walk_to(Vector2(-12.0, a.y), 30.0)
	await _walk_for(Vector3(0.0, 0.0, -1.0), 3.0)
	var side := _player.global_position
	await _walk_to(Vector2(b.x - 1.0, a.y), 20.0)
	await _walk_for(Vector3(1.0, 0.0, 0.0), 3.0)
	var tip := _player.global_position
	_track = false
	var ok := walked and side.y > top - 0.05 and absf(side.z - a.y) < float(dock["width"]) * 0.5 \
		and tip.y > top - 0.05 and tip.x < b.x
	_check("码头可走到尽头，侧面与末端栏杆挡住落水", ok,
		"侧推后 (%.1f, %.2f, %.1f)，末端推后 (%.1f, %.2f, %.1f)" % [side.x, side.y, side.z, tip.x, tip.y, tip.z])


func _test_map_edges() -> void:
	var forest := _main.get_node("World/Forest") as ForestBuilder
	forest.set_collision_enabled(false)
	var starts := [[Vector2(0, 95), Vector3(0, 0, 1)], [Vector2(-95, 0), Vector3(-1, 0, 0)],
		[Vector2(0, -95), Vector3(0, 0, -1)], [Vector2(100, 60), Vector3(1, 0, 0)]]
	var mx := WorldLayout.world_max()
	var details := PackedStringArray()
	var ok := true
	for s in starts:
		await _setup_at(s[0], 0.0)
		_begin_track()
		await _walk_for(s[1], 25.0)
		_track = false
		var p := _player.global_position
		var reach := maxf(absf(p.x), absf(p.z))
		ok = ok and reach < mx - 2.0 and _min_clearance > MIN_CLEARANCE and _max_step < MAX_STEP
		details.append("%s→ 停在 |%.1f|" % [str(s[1]), reach])
	forest.set_collision_enabled(true)
	_check("QA-01 地图四边由陡坡自然封闭（不靠空气墙，已临时关闭树木碰撞）", ok, "；".join(details))


# ---------------------------------------------------------------- M2 天气与季节

func _test_climate_rules() -> void:
	var bad := PackedStringArray()
	var missing := PackedStringArray()
	for season in ClimateData.season_order():
		var seen := {}
		for i in 400:
			var w := WeatherController.pick(StringName(season), 1234, i)
			seen[w] = true
			if not ClimateData.is_allowed(StringName(season), w):
				bad.append("%s→%s" % [season, w])
		for w in ClimateData.WEATHER_IDS:
			if ClimateData.is_allowed(StringName(season), w) and not seen.has(w):
				missing.append("%s 未出现 %s" % [season, w])
	_check("自动天气只在允许的季节出现（每季抽 400 次）", bad.is_empty() and missing.is_empty(), ", ".join(bad + missing))
	var a := PackedStringArray()
	var b := PackedStringArray()
	var c := PackedStringArray()
	for i in 30:
		a.append(String(WeatherController.pick(&"AUTUMN", 777, i)))
		b.append(String(WeatherController.pick(&"AUTUMN", 777, i)))
		c.append(String(WeatherController.pick(&"AUTUMN", 778, i)))
	_check("天气序列由种子决定（读档不会变天）", a == b and a != c, "种子 777 前 6 次：" + ", ".join(a.slice(0, 6)))


func _test_climate_runtime() -> void:
	var climate := _main.get_node("Systems") as ClimateSystem
	var env := _main.get_node("World/Environment") as EnvironmentDirector
	var precip := _main.get_node("World/Precipitation") as Precipitation
	_player.global_position = _cabin.to_global(Vector3(10.5, 0.2, 0.0))
	await _frames(3)

	climate.apply_preset("Autumn_Dusk_Clear")
	await _frames(3)
	_check("QA-03 秋季 17:20 晴：低角度暮光、太阳在湖对岸",
		WorldState.season_id == &"AUTUMN" and WorldState.weather_id == &"CLEAR" and env.sun_elevation > 8.0 and env.sun_elevation < 13.0
		and env.sun_azimuth > 55.0 and env.sun_azimuth < 70.0 and not precip.rain.emitting,
		"太阳高度 %.1f°、方位 %.0f°，雨 %s" % [env.sun_elevation, env.sun_azimuth, precip.rain.emitting])

	climate.apply_preset("Autumn_Night_HeavyRain")
	await _frames(10)
	var space := _main.get_world_3d().direct_space_state
	var inside := _cabin.to_global(Vector3(1.0, 1.5, 0.0))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(inside, inside + Vector3(0.0, 30.0, 0.0), PhysicsLayers.WORLD))
	var roofed: bool = not hit.is_empty() and _cabin.is_ancestor_of(hit["collider"])
	_check("QA-04 秋夜大雨：降雨开启、室内被屋顶遮住、雨粒子碰到屋顶即消失",
		env.night > 0.9 and precip.rain.emitting and precip.rain.amount_ratio > 0.95 and not precip.snow.emitting
		and precip.heightfield.follow_camera_enabled and roofed
		and (precip.rain.process_material as ParticleProcessMaterial).collision_mode == ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
		and float(WeatherController.blended()["rain"]) > 0.95 and WorldState.ground_wetness > 0.95,
		"夜 %.2f，雨量 %.2f，室内向上射线命中 %s" % [env.night, precip.rain.amount_ratio, hit.get("collider", null)])

	var forest := _main.get_node("World/Forest") as ForestBuilder
	var pine := _first_mmi(forest, "pine")
	var broad := _first_mmi(forest, "broadleaf")
	var samples := {}
	var meshes := {}
	var rules := PackedStringArray()
	for season in ClimateData.season_order():
		climate.jump_to_season(StringName(season))
		await _frames(3)
		samples[season] = pine.multimesh.get_meta("tint_sample", Color.BLACK)
		meshes[season] = broad.multimesh.mesh
		var snow_ok := climate.set_weather(&"SNOW", 0.0)
		var rain_ok := climate.set_weather(&"LIGHT_RAIN", 0.0)
		if snow_ok != (season == "WINTER") or rain_ok == (season == "WINTER"):
			rules.append("%s 雪=%s 雨=%s" % [season, snow_ok, rain_ok])
	var distinct := {}
	for s in samples.values():
		distinct[(s as Color).to_html()] = true
	_check("QA-06 四季植被可区分、只有冬季能下雪、冬季不下雨",
		distinct.size() == 4 and meshes["SUMMER"] != meshes["AUTUMN"] and rules.is_empty(),
		"针叶色 %d 种，阔叶夏/秋模型不同 = %s %s" % [distinct.size(), meshes["SUMMER"] != meshes["AUTUMN"], ", ".join(rules)])

	climate.apply_preset("Winter_Morning_Snow")
	climate.jump_to_season(&"SPRING")
	await _frames(2)
	_check("换季时不合法的天气自动过渡（冬雪 → 春）", ClimateData.is_allowed(&"SPRING", WorldState.weather_id),
		"%s → %s" % [WorldState.weather_from, WorldState.weather_id])

	climate.apply_preset("Autumn_Dusk_Clear")
	var started := []
	var changed := []
	var on_start := func(f: StringName, t: StringName, d: float) -> void: started.append([f, t, d])
	var on_change := func(id: StringName) -> void: changed.append(id)
	EventBus.weather_transition_started.connect(on_start)
	EventBus.weather_changed.connect(on_change)
	climate.set_weather(&"LIGHT_RAIN", 1.0)
	await _seconds(0.5)
	var mid := WorldState.weather_progress
	var mid_rain := float(WeatherController.blended()["rain"])
	await _seconds(1.0)
	EventBus.weather_transition_started.disconnect(on_start)
	EventBus.weather_changed.disconnect(on_change)
	_check("天气平滑过渡：先发 transition_started，进度到 1 再发 weather_changed",
		started.size() == 1 and mid > 0.3 and mid < 0.7 and mid_rain > 0.02 and mid_rain < 0.34 and changed == [&"LIGHT_RAIN"],
		"过渡一半时进度 %.2f、雨量 %.2f；完成后 %s" % [mid, mid_rain, changed])

	var t0 := WorldState.absolute_minutes()
	await _seconds(10.0)
	var dt := WorldState.absolute_minutes() - t0
	_check("世界时钟：现实 10 秒 = 游戏 5 分钟（一天 = 现实 48 分钟）", absf(dt - 5.0) < 0.2, "实测 %.2f 游戏分钟" % dt)

	climate.apply_preset("Winter_Morning_Snow")
	WorldState.ground_snow = 0.0
	WorldState.time_scale = 60.0
	await _seconds(2.0)
	WorldState.time_scale = 1.0
	var snow := WorldState.ground_snow
	_check("下雪时地面积雪逐渐增加", snow > 0.3 and snow < 0.8, "下雪 1 游戏小时后积雪 %.2f" % snow)
	climate.apply_preset("Autumn_Dusk_Clear")
	await _frames(3)


func _first_mmi(forest: ForestBuilder, kind: String) -> MultiMeshInstance3D:
	for child in forest.get_node("Generated").get_children():
		if child is MultiMeshInstance3D and child.get_meta("kind", "") == kind:
			return child
	return null


# ---------------------------------------------------------------- 人物

func _test_character() -> void:
	var body := _player.body
	var missing := PackedStringArray()
	for part in CharacterModel.PART_ORDER:
		for slot in Wardrobe.slot_order():
			if body.slot_node(part, slot) == null:
				missing.append("%s/%s" % [part, slot])
	for socket_name in CharacterModel.SOCKETS:
		if body.get_socket(socket_name) == null:
			missing.append("socket " + socket_name)
	_check("人物 6 个部位 × 7 个外观插槽与 4 个挂点齐全", missing.is_empty(), ", ".join(missing))

	var a := PlayerProfile.appearance
	var saved := a.to_dict()
	a.set_style("hair", "long")
	a.set_style("back", "backpack")
	a.set_style("hat", "beanie")
	await _frames(1)
	var long_hair := _slot_mesh(body, "torso", "hair") != null
	var backpack := _slot_mesh(body, "torso", "back") != null
	var hat := _slot_mesh(body, "head", "hat") != null
	a.set_style("hair", "none")
	a.set_style("back", "none")
	a.set_style("hat", "none")
	await _frames(1)
	var cleared := _slot_mesh(body, "head", "hair") == null and _slot_mesh(body, "torso", "back") == null
	a.assign(CharacterAppearance.from_dict(saved))
	_check("换装：发型、帽子、背包切换后对应插槽即时重建", long_hair and backpack and hat and cleared,
		"长发 %s，背包 %s，帽子 %s，清空 %s" % [long_hair, backpack, hat, cleared])

	var fp_hidden := (_player.camera.cull_mask & FirstPersonController.BODY_LAYER) == 0
	_player.set_third_person(true)
	await _seconds(1.0)
	var tp_len := _player.camera_boom.get_hit_length()
	var tp_visible := (_player.camera.cull_mask & FirstPersonController.BODY_LAYER) != 0
	_player.set_third_person(false)
	await _seconds(1.0)
	_check("V 切换视角：第一人称不画自己（只投影子），第三人称相机退到身后", fp_hidden and tp_visible and tp_len > 1.0,
		"第三人称相机距离 %.2f m" % tp_len)


func _slot_mesh(body: CharacterModel, part: String, slot: String) -> Mesh:
	var holder := body.slot_node(part, slot)
	var mi := holder.get_node_or_null("Mesh") as MeshInstance3D if holder != null else null
	return mi.mesh if mi != null else null

# ---------------------------------------------------------------- 工具

func _physics_process(_delta: float) -> void:
	if not _track or _player == null:
		return
	var p := _player.global_position
	var step := p.distance_to(_last_pos)
	_max_step = maxf(_max_step, step)
	_path_length += step
	_last_pos = p
	_min_clearance = minf(_min_clearance, p.y - WorldTerrain.height_at(p.x, p.z))
	_max_leg_swing = maxf(_max_leg_swing, _player.body.leg_swing_degrees())


func _begin_track() -> void:
	_last_pos = _player.global_position
	_max_step = 0.0
	_min_clearance = INF
	_path_length = 0.0
	_max_leg_swing = 0.0
	_track = true


func _setup_at(xz: Vector2, yaw: float) -> void:
	_track = false
	_player.autopilot_enabled = false
	_player.global_position = Vector3(xz.x, WorldTerrain.height_at(xz.x, xz.y) + 0.3, xz.y)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = yaw
	await _seconds(0.6)


func _walk_to(target: Vector2, timeout_s: float) -> bool:
	_player.autopilot_enabled = true
	var limit := int(timeout_s * Engine.physics_ticks_per_second)
	var frames := 0
	var arrived := false
	while frames < limit:
		var p := Vector2(_player.global_position.x, _player.global_position.z)
		var to := target - p
		if to.length() < 0.35:
			arrived = true
			break
		_player.autopilot_direction = Vector3(to.x, 0.0, to.y)
		_player.autopilot_run = to.length() > 2.5
		await get_tree().physics_frame
		frames += 1
	_player.autopilot_direction = Vector3.ZERO
	await _frames(15)
	_player.autopilot_enabled = false
	return arrived


func _walk_for(direction: Vector3, seconds: float) -> void:
	_player.autopilot_enabled = true
	_player.autopilot_direction = direction
	_player.autopilot_run = false
	await _seconds(seconds)
	_player.autopilot_direction = Vector3.ZERO
	await _frames(15)
	_player.autopilot_enabled = false


func _ray_info() -> String:
	var ray := _player.interact_ray
	ray.force_raycast_update()
	var p := _player.global_position
	if not ray.is_colliding():
		return "未命中（玩家 %.2f, %.2f, %.2f）" % [p.x, p.y, p.z]
	var c := ray.get_collider() as Node
	return "%s @ %s（玩家 %.2f, %.2f, %.2f）" % [c.get_path(), str(ray.get_collision_point()), p.x, p.y, p.z]


func _cabin_xz(local_x: float, local_z: float) -> Vector2:
	var p := _cabin.to_global(Vector3(local_x, 0.0, local_z))
	return Vector2(p.x, p.z)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * Engine.physics_ticks_per_second))


func _check(name: String, ok: bool, detail := "") -> void:
	_results.append({"name": name, "ok": ok, "detail": detail})
	print(("[PASS] " if ok else "[FAIL] ") + name + ("  —  " + detail if detail != "" else ""))


func _list_files(dir_path: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(ext):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_list_files(dir_path.path_join(d), ext))
	return out


func _report() -> void:
	var failed := 0
	for r in _results:
		if not r["ok"]:
			failed += 1
	print("=== 结果：%d 项通过，%d 项失败 ===" % [_results.size() - failed, failed])
	var f := FileAccess.open("user://last_test_results.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_results, "  "))
	get_tree().quit(1 if failed > 0 else 0)
