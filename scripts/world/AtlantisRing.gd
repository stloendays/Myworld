class_name AtlantisRing
extends Node3D
## 湖畔泳池馆地下海洋大缸底部的古老石环（PoolHouse 放在它的局部坐标里，位置见 world_layout.json → atlantis_ring）：
## 一圈长着青苔的石块围成竖立的环，石块上有发光的山铜刻纹，环里是一层微微发亮的水纹光门。
## 潜下去从环里游过去（身体穿过环面）就去亚特兰蒂斯；看着它按 E 也行（FairyPortal）。联机时照 WorldTravel 的规则不能去。

const PORTAL_SHADER := preload("res://shaders/fairy_portal.gdshader")

var target_world := "world_04"
var radius := 1.3
var portal: FairyPortal = null
var _was_inside := false
var _cooldown := 2.0     ## 刚到（从亚特兰蒂斯回来）的两秒里不触发


static func create(cfg: Dictionary, sand_y: float) -> AtlantisRing:
	var r := AtlantisRing.new()
	r.name = "AtlantisRing"
	var l: Array = cfg["local"]
	r.position = Vector3(float(l[0]), sand_y + float(cfg.get("lift", 1.75)), float(l[1]))
	r.radius = float(cfg.get("radius", 1.3))
	r.target_world = str(cfg.get("world", "world_04"))
	r._build()
	return r


func _build() -> void:
	add_to_group("atlantis_ring")
	var stone := ArtMaterials.pbr("rock_face_03", Color(0.66, 0.64, 0.6), "world", -0.1)   # 和大缸里的礁石同一种石头
	var glyph := ArtMaterials.glow(Color(1.0, 0.5, 0.22), 2.4)
	var n := 14
	for i in n:
		var a := float(i) / n * TAU
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.62, 0.5)
		mi.mesh = bm
		mi.material_override = stone
		# 环面是 YZ 平面（人沿 X 方向穿过）
		mi.transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(0.0, cos(a) * (radius + 0.3), sin(a) * (radius + 0.3)))
		add_child(mi)
		if i % 2 == 0:
			var g := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(0.52, 0.12, 0.2)
			g.mesh = gm
			g.material_override = glyph
			g.transform = mi.transform
			add_child(g)
	# 两块底座石，把环立在沙上
	for sz: float in [-1.0, 1.0]:
		var base := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.7, 0.5, 0.7)
		base.mesh = bb
		base.material_override = stone
		base.position = Vector3(0.0, -radius - 0.3, sz * 0.7)
		add_child(base)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	face.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	face.material_override = mat
	face.rotation.y = PI * 0.5
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	portal = FairyPortal.create(&"atlantis_ring", target_world, Vector2(radius * 1.6, radius * 1.6))
	portal.rotation.y = PI * 0.5
	add_child(portal)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var p := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if p == null:
		return
	var inside := contains(p.global_position + Vector3(0.0, 0.9, 0.0))
	if inside and not _was_inside and _cooldown <= 0.0 and p.swimming and not WorldTravel.busy:
		_cooldown = 3.0
		WorldRegistry.enter(target_world)
	_was_inside = inside


## 这一点在不在环面里（环面前后各 0.6 m 的薄片）。
func contains(world_point: Vector3) -> bool:
	var l := to_local(world_point)
	return absf(l.x) < 0.6 and Vector2(l.y, l.z).length() < radius
