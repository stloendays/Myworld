class_name FaunaData
extends RefCounted
## 小动物数据（data/animals/species.json）与“现在该不该出来”的规则。
## 规则只读 WorldState（时间、季节、天气），与 NPC 预留一致：动物观察环境，不自己另算天气。

const PATH := "res://data/animals/species.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("FaunaData: 无法解析 %s" % PATH)
	return _data


static func species(id: String) -> Dictionary:
	return data().get("species", {}).get(id, {})


static func is_night() -> bool:
	var profile := ClimateData.season_profile(WorldState.season_id)
	return EnvironmentDirector.sun_angles(profile, WorldState.time_minutes).x < -3.0


## active 规则：seasons / day / night / max_rain / max_snow / max_wind。缺省即不限制。
static func is_active(rules: Dictionary) -> bool:
	if rules.is_empty():
		return true
	if rules.has("seasons") and not (rules["seasons"] as Array).has(String(WorldState.season_id)):
		return false
	var night := is_night()
	if night and not bool(rules.get("night", true)):
		return false
	if not night and not bool(rules.get("day", true)):
		return false
	var w := WeatherController.blended()
	if float(w["rain"]) > float(rules.get("max_rain", 1.0)):
		return false
	if float(w["snow"]) > float(rules.get("max_snow", 1.0)):
		return false
	if float(w["wind"]) > float(rules.get("max_wind", 1.0)):
		return false
	return true


## 合并季节色与随机变体，得到某只动物的配色。
static func palette(def: Dictionary, variant: int) -> Dictionary:
	var p: Dictionary = (def.get("palette", {}) as Dictionary).duplicate()
	var seasonal: Dictionary = def.get("seasonal_palette", {}).get(String(WorldState.season_id), {})
	for k in seasonal:
		p[k] = seasonal[k]
	var variants: Array = def.get("variants", [])
	if not variants.is_empty():
		var v: Dictionary = variants[variant % variants.size()]
		for k in v:
			p[k] = v[k]
	return p
