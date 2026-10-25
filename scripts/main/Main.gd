class_name Main
extends Node3D
## 主场景：常驻 World（地形/湖/林/码头/光照）、Cabin、Player 与 UI。
## 室内与室外在同一个场景、同一坐标系；全工程没有任何场景切换调用（tests/ 会扫描确认）。
## 启动时把本地玩家放到 world_layout.json → spawn，并创建聊天框（ChatBox）、其他玩家容器（RemotePlayers）
## 和大厅菜单（LobbyMenu：作为游戏主程序启动时弹出单人 / 建房 / 加入）。


## 子节点（地形、树林、地被）开始建造之前，先在后台并行读取它们要用的几十个 Kenney 模型。
func _enter_tree() -> void:
	add_to_group("world_root")
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
			player.teleport_to(Vector3(float(a["pos"][0]), float(a["pos"][1]), float(a["pos"][2])), float(a.get("heading", 0.0)))
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
