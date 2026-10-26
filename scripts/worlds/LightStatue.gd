class_name LightStatue
extends Interactable
## 亚特兰蒂斯光束谜题的捧镜雕像：石座上一个方块人像，双手捧着一面圆铜镜。看着它按 E 转 45°（八个朝向），
## 镜子朝哪边，照到它的光就往哪边传（World04 每次转动后重新追光路）。朝向记成 "dir:N" 按 uid 存进 WorldState。

signal turned(statue: LightStatue)

const STONE_COLORS := {"robe": Color(0.86, 0.84, 0.78), "robe2": Color(0.78, 0.76, 0.7), "skin": Color(0.9, 0.88, 0.82),
	"hair": Color(0.7, 0.68, 0.62), "base": Color(0.6, 0.62, 0.6)}

var dir := 0                 ## 0 = 北，2 = 东，4 = 南，6 = 西
var correct := 0
var lit := false             ## 光照到它了
var _turner: Node3D
var _mirror_mat: StandardMaterial3D
var _glow: MeshInstance3D


static func create(id: String, start_dir: int, correct_dir: int) -> LightStatue:
	var s := LightStatue.new()
	s.name = "Statue_" + id
	s.uid = StringName(id)
	s.display_name = "捧镜雕像"
	s.dir = start_dir
	s.correct = correct_dir
	s._build()
	return s


static func dir_vector(d: int) -> Vector2:
	var a := float(posmod(d, 8)) * PI * 0.25
	return Vector2(sin(a), -cos(a))


func _build() -> void:
	var base := ArtMaterials.pbr("rustic_stone_wall", Color(0.7, 0.74, 0.74), "world")
	var plinth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.6, 1.3)
	plinth.mesh = bm
	plinth.material_override = base
	plinth.position = Vector3(0.0, 0.3, 0.0)
	add_child(plinth)
	_turner = Node3D.new()
	_turner.name = "Turner"
	_turner.position = Vector3(0.0, 0.6, 0.0)
	add_child(_turner)
	# 方块人像（面朝 -Z = 镜子朝向），像素 0.07 m
	var px := [
		[-3, 0, -2, 3, 12, 2, "robe"], [-3.5, 0, -2.5, 3.5, 3, 2.5, "robe2"], [-2, 12, -2, 2, 17, 2, "skin"],
		[-2.2, 15.5, -2.2, 2.2, 17.5, 2.2, "hair"], [-4, 7, -5, -2.5, 10, -1, "robe2"], [2.5, 7, -5, 4, 10, -1, "robe2"],
	]
	var boxes := []
	for p: Array in px:
		boxes.append({"box": p.slice(0, 6), "color": p[6]})
	var fig := MeshInstance3D.new()
	fig.mesh = BlockyMesh.build(boxes, func(k: String) -> Color: return STONE_COLORS.get(k, Color.WHITE), 0.07)
	_turner.add_child(fig)
	_mirror_mat = ArtMaterials.flat(Color(0.9, 0.7, 0.4), 0.15, false, 0.95).duplicate() as StandardMaterial3D
	var mirror := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.06
	cm.radial_segments = 24
	mirror.mesh = cm
	mirror.material_override = _mirror_mat
	mirror.rotation.x = PI * 0.5
	mirror.position = Vector3(0.0, 1.4, -0.45)   # 镜心高 0.6 + 1.4 = 2.0 m（光束高度由 World04 定）
	_turner.add_child(mirror)
	_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_glow.mesh = sm
	_glow.material_override = ArtMaterials.glow(Color(1.0, 0.8, 0.45), 4.0)
	_glow.position = Vector3(0.0, 1.4, -0.52)
	_glow.visible = false
	_turner.add_child(_glow)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 2.6, 1.3)
	cs.shape = shape
	cs.position = Vector3(0.0, 1.3, 0.0)
	body.add_child(cs)
	add_child(body)
	_apply_dir()


func get_prompt(_actor: Node) -> String:
	return "E  转动雕像（45°）"


func interact(_actor: Node) -> void:
	set_dir(dir + 1)
	_publish_state()


func set_dir(d: int) -> void:
	dir = posmod(d, 8)
	_apply_dir()
	turned.emit(self)


func set_lit(on: bool) -> void:
	lit = on
	_glow.visible = on
	_mirror_mat.emission_enabled = on
	_mirror_mat.emission = Color(1.0, 0.75, 0.4)
	_mirror_mat.emission_energy_multiplier = 1.5


func _apply_dir() -> void:
	var v := dir_vector(dir)
	_turner.rotation.y = atan2(-v.x, -v.y)


func get_state() -> String:
	return "dir:%d" % dir


func apply_state(state: String) -> void:
	if state.begins_with("dir:"):
		set_dir(int(state.substr(4)))
