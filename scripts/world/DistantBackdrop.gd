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
	var old_massif := get_node_or_null("SnowMassif")
	if old_massif != null:
		old_massif.free()
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
	_build_snow_massif()


## 东北角雪山背后的主峰群（world_layout.json → snow_peak.backdrop）：不规则的多棱锥，顶部约四成是雪，
## 雪线每条棱高低不一。只是远景（无碰撞），从湖边看过去和地图里能爬的雪山肩连成一座大雪山。
func _build_snow_massif() -> void:
	var peaks: Array = WorldLayout.section("snow_peak").get("backdrop", [])
	if peaks.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 8128
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var snow := SurfaceTool.new()
	snow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_y := SKIRT_HEIGHT - 5.0
	for pk: Dictionary in peaks:
		var c := WorldLayout.v2(pk["center"])
		var h := float(pk["height"])
		var r := float(pk["radius"])
		var seg := 9
		var apex := Vector3(c.x + rng.randf_range(-0.08, 0.08) * r, base_y + h, c.y + rng.randf_range(-0.08, 0.08) * r)
		var ring: Array[Vector3] = []
		var cap: Array[Vector3] = []
		for i in seg:
			var a := TAU * i / seg + rng.randf_range(-0.15, 0.15)
			var rr := r * rng.randf_range(0.75, 1.15)
			var b := Vector3(c.x + cos(a) * rr, base_y, c.y + sin(a) * rr)
			ring.append(b)
			cap.append(b.lerp(apex, float(pk.get("snow_from", 0.58)) + rng.randf_range(-0.07, 0.07)))
		var mid := Vector3(c.x, base_y, c.y)
		for i in seg:
			var j := (i + 1) % seg
			var out := (((ring[i] + ring[j]) * 0.5 - mid).normalized() + Vector3(0.0, r / h, 0.0)).normalized()
			MeshUtil.add_tri(rock, ring[i], ring[j], cap[j], out)
			MeshUtil.add_tri(rock, ring[i], cap[j], cap[i], out)
			MeshUtil.add_tri(snow, cap[i], cap[j], apex, out)
	# 岩石照常受距离雾影响；雪顶带一点自发光，隔着雾也是白亮的，从湖边看过去一眼就能认出来
	var rock_mat := MeshUtil.material(Color(0.4, 0.43, 0.52), 1.0)
	var snow_mat := MeshUtil.material(Color(0.92, 0.95, 1.0), 0.7)
	snow_mat.emission_enabled = true
	snow_mat.emission = Color(0.85, 0.9, 1.0)
	snow_mat.emission_energy_multiplier = 0.35
	var mesh := rock.commit()
	mesh.surface_set_material(0, rock_mat)
	snow.commit(mesh)
	mesh.surface_set_material(1, snow_mat)
	var massif := MeshInstance3D.new()
	massif.name = "SnowMassif"
	massif.mesh = mesh
	massif.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(massif)
