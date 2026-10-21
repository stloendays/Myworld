extends Node
## M0/M1 自动化检查（可 headless 运行，退出码 0 = 全部通过）。
##   godot --headless --path . --fixed-fps 60 res://tests/TestRunner.tscn
## 覆盖：脚本可加载、无切场景调用、坐标边界、地形碰撞与高度函数一致、
## QA-01 林道 → 木屋门廊连续步行、QA-02 开门进屋 / 关门 / 再出屋、
## 湖中涉水上限、码头栏杆、地图四边由地形自然封闭（暂时关闭树木碰撞单独验证地形）；
## M2：天气规则与确定性、QA-03 秋季暮色、QA-04 秋夜大雨（室内无降水）、QA-06 四季区分与“只有冬天下雪”、
## 天气过渡、时钟速率、积雪累积；人物：部位与插槽、换装、第一/第三人称、走路摆腿。
## 泳池馆：开门进馆 → 楼梯下到水族馆；泳池漂浮 → 池底洞口 → 玻璃水管 → 下潜池 → 坡道上岸；深水区爬上岸；
## 小动物：数量与 id、季节/昼夜/天气规则、兔子见人就跑、鱼不出缸；雷暴闪电、彩虹、大风、落叶。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const MAX_STEP := 0.5          ## 单个物理帧允许的最大位移（米），超过视为瞬移
const MIN_CLEARANCE := -0.3    ## 脚底低于地形高度函数的容差（米），低于视为穿地

var _results: Array[Dictionary] = []
var _main: Node3D
var _player: FirstPersonController
var _cabin: Node3D
var _house: PoolHouse
var _track := false
var _last_pos := Vector3.ZERO
var _max_step := 0.0
var _min_clearance := INF
var _path_length := 0.0
var _max_leg_swing := 0.0
var _waters_seen := {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== Dusk Lake M0/M1 自动检查 · Godot %s ===" % Engine.get_version_info()["string"])
	# 不受本机 user://settings.json 影响：测试一律从默认设置开始
	GameSettings.reset_defaults()
	_test_scripts_load()
	_test_no_scene_switching()
	_test_layout_bounds()
	_test_licenses_cover_imports()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	await _frames(10)
	_player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	_cabin = _main.get_node("Cabin")
	_house = _main.get_node("PoolHouse") as PoolHouse
	# 调试单项：DUSK_TEST_ONLY=_test_xxx（逗号分隔可多项）只跑这些，不跑全套（全套约 8 分钟）
	var only := OS.get_environment("DUSK_TEST_ONLY")
	if only != "":
		for test_name in only.split(","):
			await call(test_name.strip_edges())
		_report()
		return
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
	_house = _main.get_node("PoolHouse") as PoolHouse
	_test_signs()
	await _test_poolhouse_walk()
	await _test_poolhouse_swim()
	await _test_pool_climb_out()
	await _test_fauna()
	await _test_storm_rainbow_leaves()
	await _test_first_person_arms()
	await _test_settings()
	await _test_minimap()
	await _test_developer_mode()
	await _test_cabin_life()
	await _test_sleep()
	await _test_canoe()
	await _test_exploration_save()
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
		if _near_pit_edge(x, z):
			continue   # 基坑边缘 1 m 网格内是陡坎（在建筑台基下面），解析高度与三角面插值本来就不同
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


# ---------------------------------------------------------------- 第一人称的手、设置、小地图、开发者模式

func _test_first_person_arms() -> void:
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
	_player.set_third_person(false)
	var arms := _player.arms
	await _frames(5)
	var meshes := arms.model.find_children("*", "MeshInstance3D", true, false)
	var layers_ok := not meshes.is_empty()
	for mi: MeshInstance3D in meshes:
		layers_ok = layers_ok and mi.layers == FirstPersonArms.FP_ARMS_LAYER and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mi.material_override != null
	var cam := _player.camera
	var fp_mask_ok := (cam.cull_mask & FirstPersonArms.FP_ARMS_LAYER) != 0 and (cam.cull_mask & FirstPersonController.BODY_LAYER) == 0
	# 两只手（手臂末端）都在画面里，而且离相机不到 0.35 m（在碰撞体以内，贴墙不会插进墙里）
	var hands_ok := true
	var hand_detail := PackedStringArray()
	for part in ["arm_r", "arm_l"]:
		var pivot := arms.model.parts[part] as Node3D
		var hand := pivot.to_global(Vector3(0.0, -10.0 * Wardrobe.px(), 0.0))
		var dist := hand.distance_to(cam.global_position)
		# 按游戏的 16:9 画面算（无窗口测试的视口只有 64×64，不能直接用 is_position_in_frustum）
		var local := cam.global_transform.affine_inverse() * hand
		var tan_v := tan(deg_to_rad(cam.fov * 0.5))
		var seen := local.z < 0.0 and absf(local.y / local.z) < tan_v and absf(local.x / local.z) < tan_v * 16.0 / 9.0
		hand_detail.append("%s 手端距相机 %.2f m，在画面内 %s" % [part, dist, seen])
		hands_ok = hands_ok and seen and dist < 0.35 and pivot.visible
	var right_ok: bool = arms.model.parts["arm_r"].visible
	_player.set_third_person(true)
	await _frames(3)
	var tp_ok := not arms.visible and (cam.cull_mask & FirstPersonArms.FP_ARMS_LAYER) == 0
	_player.set_third_person(false)
	# 换上衣后袖子跟着变，手臂仍是专用材质
	var a := PlayerProfile.appearance
	var old_top := a.style("top")
	a.set_style("top", "jacket" if old_top != "jacket" else "tee")
	await _frames(3)
	var restyled := true
	for mi: MeshInstance3D in arms.model.find_children("*", "MeshInstance3D", true, false):
		restyled = restyled and mi.layers == FirstPersonArms.FP_ARMS_LAYER and mi.material_override != null
	a.set_style("top", old_top)
	await _frames(2)
	_check("第一人称看得到双手：手在画面内且在碰撞体以内，第三人称不画，换衣服袖子跟着变",
		layers_ok and fp_mask_ok and hands_ok and right_ok and tp_ok and restyled,
		"%s；第三人称隐藏 %s；换装后仍正确 %s" % ["；".join(hand_detail), tp_ok, restyled])


func _test_settings() -> void:
	var path := "user://test_settings_roundtrip.json"
	GameSettings.set_value("fov", 200.0, false)
	var clamped := GameSettings.fov == GameSettings.FOV_MAX
	GameSettings.set_value("third_person_distance", 5.0, false)
	GameSettings.set_value("shoulder_left", true, false)
	GameSettings.set_value("first_person_arms", "right", false)
	GameSettings.set_value("minimap_range", 90.0, false)
	GameSettings.set_value("view_bob", false, false)
	await _frames(2)
	var applied: bool = absf(_player.third_person_distance - 5.0) < 0.001 and _player.third_person_offset.x < 0.0 \
		and _player.arms.model.parts["arm_r"].visible and not _player.arms.model.parts["arm_l"].visible
	var saved := GameSettings.to_dict()
	GameSettings.save_to(path)
	GameSettings.reset_defaults()
	var reset_ok := GameSettings.fov == 75.0 and not GameSettings.shoulder_left
	GameSettings.load_from(path)
	var roundtrip := GameSettings.to_dict() == saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameSettings.reset_defaults()
	await _frames(2)
	_check("设置：限幅、立即生效（第三人称距离/肩位/手的显示）、保存后读回一致、恢复默认",
		clamped and applied and reset_ok and roundtrip and _player.arms.model.parts["arm_l"].visible,
		"FOV 限幅 %s，生效 %s，恢复默认 %s，读回一致 %s" % [clamped, applied, reset_ok, roundtrip])


func _test_minimap() -> void:
	var mm := _main.get_node("Minimap") as Minimap
	for i in 600:
		if mm.is_ready():
			break
		await get_tree().process_frame
	var img := mm.map_texture.get_image() if mm.is_ready() else null
	var colors_ok := false
	if img != null:
		var lake := _map_pixel(mm, img, Vector2(70.0, 20.0))
		var forest := _map_pixel(mm, img, Vector2(-85.0, -70.0))
		colors_ok = lake.b > lake.r + 0.15 and forest.g > forest.b and forest.g > forest.r
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
	var center := Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5
	var k := Minimap.SIZE * 0.5 / GameSettings.minimap_range
	var p := Vector2(_player.global_position.x, _player.global_position.z)
	GameSettings.set_value("minimap_rotate", false, false)
	var north_up := mm.world_to_map() * (p + Vector2(0.0, -10.0))
	var north_ok := north_up.distance_to(center + Vector2(0.0, -10.0 * k)) < 0.5
	GameSettings.set_value("minimap_rotate", true, false)
	_player.rotation.y = -PI * 0.5   # 朝东
	var east_up := mm.world_to_map() * (p + Vector2(10.0, 0.0))
	var rotate_ok := east_up.distance_to(center + Vector2(0.0, -10.0 * k)) < 0.5
	_player.rotation.y = 0.0
	GameSettings.set_value("minimap_enabled", false, false)
	var hidden := not (mm.get_node("MinimapRoot") as Control).visible
	GameSettings.set_value("minimap_enabled", true, false)
	var shown := (mm.get_node("MinimapRoot") as Control).visible
	_check("小地图：底图烘焙完成（湖是蓝的、林子是绿的），玩家在圆心，北朝上/随朝向旋转都对，可以关掉",
		mm.is_ready() and colors_ok and north_ok and rotate_ok and hidden and shown,
		"底图 %s，颜色 %s，北朝上 %s，旋转 %s，关闭 %s / 打开 %s" % [mm.is_ready(), colors_ok, north_ok, rotate_ok, hidden, shown])


func _map_pixel(mm: Minimap, img: Image, world: Vector2) -> Color:
	var uv := (world - mm.world_rect.position) / mm.world_rect.size
	return img.get_pixel(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))


func _test_developer_mode() -> void:
	var panel := _main.get_node("DevPanel")
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
	var mask := _player.collision_mask
	_press("toggle_fly")
	await _frames(2)
	var locked: bool = not _player.flying and not panel.is_open()
	GameSettings.set_developer_mode(true)
	await _frames(2)
	var panel_open: bool = panel.is_open()
	_press("toggle_fly")
	await _frames(2)
	var flying := _player.flying
	var y0 := _player.global_position.y
	_player.autopilot_enabled = true
	_player.autopilot_direction = Vector3.UP
	await _seconds(1.5)
	var climbed := _player.global_position.y - y0
	_player.autopilot_direction = Vector3.ZERO
	await _seconds(0.5)
	var y1 := _player.global_position.y
	await _seconds(1.0)
	var hover := absf(_player.global_position.y - y1)
	_player.autopilot_enabled = false

	# 穿墙：从门廊朝木屋正立面玻璃飞，关着穿墙被挡住，开着能穿过去
	var start := _cabin.to_global(Vector3(7.0, 1.6, 2.5))
	_player.teleport_to(start)
	_player.autopilot_enabled = true
	_player.autopilot_direction = _cabin.global_basis * Vector3(-1.0, 0.0, 0.0)
	await _seconds(2.0)
	var blocked_x := _cabin.to_local(_player.global_position).x
	_press("toggle_noclip")
	await _seconds(2.0)
	var through_x := _cabin.to_local(_player.global_position).x
	_player.autopilot_direction = Vector3.ZERO
	await _frames(10)
	_player.autopilot_enabled = false
	var noclip_ok := blocked_x > 4.6 and through_x < 3.0

	# 传送到每个地点，站稳（不掉下去）
	var spots: Array = WorldLayout.data().get("dev_spots", [])
	var bad := PackedStringArray()
	for i in spots.size():
		_player.set_flying(false)
		panel.teleport(i)
		await _seconds(1.0)
		var want: Vector3 = panel.spot_position(spots[i])
		var got := _player.global_position
		if got.distance_to(want) > 1.2 or (spots[i].get("fly", false) and not _player.flying):
			bad.append("%s 目标 %s 实际 %s" % [spots[i]["name"], str(want), str(got)])
	GameSettings.set_developer_mode(false)
	await _seconds(2.5)
	var landed: bool = not _player.flying and not _player.noclip and _player.collision_mask == mask and not panel.is_open()
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
	_check("开发者模式：普通模式不能飞；F2 打开面板，F 飞行（上升、悬停）、N 穿墙；各传送点能到；退出后恢复碰撞并落地",
		locked and panel_open and flying and climbed > 5.0 and hover < 0.3 and noclip_ok and bad.is_empty() and landed,
		"普通模式锁定 %s，面板 %s，1.5 s 上升 %.1f m，悬停漂移 %.2f m，穿墙前 x=%.1f / 穿墙后 x=%.1f，传送 %d 处%s，退出后 %s" % [
			locked, panel_open, climbed, hover, blocked_x, through_x, spots.size(), ("，失败：" + "；".join(bad)) if not bad.is_empty() else "全部到达", landed])


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


# ---------------------------------------------------------------- 木屋生活、独木舟、探索

func _cabin_point(local: Vector3) -> Vector3:
	return _cabin.to_global(local)


func _test_cabin_life() -> void:
	var life := _cabin.get_node("Generated/Life") as CabinLife
	var notes := PackedStringArray()
	_player.set_third_person(false)
	_player.teleport_to(_cabin_point(Vector3(-2.4, 0.05, -1.0)))
	await _seconds(0.5)
	# 铸铁炉：看着它按 E 熄火、再按 E 生火
	_player.look_at_point(_cabin_point(Vector3(-3.9, 0.7, -1.0)))
	await _frames(2)
	var off_ok := _player.try_interact() and WorldState.get_interactable_state(&"cabin_stove") == "off" \
		and not life.light_on("stove") and not life._fire.emitting and not life._smoke.emitting
	var on_ok := _player.try_interact() and WorldState.get_interactable_state(&"cabin_stove") == "on" \
		and life.light_on("stove") and life._fire.emitting and life._smoke.emitting
	notes.append("炉子熄火 %s / 生火 %s" % [off_ok, on_ok])
	# 落地灯：走到茶几旁看着它按 E
	_player.teleport_to(_cabin_point(Vector3(2.6, 0.05, 1.0)))
	await _seconds(0.4)
	_player.look_at_point(_cabin_point(Vector3(2.35, 1.2, 2.6)))
	await _frames(2)
	var lamp_ok := _player.try_interact() and WorldState.get_interactable_state(&"cabin_floor_lamp") == "off" and not life.light_on("floor_lamp")
	_player.try_interact()
	lamp_ok = lamp_ok and life.light_on("floor_lamp")
	notes.append("落地灯 %s" % lamp_ok)
	# 墙上开关：门边的吊灯开关
	_player.teleport_to(_cabin_point(Vector3(3.8, 0.05, -0.9)))
	await _seconds(0.4)
	_player.look_at_point(_cabin_point(Vector3(4.86, 1.25, -0.95)))
	await _frames(2)
	var switch_ok := _player.try_interact() and not life.light_on("ceiling")
	_player.try_interact()
	switch_ok = switch_ok and life.light_on("ceiling")
	notes.append("吊灯开关 %s" % switch_ok)
	# 沙发：看着坐垫按 E 坐下，按 E 站起；再坐下后用移动键站起
	_player.teleport_to(_cabin_point(Vector3(1.4, 0.05, 0.9)))
	await _seconds(0.4)
	var sofa := _cabin.get_node("Generated/Life/Seat_cabin_sofa_left") as Seat
	_player.look_at_point(sofa.global_position + Vector3(0.0, 0.2, 0.0))
	await _frames(2)
	var sat := _player.try_interact() and _player.seat == sofa and _player.body.pose == "sit"
	await _seconds(0.5)
	var held := _player.global_position.distance_to(sofa.occupant_origin()) < 0.05 and _player.collision_mask == 0
	var stood := _player.try_interact() and _player.seat == null and _player.body.pose == "stand"
	await _seconds(0.8)
	var floor_ok := _player.is_on_floor() and absf(_player.global_position.y - _cabin.global_position.y) < 0.15
	sofa.interact(_player)
	_player.autopilot_enabled = true
	_player.autopilot_direction = -_cabin.global_basis.z
	await _frames(3)
	_player.autopilot_direction = Vector3.ZERO
	_player.autopilot_enabled = false
	var move_stand := _player.seat == null
	notes.append("坐下 %s，定在座位上 %s，E 站起 %s，落地 %s，移动键站起 %s" % [sat, held, stood, floor_ok, move_stand])
	_check("木屋生活：炉子生火 / 熄火（火光、火苗、烟囱冒烟），落地灯和墙上开关，沙发坐下 / 站起",
		off_ok and on_ok and lamp_ok and switch_ok and sat and held and stood and floor_ok and move_stand, "；".join(notes))


func _test_sleep() -> void:
	var climate := _main.get_node("Systems") as ClimateSystem
	var bed := _cabin.get_node("Generated/Life/Bed_cabin_bed") as Bed
	climate.set_hour(22.0)
	var day0 := WorldState.world_day
	var hours: float = await bed.sleep(_player, true)
	var night_ok := WorldState.world_day == day0 + 1 and absf(WorldState.time_minutes - 7.0 * 60.0) < 1.0 and absf(hours - 9.0) < 0.01
	var woke := _player.global_position.distance_to(bed.to_global(bed.wake_point)) < 0.1
	climate.set_hour(13.0)
	var nap: float = await bed.sleep(_player, true)
	var nap_ok := absf(nap - 1.0) < 0.01 and absf(WorldState.time_minutes - 14.0 * 60.0) < 1.0
	await _seconds(0.8)
	_check("床：晚上 22:00 睡到第二天 7:00，白天小睡 1 小时，醒来站在床边",
		night_ok and nap_ok and woke and _player.is_on_floor(), "睡 %.1f 小时 → 第 %d 天 %s，小睡 %.1f 小时，醒在床边 %s" % [hours, WorldState.world_day, "07:00" if night_ok else "?", nap, woke])
	climate.set_hour(10.0)


func _test_canoe() -> void:
	var canoe := _main.get_node("World/Dock/Generated/Canoe") as Canoe
	var notes := PackedStringArray()
	var start_xz := canoe.world_position_2d()
	# 从码头上看着船按 E
	_player.teleport_to(Vector3(-28.0, 1.05, 25.2), 180.0)
	await _seconds(2.0)
	var moored := canoe.world_position_2d().distance_to(start_xz) < 0.001   # 没人时系在原地，不随风漂
	_player.look_at_point(canoe.global_position + Vector3(0.0, 0.2, 0.0))
	await _frames(2)
	var boarded := _player.try_interact() and _player.boat == canoe and canoe.rider == _player
	notes.append("无人时不漂 %s，上船 %s" % [moored, boarded])
	# 往东划 10 s
	_player.autopilot_enabled = true
	_player.autopilot_direction = Vector3(1.0, 0.0, 0.0)
	var min_y := INF
	var max_y := -INF
	for i in 600:
		await get_tree().physics_frame
		min_y = minf(min_y, canoe.global_position.y)
		max_y = maxf(max_y, canoe.global_position.y)
	var moved := canoe.world_position_2d().x - start_xz.x
	var follows := _player.global_position.distance_to(canoe.seat_position() - Vector3(0.0, 12.0 * Wardrobe.px(), 0.0)) < 0.05
	notes.append("10 s 向东 %.1f m，速度 %.1f m/s，起伏 %.2f m，人跟船 %s" % [moved, canoe.speed, max_y - min_y, follows])
	# 绕过码头尽头到开阔水面：这里离岸太远，下不了船
	var open_water := Vector2(5.0, 22.0)
	for i in 60 * 40:
		var to := open_water - canoe.world_position_2d()
		if to.length() < 2.0:
			break
		_player.autopilot_direction = Vector3(to.x, 0.0, to.y)
		await get_tree().physics_frame
	var too_far := not _player.try_interact() and _player.boat == canoe
	# 划向湖心小岛，直到船头碰到浅水搁浅
	var islet := Vector2(42.0, -6.0)
	var arrived := false
	for i in 60 * 90:
		var to := islet - canoe.world_position_2d()
		_player.autopilot_direction = Vector3(to.x, 0.0, to.y)
		await get_tree().physics_frame
		if canoe.grounded:
			arrived = true
			break
	_player.autopilot_direction = Vector3.ZERO
	await _seconds(1.0)
	var hull_ok := canoe._hull_clear(canoe.world_position_2d(), canoe.heading)
	var landed := _player.try_interact() and _player.boat == null
	await _seconds(1.0)
	var on_island := _player.global_position.y > WorldLayout.water_level() + 0.05 and Vector2(_player.global_position.x, _player.global_position.z).distance_to(islet) < 14.0 and _player.is_on_floor()
	var found_islet := &"lake_islet" in WorldState.discoveries
	notes.append("到岛 %s，船身在水里 %s，上岸 %s（在岛上 %s），发现小岛 %s，湖中间下船被拒 %s" % [arrived, hull_ok, landed, on_island, found_islet, too_far])
	# 在岛上往深水走：被岛边挡墙挡住
	var away := Vector2(_player.global_position.x, _player.global_position.z) - islet
	_player.autopilot_direction = Vector3(away.x, 0.0, away.y).normalized()
	await _seconds(8.0)
	_player.autopilot_direction = Vector3.ZERO
	await _frames(15)
	var depth := WorldLayout.water_level() - _player.global_position.y
	var wall_ok := depth < float(WorldLayout.section("lake")["wade_limit_depth"]) + 0.25
	notes.append("岛边涉水深度 %.2f m" % depth)
	# 再上船，放到码头边，按 E 落到码头板上
	_player.autopilot_enabled = false
	_player.board(canoe)
	canoe.place_at(Vector2(-20.0, 24.0), 90.0)
	await _frames(5)
	var dock_ok := _player.disembark() and absf(_player.global_position.y - (float(WorldLayout.section("dock")["deck_height"]) + 0.05)) < 0.2
	await _seconds(0.8)
	dock_ok = dock_ok and _player.is_on_floor()
	var saved: Dictionary = WorldState.vehicles.get("lake_canoe", {})
	notes.append("码头下船 %s，存档里的船位置 %s" % [dock_ok, str(saved.get("pos", []))])
	canoe.place_at(start_xz, 90.0)
	_check("独木舟：码头上船、划行有起伏、湖中间不能下船、划到湖心小岛靠岸上岛、岛边有涉水挡墙、码头边下船、位置记进存档",
		moored and boarded and moved > 15.0 and follows and max_y - min_y > 0.005 and too_far and arrived and hull_ok and landed and on_island \
		and found_islet and wall_ok and dock_ok and not saved.is_empty(), "；".join(notes))


func _test_exploration_save() -> void:
	var exp := _main.get_node("World/Exploration") as Exploration
	WorldState.discoveries.erase(&"dock_end")   # 前面的测试可能已经路过码头尽头
	var before := WorldState.discoveries.size()
	var found := exp.check(Vector2(-2.0, 26.0))
	var again := exp.check(Vector2(-2.0, 26.0))
	var hud := _main.get_node("HUD")
	await _frames(2)
	var toast: String = hud.toast_text()
	var snap := WorldState.snapshot()
	var migrated := WorldState.migrate({"schema_version": 1, "world_day": 3})
	var ok: bool = found == [&"dock_end"] and again.is_empty() and WorldState.discoveries.size() == before + 1 \
		and toast.contains("码头尽头") and snap["schema_version"] == 2 and (snap["discoveries"] as Array).has("dock_end") \
		and snap.has("vehicles") and migrated["schema_version"] == 2 and migrated["discoveries"] == [] and migrated["vehicles"] == {}
	_check("探索：走到码头尽头记为新发现（不重复）、弹出提示；存档快照含发现与船位置，v1 存档能升级到 v2",
		ok, "新发现 %s，提示「%s」，快照版本 %d，发现列表 %s" % [str(found), toast, snap["schema_version"], str(snap["discoveries"])])


# ---------------------------------------------------------------- 立牌

func _test_signs() -> void:
	var floating := PackedStringArray()
	for l in _main.find_children("*", "Label3D", true, false):
		var n: Node = l
		while n != null and not n is SignBoard:
			n = n.get_parent()
		if n == null:
			floating.append(str(_main.get_path_to(l)))
	var signs := get_tree().get_nodes_in_group("sign_boards")
	var missing := PackedStringArray()
	for s: SignBoard in signs:
		var t: Dictionary = SignBoard.texts().get(s.text_id, {})
		if str(t.get("title_zh", "")) == "" or str(t.get("title_en", "")) == "" or t.has("body_zh") != t.has("body_en"):
			missing.append(s.text_id)
	_check("3D 文字都写在立牌上（无悬空文字），每块中英双语", floating.is_empty() and missing.is_empty() and signs.size() >= 8,
		"立牌 %d 块；悬空文字 %s；缺译文 %s" % [signs.size(), ", ".join(floating) if not floating.is_empty() else "无", ", ".join(missing) if not missing.is_empty() else "无"])


# ---------------------------------------------------------------- 泳池馆与水族馆

func _test_poolhouse_walk() -> void:
	var notes := PackedStringArray()
	var outside := _ph(-13.4, 0.0, 0.0)
	await _setup_at(Vector2(outside.x, outside.z), -PI * 0.5)
	_player.look_at_point(_ph(-12.0, 1.3, 0.0))
	await _frames(2)
	var opened := _player.try_interact()
	await _seconds(1.0)
	var door_state := WorldState.get_interactable_state(&"poolhouse_front_door")
	notes.append("开门 %s → %s" % [opened, door_state])
	_begin_track()
	var ok := opened and door_state == "open"
	for p in [Vector2(-10.0, 0.0), Vector2(-4.3, 0.0), Vector2(-4.3, 6.4)]:
		ok = await _walk_to(_ph_xz(p), 20.0) and ok
	var in_hall := WorldState.zones_of(_player.entity_id).has(&"poolhouse")
	notes.append("大厅区域 %s" % in_hall)
	for p in [Vector2(-5.3, 6.4), Vector2(-10.9, 6.4), Vector2(-11.2, 5.0), Vector2(-11.2, 3.5), Vector2(-10.3, 3.5), Vector2(-5.0, 3.5), Vector2(-4.5, 3.5)]:
		ok = await _walk_to(_ph_xz(p), 20.0) and ok
	await _frames(10)
	_track = false
	var local := _house.to_local(_player.global_position)
	var in_aquarium := WorldState.zones_of(_player.entity_id).has(&"aquarium")
	notes.append("到达 (%.1f, %.2f, %.1f)，区域 %s" % [local.x, local.y, local.z, ", ".join(PackedStringArray(WorldState.zones_of(_player.entity_id)))])
	_check("泳池馆：门外开门 → 大厅 → 楼梯两跑下到水族馆，连续步行", ok and in_hall and in_aquarium and absf(local.y - PoolHouse.FLOOR_B) < 0.15 and _max_step < MAX_STEP,
		"%s；单帧最大位移 %.3f m" % ["；".join(notes), _max_step])


func _test_poolhouse_swim() -> void:
	var notes := PackedStringArray()
	var start := _ph(1.0, -1.6, 0.0)
	_player.autopilot_enabled = false
	_player.global_position = start
	_player.velocity = Vector3.ZERO
	await _seconds(3.0)
	var float_err := _house.to_local(_player.global_position).y - (PoolHouse.WATER_Y - 1.3)
	var floating := _player.swimming and absf(float_err) < 0.25
	notes.append("漂浮：游泳 %s，离漂浮高度 %.2f m" % [_player.swimming, float_err])
	_begin_track()
	var legs := [
		[Vector3(-1.6, -1.45, 0.0), false, "游到洞口上方"],
		[Vector3(-1.6, -9.5, 0.0), false, "穿过洞口与水管下潜"],
		[Vector3(0.6, -10.5, 0.0), true, "从管口下方游出"],
		[Vector3(5.0, -7.0, 0.0), true, "坡道上岸"],
	]
	var ok := floating
	_waters_seen.clear()
	for leg in legs:
		var target: Vector3 = leg[0]
		var arrived := await _move_to(_ph(target.x, target.y, target.z), 25.0, leg[1])
		notes.append("%s %s" % [leg[2], arrived])
		ok = ok and arrived
	await _frames(20)
	_track = false
	var tube_seen := _waters_seen.has(&"tube") and _waters_seen.has(&"dive_pool")
	var local := _house.to_local(_player.global_position)
	var in_aquarium := WorldState.zones_of(_player.entity_id).has(&"aquarium")
	notes.append("终点 (%.1f, %.2f, %.1f)，游泳 %s，区域含 aquarium %s" % [local.x, local.y, local.z, _player.swimming, in_aquarium])
	_check("泳池 → 池底洞口 → 玻璃水管 → 下潜池 → 坡道上岸进水族馆", ok and tube_seen and not _player.swimming and in_aquarium \
		and absf(local.y - PoolHouse.FLOOR_B) < 0.15 and _max_step < MAX_STEP, "%s；经过水管 %s；单帧最大位移 %.3f m" % ["；".join(notes), tube_seen, _max_step])


func _test_pool_climb_out() -> void:
	_player.autopilot_enabled = false
	_player.global_position = _ph(-2.4, -1.45, 0.0)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = PI * 0.5
	await _seconds(1.5)
	var was_swimming := _player.swimming
	_player.autopilot_enabled = true
	_player.autopilot_direction = Vector3(-1.0, 1.0, 0.0)
	await _seconds(2.0)
	_player.autopilot_direction = Vector3.ZERO
	await _seconds(1.0)
	_player.autopilot_enabled = false
	var local := _house.to_local(_player.global_position)
	_check("深水区按跳跃靠池壁爬上岸", was_swimming and not _player.swimming and local.x < PoolHouse.POOL.position.x - 0.1 and absf(local.y) < 0.15,
		"起点游泳 %s → 停在 (%.2f, %.2f, %.2f)" % [was_swimming, local.x, local.y, local.z])


func _test_fauna() -> void:
	var spawner := _main.get_node("World/Fauna") as FaunaSpawner
	var climate := _main.get_node("Systems") as ClimateSystem
	var ids := {}
	var dup := PackedStringArray()
	for a in spawner.animals:
		if ids.has(a.entity_id):
			dup.append(str(a.entity_id))
		ids[a.entity_id] = true
	var kinds := ["rabbit", "fox", "squirrel", "duck", "bird", "butterfly"]
	var counts := PackedStringArray()
	var all_present := true
	for k in kinds:
		counts.append("%s %d" % [k, spawner.count(k)])
		all_present = all_present and spawner.count(k) > 0
	_check("小动物：6 种都已生成，entity_id 不重复", all_present and dup.is_empty(), ", ".join(counts) + ("；重复 " + ", ".join(dup) if not dup.is_empty() else ""))

	var rules := {}
	for k in kinds:
		rules[k] = FaunaData.species(k).get("active", {})
	climate.jump_to_season(&"SUMMER")
	climate.set_hour(10.0)
	climate.set_weather(&"CLEAR", 0.0)
	await _frames(3)
	var day_ok: bool = FaunaData.is_active(rules["butterfly"]) and FaunaData.is_active(rules["rabbit"]) and FaunaData.is_active(rules["duck"])
	climate.set_weather(&"LIGHT_RAIN", 0.0)
	await _frames(3)
	var rain_ok: bool = not FaunaData.is_active(rules["butterfly"]) and FaunaData.is_active(rules["fox"])
	climate.set_weather(&"CLEAR", 0.0)
	climate.set_hour(23.5)
	await _frames(3)
	var night_ok: bool = not FaunaData.is_active(rules["butterfly"]) and not FaunaData.is_active(rules["rabbit"]) and FaunaData.is_active(rules["fox"])
	await _seconds(2.5)
	var hidden_ok := true
	for a in spawner.animals:
		if a.species_id == "butterfly" and a.active:
			hidden_ok = false
		if a.species_id == "fox" and not a.active:
			hidden_ok = false
	var summer_rabbit := FaunaData.palette(FaunaData.species("rabbit"), 0)
	climate.jump_to_season(&"WINTER")
	climate.set_hour(10.0)
	climate.set_weather(&"CLEAR", 0.0)
	await _frames(3)
	var winter_ok: bool = not FaunaData.is_active(rules["duck"]) and not FaunaData.is_active(rules["butterfly"]) and FaunaData.is_active(rules["rabbit"])
	var winter_rabbit := FaunaData.palette(FaunaData.species("rabbit"), 0)
	var coat_ok := summer_rabbit != winter_rabbit
	_check("动物作息：蝴蝶只在春夏晴天白天、狐狸夜里也出来、鸭子冬天不在、兔子冬天换毛色",
		day_ok and rain_ok and night_ok and hidden_ok and winter_ok and coat_ok,
		"白天 %s，下雨 %s，夜里 %s（运行时隐藏 %s），冬天 %s，换毛色 %s" % [day_ok, rain_ok, night_ok, hidden_ok, winter_ok, coat_ok])

	climate.jump_to_season(&"SUMMER")
	climate.set_hour(10.0)
	climate.set_weather(&"CLEAR", 0.0)
	await _seconds(2.0)
	var rabbit: Animal = null
	for a in spawner.animals:
		if a.species_id == "rabbit" and a.active and (rabbit == null or a.global_position.distance_to(Vector3(-47, 0, 16)) < rabbit.global_position.distance_to(Vector3(-47, 0, 16))):
			rabbit = a
	var flee_ok := false
	var detail := "没有找到活动的兔子"
	if rabbit != null:
		var rp := rabbit.global_position
		await _setup_at(Vector2(rp.x + 1.4, rp.z), 0.0)
		var saw_flee := rabbit.fleeing
		for i in 60:
			await get_tree().physics_frame
			saw_flee = saw_flee or rabbit.fleeing
		var d := Vector2(rabbit.global_position.x - _player.global_position.x, rabbit.global_position.z - _player.global_position.z).length()
		flee_ok = saw_flee and d > 3.0
		detail = "%s：玩家走到 1.4 m 内，1.6 s 后相距 %.1f m（逃跑 %s）" % [rabbit.entity_id, d, saw_flee]
	_check("兔子见人就跑", flee_ok, detail)

	var schools := get_tree().get_nodes_in_group("aquatic_life")
	var members := 0
	var inside := true
	for s: FishSchool in schools:
		members += s.members.size()
		inside = inside and s.all_inside()
	_check("水族箱：鱼、海龟、水母都在缸内游动", schools.size() == PoolHouse.TANKS.size() and members > 20 and inside,
		"%d 个缸，%d 只，全部在缸内 %s" % [schools.size(), members, inside])


func _test_storm_rainbow_leaves() -> void:
	var climate := _main.get_node("Systems") as ClimateSystem
	var env := _main.get_node("World/Environment") as EnvironmentDirector
	var winter_storm := ClimateData.is_allowed(&"WINTER", &"THUNDERSTORM")
	var summer_storm := ClimateData.is_allowed(&"SUMMER", &"THUNDERSTORM")
	climate.apply_preset("Summer_Rainbow")
	await _seconds(1.0)
	var calm_wind := env.wind_strength
	var rainbow := env.rainbow
	var rainbow_sun := env.sun_elevation
	climate.apply_preset("Summer_Night_Thunderstorm")
	var strikes := [0]
	var on_strike := func(_d: float) -> void: strikes[0] += 1
	EventBus.lightning_strike.connect(on_strike)
	var before := env.lightning_count
	await _seconds(15.0)
	EventBus.lightning_strike.disconnect(on_strike)
	var flashes := env.lightning_count - before
	var storm_wind := env.wind_strength
	_check("雷暴：冬天不会出现、夏夜雷雨 15 s 内有闪电、风明显变大", not winter_storm and summer_storm and flashes >= 1 and strikes[0] >= 1 and storm_wind > calm_wind + 0.3,
		"冬季允许 %s，闪电 %d 次（信号 %d），风 %.2f → %.2f" % [winter_storm, flashes, strikes[0], calm_wind, storm_wind])
	_check("雨后放晴、太阳较低时出现彩虹", rainbow > 0.3, "Summer_Rainbow 预设 rainbow = %.2f，太阳高度 %.1f°" % [rainbow, rainbow_sun])

	var precip := get_tree().get_first_node_in_group("precipitation") as Precipitation
	climate.jump_to_season(&"AUTUMN")
	climate.set_hour(14.0)
	climate.set_weather(&"OVERCAST", 0.0)
	await _seconds(1.0)
	var autumn_on := precip.leaves.emitting and precip.leaves_kind == "leaves"
	climate.jump_to_season(&"WINTER")
	climate.set_weather(&"CLEAR", 0.0)
	await _seconds(1.0)
	var winter_off := not precip.leaves.emitting
	var blockers := 0
	for n in [_house, _cabin]:
		blockers += n.find_children("*", "GPUParticlesCollisionBox3D", true, false).size()
	_check("秋天飘落叶、冬天不飘，建筑有落叶挡板", autumn_on and winter_off and blockers >= 4,
		"秋 %s，冬停 %s，挡板 %d 个" % [autumn_on, winter_off, blockers])


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
	if _player.current_water != null:
		_waters_seen[_player.current_water.volume_id] = true


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


## 自动驾驶朝 target 走/游（三维方向；水中可上下）。horizontal = 只按水平距离判断到达（目标点在地板以下时用）。
func _move_to(target: Vector3, timeout_s: float, horizontal := false) -> bool:
	_player.autopilot_enabled = true
	var limit := int(timeout_s * Engine.physics_ticks_per_second)
	var arrived := false
	for i in limit:
		var to := target - _player.global_position
		var flat := Vector2(to.x, to.z).length()
		var dist := flat if horizontal or not _player.swimming else to.length()
		if dist < 0.35:
			arrived = true
			break
		_player.autopilot_direction = to
		_player.autopilot_run = false
		await get_tree().physics_frame
	_player.autopilot_direction = Vector3.ZERO
	await _frames(15)
	_player.autopilot_enabled = false
	return arrived


func _ph(x: float, y: float, z: float) -> Vector3:
	return _house.to_global(Vector3(x, y, z))


func _ph_xz(local_xz: Vector2) -> Vector2:
	var p := _house.to_global(Vector3(local_xz.x, 0.0, local_xz.y))
	return Vector2(p.x, p.z)


func _ray_info() -> String:
	var ray := _player.interact_ray
	ray.force_raycast_update()
	var p := _player.global_position
	if not ray.is_colliding():
		return "未命中（玩家 %.2f, %.2f, %.2f）" % [p.x, p.y, p.z]
	var c := ray.get_collider() as Node
	return "%s @ %s（玩家 %.2f, %.2f, %.2f）" % [c.get_path(), str(ray.get_collision_point()), p.x, p.y, p.z]


func _near_pit_edge(x: float, z: float) -> bool:
	for pit in WorldLayout.section("terrain").get("pits", []):
		var r: Array = pit["rect"]
		var outer := Rect2(float(r[0]) - 1.5, float(r[1]) - 1.5, float(r[2]) - float(r[0]) + 3.0, float(r[3]) - float(r[1]) + 3.0)
		var inner := Rect2(float(r[0]) + 1.5, float(r[1]) + 1.5, float(r[2]) - float(r[0]) - 3.0, float(r[3]) - float(r[1]) - 3.0)
		if outer.has_point(Vector2(x, z)) and not inner.has_point(Vector2(x, z)):
			return true
	return false


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
