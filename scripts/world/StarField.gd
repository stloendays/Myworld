class_name StarField
extends Node3D
## 夜空里的星座（data/sky/constellations.json，原创）：每个星座几颗较亮的星，晴朗的夜里出现在固定方位。
## 在室外盯着一个星座看（视线中心离它 10° 以内）1.5 秒，星之间的连线会慢慢亮起来，同时记进图鉴（QuestLog）。
## 认出过的星座以后每晚都带着连线。星和线是贴在以相机为中心、半径 600 m 球面上的小面片（不写深度以外的任何东西：
## 山和树照样挡得住它们），跟着相机走，所以永远在“天上”。白天、阴天、下雨下雪下雾时整体淡出。

const DATA_PATH := "res://data/sky/constellations.json"
const RADIUS := 600.0
const GAZE_DEG := 10.0
const GAZE_SECONDS := 1.5
const CLEAR_WEATHER := [&"CLEAR"]

static var _data: Array = []

var visibility := 0.0             ## 0..1：夜色 × 晴朗程度
var gaze_id := ""                 ## 现在正盯着的星座
var _gaze_t := 0.0
var _stars: MeshInstance3D
var _lines: Dictionary = {}       ## id -> MeshInstance3D
var _line_alpha: Dictionary = {}  ## id -> 0..1
var _star_mat: StandardMaterial3D
var _line_mat_base: StandardMaterial3D


static func constellations() -> Array:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = (parsed as Dictionary).get("constellations", []) if parsed is Dictionary else []
	return _data


## 星座中心或其中一颗星的方向（单位向量）。az 北 = 0、顺时针；本世界北 = -Z、东 = +X。
static func direction(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func star_dirs(c: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s: Array in c["stars"]:
		# 偏移量按“右、上”加在中心方位上：右 = 方位角增加，上 = 仰角增加（高仰角处按 cos 拉宽方位）
		var el := float(c["el"]) + float(s[1])
		var az := float(c["az"]) + float(s[0]) / maxf(cos(deg_to_rad(el)), 0.25)
		out.append(direction(az, el))
	return out


func _ready() -> void:
	add_to_group("star_field")
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_star_mat.vertex_color_use_as_albedo = true
	_star_mat.disable_fog = true
	_star_mat.no_depth_test = false
	_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mat_base = _star_mat.duplicate() as StandardMaterial3D
	_build()
	for c: Dictionary in constellations():
		_line_alpha[str(c["id"])] = 1.0 if str(c["id"]) in WorldState.journal_list("constellations") else 0.0


func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Dictionary in constellations():
		var dirs := star_dirs(c)
		var stars: Array = c["stars"]
		for i in dirs.size():
			var size := 1.6 + float(stars[i][2]) * 1.6
			_billboard(st, dirs[i] * RADIUS, size, Color(1.0, 0.97, 0.88, 0.5 + float(stars[i][2]) * 0.5))
	_stars = MeshInstance3D.new()
	_stars.name = "Stars"
	_stars.mesh = st.commit()
	_stars.material_override = _star_mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.extra_cull_margin = 2000.0
	add_child(_stars)
	for c: Dictionary in constellations():
		var lt := SurfaceTool.new()
		lt.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dirs := star_dirs(c)
		for pair: Array in c["lines"]:
			_segment(lt, dirs[int(pair[0])] * RADIUS, dirs[int(pair[1])] * RADIUS, 0.7, Color(0.65, 0.85, 1.0, 0.55))
		var mi := MeshInstance3D.new()
		mi.name = "Lines_" + str(c["id"])
		mi.mesh = lt.commit()
		mi.material_override = _line_mat_base.duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2000.0
		add_child(mi)
		_lines[str(c["id"])] = mi


## 朝向球心的小方块（星）。
func _billboard(st: SurfaceTool, p: Vector3, size: float, col: Color) -> void:
	var n := -p.normalized()
	var right := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized() * size * 0.5
	var up := right.cross(n).normalized() * size * 0.5
	st.set_color(col)
	for v in [p - right - up, p - right + up, p + right + up, p - right - up, p + right + up, p + right - up]:
		st.add_vertex(v)


## 两颗星之间的细线（面朝球心的长条）。
func _segment(st: SurfaceTool, a: Vector3, b: Vector3, width: float, col: Color) -> void:
	var mid := (a + b) * 0.5
	var n := -mid.normalized()
	var side := (b - a).cross(n).normalized() * width * 0.5
	st.set_color(col)
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		st.add_vertex(v)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	global_position = cam.global_position
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var night := env.night if env != null else 0.0
	var clear := 1.0 if WorldState.weather_id in CLEAR_WEATHER else 0.0
	if WorldState.weather_progress < 1.0 and WorldState.weather_from in CLEAR_WEATHER and clear < 1.0:
		clear = 1.0 - WorldState.weather_progress
	visibility = move_toward(visibility, night * clear, delta * 0.5)
	visible = visibility > 0.01
	_star_mat.albedo_color = Color(1, 1, 1, visibility)
	for id: String in _lines:
		var mi := _lines[id] as MeshInstance3D
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, visibility * float(_line_alpha[id]))
		mi.visible = float(_line_alpha[id]) > 0.01
	_update_gaze(cam, delta)


## 盯着看：视线中心 10° 以内连续 1.5 秒（只在夜里、室外、星星看得见时）。
func _update_gaze(cam: Camera3D, delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var outdoors := player == null or not WorldState.is_indoors(player.entity_id)
	var fwd := -cam.global_basis.z
	var best := ""
	if visibility > 0.6 and outdoors:
		for c: Dictionary in constellations():
			if fwd.angle_to(direction(float(c["az"]), float(c["el"]))) < deg_to_rad(GAZE_DEG):
				best = str(c["id"])
	if best != gaze_id:
		gaze_id = best
		_gaze_t = 0.0
	if gaze_id != "":
		_gaze_t += delta
		if _gaze_t >= GAZE_SECONDS:
			discover(gaze_id)
	for id: String in _line_alpha:
		var target := 1.0 if id in WorldState.journal_list("constellations") else 0.0
		_line_alpha[id] = move_toward(float(_line_alpha[id]), target, delta * 0.8)


func discover(id: String) -> bool:
	for c: Dictionary in constellations():
		if str(c["id"]) == id:
			return QuestLog.record("constellations", id, QuestLog.text(c, "name"))
	return false
