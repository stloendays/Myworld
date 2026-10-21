class_name SignBoard
extends Node3D
## 中英双语解说立牌：木框 + 米色面板，文字贴在面板上（不悬空）。正面朝本地 +Z。
## 文字在 data/world/signs.json（按 text id），室外立牌位置在 world_layout.json → signs，
## 建筑里的立牌由建筑脚本按自己的本地坐标放。只在运行时生成（字体来自 GameSettings）。
##   style = "stand"：双腿立牌；"lectern"：单柱斜面讲台牌（放在鱼缸、泳池边）；"wall"：挂墙牌（背面贴在本地 z = 0）。
## 牌面先量文字再定尺寸：宽度取 width 与标题宽度中较大者，高度按换行后的文字总高，文字永远不会出框。

const TEXT_PATH := "res://data/world/signs.json"
const INK := Color(0.16, 0.11, 0.07)
const PIXEL := 0.002          ## 1 字号像素 = 2 mm
const MARGIN := 0.08          ## 面板内边距（米）
const DEPTH := 0.06           ## 木框厚度
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

	# 再建：木框、面板、支架
	var wood := ArtMaterials.pbr("brown_planks_05", Color(0.62, 0.40, 0.25))
	var panel := ArtMaterials.flat(Color(0.93, 0.89, 0.80), 0.9)
	var face := Node3D.new()
	face.name = "Face"
	sign.add_child(face)
	var bottom := 0.0
	var top_y := size.y
	match style:
		"stand":
			bottom = 0.75
			top_y = bottom + size.y
			for sx: float in [-1.0, 1.0]:
				_box(sign, Vector3(0.08, top_y + 0.05, 0.08), Vector3(sx * (size.x * 0.5 - 0.12), (top_y + 0.05) * 0.5, -DEPTH), wood)
			face.position = Vector3(0.0, bottom + size.y * 0.5, 0.0)
		"lectern":
			bottom = 0.95
			var tilt := deg_to_rad(LECTERN_TILT)
			top_y = bottom + size.y * cos(tilt)
			_box(sign, Vector3(0.1, bottom + 0.05, 0.1), Vector3(0.0, (bottom + 0.05) * 0.5, -0.05), wood)
			_box(sign, Vector3(maxf(size.x * 0.5, 0.4), 0.04, 0.4), Vector3(0.0, 0.02, -0.05), wood)
			face.position = Vector3(0.0, bottom + size.y * 0.5 * cos(tilt), -0.05)
			face.rotation.x = -tilt
		"wall":
			face.position = Vector3(0.0, 0.0, DEPTH * 0.5 + 0.005)
	_box(face, Vector3(size.x + 0.08, size.y + 0.08, DEPTH), Vector3.ZERO, wood)
	_box(face, Vector3(size.x - 0.02, size.y - 0.02, 0.012), Vector3(0.0, 0.0, DEPTH * 0.5 + 0.006), panel)

	# 文字：从上往下排，正文左对齐到内框左沿
	var z := DEPTH * 0.5 + 0.014
	var y := size.y * 0.5 - MARGIN
	var keys := ["title_zh", "title_en", "body_zh", "body_en"].filter(func(k: String) -> bool: return t.has(k))
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		var x := 0.0 if b["align"] == HORIZONTAL_ALIGNMENT_CENTER else -inner * 0.5
		_text(face, b, Vector3(x, y, z), pixel, font)
		y -= float(b["h"]) + float(STYLE[keys[i]]["gap"])

	# 碰撞：整块立牌一个盒子，人走不穿
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if style == "wall":
		shape.size = Vector3(size.x + 0.08, size.y + 0.08, 0.1)
		cs.position = Vector3(0.0, 0.0, 0.05)
	else:
		shape.size = Vector3(size.x + 0.1, top_y + 0.05, 0.25)
		cs.position = Vector3(0.0, (top_y + 0.05) * 0.5, -0.05)
	cs.shape = shape
	body.add_child(cs)
	sign.add_child(body)
	return sign


static func _text(parent: Node3D, b: Dictionary, pos: Vector3, pixel: float, font: Font) -> void:
	var l := Label3D.new()
	l.text = b["text"]
	l.font = font
	l.font_size = b["px"]
	l.pixel_size = pixel
	l.modulate = INK
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


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
