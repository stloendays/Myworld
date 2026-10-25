class_name SignBoard
extends Node3D
## 中英双语解说卷轴（v0.5 起代替木牌）：木架挂一幅卷轴——纸面、上下两根木轴（黄铜轴头）、轴头垂着红绳穗，
## 架子上一块小木签写着标题（远处也知道写的是什么）。正面朝本地 +Z。
## 平时卷起；本地玩家（或当前相机）走近到 unroll_radius 以内时平滑展开：下轴往下落，文字随纸面逐行露出；走远卷回去。
## 文字在 data/world/signs.json（按 text id），室外卷轴位置在 world_layout.json → signs，建筑与其他世界里的由各自脚本放。
##   style = "stand"：两根立柱 + 带小瓦顶的横梁，卷轴挂在梁下；
##   "lectern"：斜面木案（放在鱼缸、泳池边），卷轴沿案面往下铺开；
##   "wall"：墙上铜钩挂卷轴（背面贴在本地 z = 0，原点是展开后纸面的中心）。
## 纸面先量文字再定尺寸：宽度取 width 与标题宽度中较大者，正文按内宽逐行断好，每行一个 Label3D，永远不会出纸。

const TEXT_PATH := "res://data/world/signs.json"
const INK := Color(0.16, 0.11, 0.07)
const PIXEL := 0.002          ## 1 字号像素 = 2 mm
const MARGIN := 0.09          ## 纸面内边距（米）
const ROD_R := 0.035          ## 木轴半径
const ROLL_R := 0.075         ## 卷起时下面那一卷的半径
const UNROLL_SECONDS := 0.65
const RADIUS := 3.6           ## 走近多少米开始展开
const WALL_RADIUS := 9.0      ## 挂墙招牌（高处的大字）在远一点就展开
const HYSTERESIS := 0.8       ## 走远到 半径 + 回差 才卷回去，站在边上不会来回卷
const TEXT_Z := 0.006         ## 文字离纸面的距离
## 各段文字的颜色：中文标题深红褐、英文标题暖褐、正文深墨色
const INKS := {"title_zh": Color(0.36, 0.14, 0.07), "title_en": Color(0.42, 0.28, 0.15)}
const LECTERN_TILT := 40.0    ## 讲台卷轴的案面向后仰的角度，站着低头正好看
## 每段文字的字号与段后间距（米）
const STYLE := {
	"title_zh": {"px": 56, "gap": 0.01, "align": HORIZONTAL_ALIGNMENT_CENTER},
	"title_en": {"px": 30, "gap": 0.05, "align": HORIZONTAL_ALIGNMENT_CENTER},
	"body_zh": {"px": 30, "gap": 0.025, "align": HORIZONTAL_ALIGNMENT_LEFT},
	"body_en": {"px": 25, "gap": 0.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
}

static var _texts: Dictionary = {}

var text_id := ""
var style := "stand"
var panel_size := Vector2.ZERO        ## 展开后纸面的大小（米）
var unroll := 0.0                     ## 0 = 卷起，1 = 完全展开（显示用的进度）
var unroll_radius := RADIUS
var force_open := false               ## 截图、自动检查用：不看距离，一直展开
var lines: Array[Label3D] = []        ## 纸面上的每一行字（自上而下）
var line_keys := PackedStringArray()     ## 每一行属于哪一段（title_zh / title_en / body_zh / body_en / rule）
var title_tag: Label3D = null         ## 木签上的标题（卷起时也看得到）

var _target := 0.0
var _check_timer := 0.0
var _scroll: Node3D                   ## 原点 = 上轴中心；纸面沿本地 -Y 往下展开
var _paper: MeshInstance3D
var _paper_mat: StandardMaterial3D
var _roll: Node3D                     ## 下轴 + 卷起的纸 + 轴头 + 绳穗
var _roll_paper: MeshInstance3D
var _line_bottom: PackedFloat32Array = []   ## 每行字的下沿离上轴多远（米）


static func texts() -> Dictionary:
	if _texts.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEXT_PATH))
		if parsed is Dictionary:
			_texts = parsed
		else:
			push_error("SignBoard: 无法解析 %s" % TEXT_PATH)
	return _texts


## 建一幅卷轴；width = 纸面最小宽度（米），scale = 字的整体放大倍数（挂墙招牌用大字）。
static func create(id: String, sign_style: String, width: float, scale := 1.0) -> SignBoard:
	var sign := SignBoard.new()
	sign.name = "Sign_" + id
	sign.text_id = id
	sign.style = sign_style
	sign.unroll_radius = WALL_RADIUS if sign_style == "wall" else RADIUS
	sign.add_to_group("sign_boards")
	var t: Dictionary = texts().get(id, {})
	if t.is_empty():
		push_error("SignBoard: signs.json 里没有 %s" % id)
	sign._build(t, width, scale)
	return sign


## 一段文字按内宽断成行（与 Label3D 自动换行同样的规则）：返回 [{text, h}]。标题不换行。
static func split_lines(text: String, font: Font, px: int, wrap_px: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var para := TextParagraph.new()
	para.add_string(text, font, px)
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.width = wrap_px if wrap_px > 0 else -1
	for i in para.get_line_count():
		var r := para.get_line_range(i)
		out.append({"text": text.substr(r.x, r.y - r.x).strip_edges(), "h": para.get_line_size(i).y})
	return out


func _build(t: Dictionary, width: float, scale: float) -> void:
	var font := GameSettings.ui_theme().default_font
	var pixel := PIXEL * scale
	# 先量：标题不换行，决定最小宽度；正文按内宽断行，累加高度
	var w := width
	for key in ["title_zh", "title_en"]:
		if t.has(key):
			w = maxf(w, font.get_string_size(str(t[key]), HORIZONTAL_ALIGNMENT_LEFT, -1, STYLE[key]["px"]).x * pixel + MARGIN * 2.0)
	var inner := w - MARGIN * 2.0
	var wrap_px := int(inner / pixel)
	var rows: Array[Dictionary] = []   # {text, px, align, key, y_top, h}
	var y := MARGIN
	var keys := ["title_zh", "title_en", "body_zh", "body_en"].filter(func(k: String) -> bool: return t.has(k))
	var rule_y := -1.0
	for i in keys.size():
		var key: String = keys[i]
		var st: Dictionary = STYLE[key]
		var wrap := wrap_px if key.begins_with("body") else -1
		for ln: Dictionary in split_lines(str(t[key]), font, st["px"], wrap):
			var lh := float(ln["h"]) * pixel
			rows.append({"text": ln["text"], "px": st["px"], "align": st["align"], "key": key, "y": y, "h": lh})
			y += lh
		y += float(st["gap"])
		if key == "title_en" and i + 1 < keys.size():
			rule_y = y - float(st["gap"]) * 0.55
	var h := y + MARGIN - (float(STYLE[keys[-1]]["gap"]) if not keys.is_empty() else 0.0)
	panel_size = Vector2(w, h)

	var mats := _materials()
	_paper_mat = (mats.paper as StandardMaterial3D).duplicate()
	_scroll = Node3D.new()
	_scroll.name = "Scroll"
	var rod_len := w + 0.16
	var top_h := 0.0          # 架子最高点（碰撞用）
	match style:
		"stand":
			var bottom := 0.62
			var beam_y := bottom + h + 0.42
			top_h = beam_y + 0.28
			var half := rod_len * 0.5 + 0.12
			for sx: float in [-1.0, 1.0]:
				_box(self, Vector3(0.26, 0.16, 0.26), Vector3(sx * half, 0.08, 0.0), mats.stone)
				_box(self, Vector3(0.12, beam_y + 0.1, 0.12), Vector3(sx * half, (beam_y + 0.1) * 0.5, 0.0), mats.dark)
				_box(self, Vector3(0.16, 0.05, 0.16), Vector3(sx * half, 0.2, 0.0), mats.brass)
			_box(self, Vector3(half * 2.0 + 0.36, 0.12, 0.14), Vector3(0.0, beam_y + 0.06, 0.0), mats.dark)
			# 小瓦顶：两片斜板 + 屋脊
			for sz: float in [-1.0, 1.0]:
				var roof := _box(self, Vector3(half * 2.0 + 0.5, 0.04, 0.26), Vector3(0.0, beam_y + 0.19, sz * 0.1), mats.roof)
				roof.rotation.x = sz * deg_to_rad(28.0)
			_box(self, Vector3(half * 2.0 + 0.54, 0.05, 0.05), Vector3(0.0, beam_y + 0.255, 0.0), mats.light)
			# 挂绳：横梁到上轴两端
			for sx: float in [-1.0, 1.0]:
				_box(self, Vector3(0.015, 0.2, 0.015), Vector3(sx * (w * 0.5 - 0.05), beam_y - 0.1, 0.03), mats.cord)
			_scroll.position = Vector3(0.0, beam_y - 0.2, 0.03)
			_tag(t, font, scale, Vector3(0.0, beam_y + 0.06, 0.075), 0.0)
		"lectern":
			var tilt := deg_to_rad(LECTERN_TILT)
			var desk_len := h + 0.3
			var desk_top := 0.55 + (desk_len - 0.08) * cos(tilt)
			var desk := Node3D.new()
			desk.name = "Desk"
			desk.position = Vector3(0.0, desk_top, -0.05)
			desk.rotation.x = -tilt
			add_child(desk)
			# 案面（沿本地 -Y 往下），前沿一道挡条
			_box(desk, Vector3(rod_len + 0.12, desk_len, 0.05), Vector3(0.0, -desk_len * 0.5 + 0.08, -0.03), mats.light)
			_box(desk, Vector3(rod_len + 0.12, 0.05, 0.08), Vector3(0.0, -desk_len + 0.08, 0.02), mats.dark)
			var low := desk_top - (desk_len - 0.08) * cos(tilt)
			_box(self, Vector3(maxf(rod_len * 0.55, 0.5), 0.08, 0.5), Vector3(0.0, 0.04, -0.05), mats.stone)
			_box(self, Vector3(0.13, low, 0.13), Vector3(0.0, low * 0.5, -0.05 + (desk_len * 0.5) * sin(tilt)), mats.dark)
			for ry: float in [0.18, low - 0.1]:
				_box(self, Vector3(0.18, 0.04, 0.18), Vector3(0.0, ry, -0.05 + (desk_len * 0.5) * sin(tilt)), mats.brass)
			_scroll.position = Vector3(0.0, 0.0, 0.02)
			desk.add_child(_scroll)
			top_h = desk_top + 0.1
			_tag(t, font, scale * 0.8, Vector3(0.0, 0.11, 0.035), 0.0, desk)
		"wall":
			_scroll.position = Vector3(0.0, h * 0.5, 0.06)
			for sx: float in [-1.0, 1.0]:
				_box(self, Vector3(0.05, 0.05, 0.08), Vector3(sx * (w * 0.5 - 0.05), h * 0.5 + 0.12, 0.04), mats.brass)
				_box(self, Vector3(0.012, 0.13, 0.012), Vector3(sx * (w * 0.5 - 0.05), h * 0.5 + 0.06, 0.07), mats.cord)
			top_h = h * 0.5 + 0.2
	if _scroll.get_parent() == null:
		add_child(_scroll)

	# 上轴（贯穿纸宽，两端黄铜轴头 + 红绳穗）
	_rod(_scroll, rod_len, ROD_R, mats)
	# 纸面：QuadMesh 顶边贴着上轴，展开时按比例往下拉长，UV 跟着裁（纸纹不被拉伸）
	_paper = MeshInstance3D.new()
	_paper.name = "Paper"
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	_paper.mesh = quad
	_paper.material_override = _paper_mat
	_scroll.add_child(_paper)
	# 下面那一卷：随展开往下落，卷着的纸越来越薄
	_roll = Node3D.new()
	_roll.name = "Roll"
	_scroll.add_child(_roll)
	_rod(_roll, rod_len, ROD_R, mats)
	_roll_paper = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = w
	cyl.radial_segments = 14
	_roll_paper.mesh = cyl
	_roll_paper.material_override = _paper_mat
	_roll_paper.rotation.z = PI * 0.5
	_roll.add_child(_roll_paper)
	# 下轴中间垂一个小坠子
	_box(_roll, Vector3(0.05, 0.05, 0.05), Vector3(0.0, -0.08, 0.0), mats.brass)

	# 文字：每行一个 Label3D，居中或左对齐到内边距
	for r: Dictionary in rows:
		var l := Label3D.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 纸面本来就中英双语，不随界面语言替换
		l.text = r["text"]
		l.font = font
		l.font_size = r["px"]
		l.pixel_size = pixel
		l.modulate = INKS.get(r["key"], INK)
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.horizontal_alignment = r["align"]
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var x := 0.0 if r["align"] == HORIZONTAL_ALIGNMENT_CENTER else -inner * 0.5
		l.position = Vector3(x, -float(r["y"]), TEXT_Z)
		l.visible = false
		_scroll.add_child(l)
		lines.append(l)
		line_keys.append(str(r["key"]))
		_line_bottom.append(float(r["y"]) + float(r["h"]) * 0.85)
	if rule_y > 0.0:
		var rule := _box(_scroll, Vector3(inner * 0.6, 0.008, 0.004), Vector3(0.0, -rule_y, TEXT_Z * 0.6), mats.brass)
		rule.name = "Rule"
		_line_bottom.append(rule_y)
		lines.append(null)
		line_keys.append("rule")

	# 碰撞：整个架子一个盒子，人走不穿
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	match style:
		"wall":
			shape.size = Vector3(rod_len, h + 0.3, 0.12)
			cs.position = Vector3(0.0, 0.0, 0.06)
		"lectern":
			shape.size = Vector3(rod_len + 0.12, top_h, 0.7)
			cs.position = Vector3(0.0, top_h * 0.5, -0.2)
		_:
			shape.size = Vector3(rod_len + 0.6, top_h, 0.3)
			cs.position = Vector3(0.0, top_h * 0.5, 0.0)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_apply_unroll()


func _ready() -> void:
	# 挂墙招牌一开始就按距离决定；其余从卷起开始
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	# 卷着或展开着不动时每 0.1 秒看一次距离就够了；正在卷 / 展开时每帧更新
	_check_timer -= delta
	if _check_timer <= 0.0 or not is_equal_approx(unroll, _target):
		_check_timer = 0.1
		_target = 1.0 if force_open else _wanted()
	if is_equal_approx(unroll, _target):
		return
	unroll = move_toward(unroll, _target, delta / UNROLL_SECONDS)
	_apply_unroll()


## 立即卷起 / 展开（截图、自动检查用）。
func set_unrolled(on: bool) -> void:
	force_open = on
	_target = 1.0 if on else 0.0
	unroll = _target
	_apply_unroll()


func is_open() -> bool:
	return unroll >= 0.999


## 离本地玩家或当前相机较近的那个距离（水平）：近了展开，远过半径 + 回差卷回，中间保持原样。
func _wanted() -> float:
	var p := global_position
	var d := INF
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player != null:
		d = Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
		if absf(player.global_position.y - p.y) > 6.0:
			d = INF
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var cp := cam.global_position
		if absf(cp.y - p.y) < 6.0:
			d = minf(d, Vector2(cp.x - p.x, cp.z - p.z).length())
	if d < unroll_radius:
		return 1.0
	if d > unroll_radius + HYSTERESIS:
		return 0.0
	return _target


## 按展开进度摆纸面、下轴，显示已经露出来的那几行字。
func _apply_unroll() -> void:
	var e := smoothstep(0.0, 1.0, unroll)
	var length_m := panel_size.y * e
	_paper.visible = e > 0.01
	_paper.scale = Vector3(1.0, maxf(e, 0.001), 1.0)
	_paper.position = Vector3(0.0, -length_m * 0.5, 0.0)
	_paper_mat.uv1_scale = Vector3(1.0, maxf(e, 0.001), 1.0)
	# 卷起的纸：长度没展开的部分绕在下轴上，半径随之变小
	var r := lerpf(ROLL_R, ROD_R + 0.008, e)
	_roll_paper.scale = Vector3(r, 1.0, r)
	_roll.position = Vector3(0.0, -length_m - (r if e > 0.01 else ROD_R * 0.6), 0.0)
	for i in lines.size():
		var show := length_m >= _line_bottom[i]
		if lines[i] != null:
			lines[i].visible = show
		elif _scroll.has_node("Rule"):
			(_scroll.get_node("Rule") as Node3D).visible = show


## 木签：卷起时也看得到的标题（中文大、英文小），远处 30 m 外不画。
func _tag(t: Dictionary, font: Font, scale: float, pos: Vector3, yaw: float, parent: Node3D = null) -> void:
	var host: Node3D = parent if parent != null else self
	var zh := str(t.get("title_zh", ""))
	if zh == "":
		return
	var px := 40
	var pixel := PIXEL * scale * 0.8
	var tw := font.get_string_size(zh, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * pixel + 0.14
	var mats := _materials()
	var board := _box(host, Vector3(tw, px * pixel * 1.5, 0.03), pos + Vector3(0.0, 0.0, -0.01), mats.tag)
	board.name = "TitleTag"
	board.rotation.y = yaw
	title_tag = Label3D.new()
	title_tag.name = "TitleTagText"
	title_tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_tag.text = zh
	title_tag.font = font
	title_tag.font_size = px
	title_tag.pixel_size = pixel
	title_tag.modulate = Color(0.98, 0.9, 0.7)
	title_tag.outline_size = 0
	title_tag.shaded = true
	title_tag.double_sided = false
	title_tag.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	title_tag.position = pos + Vector3(0.0, 0.0, 0.0075)
	title_tag.visibility_range_end = 30.0
	title_tag.visibility_range_end_margin = 4.0
	host.add_child(title_tag)


## 一根木轴：横放的圆柱 + 两端黄铜轴头 + 轴头垂下的红绳穗。
func _rod(parent: Node3D, length: float, radius: float, mats: Dictionary) -> void:
	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 10
	rod.mesh = cm
	rod.material_override = mats.dark
	rod.rotation.z = PI * 0.5
	parent.add_child(rod)
	for sx: float in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = radius * 1.45
		cc.bottom_radius = radius * 1.2
		cc.height = 0.06
		cc.radial_segments = 10
		cap.mesh = cc
		cap.material_override = mats.brass
		cap.rotation.z = PI * 0.5
		cap.position = Vector3(sx * (length * 0.5 + 0.03), 0.0, 0.0)
		parent.add_child(cap)
		_box(parent, Vector3(0.012, 0.16, 0.012), Vector3(sx * (length * 0.5 + 0.03), -0.1, 0.0), mats.cord)
		_box(parent, Vector3(0.035, 0.07, 0.035), Vector3(sx * (length * 0.5 + 0.03), -0.2, 0.0), mats.tassel)


## 卷轴共用材质（全部经 ArtMaterials）：深色木、浅色木、石脚、黄铜、羊皮纸、红绳、瓦顶、木签。
static func _materials() -> Dictionary:
	return {
		"dark": ArtMaterials.pbr("stained_pine", Color(0.62, 0.4, 0.26)),
		"light": ArtMaterials.pbr("brown_planks_05", Color(0.86, 0.62, 0.4)),
		"stone": ArtMaterials.pbr("rustic_stone_wall", Color(0.9, 0.88, 0.84)),
		"brass": ArtMaterials.flat(Color(0.86, 0.66, 0.3), 0.35, false, 0.8),
		"paper": ArtMaterials.parchment(),
		"cord": ArtMaterials.flat(Color(0.72, 0.16, 0.12), 0.8),
		"tassel": ArtMaterials.flat(Color(0.82, 0.2, 0.14), 0.9),
		"roof": ArtMaterials.flat(Color(0.32, 0.36, 0.42), 0.7),
		"tag": ArtMaterials.flat(Color(0.3, 0.18, 0.1), 0.75),
	}


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
