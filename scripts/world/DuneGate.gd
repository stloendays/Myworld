class_name DuneGate
extends Node3D
## 南部草甸西边的沙之门（world_layout.json → dune_gate）：砂岩石拱，拱里一道暖色光门，看着按 E 去世界三「琥珀沙丘」。
## 石拱两根立柱有碰撞，人从拱前走过不会穿进去；回来时站在门前（worlds.json → dusk_lake.arrivals.world_03）。

const PORTAL_SHADER := preload("res://shaders/fairy_portal.gdshader")

var portal: FairyPortal = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var cfg := WorldLayout.section("dune_gate")
	if cfg.is_empty():
		return
	add_to_group("dune_gate")
	var c := WorldLayout.v2(cfg["center"])
	position = Vector3(c.x, WorldTerrain.height_at(c.x, c.y) - 0.15, c.y)
	rotation.y = deg_to_rad(float(cfg.get("yaw_deg", 0.0)))
	var sand := ArtMaterials.pbr("rustic_stone_wall", Color(0.98, 0.78, 0.56), "world")
	var dark := ArtMaterials.pbr("rustic_stone_wall", Color(0.78, 0.58, 0.42), "world")
	for sx: float in [-1.0, 1.0]:
		_block(Vector3(1.0, 4.6, 1.0), Vector3(sx * 2.0, 2.3, 0.0), sand, true)
		_block(Vector3(1.4, 0.5, 1.4), Vector3(sx * 2.0, 0.25, 0.0), dark, true)
		_block(Vector3(1.3, 0.35, 1.3), Vector3(sx * 2.0, 4.75, 0.0), dark, false)
	_block(Vector3(5.6, 0.7, 1.2), Vector3(0.0, 5.25, 0.0), sand, false)
	_block(Vector3(3.2, 0.5, 1.0), Vector3(0.0, 5.85, 0.0), dark, false)
	# 拱顶上一块发光的琥珀
	var gem := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.5, 0.7, 0.3)
	gem.mesh = pm
	gem.material_override = ArtMaterials.glow(Color(1.0, 0.7, 0.3), 3.0)
	gem.position = Vector3(0.0, 6.45, 0.0)
	add_child(gem)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 4.3)
	face.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	face.material_override = mat
	face.position = Vector3(0.0, 2.55, 0.0)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	portal = FairyPortal.create(&"dune_gate", str(cfg.get("world", "world_03")), Vector2(3.0, 4.2))
	portal.position = Vector3(0.0, 2.4, 0.0)
	add_child(portal)


func _block(size: Vector3, pos: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = PhysicsLayers.WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		body.add_child(cs)
		add_child(body)
