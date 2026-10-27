class_name MapArt
extends RefCounted
## 地图的画法，世界地图（Tab）、小地图和别的世界的地图共用，画成一张手绘风的地图：
##   底图像素：西北来光的山体明暗、等高线（每 4 根一根粗的）、纸面细纹、按树密度点出来的树冠（亮面朝西北）；
##   矢量层：描边的路、小溪、带投影的建筑图标、探索点图钉、光门、玩家和视野扇形、双线边框、八角指北针、分段比例尺、描边地名。
## 底图函数只用整数哈希、不碰场景，可以在后台线程里并行调用。

const PAPER := Color(0.92, 0.86, 0.72)          ## 纸色（边框、比例尺）
const PAPER_DARK := Color(0.24, 0.20, 0.16)     ## 图外压暗
const INK := Color(0.17, 0.12, 0.09)            ## 墨色（描边、等高线）
const LABEL := Color(0.99, 0.95, 0.86)
const PATH_FILL := Color(0.90, 0.82, 0.63)
const PATH_EDGE := Color(0.33, 0.25, 0.16, 0.75)
const CREEK := Color(0.36, 0.62, 0.76)
const CREEK_EDGE := Color(0.13, 0.27, 0.36, 0.8)
const GATE := Color(0.82, 0.66, 1.0)
const FOUND := Color(1.0, 0.80, 0.34)
const LIGHT_DIR := Vector3(-0.55, 1.0, -0.65)   ## 西北偏上来光（地图上北在上）


# ---------------------------------------------------------------- 底图像素（线程安全）

## 山体明暗：平地约等于 1，迎光坡亮、背光坡暗。hx、hz 是左右、上下两格的高度差，cell 是一格的米数。
static func hillshade(hx: float, hz: float, cell: float, strength := 1.0) -> float:
	var n := Vector3(-hx, 2.0 * cell, -hz).normalized()
	var l := LIGHT_DIR.normalized()
	return clampf(1.0 + (n.dot(l) - Vector3.UP.dot(l)) * 1.35 * strength, 0.5, 1.32)


## 等高线：这一格和右边、下边的格子跨过了 step 的整数倍就画线。返回 0 没有、1 细线、2 每 index 根的粗线。
static func contour(h: float, h_right: float, h_down: float, step: float, index := 4) -> int:
	var a := floori(h / step)
	var b := floori(h_right / step)
	var c := floori(h_down / step)
	if a == b and a == c:
		return 0
	return 2 if posmod(maxi(a, maxi(b, c)), index) == 0 else 1


## 纸面细纹：每个像素 1 ± amp。
static func grain(i: int, j: int, amp := 0.03) -> float:
	return 1.0 + (hash01(i, j) - 0.5) * 2.0 * amp


## 0..1 的整数哈希（同样的输入永远同样的结果，不用随机数生成器，线程安全）。
static func hash01(i: int, j: int) -> float:
	var h := (i * 374761393 + j * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## 树冠点：每 cell 像素一格，按树密度在格子里随机放一棵树（圆点）。
## 返回 Vector2(覆盖 0..1, 明暗 -1..1，西北边亮)；不在树冠里返回 (0, 0)。
static func canopy(i: int, j: int, density: float, cell := 6.0) -> Vector2:
	if density < 0.03:
		return Vector2.ZERO
	var best := Vector2.ZERO
	var ci := floori(i / cell)
	var cj := floori(j / cell)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var gi := ci + di
			var gj := cj + dj
			if hash01(gi * 7 + 1, gj * 13 + 5) > density * 1.15:
				continue
			var c := Vector2((gi + 0.2 + 0.6 * hash01(gi, gj + 101)) * cell, (gj + 0.2 + 0.6 * hash01(gi + 211, gj)) * cell)
			var rad := cell * (0.45 + 0.32 * hash01(gi + 17, gj + 29))
			var d := Vector2(i + 0.5, j + 0.5) - c
			var k := d.length() / rad
			if k < 1.0:
				var cover := clampf((1.0 - k) * 4.0, 0.0, 1.0)
				if cover > best.x:
					best = Vector2(cover, clampf(-(d.x + d.y) / (rad * 1.2), -1.0, 1.0))
	return best


# ---------------------------------------------------------------- 矢量层

## 路：深色描边 + 浅色路面（宽度是像素）。
static func draw_path(c: CanvasItem, pts: PackedVector2Array, width: float, fill := PATH_FILL, edge := PATH_EDGE) -> void:
	if pts.size() < 2:
		return
	c.draw_polyline(pts, edge, width + 2.2, true)
	c.draw_polyline(pts, fill, width, true)


## 湖畔的小溪（蓝线，画到流进湖为止）和裂谷（深色岩带，亮边）。在世界坐标的变换里调用，宽度是米。
static func draw_channels(c: CanvasItem) -> void:
	for ch: Dictionary in WorldTerrain.channels():
		var pts: PackedVector2Array = ch["pts"]
		var bed := float(ch["inner"]) * 2.0
		if str(ch["kind"]) == "creek":
			var wet := pts.slice(0, int(ch["wet_end"]) + 1)
			if wet.size() > 1:
				c.draw_polyline(wet, CREEK_EDGE, maxf(bed * 0.8, 1.6) + 1.2, true)
				c.draw_polyline(wet, CREEK, maxf(bed * 0.8, 1.6), true)
		elif pts.size() > 1:
			c.draw_polyline(pts, Color(0.30, 0.25, 0.21, 0.85), bed + 2.4, true)
			c.draw_polyline(pts, Color(0.13, 0.10, 0.09, 0.9), bed, true)


## 建筑图标：往东南偏一点的投影、填色、墨线描边，ridge 为真时沿长边画一条屋脊线。pts 已经是画面坐标。
static func draw_building(c: CanvasItem, pts: PackedVector2Array, fill: Color, ridge := true) -> void:
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(2.5, 3.0))
	c.draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.32))
	c.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	c.draw_polyline(closed, INK, 1.6, true)
	if ridge and pts.size() == 4:
		var long_a := (pts[0] + pts[3]) * 0.5
		var long_b := (pts[1] + pts[2]) * 0.5
		if pts[0].distance_to(pts[1]) < pts[1].distance_to(pts[2]):
			long_a = (pts[0] + pts[1]) * 0.5
			long_b = (pts[2] + pts[3]) * 0.5
		c.draw_line(long_a, long_b, Color(INK, 0.55), 1.2, true)


## 探索点图钉：找到了是金色带星的钉子，没找到是带问号的深色圆。
static func draw_pin(c: CanvasItem, p: Vector2, found: bool, font: Font, scale := 1.0) -> void:
	if found:
		var tip := p
		var head := p + Vector2(0.0, -14.0 * scale)
		c.draw_colored_polygon(PackedVector2Array([tip, head + Vector2(-6.0, 3.0) * scale, head + Vector2(6.0, 3.0) * scale]), INK)
		c.draw_circle(head, 7.5 * scale, INK)
		c.draw_circle(head, 6.0 * scale, FOUND)
		_star(c, head, 3.6 * scale, Color(1.0, 0.98, 0.86))
	else:
		c.draw_circle(p, 9.0 * scale, Color(0.08, 0.07, 0.09, 0.78))
		c.draw_arc(p, 9.0 * scale, 0.0, TAU, 28, Color(0.95, 0.9, 0.8, 0.7), 1.3, true)
		var size := int(14 * scale)
		var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c.draw_string(font, p + Vector2(-w * 0.5, size * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.95, 0.92, 0.86))


## 光门：发光的紫色圆环。
static func draw_gate(c: CanvasItem, p: Vector2, scale := 1.0) -> void:
	for k in 3:
		c.draw_circle(p, (13.0 - k * 3.0) * scale, Color(GATE, 0.10 + k * 0.06))
	c.draw_arc(p, 7.5 * scale, 0.0, TAU, 32, GATE, 3.0 * scale, true)
	c.draw_arc(p, 7.5 * scale, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 1.0, true)


## 玩家：视野扇形 + 呼吸的光圈 + 箭头。heading 是画面里朝前的角度（弧度，0 = 朝上）。
static func draw_player(c: CanvasItem, p: Vector2, heading: float, t: float, cone := 46.0) -> void:
	var fan := PackedVector2Array([p])
	for k in 13:
		var a := heading - 0.55 + 1.1 * k / 12.0
		fan.append(p + Vector2(sin(a), -cos(a)) * cone)
	c.draw_colored_polygon(fan, Color(1.0, 0.93, 0.72, 0.28))
	c.draw_line(p, fan[1], Color(1.0, 0.95, 0.8, 0.6), 1.2, true)
	c.draw_line(p, fan[fan.size() - 1], Color(1.0, 0.95, 0.8, 0.6), 1.2, true)
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	c.draw_circle(p, 13.0 + pulse * 4.0, Color(1.0, 0.85, 0.5, 0.18 * (1.0 - pulse) + 0.08))
	var arrow := PackedVector2Array([Vector2(0, -12), Vector2(8.5, 8), Vector2(0, 3.5), Vector2(-8.5, 8)])
	var pts := PackedVector2Array()
	for a in arrow:
		pts.append(p + a.rotated(heading))
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(1.5, 2.0))
	c.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	c.draw_colored_polygon(pts, Color(1.0, 0.97, 0.9))
	pts.append(pts[0])
	c.draw_polyline(pts, INK, 1.8, true)


## 地图的边框：外面一圈深色粗线、里面一圈纸色细线，四角各一个小菱形。
static func draw_frame(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r.grow(5.0), Color(0.07, 0.055, 0.045), false, 5.0)
	c.draw_rect(r.grow(1.0), Color(PAPER, 0.85), false, 1.5)
	c.draw_rect(r.grow(9.0), Color(PAPER, 0.35), false, 1.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var d := 7.0
		var q := PackedVector2Array([corner + Vector2(0, -d), corner + Vector2(d, 0), corner + Vector2(0, d), corner + Vector2(-d, 0)])
		c.draw_colored_polygon(q, Color(0.07, 0.055, 0.045))
		var inner := PackedVector2Array([corner + Vector2(0, -d + 2.5), corner + Vector2(d - 2.5, 0), corner + Vector2(0, d - 2.5), corner + Vector2(-d + 2.5, 0)])
		c.draw_colored_polygon(inner, PAPER)


## 八角指北针：rot 是地图转了多少（北朝上时为 0）。
static func draw_compass(c: CanvasItem, center: Vector2, r: float, font: Font, rot := 0.0) -> void:
	c.draw_circle(center, r + 6.0, Color(0.07, 0.055, 0.045, 0.72))
	c.draw_arc(center, r + 6.0, 0.0, TAU, 48, Color(PAPER, 0.6), 1.2, true)
	for k in 8:
		var a := rot + k * TAU / 8.0
		var long := k % 2 == 0
		var reach := r if long else r * 0.62
		var w := r * (0.2 if long else 0.14)
		var tip := center + Vector2(sin(a), -cos(a)) * reach
		var side := Vector2(cos(a), sin(a)) * w
		# 每根针一半亮一半暗，像立体的
		c.draw_colored_polygon(PackedVector2Array([center, tip, center + side]), PAPER if long else Color(PAPER, 0.75))
		c.draw_colored_polygon(PackedVector2Array([center, tip, center - side]), Color(0.55, 0.42, 0.28) if long else Color(0.45, 0.35, 0.25))
	var north := center + Vector2(sin(rot), -cos(rot)) * r
	c.draw_colored_polygon(PackedVector2Array([center, north, center + Vector2(cos(rot), sin(rot)) * r * 0.2]), Color(0.86, 0.36, 0.24))
	c.draw_circle(center, r * 0.12, INK)
	var label_pos := center + Vector2(sin(rot), -cos(rot)) * (r + 15.0)
	label(c, font, label_pos, "N", 15, LABEL)


## 分段比例尺：0 — 25 — 50 m，黑白相间。px_per_m 是一米多少像素。
static func draw_scale_bar(c: CanvasItem, left: Vector2, px_per_m: float, font: Font, meters := 50.0) -> void:
	var seg := meters / 4.0 * px_per_m
	c.draw_rect(Rect2(left + Vector2(-8, -19), Vector2(seg * 4.0 + 34.0, 31.0)), Color(0.07, 0.055, 0.045, 0.62))
	for k in 4:
		c.draw_rect(Rect2(left + Vector2(seg * k, 0.0), Vector2(seg, 5.0)), PAPER if k % 2 == 0 else INK)
	c.draw_rect(Rect2(left, Vector2(seg * 4.0, 5.0)), PAPER, false, 1.0)
	for k in [0, 2, 4]:
		var text := "%d" % int(meters / 4.0 * k) + (" m" if k == 4 else "")
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		c.draw_string(font, left + Vector2(seg * k - w * 0.5, -5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PAPER)


## 描边文字，center 是文字中心。
static func label(c: CanvasItem, font: Font, center: Vector2, text: String, size: int, color := LABEL) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := center - Vector2(w * 0.5, -size * 0.35)
	c.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0.06, 0.045, 0.035, 0.85))
	c.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func _star(c: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := k * TAU / 10.0
		pts.append(center + Vector2(sin(a), -cos(a)) * (r if k % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, color)
