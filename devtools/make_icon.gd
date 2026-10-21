extends SceneTree
## 生成游戏图标：暮色天空、落日、对岸林线、湖面倒影、A 字形木屋剪影与暖色窗光。
##   Godot_console.exe --headless --path . -s res://devtools/make_icon.gd
## 输出 res://icon.png（256，窗口与工程图标）和 res://installer/icon.ico（256/64/48/32/16，可执行文件与安装包）。

const S := 256


func _init() -> void:
	var img := _draw()
	img.save_png("res://icon.png")
	var sizes := [256, 64, 48, 32, 16]
	var pngs: Array[PackedByteArray] = []
	for s in sizes:
		var copy := img.duplicate() as Image
		if s != S:
			copy.resize(s, s, Image.INTERPOLATE_LANCZOS)
		pngs.append(copy.save_png_to_buffer())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://installer"))
	_write_ico("res://installer/icon.ico", sizes, pngs)
	print("icon.png / installer/icon.ico written")
	quit()


func _draw() -> Image:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var top := Color("2b2350")
	var mid := Color("b8587a")
	var low := Color("f3a65a")
	var horizon := 150
	var r := 46.0   # 圆角半径
	for y in S:
		for x in S:
			var c: Color
			if y < horizon:
				var t := float(y) / horizon
				c = top.lerp(mid, smoothstep(0.0, 0.7, t)).lerp(low, smoothstep(0.55, 1.0, t))
			else:
				# 湖面：倒映天空，越近越暗
				var t2 := float(y - horizon) / (S - horizon)
				var refl := low.lerp(mid, t2 * 1.4).lerp(Color("1d1a33"), clampf(t2 * 1.2, 0.0, 1.0))
				c = refl.darkened(0.15)
			img.set_pixel(x, y, c)
	# 落日与水面上的光带
	_disc(img, Vector2(128, 132), 34.0, Color("ffd38a"), 0.95)
	for y in range(horizon + 4, S - 20, 7):
		var w := 46.0 - (y - horizon) * 0.32
		_rect(img, 128 - w * 0.5, y, w, 2.5, Color(1.0, 0.82, 0.5, 0.55))
	# 对岸林线
	for i in 26:
		var x := i * 10.0 - 4.0
		var h := 14.0 + fmod(i * 37.0, 17.0)
		_tri(img, Vector2(x, horizon - h), Vector2(x - 8, horizon + 1), Vector2(x + 8, horizon + 1), Color("231b3a"))
	_rect(img, 0, horizon - 2, S, 4, Color("231b3a"))
	# A 字形木屋（右前方）与窗光
	var base := Vector2(176, 214)
	_tri(img, Vector2(base.x, base.y - 92), Vector2(base.x - 54, base.y), Vector2(base.x + 54, base.y), Color("1a1426"))
	_tri(img, Vector2(base.x, base.y - 58), Vector2(base.x - 25, base.y - 6), Vector2(base.x + 25, base.y - 6), Color("ffb05a"))
	_rect(img, base.x - 2, base.y - 50, 4, 44, Color("1a1426"))
	_rect(img, base.x - 22, base.y - 30, 44, 3, Color("1a1426"))
	_rect(img, base.x - 66, base.y, 132, 6, Color("1a1426"))
	# 圆角
	for y in S:
		for x in S:
			var dx := maxf(maxf(r - x, x - (S - 1 - r)), 0.0)
			var dy := maxf(maxf(r - y, y - (S - 1 - r)), 0.0)
			var d := Vector2(dx, dy).length()
			if d > r - 1.0:
				var c := img.get_pixel(x, y)
				c.a *= clampf(r - d, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return img


func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= S or y >= S:
		return
	var under := img.get_pixel(x, y)
	img.set_pixel(x, y, under.lerp(Color(c.r, c.g, c.b, under.a), clampf(a * c.a, 0.0, 1.0)))


func _disc(img: Image, center: Vector2, radius: float, c: Color, a: float) -> void:
	for y in range(int(center.y - radius - 2), int(center.y + radius + 2)):
		for x in range(int(center.x - radius - 2), int(center.x + radius + 2)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			_blend(img, x, y, c, a * clampf(radius - d + 0.5, 0.0, 1.0))


func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	for yy in range(int(y), int(ceil(y + h))):
		for xx in range(int(x), int(ceil(x + w))):
			_blend(img, xx, yy, c, 1.0)


func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var mn := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
	var mx := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
	for y in range(int(mn.y), int(ceil(mx.y)) + 1):
		for x in range(int(mn.x), int(ceil(mx.x)) + 1):
			# 2×2 超采样抗锯齿
			var cover := 0.0
			for sy in 2:
				for sx in 2:
					var p := Vector2(x + 0.25 + sx * 0.5, y + 0.25 + sy * 0.5)
					if Geometry2D.point_is_inside_triangle(p, a, b, c):
						cover += 0.25
			if cover > 0.0:
				_blend(img, x, y, col, cover)


## ICO 文件：ICONDIR + 每个尺寸一个 ICONDIRENTRY，图像数据直接用 PNG（Windows Vista 起支持）。
func _write_ico(path: String, sizes: Array, pngs: Array[PackedByteArray]) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_16(0)
	f.store_16(1)
	f.store_16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var s: int = sizes[i]
		f.store_8(0 if s >= 256 else s)
		f.store_8(0 if s >= 256 else s)
		f.store_8(0)
		f.store_8(0)
		f.store_16(1)
		f.store_16(32)
		f.store_32(pngs[i].size())
		f.store_32(offset)
		offset += pngs[i].size()
	for p in pngs:
		f.store_buffer(p)
	f.close()
