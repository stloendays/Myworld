class_name LetterSpot
extends Interactable
## 放着一封划船人的信的地方（PaddlerStory）：kind = book（木屋书架顶上的旧书，信纸露出一角）、
## crate（码头尽头的旧木盒）、tin（湖心小岛营火边石头上的铁盒）；chart 是石头小屋桌上的星图（纸由 StoneCottage 画，这里只管能看）。
## 看着它按 E 打开 LetterPanel 读信；读过还能再读。读信只改本机玩家自己的记录（WorldState.flags.letters），
## 不是世界状态，所以 get_state 为空。
## 本节点原点在物件底面中心，+Z 是正面。

var letter_id := ""
var kind := ""


static func create(id: String, k: String) -> LetterSpot:
	var s := LetterSpot.new()
	s.name = "Letter_" + id
	s.uid = StringName("letter_" + id)
	s.letter_id = id
	s.kind = k
	s.display_name = "划船人的信"
	return s


func _ready() -> void:
	add_to_group("letter_spots")
	_build()
	super()


func get_prompt(_actor: Node) -> String:
	if kind == "chart":
		return tr("E  看星图")
	if PaddlerStory.is_read(letter_id):
		return tr("E  再读一遍")
	match kind:
		"book":
			return tr("E  翻开旧书")
		"crate":
			return tr("E  打开旧木盒")
	return tr("E  打开铁盒")


func interact(actor: Node) -> void:
	var panel := get_tree().get_first_node_in_group("letter_panel") as LetterPanel
	if panel == null:
		return
	if kind == "chart":
		panel.open_chart(actor as FirstPersonController)
	else:
		panel.open_letter(letter_id, actor as FirstPersonController)


# ---------------------------------------------------------------- 外观

func _build() -> void:
	var paper := ArtMaterials.flat(Color(0.93, 0.89, 0.78), 0.9)
	var solid := Vector3.ZERO          ## 挡人的碰撞盒（木盒、垫铁盒的石头）；书放在书架顶上不需要
	var hit := Vector3(0.45, 0.3, 0.4)  ## 准星能对上的范围，比物件大一圈
	match kind:
		"book":
			# 墨绿皮面（在木屋的暖色木头前看得出来），书脊一道铜边，信纸从书页间朝外露出一角
			var leather := ArtMaterials.flat(Color(0.14, 0.3, 0.26), 0.75)
			_box(Vector3(0.32, 0.065, 0.24), Vector3(0.0, 0.0325, 0.0), leather)
			_box(Vector3(0.3, 0.05, 0.225), Vector3(0.012, 0.033, 0.0), paper)
			_box(Vector3(0.006, 0.066, 0.24), Vector3(-0.16, 0.033, 0.0), ArtMaterials.flat(Color(0.72, 0.56, 0.25), 0.45, false, 0.7))
			var corner := _box(Vector3(0.12, 0.004, 0.12), Vector3(0.06, 0.036, 0.13), paper)
			corner.rotation.y = deg_to_rad(14.0)
		"crate":
			var wood := ArtMaterials.named("M_Deck")
			_box(Vector3(0.56, 0.32, 0.4), Vector3(0.0, 0.16, 0.0), wood)
			var lid := _box(Vector3(0.6, 0.05, 0.44), Vector3(0.0, 0.345, -0.03), wood)
			lid.rotation.x = deg_to_rad(-6.0)
			for x: float in [-0.2, 0.2]:
				_box(Vector3(0.04, 0.34, 0.42), Vector3(x, 0.17, 0.0), ArtMaterials.named("M_Metal"))
			_box(Vector3(0.16, 0.004, 0.11), Vector3(0.05, 0.374, 0.2), paper)
			solid = Vector3(0.56, 0.37, 0.4)
			hit = Vector3(0.7, 0.55, 0.6)
		"chart":
			hit = Vector3(0.62, 0.12, 0.45)
		_:
			var stone := ArtMaterials.named("M_Stone")
			_box(Vector3(0.62, 0.16, 0.5), Vector3(0.0, 0.08, 0.0), stone)
			var tin := ArtMaterials.flat(Color(0.45, 0.33, 0.22), 0.55, false, 0.7)
			_box(Vector3(0.32, 0.11, 0.23), Vector3(0.0, 0.215, 0.0), tin)
			_box(Vector3(0.34, 0.025, 0.25), Vector3(0.0, 0.282, 0.0), ArtMaterials.flat(Color(0.5, 0.26, 0.18), 0.5, false, 0.7))
			solid = Vector3(0.62, 0.16, 0.5)
			hit = Vector3(0.7, 0.5, 0.6)
	_body(PhysicsLayers.INTERACTABLE, hit)
	if solid != Vector3.ZERO:
		_body(PhysicsLayers.WORLD, solid)


func _body(layer: int, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi
