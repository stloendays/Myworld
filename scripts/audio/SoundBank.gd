class_name SoundBank
extends RefCounted
## 声音表（data/audio/sounds.json）：每个声音 id → 文件（assets/audio/*.wav，全部由 devtools/audio/synth.mjs 合成，原创 CC0）、
## 总线、音量、音高浮动、是否循环、3D 衰减。读进来的 AudioStreamWAV 按 id 缓存；循环音在这里设循环点（文件里的 smpl 块是同一组点）。

const DATA_PATH := "res://data/audio/sounds.json"
const DIR := "res://assets/audio/"

static var _data: Dictionary = {}
static var _streams: Dictionary = {}   ## 文件名 -> AudioStreamWAV
static var _rng := RandomNumberGenerator.new()


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = (parsed as Dictionary).get("sounds", {}) if parsed is Dictionary else {}
	return _data


static func has(id: String) -> bool:
	return data().has(id)


static func info(id: String) -> Dictionary:
	return data().get(id, {})


## 这个声音的全部文件（variants > 1 时是 file_1 … file_n）。
static func files(id: String) -> PackedStringArray:
	var d := info(id)
	var out := PackedStringArray()
	var f := str(d.get("file", id))
	var n := int(d.get("variants", 1))
	if n <= 1:
		out.append(f)
	else:
		for i in n:
			out.append("%s_%d" % [f, i + 1])
	return out


## 一个声音的音频流；有多个变体时随机挑一个。
static func stream(id: String) -> AudioStream:
	var list := files(id)
	if list.is_empty() or not has(id):
		return null
	var d := info(id)
	return _load(list[_rng.randi() % list.size()], bool(d.get("loop", false)), float(d.get("loop_begin", 0.0)))


static func _load(file: String, loop: bool, loop_begin: float) -> AudioStreamWAV:
	if _streams.has(file):
		return _streams[file]
	var s := load(DIR + file + ".wav") as AudioStreamWAV
	if s != null and loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = int(loop_begin * s.mix_rate)
		s.loop_end = int(round(s.get_length() * s.mix_rate))
	_streams[file] = s
	return s


static func bus(id: String) -> StringName:
	return StringName(info(id).get("bus", "Master"))


static func volume_db(id: String) -> float:
	return float(info(id).get("db", 0.0))


## 每次播放的音高：1 ± pitch（脚步、鸟叫每声都不一样）。
static func pitch(id: String) -> float:
	var p := float(info(id).get("pitch", 0.0))
	return 1.0 + _rng.randf_range(-p, p)
