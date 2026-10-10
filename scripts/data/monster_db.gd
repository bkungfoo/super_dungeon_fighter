class_name MonsterDB
extends RefCounted
## The Dark Lord's roster. `value` is the summoning cost; `dm_level` is the
## Dungeon Master level required before the DM may summon it. `swing` is the
## seconds between basic attacks, `stun` whether those attacks stun, and
## `aggro` the distance (m) at which the monster notices the hero.

const MONSTERS: Dictionary = {
	"goblin": {
		"name": "Goblin", "value": 1, "dm_level": 1,
		"life": 8, "stam": 6, "regen": 2, "attack": 2, "move": 2, "weapon": "sword",
		"swing": 1.6, "stun": false, "aggro": 7.0,
		"skills": {"attack": -1, "grab": -1},
		"color": Color(0.45, 0.75, 0.35),
	},
	"wolf": {
		"name": "Wolf", "value": 1, "dm_level": 1,
		"life": 7, "stam": 6, "regen": 2, "attack": 2, "move": 3, "weapon": "claw",
		"swing": 1.3, "stun": false, "aggro": 9.0,
		"skills": {"attack": -1, "pounce": -1},
		"color": Color(0.6, 0.6, 0.65),
	},
	"skeleton": {
		"name": "Skeleton", "value": 2, "dm_level": 1,
		"life": 14, "stam": 7, "regen": 2, "attack": 3, "move": 2, "weapon": "sword",
		"swing": 1.5, "stun": false, "aggro": 7.0,
		"skills": {"attack": -1, "defend": -1, "whirlwind": 0},
		"color": Color(0.9, 0.9, 0.85),
	},
	"orc": {
		"name": "Orc", "value": 2, "dm_level": 2,
		"life": 20, "stam": 7, "regen": 2, "attack": 4, "move": 2, "weapon": "blunt",
		"swing": 1.5, "stun": true, "aggro": 8.0,
		"skills": {"attack": -1, "bash": 0, "defend": -1},
		"color": Color(0.35, 0.55, 0.30),
	},
	"ogre": {
		"name": "Ogre", "value": 4, "dm_level": 2,
		"life": 40, "stam": 8, "regen": 2, "attack": 6, "move": 1, "weapon": "blunt",
		"swing": 2.0, "stun": true, "aggro": 8.0,
		"skills": {"attack": -1, "full_swing": 1, "grab": -1},
		"color": Color(0.65, 0.45, 0.30),
	},
	"dark_knight": {
		"name": "Dark Knight", "value": 5, "dm_level": 3,
		"life": 36, "stam": 9, "regen": 2, "attack": 6, "move": 2, "weapon": "blunt",
		"swing": 1.4, "stun": true, "aggro": 9.0,
		"skills": {"attack": -1, "bash": 1, "full_swing": 1, "defend": -1},
		"color": Color(0.35, 0.25, 0.45),
	},
	"champion": {
		"name": "Ofrom Champion", "value": 8, "dm_level": 4, "boss": true,
		"life": 70, "stam": 10, "regen": 3, "attack": 8, "move": 3, "weapon": "sword",
		"swing": 1.1, "stun": true, "aggro": 11.0,
		"skills": {"attack": -1, "final_slash": 1, "whirlwind": 1, "defend": -1},
		"color": Color(0.95, 0.30, 0.30),
	},
}


static func get_def(key: String) -> Dictionary:
	return MONSTERS.get(key, {})


static func available(dm_level: int) -> Array[String]:
	var out: Array[String] = []
	for k in MONSTERS:
		if MONSTERS[k].dm_level <= dm_level:
			out.append(k)
	return out


static func make_actor(key: String) -> Actor:
	var d: Dictionary = MONSTERS[key]
	var a := Actor.new()
	a.name = d.name
	a.cls = key
	a.team = Actor.TEAM_MONSTERS
	a.max_life = d.life
	a.life = d.life
	a.max_stam = d.stam
	a.stam = d.stam
	a.stam_regen = d.regen * 0.6
	a.attack = d.attack
	a.speed = 1.4 + d.move * 0.4
	a.swing_interval = d.get("swing", 1.5)
	a.basic_stun = d.get("stun", true)
	a.aggro_range = d.get("aggro", 8.0)
	a.weapon = d.weapon
	a.skills = d.skills.duplicate()
	a.summon_value = d.value
	a.is_boss = d.get("boss", false)
	a.radius = 0.55 if a.is_boss else (0.5 if d.value >= 4 else 0.42)
	return a
