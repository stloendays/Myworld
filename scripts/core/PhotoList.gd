class_name PhotoList
extends RefCounted
## 摄影清单：data/photo/subjects.json 列出的 18 样东西（小动物、各世界的地标、天鲸、彩虹、闪电、星空、仙境）。
## 按 F12 拍照时（ActionBar.take_photo）看画面中央：视线 22° 以内、够近、没被挡住的清单对象记进图鉴（WorldState.journal → photos），
## 旅行日志的「收藏」页能看到拍到了哪些。所有玩法模式都能拍，“摄影”模式的说明里专门提它。

const PATH := "res://data/photo/subjects.json"
const VIEW_DEG := 22.0

static var _data: Dictionary = {}


static func subjects() -> Array:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"subjects": []}
	return _data["subjects"]


static func label(s: Dictionary) -> String:
	return QuestLog.text(s, "name")


## 画面中央有哪些清单对象（id 列表，不管拍没拍过）。
static func recognize(cam: Camera3D, tree: SceneTree) -> Array:
	var found := []
	if cam == null:
		return found
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	var world := WorldTravel.current_world
	var player := tree.get_first_node_in_group("local_player") as FirstPersonController
	var indoors := player != null and WorldState.is_indoors(player.entity_id)
	for s: Dictionary in subjects():
		var id := str(s["id"])
		var max_d := float(s.get("max_dist", 60.0))
		match str(s["kind"]):
			"species":
				for a in tree.get_nodes_in_group("fauna"):
					var an := a as Animal
					if an != null and an.species_id == id and an.visible and an.active and _in_view(cam, eye, fwd, an.global_position + Vector3(0.0, 0.3, 0.0), max_d, 1.0):
						found.append(id)
						break
			"place":
				if str(s.get("world", "")) == world:
					var p: Array = s["pos"]
					if _in_view(cam, eye, fwd, Vector3(float(p[0]), float(p[1]), float(p[2])), max_d, 6.0):
						found.append(id)
			"group":
				for n in tree.get_nodes_in_group(str(s["group"])):
					if (n as Node3D).is_visible_in_tree() and _in_view(cam, eye, fwd, (n as Node3D).global_position, max_d, 12.0):
						found.append(id)
						break
			"event":
				var glade := tree.get_first_node_in_group("fairy_glade") as FairyGlade
				if glade != null and glade.active and _in_view(cam, eye, fwd, glade.global_position + Vector3(0.0, 2.0, 0.0), max_d, glade.radius):
					found.append(id)
			"sky":
				var env := tree.get_first_node_in_group("environment_director") as EnvironmentDirector
				if env == null or indoors:
					continue
				match str(s["sky"]):
					"rainbow":
						if env.rainbow > 0.5:
							found.append(id)
					"lightning":
						if env.flash > 0.15:
							found.append(id)
					"stars":
						if env.night > 0.8 and fwd.y > 0.45 and WorldState.weather_id in [&"CLEAR", &"OVERCAST"]:
							found.append(id)
	return found


## 拍照时调用：认出来的记进图鉴，第一次拍到的弹提示。返回这次新记下的 id。
static func capture(cam: Camera3D, tree: SceneTree) -> Array:
	var fresh := []
	var all := subjects()
	for id: String in recognize(cam, tree):
		if WorldState.journal_add("photos", id):
			fresh.append(id)
			for s: Dictionary in all:
				if str(s["id"]) == id:
					EventBus.toast_requested.emit(TranslationServer.translate("摄影清单：拍到了「%s」（%d / %d）") % [label(s), WorldState.journal_list("photos").size(), all.size()])
	if not fresh.is_empty():
		EventBus.photo_taken.emit(fresh)
		QuestLog.changed.emit()
		SaveManager.request_save()
	return fresh


## 在不在画面中央、够不够近、有没有被挡住（射线打到的东西离目标不超过 radius 米算没挡住）。
static func _in_view(cam: Camera3D, eye: Vector3, fwd: Vector3, target: Vector3, max_d: float, radius: float) -> bool:
	var to := target - eye
	var d := to.length()
	if d > max_d or d < 0.3:
		return false
	if rad_to_deg(fwd.angle_to(to / d)) > VIEW_DEG:
		return false
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, target)
	q.collision_mask = PhysicsLayers.WORLD
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(target) <= radius
