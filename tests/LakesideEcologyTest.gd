extends Node
## Lightweight rules-only integration tests; no rendering is required.

func _ready() -> void:
	var failures: Array[String] = []
	_expect(LakesideEcology.within_window(1380, 1140, 300), "wrap night", failures)
	_expect(LakesideEcology.within_window(120, 1140, 300), "wrap predawn", failures)
	_expect(not LakesideEcology.within_window(600, 1140, 300), "wrap daytime excludes", failures)
	_expect(LakesideEcology.within_window(0, 0, 1440), "all-day fish", failures)
	_expect(not LakesideEcology.within_window(1440, 360, 1200), "midday window excludes midnight", failures)
	var night: Array = LakesideEcology.fish_candidates("north_bay", "WINTER", 1320, "CLEAR")
	_expect(night.size() == 2, "winter nocturnal north bay perch+trout", failures)
	var daytime: Array = LakesideEcology.fish_candidates("dock", "SUMMER", 720, "CLEAR")
	_expect(daytime.size() == 2, "summer daytime dock perch+carp", failures)
	_expect(LakesideEcology.cat_activity(1380, 0, 0) == "sleep", "cat sleeps at night", failures)
	_expect(LakesideEcology.cat_activity(700, 0.2, 0) == "shelter", "cat shelters in rain", failures)
	_expect(LakesideEcology.cat_activity(700, 0, 0) == "patrol", "cat patrols sunny noon", failures)
	_expect(LakesideEcology.event_active("rain_lantern", 3, 1320, "CLEAR", 0.5), "repeatable rain lantern", failures)
	_expect(not LakesideEcology.event_active("rain_lantern", 3, 1320, "HEAVY_RAIN", 0.5), "not during rain", failures)
	_expect(not LakesideEcology.event_active("rain_lantern", 3, 1320, "CLEAR", 0.0), "requires rain afterglow", failures)
	_expect(LakesideEcology.event_active("meteor_shower", 3, 1320, "CLEAR", 0.0), "meteor night", failures)
	_expect(LakesideEcology.event_active("meteor_stardust", 4, 720, "CLEAR", 0.0), "stardust next day", failures)
	_expect(not LakesideEcology.event_active("meteor_stardust", 4, 1320, "CLEAR", 0.0), "stardust daytime only", failures)
	_expect(LakesideEcology.event_active("guide_fox", 3, 1080, "CLEAR", 0.0), "guide fox periodic window", failures)
	if failures.is_empty():
		print("=== Lakeside ecology tests: 17 passed, 0 failed ===")
	else:
		for f in failures:
			push_error("Lakeside ecology test failed: " + f)
		print("=== Lakeside ecology tests: %d failed ===" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String, failures: Array[String]) -> void:
	if not ok:
		failures.append(message)
