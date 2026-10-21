class_name BlockyModel
extends Node3D
## 由 species.json 的 parts 生成的方块动物模型：每个部位一个转轴节点 + 一个网格。
## animate() 按移动方式做简单的程序动画（四足交替迈腿、跳跃、扑翅、摆尾、水母一张一缩）。

var def: Dictionary = {}
var parts: Dictionary = {}
var _palette: Dictionary = {}
var _phase := 0.0


func setup(species_def: Dictionary, palette: Dictionary) -> void:
	def = species_def
	_palette = palette
	var px := float(def.get("px", 0.0625))
	var kind := str(def.get("material", "default"))
	for part_name in def.get("parts", {}):
		var p: Dictionary = def["parts"][part_name]
		var pivot := Node3D.new()
		pivot.name = part_name
		var pv: Array = p["pivot"]
		pivot.position = Vector3(float(pv[0]), float(pv[1]), float(pv[2])) * px
		var mi := MeshInstance3D.new()
		mi.mesh = BlockyMesh.build(p["boxes"], _color, px, kind)
		pivot.add_child(mi)
		add_child(pivot)
		parts[part_name] = pivot


func recolor(palette: Dictionary) -> void:
	_palette = palette
	var px := float(def.get("px", 0.0625))
	var kind := str(def.get("material", "default"))
	for part_name in parts:
		var mi := (parts[part_name] as Node3D).get_child(0) as MeshInstance3D
		mi.mesh = BlockyMesh.build(def["parts"][part_name]["boxes"], _color, px, kind)


func _color(key: String) -> Color:
	if key.begins_with("#"):
		return Color.html(key)
	return Color.html(str(_palette.get(key, "#ff00ff")))


func _rot(part: String, v: Vector3) -> void:
	if parts.has(part):
		(parts[part] as Node3D).rotation = v


## speed：当前移动速度（m/s）；flying / hopping 由移动方式决定。
func animate(delta: float, speed: float) -> void:
	var loco := str(def.get("locomotion", "walk"))
	match loco:
		"walk", "hop":
			_phase += delta * (2.0 + speed * 7.0)
			var a := sin(_phase) * clampf(speed * 0.45, 0.0, 0.8)
			_rot("leg_fl", Vector3(a, 0, 0))
			_rot("leg_br", Vector3(a, 0, 0))
			_rot("leg_fr", Vector3(-a, 0, 0))
			_rot("leg_bl", Vector3(-a, 0, 0))
			_rot("tail", Vector3(0.25 + sin(_phase * 0.5) * 0.15, sin(_phase * 0.7) * 0.2, 0))
			_rot("head", Vector3(sin(_phase * 0.5) * 0.06, 0, 0))
		"swim_surface":
			_phase += delta * 2.0
			_rot("head", Vector3(sin(_phase) * 0.12, 0, 0))
			position.y = sin(_phase * 0.8) * 0.02
		"fly", "flutter":
			_phase += delta * (14.0 if loco == "fly" else 22.0)
			var f := sin(_phase) * (0.9 if loco == "fly" else 1.1)
			_rot("wing_l", Vector3(0, 0, f))
			_rot("wing_r", Vector3(0, 0, -f))
		"fish":
			_phase += delta * (5.0 + speed * 6.0)
			_rot("tail", Vector3(0, sin(_phase) * 0.6, 0))
			_rot("body", Vector3(0, sin(_phase) * 0.08, 0))
		"manta":
			# 蝠鲼：两翼慢慢上下扇，像在水里飞
			_phase += delta * 1.4
			var w := sin(_phase) * 0.45
			_rot("wing_l", Vector3(0, 0, -w))
			_rot("wing_r", Vector3(0, 0, w))
			_rot("tail", Vector3(sin(_phase * 0.7) * 0.08, sin(_phase * 0.5) * 0.15, 0))
		"shark":
			_phase += delta * (2.2 + speed * 2.5)
			_rot("tail", Vector3(0, sin(_phase) * 0.35, 0))
			_rot("body", Vector3(0, sin(_phase) * 0.04, 0))
		"turtle":
			_phase += delta * 1.6
			var s := sin(_phase) * 0.6
			_rot("fin_fl", Vector3(0, 0, s))
			_rot("fin_fr", Vector3(0, 0, -s))
			_rot("fin_bl", Vector3(0, 0, -s * 0.5))
			_rot("fin_br", Vector3(0, 0, s * 0.5))
			_rot("head", Vector3(sin(_phase * 0.4) * 0.1, sin(_phase * 0.3) * 0.2, 0))
		"jelly":
			_phase += delta * 1.8
			var pulse := 1.0 + sin(_phase) * 0.12
			if parts.has("body"):
				(parts["body"] as Node3D).scale = Vector3(pulse, 2.0 - pulse, pulse)
			_rot("tentacles", Vector3(sin(_phase * 0.7) * 0.12, 0, cos(_phase * 0.6) * 0.12))
