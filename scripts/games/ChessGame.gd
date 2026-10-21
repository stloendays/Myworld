class_name ChessGame
extends RefCounted
## 国际象棋规则（纯逻辑，不依赖场景）：完整走法生成（含王车易位、吃过路兵、升变）、将军 / 将死 / 逼和、
## 50 步规则、三次重复、子力不足判和、悔棋、FEN 读写、标准代数记谱（SAN）。
## 用标准 perft 计数验证走法生成（开局 1/2/3 层 = 20 / 400 / 8902，Kiwipete 1/2 层 = 48 / 2039）。
##
## 棋盘：64 格，下标 = 行 * 8 + 列，a1 = 0、h1 = 7、a8 = 56、h8 = 63。
## 棋子：0 空；白方为正、黑方为负：1 兵 2 马 3 象 4 车 5 后 6 王。
## 走法：整数打包 from | to << 6 | promo << 12 | flags << 16。

const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const F_CAPTURE := 1
const F_EP := 2
const F_CASTLE := 4
const F_DOUBLE := 8

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const KNIGHT_STEPS := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const KING_STEPS := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const BISHOP_DIRS := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const ROOK_DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const LETTERS := ["", "", "N", "B", "R", "Q", "K"]

var board := PackedInt32Array()
var white_to_move := true
var castling := 15          ## 1 白短 2 白长 4 黑短 8 黑长
var ep_square := -1
var halfmove := 0
var fullmove := 1
var history: Array[Dictionary] = []   ## 悔棋用：每步的走法与恢复信息
var moves_san: PackedStringArray = []
var _keys: Dictionary = {}            ## 局面键 -> 出现次数（三次重复）


func _init(fen := START_FEN) -> void:
	load_fen(fen)


static func encode(from: int, to: int, promo := 0, flags := 0) -> int:
	return from | (to << 6) | (promo << 12) | (flags << 16)


static func m_from(m: int) -> int:
	return m & 63


static func m_to(m: int) -> int:
	return (m >> 6) & 63


static func m_promo(m: int) -> int:
	return (m >> 12) & 15


static func m_flags(m: int) -> int:
	return (m >> 16) & 15


static func square_name(sq: int) -> String:
	return "abcdefgh"[sq % 8] + str(sq / 8 + 1)


static func square_from_name(s: String) -> int:
	return (s.unicode_at(1) - 49) * 8 + (s.unicode_at(0) - 97)


# ---------------------------------------------------------------- FEN

func load_fen(fen: String) -> void:
	var parts := fen.strip_edges().split(" ")
	board = PackedInt32Array()
	board.resize(64)
	var rank := 7
	var file := 0
	for ch in parts[0]:
		if ch == "/":
			rank -= 1
			file = 0
		elif ch.is_valid_int():
			file += int(ch)
		else:
			var kind := "pnbrqk".find(ch.to_lower()) + 1
			board[rank * 8 + file] = kind if ch == ch.to_upper() else -kind
			file += 1
	white_to_move = parts.size() < 2 or parts[1] == "w"
	castling = 0
	if parts.size() > 2:
		for i in 4:
			if parts[2].contains("KQkq"[i]):
				castling |= 1 << i
	ep_square = square_from_name(parts[3]) if parts.size() > 3 and parts[3] != "-" else -1
	halfmove = int(parts[4]) if parts.size() > 4 else 0
	fullmove = int(parts[5]) if parts.size() > 5 else 1
	history.clear()
	moves_san = PackedStringArray()
	_keys = {}
	_keys[position_key()] = 1


func to_fen() -> String:
	return "%s %d %d" % [position_key(), halfmove, fullmove]


## 局面键：FEN 去掉步数计数（三次重复判定用）。
func position_key() -> String:
	var rows := PackedStringArray()
	for rank in range(7, -1, -1):
		var row := ""
		var empty := 0
		for file in 8:
			var p := board[rank * 8 + file]
			if p == 0:
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			var ch := "pnbrqk"[absi(p) - 1]
			row += ch.to_upper() if p > 0 else ch
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var c := ""
	for i in 4:
		if castling & (1 << i):
			c += "KQkq"[i]
	return "%s %s %s %s" % ["/".join(rows), "w" if white_to_move else "b", c if c != "" else "-", square_name(ep_square) if ep_square >= 0 else "-"]


# ---------------------------------------------------------------- 攻击与走法生成

## sq 是否被 white 一方攻击。
func is_attacked(sq: int, by_white: bool) -> bool:
	var r := sq / 8
	var f := sq % 8
	var s := 1 if by_white else -1
	# 兵
	var pr := r - s
	if pr >= 0 and pr < 8:
		for df in [-1, 1]:
			var pf: int = f + df
			if pf >= 0 and pf < 8 and board[pr * 8 + pf] == s * PAWN:
				return true
	for st in KNIGHT_STEPS:
		var nr: int = r + st[1]
		var nf: int = f + st[0]
		if nr >= 0 and nr < 8 and nf >= 0 and nf < 8 and board[nr * 8 + nf] == s * KNIGHT:
			return true
	for st in KING_STEPS:
		var nr: int = r + st[1]
		var nf: int = f + st[0]
		if nr >= 0 and nr < 8 and nf >= 0 and nf < 8 and board[nr * 8 + nf] == s * KING:
			return true
	for d in BISHOP_DIRS:
		if _ray_hits(r, f, d, s * BISHOP, s * QUEEN):
			return true
	for d in ROOK_DIRS:
		if _ray_hits(r, f, d, s * ROOK, s * QUEEN):
			return true
	return false


func _ray_hits(r: int, f: int, d: Array, a: int, b: int) -> bool:
	var nr: int = r + d[1]
	var nf: int = f + d[0]
	while nr >= 0 and nr < 8 and nf >= 0 and nf < 8:
		var p := board[nr * 8 + nf]
		if p != 0:
			return p == a or p == b
		nr += d[1]
		nf += d[0]
	return false


func king_square(white: bool) -> int:
	return board.find(KING if white else -KING)


func in_check(white := white_to_move) -> bool:
	var k := king_square(white)
	return k >= 0 and is_attacked(k, not white)


## 伪合法走法（不检查走后自己的王是否被将）。
func pseudo_moves() -> PackedInt32Array:
	var out := PackedInt32Array()
	var s := 1 if white_to_move else -1
	for sq in 64:
		var p := board[sq]
		if p == 0 or (p > 0) != white_to_move:
			continue
		var r := sq / 8
		var f := sq % 8
		match absi(p):
			PAWN:
				var dir := s
				var one := sq + 8 * dir
				var last_rank := 7 if white_to_move else 0
				var start_rank := 1 if white_to_move else 6
				if one >= 0 and one < 64 and board[one] == 0:
					_add_pawn(out, sq, one, 0, last_rank)
					var two := sq + 16 * dir
					if r == start_rank and board[two] == 0:
						out.append(encode(sq, two, 0, F_DOUBLE))
				for df in [-1, 1]:
					var nf: int = f + df
					var nr: int = r + dir
					if nf < 0 or nf > 7 or nr < 0 or nr > 7:
						continue
					var t: int = nr * 8 + nf
					if board[t] != 0 and (board[t] > 0) != white_to_move:
						_add_pawn(out, sq, t, F_CAPTURE, last_rank)
					elif t == ep_square:
						out.append(encode(sq, t, 0, F_CAPTURE | F_EP))
			KNIGHT:
				_add_steps(out, sq, r, f, KNIGHT_STEPS)
			BISHOP:
				_add_rays(out, sq, r, f, BISHOP_DIRS)
			ROOK:
				_add_rays(out, sq, r, f, ROOK_DIRS)
			QUEEN:
				_add_rays(out, sq, r, f, BISHOP_DIRS)
				_add_rays(out, sq, r, f, ROOK_DIRS)
			KING:
				_add_steps(out, sq, r, f, KING_STEPS)
				_add_castles(out, sq)
	return out


func _add_pawn(out: PackedInt32Array, from: int, to: int, flags: int, last_rank: int) -> void:
	if to / 8 == last_rank:
		for promo in [QUEEN, ROOK, BISHOP, KNIGHT]:
			out.append(encode(from, to, promo, flags))
	else:
		out.append(encode(from, to, 0, flags))


func _add_steps(out: PackedInt32Array, sq: int, r: int, f: int, steps: Array) -> void:
	for st in steps:
		var nr: int = r + st[1]
		var nf: int = f + st[0]
		if nr < 0 or nr > 7 or nf < 0 or nf > 7:
			continue
		var t: int = nr * 8 + nf
		var q := board[t]
		if q == 0:
			out.append(encode(sq, t))
		elif (q > 0) != white_to_move:
			out.append(encode(sq, t, 0, F_CAPTURE))


func _add_rays(out: PackedInt32Array, sq: int, r: int, f: int, dirs: Array) -> void:
	for d in dirs:
		var nr: int = r + d[1]
		var nf: int = f + d[0]
		while nr >= 0 and nr < 8 and nf >= 0 and nf < 8:
			var t: int = nr * 8 + nf
			var q := board[t]
			if q == 0:
				out.append(encode(sq, t))
			else:
				if (q > 0) != white_to_move:
					out.append(encode(sq, t, 0, F_CAPTURE))
				break
			nr += d[1]
			nf += d[0]


func _add_castles(out: PackedInt32Array, sq: int) -> void:
	var white := white_to_move
	var home := 4 if white else 60
	if sq != home or in_check(white):
		return
	var short_bit := 1 if white else 4
	var long_bit := 2 if white else 8
	if castling & short_bit and board[home + 1] == 0 and board[home + 2] == 0 \
			and not is_attacked(home + 1, not white) and not is_attacked(home + 2, not white):
		out.append(encode(home, home + 2, 0, F_CASTLE))
	if castling & long_bit and board[home - 1] == 0 and board[home - 2] == 0 and board[home - 3] == 0 \
			and not is_attacked(home - 1, not white) and not is_attacked(home - 2, not white):
		out.append(encode(home, home - 2, 0, F_CASTLE))


## 合法走法。
func legal_moves() -> PackedInt32Array:
	var out := PackedInt32Array()
	var mover := white_to_move
	for m in pseudo_moves():
		_make(m)
		if not in_check(mover):
			out.append(m)
		_unmake()
	return out


func legal_moves_from(sq: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for m in legal_moves():
		if m_from(m) == sq:
			out.append(m)
	return out


# ---------------------------------------------------------------- 走子与悔棋

## 内部走子（不记谱、不记重复）：保存恢复信息到 history。
func _make(m: int) -> void:
	var from := m_from(m)
	var to := m_to(m)
	var flags := m_flags(m)
	var piece := board[from]
	var captured := board[to]
	var cap_sq := to
	if flags & F_EP:
		cap_sq = to - (8 if piece > 0 else -8)
		captured = board[cap_sq]
		board[cap_sq] = 0
	history.append({"m": m, "piece": piece, "captured": captured, "cap_sq": cap_sq, "castling": castling, "ep": ep_square, "half": halfmove, "full": fullmove})
	board[to] = piece
	board[from] = 0
	if m_promo(m) != 0:
		board[to] = m_promo(m) * (1 if piece > 0 else -1)
	if flags & F_CASTLE:
		if to > from:
			board[from + 1] = board[from + 3]
			board[from + 3] = 0
		else:
			board[from - 1] = board[from - 4]
			board[from - 4] = 0
	# 易位权：王动了、车动了或车被吃
	for sq in [from, to]:
		match sq:
			4: castling &= ~3
			60: castling &= ~12
			0: castling &= ~2
			7: castling &= ~1
			56: castling &= ~8
			63: castling &= ~4
	ep_square = (from + to) / 2 if flags & F_DOUBLE else -1
	halfmove = 0 if absi(piece) == PAWN or captured != 0 else halfmove + 1
	if not white_to_move:
		fullmove += 1
	white_to_move = not white_to_move


func _unmake() -> void:
	var h: Dictionary = history.pop_back()
	var m: int = h["m"]
	var from := m_from(m)
	var to := m_to(m)
	var flags := m_flags(m)
	board[from] = h["piece"]
	board[to] = 0
	board[h["cap_sq"]] = h["captured"]
	if flags & F_CASTLE:
		if to > from:
			board[from + 3] = board[from + 1]
			board[from + 1] = 0
		else:
			board[from - 4] = board[from - 1]
			board[from - 1] = 0
	castling = h["castling"]
	ep_square = h["ep"]
	halfmove = h["half"]
	fullmove = h["full"]
	white_to_move = not white_to_move


## 对外的走子：必须是合法走法；记谱、记重复。返回 SAN；不合法返回 ""。
func play(m: int) -> String:
	if not m in legal_moves():
		return ""
	var san := _san(m)
	_make(m)
	if in_check():
		san += "#" if legal_moves().is_empty() else "+"
	moves_san.append(san)
	var k := position_key()
	_keys[k] = int(_keys.get(k, 0)) + 1
	return san


## 按起止格走（升变默认后）；找不到返回 ""。
func play_squares(from: int, to: int, promo := QUEEN) -> String:
	for m in legal_moves_from(from):
		if m_to(m) == to and (m_promo(m) == 0 or m_promo(m) == promo):
			return play(m)
	return ""


func undo() -> bool:
	if history.is_empty() or moves_san.is_empty():
		return false
	var k := position_key()
	_keys[k] = int(_keys.get(k, 1)) - 1
	_unmake()
	moves_san.remove_at(moves_san.size() - 1)
	return true


func _san(m: int) -> String:
	var from := m_from(m)
	var to := m_to(m)
	var piece := absi(board[from])
	if m_flags(m) & F_CASTLE:
		return "O-O" if to > from else "O-O-O"
	var s := ""
	if piece == PAWN:
		if m_flags(m) & F_CAPTURE:
			s = "abcdefgh"[from % 8] + "x"
		s += square_name(to)
		if m_promo(m) != 0:
			s += "=" + LETTERS[m_promo(m)]
		return s
	s = LETTERS[piece]
	# 消歧义：同种棋子也能走到同一格
	var same_file := false
	var same_rank := false
	var ambiguous := false
	for o in legal_moves():
		if m_to(o) == to and m_from(o) != from and absi(board[m_from(o)]) == piece:
			ambiguous = true
			if m_from(o) % 8 == from % 8:
				same_file = true
			if m_from(o) / 8 == from / 8:
				same_rank = true
	if ambiguous:
		if not same_file:
			s += "abcdefgh"[from % 8]
		elif not same_rank:
			s += str(from / 8 + 1)
		else:
			s += square_name(from)
	if m_flags(m) & F_CAPTURE:
		s += "x"
	return s + square_name(to)


# ---------------------------------------------------------------- 结局

## "" 进行中；"checkmate_white"（白胜）/"checkmate_black"；"stalemate"、"fifty"、"repetition"、"material"（和）。
func result() -> String:
	if legal_moves().is_empty():
		if in_check():
			return "checkmate_black" if white_to_move else "checkmate_white"
		return "stalemate"
	if halfmove >= 100:
		return "fifty"
	if int(_keys.get(position_key(), 0)) >= 3:
		return "repetition"
	if _insufficient_material():
		return "material"
	return ""


func _insufficient_material() -> bool:
	var minors := 0
	for p in board:
		var a := absi(p)
		if a == PAWN or a == ROOK or a == QUEEN:
			return false
		if a == KNIGHT or a == BISHOP:
			minors += 1
	return minors <= 1


## perft：从当前局面走 depth 层的合法局面数（验证走法生成）。
func perft(depth: int) -> int:
	if depth == 0:
		return 1
	var n := 0
	var mover := white_to_move
	for m in pseudo_moves():
		_make(m)
		if not in_check(mover):
			n += 1 if depth == 1 else perft(depth - 1)
		_unmake()
	return n


func copy() -> ChessGame:
	var g := ChessGame.new(to_fen())
	return g
