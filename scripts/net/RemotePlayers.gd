class_name RemotePlayers
extends Node3D
## 房间里其他玩家的容器（Main 启动时创建，组 remote_players）。Net 调用 add / remove / set_pose / update_info / clear。
## 名字标签画在屏幕上（2D Label 投影到人物头顶），不在三维空间放文字——三维里的文字只出现在立牌上。

const TAG_RANGE := 60.0

var _players := {}   ## peer_id -> RemotePlayer
var _tags := {}      ## peer_id -> Label
var _layer: CanvasLayer


func _ready() -> void:
	add_to_group("remote_players")
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)


func add(id: int, info: Dictionary) -> void:
	if _players.has(id):
		update_info(id, info)
		return
	var p := RemotePlayer.new()
	add_child(p)
	p.setup(id, info)
	_players[id] = p
	var tag := Label.new()
	tag.theme = GameSettings.ui_theme()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font_size = 18
	ls.outline_size = 6
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.7)
	tag.label_settings = ls
	tag.text = p.display_name
	_layer.add_child(tag)
	_tags[id] = tag


func remove(id: int) -> void:
	if _players.has(id):
		(_players[id] as Node).queue_free()
		_players.erase(id)
	if _tags.has(id):
		(_tags[id] as Node).queue_free()
		_tags.erase(id)


func clear() -> void:
	for id in _players.keys():
		remove(id)


func update_info(id: int, info: Dictionary) -> void:
	if _players.has(id):
		(_players[id] as RemotePlayer).update_info(info)
		(_tags[id] as Label).text = (_players[id] as RemotePlayer).display_name


func set_pose(id: int, pose: Array) -> void:
	if _players.has(id) and pose.size() >= 5 and pose[0] is Vector3:
		(_players[id] as RemotePlayer).set_pose(pose)


func get_player(id: int) -> RemotePlayer:
	return _players.get(id)


func count() -> int:
	return _players.size()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for id in _players:
		var p: RemotePlayer = _players[id]
		var tag: Label = _tags[id]
		var head := p.head_position()
		var show := cam != null and p.visible and not cam.is_position_behind(head) \
				and cam.global_position.distance_to(head) < TAG_RANGE
		tag.visible = show
		if show:
			var at := cam.unproject_position(head)
			tag.size = Vector2.ZERO
			tag.position = at - Vector2(tag.get_minimum_size().x * 0.5, tag.get_minimum_size().y)
