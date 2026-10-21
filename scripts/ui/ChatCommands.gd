class_name ChatCommands
extends RefCounted
## 聊天框里以 / 开头的命令（/help 列出全部）。命令只调用已有系统的公开入口
## （ClimateSystem、WorldState、WorldTerrain、WorldLayout），不另存状态；结果和错误都写回聊天框。

const HELP := [
	["/help", "列出命令"],
	["/time [时:分]", "查看或设置时刻，如 /time 18:30"],
	["/weather [天气]", "查看或切换天气：晴 阴 小雨 大雨 雷雨 雾 下雪"],
	["/season [季节]", "查看或跳到某季：春 夏 秋 冬"],
	["/preset [名称]", "应用天气预设；不带名称列出全部"],
	["/pos", "当前坐标与所在区域"],
	["/tp <x> <z> | /tp 出生点", "传送到室外地面（不能传进建筑）"],
	["/name <名字>", "修改聊天名字"],
	["/me <动作>", "以第三人称描述动作"],
	["/clear", "清空聊天记录"],
]
const TP_MARGIN := 105.0   ## 传送范围 |x|、|z| 上限（再往外是地图边缘的陡坡）


static func run(chat: ChatBox, line: String) -> void:
	var parts := line.substr(1).strip_edges().split(" ", false)
	if parts.is_empty():
		chat.post_error(chat.tr("空命令。输入 /help 查看命令。"))
		return
	var cmd := parts[0].to_lower()
	var arg := " ".join(parts.slice(1)).strip_edges()
	match cmd:
		"help", "?", "帮助":
			for h in HELP:
				chat.post_system("%s — %s" % [chat.tr(h[0]), chat.tr(h[1])])
		"time", "时间":
			_time(chat, arg)
		"weather", "天气":
			_weather(chat, arg)
		"season", "季节":
			_season(chat, arg)
		"preset", "预设":
			_preset(chat, arg)
		"pos", "坐标":
			_pos(chat)
		"tp", "传送":
			_tp(chat, parts.slice(1))
		"name", "名字":
			if chat.set_player_name(arg):
				chat.post_system(chat.tr("聊天名字已改为 %s。") % chat.player_name)
			else:
				chat.post_error(chat.tr("名字需要 1–%d 个字。") % ChatBox.MAX_NAME_LENGTH)
		"me":
			if arg.is_empty():
				chat.post_error(chat.tr("用法：/me <动作>"))
			else:
				var emote := "* %s %s" % [chat.player_name, arg]
				chat.post("emote", chat.player_name, emote)
				Net.send_chat("emote", emote)
		"clear", "清屏":
			chat.clear()
		_:
			chat.post_error(chat.tr("未知命令 /%s。输入 /help 查看命令。") % cmd)


static func _climate(chat: ChatBox) -> ClimateSystem:
	return chat.get_tree().get_first_node_in_group("climate_system") as ClimateSystem


static func _player(chat: ChatBox) -> FirstPersonController:
	return chat.get_tree().get_first_node_in_group("local_player") as FirstPersonController


## 联机时时间、天气、季节以房主为准：访客改了也会被房主的同步盖回去，所以直接拦下。
static func _guest_blocked(chat: ChatBox) -> bool:
	if Net.is_client():
		chat.post_error(chat.tr("只有房主可以改时间、天气和季节。"))
		return true
	return false


static func _time(chat: ChatBox, arg: String) -> void:
	if arg.is_empty():
		chat.post_system(chat.tr("现在是第 %d 天 %s。") % [WorldState.world_day, ClimateData.format_time(WorldState.time_minutes)])
		return
	if _guest_blocked(chat):
		return
	var hm := arg.replace("：", ":").split(":")
	var ok := hm.size() <= 2 and hm[0].is_valid_int() and (hm.size() == 1 or hm[1].is_valid_int())
	var h := hm[0].to_int() if ok else -1
	var m := (hm[1].to_int() if hm.size() > 1 else 0) if ok else -1
	if not ok or h < 0 or h > 23 or m < 0 or m > 59 or _climate(chat) == null:
		chat.post_error(chat.tr("用法：/time 时:分，例如 /time 18:30"))
		return
	_climate(chat).set_hour(h + m / 60.0)
	chat.post_system(chat.tr("时间设为 %s。") % ClimateData.format_time(WorldState.time_minutes))


static func _weather(chat: ChatBox, arg: String) -> void:
	if arg.is_empty():
		var now: String = chat.tr(ClimateData.weather_profile(WorldState.weather_id).get("name", String(WorldState.weather_id)))
		chat.post_system(chat.tr("现在是%s。可选：%s") % [now, " ".join(_names(ClimateData.WEATHER_IDS, false))])
		return
	if _guest_blocked(chat):
		return
	var id := _find_id(ClimateData.WEATHER_IDS, arg, false)
	if id == &"":
		chat.post_error(chat.tr("没有“%s”这种天气。可选：%s") % [arg, " ".join(_names(ClimateData.WEATHER_IDS, false))])
		return
	var name: String = chat.tr(ClimateData.weather_profile(id).get("name", String(id)))
	if not ClimateData.is_allowed(WorldState.season_id, id):
		chat.post_error(chat.tr("%s季不会出现%s。") % [chat.tr(ClimateData.season_profile(WorldState.season_id).get("name", "")), name])
		return
	if _climate(chat) != null and _climate(chat).set_weather(id):
		chat.post_system(chat.tr("天气正在转为%s…") % name)


static func _season(chat: ChatBox, arg: String) -> void:
	var ids := ClimateData.season_order()
	if arg.is_empty():
		chat.post_system(chat.tr("现在是%s季（第 %d 天）。") % [chat.tr(ClimateData.season_profile(WorldState.season_id).get("name", "")), WorldState.world_day])
		return
	if _guest_blocked(chat):
		return
	var id := _find_id(ids, arg.trim_suffix("季").trim_suffix("天"), true)
	if id == &"" or _climate(chat) == null:
		chat.post_error(chat.tr("没有“%s”这个季节。可选：%s") % [arg, " ".join(_names(ids, true))])
		return
	_climate(chat).jump_to_season(id)
	chat.post_system(chat.tr("跳到%s季第一天。") % chat.tr(ClimateData.season_profile(id).get("name", "")))


static func _preset(chat: ChatBox, arg: String) -> void:
	var presets: Array = ClimateData.weather().get("presets", {}).keys()
	if arg.is_empty():
		chat.post_system(chat.tr("预设：") + " ".join(presets))
		return
	if _guest_blocked(chat):
		return
	for p in presets:
		if str(p).to_lower() == arg.to_lower():
			_climate(chat).apply_preset(str(p))
			chat.post_system(chat.tr("已应用预设 %s。") % p)
			return
	chat.post_error(chat.tr("没有预设“%s”。输入 /preset 列出全部。") % arg)


static func _pos(chat: ChatBox) -> void:
	var p := _player(chat)
	if p == null:
		return
	var at := p.global_position
	var zones := PackedStringArray()
	for z in WorldState.zones_of(p.entity_id):
		zones.append(zone_name(StringName(z)))
	chat.post_system(chat.tr("坐标 x %.1f  y %.1f  z %.1f%s") % [at.x, at.y, at.z, ("  ·  " + "、".join(zones)) if not zones.is_empty() else ""])


static func _tp(chat: ChatBox, args: Array) -> void:
	var p := _player(chat)
	if p == null:
		return
	var target := Vector2.INF
	if args.size() == 1 and str(args[0]) in ["出生点", "spawn"]:
		target = WorldLayout.v2(WorldLayout.section("spawn")["position"])
	elif args.size() == 2 and str(args[0]).is_valid_float() and str(args[1]).is_valid_float():
		target = Vector2(str(args[0]).to_float(), str(args[1]).to_float())
	if target == Vector2.INF:
		chat.post_error(chat.tr("用法：/tp <x> <z> 或 /tp 出生点"))
		return
	var why := tp_blocked_reason(target)
	if why != "":
		chat.post_error(chat.tr("不能传送到 (%.1f, %.1f)：%s。") % [target.x, target.y, why])
		return
	p.global_position = Vector3(target.x, WorldTerrain.height_at(target.x, target.y) + 0.2, target.y)
	p.velocity = Vector3.ZERO
	chat.post_system(chat.tr("已传送到 (%.1f, %.1f)。") % [target.x, target.y])


## 传送只到室外地面：不出地图、不进湖、不进建筑（进屋必须走门）。返回空串表示可以。
static func tp_blocked_reason(xz: Vector2) -> String:
	if absf(xz.x) > TP_MARGIN or absf(xz.y) > TP_MARGIN:
		return TranslationServer.translate("超出地图（|x|、|z| ≤ %d）") % int(TP_MARGIN)
	for k in WorldLayout.data().get("keepouts", []):
		var r: Array = k["rect"]
		if xz.x >= r[0] and xz.x <= r[2] and xz.y >= r[1] and xz.y <= r[3]:
			return TranslationServer.translate("那里是建筑（%s），请从门进去") % zone_name(StringName(k["id"]))
	if WorldTerrain.height_at(xz.x, xz.y) < WorldLayout.water_level():
		return TranslationServer.translate("那里是湖面")
	return ""


## 区域名（按当前语言）：先查 world_layout.json → zones，再查建筑段的常用名，都没有就用 id。
static func zone_name(zone_id: StringName) -> String:
	for z in WorldLayout.zones():
		if StringName(z.get("zone_id", "")) == zone_id:
			return TranslationServer.translate(str(z.get("name", zone_id)))
	match zone_id:
		&"cabin":
			return TranslationServer.translate("木屋")
		&"poolhouse":
			return TranslationServer.translate("泳池馆")
	return String(zone_id)


static func _names(ids: Array, season: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		var prof := ClimateData.season_profile(StringName(id)) if season else ClimateData.weather_profile(StringName(id))
		out.append(TranslationServer.translate(str(prof.get("name", id))))
	return out


## 按 id（不分大小写）或中文名找天气 / 季节 id，找不到返回 &""。
static func _find_id(ids: Array, arg: String, season: bool) -> StringName:
	for id in ids:
		var prof := ClimateData.season_profile(StringName(id)) if season else ClimateData.weather_profile(StringName(id))
		if String(id).to_lower() == arg.to_lower() or str(prof.get("name", "")) == arg \
				or TranslationServer.translate(str(prof.get("name", ""))).to_lower() == arg.to_lower():
			return StringName(id)
	return &""
