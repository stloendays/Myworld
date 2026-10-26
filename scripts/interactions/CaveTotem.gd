class_name CaveTotem
extends Interactable
## 图腾山洞里会说话的老图腾：三节雕刻木柱叠在石座上，顶上一对展开的木翅膀，眼睛是会发光的青色方块。
## 看着它按 E 打开对话（DialoguePanel）：先谢谢你完成的任务，再给下一个任务（QuestLog）。
## 有新任务可接（或暮烬之夜有故事要讲）时，头顶有一颗慢慢转的金色菱形；说话时眼睛更亮。本节点原点在石座底面中心，+Z 是脸朝的方向。

const PX := 0.1   ## 雕刻细节的方块边长（米）

var marker: MeshInstance3D
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _talking := false
var _t := 0.0


static func create(id: StringName) -> CaveTotem:
	var t := CaveTotem.new()
	t.name = "Totem"
	t.uid = id
	t.display_name = "老图腾"
	return t


func _ready() -> void:
	add_to_group("cave_totem")
	_build()
	super()


func get_prompt(_actor: Node) -> String:
	return "E  和老图腾说话"


func interact(actor: Node) -> void:
	var panel := get_tree().get_first_node_in_group("dialogue_panel") as DialoguePanel
	if panel != null:
		panel.open_totem(self, actor as FirstPersonController)


func set_talking(on: bool) -> void:
	_talking = on


func _process(delta: float) -> void:
	_t += delta
	var story := get_tree().get_first_node_in_group("story_director") as StoryDirector
	var has_offer := not QuestLog.next_offer().is_empty() or not QuestLog.unthanked().is_empty() \
		or (story != null and story.finale_ready())
	marker.visible = has_offer and not _talking
	if marker.visible:
		marker.rotation.y = _t * 1.6
		marker.position.y = 4.75 + sin(_t * 2.2) * 0.08
	var glow := 4.5 if _talking else 2.2 + sin(_t * 1.3) * 0.4
	_eye_mat.emission_energy_multiplier = glow


# ---------------------------------------------------------------- 外观

func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var stone := Color(0.42, 0.41, 0.4)
	var wood_dark := Color(0.32, 0.2, 0.13)
	var wood := Color(0.55, 0.33, 0.18)
	var red := Color(0.62, 0.2, 0.14)
	var teal := Color(0.18, 0.5, 0.48)
	var cream := Color(0.88, 0.82, 0.68)
	var black := Color(0.08, 0.06, 0.05)
	var orange := Color(0.9, 0.55, 0.18)
	# 石座
	_box(st, Vector3(0.0, 0.2, 0.0), Vector3(1.5, 0.4, 1.5), stone)
	_box(st, Vector3(0.0, 0.45, 0.0), Vector3(1.25, 0.12, 1.25), stone.darkened(0.15))
	# 第一节：低头的熊脸（深色木）
	_box(st, Vector3(0.0, 1.05, 0.0), Vector3(1.05, 1.1, 1.05), wood_dark)
	_box(st, Vector3(0.0, 1.45, 0.53), Vector3(0.8, 0.12, 0.04), black)          # 眉
	_box(st, Vector3(-0.22, 1.25, 0.535), Vector3(0.2, 0.14, 0.04), cream)      # 眼白
	_box(st, Vector3(0.22, 1.25, 0.535), Vector3(0.2, 0.14, 0.04), cream)
	_box(st, Vector3(0.0, 1.0, 0.56), Vector3(0.24, 0.3, 0.1), wood)            # 鼻
	_box(st, Vector3(0.0, 0.72, 0.535), Vector3(0.6, 0.12, 0.04), black)        # 嘴
	for i in 4:
		_box(st, Vector3(-0.21 + i * 0.14, 0.79, 0.545), Vector3(0.07, 0.06, 0.03), cream)   # 牙
	# 第二节：红色的鸟脸（会发光的眼睛另做）
	_box(st, Vector3(0.0, 2.1, 0.0), Vector3(0.98, 1.0, 0.98), red)
	_box(st, Vector3(0.0, 2.48, 0.5), Vector3(0.9, 0.1, 0.04), teal)
	_box(st, Vector3(0.0, 1.66, 0.5), Vector3(0.9, 0.1, 0.04), teal)
	_box(st, Vector3(-0.24, 2.22, 0.5), Vector3(0.3, 0.22, 0.04), black)        # 眼眶
	_box(st, Vector3(0.24, 2.22, 0.5), Vector3(0.3, 0.22, 0.04), black)
	_box(st, Vector3(0.0, 1.92, 0.62), Vector3(0.22, 0.2, 0.28), orange)        # 喙
	_box(st, Vector3(0.0, 1.82, 0.72), Vector3(0.14, 0.1, 0.12), orange.darkened(0.25))
	# 第三节：雷鸟头，两侧展翅
	_box(st, Vector3(0.0, 3.05, 0.0), Vector3(1.0, 0.9, 1.0), wood)
	_box(st, Vector3(-0.2, 3.15, 0.505), Vector3(0.16, 0.16, 0.04), black)
	_box(st, Vector3(0.2, 3.15, 0.505), Vector3(0.16, 0.16, 0.04), black)
	_box(st, Vector3(0.0, 2.88, 0.65), Vector3(0.18, 0.3, 0.3), cream)          # 弯喙
	_box(st, Vector3(0.0, 2.72, 0.76), Vector3(0.12, 0.12, 0.1), cream.darkened(0.2))
	for side: float in [-1.0, 1.0]:
		for f in 4:
			var reach := 0.62 + f * 0.36
			var col := [teal, cream, red, teal][f] as Color
			_box(st, Vector3(side * reach, 3.25 + f * 0.09, 0.0), Vector3(0.34, 0.22 + f * 0.05, 0.16), col)
		_box(st, Vector3(side * 1.95, 3.6, 0.0), Vector3(0.22, 0.5, 0.14), cream)   # 翼尖
	# 头顶羽冠
	for i in 5:
		var x := -0.32 + i * 0.16
		_box(st, Vector3(x, 3.65 + absf(i - 2) * -0.06 + 0.12, -0.05), Vector3(0.12, 0.38 - absf(i - 2) * 0.06, 0.1), [red, orange, cream, orange, red][i] as Color)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Carving"
	mi.mesh = st.commit()
	mi.material_override = ArtMaterials.flat(Color.WHITE, 0.85, true)
	add_child(mi)
	# 第二节会发光的眼睛
	_eye_mat = ArtMaterials.glow(Color(0.35, 1.0, 0.9), 2.2).duplicate() as StandardMaterial3D
	for x: float in [-0.24, 0.24]:
		var eye := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.1, 0.04)
		eye.mesh = bm
		eye.material_override = _eye_mat
		eye.position = Vector3(x, 2.22, 0.525)
		add_child(eye)
		_eyes.append(eye)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 2.2, 0.9)
	glow.light_color = Color(0.4, 1.0, 0.9)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	add_child(glow)
	# 有新任务时的金色菱形
	marker = MeshInstance3D.new()
	marker.name = "QuestMarker"
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 0.16
	prism.height = 0.28
	prism.radial_segments = 4
	var top := prism
	marker.mesh = top
	marker.material_override = ArtMaterials.glow(Color(1.0, 0.8, 0.3), 3.0)
	marker.position = Vector3(0.0, 4.75, 0.0)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bottom := MeshInstance3D.new()
	var prism2 := prism.duplicate() as CylinderMesh
	bottom.mesh = prism2
	bottom.material_override = marker.material_override
	bottom.rotation.x = PI
	bottom.position = Vector3(0.0, -0.28, 0.0)
	bottom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(bottom)
	add_child(marker)
	# 碰撞：整根柱子；交互盒包住脸，准星看哪一节都能对话
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 3.8, 1.2)
	cs.shape = shape
	cs.position = Vector3(0.0, 1.9, 0.0)
	body.add_child(cs)
	add_child(body)
	var hit := StaticBody3D.new()
	hit.collision_layer = PhysicsLayers.INTERACTABLE
	hit.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hshape := BoxShape3D.new()
	hshape.size = Vector3(1.6, 3.6, 1.6)
	hcs.shape = hshape
	hcs.position = Vector3(0.0, 2.0, 0.05)
	hit.add_child(hcs)
	add_child(hit)


func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var corners := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	# 每个面四个角（从外面看顺时针，Godot 的正面）
	var faces := [[4, 7, 6, 5], [1, 2, 3, 0], [5, 6, 2, 1], [0, 3, 7, 4], [7, 3, 2, 6], [0, 4, 5, 1]]
	st.set_color(col)
	for f: Array in faces:
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var cc: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(cc)
		st.add_vertex(a)
		st.add_vertex(cc)
		st.add_vertex(d)
