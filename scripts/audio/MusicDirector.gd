class_name MusicDirector
extends Node
## 背景音乐（规格 07：可选的极轻背景音乐；AudioDirector 的子节点 Sound.music）。乐曲不是录好的，而是按 data/audio/music.json 的
## 曲风现场生成：每个世界、湖畔的白天 / 黄昏 / 夜里 / 雨天 / 冬天各有调、音阶、速度和乐器；一首十几二十小节——长音铺底、低音、
## 在五声音阶上游走的旋律、每四小节留一口气——放完安静一两分钟再来（像《我的世界》那样，音乐只是偶尔出现）。
## 换了世界或天变了，正在放的那首淡出，换新的曲风。过场时 play_theme() 放写好的配乐，结束时 end_theme() 淡出。

const DATA_PATH := "res://data/audio/music.json"
const VOICES := 16

var mood := ""            ## 现在的曲风（自动检查读）
var playing_piece := false
var theme := ""           ## 正在放的过场配乐
var notes_played := 0

var _data: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _tweens: Array[Tween] = []
var _voice_i := 0
var _beat := 0
var _beat_t := 0.0
var _bars_left := 0
var _gap := 30.0
var _deg := 4
var _theme_notes: Array = []
var _theme_beat := 0.75
var _theme_t := 0.0
var _theme_i := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_data = parsed if parsed is Dictionary else {}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"MUSIC"
		add_child(p)
		_voices.append(p)
		_tweens.append(null)
	var fg: Array = _data.get("first_gap", [25, 50])
	_gap = _rng.randf_range(float(fg[0]), float(fg[1]))


## 现在该用哪种曲风：其他世界各一种；湖畔按天气、昼夜、季节、是不是黄昏。没有世界（加载中）时为空。
func current_mood() -> String:
	if get_tree().get_first_node_in_group("world_root") == null:
		return ""
	match WorldTravel.current_world:
		"world_02":
			return "cloudsea"
		"world_03":
			return "dunes"
		"world_04":
			return "atlantis"
	var env := get_tree().get_first_node_in_group("environment_director") as EnvironmentDirector
	var night := env.night if env != null else 0.0
	if float(WeatherController.blended().get("rain", 0.0)) > 0.4:
		return "lake_rain"
	if night > 0.6:
		return "lake_night"
	if WorldState.season_id == &"WINTER":
		return "lake_winter"
	if env != null and env.sun_elevation < 14.0:
		return "lake_dusk"
	return "lake_day"


func moods() -> Dictionary:
	return _data.get("moods", {})


func _process(delta: float) -> void:
	if theme != "":
		_theme_step(delta)
		return
	var m := current_mood()
	if m != mood:
		if playing_piece:
			fade_all(3.0)
			playing_piece = false
			_gap = _rng.randf_range(8.0, 16.0)
		mood = m
	if mood == "" or not moods().has(mood):
		return
	if not playing_piece:
		_gap -= delta
		if _gap <= 0.0:
			start_piece()
		return
	_beat_t -= delta
	if _beat_t > 0.0:
		return
	var md: Dictionary = moods()[mood]
	_beat_t += float(md["beat"])
	_play_beat(md)
	_beat += 1
	if _beat % 4 == 0:
		_bars_left -= 1
		if _bars_left <= 0:
			playing_piece = false
			var g: Array = _data.get("gap", [100, 220])
			_gap = _rng.randf_range(float(g[0]), float(g[1]))


## 马上开始一首（自动检查、过场以后用）。
func start_piece() -> void:
	var pb: Array = _data.get("piece_bars", [16, 28])
	_bars_left = _rng.randi_range(int(pb[0]), int(pb[1]))
	_beat = 0
	_beat_t = 0.0
	_deg = _rng.randi_range(3, 6)
	playing_piece = true


## 一拍：每两小节换和弦（长音铺根音和五度、低音），旋律在音阶上一步一两格地走，乐句最后三拍留空。
func _play_beat(md: Dictionary) -> void:
	var bar := _beat / 4
	var pos := _beat % 4
	var chords: Array = md["chords"]
	var chord := int(chords[(bar / 2) % chords.size()]) % 12
	var key := int(md["key"])
	var beat_s := float(md["beat"])
	if pos == 0 and bar % 2 == 0:
		if md.get("pad", false):
			note("pad", key - 12 + chord, 0.5, beat_s * 8.0)
			note("pad", key - 12 + chord + 7, 0.32, beat_s * 8.0)
		if md.get("bass", false):
			note("bass", key - 24 + chord, 0.55)
	if _beat % 16 >= 13:
		return
	var chance := float(md["density"]) * (1.4 if pos == 0 else (0.7 if pos % 2 == 1 else 1.0))
	if _rng.randf() >= chance:
		return
	var scale: Array = md["scale"]
	var n := scale.size()
	_deg = clampi(_deg + [-2, -1, -1, 0, 1, 1, 2][_rng.randi() % 7], 0, n * 2)
	if pos == 0:
		# 小节头落在和弦音上（根音或五度），听起来更稳
		for k in n:
			if (int(scale[_deg % n]) - chord + 24) % 12 in [0, 7]:
				break
			_deg = clampi(_deg + (1 if _rng.randf() < 0.5 else -1), 0, n * 2)
	var midi := key + int(scale[_deg % n]) + 12 * (_deg / n)
	note(str(md["lead"]), midi, _rng.randf_range(0.45, 0.75))
	if _rng.randf() < 0.15 and _deg >= 2:
		var low := _deg - 2
		note(str(md["lead"]), key + int(scale[low % n]) + 12 * (low / n), 0.3)


## 放一个音：乐器的采样按音高换算 pitch_scale；长音（sustain）在 hold 秒后 1.5 秒淡出。
func note(inst: String, midi: int, velocity: float, hold := 0.0) -> void:
	var ins: Dictionary = (_data.get("instruments", {}) as Dictionary).get(inst, {})
	if ins.is_empty():
		return
	var sound := str(ins["sound"])
	var p := _voices[_voice_i]
	var old := _tweens[_voice_i]
	if old != null and old.is_valid():
		old.kill()
	p.stop()
	p.stream = SoundBank.stream(sound)
	p.pitch_scale = pow(2.0, float(midi - int(ins["root"])) / 12.0)
	p.volume_db = SoundBank.volume_db(sound) + linear_to_db(maxf(velocity, 0.01))
	p.play()
	if ins.get("sustain", false):
		var tw := p.create_tween()
		tw.tween_interval(maxf(hold, 0.5))
		tw.tween_property(p, "volume_db", -60.0, 1.5)
		tw.tween_callback(p.stop)
		_tweens[_voice_i] = tw
	else:
		_tweens[_voice_i] = null
	_voice_i = (_voice_i + 1) % _voices.size()
	notes_played += 1


## 所有正在响的音在 seconds 秒里淡出。
func fade_all(seconds: float) -> void:
	for i in _voices.size():
		var p := _voices[i]
		if not p.playing:
			continue
		var old := _tweens[i]
		if old != null and old.is_valid():
			old.kill()
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -60.0, seconds)
		tw.tween_callback(p.stop)
		_tweens[i] = tw


# ---------------------------------------------------------------- 过场配乐

func play_theme(id: String) -> void:
	var t: Dictionary = (_data.get("themes", {}) as Dictionary).get(id, {})
	if t.is_empty():
		return
	fade_all(1.0)
	playing_piece = false
	theme = id
	_theme_notes = t["notes"]
	_theme_beat = float(t.get("beat", 0.75))
	_theme_t = 0.0
	_theme_i = 0


func end_theme() -> void:
	if theme == "":
		return
	theme = ""
	fade_all(2.5)
	_gap = _rng.randf_range(60.0, 140.0)


func _theme_step(delta: float) -> void:
	_theme_t += delta
	while _theme_i < _theme_notes.size():
		var nt: Array = _theme_notes[_theme_i]
		if float(nt[0]) * _theme_beat > _theme_t:
			break
		note(str(nt[1]), int(nt[2]), float(nt[4]), float(nt[3]) * _theme_beat)
		_theme_i += 1
