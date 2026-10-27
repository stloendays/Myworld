class_name StoryDirector
extends Node
## 第一章「把光送回去」在暮色湖畔的收尾（世界观落地②，2026-10-26）。挂在 Main 下，每半秒看一次世界状态：
##   · 新星座：哪个世界的光送回去了（云海风灯 / 沙丘祭坛 / 海底尖塔），湖畔夜空就多一个星座（StarField 里带 requires 的）。
##     第一次在晴朗的夜里、人在室外时放一段过场：镜头隔着湖望向那片天，星一颗一颗亮起来、连上线（new_star）。
##   · 暮烬之夜：三盏灯都亮了以后，傍晚（日落前 30 分钟）到凌晨 4:30，湖面升起暮烬（EmberField），镜头跟着的那层
##     飘落物换成原版红点（legacy_red_motes，参数不改）。老图腾讲完最后一个故事以前，每天傍晚都有，开始时把天放晴；
##     讲完以后只在晴朗的秋夜回来。第一次飘起来时放一段过场（ember_night）。
##   · 终章：暮烬之夜接着「暮烬之夜」任务去找图腾，它讲完最后一个故事（DialoguePanel）就放终章过场（finale）：
##     篝火、升上天的暮烬、满天的星座、石头小屋自己亮起来的台灯，最后是第一章的标题；书桌上多了划船人的第四封信。
## 过场的镜头和字幕在 data/story/cutscenes.json；锚点（湖、山洞、图腾、小屋、看星星的位置）在 anchor() 里按布局算。
## 设置里关掉“剧情过场动画”时，只弹提示、直接把结果放进世界。联机访客不放（世界状态以房主为准）。
## 状态都在 WorldState.flags：star_<id>（新星座放过）、ember_night_seen、ember_night_heard、farewell_read、star_chart_done。

const LIGHTS := ["cloudsea_beacons", "dunes_altar", "atlantis_spire"]
const EMBER_PROFILE := "legacy_red_motes"
const EMBER_LEAD := 30.0      ## 日落前多少分钟开始
const EMBER_END := 270.0      ## 凌晨 4:30 结束
const REVEAL_SECONDS := 6.5
const GAP := 6.0              ## 一段过场放完，隔几秒才放下一段

var embers_on := false
var ember_field: EmberField = null
var star_id := ""             ## 正在放的新星座
var playing := ""             ## 正在放的过场 id
var _timer := 0.0
var _gap := 0.0


static func lights_done() -> bool:
	for k: String in LIGHTS:
		if not bool(WorldState.flags.get(k, false)):
			return false
	return true


static func heard() -> bool:
	return bool(WorldState.flags.get("ember_night_heard", false))


## 现在是不是暮烬飘起来的时刻（日落前 30 分钟到凌晨 4:30）。
static func ember_time(time_minutes: float, season: StringName) -> bool:
	var sunset := ClimateData.parse_time(str(ClimateData.season_profile(season).get("sunset", "18:00")))
	var t := fposmod(time_minutes, 1440.0)
	return t >= sunset - EMBER_LEAD or t < EMBER_END


## 暮烬之夜：三盏灯都亮了、在傍晚到凌晨之间；讲完最后一个故事以后只在晴朗的秋夜。
static func is_ember_night() -> bool:
	if not lights_done() or not ember_time(WorldState.time_minutes, WorldState.season_id):
		return false
	if not heard():
		return true
	return WorldState.season_id == &"AUTUMN" and WorldState.weather_id == &"CLEAR"


## 图腾这次要讲最后一个故事（暮烬正飘着、接了「暮烬之夜」、还没讲过）。
func finale_ready() -> bool:
	return embers_on and QuestLog.state_of("ember_night") == "active" and not heard()


func _ready() -> void:
	add_to_group("story_director")
	ember_field = EmberField.new()
	add_child(ember_field)
	if is_ember_night():
		_set_embers(true, true)


func _process(delta: float) -> void:
	_gap = maxf(_gap - delta, 0.0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var want := is_ember_night()
	if want != embers_on:
		_set_embers(want, false)
	if not bool(WorldState.flags.get("star_chart_done", false)) and StarField.extras().all(func(c: Dictionary) -> bool: return StarField.shown(c)):
		WorldState.flags["star_chart_done"] = true
	if playing != "" or _gap > 0.0 or Net.is_client():
		return
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if not _can_play(player):
		return
	if embers_on and not bool(WorldState.flags.get("ember_night_seen", false)):
		WorldState.flags["ember_night_seen"] = true
		_play("ember_night")
		return
	var pending := pending_star()
	if pending != "" and not WorldState.is_indoors(player.entity_id):
		var stars := get_tree().get_first_node_in_group("star_field") as StarField
		if stars != null and stars.visibility > 0.6:
			star_id = pending
			_play("new_star")


## 已经点亮、还没在湖畔夜空放出来的新星座（按数据顺序第一个）。
static func pending_star() -> String:
	for c: Dictionary in StarField.extras():
		if StarField.unlocked(c) and not StarField.shown(c):
			return str(c["id"])
	return ""


## 现在能不能放过场：人在、没开着别的界面（对话、信、棋盘、菜单都会锁住输入）、没有黑幕和别的过场、没暂停。
func _can_play(player: FirstPersonController) -> bool:
	if player == null or player.input_locked or get_tree().paused or BootLoader.active or Fade.is_black():
		return false
	if Cutscene.any_playing(get_tree()):
		return false
	var lobby := get_tree().get_first_node_in_group("lobby_menu") as LobbyMenu
	return lobby == null or not lobby.is_open()


## 暮烬开关：湖面的暮烬 + 镜头周围飘的原版红点；讲完故事以前，傍晚开始时把天放晴（“那天傍晚，云散了”）。
func _set_embers(on: bool, instant: bool) -> void:
	embers_on = on
	ember_field.set_active(on, instant)
	var precip := get_tree().get_first_node_in_group("precipitation") as Precipitation
	if precip != null:
		precip.story_profile = EMBER_PROFILE if on else ""
	if not on:
		return
	if not heard() and WorldState.weather_id != &"CLEAR":
		var weather := get_tree().get_first_node_in_group("weather_controller") as WeatherController
		if weather != null:
			weather.request_weather(&"CLEAR", 0.0 if instant else 40.0)
	if not instant and bool(WorldState.flags.get("ember_night_seen", false)):
		EventBus.toast_requested.emit(tr("湖上飘起了暮烬"))


## 放一段过场；设置里关掉了就直接给结果。
func _play(id: String) -> void:
	if not GameSettings.story_cutscenes:
		_cue(id)
		_after(id)
		return
	playing = id
	var vars := {"story": QuestLog.text(StarField.find(star_id), "story")} if id == "new_star" else {}
	var cs := Cutscene.run(get_parent(), id, anchor, _cue, vars)
	await cs.finished
	playing = ""
	_gap = GAP
	_after(id)


## 每段开头的提示：让星座亮起来、让暮烬一下子飘满、让所有星座的连线一起亮、让小屋的台灯亮。
func _cue(name: String) -> void:
	match name:
		"reveal", "new_star":
			var stars := get_tree().get_first_node_in_group("star_field") as StarField
			if stars != null and star_id != "" and stars.revealing == "":
				stars.reveal(star_id, REVEAL_SECONDS if name == "reveal" else 0.1)
		"embers", "ember_night":
			ember_field.set_active(true, true)
		"all_stars":
			var sky := get_tree().get_first_node_in_group("star_field") as StarField
			if sky != null:
				sky.highlight_all = true
		"cottage_lamp", "finale":
			_light_cottage()


func _after(id: String) -> void:
	match id:
		"new_star":
			var c := StarField.find(star_id)
			if not c.is_empty() and not StarField.shown(c):
				_cue("new_star")     # 过场在星座亮起之前就被跳过了：直接放出来
			if not GameSettings.story_cutscenes and not c.is_empty():
				EventBus.toast_requested.emit(tr("湖畔的夜空里多了一个星座：%s") % QuestLog.text(c, "name"))
			star_id = ""
			_refresh_chart()
		"ember_night":
			if not GameSettings.story_cutscenes:
				EventBus.toast_requested.emit(tr("湖上飘起了暮烬——山洞里的火，好像在叫你回去"))
		"finale":
			_light_cottage()
			var sky := get_tree().get_first_node_in_group("star_field") as StarField
			if sky != null:
				sky.highlight_all = false
			EventBus.toast_requested.emit(tr("任务更新：去石头小屋看看"))
	SaveManager.request_save()


## 图腾讲完最后一个故事（DialoguePanel 最后一页合上时调用）。
func finale_heard() -> void:
	if heard():
		return
	WorldState.flags["ember_night_heard"] = true
	SaveManager.request_save()
	_play("finale")


## 石头小屋的台灯自己亮了，书桌上多了一封信。
func _light_cottage() -> void:
	var cottage := get_tree().get_first_node_in_group("stone_cottage") as StoneCottage
	if cottage == null:
		return
	if cottage.lamp != null and not cottage.lamp.on:
		cottage.lamp.set_on(true)
	cottage.place_farewell()


func _refresh_chart() -> void:
	var cottage := get_tree().get_first_node_in_group("stone_cottage") as StoneCottage
	if cottage != null:
		cottage.refresh_chart()


# ---------------------------------------------------------------- 锚点

## 过场镜头的锚点（Cutscene 每帧来取）：Vector3 是位置，Transform3D 带朝向（偏移按它转）。
func anchor(name: String) -> Variant:
	match name:
		"lake":
			var c := WorldLayout.v2(WorldLayout.section("lake")["center"])
			return Vector3(c.x, WorldLayout.water_level(), c.y)
		"cave_mouth":
			var p := WorldLayout.v2((WorldLayout.section("cave")["centerline"] as Array)[0])
			return Vector3(p.x, WorldTerrain.height_at(p.x, p.y), p.y)
		"totem":
			var totem := get_tree().get_first_node_in_group("cave_totem") as Node3D
			return totem.global_transform if totem != null else null
		"cottage":
			var cottage := get_tree().get_first_node_in_group("stone_cottage") as Node3D
			return cottage.global_transform if cottage != null else null
		"stargaze", "sky", "sky_low":
			return _sky_anchor(name)
	return null


## 看新星座的位置：站在湖上、背对那片天 45 m（隔着湖望过去），离水面 2.5 m；sky 是星座中心，sky_low 是它下方的地平线。
func _sky_anchor(name: String) -> Vector3:
	var c := StarField.find(star_id)
	var dir := StarField.center_dir(c) if not c.is_empty() else Vector3(0.0, 0.5, -1.0).normalized()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var lake: Vector3 = anchor("lake")
	var eye := lake - flat * 45.0 + Vector3(0.0, 2.5, 0.0)
	match name:
		"sky":
			return eye + dir * 300.0
		"sky_low":
			return eye + flat * 300.0 + Vector3(0.0, 25.0, 0.0)
	return eye
