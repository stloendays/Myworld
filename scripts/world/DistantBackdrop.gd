@tool
class_name DistantBackdrop
extends Node3D
## 地图边界以外的远山剪影（无碰撞、不投影），配合高度雾给出“边界之外还有世界”的纵深。

const GENERATED := "Generated"
const PEAKS := 60
const SKIRT_HEIGHT := 30.0


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in PEAKS:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / PEAKS
		var dist := rng.randf_range(250.0, 380.0)
		var center := Vector3(cos(a) * dist, 0.0, sin(a) * dist)
		MeshUtil.add_cone(st, center, SKIRT_HEIGHT - 5.0, rng.randf_range(45.0, 110.0), rng.randf_range(55.0, 95.0), 6, rng.randf() * TAU)
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshUtil.material(Color(0.17, 0.17, 0.30), 1.0))
	# 地图之外的“台地”：一圈环绕方形地形的平面，略低于地形外缘（外缘高度 > 30 m），
	# 从地图内看不到接缝，从高处看不会露出天空底色。
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := WorldTerrain.extent() - 0.5
	var o := 650.0
	var y := SKIRT_HEIGHT
	var rings := [
		[Vector3(-o, y, -o), Vector3(o, y, -o), Vector3(o, y, -e), Vector3(-o, y, -e)],
		[Vector3(-o, y, e), Vector3(o, y, e), Vector3(o, y, o), Vector3(-o, y, o)],
		[Vector3(-o, y, -e), Vector3(-e, y, -e), Vector3(-e, y, e), Vector3(-o, y, e)],
		[Vector3(e, y, -e), Vector3(o, y, -e), Vector3(o, y, e), Vector3(e, y, e)],
	]
	for q in rings:
		MeshUtil.add_tri(skirt, q[0], q[1], q[2], Vector3.UP)
		MeshUtil.add_tri(skirt, q[0], q[2], q[3], Vector3.UP)
	skirt.commit(mesh)
	mesh.surface_set_material(1, MeshUtil.material(Color(0.13, 0.15, 0.16), 1.0))
	var mi := MeshInstance3D.new()
	mi.name = GENERATED
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
