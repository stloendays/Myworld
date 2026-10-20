class_name MeshUtil
extends RefCounted
## 程序化低多边形几何的小工具：平面着色三角形、棱台、圆锥、沿 X 轴挤出的凸多边形。
## Godot 以顺时针为正面；add_tri 根据给定的外法线自动纠正绕序。


static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


## 竖直棱台（侧面，无顶底），用于树干、桩子。
static func add_frustum(st: SurfaceTool, base: Vector3, y0: float, y1: float, r0: float, r1: float,
		segments: int, phase := 0.0) -> void:
	for i in segments:
		var a0 := phase + TAU * float(i) / segments
		var a1 := phase + TAU * float(i + 1) / segments
		var b0 := base + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := base + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := base + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := base + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var mid := (a0 + a1) * 0.5
		var out := Vector3(cos(mid), 0.0, sin(mid))
		add_tri(st, b0, t0, t1, out)
		add_tri(st, b0, t1, b1, out)


## 圆锥（侧面 + 底面），用于针叶树冠、远山。
static func add_cone(st: SurfaceTool, base: Vector3, y0: float, height: float, radius: float,
		segments: int, phase := 0.0) -> void:
	var apex := base + Vector3(0.0, y0 + height, 0.0)
	var center := base + Vector3(0.0, y0, 0.0)
	for i in segments:
		var a0 := phase + TAU * float(i) / segments
		var a1 := phase + TAU * float(i + 1) / segments
		var p0 := center + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var mid := (a0 + a1) * 0.5
		add_tri(st, apex, p0, p1, Vector3(cos(mid), radius / height, sin(mid)))
		add_tri(st, center, p1, p0, Vector3.DOWN)


## 把 (z, y) 平面上的凸多边形沿 X 轴挤出为厚板，中心在 x_center。
static func add_prism_x(st: SurfaceTool, poly: PackedVector2Array, x_center: float, thickness: float) -> void:
	var x0 := x_center - thickness * 0.5
	var x1 := x_center + thickness * 0.5
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	for i in range(1, poly.size() - 1):
		var a := poly[0]
		var b := poly[i]
		var c := poly[i + 1]
		add_tri(st, Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x1, c.y, c.x), Vector3.RIGHT)
		add_tri(st, Vector3(x0, a.y, a.x), Vector3(x0, b.y, b.x), Vector3(x0, c.y, c.x), Vector3.LEFT)
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var mid := (p + q) * 0.5 - centroid
		var out := Vector3(0.0, mid.y, mid.x)
		add_tri(st, Vector3(x0, p.y, p.x), Vector3(x1, p.y, p.x), Vector3(x1, q.y, q.x), out)
		add_tri(st, Vector3(x0, p.y, p.x), Vector3(x1, q.y, q.x), Vector3(x0, q.y, q.x), out)


static func prism_x_points(poly: PackedVector2Array, x_center: float, thickness: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(x_center - thickness * 0.5, p.y, p.x))
		pts.append(Vector3(x_center + thickness * 0.5, p.y, p.x))
	return pts


static func material(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
