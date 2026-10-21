class_name ChessPanel
extends CanvasLayer
## 2D 国际象棋界面（在木屋茶几上的棋盘按 E 打开）。
##   点自己的棋子 → 能走的格子出现圆点 → 点目标格落子；兵走到底线时选升变成什么。
##   模式：双人同屏（轮流走）、人机（你执白 / 你执黑）；难度：简单 / 普通 / 困难。
##   按钮：新局、悔棋（人机模式下一次退两步，回到你走之前）、翻转棋盘、关闭（Esc 也行）。
##   电脑在后台线程里思考，不卡画面。棋局随时存进 WorldState.flags["chess"]，关掉再打开接着下。

signal closed
signal position_changed

const LIGHT := Color(0.93, 0.85, 0.70)
const DARK := Color(0.62, 0.44, 0.30)
const SELECT := Color(0.98, 0.86, 0.35, 0.75)
const LAST := Color(0.95, 0.78, 0.35, 0.45)
const CHECK := Color(0.95, 0.25, 0.20, 0.65)
const GLYPHS := ["", "♟", "♞", "♝", "♜", "♛", "♚"]
const MODES := ["pvp", "ai_black", "ai_white"]            ## 双人 / 你执白（电脑执黑）/ 你执黑（电脑执白）
const MODE_NAMES := ["双人同屏", "人机 · 我执白", "人机 · 我执黑"]
const LEVELS := ["easy", "normal", "hard"]
const LEVEL_NAMES := ["简单", "普通", "困难"]
const BOARD_PX := 560.0

var game := ChessGame.new()
var mode := "ai_black"
var level := "normal"
var flipped := false
var selected := -1
var last_move := -1
var thinking := false

var _root: Control
var _board: Control
var _status: Label
var _moves: Label
var _promo_box: HBoxContainer
var _pending_promo := []        ## [from, to]
var _ai_task := -1
var _ai_result := -1
var _ai_game: ChessGame
var _piece_font: Font


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI Symbol", "Noto Sans Symbols 2", "DejaVu Sans", "Arial Unicode MS", "sans-serif"])
	_piece_font = sf
	_build()
	_restore()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	(_root.find_child("Mode", true, false) as OptionButton).select(MODES.find(mode))
	(_root.find_child("Level", true, false) as OptionButton).select(LEVELS.find(level))
	_refresh()
	_maybe_ai()


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 界面

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameSettings.ui_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	_board = Control.new()
	_board.name = "Board"
	_board.custom_minimum_size = Vector2(BOARD_PX, BOARD_PX)
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_board_input)
	row.add_child(_board)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(280, 0)
	side.add_theme_constant_override("separation", 10)
	row.add_child(side)
	var title := Label.new()
	title.text = "国际象棋 · Chess"
	title.add_theme_font_size_override("font_size", 26)
	side.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status)
	var mode_opt := OptionButton.new()
	for n in MODE_NAMES:
		mode_opt.add_item(n)
	mode_opt.select(MODES.find(mode))
	mode_opt.item_selected.connect(_on_mode)
	mode_opt.name = "Mode"
	side.add_child(mode_opt)
	var level_opt := OptionButton.new()
	for n in LEVEL_NAMES:
		level_opt.add_item("电脑难度：" + n)
	level_opt.select(LEVELS.find(level))
	level_opt.item_selected.connect(_on_level)
	level_opt.name = "Level"
	side.add_child(level_opt)
	var buttons := HFlowContainer.new()
	for item in [["新局", new_game], ["悔棋", undo], ["翻转棋盘", _flip], ["关闭（Esc）", close]]:
		var b := Button.new()
		b.text = item[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(item[1])
		buttons.add_child(b)
	side.add_child(buttons)
	_promo_box = HBoxContainer.new()
	_promo_box.visible = false
	var promo_label := Label.new()
	promo_label.text = "升变为："
	_promo_box.add_child(promo_label)
	for kind in [ChessGame.QUEEN, ChessGame.ROOK, ChessGame.BISHOP, ChessGame.KNIGHT]:
		var b := Button.new()
		b.text = ["", "", "马", "象", "车", "后"][kind]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_promote.bind(kind))
		_promo_box.add_child(b)
	side.add_child(_promo_box)
	var moves_title := Label.new()
	moves_title.text = "着法记录"
	side.add_child(moves_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 260)
	side.add_child(scroll)
	_moves = Label.new()
	_moves.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_moves.custom_minimum_size = Vector2(260, 0)
	scroll.add_child(_moves)


func _sq_rect(sq: int) -> Rect2:
	var cell := BOARD_PX / 8.0
	var f := sq % 8
	var r := sq / 8
	var col := 7 - f if flipped else f
	var row := r if flipped else 7 - r
	return Rect2(col * cell, row * cell, cell, cell)


func square_at(pos: Vector2) -> int:
	var cell := BOARD_PX / 8.0
	var col := int(pos.x / cell)
	var row := int(pos.y / cell)
	if col < 0 or col > 7 or row < 0 or row > 7:
		return -1
	var f := 7 - col if flipped else col
	var r := row if flipped else 7 - row
	return r * 8 + f


func _draw_board() -> void:
	var cell := BOARD_PX / 8.0
	var check_sq := game.king_square(game.white_to_move) if game.in_check() else -1
	var targets := {}
	if selected >= 0:
		for m in game.legal_moves_from(selected):
			targets[ChessGame.m_to(m)] = true
	for sq in 64:
		var rect := _sq_rect(sq)
		_board.draw_rect(rect, LIGHT if (sq % 8 + sq / 8) % 2 == 1 else DARK)
		if last_move >= 0 and (sq == ChessGame.m_from(last_move) or sq == ChessGame.m_to(last_move)):
			_board.draw_rect(rect, LAST)
		if sq == selected:
			_board.draw_rect(rect, SELECT)
		if sq == check_sq:
			_board.draw_rect(rect, CHECK)
		var p := game.board[sq]
		if p != 0:
			_draw_piece(rect, p)
		if targets.has(sq):
			if p != 0:
				_board.draw_arc(rect.get_center(), cell * 0.44, 0.0, TAU, 32, Color(0.1, 0.1, 0.1, 0.45), 4.0, true)
			else:
				_board.draw_circle(rect.get_center(), cell * 0.14, Color(0.1, 0.1, 0.1, 0.35))
	# 坐标
	for i in 8:
		var file_sq := i if not flipped else 7 - i
		_board.draw_string(GameSettings.ui_theme().default_font, Vector2(i * cell + cell - 13.0, BOARD_PX - 4.0), "abcdefgh"[file_sq], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.15, 0.1, 0.8))
		var rank_n := 8 - i if not flipped else i + 1
		_board.draw_string(GameSettings.ui_theme().default_font, Vector2(3.0, i * cell + 15.0), str(rank_n), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.15, 0.1, 0.8))


## 棋子：都用实心字形，白方填象牙白、描深色边；黑方填深色、描浅边。
func _draw_piece(rect: Rect2, p: int) -> void:
	var glyph: String = GLYPHS[absi(p)]
	var size := int(rect.size.y * 0.78)
	var base := rect.position + Vector2(rect.size.x * 0.5 - size * 0.42, rect.size.y * 0.80)
	var fill := Color(0.98, 0.96, 0.90) if p > 0 else Color(0.13, 0.11, 0.10)
	var edge := Color(0.15, 0.12, 0.10) if p > 0 else Color(0.85, 0.80, 0.70)
	_board.draw_string_outline(_piece_font, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, edge)
	_board.draw_string(_piece_font, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


func _refresh() -> void:
	_board.queue_redraw()
	var r := game.result()
	var side := "白方" if game.white_to_move else "黑方"
	var text := ""
	match r:
		"checkmate_white": text = "将死！白方胜"
		"checkmate_black": text = "将死！黑方胜"
		"stalemate": text = "逼和（无子可动）"
		"fifty": text = "和棋（50 步无吃子、无兵动）"
		"repetition": text = "和棋（同一局面出现三次）"
		"material": text = "和棋（双方子力都不足以将死）"
		_:
			text = "%s走棋%s" % [side, "（将军！）" if game.in_check() else ""]
			if thinking:
				text += "\n电脑思考中…"
			elif _is_human_turn():
				text += "\n轮到你"
	_status.text = text
	var lines := PackedStringArray()
	for i in range(0, game.moves_san.size(), 2):
		var w := game.moves_san[i]
		var b := game.moves_san[i + 1] if i + 1 < game.moves_san.size() else ""
		lines.append("%d. %s  %s" % [i / 2 + 1, w, b])
	_moves.text = "\n".join(lines)
	position_changed.emit()


func _is_human_turn() -> bool:
	if mode == "pvp":
		return true
	return game.white_to_move == (mode == "ai_black")


func _board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_square(square_at(event.position))


## 点一个格子（也给自动检查用）：选子 / 走子。返回这次是否走了一步。
func click_square(sq: int) -> bool:
	if sq < 0 or thinking or not _is_human_turn() or game.result() != "" or _promo_box.visible:
		return false
	var p := game.board[sq]
	if selected >= 0:
		for m in game.legal_moves_from(selected):
			if ChessGame.m_to(m) == sq:
				if ChessGame.m_promo(m) != 0:
					_pending_promo = [selected, sq]
					_promo_box.visible = true
					return false
				_do_move(m)
				return true
	if p != 0 and (p > 0) == game.white_to_move:
		selected = sq
	else:
		selected = -1
	_board.queue_redraw()
	return false


func _promote(kind: int) -> void:
	_promo_box.visible = false
	if _pending_promo.is_empty():
		return
	for m in game.legal_moves_from(_pending_promo[0]):
		if ChessGame.m_to(m) == _pending_promo[1] and ChessGame.m_promo(m) == kind:
			_pending_promo = []
			_do_move(m)
			return


func _do_move(m: int) -> void:
	game.play(m)
	last_move = m
	selected = -1
	_save()
	_refresh()
	_maybe_ai()


func new_game() -> void:
	_cancel_ai()
	game = ChessGame.new()
	last_move = -1
	selected = -1
	flipped = mode == "ai_white"
	_save()
	_refresh()
	_maybe_ai()


func undo() -> void:
	_cancel_ai()
	game.undo()
	# 人机模式：退到轮到你为止
	if mode != "pvp" and not _is_human_turn():
		game.undo()
	last_move = -1
	selected = -1
	_save()
	_refresh()
	_maybe_ai()


func _flip() -> void:
	flipped = not flipped
	_board.queue_redraw()


func _on_mode(i: int) -> void:
	mode = MODES[i]
	flipped = mode == "ai_white"
	_save()
	_refresh()
	_maybe_ai()


func _on_level(i: int) -> void:
	level = LEVELS[i]
	_save()


# ---------------------------------------------------------------- 电脑

func _maybe_ai() -> void:
	if not visible or thinking or mode == "pvp" or _is_human_turn() or game.result() != "":
		return
	thinking = true
	_ai_game = game.copy()
	var lv := level
	_ai_task = WorkerThreadPool.add_task(func() -> void: _ai_result = ChessAI.new().choose(_ai_game, lv), true, "chess ai")
	_refresh()


func _process(_delta: float) -> void:
	if _ai_task >= 0 and WorkerThreadPool.is_task_completed(_ai_task):
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
		thinking = false
		if _ai_result >= 0 and visible:
			_do_move(_ai_result)
		else:
			_refresh()


func _cancel_ai() -> void:
	if _ai_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
	thinking = false


## 等电脑想完并落子（自动检查用）。
func wait_ai() -> void:
	while thinking:
		await get_tree().process_frame


# ---------------------------------------------------------------- 存档

func _save() -> void:
	WorldState.flags["chess"] = {"fen": game.to_fen(), "moves": Array(game.moves_san), "mode": mode, "level": level}


func _restore() -> void:
	var s: Dictionary = WorldState.flags.get("chess", {})
	if s.is_empty():
		return
	game = ChessGame.new(str(s.get("fen", ChessGame.START_FEN)))
	game.moves_san = PackedStringArray(s.get("moves", []))
	mode = str(s.get("mode", mode))
	level = str(s.get("level", level))
	flipped = mode == "ai_white"
