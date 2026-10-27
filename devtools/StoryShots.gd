extends Node
## 开发工具：把剧情过场一段一段放出来，每段放到 60 % 时截一张图（带黑边和字幕），输出到 docs/screenshots/story_*.png。
##   Godot_console.exe --path . --resolution 1600x900 --position 100000,100000 res://devtools/StoryShots.tscn [-- 名称前缀（逗号分隔可多个）]
## 湖畔：new_star（点亮云海后的晴夜）、ember_night（三盏灯都亮后的傍晚）、finale（暮烬之夜图腾讲完故事），
## 外加图腾最后一页对话、补完的星图、书桌上的信；然后依次进云海浮岛、琥珀沙丘、亚特兰蒂斯，把那里的光送回去，拍点亮的过场。
## 截图期间时间暂停（光照固定）。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const OUT_DIR := "res://docs/screenshots"
const AT := 0.6

var _main: Node3D
var _prefix := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameSettings.set_value("fullscreen", false, false)
	GameSettings.set_value("story_cutscenes", true, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if not OS.get_cmdline_user_args().is_empty():
		_prefix = OS.get_cmdline_user_args()[0]
	QuestLog.persist = false
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	await _wait(120)
	(_main.get_node("DebugOverlay") as CanvasLayer).visible = false
	var story := _main.get_node("StoryDirector") as StoryDirector
	story.set_process(false)          # 由本工具决定放什么，不让它自己按时间触发
	var climate := _main.get_node("Systems") as ClimateSystem

	# 新星座：夏夜 23 点，晴
	if _want("story_new_star"):
		_climate(climate, &"SUMMER", 23.0)
		WorldState.flags["cloudsea_beacons"] = true
		await _wait(90)
		story.star_id = "sky_whale"
		var vars := {"story": QuestLog.text(StarField.find("sky_whale"), "story")}
		await _shoot(Cutscene.run(_main, "new_star", story.anchor, story._cue, vars), "story_new_star")
		story.star_id = ""
	for id in ["sky_whale", "stone_arch", "manta"]:
		WorldState.flags["star_" + id] = true
		WorldState.journal_add("constellations", id)
	for k in StoryDirector.LIGHTS:
		WorldState.flags[k] = true

	# 暮烬之夜：夏天日落前 5 分钟
	if _want("story_ember"):
		var sunset := ClimateData.parse_time(str(ClimateData.season_profile(&"SUMMER")["sunset"]))
		_climate(climate, &"SUMMER", (sunset - 5.0) / 60.0)
		story._set_embers(true, true)
		await _wait(90)
		await _shoot(Cutscene.run(_main, "ember_night", story.anchor, story._cue), "story_ember")

	# 终章：秋夜 21:30，晴，暮烬飘着；先拍图腾最后一页对话
	if _want("story_finale"):
		_climate(climate, &"AUTUMN", 21.5)
		story._set_embers(true, true)
		WorldState.quests["ember_night"] = {"state": "active", "progress": 0}
		WorldState.flags["met_totem"] = true
		await _wait(90)
		var cave := get_tree().get_first_node_in_group("cave") as Cave
		var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
		var t := cave.totem.global_position + cave.totem.global_basis.z * 4.2
		player.teleport_to(Vector3(t.x, t.y + 0.1, t.z), rad_to_deg(cave.totem.global_rotation.y) + 180.0)
		await _wait(30)
		player.look_at_point(cave.totem.global_position + Vector3(0.0, 2.2, 0.0))
		var dialogue := _main.get_node("DialoguePanel") as DialoguePanel
		dialogue.open_totem(cave.totem, player)
		dialogue.page_index = dialogue.pages.size() - 2
		dialogue._show_page()
		await _wait(200)
		_save("story_finale_00_totem")
		dialogue.close()
		WorldState.flags["ember_night_heard"] = true
		await _shoot(Cutscene.run(_main, "finale", story.anchor, story._cue), "story_finale")
		# 书桌上的信、补完的星图
		var letters := _main.get_node("LetterPanel") as LetterPanel
		letters.open_letter(PaddlerStory.FAREWELL, player)
		await _wait(20)
		_save("story_finale_06_letter")
		letters.close()
		letters.open_chart(player)
		await _wait(20)
		_save("story_finale_07_chart")
		letters.close()
		var cottage := get_tree().get_first_node_in_group("stone_cottage") as StoneCottage
		var desk := cottage.to_global(Vector3(1.6, StoneCottage.FLOOR + 1.62, -0.75))
		player.teleport_to(cottage.to_global(Vector3(1.6, StoneCottage.FLOOR + 0.05, -0.55)))
		await _wait(20)
		player.camera.current = true
		player.look_at_point(cottage.to_global(StoneCottage.FAREWELL + Vector3(-0.2, 0.0, -0.1)))
		await _wait(40)
		_save("story_finale_08_desk")
		story._set_embers(false, true)

	# 其他世界：把光送回去的那一刻
	for spec: Array in [["world_02", "story_cloudsea", "cloudsea_beacons"], ["world_03", "story_dunes", "dunes_altar"], ["world_04", "story_atlantis", "atlantis_spire"]]:
		if not _want(str(spec[1])):
			continue
		WorldState.flags.erase(str(spec[2]))
		if _main.is_inside_tree():
			remove_child(_main)
		var w := (load(str(WorldRegistry.get_world(str(spec[0]))["scene"])) as PackedScene).instantiate() as MiniWorld
		add_child(w)
		await _wait(90)
		if w is World02:
			for b in (w as World02).beacons:
				b.set_lit(true)
		elif w is World03:
			(w as World03).altar.apply_state("placed:6")
		elif w is World04:
			(w as World04)._set_puzzle(true, false)
		await _wait(2)
		var cs: Cutscene = null
		for c in get_tree().get_nodes_in_group("cutscene"):
			cs = c
		await _shoot(cs, str(spec[1]))
		w.queue_free()
		await _wait(2)
	# 湖畔放回树里再退出，由场景树正常释放（留在树外退出时引擎会崩）
	if not _main.is_inside_tree():
		add_child(_main)
		await _wait(2)
	get_tree().quit()


func _want(name: String) -> bool:
	if _prefix == "":
		return true
	for p in _prefix.split(","):
		if name.begins_with(p) or p.begins_with(name):
			return true
	return false


func _climate(climate: ClimateSystem, season: StringName, hour: float) -> void:
	WorldState.time_paused = false
	climate.jump_to_season(season)
	climate.set_hour(hour)
	climate.set_weather(&"CLEAR", 0.0)
	WorldState.ground_wetness = 0.0
	WorldState.rain_recent = 0.0
	WorldState.time_paused = true


## 每段放到 AT 时截一张：<名字>_<段号>.png；放完等它收尾。
func _shoot(cs: Cutscene, name: String) -> void:
	if cs == null:
		push_warning("StoryShots: %s 没有过场" % name)
		return
	var shots: Array = []
	var taken := {}
	while is_instance_valid(cs) and (cs.playing or cs.shot_index < 0):
		await get_tree().process_frame
		if not is_instance_valid(cs) or cs.shot_index < 0:
			continue
		if shots.is_empty():
			shots = Cutscene.shots_of(str(cs.name).trim_prefix("Cutscene_"))
		var i := cs.shot_index
		if not taken.has(i) and i < shots.size() and cs.shot_t >= float((shots[i] as Dictionary).get("seconds", 6.0)) * AT:
			taken[i] = true
			_save("%s_%02d" % [name, i + 1])
	await _wait(60)


func _save(name: String) -> void:
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
