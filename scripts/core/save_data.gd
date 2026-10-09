extends Node
## Persistent roster: heroes (level, XP, skill points, skills) and the Dungeon
## Master's own progression. Saved as JSON in user://.

## Tests point this at a scratch file so they never touch the real roster.
var save_path := "user://sdf_save.json"
const START_SKILL_POINTS := 5
const DM_XP_PER_LEVEL := 20
const MAX_HERO_LEVEL := 20

var data: Dictionary = {}


func _ready() -> void:
	load_game()


func _default_data() -> Dictionary:
	return {"heroes": [], "dm": {"xp": 0, "kos": 0, "wipes": 0}, "runs": 0, "wins": 0, "next_hero_id": 1}


func load_game() -> void:
	data = _default_data()
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for k in parsed:
					data[k] = parsed[k]
	# JSON turns ints into floats; normalise the fields we do arithmetic on.
	for h in data.heroes:
		for k in ["id", "level", "xp", "sp", "runs", "kills"]:
			h[k] = int(h.get(k, 0))
		var fixed := {}
		for s in h.get("skills", {}):
			fixed[s] = int(h.skills[s])
		h.skills = fixed
	for k in data.dm:
		data.dm[k] = int(data.dm[k])
	data.runs = int(data.runs)
	data.wins = int(data.wins)
	data.next_hero_id = int(data.next_hero_id)


func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))


func reset() -> void:
	data = _default_data()
	save_game()


# ------------------------------------------------------------------ heroes

func heroes() -> Array:
	return data.heroes


func hero_by_id(id: int) -> Dictionary:
	for h in data.heroes:
		if h.id == id:
			return h
	return {}


func new_hero(hero_name: String, cls: String) -> Dictionary:
	var def := HeroDB.get_def(cls)
	var skills := {}
	for s in def.skills:
		skills[s] = -1
	var h := {
		"id": data.next_hero_id, "name": hero_name, "cls": cls,
		"level": 1, "xp": 0, "sp": START_SKILL_POINTS, "skills": skills,
		"runs": 0, "kills": 0,
	}
	data.next_hero_id += 1
	data.heroes.append(h)
	save_game()
	return h


func remove_hero(id: int) -> void:
	for i in data.heroes.size():
		if data.heroes[i].id == id:
			data.heroes.remove_at(i)
			break
	save_game()


func xp_to_next(level: int) -> int:
	return 4 + 2 * level


## Returns the cost to buy the next rank of `skill` for `hero`, or -1 if maxed.
func next_rank_cost(h: Dictionary, skill: String) -> int:
	var cur: int = h.skills.get(skill, -1)
	if not SkillDB.has_ranks(skill):
		return -1
	if cur >= SkillDB.max_rank(skill):
		return -1
	return SkillDB.rank_cost(skill, cur + 1)


func can_learn(h: Dictionary, skill: String) -> bool:
	var cost := next_rank_cost(h, skill)
	return cost >= 0 and h.sp >= cost


func learn(h: Dictionary, skill: String) -> bool:
	if not can_learn(h, skill):
		return false
	h.sp -= next_rank_cost(h, skill)
	h.skills[skill] = h.skills.get(skill, -1) + 1
	save_game()
	return true


## Level-1 base stats scaled by level.
func hero_stats(h: Dictionary) -> Dictionary:
	var def := HeroDB.get_def(h.cls)
	var lv: int = h.level
	return {
		"life": def.life + 4 * (lv - 1),
		"stam": def.stam + (lv - 1),
		"regen": def.regen,
		"attack": def.attack + int((lv - 1) / 2),
		"move": def.move,
	}


func make_unit(h: Dictionary) -> Unit:
	var def := HeroDB.get_def(h.cls)
	var st := hero_stats(h)
	var u := Unit.new()
	u.name = h.name
	u.cls = h.cls
	u.team = Unit.TEAM_HEROES
	u.hero_id = h.id
	u.max_life = st.life
	u.life = st.life
	u.max_stam = st.stam
	u.stam = st.stam
	u.stam_regen = st.regen
	u.attack = st.attack
	u.move = st.move
	u.weapon = def.weapon
	u.has_shield = def.shield
	u.skills = h.skills.duplicate()
	return u


# ------------------------------------------------------------------ run results

func dm_level() -> int:
	return 1 + int(data.dm.xp / DM_XP_PER_LEVEL)


## Applies XP from a finished run. Returns a list of human-readable lines.
func apply_run(engine: GameEngine, heroes_won: bool) -> Array[String]:
	var lines: Array[String] = []
	data.runs += 1
	if heroes_won:
		data.wins += 1
	for u in engine.units:
		if not u.is_hero():
			continue
		var h := hero_by_id(u.hero_id)
		if h.is_empty():
			continue
		h.runs += 1
		h.kills += u.kill_xp
		var gained: int = u.kill_xp + (2 if heroes_won and u.alive else 0)
		h.xp += gained
		var levels := 0
		while h.level < MAX_HERO_LEVEL and h.xp >= xp_to_next(h.level):
			h.xp -= xp_to_next(h.level)
			h.level += 1
			h.sp += 1
			levels += 1
		var line := "%s: +%d XP" % [h.name, gained]
		if levels > 0:
			line += "  LEVEL UP -> %d (+%d skill point%s)" % [h.level, levels, "s" if levels > 1 else ""]
		if not u.alive:
			line += "  (knocked out, recovers in town)"
		lines.append(line)
	var dm_before := dm_level()
	var dm_gain: int = int(engine.damage_to_heroes / 5) + 5 * engine.hero_kos + (10 if not heroes_won else 0)
	data.dm.xp += dm_gain
	data.dm.kos += engine.hero_kos
	if not heroes_won:
		data.dm.wipes += 1
	var dm_line := "Dark Lord: +%d XP" % dm_gain
	if dm_level() > dm_before:
		dm_line += "  The Dark Lord grows stronger (level %d): new monsters unlocked!" % dm_level()
	lines.append(dm_line)
	save_game()
	return lines
