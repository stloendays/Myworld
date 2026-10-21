class_name Main
extends Node3D
## 主场景：常驻 World（地形/湖/林/码头/光照）、Cabin、Player 与 UI。
## 室内与室外在同一个场景、同一坐标系；全工程没有任何场景切换调用（tests/ 会扫描确认）。
## 启动时把本地玩家放到 world_layout.json → spawn，并创建聊天框（ChatBox）、其他玩家容器（RemotePlayers）
## 和大厅菜单（LobbyMenu：作为游戏主程序启动时弹出单人 / 建房 / 加入）。


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player != null:
		place_at_spawn(player)
	if DisplayServer.get_name() != "headless":
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


static func place_at_spawn(player: FirstPersonController) -> void:
	var spawn := WorldLayout.section("spawn")
	var p := WorldLayout.v2(spawn["position"])
	var y := WorldTerrain.height_at(p.x, p.y) + 0.2
	player.global_position = Vector3(p.x, y, p.y)
	player.velocity = Vector3.ZERO
	if spawn.has("look_at"):
		var t := WorldLayout.v2(spawn["look_at"])
		player.look_at_point(Vector3(t.x, y + 1.65, t.y))
