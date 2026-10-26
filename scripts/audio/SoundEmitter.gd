class_name SoundEmitter
extends AudioStreamPlayer3D
## 一直在响的定位声源（炉火、篝火、瀑布、仙境的铃声……）：声音、总线、衰减距离来自 sounds.json。
## set_on() 让它慢慢响起来或慢慢灭掉（炉火熄灭时先减弱、再停），不会一下子断掉。

const FADE_DB_PER_S := 30.0

var sound_id := ""
var on := true
var _base_db := 0.0


## 建一个声源：id 是 sounds.json 里的循环声音；start_on = false 时先不响。
static func create(id: String, start_on := true) -> SoundEmitter:
	var e := SoundEmitter.new()
	e.name = "Sound_" + id
	e.sound_id = id
	e.on = start_on
	return e


func _ready() -> void:
	add_to_group("sound_emitters")
	var d := SoundBank.info(sound_id)
	stream = SoundBank.stream(sound_id)
	bus = SoundBank.bus(sound_id)
	_base_db = SoundBank.volume_db(sound_id)
	unit_size = float(d.get("unit_size", 3.0))
	max_distance = float(d.get("max_distance", 30.0))
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	panning_strength = 1.0
	volume_db = _base_db if on else -60.0
	if on and stream != null:
		play(randf() * stream.get_length())


## 慢慢打开 / 关掉（instant 用于读档）。
func set_on(value: bool, instant := false) -> void:
	on = value
	if instant:
		volume_db = _base_db if on else -60.0
		if on and not playing and stream != null:
			play(randf() * stream.get_length())
		elif not on:
			stop()


func _process(delta: float) -> void:
	var target := _base_db if on else -60.0
	if absf(volume_db - target) > 0.01:
		volume_db = move_toward(volume_db, target, FADE_DB_PER_S * delta)
		if on and not playing and stream != null:
			play(randf() * stream.get_length())
	elif not on and playing:
		stop()
