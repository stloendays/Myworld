class_name SignBoard
extends Node3D
## 中英双语解说立牌：童话风木牌（厚木框、羊皮纸面、黄铜角钉、阶梯拱牌头和发光徽记），文字贴在纸面上（不悬空）。正面朝本地 +Z。
## 文字在 data/world/signs.json（按 text id），室外立牌位置在 world_layout.json → signs，
## 建筑里的立牌由建筑脚本按自己的本地坐标放。只在运行时生成（字体来自 GameSettings）。
##   style = "stand"：双腿立牌；"lectern"：单柱斜面讲台牌（放在鱼缸、泳池边）；"wall"：挂墙牌（背面贴在本地 z = 0）。
## 牌面先量文字再定尺寸：宽度取 width 与标题宽度中较大者，高度按换行后的文字总高，文字永远不会出框。

const TEXT_PATH := "res://data/world/signs.json"
const INK := Color(0.16, 0.11, 0.07)
const PIXEL := 0.002          ## 1 字号像素 = 2 mm
const MARGIN := 0.08          ## 面板内边距（米）
const DEPTH := 0.07           ## 木框厚度
const FRAME := 0.075          ## 木框宽度
const CREST_STEP := 0.06      ## 牌头每级台阶的高度
## 各段文字的颜色：中文标题深红褐、英文标题暖褐、正文深墨色
const INKS := {"title_zh": Color(0.36, 0.14, 0.07), "title_en": Color(0.42, 0.28, 0.15)}
const LECTERN_TILT := 40.0    ## 讲台牌面板向后仰的角度，站着低头正好看
## 每段文字的字号与段后间距（米）
const STYLE := {
	"title_zh": {"px": 56, "gap": 0.01, "align": HORIZONTAL_ALIGNMENT_CENTER},
	"title_en": {"px": 30, "gap": 0.05, "align": HORIZONTAL_ALIGNMENT_CENTER},
	"body_zh": {"px": 26, "gap": 0.025, "align": HORIZONTAL_ALIGNMENT_LEFT},
	"body_en": {"px": 22, "gap": 0.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
}

static var _texts: Dictionary = {}

var text_id := ""
var panel_size := Vector2.ZERO


static func texts() -> Dictionary:
	if _texts.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEXT_PATH))
		if parsed is Dictionary:
			_texts = parsed
		else:
			push_error("SignBoard: 无法解析 %s" % TEXT_PATH)
	return _texts


## 建一块立牌；width = 牌面最小宽度（米），scale = 字的整体放大倍数（挂墙招牌用大字）。
static func create(id: String, style: String, width: float, scale := 1.0) -> SignBoard:
	var sign := SignBoard.new()
	sign.name = "Sign_" + id
	sign.text_id = id
	sign.add_to_group("sign_boards")
	var t: Dictionary = texts().get(id, {})
	if t.is_empty():
		push_error("SignBoard: signs.json 里没有 %s" % id)
	var font := GameSettings.ui_theme().default_font
	var pixel := PIXEL * scale

	# 先量：标题不换行，决定最小宽度；正文按内宽换行，累加高度
	var w := width
	for key in ["title_zh", "title_en"]:
		if t.has(key):
			w = maxf(w, font.get_string_size(str(t[key]), HORIZONTAL_ALIGNMENT_LEFT, -1, STYLE[key]["px"]).x * pixel + MARGIN * 2.0)
	var inner := w - MARGIN * 2.0
	var wrap_px := int(inner / pixel)
	var blocks: Array[Dictionary] = []
	var h := MARGIN * 2.0
	for key in ["title_zh", "title_en", "body_zh", "body_en"]:
		if not t.has(key):
			continue
		var st: Dictionary = STYLE[key]
		var wrap := wrap_px if key.begins_with("body") else -1
		var block_h := font.get_multiline_string_size(str(t[key]), st["align"], wrap, st["px"]).y * pixel
		blocks.append({"text": str(t[key]), "px": st["px"], "align": st["align"], "wrap": wrap, "h": block_h})
		h += block_h + float(st["gap"])
	var size := Vector2(w, h)
	sign.panel_size = size

	# 再建：童话风木牌——厚木框 + 浅色内框 + 羊皮纸面 + 黄铜角钉；立式和挂墙牌顶上有阶梯拱形牌头和发光徽记，
	# 立式牌的柱子有石脚和柱帽，讲台牌是带石座和箍环的单柱
	var mats := _materials()
	var face := Node3D.new()
	face.name = "Face"
	sign.add_child(face)
	var crest := style != "lectern"
	var crest_h := CREST_STEP * 3.0 if crest else 0.0
	var outer := size + Vector2(FRAME * 2.0, FRAME * 2.0)
	var bottom := 0.0
	var top_y := size.y
	match style:
		"stand":
			bottom = 0.7
			top_y = bottom + outer.y + crest_h
			var post_h := bottom + outer.y * 0.85
			for sx: float in [-1.0, 1.0]:
				var px := sx * (outer.x * 0.5 - 0.02)
				_box(sign, Vector3(0.26, 0.16, 0.26), Vector3(px, 0.08, -DEPTH * 0.5), mats.stone)
				_box(sign, Vector3(0.12, post_h, 0.12), Vector3(px, post_h * 0.5, -DEPTH * 0.5), mats.dark)
				_box(sign, Vector3(0.17, 0.05, 0.17), Vector3(px, post_h + 0.025, -DEPTH * 0.5), mats.light)
				_box(sign, Vector3(0.09, 0.07, 0.09), Vector3(px, post_h + 0.085, -DEPTH * 0.5), mats.brass)
			face.position = Vector3(0.0, bottom + outer.y * 0.5, 0.0)
		"lectern":
			bottom = 0.95
			var tilt := deg_to_rad(LECTERN_TILT)
			top_y = bottom + outer.y * cos(tilt)
			_box(sign, Vector3(maxf(outer.x * 0.55, 0.5), 0.08, 0.45), Vector3(0.0, 0.04, -0.05), mats.stone)
			_box(sign, Vector3(0.13, bottom, 0.13), Vector3(0.0, bottom * 0.5, -0.05), mats.dark)
			for ry: float in [0.18, bottom - 0.12]:
				_box(sign, Vector3(0.18, 0.04, 0.18), Vector3(0.0, ry, -0.05), mats.brass)
			face.position = Vector3(0.0, bottom + outer.y * 0.5 * cos(tilt), -0.05)
			face.rotation.x = -tilt
		"wall":
			face.position = Vector3(0.0, 0.0, DEPTH * 0.5 + 0.005)
	# 背板、四根框条（上下通长、左右夹在中间）、浅色内框
	_box(face, Vector3(outer.x, outer.y, DEPTH * 0.6), Vector3(0.0, 0.0, -DEPTH * 0.2), mats.dark)
	for sy: float in [-1.0, 1.0]:
		_box(face, Vector3(outer.x, FRAME, DEPTH), Vector3(0.0, sy * (outer.y - FRAME) * 0.5, 0.0), mats.dark)
	for sx: float in [-1.0, 1.0]:
		_box(face, Vector3(FRAME, outer.y - FRAME * 2.0, DEPTH), Vector3(sx * (outer.x - FRAME) * 0.5, 0.0, 0.0), mats.dark)
	var lip := 0.018
	for sy: float in [-1.0, 1.0]:
		_box(face, Vector3(size.x, lip, 0.014), Vector3(0.0, sy * (size.y - lip) * 0.5, DEPTH * 0.5 + 0.004), mats.light)
	for sx: float in [-1.0, 1.0]:
		_box(face, Vector3(lip, size.y, 0.014), Vector3(sx * (size.x - lip) * 0.5, 0.0, DEPTH * 0.5 + 0.004), mats.light)
	# 羊皮纸面（QuadMesh：UV 正好铺满一张纸）
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size - Vector2(lip * 2.0, lip * 2.0)
	paper.mesh = quad
	paper.material_override = mats.paper
	paper.position = Vector3(0.0, 0.0, DEPTH * 0.5 + 0.002)
	face.add_child(paper)
	# 四角黄铜钉
	for cx: float in [-1.0, 1.0]:
		for cy: float in [-1.0, 1.0]:
			_box(face, Vector3(0.045, 0.045, 0.02), Vector3(cx * (outer.x - FRAME) * 0.5, cy * (outer.y - FRAME) * 0.5, DEPTH * 0.5 + 0.01), mats.brass)
	# 牌头：三级阶梯拱 + 中间一颗发光的菱形徽记
	if crest:
		var top := outer.y * 0.5
		var widths := [outer.x * 0.7, outer.x * 0.5, outer.x * 0.28]
		for i in 3:
			_box(face, Vector3(widths[i], CREST_STEP, DEPTH), Vector3(0.0, top + CREST_STEP * (i + 0.5), 0.0), mats.dark if i != 1 else mats.light)
		var gem := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.075, 0.075, 0.03)
		gem.mesh = gm
		gem.material_override = mats.glow
		gem.position = Vector3(0.0, top + CREST_STEP * 1.5, DEPTH * 0.5 + 0.016)
		gem.rotation.z = PI * 0.25
		face.add_child(gem)
		# 两个上角：一小簇叶子和一朵发光的小花
		for cx: float in [-1.0, 1.0]:
			var c := Vector3(cx * (outer.x * 0.5 - 0.02), top - 0.01, DEPTH * 0.5 + 0.01)
			for leaf: Array in [[Vector3(-0.09, 0.03, 0.0), Vector3(0.16, 0.06, 0.04)], [Vector3(0.05, 0.09, 0.005), Vector3(0.12, 0.055, 0.04)], [Vector3(0.0, -0.05, 0.01), Vector3(0.1, 0.05, 0.04)]]:
				_box(face, leaf[1], c + Vector3(leaf[0].x * cx, leaf[0].y, leaf[0].z), mats.leaf)
			_box(face, Vector3(0.06, 0.06, 0.05), c + Vector3(-0.03 * cx, 0.05, 0.035), mats.flower)

	# 文字：从上往下排，正文左对齐到内框左沿；英文标题下画一条黄铜分隔线
	var z := DEPTH * 0.5 + 0.006
	var y := size.y * 0.5 - MARGIN
	var keys := ["title_zh", "title_en", "body_zh", "body_en"].filter(func(k: String) -> bool: return t.has(k))
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		var x := 0.0 if b["align"] == HORIZONTAL_ALIGNMENT_CENTER else -inner * 0.5
		_text(face, b, Vector3(x, y, z), pixel, font, INKS.get(keys[i], INK))
		y -= float(b["h"]) + float(STYLE[keys[i]]["gap"])
		if keys[i] == "title_en" and i + 1 < blocks.size():
			_box(face, Vector3(inner * 0.6, 0.008, 0.004), Vector3(0.0, y + float(STYLE["title_en"]["gap"]) * 0.45, z), mats.brass)

	# 碰撞：整块立牌一个盒子，人走不穿
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if style == "wall":
		shape.size = Vector3(outer.x, outer.y + crest_h, 0.1)
		cs.position = Vector3(0.0, crest_h * 0.5, 0.05)
	else:
		shape.size = Vector3(outer.x + 0.06, top_y + 0.05, 0.25)
		cs.position = Vector3(0.0, (top_y + 0.05) * 0.5, -0.05)
	cs.shape = shape
	body.add_child(cs)
	sign.add_child(body)
	return sign


static func _text(parent: Node3D, b: Dictionary, pos: Vector3, pixel: float, font: Font, ink: Color) -> void:
	var l := Label3D.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 牌面本来就中英双语，不随界面语言替换
	l.text = b["text"]
	l.font = font
	l.font_size = b["px"]
	l.pixel_size = pixel
	l.modulate = ink
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.horizontal_alignment = b["align"]
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if int(b["wrap"]) > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = int(b["wrap"])
	l.position = pos
	parent.add_child(l)


## 立牌共用材质（全部经 ArtMaterials）：深色框木、浅色内框、石脚、黄铜、羊皮纸、发光徽记。
static func _materials() -> Dictionary:
	return {
		"dark": ArtMaterials.pbr("stained_pine", Color(0.78, 0.52, 0.33)),
		"light": ArtMaterials.pbr("brown_planks_05", Color(0.86, 0.62, 0.4)),
		"stone": ArtMaterials.pbr("rustic_stone_wall", Color(0.9, 0.88, 0.84)),
		"brass": ArtMaterials.flat(Color(0.86, 0.66, 0.3), 0.35, false, 0.8),
		"paper": ArtMaterials.parchment(),
		"glow": ArtMaterials.glow(Color(1.0, 0.82, 0.45), 2.4),
		"leaf": ArtMaterials.flat(Color(0.36, 0.58, 0.3), 0.8),
		"flower": ArtMaterials.glow(Color(1.0, 0.62, 0.82), 2.0),
	}


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
