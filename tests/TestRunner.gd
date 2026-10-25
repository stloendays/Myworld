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
## 聊天框：按键开关、打字时人物不动、消息转义、命令（时刻 / 季节 / 天气 / 传送 / 清屏）、系统消息。

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
var _min_y := INF
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
	_test_world_anchor()
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
	await _test_chat()
	_test_release()
	await _test_poolhouse_walk()
	await _test_poolhouse_swim()
	await _test_pool_climb_out()
	await _test_fauna()
	await _test_storm_rainbow_leaves()
	await _test_first_person_arms()
	await _test_hands_and_right_click()
	await _test_settings()
	await _test_minimap()
	await _test_developer_mode()
	await _test_cabin_life()
	await _test_sleep()
	await _test_canoe()
	await _test_exploration_save()
	await _test_performance()
	_test_memory()
	_test_chess_rules()
	await _test_chess_table()
	_test_aquarium_decor()
	await _test_emotes()
	await _test_seasonal_fx()
	await _test_fullscreen_and_world_map()
	_test_updater()
	await _test_fairy_glade()
	await _test_snow_peak()
	await _test_cave()
	await _test_totem_quests()
	await _test_constellations()
	await _test_cottage()
	await _test_nature()
	_test_cover_fade()
	await _test_world_travel()
	_report()


# ---------------------------------------------------------------- 图腾山洞、任务、星座、石头小屋、跨世界

func _test_cave() -> void:
	var cave := get_tree().get_first_node_in_group("cave") as Cave
	if cave == null:
		_check("图腾山洞已生成", false)
		return
	# 步行路线 = 洞道中线，只是在石厅里从篝火南边绕过去
	var centers := []
	for p: Vector2 in cave.centerline:
		centers.append(p + Vector2(0.0, 2.8) if p.distance_to(cave.chamber) < 0.5 else p)
	# 从洞外步道沿中线走进石厅，再走到传送门前：一路连续、没被岩壁挡住，进洞后属于室内区域 cave
	await _setup_at(Vector2(-8.0, -84.0), 0.0)
	_begin_track()
	var ok := true
	for p: Vector2 in centers.slice(0, centers.size() - 1):
		ok = await _walk_to(p, 25.0) and ok
	_track = false
	var inside := WorldState.zones_of(_player.entity_id).has(&"cave") and WorldState.is_indoors(_player.entity_id)
	var end_xz := Vector2(_player.global_position.x, _player.global_position.z)
	var near_portal := end_xz.distance_to(WorldLayout.v2(WorldLayout.section("cave")["portal"]["pos"])) < 4.5
	# 岩壁挡人：从石厅中心往北直走 8 秒也出不了山洞
	await _setup_at(cave.chamber, 0.0)
	await _walk_for(Vector3(0.0, 0.0, -1.0), 8.0)
	var blocked := WorldState.zones_of(_player.entity_id).has(&"cave") and _player.global_position.z > cave.chamber.y - 7.0
	# 洞里不下雨：雨天里站在石厅，降水粒子被挡（室内）
	var no_trees := Vegetation.tree_density(cave.chamber.x, cave.chamber.y) == 0.0 and Vegetation.tree_density(-8.0, -95.0) == 0.0
	_check("图腾山洞：从步道走进洞口、穿过石厅走到光门前（连续、无穿墙），洞内是室内区域，岩壁挡人，洞里没有树",
		ok and inside and near_portal and blocked and no_trees and _max_step < MAX_STEP,
		"走完 %s · 室内 %s · 到光门 %s · 撞墙停住 %s（z = %.1f）· 无树 %s · 最大单步 %.2f m · 路程 %.0f m" % [ok, inside, near_portal, blocked, _player.global_position.z, no_trees, _max_step, _path_length])
	# 篝火：按 E 熄灭 / 点燃，原木可以坐
	var fire := cave.bonfire
	await _setup_at(cave.chamber + Vector2(-1.8, 1.8), 0.0)
	_player.look_at_point(fire.global_position + Vector3(0.0, 0.4, 0.0))
	await _frames(2)
	var off := _player.try_interact() and WorldState.get_interactable_state(&"cave_bonfire") == "off"
	var on := _player.try_interact() and WorldState.get_interactable_state(&"cave_bonfire") == "on"
	_check("篝火按 E 熄灭再点燃（状态按 uid 登记），三根原木都是座位", off and on and cave.seats.size() == 3,
		"熄灭 %s · 点燃 %s · 座位 %d" % [off, on, cave.seats.size()])


func _test_totem_quests() -> void:
	var cave := get_tree().get_first_node_in_group("cave") as Cave
	var panel := _main.get_node("DialoguePanel") as DialoguePanel
	QuestLog.reset()
	WorldState.flags.erase("met_totem")
	# 走到图腾前，看着它按 E：对话框打开、玩家不能动；第一页是打招呼，第二页给第一个任务
	var t := cave.totem.global_position
	await _setup_at(Vector2(t.x, t.z) + Vector2(0.0, 2.6), 0.0)
	_player.look_at_point(t + Vector3(0.0, 2.0, 0.0))
	await _frames(2)
	var opened := _player.try_interact() and panel.is_open() and _player.input_locked
	var greet := panel.pages.size() == 2 and str(panel.pages[0]["text"]) == QuestLog.line("greeting")
	panel.advance()     # 先把这页的字打完
	panel.advance()     # 翻到下一页
	var offer_ok := panel.page_index == 1 and (panel.pages[1]["choices"] as Array).size() == 2
	panel.choose(0)
	var accepted := QuestLog.state_of("fireside") == "active" and not panel.is_open() and not _player.input_locked
	_check("老图腾：看着它按 E 打开对话（锁住移动）→ 打招呼 → 给任务 → 选“好”接下任务并关掉对话",
		opened and greet and offer_ok and accepted, "打开 %s · 招呼 %s · 选项 %s · 接下 %s" % [opened, greet, offer_ok, accepted])
	# 任务目标：坐到篝火边的原木上 → 自动完成；再和图腾说话先道谢、再给下一个任务（巡湖）
	var seat := cave.seats[0]
	_player.look_at_point(seat.global_position + Vector3(0.0, 0.2, 0.0))
	seat.interact(_player)
	await _frames(2)
	var done := QuestLog.evaluate(_player)
	_player.stand_up()
	await _seconds(0.5)
	var fire_done := done == ["fireside"] and QuestLog.state_of("fireside") == "done" and (_main.get_node("HUD").toast_text() as String).contains("篝火边的老朋友")
	panel.open_totem(cave.totem, _player)
	var thanks := str(panel.pages[0]["text"]) == QuestLog.text(QuestLog.get_quest("fireside"), "done") and panel.pages.size() == 2
	panel.advance()
	panel.advance()
	panel.choose(0)
	var survey := QuestLog.state_of("lake_survey") == "active"
	_check("任务：坐到原木上自动完成并提示；再对话先道谢，再接下一个任务（巡湖）", fire_done and thanks and survey,
		"完成 %s · 道谢 %s · 巡湖 %s" % [fire_done, thanks, survey])
	# 各类目标的进度
	for id in ["lake_islet", "north_reed_bay"]:
		WorldState.discoveries.erase(StringName(id))
	WorldState.discover(&"lake_islet")
	QuestLog.evaluate(_player)
	var partial: int = WorldState.quests["lake_survey"]["progress"]
	WorldState.discover(&"north_reed_bay")
	WorldState.discover(&"east_lily_cove")
	var survey_done := QuestLog.evaluate(_player) == ["lake_survey"]
	var reach := {"type": "reach", "pos": [102, -108], "radius": 7.0}
	var far_p := QuestLog.objective_progress(reach, _player)
	var species := {"type": "species", "count": 2}
	QuestLog.record("species", "rabbit", "兔子")
	var dup := QuestLog.record("species", "rabbit", "兔子")
	QuestLog.record("species", "fox", "狐狸")
	var sp := QuestLog.objective_progress(species, _player)
	var dance := {"type": "emote_at", "id": "dance", "pos": [-2, 26], "radius": 6.0}
	await _setup_at(Vector2(-6.0, 26.0), 0.0)
	var before_dance := QuestLog.objective_progress(dance, _player)
	_player.do_emote("dance")
	await _frames(2)
	var after_dance := QuestLog.objective_progress(dance, _player)
	_player.end_emote()
	_check("任务目标：探索点逐个计数（1/3 → 完成）、走到远处才算到达、图鉴记动物不重复、在码头尽头跳舞",
		partial == 1 and survey_done and far_p == Vector2i(0, 1) and not dup and sp == Vector2i(2, 2) and before_dance.x == 0 and after_dance.x == 1,
		"巡湖进度 %d → 完成 %s · 远处到达 %s · 重复记录 %s · 图鉴 %s · 跳舞 %s → %s" % [partial, survey_done, far_p, dup, sp, before_dance, after_dance])
	# 进行中最多 3 个；全部完成后图腾说结束语；存档快照里有任务与图鉴
	QuestLog.reset()
	for id in ["summit", "naturalist", "deep_dive"]:
		QuestLog.accept(id)
	var capped := QuestLog.next_offer().is_empty()
	for q: Dictionary in QuestLog.quests():
		WorldState.quests[str(q["id"])] = {"state": "done", "progress": 1, "thanked": true}
	var final_pages := panel.build_pages()
	var final_ok := str(final_pages[-1]["text"]) == QuestLog.line("all_done")
	var snap := WorldState.snapshot()
	var snap_ok := (snap["quests"] as Dictionary).size() == QuestLog.quests().size() and (snap["journal"] as Dictionary).has("species") == false
	_check("进行中的任务最多 3 个；全部完成后老图腾说结束语；任务进度写进存档快照（v3）", capped and final_ok and snap_ok,
		"满 3 个不再给 %s · 结束语 %s · 快照 %s" % [capped, final_ok, snap_ok])
	panel.close()
	QuestLog.reset()


func _test_constellations() -> void:
	var stars := _main.get_node("StarField") as StarField
	var climate := _main.get_node("Systems") as ClimateSystem
	QuestLog.reset()
	climate.jump_to_season(&"SUMMER")
	climate.set_hour(23.0)
	climate.set_weather(&"CLEAR", 0.0)
	await _setup_at(Vector2(-2.0, 30.0), 0.0)
	await _seconds(3.0)
	var night_vis := stars.visibility
	# 抬头盯着独木舟座看 2 秒：连线亮起、记进图鉴
	var c: Dictionary = StarField.constellations()[0]
	var dir := StarField.direction(float(c["az"]), float(c["el"]))
	_player.look_at_point(_player.head.global_position + dir * 50.0)
	await _seconds(2.2)
	var found := str(c["id"]) in WorldState.journal_list("constellations")
	# 白天看不见
	climate.set_hour(13.0)
	await _seconds(3.0)
	var day_vis := stars.visibility
	_check("星座：晴朗夜里在室外盯着看 1.5 秒就认出（记进图鉴），白天看不见",
		night_vis > 0.9 and found and day_vis < 0.1 and StarField.constellations().size() == 5,
		"夜里可见度 %.2f · 认出 %s · 白天可见度 %.2f" % [night_vis, found, day_vis])
	QuestLog.reset()


func _test_cottage() -> void:
	var cottage := get_tree().get_first_node_in_group("stone_cottage") as StoneCottage
	if cottage == null:
		_check("石头小屋已生成", false)
		return
	var door := cottage.door
	var front := door.global_position + door.global_basis.z * 1.6
	await _setup_at(Vector2(front.x, front.z), 0.0)
	_player.look_at_point(door.global_position)
	await _frames(2)
	var prompt_ok := _player.try_interact() and (_main.get_node("HUD").toast_text() as String).contains("门锁着")
	# 朝门直走 4 秒：被墙挡在外面
	var inward := -door.global_basis.z
	await _walk_for(Vector3(inward.x, 0.0, inward.z), 4.0)
	var c := cottage.global_position
	var local := cottage.to_local(_player.global_position)
	var outside := absf(local.x) > StoneCottage.SIZE.x * 0.5 or absf(local.z) > StoneCottage.SIZE.z * 0.5
	var no_trees := Vegetation.tree_density(c.x, c.z) == 0.0
	_check("石头小屋：门锁着（按 E 只提示），走不进去，屋旁没有树", prompt_ok and outside and no_trees and WorldState.get_interactable_state(&"cottage_door") == "locked",
		"提示 %s · 在屋外 %s（本地 %.1f, %.1f）· 无树 %s" % [prompt_ok, outside, local.x, local.z, no_trees])


# ---------------------------------------------------------------- 自然景观：小溪、瀑布、裂谷、桥

func _test_nature() -> void:
	var creek: Dictionary = {}
	var gorge: Dictionary = {}
	for c in WorldTerrain.channels():
		if c["id"] == "west_creek":
			creek = c
		elif c["id"] == "north_gorge":
			gorge = c
	if creek.is_empty() or gorge.is_empty():
		_check("小溪与裂谷已生成", false)
		return
	# 小溪：水面沿流向只降不升、有一道约 1.8 m 的跌水、流进湖里；河床比两岸低
	var water: PackedFloat64Array = creek["water"]
	var mono := true
	var biggest_drop := 0.0
	for i in range(1, water.size()):
		mono = mono and water[i] <= water[i - 1] + 1e-4
		biggest_drop = maxf(biggest_drop, water[i - 1] - water[i])
	var wet_end: int = creek["wet_end"]
	var into_lake := water[wet_end] <= WorldLayout.water_level() + 0.06 and wet_end < water.size() - 1
	var pts: PackedVector2Array = creek["pts"]
	var mid := pts[pts.size() / 2]
	var f := (pts[pts.size() / 2 + 1] - pts[pts.size() / 2 - 1]).normalized()
	var r := Vector2(-f.y, f.x)
	var bank := minf(WorldTerrain.height_at((mid + r * 4.5).x, (mid + r * 4.5).y), WorldTerrain.height_at((mid - r * 4.5).x, (mid - r * 4.5).y))
	var sunk := bank - WorldTerrain.height_at(mid.x, mid.y)
	# 裂谷：桥下最深处比两边谷沿低 6 m 以上，两头渐浅
	var gp: PackedVector2Array = gorge["pts"]
	var gbed: PackedFloat64Array = gorge["bed"]
	var deepest := 0.0
	for i in gp.size():
		deepest = maxf(deepest, WorldTerrain._raw(gp[i].x, gp[i].y) - gbed[i])
	var ends_shallow := WorldTerrain._raw(gp[0].x, gp[0].y) - gbed[0] < 0.5 and WorldTerrain._raw(gp[gp.size() - 1].x, gp[gp.size() - 1].y) - gbed[gbed.size() - 1] < 0.5
	# 河床、谷底不长树不长草，动物不进去
	var clean := true
	for c in [creek, gorge]:
		var cp: PackedVector2Array = c["pts"]
		for i in range(2, cp.size() - 2, 4):
			clean = clean and Vegetation.tree_density(cp[i].x, cp[i].y) == 0.0 and WorldTerrain.channel_distance(cp[i].x, cp[i].y) < 0.0
	var streams := _main.get_node("Streams") as Streams
	var built := streams.water_meshes.size() == 1 and streams.mists.size() == 1 and streams.bridges.size() == 2
	_check("小溪：水面只降不升、有一道 %.1f m 的瀑布、流进湖里，河床比两岸低 %.1f m；裂谷最深 %.1f m、两头渐浅；河床谷底不长树" % [biggest_drop, sunk, deepest],
		mono and biggest_drop > 1.4 and into_lake and sunk > 0.5 and deepest > 6.0 and ends_shallow and clean and built,
		"只降不升 %s · 入湖 %s · 两头渐浅 %s · 无树 %s · 水面 / 水雾 / 桥 %d / %d / %d" % [mono, into_lake, ends_shallow, clean, streams.water_meshes.size(), streams.mists.size(), streams.bridges.size()])
	# 林道过小溪：走过木板桥，脚一直在水面以上
	var bridges: Array = WorldLayout.section("nature")["bridges"]
	var b0: Dictionary = bridges[0]
	var a0 := WorldLayout.v2(b0["from"])
	var e0 := WorldLayout.v2(b0["to"])
	var dir0 := (e0 - a0).normalized()
	await _setup_at(a0 - dir0 * 2.5, 0.0)
	_begin_track()
	var crossed := await _walk_to(e0 + dir0 * 2.5, 20.0)
	_track = false
	var near_i := 0
	for i in pts.size():
		if pts[i].distance_to(a0.lerp(e0, 0.5)) < pts[near_i].distance_to(a0.lerp(e0, 0.5)):
			near_i = i
	# 桥中段的桥面比桥下的水面高（人走在桥上脚不沾水），一路连续
	var dry := _max_step < MAX_STEP
	for t in [0.35, 0.5, 0.65]:
		dry = dry and Streams.deck_height(b0, t) > float(water[near_i]) + 0.15
	# 林道过裂谷：走过原木桥，掉不下去
	var b1: Dictionary = bridges[1]
	var a1 := WorldLayout.v2(b1["from"])
	var e1 := WorldLayout.v2(b1["to"])
	var dir1 := (e1 - a1).normalized()
	await _setup_at(a1 - dir1 * 2.0, 0.0)
	_begin_track()
	var crossed1 := await _walk_to(e1 + dir1 * 2.0, 25.0)
	_track = false
	var gorge_bed := WorldTerrain.height_at(a1.lerp(e1, 0.5).x, a1.lerp(e1, 0.5).y)
	var not_fallen := _min_y > gorge_bed + 2.0 and _max_step < MAX_STEP
	# 桥上往侧面走：被栏杆挡住
	var mid1 := a1.lerp(e1, 0.5)
	_player.teleport_to(Vector3(mid1.x, Streams.deck_height(b1, 0.5) + 0.3, mid1.y))
	await _seconds(0.5)
	var side := Vector2(-dir1.y, dir1.x)
	await _walk_for(Vector3(side.x, 0.0, side.y), 3.0)
	var railed := _player.global_position.y > Streams.deck_height(b1, 0.5) - 0.5
	# 从东头走下裂谷谷底，再走回去
	await _setup_at(gp[gp.size() - 1] + Vector2(2.0, -1.0), 0.0)
	_begin_track()
	var down := true
	for i in [gp.size() - 6, gp.size() - 12, gp.size() / 2 + 6]:
		down = await _walk_to(gp[i], 25.0) and down
	var floor_y := _player.global_position.y
	var bed_here := WorldTerrain.height_at(_player.global_position.x, _player.global_position.z)
	var out := await _walk_to(gp[gp.size() - 1] + Vector2(2.0, -1.0), 30.0)
	_track = false
	var in_gorge := WorldTerrain._raw(gp[gp.size() / 2 + 6].x, gp[gp.size() / 2 + 6].y) - bed_here > 4.0
	_check("桥：走过木板桥过溪（脚不沾水）、走过原木桥过裂谷（掉不下去，侧面有栏杆）；裂谷能从东头走到谷底再走出来",
		crossed and dry and crossed1 and not_fallen and railed and down and in_gorge and out and floor_y - bed_here < 0.6,
		"过溪 %s（最低 %.2f m，脚不沾水 %s）· 过裂谷 %s · 没掉下去 %s · 栏杆 %s · 下到谷底 %s（离两侧谷沿 %.1f m 深）· 走出来 %s · 离谷底 %.2f m · 最大单步 %.2f m" % [
			crossed, _min_y, dry, crossed1, not_fallen, railed, down, WorldTerrain._raw(gp[gp.size() / 2 + 6].x, gp[gp.size() / 2 + 6].y) - bed_here, out, floor_y - bed_here, _max_step])


## 草、花、蘑菇：远处逐株缩小（着色器参数），整块要等全部缩没才剔除（不再整块抖动淡出）。
func _test_cover_fade() -> void:
	var cover := get_tree().get_first_node_in_group("ground_cover")
	var fading := 0
	var ok := true
	for mmi: MultiMeshInstance3D in cover.find_children("*", "MultiMeshInstance3D", true, false):
		var m := mmi.multimesh.mesh
		var mat := m.surface_get_material(0)
		var far_v: Variant = (mat as ShaderMaterial).get_shader_parameter("fade_far") if mat is ShaderMaterial else null
		if far_v != null and float(far_v) > 0.0:
			fading += 1
			var far := float(far_v)
			ok = ok and mmi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED 				and mmi.visibility_range_end >= far + GroundCoverBuilder.CHUNK * 0.7
	_check("地被：草、花、蘑菇远处逐株缩小消失，整块只在全部缩没后才剔除（走动时不再成块闪现）", fading > 50 and ok, "逐株缩小的块 %d 个，设置正确 %s" % [fading, ok])


## 最后一项：去第二个世界再回来（会换掉 _main），检查不同时加载、内存降下来、回来站在光门前。
func _test_world_travel() -> void:
	var nodes_lake := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem_lake := Performance.get_monitor(Performance.MEMORY_STATIC)
	var blocked_here := WorldTravel.blocked_reason("dusk_lake") != ""
	var blocked_planned := WorldTravel.blocked_reason("world_03") != ""
	var ok_go := WorldRegistry.enter("world_02")
	await WorldTravel.travel_finished
	var w2 := get_tree().get_first_node_in_group("world_root")
	var only_one := get_tree().get_nodes_in_group("world_root").size() == 1 and w2 is World02 and not is_instance_valid(_main) \
		and get_tree().get_first_node_in_group("cave") == null
	var r: Dictionary = WorldTravel.last_report
	var nodes_w2 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem_w2 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var lighter := nodes_w2 < nodes_lake * 0.2 and mem_w2 < mem_lake * 0.85
	var current_ok := WorldRegistry.current_id() == "world_02"
	# 回去：光门对面站着
	var back := WorldRegistry.enter("dusk_lake")
	await WorldTravel.travel_finished
	_main = get_tree().get_first_node_in_group("world_root") as Node3D
	_player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	await _seconds(1.0)
	var arrive: Dictionary = (WorldRegistry.get_world("dusk_lake")["arrivals"] as Dictionary)["world_02"]
	var at_gate := Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(float(arrive["pos"][0]), float(arrive["pos"][2]))) < 1.0
	var mem_back := Performance.get_monitor(Performance.MEMORY_STATIC)
	var no_leak := mem_back < mem_lake * 1.15
	var lobby := _main.get_node_or_null("LobbyMenu") as LobbyMenu
	_check("跨世界：图腾山洞的光门通往第二个世界，先卸载湖畔再加载（不同时存在），世界二节点数和内存大降；回来站在光门前，内存不涨",
		ok_go and blocked_here and blocked_planned and only_one and lighter and current_ok and back and at_gate and no_leak and (lobby == null or not lobby.is_open()),
		"节点 %d → %d（卸载后 %d）· 静态内存 %.0f → %.0f MB → 回来 %.0f MB · 只有一个世界 %s · 到光门前 %s · 用时 %d ms" % [
			nodes_lake, nodes_w2, int(r.get("nodes_unloaded", 0)), mem_lake / 1048576.0, mem_w2 / 1048576.0, mem_back / 1048576.0, only_one, at_gate, int(r.get("ms", 0))])


# ---------------------------------------------------------------- 国际象棋

func _sq(name: String) -> int:
	return ChessGame.square_from_name(name)


func _test_chess_rules() -> void:
	var notes := PackedStringArray()
	# perft：标准走法计数（开局、Kiwipete、第 3 号局面），任何一个走法规则错都会对不上
	var perft_ok := true
	for case in [[ChessGame.START_FEN, [20, 400, 8902]],
			["r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039]],
			["8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812]]]:
		var g := ChessGame.new(case[0])
		for d in (case[1] as Array).size():
			var n := g.perft(d + 1)
			if n != int(case[1][d]):
				perft_ok = false
				notes.append("perft %s 第 %d 层 = %d（应为 %d）" % [str(case[0]).left(12), d + 1, n, case[1][d]])
	notes.append("perft %s" % perft_ok)
	# 愚人杀
	var fool := ChessGame.new()
	for mv in [["f2", "f3"], ["e7", "e5"], ["g2", "g4"], ["d8", "h4"]]:
		fool.play_squares(_sq(mv[0]), _sq(mv[1]))
	var mate_ok := fool.result() == "checkmate_black" and fool.moves_san[3] == "Qh4#"
	# 逼和
	var stale_ok := ChessGame.new("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").result() == "stalemate"
	# 吃过路兵：吃掉 d5 的兵
	var ep := ChessGame.new("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	var ep_san := ep.play_squares(_sq("e5"), _sq("d6"))
	var ep_ok := ep_san == "exd6" and ep.board[_sq("d5")] == 0
	# 王车易位：f1 被车控制时不能短易位，长易位可以
	var castle := ChessGame.new("r3k3/8/8/8/8/8/5r2/R3K2R w KQq - 0 1")
	var short_ok := castle.play_squares(_sq("e1"), _sq("g1")) == ""
	var long_ok := castle.play_squares(_sq("e1"), _sq("c1")) == "O-O-O" and castle.board[_sq("d1")] == ChessGame.ROOK
	# 升变成马
	var promo := ChessGame.new("8/P7/8/8/8/8/8/k6K w - - 0 1")
	var promo_ok := promo.play_squares(_sq("a7"), _sq("a8"), ChessGame.KNIGHT) == "a8=N" and promo.board[_sq("a8")] == ChessGame.KNIGHT
	# 三次重复
	var rep := ChessGame.new()
	for i in 2:
		for mv in [["g1", "f3"], ["g8", "f6"], ["f3", "g1"], ["f6", "g8"]]:
			rep.play_squares(_sq(mv[0]), _sq(mv[1]))
	var rep_ok := rep.result() == "repetition"
	# 悔棋
	var u := ChessGame.new()
	u.play_squares(_sq("e2"), _sq("e4"))
	var undo_ok := u.undo() and u.to_fen() == ChessGame.START_FEN
	# 电脑：一步杀能找到（普通难度）
	var ai_move := ChessAI.new(7).choose(ChessGame.new("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"), "normal")
	var ai_ok := ChessGame.m_to(ai_move) == _sq("a8")
	notes.append("将死 %s，逼和 %s，过路兵 %s，易位 %s/%s，升变 %s，三次重复 %s，悔棋 %s，电脑一步杀 %s" % [mate_ok, stale_ok, ep_ok, short_ok, long_ok, promo_ok, rep_ok, undo_ok, ai_ok])
	_check("国际象棋规则：perft 标准计数（20/400/8902、48/2039、14/191/2812）、将死、逼和、过路兵、易位、升变、三次重复、悔棋、电脑找一步杀",
		perft_ok and mate_ok and stale_ok and ep_ok and short_ok and long_ok and promo_ok and rep_ok and undo_ok and ai_ok, "；".join(notes))


func _test_chess_table() -> void:
	var life := _cabin.get_node("Generated/Life") as CabinLife
	var table := life.chess
	var notes := PackedStringArray()
	# 坐在沙发上，看着棋盘按 E
	var sofa := _cabin.get_node("Generated/Life/Seat_cabin_sofa_left") as Seat
	_player.teleport_to(_cabin_point(Vector3(1.4, 0.05, 1.9)))
	await _seconds(0.3)
	_player.sit(sofa)
	await _frames(3)
	_player.look_at_point(table.global_position + Vector3(0.0, 0.05, 0.0))
	await _frames(3)
	var opened := _player.try_interact() and table.panel.is_open() and _player.input_locked and _player.seat == sofa
	notes.append("坐着打开棋盘 %s" % opened)
	# 人机（我执白）：e2-e4，电脑应着
	var p := table.panel
	p.mode = "ai_black"
	p.level = "easy"
	p.new_game()
	p.click_square(_sq("e2"))
	var moved := p.click_square(_sq("e4"))
	await p.wait_ai()
	await _frames(2)
	var replied := p.game.moves_san.size() == 2 and p.game.white_to_move
	var synced := table.piece_count() == 32
	var e4_piece := false
	for n: Node3D in table._pieces.get_children():
		if n.position.distance_to(ChessTable.square_center(_sq("e4"))) < 0.01:
			e4_piece = true
	notes.append("走 e4 %s，电脑应着 %s（%s），3D 棋子 %d 个，e4 上有子 %s" % [moved, replied, " ".join(p.game.moves_san), table.piece_count(), e4_piece])
	# 非法走法不动：点白方的车走斜线
	p.click_square(_sq("a1"))
	var illegal_blocked := not p.click_square(_sq("b2")) and p.game.moves_san.size() == 2
	# 存档、关闭
	var saved: Dictionary = WorldState.flags.get("chess", {})
	p.close()
	await _frames(2)
	var closed_ok := not p.is_open() and not _player.input_locked
	_player.stand_up()
	notes.append("非法走法被拒 %s，存档 %s，关闭后解锁 %s" % [illegal_blocked, str(saved.get("moves", [])), closed_ok])
	_check("国际象棋：坐在沙发上看着茶几上的棋盘按 E 打开 2D 棋盘，人机对弈走子与电脑应着，3D 棋盘同步，非法走法被拒，棋局存档，关闭后解锁移动",
		opened and moved and replied and synced and e4_piece and illegal_blocked and saved.get("moves", []).size() == 2 and closed_ok, "；".join(notes))


# ---------------------------------------------------------------- 性能

func _test_performance() -> void:
	var notes := PackedStringArray()
	# 树林分块：每块的包围盒不超过一个方格（加树冠余量）
	var forest := _main.get_node("World/Forest") as ForestBuilder
	var mmis := forest.get_node("Generated").find_children("*", "MultiMeshInstance3D", false, false)
	var cells := {}
	var tagged := 0
	for mmi: MultiMeshInstance3D in mmis:
		if mmi.has_meta("cell"):
			tagged += 1
			cells[mmi.get_meta("cell")] = true
	# 分块规则本身：同一方格里的点进同一块
	var grouped := ForestBuilder._by_cell([{"transform": Transform3D(Basis(), Vector3(1, 0, 1))}, {"transform": Transform3D(Basis(), Vector3(63, 0, 10))}, {"transform": Transform3D(Basis(), Vector3(65, 0, 10))}])
	var chunk_ok := mmis.size() > 40 and tagged == mmis.size() and cells.size() >= 12 and grouped.size() == 2
	notes.append("树林 %d 块（%d 个 64 m 方格）" % [mmis.size(), cells.size()])
	# 遮挡剔除：工程开启 + 地形遮挡体
	var occ_ok := bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling")) \
		and _main.find_child("TerrainOccluder", true, false) != null
	notes.append("遮挡剔除 %s" % occ_ok)
	# 画质分级
	var perf := _main.get_node("Performance") as PerformanceDirector
	var env := _main.get_node("World/Environment") as EnvironmentDirector
	GameSettings.set_value("graphics_quality", "low", false)
	await _frames(2)
	var low_ok := not env.environment.ssr_enabled and not env.environment.ssao_enabled and env.sun.directional_shadow_max_distance == 60.0 \
		and env.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and get_viewport().msaa_3d == Viewport.MSAA_DISABLED and get_viewport().positional_shadow_atlas_size == 1024
	GameSettings.set_value("graphics_quality", "high", false)
	await _frames(2)
	var high_ok := env.environment.ssr_enabled and env.sun.directional_shadow_max_distance == 120.0 and get_viewport().msaa_3d == Viewport.MSAA_DISABLED \
		and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and get_viewport().use_taa and get_viewport().positional_shadow_atlas_size == 2048
	GameSettings.set_value("graphics_quality", "ultra", false)
	await _frames(2)
	var ultra_ok := get_viewport().msaa_3d == Viewport.MSAA_2X and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and get_viewport().use_taa
	GameSettings.set_value("graphics_quality", "medium", false)
	await _frames(2)
	var medium_ok := not get_viewport().use_taa and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA
	GameSettings.set_value("graphics_quality", "high", false)
	await _frames(2)
	notes.append("画质 低 %s / 中 %s / 高 %s（TAA）/ 极高 %s" % [low_ok, medium_ok, high_ok, ultra_ok])
	# 动态分辨率防抖：只超预算一次不降
	var once := perf.update_dynamic_scale(25.0)
	perf.update_dynamic_scale(10.0)
	var debounce_ok := absf(once - 1.0) < 0.001
	# 动态分辨率：GPU 25 ms（超 60 fps 预算）一路降到下限，GPU 5 ms 一路升回 100%
	var lowest := 1.0
	for i in 40:
		lowest = minf(lowest, perf.update_dynamic_scale(25.0))
	var fsr := get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR
	var floor_ok := absf(perf.effective_scale() - PerformanceDirector.MIN_SCALE) < 0.01
	var back := 0.0
	for i in 40:
		back = perf.update_dynamic_scale(5.0)
	var dyn_ok := debounce_ok and floor_ok and fsr and absf(back - 1.0) < 0.001 and get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR
	notes.append("动态分辨率 最低 %.0f%%（FSR %s），恢复 %.0f%%" % [perf.effective_scale() * 100.0 if not dyn_ok else PerformanceDirector.MIN_SCALE * 100.0, fsr, back * 100.0])
	# 帧率上限：默认 60；无窗口的自动检查不限
	var cap_ok := int(GameSettings.DEFAULTS["max_fps"]) == 60 and Engine.max_fps == 0
	# 局部灯都按距离淡出
	await _frames(2)
	# 后加入的灯在加入时就设好淡出（不再定时全树搜索）
	var late := OmniLight3D.new()
	_main.add_child(late)
	var late_ok := late.distance_fade_enabled
	late.free()
	notes.append("后加的灯自动淡出 %s" % late_ok)
	var lights := _main.find_children("*", "OmniLight3D", true, false)
	var faded := 0
	for l: OmniLight3D in lights:
		if l.distance_fade_enabled:
			faded += 1
	notes.append("局部灯淡出 %d / %d" % [faded, lights.size()])
	# 在地下水族馆时不算太阳阴影
	_player.teleport_to(_ph(-4.5, -6.95, 3.5))
	await _seconds(0.6)
	var under_ok := not env.sun_shadows_allowed
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
	await _seconds(0.3)
	under_ok = under_ok and env.sun_shadows_allowed
	notes.append("地下关太阳阴影 %s" % under_ok)
	# 远处动物降频
	var far_animal: Animal = null
	for a in (_main.get_node("World/Fauna") as FaunaSpawner).animals:
		if a.global_position.distance_to(_player.camera.global_position) > 160.0:
			far_animal = a
			break
	var lod_ok := far_animal != null and far_animal._lod_interval() == 12
	_check("性能：树林分块、地形遮挡剔除、画质分级、动态分辨率（FSR）、默认 60 帧上限、局部灯淡出、地下关太阳阴影、远处动物降频",
		chunk_ok and occ_ok and low_ok and medium_ok and high_ok and ultra_ok and dyn_ok and cap_ok and late_ok and faded == lights.size() and under_ok and lod_ok, "；".join(notes))


# ---------------------------------------------------------------- 内存

func _test_memory() -> void:
	var notes := PackedStringArray()
	# 外部贴图都以显存压缩格式 + mipmap 导入（无损导入时每张 1k 贴图占 4 MB 显存、没有 mipmap）
	var total := 0
	var compressed := 0
	var normals_ok := true
	for dir in DirAccess.get_directories_at("res://assets/imported/textures"):
		var base := "res://assets/imported/textures/%s/" % dir
		for f in DirAccess.get_files_at(base):
			if not f.ends_with(".jpg.import") and not f.ends_with(".png.import"):
				continue
			total += 1
			var text := FileAccess.get_file_as_string(base + f)
			if text.contains("compress/mode=2") and text.contains("mipmaps/generate=true"):
				compressed += 1
			if f.contains("_nor_") and not text.contains("compress/normal_map=1"):
				normals_ok = false
	notes.append("压缩贴图 %d / %d，法线 BC5 %s" % [compressed, total, normals_ok])
	# 树和地被：实例数组留在 CPU 侧，换季上色整块上传
	var forest := _main.get_node("World/Forest") as ForestBuilder
	var mmi := forest.get_node("Generated").find_children("*", "MultiMeshInstance3D", false, false)[0] as MultiMeshInstance3D
	var mm := mmi.multimesh
	var buf: PackedFloat32Array = mm.get_meta(ForestBuilder.BUFFER_META, PackedFloat32Array())
	var buf_ok := buf.size() == mm.instance_count * 16
	ForestBuilder.recolor(mm, [Color(0.25, 0.5, 0.75)])
	var after: PackedFloat32Array = mm.get_meta(ForestBuilder.BUFFER_META, PackedFloat32Array())
	var recolor_ok := after.size() == buf.size() and is_equal_approx(after[12], 0.25) and is_equal_approx(after[14], 0.75) \
		and is_equal_approx(after[3], buf[3]) and is_equal_approx(after[11], buf[11])
	forest.apply_season(WorldState.season_id)
	notes.append("实例数组 %s，整块换色 %s" % [buf_ok, recolor_ok])
	# 湖面反射探针重拍时不画阴影（重拍那一帧的尖峰少约三成）
	var probe := _main.find_child("LakeReflection", true, false) as ReflectionProbe
	var probe_ok := probe != null and not probe.enable_shadows
	_check("内存：外部贴图显存压缩 + mipmap、法线 BC5、树木地被实例数组整块写入与换色、湖面反射重拍不画阴影",
		compressed == total and total > 0 and normals_ok and buf_ok and recolor_ok and probe_ok, "；".join(notes))


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
		and toast.contains("码头尽头") and snap["schema_version"] == 3 and (snap["discoveries"] as Array).has("dock_end") \
		and snap.has("vehicles") and snap.has("quests") and snap.has("journal") and migrated["schema_version"] == 3 \
		and migrated["discoveries"] == [] and migrated["vehicles"] == {} and migrated["quests"] == {} and migrated["journal"] == {}
	_check("探索：走到码头尽头记为新发现（不重复）、弹出提示；存档快照含发现、船位置、任务与图鉴，v1 存档能升级到 v3",
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
		[Vector3(-1.8, -10.4, -1.2), true, "到通道口"],
		[Vector3(-1.8, -10.4, -2.4), true, "进入水下通道"],
		[Vector3(-1.8, -9.0, -5.6), false, "游进海洋大缸"],
		[Vector3(4.0, -7.5, -5.6), false, "在大缸里游"],
		[Vector3(-1.8, -10.4, -2.4), true, "游回通道"],
		[Vector3(-1.8, -10.4, -0.9), true, "回到下潜池"],
		[Vector3(0.6, -10.4, 0.5), true, "游到坡道脚下"],
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
	var tube_seen := _waters_seen.has(&"tube") and _waters_seen.has(&"dive_pool") and _waters_seen.has(&"reef_channel") and _waters_seen.has(&"reef")
	var local := _house.to_local(_player.global_position)
	var in_aquarium := WorldState.zones_of(_player.entity_id).has(&"aquarium")
	notes.append("终点 (%.1f, %.2f, %.1f)，游泳 %s，区域含 aquarium %s" % [local.x, local.y, local.z, _player.swimming, in_aquarium])
	_check("泳池 → 池底洞口 → 玻璃水管 → 下潜池 → 水下通道 → 海洋大缸 → 游回下潜池 → 坡道上岸进水族馆", ok and tube_seen and not _player.swimming and in_aquarium \
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
	var kinds := ["rabbit", "fox", "squirrel", "duck", "bird", "butterfly", "fairy"]
	var counts := PackedStringArray()
	var all_present := true
	for k in kinds:
		counts.append("%s %d" % [k, spawner.count(k)])
		all_present = all_present and spawner.count(k) > 0
	_check("小动物：7 种（含仙境的小仙子）都已生成，entity_id 不重复", all_present and dup.is_empty(), ", ".join(counts) + ("；重复 " + ", ".join(dup) if not dup.is_empty() else ""))

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
	_check("水族箱：海洋大缸（含蝠鲼、礁鲨）、珊瑚缸、水母缸里的生物都在缸内游动", schools.size() == PoolHouse.TANKS.size() + 1 and members > 20 and inside,
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

# ---------------------------------------------------------------- 聊天框

func _test_chat() -> void:
	var chat := get_tree().get_first_node_in_group("chat_box") as ChatBox
	var climate := get_tree().get_first_node_in_group("climate_system") as ClimateSystem
	_check("聊天框随 Main 创建，启动时有欢迎消息", chat != null and not chat.messages.is_empty() and chat.messages[0]["kind"] == "system",
		"%d 条消息" % (chat.messages.size() if chat != null else 0))
	if chat == null:
		return
	await _setup_at(Vector2(-50.0, 29.0), 0.0)

	# 按键：T 打开、Esc 关闭（Esc 不打开暂停菜单）；/ 打开时输入行预填 "/"
	var pause := _main.get_node("PauseMenu")
	Input.parse_input_event(_key(KEY_T, true))
	Input.parse_input_event(_key(KEY_T, false))
	await _frames(2)
	var opened_t := chat.is_open() and chat._field.text == ""
	Input.parse_input_event(_key(KEY_ESCAPE, true))
	Input.parse_input_event(_key(KEY_ESCAPE, false))
	await _frames(2)
	var closed_esc: bool = not chat.is_open() and not pause.is_open() and not get_tree().paused
	Input.parse_input_event(_key(KEY_SLASH, true))
	Input.parse_input_event(_key(KEY_SLASH, false))
	await _frames(2)
	var opened_slash := chat.is_open() and chat._field.text == "/"
	_check("T 打开聊天、Esc 只关聊天不暂停、/ 打开时预填命令符", opened_t and closed_esc and opened_slash,
		"T %s · Esc %s · / %s" % [opened_t, closed_esc, opened_slash])

	# 打字时人物不走（W 键按住也不动），关闭后恢复移动
	var start := _player.global_position
	Input.action_press("move_forward")
	await _seconds(0.8)
	var moved_open := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	chat.close()
	await _seconds(0.8)
	Input.action_release("move_forward")
	var moved_closed := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length() - moved_open
	_check("聊天框打开时按 W 人物不动，关闭后恢复行走", moved_open < 0.05 and moved_closed > 1.0 and not _player.autopilot_enabled,
		"打开时位移 %.2f m，关闭后 0.8 s 位移 %.2f m" % [moved_open, moved_closed])
	await _seconds(0.5)

	# 普通消息带名字，方括号不被当作富文本标记
	chat.submit("  你好 [b]湖畔[/b]  ")
	var last: Dictionary = chat.messages[-1]
	var line := ChatBox.format_line(last)
	_check("发送消息：去掉首尾空格、带玩家名字、方括号原样显示", last["kind"] == "player" and last["author"] == chat.player_name \
		and last["text"] == "你好 [b]湖畔[/b]" and line.contains("[lb]b]") and not line.contains("[b]"), line)

	# 命令
	chat.submit("/time 18:30")
	var time_ok := absf(WorldState.time_minutes - 1110.0) < 1.0
	chat.submit("/season 冬")
	var season_ok := WorldState.season_id == &"WINTER"
	chat.submit("/weather 雷雨")
	var refused: bool = chat.messages[-1]["kind"] == "error" and WorldState.weather_id != &"THUNDERSTORM"
	chat.submit("/weather 下雪")
	var snow_ok := WorldState.weather_id == &"SNOW"
	chat.submit("/foo")
	var unknown: bool = chat.messages[-1]["kind"] == "error"
	_check("命令：/time 设时刻、/season 跳季、/weather 切天气且拒绝本季没有的天气、未知命令报错",
		time_ok and season_ok and refused and snow_ok and unknown,
		"time %s · season %s · 冬季拒绝雷雨 %s · 下雪 %s · 未知 %s" % [time_ok, season_ok, refused, snow_ok, unknown])
	var count := chat.messages.size()
	await _seconds(10.0)
	var notice := false
	for i in range(count, chat.messages.size()):
		notice = notice or (chat.messages[i]["kind"] == "system" and str(chat.messages[i]["text"]).contains(tr("下雪")))
	_check("天气过渡完成后聊天框收到系统消息", notice, "新增 %d 条" % (chat.messages.size() - count))

	# 传送只到室外地面
	chat.submit("/tp -84 93")
	await _frames(2)
	var tp_ok := Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(-84, 93)) < 0.1
	var before := _player.global_position
	chat.submit("/tp -66 37")
	var no_house: bool = chat.messages[-1]["kind"] == "error" and _player.global_position == before
	chat.submit("/tp 35 -2")
	var no_lake: bool = chat.messages[-1]["kind"] == "error" and _player.global_position == before
	await _seconds(1.0)
	var landed := _player.is_on_floor()
	chat.submit("/tp 出生点")
	_check("/tp 传送到室外地面并落地，拒绝传进木屋或湖面", tp_ok and landed and no_house and no_lake,
		"草甸 %s · 落地 %s · 拒绝木屋 %s · 拒绝湖面 %s" % [tp_ok, landed, no_house, no_lake])

	chat.submit("/clear")
	_check("/clear 清空记录", chat.messages.is_empty())
	climate.apply_preset("Autumn_Dusk_Clear")
	await _seconds(0.6)


# ---------------------------------------------------------------- 发布版：语言、房间号、联机规则

func _test_release() -> void:
	# 默认跟随系统语言（中文系统显示中文，其他系统英文）；选 English 后用英文翻译表，中文没有翻译表，tr() 原样返回中文
	var auto_ok := GameSettings.language == "auto" and GameSettings.resolved_language() == ("zh" if OS.get_locale_language() == "zh" else "en")
	GameSettings.set_value("language", "en", false)
	var en_ok := tr("继续") == "Resume" and tr("E  打开木门") == "E  Open the door"
	GameSettings.set_value("language", "zh", false)
	var zh_ok := tr("继续") == "继续" and TranslationServer.get_locale().begins_with("zh")
	GameSettings.set_value("language", "en", false)
	var back_en := tr("继续") == "Resume"
	GameSettings.set_value("language", "auto", false)
	_check("界面语言默认跟随系统，可切换英文 / 中文", auto_ok and en_ok and zh_ok and back_en, "跟随系统 %s（系统 %s）· en %s · zh %s" % [auto_ok, OS.get_locale_language(), en_ok, zh_ok])

	# 界面脚本里出现的中文都有英文翻译（新增文字忘了加翻译会在这里失败）
	GameSettings.set_value("language", "en", false)
	var skip := ["帮助", "时间", "天气", "季节", "预设", "坐标", "传送", "名字", "清屏", "中文", "、", "：", "季", "天",
		"%s：%s", "%s — %s", "×%d", "%d°", "—", "  ·  ", "出生点", "语言 / Language",
		"♟", "♞", "♝", "♜", "♛", "♚", "%s  ·  %s", "  ·  ", "✓  ", "◆  "]
	var missing := PackedStringArray()
	var re := RegEx.create_from_string(r'"([^"\n]*[^\x00-\x7F][^"\n]*)"')
	for dir in ["res://scripts/ui", "res://scripts/net", "res://scripts/interactions", "res://scripts/core", "res://scripts/games",
			"res://scripts/player", "res://scripts/buildings", "res://scripts/world", "res://scripts/systems", "res://scripts/vehicles", "res://scripts/worlds"]:
		for path in _list_files(dir, ".gd"):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var s := line.strip_edges()
				if s.begins_with("#") or s.contains("push_error") or s.contains("push_warning") or s.begins_with("const LANGUAGE"):
					continue
				for m in re.search_all(line):
					var text := m.get_string(1).c_unescape()
					if not text in skip and tr(text) == text:
						missing.append(text)
	# 数据文件里显示在界面上的名字：世界注册表、季节飘落物方案
	for w in WorldRegistry.worlds():
		for key in ["name", "summary"]:
			if tr(str(w[key])) == str(w[key]):
				missing.append(str(w[key]))
	for pid in (Precipitation.fx_data()["profiles"] as Dictionary).keys():
		var pname := str(Precipitation.fx_profile(str(pid)).get("name", pid))
		if tr(pname) == pname:
			missing.append(pname)
	_check("界面文字全部有英文翻译", missing.is_empty(), ", ".join(missing))
	GameSettings.set_value("language", "auto", false)

	# 房间号：编码解码往返、抄错能发现、地址直接输入、地址分类
	var round_ok := true
	for case in [["192.168.1.23", 24567], ["10.0.0.5", 24567], ["100.101.102.103", 24567], ["203.0.113.77", 30000], ["8.8.4.4", 1]]:
		var code := RoomCode.encode(case[0], case[1])
		var d := RoomCode.decode(code.to_lower().replace("-", " "))
		round_ok = round_ok and d["ok"] and d["host"] == case[0] and d["port"] == case[1] \
			and code.length() == (8 if case[1] == 24567 else 11)
	var good := RoomCode.encode("192.168.1.23")
	var caught := 0
	var tried := 0
	for i in good.length():
		if good[i] == "-":
			continue
		for ch in RoomCode.ALPHABET:
			if ch == good[i]:
				continue
			tried += 1
			var typo := good.substr(0, i) + ch + good.substr(i + 1)
			var r := RoomCode.decode(typo)
			if not r["ok"] or r["host"] != "192.168.1.23":
				caught += 1
	var addr := RoomCode.decode("192.168.1.9:4000")
	var classify_ok := RoomCode.classify("192.168.0.2") == "lan" and RoomCode.classify("100.88.1.2") == "vpn" \
		and RoomCode.classify("203.0.113.5") == "public" and RoomCode.classify("127.0.0.1") == "loopback"
	_check("房间号：往返无误、单字符抄错能识别、可直接输入 IP:端口、地址分类正确",
		round_ok and float(caught) / tried > 0.8 and addr["ok"] and addr["port"] == 4000 and classify_ok,
		"%s → 抄错识别 %d / %d" % [good, caught, tried])

	# 房主接纳规则：版本一致才能进，满 4 人拒绝
	var saved_roster := Net.roster
	Net.roster = {1: {}, 2: {}, 3: {}}
	var admit_ok := Net.admit_reason(Net.PROTOCOL, Net.game_version()) == "" \
		and Net.admit_reason(Net.PROTOCOL, "0.0.1") == "版本不一致" and Net.admit_reason(Net.PROTOCOL + 1, Net.game_version()) == "版本不一致"
	Net.roster[4] = {}
	var full_ok := Net.admit_reason(Net.PROTOCOL, Net.game_version()) == "房间已满"
	Net.roster = saved_roster
	_check("联机：版本不一致拒绝、满 4 人拒绝", admit_ok and full_ok, "版本 %s · 人数 %s" % [admit_ok, full_ok])

	# 大厅菜单在自动检查里不弹出；单人模式下暂停菜单仍会暂停世界
	var lobby := _main.get_node("LobbyMenu") as LobbyMenu
	_check("大厅菜单只在游戏主程序启动时弹出（自动检查里不弹）", lobby != null and not lobby.is_open() and not PlayerHold.is_held())


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = pressed
	return ev

# ---------------------------------------------------------------- 水族馆装饰、动作、飘落物、全屏与世界地图

func _test_aquarium_decor() -> void:
	var aq_seats := 0
	for s in _house.find_children("*", "Seat", true, false):
		if String((s as Seat).uid).begins_with("aquarium"):
			aq_seats += 1
	var planters := _house.find_children("CoralPlanter*", "MeshInstance3D", true, false).size()
	var whale := _house.find_child("Whale", true, false) as Node3D
	var kelp := _house.find_child("KelpPlanter", true, false) != null
	var hung := whale != null and kelp
	var clear_head := true
	for n in [whale]:
		if n != null:
			var m := (n as Node3D).get_node("Model") as MeshInstance3D
			var low := m.global_transform * m.get_aabb().position
			clear_head = clear_head and _house.to_local(low).y > PoolHouse.FLOOR_B + 1.95
	_check("水族馆不放长椅，换成珊瑚花坛、海带花坛与头顶的方块鲸鱼", aq_seats == 0 and planters == 4 and hung and clear_head,
		"水族馆座位 %d，珊瑚花坛 %d，鲸鱼与海带 %s，离地 ≥ 1.95 m %s" % [aq_seats, planters, hung, clear_head])


func _test_emotes() -> void:
	var notes := PackedStringArray()
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
	await _seconds(1.0)
	var bar := _main.get_node("ActionBar") as ActionBar
	var stand_eye := _player.head.global_position.y
	var wheel_hidden := not bar.wheel_open and not (bar.get_node("ActionWheelRoot") as Control).visible
	var sat := bar.trigger("rest") and _player.body.pose == "ground_sit"
	await _seconds(1.5)
	var sit_drop := stand_eye - _player.head.global_position.y
	notes.append("坐下 %s，眼睛降低 %.2f m" % [sat, sit_drop])
	# 想走就起身
	_player.autopilot_enabled = true
	_player.autopilot_direction = Vector3(1.0, 0.0, 0.0)
	await _frames(3)
	_player.autopilot_direction = Vector3.ZERO
	await _frames(20)
	_player.autopilot_enabled = false
	var stood := _player.emote == "" and _player.body.pose == "stand"
	notes.append("走动起身 %s" % stood)
	var lay := bar.trigger("rest") and _player.emote == "ground_sit" and bar.trigger("rest") and _player.body.pose == "lie"
	await _seconds(1.5)
	var flat := absf(rad_to_deg(_player.body.rotation.x) - 90.0) < 1.0
	var eye_low := _player.head.global_position.y - _player.global_position.y < 0.6
	var arms_hidden := not _player.arms.visible
	var toggled_off := bar.trigger("rest") and _player.emote == "" and absf(_player.body.rotation.x) < 0.01
	notes.append("躺下 %s，放平 %s，视线低 %s，第一人称手隐藏 %s，再按起身 %s" % [lay, flat, eye_low, arms_hidden, toggled_off])
	_player.set_third_person(false)
	# 轮盘：往右推选中“挥手”，松开即执行
	var dirs_ok := ActionBar.slice_at(Vector2(0, -80)) == 0 and ActionBar.slice_at(Vector2(80, 0)) == 1 \
		and ActionBar.slice_at(Vector2(0, 80)) == 2 and ActionBar.slice_at(Vector2(-80, 0)) == 3 and ActionBar.slice_at(Vector2(10, 5)) == -1
	bar._set_wheel(true)
	var wheel_shown := bar.wheel_open
	bar.hovered = 1
	bar._choose_or_close()
	var waved := not bar.wheel_open and _player.body.gesture == "wave" and _player.third_person
	await _frames(20)
	var arm_up := rad_to_deg((_player.body.parts["arm_r"] as Node3D).rotation.z) > 100.0
	await _seconds(3.0)
	var wave_done := _player.emote == "" and not _player.third_person
	notes.append("轮盘方向 %s，平时隐藏 %s、按 G 显示 %s" % [dirs_ok, wheel_hidden, wheel_shown])
	notes.append("挥手 %s，手举起 %s，做完自动结束并切回第一人称 %s" % [waved, arm_up, wave_done])
	var danced := bar.trigger("dance")
	await _seconds(4.0)
	var still_dancing := _player.emote == "dance"
	_player.end_emote()
	var clapped := bar.trigger("clap") and _player.body.gesture == "clap"
	await _seconds(3.2)
	var clap_done := _player.emote == ""
	notes.append("跳舞持续 %s，鼓掌 %s → 结束 %s" % [danced and still_dancing, clapped, clap_done])
	# 水里不能做动作
	_player.global_position = _ph(1.0, -1.6, 0.0)
	_player.velocity = Vector3.ZERO
	await _seconds(1.0)
	var refused := not bar.trigger("rest") and _player.emote == ""
	notes.append("游泳时拒绝 %s" % refused)
	var photo_path: String = await bar.take_photo() if DisplayServer.get_name() == "headless" else ""
	var photo_ok := photo_path == ""
	var keys_ok := true
	for i in 4:
		keys_ok = keys_ok and InputMap.has_action("action_%d" % (i + 1))
	keys_ok = keys_ok and InputMap.has_action("photo") and InputMap.has_action("toggle_actions")
	_check("动作轮盘：平时隐藏、G 弹出；休息（坐下 → 躺下 → 起身）、挥手、跳舞、鼓掌，移动起身，水里不能做", sat and sit_drop > 0.5 and stood and lay and flat and eye_low and arms_hidden \
		and toggled_off and waved and arm_up and wave_done and danced and still_dancing and clapped and clap_done and refused and photo_ok and keys_ok and dirs_ok and wheel_hidden and wheel_shown,
		"；".join(notes))
	await _setup_at(Vector2(-50.0, 29.0), 0.0)


func _test_seasonal_fx() -> void:
	var climate := _main.get_node("Systems") as ClimateSystem
	var env := _main.get_node("World/Environment") as EnvironmentDirector
	var precip := get_tree().get_first_node_in_group("precipitation") as Precipitation
	climate.jump_to_season(&"AUTUMN")
	climate.set_hour(15.0)
	climate.set_weather(&"CLEAR", 0.0)
	await _seconds(1.0)
	var calm_count := precip.leaves.amount * precip.leaves.amount_ratio
	var calm_wind := env.wind_strength
	var leaf_shape := ((precip.leaves.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_texture != null
	precip.profile_override = "legacy_red_motes"
	await _seconds(1.0)
	var legacy_count := precip.leaves.amount * precip.leaves.amount_ratio
	var legacy_kept := precip.leaves_kind == "legacy_red_motes" and precip.leaves.amount == 700 \
		and ((precip.leaves.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_texture == null
	precip.profile_override = ""
	await _seconds(1.0)
	var back := precip.leaves_kind == "leaves"
	_check("晴天落叶零星（原版红点保留为可切换方案）", calm_count < 120.0 and calm_count > 0.0 and leaf_shape and legacy_kept and legacy_count > calm_count * 3.0 and back,
		"秋天晴 %.0f 个（风 %.2f，叶形 %s）；原版红点 %.0f 个，保留 %s；切回 %s" % [calm_count, calm_wind, leaf_shape, legacy_count, legacy_kept, back])


func _test_fullscreen_and_world_map() -> void:
	var f11 := false
	for ev in InputMap.action_get_events("toggle_fullscreen"):
		f11 = f11 or (ev as InputEventKey).physical_keycode == KEY_F11
	GameSettings.set_value("fullscreen", true, false)
	var on := GameSettings.fullscreen
	GameSettings.set_value("fullscreen", false, false)
	# Alt + Enter 切全屏，不打开聊天框（Enter 单独按才是聊天）
	var alt_enter := _key(KEY_ENTER, true)
	alt_enter.alt_pressed = true
	Input.parse_input_event(alt_enter)
	Input.parse_input_event(_key(KEY_ENTER, false))
	await _frames(2)
	var chat := get_tree().get_first_node_in_group("chat_box") as ChatBox
	var alt_ok := GameSettings.fullscreen and (chat == null or not chat.is_open())
	GameSettings.set_value("fullscreen", false, false)
	on = on and alt_ok
	var wm := _main.get_node("WorldMap") as WorldMap
	var ev := InputEventAction.new()
	ev.action = "world_map"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	var opened := wm.open
	var cur := WorldRegistry.current()
	var planned := 0
	for w in WorldRegistry.worlds():
		if not WorldRegistry.is_open(str(w["id"])):
			planned += 1
	# 世界三还在规划中：进不去、只提示；世界二是“建设中可进入”（真正的往返在 _test_world_travel 里测）
	var blocked := not WorldRegistry.enter("world_03") and not WorldRegistry.can_enter("world_03") and WorldRegistry.can_enter("world_02")
	wm.toggle()
	await _frames(2)
	_check("F11 / Alt+Enter 全屏切换（不误开聊天）；Tab 打开世界地图，世界注册表含规划中的其他世界", f11 and on and opened and not wm.open \
		and str(cur.get("id", "")) == "dusk_lake" and planned >= 1 and blocked,
		"F11 %s，全屏 %s，地图打开 %s，当前 %s，规划中 %d 个，规划中的世界不能进、建设中的能进 %s" % [f11, on, opened, cur.get("name", "?"), planned, blocked])

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
	_min_y = minf(_min_y, p.y)
	_max_leg_swing = maxf(_max_leg_swing, _player.body.leg_swing_degrees())
	if _player.current_water != null:
		_waters_seen[_player.current_water.volume_id] = true


func _begin_track() -> void:
	_last_pos = _player.global_position
	_max_step = 0.0
	_min_clearance = INF
	_min_y = INF
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
	# 裂谷、河床的陡壁上 1 m 网格的三角面插值和解析高度本来就不同（谷底和谷沿上仍然逐点比较）
	for c in WorldTerrain.channels():
		if c["kind"] == "gorge":
			var d := WorldTerrain.channel_distance(x, z, "gorge") + float(c["inner"])
			if d > float(c["inner"]) - 1.0 and d < float(c["outer"]) + 1.0:
				return true
	for pit in WorldLayout.section("terrain").get("pits", []):
		var r: Array = pit["rect"]
		var outer := Rect2(float(r[0]) - 1.5, float(r[1]) - 1.5, float(r[2]) - float(r[0]) + 3.0, float(r[3]) - float(r[1]) + 3.0)
		var inner := Rect2(float(r[0]) + 1.5, float(r[1]) + 1.5, float(r[2]) - float(r[0]) - 3.0, float(r[3]) - float(r[1]) - 3.0)
		if outer.has_point(Vector2(x, z)) and not inner.has_point(Vector2(x, z)):
			return true
	return false


# ---------------------------------------------------------------- 第一人称双手的大小与右键

## 世界坐标 → 16:9 画面上的位置（0–1，左上为原点），按相机的竖直 FOV 自己算：无窗口时视口只有 64×64，不能用 unproject。
func _screen_frac(point: Vector3) -> Vector2:
	var cam := _player.camera
	var p := cam.global_transform.affine_inverse() * point
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var depth := maxf(-p.z, 0.001)
	return Vector2(0.5 + 0.5 * p.x / (depth * t * 16.0 / 9.0), 0.5 - 0.5 * p.y / (depth * t))


## 一只手臂（含拳头）在 16:9 画面上的包围盒（0–1）：网格包围盒的 8 个角投影。
func _arm_screen_rect(part: Node3D) -> Rect2:
	var r := Rect2()
	var first := true
	for mi: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
		var box := mi.get_aabb()
		for i in 8:
			var p := _screen_frac(mi.global_transform * box.get_endpoint(i))
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


func _test_hands_and_right_click() -> void:
	await _setup_at(Vector2(-50.0, 29.0), deg_to_rad(-70.0))
	_player.set_third_person(false)
	_player.head.rotation.x = 0.0
	var arms := _player.arms
	var view := Vector2.ONE
	arms.set_size(1.0)
	await _frames(4)
	var big_r := _arm_screen_rect(arms.model.parts["arm_r"]).intersection(Rect2(Vector2.ZERO, view))
	arms.set_size(GameSettings.hand_size)
	await _frames(4)
	var r := _arm_screen_rect(arms.model.parts["arm_r"]).intersection(Rect2(Vector2.ZERO, view))
	var l := _arm_screen_rect(arms.model.parts["arm_l"]).intersection(Rect2(Vector2.ZERO, view))
	var area := (r.get_area() + l.get_area()) / (view.x * view.y)
	var ratio := r.get_area() / maxf(big_r.get_area(), 1.0)
	var fist_r := _screen_frac((arms.model.parts["arm_r"].get_node("Fist") as Node3D).global_position)
	var fist_l := _screen_frac((arms.model.parts["arm_l"].get_node("Fist") as Node3D).global_position)
	var placed := fist_r.x > view.x * 0.62 and fist_l.x < view.x * 0.38 and fist_r.y > view.y * 0.6 and fist_l.y > view.y * 0.6 \
		and fist_r.y < view.y and fist_l.y < view.y
	# 包围盒（手臂斜着伸进来，盒子比手大）：都在画面下方 45% 以内，分别在左右两侧 40% 以内，中间一条不挡
	var center_clear := r.position.y > 0.55 and l.position.y > 0.55 and r.position.x > 0.6 and l.end.x < 0.4
	_check("第一人称双手默认缩小到一半：两只拳头分在左右下角，画面中央空出来", GameSettings.hand_size == 0.5 and area < 0.25 \
		and ratio < 0.4 and placed and center_clear,
		"双手包围盒共占画面 %.1f%%，右手是原大小的 %.0f%%，右手盒左边 %.0f%%、左手盒右边 %.0f%%、上沿 %.0f%%，右拳 (%.0f%%, %.0f%%) 左拳 (%.0f%%, %.0f%%)" % [area * 100.0, ratio * 100.0, r.position.x * 100.0, l.end.x * 100.0, minf(r.position.y, l.position.y) * 100.0,
			fist_r.x / view.x * 100.0, fist_r.y / view.y * 100.0, fist_l.x / view.x * 100.0, fist_l.y / view.y * 100.0])

	# 右键对着门 = 开门（和 E 一样），手往前一伸
	var door := _cabin.get_node("FrontDoor") as InteractableDoor
	door.set_open(false, true)
	var porch := Vector3.ZERO
	for s in WorldLayout.data().get("dev_spots", []):
		if str(s["name"]) == "木屋门廊":
			porch = Vector3(float(s["pos"][0]), float(s["pos"][1]), float(s["pos"][2]))
	_player.teleport_to(porch + Vector3(0.0, 0.05, 0.0), 270.0)
	await _seconds(0.5)
	_player.look_at_point(_cabin.to_global(Vector3(5.0, 1.3, 0.0)))
	await _frames(3)
	Input.parse_input_event(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	Input.parse_input_event(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	await _seconds(0.3)
	var door_ok := door.get_state() == "open"
	door.set_open(false, true)

	# 右键对着空处 = 挥右手（第一人称看得到，方块人也挥手），不切到第三人称；走动就停
	await _setup_at(Vector2(-50.0, 29.0), deg_to_rad(-70.0))
	_player.head.rotation.x = deg_to_rad(25.0)
	await _frames(3)
	var third_before := _player.third_person
	Input.parse_input_event(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	Input.parse_input_event(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	await _frames(6)
	var waving := arms.is_waving() and _player.emote == "wave" and _player.third_person == third_before
	await _seconds(3.0)
	var stopped := _player.emote == "" and not arms.is_waving()
	_player.head.rotation.x = 0.0
	_check("右键：对着门就开门，对着空处就挥右手（不切视角，挥完自己停）", door_ok and waving and stopped,
		"开门 %s · 挥手 %s · 挥完停下 %s" % [door_ok, waving, stopped])


func _mouse_button(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = get_viewport().get_visible_rect().size * 0.5
	return ev


# ---------------------------------------------------------------- 世界根节点不带位移旋转

## 编辑器里误拖根节点再保存会让整个世界倾斜（立牌飘在天上、船埋进地里、桥闪烁）：
## 场景文件里 Main 下的节点都不该写 transform，根节点和地形在编辑器里锁定；运行时也会放回原点。
func _test_world_anchor() -> void:
	var st := (load(MAIN_SCENE) as PackedScene).get_state()
	var with_transform := PackedStringArray()
	var locked := PackedStringArray()
	for i in st.get_node_count():
		for j in st.get_node_property_count(i):
			var prop := st.get_node_property_name(i, j)
			if prop == "transform" or prop == "position" or prop == "rotation":
				with_transform.append(str(st.get_node_path(i)))
			if prop == "metadata/_edit_lock_" and st.get_node_property_value(i, j) == true:
				locked.append(str(st.get_node_path(i)))
	# 运行时放回原点：拿一棵倾斜的假场景树试
	var root := Node3D.new()
	root.name = "TiltedRoot"
	root.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(37.6)), Vector3(0.0, 1.0, 0.0))
	var child := Node3D.new()
	child.name = "MovedChild"
	child.position = Vector3(3.0, 0.0, 0.0)
	root.add_child(child)
	var moved := Main.anchor_to_origin(root)
	var reset_ok := moved.size() == 2 and root.transform == Transform3D.IDENTITY and child.transform == Transform3D.IDENTITY
	root.free()
	_check("世界根节点在原点：Main.tscn 里不写位移旋转、根节点和地形在编辑器里锁定、运行时误存的倾斜会放回原点",
		with_transform.is_empty() and locked.has(".") and locked.has("./World") and reset_ok \
			and _main.transform.is_equal_approx(Transform3D.IDENTITY),
		"带 transform 的节点：%s · 锁定：%s · 放回 %s" % [", ".join(with_transform) if not with_transform.is_empty() else "无", ", ".join(locked), ", ".join(moved)])


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


# ---------------------------------------------------------------- 自动更新与仙境林地（夜里的特殊事件）

func _test_updater() -> void:
	var cmp_ok := Updater.compare_versions("0.3.1", "0.3.0") == 1 and Updater.compare_versions("v0.3.0", "0.3") == 0 \
		and Updater.compare_versions("0.2.9", "0.10.0") == -1 and Updater.compare_versions("1.0", "0.99.99") == 1
	var release := {"tag_name": "v0.4.0", "body": "notes", "assets": [
		{"name": "DuskLake.exe", "browser_download_url": "https://example.invalid/DuskLake.exe", "size": 1234},
		{"name": "DuskLake.exe.sha256", "browser_download_url": "https://example.invalid/DuskLake.exe.sha256", "size": 80}]}
	var r := Updater.read_release(release)
	var read_ok: bool = r.get("version", "") == "0.4.0" and r.get("size", 0) == 1234 and str(r.get("sha_url", "")).ends_with(".sha256")
	var draft := release.duplicate(true)
	draft["draft"] = true
	var no_asset := {"tag_name": "v0.5.0", "assets": [{"name": "other.zip", "browser_download_url": "x", "size": 1}]}
	var skip_ok := Updater.read_release(draft).is_empty() and Updater.read_release(no_asset).is_empty()
	# 下载核对：大小、SHA-256
	var path := ProjectSettings.globalize_path("user://updater_test.bin")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("dusk lake")
	f.close()
	var sha := FileAccess.get_sha256(path)
	var verify_ok := Updater.verify_file(path, 9, sha) == "" and Updater.verify_file(path, 10, "") != "" \
		and Updater.verify_file(path, 9, "00" + sha.substr(2)) != "" and Updater.verify_file(path + ".missing", 9, "") != ""
	DirAccess.remove_absolute(path)
	# 替换脚本：等进程、换文件、可选重启；中文路径和单引号要正确转义
	var s := Updater.update_script(4321, "D:/个人世界/it's/DuskLake.exe", "D:/个人世界/it's/DuskLake.exe.download", true)
	var s2 := Updater.update_script(4321, "C:/Games/DuskLake.exe", "C:/Games/DuskLake.exe.download", false)
	var script_ok := s.contains("Wait-Process -Id 4321") and s.contains("'D:\\个人世界\\it''s\\DuskLake.exe'") \
		and s.contains("Move-Item -LiteralPath $new -Destination $exe") and s.contains("Start-Process") and not s2.contains("Start-Process")
	var offline_ok := not Updater.can_self_update() and Updater.state != Updater.State.CHECKING
	_check("自动更新：版本比较、读取发布、核对下载、替换脚本；自动检查里不联网",
		cmp_ok and read_ok and skip_ok and verify_ok and script_ok and offline_ok,
		"比较 %s · 读取 %s · 跳过草稿/无附件 %s · 核对 %s · 脚本 %s · 不联网 %s" % [cmp_ok, read_ok, skip_ok, verify_ok, script_ok, offline_ok])



func _test_fairy_glade() -> void:
	var glade := get_tree().get_first_node_in_group("fairy_glade") as FairyGlade
	var climate := _main.get_node("Systems") as ClimateSystem
	if glade == null:
		_check("仙境林地已生成", false)
		return
	var rule_ok := FairyGlade.should_appear(22.0 * 60.0, &"CLEAR") and FairyGlade.should_appear(3.0 * 60.0, &"OVERCAST") \
		and not FairyGlade.should_appear(12.0 * 60.0, &"CLEAR") and not FairyGlade.should_appear(23.0 * 60.0, &"HEAVY_RAIN") \
		and not FairyGlade.should_appear(5.0 * 60.0, &"CLEAR")
	# 白天：看不见、没有碰撞、传送门不能用
	climate.jump_to_season(&"SUMMER")
	climate.set_weather(&"CLEAR", 0.0)
	climate.set_hour(12.0)
	await _seconds(3.0)
	var magic := glade.get_node("Magic") as Node3D
	var day_hidden := not glade.active and not magic.visible and (glade.get_node("Magic/Collision") as StaticBody3D).collision_layer == 0
	# 晴朗的夜里：长出来，碰撞和传送门打开，有提示
	var hud := _main.get_node("HUD")
	climate.set_hour(22.0)
	await _seconds(1.0)
	var toast: String = hud.toast_text()
	await _seconds(FairyGlade.GROW_SECONDS + 0.5)
	var night_on := glade.active and magic.visible and magic.scale.is_equal_approx(Vector3.ONE) \
		and (glade.get_node("Magic/Collision") as StaticBody3D).collision_layer == PhysicsLayers.WORLD
	var crystals := magic.find_children("Crystal*", "MeshInstance3D", false, false).size()
	var built := glade.mushrooms.size() >= 8 and glade.islands.size() == 3 and glade.portal != null and crystals >= 10
	var c := Vector2(glade.position.x, glade.position.z)
	var flat := 0.0
	for i in 16:
		var a := i * TAU / 16.0
		flat = maxf(flat, absf(WorldTerrain.height_at(c.x + cos(a) * 9.0, c.y + sin(a) * 9.0) - glade.position.y))
	_check("仙境林地是夜里的特殊事件：白天隐藏、晴夜长出来并提示（仙树、%d 朵蘑菇、%d 颗水晶、3 座小岛、传送门）" % [glade.mushrooms.size(), crystals],
		rule_ok and day_hidden and night_on and built and toast != "" and flat < 0.4,
		"规则 %s · 白天隐藏 %s · 夜里出现 %s · 提示「%s」· 9 m 内高差 %.2f m" % [rule_ok, day_hidden, night_on, toast, flat])
	# 沿新步道走进林地
	await _setup_at(Vector2(50.0, 84.0), -PI * 0.5)
	_begin_track()
	var ok := true
	for p in [Vector2(62.0, 88.0), Vector2(68.0, 88.0), Vector2(72.0, 88.0)]:
		ok = await _walk_to(p, 25.0) and ok
	_track = false
	var inside := WorldState.zones_of(_player.entity_id).has(&"fairy_glade")
	_check("沿仙境步道走进林地（区域 fairy_glade），连续步行", ok and inside and _max_step < MAX_STEP,
		"到达 %s，区域 %s，单帧最大位移 %.3f m" % [ok, inside, _max_step])
	# 看着传送门：对得准，门通往世界二且现在能去（真正按 E 会换世界，往返放在最后一项 _test_world_travel 里测）
	var gate := glade.portal.global_position
	_player.global_position = gate + Vector3(-2.2, -2.5, 0.0)
	_player.velocity = Vector3.ZERO
	await _seconds(0.6)
	_player.look_at_point(gate)
	await _frames(3)
	var focused := _player.focused_target() == glade.portal
	var used := glade.portal.target_world == "world_02" and WorldTravel.blocked_reason("world_02") == ""
	var portal_toast: String = glade.portal.get_prompt(_player)
	# 天亮：缩回去，碰撞关掉
	climate.set_hour(6.0)
	await _seconds(FairyGlade.GROW_SECONDS + 1.0)
	var gone := not glade.active and not magic.visible and (glade.get_node("Magic/Collision") as StaticBody3D).collision_layer == 0
	_check("月光石门对得准、通往世界二（现在可以进去）；天亮后仙境消失", focused and used and portal_toast != "" and gone,
		"对准 %s，能去世界二 %s，提示「%s」，天亮消失 %s" % [focused, used, portal_toast, gone])
	climate.apply_preset("Autumn_Dusk_Clear")
	await _setup_at(Vector2(-50.0, 29.0), 0.0)


func _test_snow_peak() -> void:
	var peak := get_tree().get_first_node_in_group("snow_peak") as SnowPeak
	if peak == null:
		_check("雪山已生成", false)
		return
	var terrain_cfg := WorldLayout.section("terrain")
	var snowline := float(terrain_cfg["snowline"])
	var top := WorldTerrain.height_at(peak.summit.x, peak.summit.y)
	var no_trees := Vegetation.tree_density(peak.summit.x, peak.summit.y) == 0.0 and Vegetation.tree_density(88.0, -105.0) == 0.0
	var mat := (_main.get_node("World/Terrain").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var shader_ok := mat != null and absf(float(mat.get_shader_parameter("snowline")) - snowline) < 0.01
	var massif := _main.find_child("SnowMassif", true, false) as MeshInstance3D
	var massif_ok := massif != null and massif.mesh.get_surface_count() == 2
	# 地图内的山体处处可走（坡度 < 1，即 45°）；湖岸和地图边缘的陡坡不算
	var worst := 0.0
	for x in range(48, 106, 3):
		for z in range(-106, -60, 3):
			if WorldTerrain.lake_radius(x, z) < 1.25:
				continue
			worst = maxf(worst, WorldTerrain.slope_at(x, z))
	_check("雪山：山顶 %.1f m（雪线 %.0f m 以上常年积雪），林线以上无树，坡度处处可走，背后有雪顶主峰远景" % [top, snowline],
		top > snowline + 8.0 and no_trees and shader_ok and massif_ok and worst < 0.95,
		"无树 %s · 地形雪线参数 %s · 远景主峰 %s · 山体最大坡度 %.2f" % [no_trees, shader_ok, massif_ok, worst])
	# 沿步道折返上山
	await _setup_at(Vector2(58.0, -92.0), 0.0)
	_begin_track()
	var ok := true
	for p in [Vector2(64.0, -101.0), Vector2(74.0, -97.0), Vector2(82.0, -106.0), Vector2(92.0, -104.0), Vector2(100.0, -107.0)]:
		ok = await _walk_to(p, 40.0) and ok
	_track = false
	var inside := WorldState.zones_of(_player.entity_id).has(&"snow_peak")
	var height := _player.global_position.y
	_check("沿雪山步道走上山顶（区域 snow_peak），连续步行", ok and inside and height > snowline + 8.0 and _max_step < MAX_STEP,
		"到达 %s，区域 %s，高度 %.1f m，单帧最大位移 %.3f m" % [ok, inside, height, _max_step])
	# 山顶长椅：坐下看湖，小雪在飘
	_player.global_position = peak.seat.exit_point() + Vector3(0.0, 0.2, 0.0)
	_player.velocity = Vector3.ZERO
	await _seconds(0.5)
	_player.sit(peak.seat)
	var sat := _player.seat == peak.seat
	_player.stand_up()
	var flurry_ok := peak.flurry != null and peak.flurry.emitting
	_check("山顶长椅可以坐，周围常年飘小雪", sat and flurry_ok, "坐下 %s · 小雪 %s" % [sat, flurry_ok])
	await _setup_at(Vector2(-50.0, 29.0), 0.0)
