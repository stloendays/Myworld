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
	# 每个世界都有自己的一份（旅行时随世界卸载重建）：按房间名单把已经在房间里的人补上
	for id in Net.roster:
		if id != Net.my_id():
			add(id, Net.roster[id])


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
	ls.font_color = color_of(id)
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
	if _players.has(id) and Net.valid_pose(pose):
		(_players[id] as RemotePlayer).set_pose(pose)


func get_player(id: int) -> RemotePlayer:
	return _players.get(id)


func count() -> int:
	return _players.size()


## 每位朋友固定一种颜色（按 peer_id 排序后的位置），名字标签、小地图、罗盘、地图上用同一种。
const FRIEND_COLORS := [Color(0.45, 0.8, 1.0), Color(1.0, 0.55, 0.6), Color(0.6, 0.95, 0.5), Color(1.0, 0.78, 0.35)]


static func color_of(id: int) -> Color:
	var ids := Net.roster.keys()
	ids.sort()
	var i := ids.find(id)
	return FRIEND_COLORS[maxi(i, 0) % FRIEND_COLORS.size()]


## 和我在同一个世界、已经出现的朋友：[{id, name, pos: Vector2（世界 xz）, yaw, color}]。小地图、罗盘、世界地图都读它。
static func friends(tree: SceneTree) -> Array:
	var out := []
	var rp := tree.get_first_node_in_group("remote_players") as RemotePlayers
	if rp == null:
		return out
	for id in rp._players:
		var p: RemotePlayer = rp._players[id]
		if p.visible:
			out.append({"id": id, "name": p.display_name, "pos": Vector2(p.global_position.x, p.global_position.z),
				"yaw": p.rotation.y, "color": color_of(id)})
	return out


## 到朋友身边（房间页的“到 TA 身边”）：站到 TA 站的地方（别人的方块人没有碰撞，不会卡住；TA 背后可能是墙），面朝同一个方向。
## 不在同一个世界、还没出现时返回 false。
func go_to(id: int) -> bool:
	var p: RemotePlayer = _players.get(id)
	var me := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if p == null or not p.visible or me == null:
		return false
	var at := p.global_position + Vector3(0.0, 0.1, 0.0)
	Fade.flash(tr("来到 %s 身边") % p.display_name)
	me.teleport_to(at, -rad_to_deg(p.rotation.y))
	return true


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
