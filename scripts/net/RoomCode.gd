class_name RoomCode
extends RefCounted
## 房间号：把房主的 IPv4 地址和端口编码成好念、好发的短码（Crockford Base32，不含 I L O U）。
##   默认端口：7 位，写成 XXX-XXXX（32 位地址 + 3 位校验）；
##   其他端口：10 位，写成 XXXXX-XXXXX（32 位地址 + 16 位端口 + 2 位校验）。
## 校验位能发现大多数抄错的码。解码也接受直接写的地址：192.168.1.5、192.168.1.5:24567、主机名:端口。
## 房间号只是地址的另一种写法：能不能连上仍取决于网络（局域网、Tailscale、或房主路由器打开了端口）。

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const DEFAULT_PORT := 24567


static func encode(ip: String, port := DEFAULT_PORT) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var value := 0
	for p in parts:
		if not p.is_valid_int() or p.to_int() < 0 or p.to_int() > 255:
			return ""
		value = (value << 8) | p.to_int()
	if port == DEFAULT_PORT:
		var v := (value << 3) | _checksum(value, 8)
		var s := _to_base32(v, 7)
		return s.substr(0, 3) + "-" + s.substr(3)
	var w := (((value << 16) | (port & 0xFFFF)) << 2) | _checksum(value ^ port, 4)
	var t := _to_base32(w, 10)
	return t.substr(0, 5) + "-" + t.substr(5)


## 返回 {"ok": bool, "host": String, "port": int, "error": String}。error 是可翻译的中文原文。
static func decode(text: String) -> Dictionary:
	var raw := text.strip_edges()
	if raw.is_empty():
		return _fail("请输入房间号")
	if raw.contains(".") or raw.contains(":"):
		return _parse_address(raw)
	var s := ""
	for ch in raw.to_upper():
		if ch == "-" or ch == " ":
			continue
		ch = {"O": "0", "I": "1", "L": "1", "U": "V"}.get(ch, ch)
		if ALPHABET.find(ch) < 0:
			return _fail("房间号里有无效的字符")
		s += ch
	if s.length() == 7:
		var v := _from_base32(s)
		var ip_value := v >> 3
		if (v & 7) != _checksum(ip_value, 8):
			return _fail("房间号不对，请检查有没有抄错")
		return {"ok": true, "host": _ip_string(ip_value), "port": DEFAULT_PORT, "error": ""}
	if s.length() == 10:
		var w := _from_base32(s)
		var port := (w >> 2) & 0xFFFF
		var ip_value2 := w >> 18
		if (w & 3) != _checksum(ip_value2 ^ port, 4) or port == 0:
			return _fail("房间号不对，请检查有没有抄错")
		return {"ok": true, "host": _ip_string(ip_value2), "port": port, "error": ""}
	return _fail("房间号应为 7 位或 10 位")


## 地址类别：lan（私有网段）、vpn（100.64/10，Tailscale 等）、loopback、public、invalid。
static func classify(ip: String) -> String:
	var p := ip.split(".")
	if p.size() != 4:
		return "invalid"
	var a := p[0].to_int()
	var b := p[1].to_int()
	if a == 127:
		return "loopback"
	if a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168):
		return "lan"
	if a == 100 and b >= 64 and b <= 127:
		return "vpn"
	if a == 169 and b == 254 or a == 0 or a >= 224:
		return "invalid"
	return "public"


static func _parse_address(raw: String) -> Dictionary:
	var host := raw
	var port := DEFAULT_PORT
	var colon := raw.rfind(":")
	if colon > 0:
		host = raw.substr(0, colon)
		var p := raw.substr(colon + 1)
		if not p.is_valid_int() or p.to_int() < 1 or p.to_int() > 65535:
			return _fail("端口应为 1–65535")
		port = p.to_int()
	if host.is_empty():
		return _fail("请输入房间号")
	return {"ok": true, "host": host, "port": port, "error": ""}


static func _checksum(value: int, modulo: int) -> int:
	var s := 0
	var v := value
	for i in 6:
		s += (v & 0xFF) * (i + 3)
		v >>= 8
	return s % modulo


static func _to_base32(value: int, length: int) -> String:
	var out := ""
	for i in length:
		out = ALPHABET[value & 31] + out
		value >>= 5
	return out


static func _from_base32(s: String) -> int:
	var v := 0
	for ch in s:
		v = (v << 5) | ALPHABET.find(ch)
	return v


static func _ip_string(v: int) -> String:
	return "%d.%d.%d.%d" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "host": "", "port": 0, "error": message}
