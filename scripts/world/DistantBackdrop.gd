@tool
class_name DistantBackdrop
extends Node3D
## 地图边界以外的远山（无碰撞、不投影），配合高度雾给出“边界之外还有世界”的纵深。
## 两层山：近处一圈较低、颜色较深的山（距中心约 210–270 m），远处一圈更高、颜色较浅的山（约 330–430 m），
## 远层最高的几座带雪顶。每座山形状都不一样：
##   · 底圈 10–13 个点、半径各不相同，有的沿切线方向拉长成山脊；
##   · 半山腰一圈“山肩”高低错落，轮廓线不再是一条直线；
##   · 山尖偏离中心，一边陡一边缓；
##   · 一部分山旁边再长一座矮一些的副峰。
## 东北方向留给雪山背后的雪顶主峰群（world_layout.json → snow_peak.backdrop），普通远山不放在那里。
## 颜色写在顶点色里：山脚深、山顶浅；雾再把远层冲淡一些。

const GENERATED := "Generated"
const SKIRT_HEIGHT := 30.0
const BASE_Y := SKIRT_HEIGHT - 5.0
## [数量, 最近距离, 最远距离, 最矮, 最高, 底半径下限, 底半径上限, 山色]
const LAYERS := [
	[9, 235.0, 290.0, 40.0, 75.0, 50.0, 85.0, Color(0.16, 0.19, 0.24)],
	[7, 340.0, 440.0, 95.0, 160.0, 80.0, 130.0, Color(0.27, 0.30, 0.40)],
]
const SNOW_ABOVE := 125.0                     ## 远层高于这个高度的山带雪顶
const SNOW_COLOR := Color(0.86, 0.89, 0.95)
const KEEP_CLEAR_DEG := -45.0                 ## 雪山主峰群所在的方向（东北）
const KEEP_CLEAR_HALF := 26.0


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for n in [GENERATED, "SnowMassif"]:
		var old := get_node_or_null(n)
		if old != null:
			old.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for li in LAYERS.size():
		var layer: Array = LAYERS[li]
		var count := int(layer[0])
		var offset := rng.randf() * TAU
		for i in count:
			var a := offset + TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / count
			if absf(wrapf(rad_to_deg(a) - KEEP_CLEAR_DEG, -180.0, 180.0)) < KEEP_CLEAR_HALF:
				continue
			var dist := rng.randf_range(layer[1], layer[2])
			var center := Vector2(cos(a), sin(a)) * dist
			var h := rng.randf_range(layer[3], layer[4])
			var r := rng.randf_range(layer[5], layer[6])
			var tangent := Vector2(-sin(a), cos(a))
			var stretch := rng.randf_range(1.0, 1.9) if rng.randf() < 0.5 else 1.0
			var tint: Color = layer[7] * rng.randf_range(0.88, 1.12)
			var snow := li == 1 and h > SNOW_ABOVE
			_mountain(st, null, center, h, r, tangent, stretch, tint, 0.62 if snow else 2.0, rng)
			# 一半的山旁边再长一座副峰（沿切线方向，矮一些）
			if rng.randf() < 0.5:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var sub_c := center + tangent * side * r * rng.randf_range(0.6, 0.95)
				var sub_h := h * rng.randf_range(0.55, 0.78)
				_mountain(st, null, sub_c, sub_h, r * rng.randf_range(0.55, 0.8), tangent, rng.randf_range(1.0, 1.5), tint * 0.96,
					0.62 if li == 1 and sub_h > SNOW_ABOVE else 2.0, rng)
	var mesh := st.commit()
	var mat := MeshUtil.material(Color.WHITE, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mesh.surface_set_material(0, mat)
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


## 一座山：底圈 → 两圈错落的山腰 → 偏心的山尖。profile 在“尖峰”和“圆顶”之间随机：
## 尖峰的上圈又窄又高，轮廓陡；圆顶的上圈宽而低，轮廓圆。每圈每个点的高度和半径都再抖一点，轮廓线有好几处转折。
## snow_from：上圈到山尖之间从这个比例开始积雪（≥ 1 表示不积雪）；snow_st 不为空时雪面单独放进去（雪山主峰群用）。
func _mountain(st: SurfaceTool, snow_st: SurfaceTool, c: Vector2, h: float, r: float, tangent: Vector2, stretch: float,
		tint: Color, snow_from: float, rng: RandomNumberGenerator) -> void:
	var seg := rng.randi_range(11, 14)
	var phase := rng.randf() * TAU
	var lean := Vector2(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.22, 0.22)) * r
	var apex := Vector3(c.x + lean.x, BASE_Y + h, c.y + lean.y)
	var normal_dir := Vector2(-tangent.y, tangent.x)
	var p := rng.randf()                                    # 0 尖峰 … 1 圆顶
	var fracs := [[1.0, 0.0], [lerpf(0.72, 0.88, p), lerpf(0.32, 0.24, p)], [lerpf(0.4, 0.64, p), lerpf(0.66, 0.54, p)]]
	var rings: Array = []                                   # rings[k][i]：第 k 圈第 i 个点
	for k in fracs.size():
		rings.append([])
	for i in seg:
		var a := phase + TAU * i / seg + rng.randf_range(-0.12, 0.12)
		var d := Vector2(cos(a), sin(a))
		var local := tangent * d.dot(tangent) * stretch + normal_dir * d.dot(normal_dir)
		var reach := r * rng.randf_range(0.8, 1.15)
		for k in fracs.size():
			var rf := float(fracs[k][0]) * (1.0 if k == 0 else rng.randf_range(0.88, 1.12))
			var hf := float(fracs[k][1]) * (1.0 if k == 0 else rng.randf_range(0.85, 1.15))
			var xz := c.lerp(Vector2(apex.x, apex.z), hf) + local * reach * rf
			rings[k].append(Vector3(xz.x, BASE_Y + h * hf, xz.y))
	var top_col := tint.lerp(Color(0.62, 0.66, 0.76), 0.3)
	var cols := [tint * 0.8, tint.lerp(top_col, 0.35), tint.lerp(top_col, 0.7)]
	var mid := Vector3(c.x, BASE_Y, c.y)
	var snowy := snow_from < 1.0
	for i in seg:
		var j := (i + 1) % seg
		var b0: Vector3 = rings[0][i]
		var b1: Vector3 = rings[0][j]
		var out := ((b0 + b1) * 0.5 - mid).normalized() + Vector3(0.0, 0.45, 0.0)
		for k in fracs.size() - 1:
			var lo: Array = rings[k]
			var hi: Array = rings[k + 1]
			_tri(st, lo[i], lo[j], hi[j], cols[k], cols[k], cols[k + 1], out)
			_tri(st, lo[i], hi[j], hi[i], cols[k], cols[k + 1], cols[k + 1], out)
		var top: Array = rings[fracs.size() - 1]
		if snowy:
			# 上圈到山尖：从 snow_from 处切开，下段岩石、上段是雪（每条棱的雪线高低不一）
			var ci: Vector3 = top[i].lerp(apex, clampf(snow_from + rng.randf_range(-0.12, 0.08), 0.0, 0.9))
			var cj: Vector3 = top[j].lerp(apex, clampf(snow_from + rng.randf_range(-0.12, 0.08), 0.0, 0.9))
			_tri(st, top[i], top[j], cj, cols[2], cols[2], top_col, out)
			_tri(st, top[i], cj, ci, cols[2], top_col, top_col, out)
			var target := snow_st if snow_st != null else st
			_tri(target, ci, cj, apex, SNOW_COLOR, SNOW_COLOR, SNOW_COLOR, out)
		else:
			_tri(st, top[i], top[j], apex, cols[2], cols[2], top_col, out)


## 带顶点色的平面三角形（绕序按外法线纠正）。
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	n = n.normalized()
	for v in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(v[1])
		st.add_vertex(v[0])


## 东北角雪山背后的主峰群（world_layout.json → snow_peak.backdrop）：同样的造山方法，雪面单独一个材质，
## 带一点自发光，隔着雾也是白亮的，从湖边看过去和地图里能爬的雪山肩连成一座大雪山。
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
	for pk: Dictionary in peaks:
		var c := WorldLayout.v2(pk["center"])
		var a := atan2(c.y, c.x)
		var tangent := Vector2(-sin(a), cos(a))
		# 主峰的山肩以上就开始积雪（snow_from 相对山肩到山尖）
		_mountain(rock, snow, c, float(pk["height"]), float(pk["radius"]), tangent, 1.25, Color(0.4, 0.43, 0.52),
			clampf(float(pk.get("snow_from", 0.5)) - 0.35, 0.0, 0.5), rng)
	var rock_mat := MeshUtil.material(Color.WHITE, 1.0)
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.vertex_color_is_srgb = true
	var snow_mat := MeshUtil.material(Color.WHITE, 0.7)
	snow_mat.vertex_color_use_as_albedo = true
	snow_mat.vertex_color_is_srgb = true
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
