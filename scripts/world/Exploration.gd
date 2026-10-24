class_name Exploration
extends Node3D
## 探索点：world_layout.json → lake_pois 列出的地点（湖心小岛、码头尽头、北岸芦苇湾、东岸睡莲湾，以及西岭小瀑布、北岭裂谷）。
## 玩家（走路或划独木舟）进入某点的半径就算“发现”：记进 WorldState.discoveries，屏幕上弹出提示，
## 小地图上该点由问号变成金色标记。每个点的摆件（营火、帐篷、芦苇、睡莲）也在这里按布局生成。

const NATURE := "res://assets/imported/kenney/nature/"

var _timer := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for poi in pois():
		for prop in poi.get("props", []):
			_place_prop(prop)
		if poi.has("scatter"):
			_scatter(poi)


static func pois() -> Array:
	return WorldLayout.data().get("lake_pois", [])


static func poi_label(poi: Dictionary) -> String:
	# 英文界面只显示英文名；中文界面中英并列
	if TranslationServer.get_locale().begins_with("en") and str(poi.get("name_en", "")) != "":
		return str(poi["name_en"])
	return "%s %s" % [poi["name"], poi.get("name_en", "")]


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player != null:
		check(Vector2(player.global_position.x, player.global_position.z))


## 检查某点附近有没有新地点；返回这次新发现的 id 列表。
func check(at: Vector2) -> Array[StringName]:
	var found: Array[StringName] = []
	var list := pois()
	for poi in list:
		var id := StringName(poi["id"])
		if at.distance_to(WorldLayout.v2(poi["center"])) <= float(poi["radius"]) and WorldState.discover(id):
			found.append(id)
			EventBus.toast_requested.emit(tr("发现：%s（%d / %d）") % [poi_label(poi), WorldState.discoveries.size(), list.size()])
	return found


## 单个摆件：{"asset", "pos": [x, z], "yaw", "scale", "float": true 表示浮在水面}
func _place_prop(prop: Dictionary) -> void:
	var p := WorldLayout.v2(prop["pos"])
	var y := WorldLayout.water_level() + 0.02 if prop.get("float", false) else WorldTerrain.height_at(p.x, p.y)
	var node := ArtMaterials.kenney_prop(NATURE + str(prop["asset"]) + ".glb", Vector3(p.x, y, p.y), float(prop.get("yaw", 0.0)), float(prop.get("scale", 3.0)))
	add_child(node)


## 成片撒：芦苇长在浅水和岸边（水深在 depth 范围内），睡莲浮在水面上。固定种子，每次一样。
func _scatter(poi: Dictionary) -> void:
	var s: Dictionary = poi["scatter"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(poi["id"]))
	var c := WorldLayout.v2(poi["center"])
	var water := WorldLayout.water_level()
	var depth: Array = s["depth"]
	var assets: Array = s["assets"]
	var placed := 0
	var tries := 0
	while placed < int(s["count"]) and tries < int(s["count"]) * 30:
		tries += 1
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(poi["radius"])
		var d := water - WorldTerrain.height_at(p.x, p.y)
		if d < float(depth[0]) or d > float(depth[1]):
			continue
		var floating := bool(s.get("float", false))
		var y := water + 0.02 if floating else WorldTerrain.height_at(p.x, p.y)
		var scale := rng.randf_range(float(s["scale"][0]), float(s["scale"][1]))
		var node := ArtMaterials.kenney_prop(NATURE + str(assets[rng.randi() % assets.size()]) + ".glb", Vector3(p.x, y, p.y), rng.randf() * 360.0, scale)
		add_child(node)
		placed += 1
