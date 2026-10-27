class_name CottageDoor
extends Interactable
## 石头小屋的门：挂着一把三环转锁。状态 "locked" / "closed" / "open"（按 uid 存档和联机同步）。
##   · 锁着时按 E：三封信都读过就把三个环转到独木舟、狐狸、灯塔，锁开、门推开（flags.cottage_unlocked）；
##     没读全只提示已经知道哪几个图案；联机做客时提示要房主来开（世界是房主的）。
##   · 开锁以后就是普通的木门，按 E 开 / 关。
## 本节点原点在铰链（门洞左下角、墙厚中间）；门板沿本地 +X 展开，向屋里（本地 -Z）转开。

const OPEN_DEG := 100.0
const SWING_TIME := 0.7

var size := Vector2(1.1, 2.05)
var leaf: AnimatableBody3D
var _state := "locked"
var _tween: Tween = null


static func create(id: StringName, door_size: Vector2, mat: Material) -> CottageDoor:
	var d := CottageDoor.new()
	d.name = "CottageDoor"
	d.uid = id
	d.display_name = "石头小屋的门"
	d.size = door_size
	d.leaf = AnimatableBody3D.new()
	d.leaf.name = "Leaf"
	d.leaf.sync_to_physics = true
	d.leaf.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	d.leaf.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(door_size.x, door_size.y, 0.07)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(door_size.x * 0.5, door_size.y * 0.5, 0.0)
	d.leaf.add_child(mi)
	var knob := MeshInstance3D.new()
	var kb := BoxMesh.new()
	kb.size = Vector3(0.07, 0.07, 0.16)
	knob.mesh = kb
	knob.material_override = ArtMaterials.named("M_Metal")
	knob.position = Vector3(door_size.x * 0.86, 0.95, 0.0)
	d.leaf.add_child(knob)
	# 门外的三环转锁：一块铁板上三个铜环
	var plate := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.16, 0.36, 0.03)
	plate.mesh = pb
	plate.material_override = ArtMaterials.named("M_Metal")
	plate.position = Vector3(door_size.x * 0.86, 1.25, 0.05)
	d.leaf.add_child(plate)
	var brass := ArtMaterials.flat(Color(0.72, 0.55, 0.25), 0.4, false, 0.85)
	for i in 3:
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 0.05
		ring.mesh = cyl
		ring.material_override = brass
		ring.rotation.x = PI * 0.5
		ring.position = Vector3(door_size.x * 0.86, 1.36 - i * 0.11, 0.08)
		d.leaf.add_child(ring)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(door_size.x, door_size.y, 0.12)
	cs.shape = shape
	cs.position = Vector3(door_size.x * 0.5, door_size.y * 0.5, 0.0)
	d.leaf.add_child(cs)
	d.add_child(d.leaf)
	return d


func is_locked() -> bool:
	return _state == "locked"


func is_open() -> bool:
	return _state == "open"


func get_prompt(_actor: Node) -> String:
	match _state:
		"locked" when GameRules.is_story():
			return tr("E  看看门锁")
		"open":
			return tr("E  关上木门")
	return tr("E  打开木门")


func interact(_actor: Node) -> void:
	if _state != "locked":
		set_open(_state != "open")
		return
	# 休闲模式没有剧情：门没锁，推开就进
	if not GameRules.is_story():
		set_open(true)
		return
	if Net.is_client():
		EventBus.toast_requested.emit(tr("联机做客时，这扇门要房主来开。"))
		Sound.play("door_locked", global_position)
		return
	if PaddlerStory.all_read():
		unlock()
		return
	Sound.play("door_locked", global_position)
	var known := PaddlerStory.known_symbols()
	if known.is_empty():
		EventBus.toast_requested.emit(tr("门锁着。锁上有三个刻着图案的转环，不知道该转到哪里。"))
	else:
		EventBus.toast_requested.emit(tr("门锁着。三个转环里你知道 %d 个：%s。") % [known.size(), tr("、").join(known)])


## 开锁并把门推开。
func unlock() -> void:
	var lock: Dictionary = PaddlerStory.data().get("lock", {})
	Sound.play("unlock", global_position)
	EventBus.toast_requested.emit(PaddlerStory.text(lock, "unlock"))
	WorldState.flags["cottage_unlocked"] = true
	SaveManager.request_save()
	set_open(true)


func set_open(value: bool, instant := false) -> void:
	_state = "open" if value else "closed"
	var target := deg_to_rad(OPEN_DEG) if value else 0.0
	if _tween != null:
		_tween.kill()
	if instant:
		leaf.rotation.y = target
	else:
		_tween = create_tween()
		_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_tween.tween_property(leaf, "rotation:y", target, SWING_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_publish_state()


func get_state() -> String:
	return _state


func apply_state(state: String) -> void:
	if state == "locked":
		_state = "locked"
		leaf.rotation.y = 0.0
		return
	WorldState.flags["cottage_unlocked"] = true
	set_open(state == "open", true)


func apply_remote_state(state: String) -> void:
	if state == "locked":
		apply_state(state)
		return
	WorldState.flags["cottage_unlocked"] = true
	set_open(state == "open")
