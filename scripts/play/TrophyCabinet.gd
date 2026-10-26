class_name TrophyCabinet
extends Node3D
## 木屋北墙的收藏柜（CabinLife 放置，木屋局部坐标，正面朝屋里 +Z）：三层木架，十二个格子，
## 收集到什么就摆出什么——云珠、古代碎片、珍珠、贝壳、石板、山铜晶、宝箱、鱼标本、金牌、水漂石、小图腾、星盘。
## 按 WorldState 的记录显示（存档、换世界回来都一样），每 2 秒对一次。

const W := 1.9
const H := 1.75
const D := 0.42
const SHELVES := [0.05, 0.62, 1.19]

## 格子：id、名字、条件（Callable 由 _met 判断）
const SLOTS := [
	["cloud_pearl", "云珠"], ["amber_shard", "古代碎片"], ["sea_pearl", "珍珠"], ["sea_shell", "贝壳"],
	["tablet", "古代石板"], ["orichalcum", "山铜晶"], ["chest", "宝箱"], ["fish", "鱼标本"],
	["medal", "金牌"], ["skip_stone", "水漂石"], ["totem", "小图腾"], ["star_globe", "星盘"],
]

var _items: Dictionary = {}     ## id -> Node3D
var _t := 0.0


static func create(at: Vector3) -> TrophyCabinet:
	var c := TrophyCabinet.new()
	c.name = "TrophyCabinet"
	c.position = at
	c._build()
	return c


func _build() -> void:
	add_to_group("trophy_cabinet")
	var wood := ArtMaterials.pbr("stained_pine", Color(0.62, 0.44, 0.3), "world")
	var dark := ArtMaterials.pbr("stained_pine", Color(0.42, 0.3, 0.2), "world")
	# 背板、两侧、顶、三层隔板
	_box(Vector3(W, H, 0.04), Vector3(0.0, H * 0.5, -D * 0.5 + 0.02), dark)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.05, H, D), Vector3(sx * (W * 0.5 - 0.025), H * 0.5, 0.0), wood)
	_box(Vector3(W, 0.05, D), Vector3(0.0, H - 0.025, 0.0), wood)
	for y: float in SHELVES:
		_box(Vector3(W - 0.1, 0.04, D - 0.04), Vector3(0.0, y + 0.02, 0.0), wood)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(W, H, D)
	cs.shape = shape
	cs.position = Vector3(0.0, H * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)
	# 柜里一盏暖色小灯，晚上也看得清摆的东西
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 0.9
	lamp.omni_range = 1.8
	lamp.position = Vector3(0.0, H - 0.2, 0.15)
	add_child(lamp)
	for i in SLOTS.size():
		var id: String = SLOTS[i][0]
		var row := i / 4
		var col := i % 4
		var n := _model(id)
		n.name = "Trophy_" + id
		n.position = Vector3(-W * 0.5 + 0.28 + col * ((W - 0.56) / 3.0), float(SHELVES[2 - row]) + 0.04, 0.02)
		add_child(n)
		_items[id] = n
	refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 2.0
		refresh()


func refresh() -> void:
	for id: String in _items:
		(_items[id] as Node3D).visible = _met(id)


## 现在摆出来的格子 id（自动检查读）。
func shown_ids() -> Array:
	var out := []
	for id: String in _items:
		if _met(id):
			out.append(id)
	return out


static func _met(id: String) -> bool:
	match id:
		"cloud_pearl":
			return not WorldState.collected("world_02").is_empty()
		"amber_shard":
			return not WorldState.collected("world_03").is_empty()
		"sea_pearl":
			return WorldState.collected("world_04").any(func(x: String) -> bool: return x.begins_with("pearl"))
		"sea_shell":
			return WorldState.collected("world_04").any(func(x: String) -> bool: return x.begins_with("shell"))
		"tablet":
			return not WorldState.journal_list("lore").is_empty()
		"orichalcum":
			return bool(WorldState.flags.get("atlantis_spire", false))
		"chest":
			return not WorldState.treasures.is_empty()
		"fish":
			return not WorldState.catches.is_empty()
		"medal":
			return Play.met({"type": "medal"})
		"skip_stone":
			return int(WorldState.records.get("skip_best", 0)) >= 5
		"totem":
			return Play.met({"type": "quests", "count": 0})
		"star_globe":
			return WorldState.journal_list("constellations").size() >= 3
	return false


func _model(id: String) -> Node3D:
	var n := Node3D.new()
	match id:
		"cloud_pearl":
			_sphere(n, 0.09, Vector3(0, 0.12, 0), ArtMaterials.glow(Color(0.6, 0.9, 1.0), 2.0))
			_box(Vector3(0.22, 0.03, 0.16), Vector3(0, 0.015, 0), ArtMaterials.flat(Color(0.5, 0.2, 0.25), 0.8), n)
		"amber_shard":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.12, 0.24, 0.08)
			_mesh(n, pm, Vector3(0, 0.12, 0), ArtMaterials.glow(Color(1.0, 0.7, 0.3), 1.8))
		"sea_pearl":
			_box(Vector3(0.24, 0.04, 0.18), Vector3(0, 0.02, 0), ArtMaterials.flat(Color(0.55, 0.7, 0.85), 0.5), n)
			_sphere(n, 0.06, Vector3(0, 0.1, 0), ArtMaterials.flat(Color(0.97, 0.96, 1.0), 0.15, false, 0.3))
		"sea_shell":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.22, 0.18, 0.05)
			var mi := _mesh(n, pm, Vector3(0, 0.1, 0), ArtMaterials.flat(Color(1.0, 0.72, 0.62), 0.5))
			mi.rotation.z = PI
		"tablet":
			_box(Vector3(0.18, 0.26, 0.04), Vector3(0, 0.13, -0.05), ArtMaterials.flat(Color(0.62, 0.6, 0.56), 0.9), n)
			_box(Vector3(0.12, 0.02, 0.005), Vector3(0, 0.18, -0.028), ArtMaterials.glow(Color(1.0, 0.55, 0.25), 1.6), n)
			_box(Vector3(0.12, 0.02, 0.005), Vector3(0, 0.12, -0.028), ArtMaterials.glow(Color(1.0, 0.55, 0.25), 1.6), n)
		"orichalcum":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.1, 0.32, 0.1)
			_mesh(n, pm, Vector3(0, 0.16, 0), ArtMaterials.glow(Color(1.0, 0.45, 0.2), 2.6))
		"chest":
			_box(Vector3(0.26, 0.14, 0.17), Vector3(0, 0.07, 0), ArtMaterials.pbr("weathered_planks", Color(0.72, 0.5, 0.32), "world"), n)
			_box(Vector3(0.27, 0.03, 0.18), Vector3(0, 0.15, 0), ArtMaterials.flat(Color(0.86, 0.66, 0.28), 0.35, false, 0.8), n)
		"fish":
			_box(Vector3(0.36, 0.2, 0.03), Vector3(0, 0.2, -0.17), ArtMaterials.pbr("stained_pine", Color(0.5, 0.36, 0.24), "world"), n)
			_box(Vector3(0.24, 0.08, 0.04), Vector3(0, 0.2, -0.14), ArtMaterials.flat(Color(0.7, 0.62, 0.68), 0.4, false, 0.2), n)
			_box(Vector3(0.06, 0.1, 0.03), Vector3(0.14, 0.2, -0.14), ArtMaterials.flat(Color(0.6, 0.52, 0.58), 0.4), n)
		"medal":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.08
			cm.bottom_radius = 0.08
			cm.height = 0.02
			var mi := _mesh(n, cm, Vector3(0, 0.12, -0.05), ArtMaterials.flat(Color(1.0, 0.8, 0.3), 0.25, false, 0.9))
			mi.rotation.x = PI * 0.5
			_box(Vector3(0.04, 0.1, 0.01), Vector3(0, 0.22, -0.06), ArtMaterials.flat(Color(0.8, 0.2, 0.2), 0.8), n)
		"skip_stone":
			var sm := SphereMesh.new()
			sm.radius = 0.08
			sm.height = 0.05
			_mesh(n, sm, Vector3(0, 0.03, 0), ArtMaterials.flat(Color(0.55, 0.55, 0.58), 0.7))
		"totem":
			_box(Vector3(0.1, 0.1, 0.1), Vector3(0, 0.05, 0), ArtMaterials.flat(Color(0.5, 0.36, 0.24), 0.9), n)
			_box(Vector3(0.09, 0.09, 0.09), Vector3(0, 0.145, 0), ArtMaterials.flat(Color(0.62, 0.3, 0.22), 0.9), n)
			_box(Vector3(0.08, 0.08, 0.08), Vector3(0, 0.23, 0), ArtMaterials.flat(Color(0.35, 0.5, 0.42), 0.9), n)
		"star_globe":
			_sphere(n, 0.1, Vector3(0, 0.13, 0), ArtMaterials.glow(Color(0.5, 0.55, 1.0), 1.4))
			_box(Vector3(0.12, 0.03, 0.12), Vector3(0, 0.015, 0), ArtMaterials.flat(Color(0.86, 0.66, 0.28), 0.35, false, 0.8), n)
	return n


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	_mesh(parent, sm, pos, mat)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_mesh(parent if parent != null else self, bm, pos, mat)
