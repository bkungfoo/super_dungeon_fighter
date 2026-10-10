extends Node
## Persistent roster: heroes (level, XP, card collection, deck) and the
## Dungeon Master's own progression. Saved as JSON in user://.

## Tests point this at a scratch file so they never touch the real roster.
var save_path := "user://sdf_save.json"
const DECK_SIZE := 30
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
		for k in ["id", "level", "xp", "runs", "kills"]:
			h[k] = int(h.get(k, 0))
		# Migrate pre-deck saves (skill points + ranks) to a starter deck.
		if not h.has("deck"):
			h.deck = HeroDB.get_def(h.cls).starter_deck.duplicate()
			h.collection = h.deck.duplicate()
		h.erase("skills")
		h.erase("sp")
		for field in ["deck", "collection"]:
			var fixed := {}
			for key in h.get(field, {}):
				# Attack became the built-in default; drop its cards.
				if key.begins_with("attack:"):
					continue
				fixed[key] = int(h[field][key])
			h[field] = fixed
		if deck_size(h) < DECK_SIZE:
			_top_up_deck(h)
	for k in data.dm:
		data.dm[k] = int(data.dm[k])
	data.runs = int(data.runs)
	data.wins = int(data.wins)
	data.next_hero_id = int(data.next_hero_id)


## Fills a short deck from the collection, then from the starter deck.
func _top_up_deck(h: Dictionary) -> void:
	for key in h.collection:
		while deck_size(h) < DECK_SIZE and h.deck.get(key, 0) < h.collection[key]:
			h.deck[key] = h.deck.get(key, 0) + 1
	var starter: Dictionary = HeroDB.get_def(h.cls).starter_deck
	var keys: Array = starter.keys()
	var i := 0
	while deck_size(h) < DECK_SIZE and not keys.is_empty():
		var key: String = keys[i % keys.size()]
		h.deck[key] = h.deck.get(key, 0) + 1
		h.collection[key] = maxi(h.collection.get(key, 0), h.deck[key])
		i += 1


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
	var h := {
		"id": data.next_hero_id, "name": hero_name, "cls": cls,
		"level": 1, "xp": 0, "runs": 0, "kills": 0,
		"deck": def.starter_deck.duplicate(),
		"collection": def.starter_deck.duplicate(),
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


# ------------------------------------------------------------------ cards

func deck_size(h: Dictionary) -> int:
	var n := 0
	for key in h.deck:
		n += h.deck[key]
	return n


func collection_size(h: Dictionary) -> int:
	var n := 0
	for key in h.collection:
		n += h.collection[key]
	return n


## The deck expanded into individual cards, ready for BattleSim.setup_deck.
func deck_cards(h: Dictionary) -> Array:
	var out: Array = []
	for key in h.deck:
		var c := SkillDB.parse_key(key)
		for i in h.deck[key]:
			out.append({"skill": c.skill, "rank": c.rank})
	return out


func add_to_deck(h: Dictionary, key: String) -> bool:
	if h.deck.get(key, 0) >= h.collection.get(key, 0) or deck_size(h) >= DECK_SIZE:
		return false
	h.deck[key] = h.deck.get(key, 0) + 1
	save_game()
	return true


func remove_from_deck(h: Dictionary, key: String) -> bool:
	if h.deck.get(key, 0) <= 0:
		return false
	h.deck[key] -= 1
	if h.deck[key] == 0:
		h.deck.erase(key)
	save_game()
	return true


## Rarity odds shift toward rare cards as the dungeon level rises.
func rarity_weights(dungeon_level: int) -> Array[float]:
	var L := float(dungeon_level)
	return [maxf(5.0, 55.0 - 5.0 * L), 30.0, 10.0 + 2.0 * L, maxf(0.0, 2.0 * L - 4.0)]


func roll_rarity(dungeon_level: int, rng: RandomNumberGenerator) -> int:
	var w := rarity_weights(dungeon_level)
	var total := 0.0
	for x in w:
		total += x
	var roll := rng.randf() * total
	for i in w.size():
		roll -= w[i]
		if roll <= 0.0:
			return i
	return 0


## A random card the hero's class can use, of the rolled rarity (or the next
## rarity down if the class has none at that tier). Returns the card key.
func random_card(h: Dictionary, dungeon_level: int, rng: RandomNumberGenerator) -> String:
	var r := roll_rarity(dungeon_level, rng)
	while r >= 0:
		var pool := HeroDB.cards_for_class(h.cls, r)
		if not pool.is_empty():
			var c: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			return SkillDB.card_key(c.skill, c.rank)
		r -= 1
	return "attack:-1"


func grant_card(h: Dictionary, key: String) -> void:
	h.collection[key] = h.collection.get(key, 0) + 1


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


func make_actor(h: Dictionary) -> Actor:
	var def := HeroDB.get_def(h.cls)
	var st := hero_stats(h)
	var a := Actor.new()
	a.name = h.name
	a.cls = h.cls
	a.team = Actor.TEAM_HEROES
	a.hero_id = h.id
	a.max_life = st.life
	a.life = st.life
	a.max_stam = st.stam
	a.stam = st.stam
	a.stam_regen = st.regen * 0.6
	a.attack = st.attack
	a.speed = 2.0 + st.move * 0.5
	a.weapon = def.weapon
	a.has_shield = def.shield
	return a


# ------------------------------------------------------------------ run results

func dm_level() -> int:
	return 1 + int(data.dm.xp / DM_XP_PER_LEVEL)


## Applies XP and card rewards from a finished run. Returns readable lines.
func apply_run(sim: BattleSim, heroes_won: bool, dungeon_level: int) -> Array[String]:
	var lines: Array[String] = []
	data.runs += 1
	if heroes_won:
		data.wins += 1
	for u in sim.actors:
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
			levels += 1
		var line := "%s: +%d XP" % [h.name, gained]
		if levels > 0:
			line += "  LEVEL UP -> %d" % h.level
		if not u.alive:
			line += "  (knocked out, recovers in town)"
		if heroes_won:
			var key := random_card(h, dungeon_level, sim.rng)
			grant_card(h, key)
			var c := SkillDB.parse_key(key)
			line += "\n   New card: %s (%s)" % [SkillDB.display_name(c.skill, c.rank), SkillDB.rarity_name(c.skill, c.rank)]
		lines.append(line)
	var dm_before := dm_level()
	var dm_gain: int = int(sim.damage_to_heroes / 5) + 5 * sim.hero_kos + (10 if not heroes_won else 0)
	data.dm.xp += dm_gain
	data.dm.kos += sim.hero_kos
	if not heroes_won:
		data.dm.wipes += 1
	var dm_line := "Dark Lord: +%d XP" % dm_gain
	if dm_level() > dm_before:
		dm_line += "  The Dark Lord grows stronger (level %d): new monsters unlocked!" % dm_level()
	lines.append(dm_line)
	save_game()
	return lines
