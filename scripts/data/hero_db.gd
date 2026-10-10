class_name HeroDB
extends RefCounted
## Hero classes. Each class has a pool of skills its cards can come from and
## a 30-card starter deck (card key -> count).

const CLASSES: Dictionary = {
	"warrior": {
		"name": "Warrior", "weapon": "sword", "shield": false,
		"life": 32, "stam": 10, "regen": 2, "attack": 6, "move": 3,
		"skills": ["attack", "defend", "grab", "whirlwind", "final_slash"],
		"starter_deck": {"attack:-1": 12, "defend:-1": 7, "grab:-1": 5, "whirlwind:0": 3, "final_slash:0": 3},
		"color": Color(0.31, 0.64, 1.0),
		"desc": "Sword fighter. Mobile, with the dash-slashing Final Slash.",
	},
	"knight": {
		"name": "Knight", "weapon": "blunt", "shield": true,
		"life": 38, "stam": 9, "regen": 2, "attack": 5, "move": 2,
		"skills": ["attack", "defend", "grab", "bash", "full_swing", "whirlwind"],
		"starter_deck": {"attack:-1": 10, "defend:-1": 7, "grab:-1": 4, "bash:0": 5, "full_swing:0": 4},
		"color": Color(0.95, 0.80, 0.30),
		"desc": "Mace and shield. Slow but sturdy; Bash and Full Swing chain into combos.",
	},
	"mage": {
		"name": "Mage", "weapon": "staff", "shield": false,
		"life": 22, "stam": 14, "regen": 3, "attack": 4, "move": 3,
		"skills": ["attack", "defend", "blink", "fireball", "frost_nova"],
		"starter_deck": {"attack:-1": 7, "defend:-1": 6, "blink:-1": 5, "fireball:0": 7, "frost_nova:0": 5},
		"color": Color(0.75, 0.45, 1.0),
		"desc": "Fragile caster. Fireball and Frost Nova ignore Defend; Blink repositions.",
	},
}

const NAMES: Array[String] = [
	"Ardin", "Bryn", "Cassia", "Doran", "Elowen", "Fenn", "Garrick", "Hale",
	"Isolde", "Jorah", "Kestrel", "Lyra", "Maren", "Nox", "Orla", "Pike",
	"Quill", "Rosalind", "Sorrel", "Tamsin", "Ulric", "Vesna", "Wren", "Yorick",
]


static func get_def(cls: String) -> Dictionary:
	return CLASSES.get(cls, {})


## Cards of the given rarity a class can use.
static func cards_for_class(cls: String, rarity: int = -1) -> Array:
	var def := get_def(cls)
	var out: Array = []
	for c in SkillDB.all_cards():
		if not (c.skill in def.skills):
			continue
		if rarity >= 0 and SkillDB.rarity(c.skill, c.rank) != rarity:
			continue
		out.append(c)
	return out


static func random_name(rng: RandomNumberGenerator) -> String:
	return NAMES[rng.randi_range(0, NAMES.size() - 1)]
