extends Node
## 小玩法的规则与记录（Autoload）：钓鱼、打水漂、寻宝、炉火烹饪、计时挑战、成就。
## 状态只写在 WorldState（存档 v5：achievements、records、catches、pantry、treasures，加上 flags），这里负责：
##   · 读数据：data/play/fish.json（鱼、菜、效果）、treasure.json（埋宝候选点）、challenges.json（挑战路线）、achievements.json；
##   · 能不能玩（blocked）：本局规则关掉了、或者联机做客（世界是房主的，访客的记录不存）时给出原因；
##   · 记一条鱼、做一道菜、吃了以后的效果（mult：体力恢复、游速、氧气消耗的倍率，有时限）、宝箱、挑战成绩与奖牌；
##   · 每秒检查一次成就，满足就解锁、提示、存档。
## 世界里的操作（甩竿、扔石头、挖、挑战的金环）在 PlayActivities；铁锅在 CookPot / CookingPanel。

signal changed   ## 记录有变化（收藏柜、旅行日志刷新用）

const FEATURE_NAMES := {"fishing": "钓鱼", "skipping": "打水漂", "treasure": "寻宝", "cooking": "烹饪", "challenges": "计时挑战", "achievements": "成就"}
const MEDALS := ["gold", "silver", "bronze"]
const MEDAL_NAMES := {"gold": "金牌", "silver": "银牌", "bronze": "铜牌", "": "完成"}

var fish_data: Dictionary = {}
var treasure_data: Dictionary = {}
var course_data: Dictionary = {}
var achievement_data: Dictionary = {}
var buffs: Dictionary = {}       ## buff id -> 结束时刻（引擎毫秒；不存档）

var _timer := 1.0


func _ready() -> void:
	fish_data = _load("res://data/play/fish.json")
	treasure_data = _load("res://data/play/treasure.json")
	course_data = _load("res://data/play/challenges.json")
	achievement_data = _load("res://data/play/achievements.json")


static func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	_expire_buffs()
	if get_tree().get_first_node_in_group("local_player") != null:
		check_achievements()


## 能不能玩某个活动：空字符串 = 可以，否则是给玩家看的原因。
func blocked(feature: String) -> String:
	var name_ := tr(str(FEATURE_NAMES.get(feature, feature)))
	if not GameRules.flag(feature):
		return tr("这一局没有开启%s（新建游戏页的「玩法活动」）") % name_
	if Net.is_client():
		return tr("联机做客时不能%s（这是房主的世界，记录不会保存）") % name_
	return ""


static func text(d: Dictionary, key: String) -> String:
	return QuestLog.text(d, key)


# ---------------------------------------------------------------- 钓鱼

func fish_list() -> Array:
	return fish_data.get("fish", [])


func fish(id: String) -> Dictionary:
	for f: Dictionary in fish_list():
		if str(f["id"]) == id:
			return f
	return {}


## 在某片水域按权重挑一条鱼和它的长度。
func roll_fish(water: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool := fish_list().filter(func(f: Dictionary) -> bool: return water in (f["waters"] as Array))
	if pool.is_empty():
		return {}
	var total := 0.0
	for f: Dictionary in pool:
		total += float(f["weight"])
	var r := rng.randf() * total
	var pick: Dictionary = pool[-1]
	for f: Dictionary in pool:
		r -= float(f["weight"])
		if r <= 0.0:
			pick = f
			break
	var sz: Array = pick["size"]
	var cm := snappedf(lerpf(float(sz[0]), float(sz[1]), pow(rng.randf(), 1.6)), 0.5)
	return {"id": str(pick["id"]), "cm": cm}


## 记一条钓到的鱼：图鉴（条数、最大尺寸）+ 鱼篓（做菜用）。返回是不是新的一种。
func record_catch(id: String, cm: float) -> bool:
	var c: Dictionary = WorldState.catches.get(id, {"count": 0, "best_cm": 0.0})
	var first := int(c["count"]) == 0
	c["count"] = int(c["count"]) + 1
	c["best_cm"] = maxf(float(c["best_cm"]), cm)
	WorldState.catches[id] = c
	WorldState.pantry["fish:" + id] = int(WorldState.pantry.get("fish:" + id, 0)) + 1
	_changed()
	return first


func fish_total() -> int:
	var n := 0
	for id in WorldState.catches:
		n += int(WorldState.catches[id]["count"])
	return n


func fish_in_pantry() -> Dictionary:
	var out := {}
	for k: String in WorldState.pantry:
		if k.begins_with("fish:") and int(WorldState.pantry[k]) > 0:
			out[k.substr(5)] = int(WorldState.pantry[k])
	return out


# ---------------------------------------------------------------- 烹饪

func recipes() -> Array:
	return fish_data.get("recipes", [])


func recipe(id: String) -> Dictionary:
	for r: Dictionary in recipes():
		if str(r["id"]) == id:
			return r
	return {}


## 做不了的原因（空 = 可以做）。
func cook_problem(id: String) -> String:
	var r := recipe(id)
	if r.is_empty():
		return "?"
	var have := fish_in_pantry()
	var total := 0
	for k in have:
		total += int(have[k])
	if total < int(r["fish"]):
		return tr("鱼不够：要 %d 条，鱼篓里有 %d 条") % [int(r["fish"]), total]
	if have.size() < int(r["kinds"]):
		return tr("要 %d 种不同的鱼，鱼篓里只有 %d 种") % [int(r["kinds"]), have.size()]
	return ""


## 做一道菜：从鱼篓里取鱼（先用不同的种类，再用最多的），做好就吃，得到效果。
func cook(id: String) -> bool:
	if cook_problem(id) != "":
		return false
	Sound.play("sizzle")
	var r := recipe(id)
	var need := int(r["fish"])
	var kinds := int(r["kinds"])
	var have := fish_in_pantry()
	var order := have.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return int(have[a]) > int(have[b]))
	var used := {}
	for k: String in order:
		if used.size() >= kinds:
			break
		used[k] = 1
	while _sum(used) < need:
		for k: String in order:
			if _sum(used) >= need:
				break
			if int(used.get(k, 0)) < int(have[k]):
				used[k] = int(used.get(k, 0)) + 1
	for k: String in used:
		WorldState.pantry["fish:" + k] = int(WorldState.pantry["fish:" + k]) - int(used[k])
	WorldState.pantry["dish:" + id] = int(WorldState.pantry.get("dish:" + id, 0)) + 1
	WorldState.records["dishes"] = int(WorldState.records.get("dishes", 0)) + 1
	WorldState.flags["cooked_" + id] = true
	apply_buff(str(r["buff"]))
	var b: Dictionary = (fish_data.get("buffs", {}) as Dictionary).get(str(r["buff"]), {})
	EventBus.toast_requested.emit(tr("做好了%s，吃得很香——%s：%s（%d 分钟）") % [text(r, "name"), text(b, "name"), text(b, "desc"), int(float(b.get("seconds", 300)) / 60.0)])
	_changed()
	return true


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func apply_buff(id: String) -> void:
	var b: Dictionary = (fish_data.get("buffs", {}) as Dictionary).get(id, {})
	if b.is_empty():
		return
	buffs[id] = Time.get_ticks_msec() + int(float(b.get("seconds", 300)) * 1000.0)


## 各种效果叠起来的倍率（swim_speed、stamina_regen、oxygen_drain）；没有效果时为 1。
func mult(key: String) -> float:
	var m := 1.0
	if buffs.is_empty():
		return m
	var now := Time.get_ticks_msec()
	for id: String in buffs:
		if int(buffs[id]) > now:
			var b: Dictionary = (fish_data.get("buffs", {}) as Dictionary).get(id, {})
			m *= float((b.get("mult", {}) as Dictionary).get(key, 1.0))
	return m


## 还在生效的效果 [{id, name, seconds_left}]。
func active_buffs() -> Array:
	var out := []
	var now := Time.get_ticks_msec()
	for id: String in buffs:
		if int(buffs[id]) > now:
			var b: Dictionary = (fish_data.get("buffs", {}) as Dictionary).get(id, {})
			out.append({"id": id, "name": text(b, "name"), "seconds_left": (int(buffs[id]) - now) / 1000})
	return out


func _expire_buffs() -> void:
	var now := Time.get_ticks_msec()
	for id: String in buffs.keys():
		if int(buffs[id]) <= now:
			buffs.erase(id)


# ---------------------------------------------------------------- 寻宝

## 本局的种子（新建游戏页的世界种子；0 = 用世界自带的）。
func seed_value() -> int:
	var s := GameRules.world_seed()
	return s if s != 0 else WorldState.world_seed


## 某个世界这一局的埋宝点：{pos: Vector2, hint, index}；没有候选点返回 {}。
func treasure_spot(world_id: String, seed_override := -1) -> Dictionary:
	var list: Array = (treasure_data.get("worlds", {}) as Dictionary).get(world_id, [])
	if list.is_empty():
		return {}
	var s := seed_value() if seed_override < 0 else seed_override
	var i := absi(hash([s, world_id, "treasure"])) % list.size()
	var c: Dictionary = list[i]
	return {"pos": Vector2(float(c["pos"][0]), float(c["pos"][1])), "hint": text(c, "hint"), "index": i}


func treasure_found(world_id: String) -> bool:
	return WorldState.treasures.has(world_id)


func mark_treasure(world_id: String) -> void:
	WorldState.treasures[world_id] = WorldState.world_day
	_changed()


# ---------------------------------------------------------------- 计时挑战

func courses() -> Array:
	return course_data.get("courses", [])


func course(id: String) -> Dictionary:
	for c: Dictionary in courses():
		if str(c["id"]) == id:
			return c
	return {}


func course_best(id: String) -> float:
	return float(WorldState.records.get("course:" + id, 0.0))


## 某个成绩值什么奖牌："gold" / "silver" / "bronze" / ""（只是完成）。
func medal_for(id: String, seconds: float) -> String:
	var m: Array = course(id).get("medals", [])
	for i in mini(m.size(), 3):
		if seconds <= float(m[i]):
			return MEDALS[i]
	return ""


## 记一次完成：返回 {medal, best, new_best}，并弹出提示。
func finish_course(id: String, seconds: float) -> Dictionary:
	var best := course_best(id)
	var new_best := best <= 0.0 or seconds < best
	if new_best:
		WorldState.records["course:" + id] = snappedf(seconds, 0.01)
	var medal := medal_for(id, seconds)
	var c := course(id)
	EventBus.toast_requested.emit(tr("%s：%.1f 秒 · %s%s") % [text(c, "name"), seconds, tr(str(MEDAL_NAMES[medal])),
		(tr("（新纪录！）") if new_best and best > 0.0 else (tr("（最好 %.1f 秒）") % best if not new_best else ""))])
	_changed()
	return {"medal": medal, "best": course_best(id), "new_best": new_best}


# ---------------------------------------------------------------- 打水漂

## 记一次水漂；返回是不是新纪录。
func record_skip(bounces: int) -> bool:
	var best := int(WorldState.records.get("skip_best", 0))
	if bounces > best:
		WorldState.records["skip_best"] = bounces
		_changed()
		return true
	return false


# ---------------------------------------------------------------- 成就

func achievements() -> Array:
	return achievement_data.get("achievements", [])


func is_unlocked(id: String) -> bool:
	return id in WorldState.achievements


## 检查全部成就，新解锁的返回 id 列表（关掉成就的局不检查）。
func check_achievements() -> Array:
	var out := []
	if not GameRules.flag("achievements"):
		return out
	for a: Dictionary in achievements():
		var id := str(a["id"])
		if id in WorldState.achievements:
			continue
		if met(a):
			WorldState.achievements.append(id)
			out.append(id)
			EventBus.toast_requested.emit(tr("成就解锁：%s——%s") % [text(a, "name"), text(a, "desc")])
	if not out.is_empty():
		Sound.play("achievement")
		_changed()
	return out


func met(a: Dictionary) -> bool:
	match str(a["type"]):
		"visit":
			var n := 0
			for w in WorldRegistry.worlds():
				if WorldState.flags.get("visited_" + str(w["id"]), false):
					n += 1
			return n >= int(a["count"])
		"discoveries":
			var c := int(a["count"])
			return WorldState.discoveries.size() >= (c if c > 0 else all_discoveries())
		"collect_kind":
			var wid := str(a["world"])
			var kind := str(a["kind"])
			var items: Array = MiniWorld.data_for(wid).get("items", [])
			var want := items.filter(func(it: Dictionary) -> bool: return str(it.get("kind", "")) == kind)
			if want.is_empty():
				return false
			var got := WorldState.collected(wid)
			for it: Dictionary in want:
				if not str(it["id"]) in got:
					return false
			return true
		"lore":
			return WorldState.journal_list("lore").size() >= int(a["count"])
		"flag":
			return bool(WorldState.flags.get(str(a["key"]), false))
		"fish_total":
			return fish_total() >= int(a["count"])
		"fish_species":
			return WorldState.catches.size() >= int(a["count"])
		"fish_size":
			for id in WorldState.catches:
				if float(WorldState.catches[id]["best_cm"]) >= float(a["min"]):
					return true
			return false
		"record":
			return float(WorldState.records.get(str(a["key"]), 0)) >= float(a["min"])
		"treasures":
			return WorldState.treasures.size() >= int(a["count"])
		"medal":
			for c: Dictionary in courses():
				var b := course_best(str(c["id"]))
				if b > 0.0 and medal_for(str(c["id"]), b) == "gold":
					return true
			return false
		"courses":
			var n := 0
			for c: Dictionary in courses():
				if course_best(str(c["id"])) > 0.0:
					n += 1
			return n >= int(a["count"])
		"dishes":
			return int(WorldState.records.get("dishes", 0)) >= int(a["count"])
		"photos":
			return WorldState.journal_list("photos").size() >= int(a["count"])
		"quests":
			var c := int(a["count"])
			var done := 0
			for q: Dictionary in QuestLog.quests():
				if QuestLog.state_of(str(q["id"])) == "done":
					done += 1
			return done >= (c if c > 0 else QuestLog.quests().size())
	return false


## 全部探索点的个数（湖畔 + 其他世界的数据文件）。
func all_discoveries() -> int:
	var n := Exploration.pois().size()
	for w in WorldRegistry.worlds():
		if str(w["id"]) != "dusk_lake":
			n += (MiniWorld.data_for(str(w["id"])).get("pois", []) as Array).size()
	return n


func _changed() -> void:
	changed.emit()
	SaveManager.request_save()
