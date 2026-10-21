@tool
class_name PoolHouse
extends Node3D
## 泳池馆 + 地下水族馆：与室外在同一世界坐标系（world_layout.json → poolhouse）。
## 局部坐标：首层地坪 y = 0（与周围平台齐平），+X 东，-Z 北（朝湖，整面玻璃）；平面 24 × 16 m。
##   首层：西侧门厅（正门、下行楼梯），东侧泳池厅（13 × 6 m 泳池，浅端 1.1 m、深端 3.2 m，北面玻璃墙外是观湖平台）。
##   地下（地坪 y = -7）：水族馆——北侧整面落地玻璃后是能潜进去的海洋大缸（ReefTank.gd），南侧珊瑚缸、东侧水母缸，
##   头顶是泳池深端的玻璃池底（能看见泳池里的人），
##   泳池深端池底有一个洞口连着一根玻璃水管，可以从泳池一路潜下去，从水族馆的下潜池浮出、走坡道上岸；
##   下潜池北壁底部还有一条水下通道（CHANNEL）通进海洋大缸，可以在缸里和鱼一起游。
##   不会游泳也能走：门厅的折返楼梯直通水族馆。
## 地形在建筑下方有基坑（terrain.pits），被首层地坪与地下室墙体完全遮住。

const GENERATED := "Generated"
const HX := 12.0
const HZ := 8.0
const WALL_H := 4.2
const PLINTH := 2.0
const WATER_Y := -0.12
const DEEP := -3.2
const SHALLOW := -1.1
const POOL := Rect2(-3.0, -3.0, 13.0, 6.0)          ## x, z, 宽, 深（局部 XZ）
const HOLE := Rect2(-2.5, -0.9, 1.8, 1.8)
const TUBE_CENTER := Vector2(-1.6, 0.0)
const TUBE_R := 0.88
const PANEL := Rect2(0.4, -2.6, 2.4, 5.2)
const WELL := Rect2(-11.85, 2.2, 6.25, 5.6)          ## 楼梯井
const FLOOR_B := -7.0
const CEIL_B := -3.9
const BASIN := Rect2(-3.4, -1.8, 7.0, 3.6)
const BASIN_FLOOR := -9.8   ## 比水管下沿低 2.2 m，人从管口下方游出
const BASIN_RAMP_X := -0.6  ## 上岸坡道起点（在水管东侧）
const BASIN_WATER := -7.15
## 海洋大缸（北侧整段）：缸底比水族馆地面低 2.8 m，水一直满到顶板；z = REEF.end.y 处是落地玻璃
const REEF := Rect2(-12.0, -8.0, 24.0, 4.9)   ## x, z, 宽, 深：z -8 .. -3.1
const REEF_SAND := -9.8
const REEF_TOP := -4.1
## 下潜池 → 海洋大缸的水下通道（从玻璃墙下方通到下潜池北壁、对着池底平坦的西半边），顶是大厅地板底面
const CHANNEL := Rect2(-2.8, -3.1, 2.0, 1.3)  ## x -2.8 .. -0.8（避开东侧上岸坡道），z -3.1 .. -1.8
const CHANNEL_TOP := -7.3
const REEF_LIFE := ["clownfish", "blue_tang", "yellow_tang", "silver_fish", "silver_fish", "turtle", "manta_ray", "reef_shark"]
const TANKS := [
	{"id": "south", "rect": Rect2(-4.0, 5.4, 15.6, 2.3), "glass": "z+", "life": ["clownfish", "blue_tang", "yellow_tang", "silver_fish"]},
	{"id": "jelly", "rect": Rect2(9.6, -2.6, 2.1, 5.8), "glass": "x-", "life": ["jellyfish"]},
]
const TANK_SAND := -6.7
const TANK_TOP := -4.1
const POOL_TILES := preload("res://shaders/pool_tiles.gdshader")
const POOL_WATER := preload("res://shaders/pool_water.gdshader")
const SAND := preload("res://shaders/caustic_sand.gdshader")
const DOOR_SCENE := preload("res://scenes/props/InteractableDoor.tscn")
const FURNITURE := "res://assets/imported/kenney/furniture/"

var tank_bounds: Array[AABB] = []   ## 各鱼缸可游动范围（世界坐标），测试与鱼群使用
var _m := {}
var _body: StaticBody3D = null


func _enter_tree() -> void:
	var cfg := WorldLayout.section("poolhouse")
	var c := WorldLayout.v2(cfg["center"])
	position = Vector3(c.x, float(cfg["floor_height"]), c.y)
	rotation = Vector3(0.0, deg_to_rad(float(cfg.get("yaw_deg", 0.0))), 0.0)


func _ready() -> void:
	add_to_group("poolhouse")
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var g := Node3D.new()
	g.name = GENERATED
	add_child(g)
	_materials()
	_body = StaticBody3D.new()
	_body.name = "Structure"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	g.add_child(_body)
	_build_ground_floor(g)
	_build_walls_and_roof(g)
	_build_pool(g)
	_build_tube(g)
	_build_stairs(g)
	_build_aquarium(g)
	_build_lights(g)
	_build_props(g)
	if Engine.is_editor_hint():
		return
	_build_door(g)
	_build_water_volumes(g)
	g.add_child(ZoneArea.create_box(&"poolhouse", Vector3(23.6, 4.2, 15.6), Vector3(0.0, 2.1, 0.0), true))
	g.add_child(ZoneArea.create_box(&"aquarium", Vector3(23.6, 3.3, 15.6), Vector3(0.0, -5.4, 0.0), true))
	# 整栋楼（含屋顶和地下水族馆）挡住落叶：玻璃墙外的叶子照常飘，馆内和地下都不会有
	var leaf_top := WALL_H + 0.6
	var leaf_bottom := BASIN_FLOOR - 0.5
	g.add_child(Precipitation.leaf_blocker(Vector3(HX * 2.0 + 1.2, leaf_top - leaf_bottom, HZ * 2.0 + 1.2), Transform3D(Basis(), Vector3(0.0, (leaf_top + leaf_bottom) * 0.5, 0.0))))
	_populate_tanks(g)


func _materials() -> void:
	var tiles := ShaderMaterial.new()
	tiles.shader = POOL_TILES
	tiles.set_shader_parameter("water_level", position.y + WATER_Y)
	var basin_tiles := ShaderMaterial.new()
	basin_tiles.shader = POOL_TILES
	basin_tiles.set_shader_parameter("water_level", position.y + BASIN_WATER)
	var water := ShaderMaterial.new()
	water.shader = POOL_WATER
	water.set_shader_parameter("ripple_a", _ripple(301, 0.03))
	water.set_shader_parameter("ripple_b", _ripple(302, 0.05))
	var sand := ShaderMaterial.new()
	sand.shader = SAND
	sand.set_shader_parameter("albedo_tex", ArtMaterials.texture("damp_beach_sand", "diff"))
	sand.set_shader_parameter("normal_tex", ArtMaterials.texture("damp_beach_sand", "nor_gl"))
	var tank_water := StandardMaterial3D.new()
	tank_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tank_water.cull_mode = BaseMaterial3D.CULL_FRONT
	tank_water.albedo_color = Color(0.10, 0.42, 0.58, 0.42)
	tank_water.emission_enabled = true
	tank_water.emission = Color(0.02, 0.10, 0.14)
	var tube_water := tank_water.duplicate() as StandardMaterial3D
	tube_water.albedo_color = Color(0.25, 0.65, 0.78, 0.22)
	_m = {
		"tiles": tiles, "basin_tiles": basin_tiles, "water": water, "sand": sand,
		"tank_water": tank_water, "tube_water": tube_water,
		"floor": ArtMaterials.pbr("floor_tiles_02", Color(1.0, 0.97, 0.92), "world"),
		"coping": ArtMaterials.pbr("floor_tiles_02", Color(1.08, 1.06, 1.02), "world", -0.2),
		"stone": ArtMaterials.pbr("rustic_stone_wall", Color.WHITE, "world"),
		"deck": ArtMaterials.snowable(ArtMaterials.pbr("weathered_planks", Color(1.0, 0.9, 0.8), "world")),
		"siding": ArtMaterials.pbr("brown_planks_05", Color(0.62, 0.40, 0.25), "world"),
		"lining": ArtMaterials.pbr("brown_planks_05", Color(1.0, 0.74, 0.5), "world"),
		"timber": ArtMaterials.pbr("stained_pine", Color(0.55, 0.38, 0.28), "world"),
		"roof": ArtMaterials.snowable(ArtMaterials.pbr("roof_slates_02", Color(0.42, 0.42, 0.46), "world")),
		"concrete": ArtMaterials.pbr("concrete_floor_01", Color(0.42, 0.47, 0.52), "world"),
		"aq_floor": _aquarium_floor(),
		"aq_wall": ArtMaterials.pbr("concrete_floor_01", Color(0.22, 0.30, 0.40), "world", -0.1),
		"aq_ceiling": ArtMaterials.pbr("concrete_floor_01", Color(0.20, 0.26, 0.34), "world"),
		"strip": ArtMaterials.glow(Color(0.55, 0.85, 1.0), 2.4),
		"frame": ArtMaterials.flat(Color(0.07, 0.07, 0.08), 0.4, false, 0.6),
		"glass": ArtMaterials.glass(),
		"clear": ArtMaterials.clear_glass(),
		"lamp": ArtMaterials.glow(Color(1.0, 0.82, 0.6), 2.0),
		"blue_lamp": ArtMaterials.glow(Color(0.4, 0.85, 1.0), 3.0),
	}


## 水族馆大厅地面：深色水磨石，靠近大缸玻璃的地方映出水纹光。
func _aquarium_floor() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/aquarium_floor.gdshader")
	m.set_shader_parameter("glass_z", position.z + REEF.end.y)
	m.set_shader_parameter("glass_side", -1.0)
	return m


# ---------------------------------------------------------------- 首层

func _build_ground_floor(g: Node3D) -> void:
	# 室外石砌台基（盖住地下室基坑的边缘），与周围平台齐平；可见面略抬 2 cm 避免与地形打架
	for r in _ring(Rect2(-HX - PLINTH, -HZ - PLINTH, (HX + PLINTH) * 2.0, (HZ + PLINTH) * 2.0), Rect2(-HX, -HZ, HX * 2.0, HZ * 2.0)):
		_slab(g, r, -0.3, 0.0, _m.stone, true, 0.02)
	# 室内地坪：留出泳池与楼梯井
	for r in _subtract(Rect2(-HX, -HZ, HX * 2.0, HZ * 2.0), [POOL.grow(0.3), WELL]):
		_slab(g, r, -0.3, 0.0, _m.floor, true, 0.01)
	# 北侧观湖平台（木板）
	_slab(g, Rect2(-HX, -HZ - 3.5, HX * 2.0, 1.5), -0.2, 0.0, _m.deck, true, 0.04)
	# 泳池池岸压顶
	for r in _ring(POOL.grow(0.45), POOL):
		_slab(g, r, -0.05, 0.03, _m.coping, false)


func _build_walls_and_roof(g: Node3D) -> void:
	var t := 0.3
	# 西墙（正门）
	_box(g, Vector3(t, WALL_H, HZ - 0.6), Vector3(-HX, WALL_H * 0.5, -(HZ + 0.6) * 0.5), _m.siding)
	_box(g, Vector3(t, WALL_H, HZ - 0.6), Vector3(-HX, WALL_H * 0.5, (HZ + 0.6) * 0.5), _m.siding)
	_box(g, Vector3(t, WALL_H - 2.2, 1.2), Vector3(-HX, 2.2 + (WALL_H - 2.2) * 0.5, 0.0), _m.siding)
	_box(g, Vector3(0.36, 0.12, 1.44), Vector3(-HX, 2.26, 0.0), _m.timber, false)
	for z: float in [-0.66, 0.66]:
		_box(g, Vector3(0.36, 2.2, 0.12), Vector3(-HX, 1.1, z), _m.timber, false)
	# 南墙：实墙 + 高窗
	_box(g, Vector3(HX * 2.0, 3.0, t), Vector3(0.0, 1.5, HZ), _m.siding)
	_box(g, Vector3(HX * 2.0, 1.0, 0.05), Vector3(0.0, 3.5, HZ), _m.glass)
	_box(g, Vector3(HX * 2.0, 0.2, t), Vector3(0.0, 4.1, HZ), _m.siding)
	# 北墙：整面玻璃，x 6..8 处留通往观湖平台的门洞
	_box(g, Vector3(18.0, WALL_H, 0.06), Vector3(-3.0, WALL_H * 0.5, -HZ), _m.glass)
	_box(g, Vector3(4.0, WALL_H, 0.06), Vector3(10.0, WALL_H * 0.5, -HZ), _m.glass)
	_box(g, Vector3(2.0, WALL_H - 2.4, 0.06), Vector3(7.0, 2.4 + (WALL_H - 2.4) * 0.5, -HZ), _m.glass)
	# 东墙：玻璃
	_box(g, Vector3(0.06, WALL_H, HZ * 2.0), Vector3(HX, WALL_H * 0.5, 0.0), _m.glass)
	# 玻璃窗框（竖梃）
	var x := -HX
	while x <= HX + 0.01:
		_box(g, Vector3(0.1, WALL_H, 0.14), Vector3(x, WALL_H * 0.5, -HZ), _m.frame, false)
		x += 2.0
	var z := -HZ
	while z <= HZ + 0.01:
		_box(g, Vector3(0.14, WALL_H, 0.1), Vector3(HX, WALL_H * 0.5, z), _m.frame, false)
		z += 2.0
	_box(g, Vector3(HX * 2.0, 0.12, 0.16), Vector3(0.0, 2.4, -HZ), _m.frame, false)
	_box(g, Vector3(0.16, 0.12, HZ * 2.0), Vector3(HX, 2.4, 0.0), _m.frame, false)
	# 平屋顶：石板面层 + 木封檐 + 室内木吊顶
	_box(g, Vector3(HX * 2.0 + 1.2, 0.3, HZ * 2.0 + 1.2), Vector3(0.0, WALL_H + 0.15, 0.0), _m.roof)
	_box(g, Vector3(HX * 2.0 + 1.3, 0.36, 0.08), Vector3(0.0, WALL_H + 0.12, -HZ - 0.64), _m.timber, false)
	_box(g, Vector3(HX * 2.0 + 1.3, 0.36, 0.08), Vector3(0.0, WALL_H + 0.12, HZ + 0.64), _m.timber, false)
	_box(g, Vector3(0.08, 0.36, HZ * 2.0 + 1.3), Vector3(-HX - 0.64, WALL_H + 0.12, 0.0), _m.timber, false)
	_box(g, Vector3(0.08, 0.36, HZ * 2.0 + 1.3), Vector3(HX + 0.64, WALL_H + 0.12, 0.0), _m.timber, false)
	_box(g, Vector3(HX * 2.0, 0.04, HZ * 2.0), Vector3(0.0, WALL_H - 0.02, 0.0), _m.lining, false)
	for bx: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_box(g, Vector3(0.2, 0.3, HZ * 2.0), Vector3(bx, WALL_H - 0.19, 0.0), _m.timber, false)
	# 楼梯井口栏杆（首层）：玻璃栏板，西侧靠墙、南侧靠墙，flight 1 入口（x = -5.6, z 5..7.8）开口
	_box(g, Vector3(WELL.size.x, 1.0, 0.04), Vector3(WELL.get_center().x, 0.5, WELL.position.y), _m.clear)
	_box(g, Vector3(0.04, 1.0, 2.6), Vector3(WELL.end.x, 0.5, WELL.position.y + 1.3), _m.clear)
	_box(g, Vector3(WELL.size.x, 0.05, 0.08), Vector3(WELL.get_center().x, 1.02, WELL.position.y), _m.timber, false)
	_box(g, Vector3(0.08, 0.05, 2.6), Vector3(WELL.end.x, 1.02, WELL.position.y + 1.3), _m.timber, false)


# ---------------------------------------------------------------- 泳池与水管

func _build_pool(g: Node3D) -> void:
	var t := 0.3
	var x0 := POOL.position.x
	var x1 := POOL.end.x
	var z0 := POOL.position.y
	var z1 := POOL.end.y
	var bottom := DEEP - 0.3
	# 池壁
	_box(g, Vector3(POOL.size.x + 2.0 * t, -bottom, t), Vector3(POOL.get_center().x, bottom * 0.5, z0 - t * 0.5), _m.tiles)
	_box(g, Vector3(POOL.size.x + 2.0 * t, -bottom, t), Vector3(POOL.get_center().x, bottom * 0.5, z1 + t * 0.5), _m.tiles)
	_box(g, Vector3(t, -bottom, POOL.size.y), Vector3(x0 - t * 0.5, bottom * 0.5, POOL.get_center().y), _m.tiles)
	_box(g, Vector3(t, -SHALLOW + 0.3, POOL.size.y), Vector3(x1 + t * 0.5, (SHALLOW - 0.3) * 0.5, POOL.get_center().y), _m.tiles)
	# 深水区池底：留出下潜洞口与玻璃观景窗
	for r in _subtract(Rect2(x0, z0, 6.0, POOL.size.y), [HOLE, PANEL]):
		_slab(g, r, DEEP - 0.3, DEEP, _m.tiles)
	_slab(g, PANEL, DEEP - 0.05, DEEP, _m.clear)
	# 斜坡池底（x 3..8 从 -3.2 升到 -1.1）与浅水区
	_ramp(g, Vector2(3.0, DEEP), Vector2(8.0, SHALLOW), POOL.get_center().y, POOL.size.y, 0.3, _m.tiles)
	_slab(g, Rect2(8.0, z0, 2.0, POOL.size.y), SHALLOW - 0.3, SHALLOW, _m.tiles)
	# 浅水区东北角的入水台阶（坡面碰撞 + 三级可见台阶）
	_ramp(g, Vector2(8.6, SHALLOW), Vector2(10.0, 0.0), 2.3, 1.4, 0.2, null)
	for i in 3:
		var top := SHALLOW + (i + 1) * (-SHALLOW / 3.0)
		_box(g, Vector3(0.47, top - SHALLOW, 1.4), Vector3(8.6 + (i + 0.5) * 0.467, (top + SHALLOW) * 0.5, 2.3), _m.coping, false)
	# 洞口下方的竖井壁（穿过池底与水族馆顶板之间）
	_shaft_walls(g, HOLE, CEIL_B, DEEP - 0.3)
	# 水面
	var plane := PlaneMesh.new()
	plane.size = POOL.size
	plane.subdivide_width = 26
	plane.subdivide_depth = 12
	plane.material = _m.water
	var mi := MeshInstance3D.new()
	mi.name = "PoolWater"
	mi.mesh = plane
	mi.position = Vector3(POOL.get_center().x, WATER_Y, POOL.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)


func _build_tube(g: Node3D) -> void:
	var top := DEEP
	var bottom := BASIN_WATER - 0.45
	var h := top - bottom
	var center := Vector3(TUBE_CENTER.x, (top + bottom) * 0.5, TUBE_CENTER.y)
	_cylinder(g, TUBE_R + 0.03, h, center, _m.clear)
	_cylinder(g, TUBE_R - 0.02, h, center, _m.tube_water)
	# 顶部与底部的金属箍
	_cylinder(g, TUBE_R + 0.08, 0.12, Vector3(center.x, CEIL_B - 0.06, center.z), _m.frame)
	_cylinder(g, TUBE_R + 0.08, 0.12, Vector3(center.x, FLOOR_B + 0.5, center.z), _m.frame)
	# 管壁碰撞：一圈竖直薄板
	var n := 16
	for i in n:
		var a := TAU * float(i) / n
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.08, h, TAU * (TUBE_R + 0.06) / n + 0.04)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.UP, -a), center + Vector3(cos(a), 0.0, sin(a)) * (TUBE_R + 0.06))
		_body.add_child(cs)


# ---------------------------------------------------------------- 楼梯

func _build_stairs(g: Node3D) -> void:
	var x_top := WELL.end.x          # -5.6
	var x_land := -10.6
	var lane1 := Rect2(x_land, 5.0, x_top - x_land, WELL.end.y - 5.0)
	var lane2 := Rect2(x_land, WELL.position.y, x_top - x_land, 4.8 - WELL.position.y)
	var mid := -3.5
	_ramp(g, Vector2(x_land, mid), Vector2(x_top, 0.0), lane1.get_center().y, lane1.size.y, 0.3, null)
	_ramp(g, Vector2(x_land, mid), Vector2(x_top, FLOOR_B), lane2.get_center().y, lane2.size.y, 0.3, null)
	_steps(g, Vector2(x_top, 0.0), Vector2(x_land, mid), lane1)
	_steps(g, Vector2(x_land, mid), Vector2(x_top, FLOOR_B), lane2)
	_slab(g, Rect2(WELL.position.x, WELL.position.y, x_land - WELL.position.x, WELL.size.y), mid - 0.3, mid, _m.floor)
	# 两跑之间的隔墙（高出首层 0.9 m 兼作栏杆）、楼梯井围墙
	_box(g, Vector3(x_top - x_land, -FLOOR_B + 0.9, 0.2), Vector3((x_top + x_land) * 0.5, (FLOOR_B + 0.9) * 0.5, 4.9), _m.concrete)
	_box(g, Vector3(0.2, -0.3 - FLOOR_B, lane1.size.y), Vector3(x_top + 0.1, (FLOOR_B - 0.3) * 0.5, lane1.get_center().y), _m.concrete)
	_box(g, Vector3(0.2, -0.3 - CEIL_B, lane2.size.y), Vector3(x_top + 0.1, (CEIL_B - 0.3) * 0.5, lane2.get_center().y), _m.concrete)
	_box(g, Vector3(WELL.size.x, -0.3 - CEIL_B, 0.2), Vector3(WELL.get_center().x, (CEIL_B - 0.3) * 0.5, WELL.position.y - 0.1), _m.concrete)
	_box(g, Vector3(WELL.size.x, CEIL_B - FLOOR_B, 0.04), Vector3(WELL.get_center().x, (CEIL_B + FLOOR_B) * 0.5, WELL.position.y), _m.clear)
	_box(g, Vector3(WELL.size.x, -0.3 - FLOOR_B, 0.2), Vector3(WELL.get_center().x, (FLOOR_B - 0.3) * 0.5, WELL.end.y + 0.1), _m.concrete)


func _steps(g: Node3D, from: Vector2, to: Vector2, lane: Rect2) -> void:
	var count := 20
	for i in count:
		var t0 := float(i) / count
		var t1 := float(i + 1) / count
		var xa := lerpf(from.x, to.x, t0)
		var xb := lerpf(from.x, to.x, t1)
		var y_top := maxf(lerpf(from.y, to.y, t0), lerpf(from.y, to.y, t1))
		_box(g, Vector3(absf(xb - xa), 0.4, lane.size.y), Vector3((xa + xb) * 0.5, y_top - 0.2, lane.get_center().y), _m.floor, false)


# ---------------------------------------------------------------- 水族馆

func _build_aquarium(g: Node3D) -> void:
	# 地坪（留出下潜池）、顶板（留出水管洞口、玻璃观景窗、楼梯井）
	for r in _subtract(Rect2(-HX, -HZ, HX * 2.0, HZ * 2.0), [BASIN, REEF]):
		_slab(g, r, FLOOR_B - 0.3, FLOOR_B, _m.aq_floor, true, 0.0)
	for r in _subtract(Rect2(-HX, -HZ, HX * 2.0, HZ * 2.0), [HOLE, PANEL, WELL]):
		_slab(g, r, CEIL_B, CEIL_B + 0.3, _m.aq_ceiling)
	_shaft_walls(g, PANEL, CEIL_B, DEEP - 0.05)
	# 外墙（地下）
	var t := 0.3
	var h := -FLOOR_B + 0.3
	_box(g, Vector3(t, h, HZ * 2.0 + 2.0 * t), Vector3(-HX - t * 0.5, -h * 0.5, 0.0), _m.aq_wall)
	_box(g, Vector3(t, h, HZ * 2.0 + 2.0 * t), Vector3(HX + t * 0.5, -h * 0.5, 0.0), _m.aq_wall)
	_box(g, Vector3(HX * 2.0, h, t), Vector3(0.0, -h * 0.5, -HZ - t * 0.5), _m.aq_wall)
	_box(g, Vector3(HX * 2.0, h, t), Vector3(0.0, -h * 0.5, HZ + t * 0.5), _m.aq_wall)
	# 下潜池：四壁、池底、上岸坡道
	var bt := 0.3
	var bh := FLOOR_B - BASIN_FLOOR
	# 北壁在通道处开口（通道两侧各一段，通道上方一段过梁）
	var nz := BASIN.position.y - bt * 0.5
	var ny := (FLOOR_B + BASIN_FLOOR) * 0.5
	var left := CHANNEL.position.x - (BASIN.position.x - bt)
	var right := (BASIN.end.x + bt) - CHANNEL.end.x
	_box(g, Vector3(left, bh, bt), Vector3(BASIN.position.x - bt + left * 0.5, ny, nz), _m.basin_tiles)
	_box(g, Vector3(right, bh, bt), Vector3(CHANNEL.end.x + right * 0.5, ny, nz), _m.basin_tiles)
	_box(g, Vector3(CHANNEL.size.x, FLOOR_B - CHANNEL_TOP, bt), Vector3(CHANNEL.get_center().x, (FLOOR_B + CHANNEL_TOP) * 0.5, nz), _m.basin_tiles)
	_box(g, Vector3(BASIN.size.x + 2.0 * bt, bh, bt), Vector3(BASIN.get_center().x, (FLOOR_B + BASIN_FLOOR) * 0.5, BASIN.end.y + bt * 0.5), _m.basin_tiles)
	_box(g, Vector3(bt, bh, BASIN.size.y), Vector3(BASIN.position.x - bt * 0.5, (FLOOR_B + BASIN_FLOOR) * 0.5, BASIN.get_center().y), _m.basin_tiles)
	_box(g, Vector3(bt, bh, BASIN.size.y), Vector3(BASIN.end.x + bt * 0.5, (FLOOR_B + BASIN_FLOOR) * 0.5, BASIN.get_center().y), _m.basin_tiles)
	_slab(g, Rect2(BASIN.position.x, BASIN.position.y, BASIN_RAMP_X - BASIN.position.x, BASIN.size.y), BASIN_FLOOR - 0.3, BASIN_FLOOR, _m.basin_tiles)
	_ramp(g, Vector2(BASIN_RAMP_X, BASIN_FLOOR), Vector2(BASIN.end.x, FLOOR_B), BASIN.get_center().y, BASIN.size.y, 0.3, _m.basin_tiles)
	for r in _ring(BASIN.grow(0.35), BASIN):
		_slab(g, r, FLOOR_B - 0.02, FLOOR_B + 0.04, _m.coping, false)
	var plane := PlaneMesh.new()
	plane.size = BASIN.size
	plane.material = _m.water
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(BASIN.get_center().x, BASIN_WATER, BASIN.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)
	# 鱼缸：先建海洋大缸（tank_bounds[0]），再建南侧珊瑚缸与水母缸
	tank_bounds.clear()
	ReefTank.build(self, g)
	for tank in TANKS:
		_build_tank(g, tank)


func _build_tank(g: Node3D, tank: Dictionary) -> void:
	var r: Rect2 = tank["rect"]
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var water_h := TANK_TOP - TANK_SAND
	_slab(g, r, FLOOR_B, TANK_SAND, _m.sand)
	var water := BoxMesh.new()
	water.size = Vector3(r.size.x, water_h, r.size.y)
	water.material = _m.tank_water
	var wmi := MeshInstance3D.new()
	wmi.mesh = water
	wmi.position = Vector3(c.x, (TANK_SAND + TANK_TOP) * 0.5, c.z)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(wmi)
	_slab(g, r.grow(0.1), TANK_TOP, CEIL_B, _m.concrete)
	var side := str(tank["glass"])
	var gh := TANK_TOP - FLOOR_B
	match side:
		"z-":
			_box(g, Vector3(r.size.x, gh, 0.05), Vector3(c.x, (FLOOR_B + TANK_TOP) * 0.5, r.end.y), _m.clear)
			_box(g, Vector3(r.size.x + 0.1, 0.12, 0.14), Vector3(c.x, TANK_TOP - 0.06, r.end.y), _m.frame, false)
		"z+":
			_box(g, Vector3(r.size.x, gh, 0.05), Vector3(c.x, (FLOOR_B + TANK_TOP) * 0.5, r.position.y), _m.clear)
			_box(g, Vector3(r.size.x + 0.1, 0.12, 0.14), Vector3(c.x, TANK_TOP - 0.06, r.position.y), _m.frame, false)
		"x-":
			_box(g, Vector3(0.05, gh, r.size.y), Vector3(r.position.x, (FLOOR_B + TANK_TOP) * 0.5, c.z), _m.clear)
			_box(g, Vector3(0.14, 0.12, r.size.y + 0.1), Vector3(r.position.x, TANK_TOP - 0.06, c.z), _m.frame, false)
	# 缸底装饰：几块岩石与水草（Kenney，按水下配色）
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tank["id"])
	for i in int(r.size.x * r.size.y / 3.0):
		var px := rng.randf_range(r.position.x + 0.3, r.end.x - 0.3)
		var pz := rng.randf_range(r.position.y + 0.3, r.end.y - 0.3)
		var asset: String = ["rock_smallA", "rock_smallC", "rock_largeA", "plant_bush", "plant_bushSmall", "grass_large"][rng.randi() % 6]
		var node := ArtMaterials.kenney_prop("res://assets/imported/kenney/nature/%s.glb" % asset, Vector3(px, TANK_SAND, pz), rng.randf() * 360.0, rng.randf_range(1.2, 2.4))
		_underwater_restyle(node, asset, rng)
		g.add_child(node)
	var inner := AABB(Vector3(r.position.x + 0.25, TANK_SAND + 0.25, r.position.y + 0.25), Vector3(r.size.x - 0.5, water_h - 0.5, r.size.y - 0.5))
	tank_bounds.append(AABB(to_global(inner.position), inner.size))


## 缸里的岩石与水草换成水下专用材质：不积雪、不随风摆，水草与珊瑚颜色鲜艳一些。
func _underwater_restyle(node: Node, asset: String, rng: RandomNumberGenerator) -> void:
	var coral := [Color(0.92, 0.45, 0.48), Color(0.98, 0.66, 0.30), Color(0.55, 0.36, 0.78), Color(0.25, 0.62, 0.42)]
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if asset.begins_with("rock"):
			(mi as MeshInstance3D).material_override = ArtMaterials.pbr("rock_face_03", Color(0.66, 0.64, 0.6), "world", -0.1)
		else:
			(mi as MeshInstance3D).material_override = ArtMaterials.flat(coral[rng.randi() % coral.size()], 0.7)


# ---------------------------------------------------------------- 灯光、摆件、门、水体

func _build_lights(g: Node3D) -> void:
	for p in [Vector3(-8.5, 3.8, -4.0), Vector3(-8.5, 3.8, 4.0), Vector3(0.0, 3.8, -5.6), Vector3(6.0, 3.8, -5.6), Vector3(0.0, 3.8, 5.6), Vector3(6.0, 3.8, 5.6)]:
		_omni(g, p, Color(1.0, 0.8, 0.6), 0.8, 8.5)
		_box(g, Vector3(0.35, 0.06, 0.35), p + Vector3(0.0, 0.32, 0.0), _m.lamp, false)
	for p in [Vector3(-1.0, -1.6, -2.85), Vector3(5.0, -1.6, -2.85), Vector3(-1.0, -1.6, 2.85), Vector3(5.0, -1.6, 2.85)]:
		_omni(g, p, Color(0.45, 0.85, 1.0), 1.3, 5.5)
		_box(g, Vector3(0.3, 0.3, 0.04), p + Vector3(0.0, 0.0, signf(p.z) * 0.12), _m.blue_lamp, false)
	for tank in TANKS:
		var r: Rect2 = tank["rect"]
		var n := maxi(1, int(maxf(r.size.x, r.size.y) / 5.0))
		for i in n:
			var f := (float(i) + 0.5) / n
			var p := Vector3(lerpf(r.position.x, r.end.x, f), TANK_TOP - 0.3, r.get_center().y) if r.size.x > r.size.y else Vector3(r.get_center().x, TANK_TOP - 0.3, lerpf(r.position.y, r.end.y, f))
			var col := Color(0.75, 0.45, 1.0) if tank["id"] == "jelly" else Color(0.35, 0.8, 1.0)
			_omni(g, p, col, 1.8, 4.5)
	_omni(g, Vector3(2.0, -4.3, 0.0), Color(1.0, 0.85, 0.7), 0.5, 13.0)
	# 水族馆大厅顶上的两条暖白灯带（南侧鱼缸前；避开头顶的玻璃池底和水管洞口）
	for z: float in [4.3, 3.2]:
		_box(g, Vector3(14.0, 0.05, 0.14), Vector3(2.5, CEIL_B - 0.03, z), _m.lamp, false)
		for x: float in [-2.5, 4.5]:
			_omni(g, Vector3(x, CEIL_B - 0.25, z), Color(1.0, 0.86, 0.72), 0.6, 6.0)
	_omni(g, Vector3(-8.0, -1.5, 5.0), Color(1.0, 0.85, 0.7), 0.7, 7.0)
	_omni(g, Vector3(-1.6, -6.2, 0.0), Color(0.4, 0.85, 1.0), 1.0, 4.0)


func _build_props(g: Node3D) -> void:
	for x: float in [-1.0, 2.2, 5.4]:
		g.add_child(ArtMaterials.kenney_prop(FURNITURE + "loungeChairRelax.glb", Vector3(x, 0.0, -6.3), 180.0, 2.1))
	for p in [Vector3(-4.6, 0.0, -7.2), Vector3(11.0, 0.0, -7.2), Vector3(11.0, 0.0, 7.2), Vector3(-11.2, 0.0, -7.2)]:
		g.add_child(ArtMaterials.kenney_prop(FURNITURE + "pottedPlant.glb", p, 30.0, 2.3))
	g.add_child(ArtMaterials.kenney_prop(FURNITURE + "rugRectangle.glb", Vector3(-8.6, 0.006, -3.2), 90.0, 2.0))
	g.add_child(ArtMaterials.kenney_prop(FURNITURE + "bench.glb", Vector3(-8.6, 0.0, -6.8), 0.0, 2.2))
	for p in [Vector3(-6.5, FLOOR_B, -2.4), Vector3(6.5, FLOOR_B, -2.4)]:
		g.add_child(ArtMaterials.kenney_prop(FURNITURE + "bench.glb", p, 180.0, 2.2))
	for p in [Vector3(1.5, FLOOR_B, 3.7), Vector3(6.0, FLOOR_B, 3.7)]:
		g.add_child(ArtMaterials.kenney_prop(FURNITURE + "bench.glb", p, 0.0, 2.2))
	if Engine.is_editor_hint():
		return
	# 解说立牌（中英双语，文字见 data/world/signs.json）。yaw 让正面朝向读牌的人
	_sign(g, "poolhouse_name", "wall", 2.4, Vector3(-HX - 0.16, 3.1, 0.0), -90.0, 2.0)
	_sign(g, "poolhouse_entrance", "stand", 1.4, Vector3(-15.0, 0.0, 2.6), -90.0, 1.4)
	_sign(g, "pool_dive", "lectern", 1.0, Vector3(-1.6, 0.0, -3.8), 180.0)
	_sign(g, "stairs_aquarium", "stand", 1.0, Vector3(-3.6, 0.0, 7.45), 180.0)
	_sign(g, "tank_north", "lectern", 1.0, Vector3(-9.0, FLOOR_B, -2.6), 0.0)
	_sign(g, "reef_dive", "lectern", 0.9, Vector3(-4.3, FLOOR_B, -1.0), -90.0)
	_sign(g, "tank_south", "lectern", 0.9, Vector3(-2.6, FLOOR_B, 4.55), 180.0)
	_sign(g, "tank_jelly", "lectern", 0.9, Vector3(8.85, FLOOR_B, 2.2), -90.0)
	# 能坐的地方：泳池躺椅、大厅长椅、水族馆长椅（面朝鱼缸）
	var seat_list := [
		[&"pool_lounger_1", "躺椅", Vector3(-1.0, 0.42, -6.2), 0.0],
		[&"pool_lounger_2", "躺椅", Vector3(2.2, 0.42, -6.2), 0.0],
		[&"pool_lounger_3", "躺椅", Vector3(5.4, 0.42, -6.2), 0.0],
		[&"hall_bench", "长椅", Vector3(-8.6, 0.48, -6.8), 180.0],
		[&"aquarium_bench_1", "长椅", Vector3(-6.5, FLOOR_B + 0.48, -2.4), 0.0],
		[&"aquarium_bench_2", "长椅", Vector3(6.5, FLOOR_B + 0.48, -2.4), 0.0],
		[&"aquarium_bench_3", "长椅", Vector3(1.5, FLOOR_B + 0.48, 3.7), 180.0],
		[&"aquarium_bench_4", "长椅", Vector3(6.0, FLOOR_B + 0.48, 3.7), 180.0],
	]
	for item in seat_list:
		g.add_child(Seat.create(item[0], item[1], item[2], item[3], 0.45, 0.9))


func _build_door(g: Node3D) -> void:
	var door := DOOR_SCENE.instantiate() as InteractableDoor
	door.name = "FrontDoor"
	door.uid = &"poolhouse_front_door"
	door.display_name = "泳池馆正门"
	door.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-HX, 0.0, 0.6))
	g.add_child(door)


func _build_water_volumes(g: Node3D) -> void:
	var pool_h := WATER_Y - DEEP
	g.add_child(WaterVolume.create_box(&"pool", Vector3(POOL.get_center().x, (WATER_Y + DEEP) * 0.5, POOL.get_center().y), Vector3(POOL.size.x, pool_h, POOL.size.y)))
	var top := DEEP + 0.05
	var bottom := BASIN_WATER - 0.45
	g.add_child(WaterVolume.create_cylinder(&"tube", Vector3(TUBE_CENTER.x, (top + bottom) * 0.5, TUBE_CENTER.y), TUBE_R - 0.02, top - bottom))
	g.add_child(WaterVolume.create_box(&"dive_pool", Vector3(BASIN.get_center().x, (BASIN_WATER + BASIN_FLOOR) * 0.5, BASIN.get_center().y), Vector3(BASIN.size.x, BASIN_WATER - BASIN_FLOOR, BASIN.size.y)))
	# 海洋大缸（水满到顶，没有水面）与通道
	g.add_child(WaterVolume.create_box(&"reef", Vector3(REEF.get_center().x, (REEF_SAND + REEF_TOP) * 0.5, REEF.get_center().y), Vector3(REEF.size.x, REEF_TOP - REEF_SAND, REEF.size.y), false))
	g.add_child(WaterVolume.create_box(&"reef_channel", Vector3(CHANNEL.get_center().x, (REEF_SAND + CHANNEL_TOP) * 0.5, CHANNEL.get_center().y), Vector3(CHANNEL.size.x, CHANNEL_TOP - REEF_SAND, CHANNEL.size.y + 0.4), false))


func _populate_tanks(g: Node3D) -> void:
	var lists := [REEF_LIFE]
	var names := ["reef"]
	for tank in TANKS:
		lists.append(tank["life"])
		names.append(tank["id"])
	for i in lists.size():
		var school := FishSchool.new()
		school.name = "Life_%s" % names[i]
		school.bounds = tank_bounds[i]
		school.species_list = lists[i]
		school.seed_value = 4000 + i
		g.add_child(school)


# ---------------------------------------------------------------- 几何工具

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := true, basis := Basis(), visual_lift := 0.0) -> void:
	if mat != null:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.transform = Transform3D(basis, pos + Vector3(0.0, visual_lift, 0.0))
		parent.add_child(mi)
	if collide and _body != null and not Engine.is_editor_hint():
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(basis, pos)
		_body.add_child(cs)


func _slab(parent: Node3D, r: Rect2, y0: float, y1: float, mat: Material, collide := true, visual_lift := 0.0) -> void:
	if r.size.x <= 0.001 or r.size.y <= 0.001:
		return
	_box(parent, Vector3(r.size.x, y1 - y0, r.size.y), Vector3(r.get_center().x, (y0 + y1) * 0.5, r.get_center().y), mat, collide, Basis(), visual_lift)


## 斜坡板：沿 X 从 a (x, 顶面 y) 到 b，横跨 z_center ± width/2。
func _ramp(parent: Node3D, a: Vector2, b: Vector2, z_center: float, width: float, thickness: float, mat: Material, collide := true) -> void:
	var d := b - a
	var angle := atan2(d.y, d.x)
	var basis := Basis(Vector3.BACK, angle)
	var top_mid := Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, z_center)
	var normal := basis * Vector3.UP
	_box(parent, Vector3(d.length(), thickness, width), top_mid - normal * thickness * 0.5, mat, collide, basis)


func _shaft_walls(parent: Node3D, r: Rect2, y0: float, y1: float) -> void:
	var t := 0.15
	var h := y1 - y0
	var yc := (y0 + y1) * 0.5
	_box(parent, Vector3(r.size.x + 2.0 * t, h, t), Vector3(r.get_center().x, yc, r.position.y - t * 0.5), _m.concrete)
	_box(parent, Vector3(r.size.x + 2.0 * t, h, t), Vector3(r.get_center().x, yc, r.end.y + t * 0.5), _m.concrete)
	_box(parent, Vector3(t, h, r.size.y), Vector3(r.position.x - t * 0.5, yc, r.get_center().y), _m.concrete)
	_box(parent, Vector3(t, h, r.size.y), Vector3(r.end.x + t * 0.5, yc, r.get_center().y), _m.concrete)


func _cylinder(parent: Node3D, r: float, h: float, center: Vector3, mat: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 32
	cm.cap_top = false
	cm.cap_bottom = false
	cm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	parent.add_child(light)


func _sign(parent: Node3D, id: String, style: String, width: float, pos: Vector3, yaw_deg: float, scale := 1.0) -> void:
	var s := SignBoard.create(id, style, width, scale)
	s.position = pos
	s.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(s)


## 矩形减去若干矩形孔，返回覆盖剩余区域的矩形列表（按网格切分后沿 Z 合并）。
static func _subtract(r: Rect2, holes: Array) -> Array[Rect2]:
	var xs: Array[float] = [r.position.x, r.end.x]
	var zs: Array[float] = [r.position.y, r.end.y]
	for h: Rect2 in holes:
		for v in [h.position.x, h.end.x]:
			if v > r.position.x and v < r.end.x:
				xs.append(v)
		for v in [h.position.y, h.end.y]:
			if v > r.position.y and v < r.end.y:
				zs.append(v)
	xs.sort()
	zs.sort()
	var out: Array[Rect2] = []
	for i in xs.size() - 1:
		var start := -1
		for j in zs.size():
			var free := false
			if j < zs.size() - 1:
				var c := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
				free = xs[i + 1] - xs[i] > 0.001 and zs[j + 1] - zs[j] > 0.001
				for h: Rect2 in holes:
					if h.has_point(c):
						free = false
			if free and start < 0:
				start = j
			elif not free and start >= 0:
				out.append(Rect2(xs[i], zs[start], xs[i + 1] - xs[i], zs[j] - zs[start]))
				start = -1
	return out


## 外矩形减内矩形的环。
static func _ring(outer: Rect2, inner: Rect2) -> Array[Rect2]:
	return _subtract(outer, [inner])


func _ripple(seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 4.0
	tex.noise = noise
	return tex
