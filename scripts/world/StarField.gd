class_name StarField
extends Node3D
## 夜空里的星座（data/sky/constellations.json，原创）：每个星座几颗较亮的星，晴朗的夜里出现在固定方位。
## 在室外盯着一个星座看（视线中心离它 10° 以内）1.5 秒，星之间的连线会慢慢亮起来，同时记进图鉴（QuestLog）。
## 认出过的星座以后每晚都带着连线。星和线是贴在以相机为中心、半径 600 m 球面上的小面片（不写深度以外的任何东西：
## 山和树照样挡得住它们），跟着相机走，所以永远在“天上”。白天、阴天、下雨下雪下雾时整体淡出。
## 带 requires 的新星座（天鲸、石拱、蝠鲼）在那个世界的光送回去之前不在天上；StoryDirector 第一次放它们时调用 reveal()：
## 星一颗一颗亮起来（亮的那一下大一点），再一笔一笔连上线，最后记进图鉴。放过的记在 WorldState.flags["star_<id>"]。

const DATA_PATH := "res://data/sky/constellations.json"
const RADIUS := 600.0
const GAZE_DEG := 10.0
const GAZE_SECONDS := 1.5
const CLEAR_WEATHER := [&"CLEAR"]
const STAR_PHASE := 0.6           ## reveal：前 60 % 的时间里星一颗一颗亮，之后连线

static var _data: Array = []

var visibility := 0.0             ## 0..1：夜色 × 晴朗程度
var gaze_id := ""                 ## 现在正盯着的星座
var revealing := ""               ## 正在一颗一颗亮起来的新星座
var highlight_all := false        ## 终章过场里所有星座的连线一起亮（只是画面，不记图鉴）
var _gaze_t := 0.0
var _stars: Dictionary = {}       ## id -> MeshInstance3D（星）
var _lines: Dictionary = {}       ## id -> MeshInstance3D（连线）
var _line_alpha: Dictionary = {}  ## id -> 0..1
var _reveal_t := 0.0
var _reveal_seconds := 6.0
var _star_mat: StandardMaterial3D
var _line_mat_base: StandardMaterial3D


static func constellations() -> Array:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = (parsed as Dictionary).get("constellations", []) if parsed is Dictionary else []
	return _data


static func find(id: String) -> Dictionary:
	for c: Dictionary in constellations():
		if str(c["id"]) == id:
			return c
	return {}


## 湖畔原本就有的星座（前一位旅人那张星图上画着的五个）。
static func base_list() -> Array:
	return constellations().filter(func(c: Dictionary) -> bool: return not c.has("requires"))


## 把光送回去以后才出现的新星座（星图上的三个空位），按数据里的顺序。
static func extras() -> Array:
	return constellations().filter(func(c: Dictionary) -> bool: return c.has("requires"))


## 这个新星座的世界已经点亮（可以放出来了）。
static func unlocked(c: Dictionary) -> bool:
	return not c.has("requires") or not GameRules.is_story() or bool(WorldState.flags.get(str(c["requires"]), false))


## 已经在天上（原有的、或放过一次的新星座）。休闲模式没有剧情，八个星座一开始就都在天上。
static func shown(c: Dictionary) -> bool:
	return not c.has("requires") or not GameRules.is_story() or bool(WorldState.flags.get("star_" + str(c["id"]), false))


## 星座中心或其中一颗星的方向（单位向量）。az 北 = 0、顺时针；本世界北 = -Z、东 = +X。
static func direction(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func center_dir(c: Dictionary) -> Vector3:
	return direction(float(c["az"]), float(c["el"]))


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
	for c: Dictionary in constellations():
		var id := str(c["id"])
		var stars := MeshInstance3D.new()
		stars.name = "Stars_" + id
		stars.mesh = _star_mesh(c, 1.0)
		stars.material_override = _star_mat
		stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stars.extra_cull_margin = 2000.0
		add_child(stars)
		_stars[id] = stars
		var mi := MeshInstance3D.new()
		mi.name = "Lines_" + id
		mi.mesh = _line_mesh(c, 1.0)
		mi.material_override = _line_mat_base.duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2000.0
		add_child(mi)
		_lines[id] = mi


## 一个星座的星。p < 1 时是 reveal 进行到 p：第 k 颗在 p 到达 k / n × STAR_PHASE 时亮起，刚亮时大一圈、更亮。
func _star_mesh(c: Dictionary, p: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := star_dirs(c)
	var stars: Array = c["stars"]
	var n := dirs.size()
	for i in n:
		var t := 1.0 if p >= 1.0 else clampf((p - STAR_PHASE * i / n) / 0.12, 0.0, 1.0)
		if t <= 0.0:
			continue
		var pop := 1.0 if p >= 1.0 else 1.0 + 1.2 * sin(t * PI) * (1.0 - t * 0.5)
		var size := (1.6 + float(stars[i][2]) * 1.6) * pop
		_billboard(st, dirs[i] * RADIUS, size, Color(1.0, 0.97, 0.88, (0.5 + float(stars[i][2]) * 0.5) * t))
	return st.commit()


## 一个星座的连线。p < 1 时按 reveal 进度一笔一笔画：STAR_PHASE 之后依次画每一段，画到一半的那段从起点伸出去。
func _line_mesh(c: Dictionary, p: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := star_dirs(c)
	var pairs: Array = c["lines"]
	var draw := 1.0 * pairs.size() if p >= 1.0 else clampf((p - STAR_PHASE) / (1.0 - STAR_PHASE), 0.0, 1.0) * pairs.size()
	for j in pairs.size():
		var f := clampf(draw - j, 0.0, 1.0)
		if f <= 0.0:
			break
		var a := dirs[int(pairs[j][0])] * RADIUS
		var b := dirs[int(pairs[j][1])] * RADIUS
		_segment(st, a, a.lerp(b, f), 0.7, Color(0.65, 0.85, 1.0, 0.55))
	return st.commit()


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
	if revealing != "":
		_step_reveal(delta)
	for c: Dictionary in constellations():
		var id := str(c["id"])
		var up := id == revealing or shown(c)
		(_stars[id] as MeshInstance3D).visible = up
		var mi := _lines[id] as MeshInstance3D
		var la := 1.0 if id == revealing or (highlight_all and up) else float(_line_alpha[id])
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, visibility * la)
		mi.visible = up and la > 0.01
	_update_gaze(cam, delta)


## 让一个新星座在 seconds 秒里一颗一颗亮起来、连上线；放完记进图鉴，以后每晚都在。
func reveal(id: String, seconds := 6.0) -> void:
	var c := find(id)
	if c.is_empty():
		return
	revealing = id
	_reveal_t = 0.0
	_reveal_seconds = maxf(seconds, 0.1)
	WorldState.flags["star_" + id] = true
	_line_alpha[id] = 0.0
	(_stars[id] as MeshInstance3D).mesh = _star_mesh(c, 0.0)
	(_lines[id] as MeshInstance3D).mesh = _line_mesh(c, 0.0)


func _step_reveal(delta: float) -> void:
	var c := find(revealing)
	_reveal_t += delta
	var p := minf(_reveal_t / _reveal_seconds, 1.0)
	(_stars[revealing] as MeshInstance3D).mesh = _star_mesh(c, p)
	(_lines[revealing] as MeshInstance3D).mesh = _line_mesh(c, p)
	if p >= 1.0:
		_line_alpha[revealing] = 1.0
		discover(revealing)
		revealing = ""


## 盯着看：视线中心 10° 以内连续 1.5 秒（只在夜里、室外、星星看得见时；还没放出来的新星座不算）。
func _update_gaze(cam: Camera3D, delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	var outdoors := player == null or not WorldState.is_indoors(player.entity_id)
	var fwd := -cam.global_basis.z
	var best := ""
	if visibility > 0.6 and outdoors:
		for c: Dictionary in constellations():
			if shown(c) and fwd.angle_to(center_dir(c)) < deg_to_rad(GAZE_DEG):
				best = str(c["id"])
	if best != gaze_id:
		gaze_id = best
		_gaze_t = 0.0
	if gaze_id != "":
		_gaze_t += delta
		if _gaze_t >= GAZE_SECONDS:
			discover(gaze_id)
	for id: String in _line_alpha:
		if id == revealing:
			continue
		var target := 1.0 if id in WorldState.journal_list("constellations") else 0.0
		_line_alpha[id] = move_toward(float(_line_alpha[id]), target, delta * 0.8)


func discover(id: String) -> bool:
	var c := find(id)
	if c.is_empty():
		return false
	return QuestLog.record("constellations", id, QuestLog.text(c, "name"))
