class_name ChessTable
extends Interactable
## 木屋茶几上的国际象棋：一块 3D 棋盘，棋子位置和 2D 对局实时同步。
## 看着棋盘按 E（站着或坐在沙发上都行）打开 2D 棋盘界面（ChessPanel）；Esc 或“关闭”回到世界。
## 打开期间锁住玩家移动（鼠标给棋盘用）。本节点原点 = 棋盘底面中心，白方在本地 +Z 一侧（靠沙发）。

const SIZE := 0.52
const LIGHT := Color(0.90, 0.82, 0.66)
const DARK := Color(0.42, 0.28, 0.18)
const IVORY := Color(0.94, 0.91, 0.84)
const EBONY := Color(0.12, 0.10, 0.09)
## 各棋子（兵马象车后王）的高度与半径（米）
const SHAPES := [[0.0, 0.0], [0.034, 0.016], [0.046, 0.018], [0.052, 0.018], [0.044, 0.019], [0.062, 0.020], [0.068, 0.020]]

var panel: ChessPanel
var _pieces: Node3D
var _player: FirstPersonController = null


static func create(id: StringName, pos: Vector3, yaw_deg: float) -> ChessTable:
	var t := ChessTable.new()
	t.name = "ChessTable"
	t.uid = id
	t.display_name = "国际象棋"
	t.position = pos
	t.rotation.y = deg_to_rad(yaw_deg)
	return t


func _ready() -> void:
	_build_board()
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.INTERACTABLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE + 0.1, 0.18, SIZE + 0.1)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.09, 0.0)
	body.add_child(cs)
	add_child(body)
	panel = ChessPanel.new()
	panel.name = "ChessPanel"
	add_child(panel)
	panel.position_changed.connect(sync_pieces)
	panel.closed.connect(_on_closed)
	sync_pieces()
	super()


func get_prompt(_actor: Node) -> String:
	return "E  下国际象棋"


func interact(actor: Node) -> void:
	_player = actor as FirstPersonController
	if _player != null:
		_player.input_locked = true
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.open()


func _on_closed() -> void:
	if _player != null:
		_player.input_locked = false
		_player = null
	if GameSettings.can_grab_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_publish_state()


func get_state() -> String:
	return panel.game.to_fen() if panel != null else ""


func _build_board() -> void:
	var cell := SIZE / 8.0
	_box(Vector3(SIZE + 0.04, 0.022, SIZE + 0.04), Vector3(0.0, 0.011, 0.0), ArtMaterials.pbr("stained_pine", Color(0.45, 0.30, 0.20)))
	var light := ArtMaterials.flat(LIGHT, 0.6)
	var dark := ArtMaterials.flat(DARK, 0.6)
	for sq in 64:
		var c := square_center(sq)
		_box(Vector3(cell, 0.004, cell), Vector3(c.x, 0.024, c.z), light if (sq % 8 + sq / 8) % 2 == 1 else dark)
	_pieces = Node3D.new()
	_pieces.name = "Pieces"
	add_child(_pieces)


## 某格中心（本地坐标，棋盘面上）：a1 在白方左手边（本地 -X、+Z 角）。
static func square_center(sq: int) -> Vector3:
	var cell := SIZE / 8.0
	return Vector3((sq % 8 - 3.5) * cell, 0.026, (3.5 - sq / 8) * cell)


## 按当前棋局重摆 3D 棋子。
func sync_pieces() -> void:
	if _pieces == null:
		return
	for c in _pieces.get_children():
		c.free()
	var ivory := ArtMaterials.flat(IVORY, 0.35)
	var ebony := ArtMaterials.flat(EBONY, 0.35)
	for sq in 64:
		var p := panel.game.board[sq]
		if p == 0:
			continue
		_pieces.add_child(_piece(absi(p), ivory if p > 0 else ebony, square_center(sq), p < 0))


func piece_count() -> int:
	return _pieces.get_child_count() if _pieces != null else 0


## 一个棋子：圆底座 + 身子 + 按种类不同的头（兵小球、马侧头、象尖顶、车方垛、后冠、王十字）。
func _piece(kind: int, mat: Material, at: Vector3, black: bool) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var h: float = SHAPES[kind][0]
	var r: float = SHAPES[kind][1]
	_cyl(n, r, r * 1.05, 0.008, 0.004, mat)
	_cyl(n, r * 0.55, r * 0.8, h * 0.6, 0.008 + h * 0.3, mat)
	match kind:
		ChessGame.PAWN:
			_sphere(n, r * 0.7, Vector3(0.0, h * 0.75, 0.0), mat)
		ChessGame.KNIGHT:
			var head := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(r * 0.9, h * 0.45, r * 1.6)
			b.material = mat
			head.mesh = b
			head.position = Vector3(0.0, h * 0.78, r * 0.25 * (1.0 if black else -1.0))
			head.rotation.x = deg_to_rad(-25.0 if not black else 25.0)
			n.add_child(head)
		ChessGame.BISHOP:
			_cyl(n, 0.0, r * 0.7, h * 0.4, h * 0.82, mat)
		ChessGame.ROOK:
			_cyl(n, r * 0.85, r * 0.85, h * 0.25, h * 0.8, mat)
		ChessGame.QUEEN:
			_cyl(n, r * 0.9, r * 0.6, h * 0.2, h * 0.75, mat)
			_sphere(n, r * 0.35, Vector3(0.0, h * 0.92, 0.0), mat)
		ChessGame.KING:
			_cyl(n, r * 0.8, r * 0.6, h * 0.2, h * 0.72, mat)
			_boxp(n, Vector3(r * 0.3, h * 0.25, r * 0.3), Vector3(0.0, h * 0.95, 0.0), mat)
			_boxp(n, Vector3(r * 0.8, r * 0.3, r * 0.3), Vector3(0.0, h * 0.97, 0.0), mat)
	return n


func _cyl(parent: Node3D, top_r: float, bottom_r: float, height: float, center_y: float, mat: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = 12
	c.rings = 1
	c.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.position = Vector3(0.0, center_y, 0.0)
	parent.add_child(mi)


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> void:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	s.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.position = pos
	parent.add_child(mi)


func _boxp(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	_boxp(self, size, pos, mat)
