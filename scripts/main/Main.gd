class_name Main
extends Node3D
## 主场景：常驻 World（地形/湖/林/码头/光照）、Cabin、Player 与 UI。
## 室内与室外在同一个场景、同一坐标系；全工程没有任何场景切换调用（tests/ 会扫描确认）。
## 启动时把本地玩家放到 world_layout.json → spawn，并创建聊天框（ChatBox）、其他玩家容器（RemotePlayers）
## 和大厅菜单（LobbyMenu：作为游戏主程序启动时弹出单人 / 建房 / 加入）。


var batch_stats := {}   ## 静态合批的结果：{"meshes": 并掉的网格数, "batches": 合成的网格数}


## 子节点（地形、树林、地被）开始建造之前，先在后台并行读取它们要用的几十个 Kenney 模型。
func _enter_tree() -> void:
	add_to_group("world_root")
	WorldTravel.current_world = "dusk_lake"
	WorldState.flags["visited_dusk_lake"] = true
	var moved := anchor_to_origin(self)
	if not moved.is_empty():
		push_warning("Main: 场景文件里这些节点带了位移或旋转，已放回原点：%s（多半是在编辑器里误拖后保存了）" % ", ".join(moved))
	ArtMaterials.preload_kenney(ForestBuilder.asset_paths() + GroundCoverBuilder.asset_paths())


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player != null:
		place_at_spawn(player)
		# 从别的世界回来：站在来时那道门前（worlds.json → arrivals）
		var a := WorldTravel.arrival()
		if not a.is_empty():
			var p := Vector3(float(a["pos"][0]), float(a["pos"][1]), float(a["pos"][2]))
			if a.get("ground", false):
				p.y = WorldTerrain.height_at(p.x, p.z) + 0.2
			player.teleport_to(p, float(a.get("heading", 0.0)))
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var remote := RemotePlayers.new()
	remote.name = "RemotePlayers"
	add_child(remote)
	var chat := ChatBox.new()
	chat.name = "ChatBox"
	add_child(chat)
	var lobby := LobbyMenu.new()
	lobby.name = "LobbyMenu"
	add_child(lobby)
	var dialogue := DialoguePanel.new()
	dialogue.name = "DialoguePanel"
	add_child(dialogue)
	var journal := JournalPanel.new()
	journal.name = "JournalPanel"
	add_child(journal)
	var gate := DuneGate.new()
	gate.name = "DuneGate"
	add_child(gate)
	var compass := CompassBar.new()
	compass.name = "CompassBar"
	add_child(compass)
	var play := PlayActivities.new()
	play.name = "PlayActivities"
	add_child(play)
	var cooking := CookingPanel.new()
	cooking.name = "CookingPanel"
	add_child(cooking)
	var story := PaddlerStory.new()
	story.name = "PaddlerStory"
	add_child(story)
	var letters := LetterPanel.new()
	letters.name = "LetterPanel"
	add_child(letters)
	var director := StoryDirector.new()
	director.name = "StoryDirector"
	add_child(director)
	_merge_static.call_deferred()


## 静态合批（StaticBatch）：等所有建造（包括延后一帧的）做完，把建筑、码头、小溪、卷轴木架这些不会动的小网格并起来。
## 玩家、其他玩家、小动物、树林和地被（已经是 MultiMesh）、远景（几个大网格，按名字重建）不碰。
func _merge_static() -> void:
	await get_tree().process_frame
	var skip := []
	for path in ["Player", "World/Fauna", "World/Forest", "World/GroundCover", "World/Backdrop", "RemotePlayers"]:
		skip.append(get_node_or_null(path))
	skip.append_array(get_tree().get_nodes_in_group("local_player"))
	var t := Time.get_ticks_usec()
	var s := StaticBatch.merge_all(get_tree(), [self], skip)
	ArtMaterials.warm_snow_overlay()
	print_verbose("StaticBatch: %d 个网格并成 %d 个，%.0f ms" % [s["meshes"], s["batches"], (Time.get_ticks_usec() - t) / 1000.0])
	batch_stats = s


## 世界坐标就是 Main 的坐标：Main 自己和它下面的 3D 节点在场景文件里都不该带位移或旋转——
## 位置全部来自 world_layout.json（木屋、泳池馆等在各自的 _enter_tree 里按布局摆放，玩家在 _ready 里放到出生点）。
## 编辑器里误拖了根节点再保存，整个世界会倾斜：地形、桥跟着斜，按世界坐标摆的立牌、船却没斜，
## 于是立牌飘在天上、船埋进地里、桥和溪水交错闪烁（2026-10-24 用户遇到过）。这里在子节点摆放之前统一放回原点，
## 返回被放回去的节点名。子节点的 _enter_tree 在本函数之后才运行，所以按布局摆放的节点不受影响。
static func anchor_to_origin(root: Node3D) -> PackedStringArray:
	var moved := PackedStringArray()
	if not root.transform.is_equal_approx(Transform3D.IDENTITY):
		moved.append(String(root.name))
		root.transform = Transform3D.IDENTITY
	for c in root.get_children():
		if c is Node3D and not (c as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
			moved.append(String(c.name))
			(c as Node3D).transform = Transform3D.IDENTITY
	return moved


static func place_at_spawn(player: FirstPersonController) -> void:
	var spawn := WorldLayout.section("spawn")
	var p := WorldLayout.v2(spawn["position"])
	var y := WorldTerrain.height_at(p.x, p.y) + 0.2
	player.global_position = Vector3(p.x, y, p.y)
	player.velocity = Vector3.ZERO
	if spawn.has("look_at"):
		var t := WorldLayout.v2(spawn["look_at"])
		player.look_at_point(Vector3(t.x, y + 1.65, t.y))


## 罗盘和小地图用的标记：探索点（发现了没有）和两道光门（山洞尽头去云海浮岛、南部草甸的沙之门去琥珀沙丘）。
func map_markers() -> Array:
	var out := []
	for poi in Exploration.pois():
		out.append({"pos": WorldLayout.v2(poi["center"]), "kind": "poi", "done": StringName(poi["id"]) in WorldState.discoveries, "label": str(poi["name"])})
	var cave := WorldLayout.section("cave")
	if cave.has("portal"):
		out.append({"pos": WorldLayout.v2(cave["portal"]["pos"]), "kind": "gate", "done": false, "label": "光门"})
	var dune := WorldLayout.section("dune_gate")
	if not dune.is_empty():
		out.append({"pos": WorldLayout.v2(dune["center"]), "kind": "gate", "done": false, "label": "沙之门"})
	return out


## 钓鱼、打水漂用：湖面（离岸线不远、水深超过 35 cm 的地方）。其他世界见 MiniWorld.water_at。
func water_at(x: float, z: float) -> Dictionary:
	var water := WorldLayout.water_level()
	if WorldTerrain.lake_radius(x, z) < 1.2 and WorldTerrain.height_at(x, z) < water - 0.35:
		return {"id": "lake", "y": water, "fish": "lake"}
	return {}
