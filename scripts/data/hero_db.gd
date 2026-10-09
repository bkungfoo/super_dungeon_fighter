class_name HeroDB
extends RefCounted
## Hero classes. Each class starts with a few free skills and can spend
## skill points on the learnable list in town.

const CLASSES: Dictionary = {
	"warrior": {
		"name": "Warrior", "weapon": "sword", "shield": false,
		"life": 32, "stam": 10, "regen": 2, "attack": 6, "move": 3,
		"skills": ["attack", "defend", "grab"],
		"learnable": ["whirlwind", "final_slash"],
		"color": Color(0.31, 0.64, 1.0),
		"desc": "Sword fighter. Mobile, with the dash-slashing Final Slash.",
	},
	"knight": {
		"name": "Knight", "weapon": "blunt", "shield": true,
		"life": 38, "stam": 9, "regen": 2, "attack": 5, "move": 2,
		"skills": ["attack", "defend", "grab"],
		"learnable": ["bash", "full_swing", "whirlwind"],
		"color": Color(0.95, 0.80, 0.30),
		"desc": "Mace and shield. Slow but sturdy; Bash and Full Swing chain into combos.",
	},
	"mage": {
		"name": "Mage", "weapon": "staff", "shield": false,
		"life": 22, "stam": 14, "regen": 3, "attack": 4, "move": 3,
		"skills": ["attack", "defend", "blink"],
		"learnable": ["fireball", "frost_nova"],
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


static func random_name(rng: RandomNumberGenerator) -> String:
	return NAMES[rng.randi_range(0, NAMES.size() - 1)]
