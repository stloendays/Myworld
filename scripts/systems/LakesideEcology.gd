class_name LakesideEcology
extends RefCounted
## Deterministic, inspectable data-driven prototype. No independent weather clock.
const PATH := "res://data/world/lakeside_ecology.json"
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if result is Dictionary:
			_data = result
		else:
			push_error("LakesideEcology: invalid rules JSON")
	return _data


static func within_window(minutes: float, start: float, end: float) -> bool:
	var m := fposmod(minutes, 1440.0)
	if start <= end:
		return m >= start and m < end
	return m >= start or m < end


static func fish_candidates(spot_id: String, season: String, minutes: float, weather: String) -> Array:
	var out: Array = []
	for item in data().get("fish", []):
		var f: Dictionary = item
		if not (f.get("spots", []) as Array).has(spot_id):
			continue
		if not (f.get("seasons", []) as Array).has(season):
			continue
		if f.has("weather") and not (f["weather"] as Array).has(weather):
			continue
		if not within_window(minutes, float(f.get("start", 0)), float(f.get("end", 1440))):
			continue
		out.append(f)
	return out


static func draw_fish(spot_id: String, day: int, attempt: int, season: String, minutes: float, weather: String) -> Dictionary:
	var candidates := fish_candidates(spot_id, season, minutes, weather)
	if candidates.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash([spot_id, day, attempt, season, int(minutes / 60.0)]))
	var total := 0
	for item in candidates:
		total += maxi(0, int(item.get("weight", 0)))
	if total == 0:
		return {}
	var draw := rng.randi_range(1, total)
	for item in candidates:
		draw -= maxi(0, int(item.get("weight", 0)))
		if draw <= 0:
			return item
	return {}


static func cat_activity(minutes: float, rain: float, snow: float) -> String:
	var cat: Dictionary = data().get("cat", {})
	if rain >= float(cat.get("rain_threshold", 0.12)) or snow > 0.1:
		return "shelter"
	if within_window(minutes, float(cat.get("sleep_from", 1200)), float(cat.get("sleep_to", 420))):
		return "sleep"
	if within_window(minutes, 480, 1020):
		return "patrol"
	return "porch"


static func event_active(event_id: String, day: int, minutes: float, weather: String, rain_recent: float) -> bool:
	for item in data().get("events", []):
		var e: Dictionary = item
		if str(e.get("id", "")) != event_id:
			continue
		if event_id == "meteor_stardust":
			if not within_window(minutes, float(e.get("start", 0)), float(e.get("end", 1440))):
				return false
			return _periodic("meteor_shower", day - 1)
		if not _periodic(event_id, day):
			return false
		if not within_window(minutes, float(e.get("start", 0)), float(e.get("end", 1440))):
			return false
		if e.has("weather") and not (e["weather"] as Array).has(weather):
			return false
		if rain_recent < float(e.get("min_rain_recent", 0.0)):
			return false
		return true
	return false


static func _periodic(event_id: String, day: int) -> bool:
	if day < 1:
		return false
	for item in data().get("events", []):
		var e: Dictionary = item
		if str(e.get("id", "")) == event_id:
			var cycle := maxi(1, int(e.get("interval_days", 1)))
			return posmod(day + int(e.get("offset", 0)), cycle) == 0
	return false
