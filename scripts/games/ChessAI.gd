class_name ChessAI
extends RefCounted
## 国际象棋电脑对手：负极大值 + Alpha-Beta 剪枝，吃子优先排序；叶子节点做有限层的吃子延伸（静态搜索），
## 避免“吃了子马上被吃回来”这类明显漏着。估值 = 子力 + 简单的位置表（兵往前、马象居中、王躲在后排）。
## 难度：简单 = 1 层且带随机；普通 = 2 层；困难 = 3 层。在后台线程里跑，不卡画面（见 ChessTable）。

const VALUES := [0, 100, 320, 330, 500, 900, 0]
const MATE := 100000

## 位置表（白方视角，下标 = 行 * 8 + 列，a1 = 0）。黑方用镜像。
const PAWN_TABLE := [
	0, 0, 0, 0, 0, 0, 0, 0,
	5, 10, 10, -20, -20, 10, 10, 5,
	5, -5, -10, 0, 0, -10, -5, 5,
	0, 0, 0, 20, 20, 0, 0, 0,
	5, 5, 10, 25, 25, 10, 5, 5,
	10, 10, 20, 30, 30, 20, 10, 10,
	50, 50, 50, 50, 50, 50, 50, 50,
	0, 0, 0, 0, 0, 0, 0, 0]
const KNIGHT_TABLE := [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20, 0, 5, 5, 0, -20, -40,
	-30, 5, 10, 15, 15, 10, 5, -30,
	-30, 0, 15, 20, 20, 15, 0, -30,
	-30, 5, 15, 20, 20, 15, 5, -30,
	-30, 0, 10, 15, 15, 10, 0, -30,
	-40, -20, 0, 0, 0, 0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50]
const BISHOP_TABLE := [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10, 5, 0, 0, 0, 0, 5, -10,
	-10, 10, 10, 10, 10, 10, 10, -10,
	-10, 0, 10, 10, 10, 10, 0, -10,
	-10, 5, 5, 10, 10, 5, 5, -10,
	-10, 0, 5, 10, 10, 5, 0, -10,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-20, -10, -10, -10, -10, -10, -10, -20]
const KING_TABLE := [
	20, 30, 10, 0, 0, 10, 30, 20,
	20, 20, 0, 0, 0, 0, 20, 20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30]

const DEPTH_BY_LEVEL := {"easy": 1, "normal": 2, "hard": 3}

var nodes := 0
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()


## 为当前一方选一步。level = easy / normal / hard。没有合法走法时返回 -1。
func choose(game: ChessGame, level: String) -> int:
	nodes = 0
	var depth: int = DEPTH_BY_LEVEL.get(level, 2)
	var moves := _ordered(game, game.legal_moves())
	if moves.is_empty():
		return -1
	var best := moves[0]
	var best_score := -MATE * 2
	var alpha := -MATE * 2
	for m in moves:
		game._make(m)
		var score := -_negamax(game, depth - 1, -MATE * 2, -alpha, 1)
		game._unmake()
		if level == "easy":
			score += _rng.randi_range(-60, 60)   # 简单：带点随机，偶尔走得不那么准
		if score > best_score:
			best_score = score
			best = m
		alpha = maxi(alpha, score)
	return best


func _negamax(game: ChessGame, depth: int, alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if depth <= 0:
		return _quiesce(game, alpha, beta, 2)
	var moves := game.legal_moves()
	if moves.is_empty():
		return -MATE + ply if game.in_check() else 0
	for m in _ordered(game, moves):
		game._make(m)
		var score := -_negamax(game, depth - 1, -beta, -alpha, ply + 1)
		game._unmake()
		if score >= beta:
			return beta
		alpha = maxi(alpha, score)
	return alpha


## 吃子延伸：只看吃子，最多 depth 层。
func _quiesce(game: ChessGame, alpha: int, beta: int, depth: int) -> int:
	var stand := evaluate(game)
	if depth == 0 or stand >= beta:
		return maxi(stand, alpha) if stand < beta else beta
	alpha = maxi(alpha, stand)
	var mover := game.white_to_move
	for m in _ordered(game, game.pseudo_moves()):
		if not (ChessGame.m_flags(m) & ChessGame.F_CAPTURE):
			continue
		game._make(m)
		if game.in_check(mover):
			game._unmake()
			continue
		var score := -_quiesce(game, -beta, -alpha, depth - 1)
		game._unmake()
		if score >= beta:
			return beta
		alpha = maxi(alpha, score)
	return alpha


## 吃子在前（被吃的越值钱、吃人的越便宜越靠前），升变也靠前。
func _ordered(game: ChessGame, moves: PackedInt32Array) -> PackedInt32Array:
	var scored: Array = []
	for m in moves:
		var s := 0
		if ChessGame.m_flags(m) & ChessGame.F_CAPTURE:
			var victim := absi(game.board[ChessGame.m_to(m)])
			s = 10 * VALUES[victim if victim != 0 else ChessGame.PAWN] - VALUES[absi(game.board[ChessGame.m_from(m)])] + 10000
		if ChessGame.m_promo(m) != 0:
			s += 8000
		scored.append([s, m])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := PackedInt32Array()
	for e in scored:
		out.append(e[1])
	return out


## 静态估值（当前走棋一方的视角，分）。
static func evaluate(game: ChessGame) -> int:
	var score := 0
	for sq in 64:
		var p := game.board[sq]
		if p == 0:
			continue
		var kind := absi(p)
		var idx := sq if p > 0 else (7 - sq / 8) * 8 + sq % 8
		var v: int = VALUES[kind]
		match kind:
			ChessGame.PAWN: v += PAWN_TABLE[idx]
			ChessGame.KNIGHT: v += KNIGHT_TABLE[idx]
			ChessGame.BISHOP: v += BISHOP_TABLE[idx]
			ChessGame.KING: v += KING_TABLE[idx]
		score += v if p > 0 else -v
	return score if game.white_to_move else -score
