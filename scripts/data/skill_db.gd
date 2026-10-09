class_name SkillDB
extends RefCounted
## Skill table. Melee skills follow the design document; Defend/Grab/Fireball/
## Frost Nova/Blink/Pounce are additions to give every class a counter triangle
## (Attack beats Grab, Grab beats Defend, Defend beats Attack).
##
## Shield Charge is intentionally absent: it will be designed later.
##
## Parameter keys (merged from "base" and the chosen "ranks" entry):
##   cost        stamina cost            life_cost  life paid on play
##   load        rounds of load time     load_immobile  can't move while loading
##   cooldown    rounds unable to act    immobile   rounds unable to move
##   invuln      rounds invulnerable     stun / down   status strength
##   mult        damage multiplier       knockback  cells pushed
##   radius      area around self/cell  range      targeting range
##   charge      dash distance           split / hitpct  Final Slash hits
##   guard_break halves damage vs Defend instead of being blocked
##   unblockable ignores Defend entirely  ranged  ignores Defend (spells)
##   defend      marks the user as defending   teleport   Blink

const RANK_NAMES: Array[String] = ["C", "B", "A", "S"]

const SKILLS: Dictionary = {
	"attack": {
		"name": "Attack", "weapon": "melee", "target": "dir",
		"base": {"cost": 1, "stun": 1, "mult": 1.0},
		"ranks": [],
		"chains": ["attack", "whirlwind"],
		"desc": "Strike an adjacent enemy for x1 damage. Stun 1. Beats Grab; parried by Defend.",
	},
	"defend": {
		"name": "Defend", "weapon": "any", "target": "self",
		"base": {"cost": 0, "defend": true},
		"ranks": [],
		"chains": [],
		"desc": "Block all melee damage and status this round. Parries Attack (attacker is Stun 1). Loses to Grab. Guard-break skills still deal half damage.",
	},
	"grab": {
		"name": "Grab", "weapon": "any", "target": "dir",
		"base": {"cost": 1, "down": 1, "mult": 0.5, "unblockable": true},
		"ranks": [],
		"chains": ["attack"],
		"desc": "Throw an adjacent enemy to the floor: x0.5 damage, Down 1. Beats Defend; broken if the target Attacks you this round.",
	},
	"bash": {
		"name": "Bash", "weapon": "blunt", "target": "dir",
		"base": {"load": 1, "cooldown": 2, "mult": 1.0},
		"ranks": [
			{"exp": 1, "cost": 2, "stun": 2},
			{"exp": 3, "cost": 3, "stun": 3},
			{"exp": 6, "cost": 4, "stun": 4},
			{"exp": 10, "cost": 5, "stun": 5},
		],
		"chains": ["attack", "whirlwind"],
		"desc": "Load 1. Hit an adjacent enemy for x1 damage and Stun {stun}. Cooldown 2.",
	},
	"full_swing": {
		"name": "Full Swing", "weapon": "blunt", "target": "dir",
		"base": {"load": 2, "down": 2, "knockback": 2, "cooldown": 2, "immobile": 2, "guard_break": true},
		"ranks": [
			{"exp": 1, "cost": 2, "mult": 2},
			{"exp": 5, "cost": 3, "mult": 3},
			{"exp": 9, "cost": 4, "mult": 4},
			{"exp": 12, "cost": 5, "mult": 5},
		],
		"chains": ["whirlwind", "defend"],
		"desc": "Load 2. Hit an adjacent enemy for x{mult} damage, Down 2, Knockback 2. Cooldown 2, Immobile 2.",
	},
	"final_slash": {
		"name": "Final Slash", "weapon": "sword", "target": "dir",
		"base": {"load": 2, "load_immobile": true, "cooldown": 2, "guard_break": true},
		"ranks": [
			{"exp": 3, "cost": 2, "split": 3, "hitpct": 10, "charge": 4},
			{"exp": 7, "cost": 4, "split": 5, "hitpct": 9, "charge": 5},
			{"exp": 12, "cost": 6, "split": 7, "hitpct": 8, "charge": 6},
			{"exp": 18, "cost": 8, "split": 10, "hitpct": 7, "charge": 7},
		],
		"chains": [],
		"desc": "Load 2 (immobile). Dash up to {charge} cells through enemies and deal {split} hits of {hitpct}0% damage, split among every enemy in the lane. Cooldown 2.",
	},
	"whirlwind": {
		"name": "Whirlwind", "weapon": "melee", "target": "self",
		"base": {"load": 1, "load_immobile": true, "knockback": 2, "down": 1, "invuln": 1, "cooldown": 2, "immobile": 2, "life_cost": 1, "guard_break": true},
		"ranks": [
			{"exp": 1, "cost": 2, "radius": 2, "mult": 1},
			{"exp": 5, "cost": 3, "radius": 3, "mult": 1},
			{"exp": 10, "cost": 4, "radius": 3, "mult": 2},
			{"exp": 15, "cost": 5, "radius": 4, "mult": 2},
		],
		"chains": ["full_swing", "defend"],
		"desc": "Load 1 (immobile), costs 1 life. Hits every enemy within {radius} cells for x{mult} damage, Down 1, Knockback 2. Invulnerable while spinning. Cooldown 2, Immobile 2.",
	},
	"fireball": {
		"name": "Fireball", "weapon": "staff", "target": "cell",
		"base": {"load": 1, "range": 4, "radius": 1, "ranged": true},
		"ranks": [
			{"exp": 2, "cost": 3, "mult": 2},
			{"exp": 4, "cost": 4, "mult": 3},
			{"exp": 7, "cost": 5, "mult": 4},
			{"exp": 10, "cost": 6, "mult": 5},
		],
		"chains": ["blink"],
		"desc": "Load 1. Explodes at a cell within 4 for x{mult} damage to every unit within 1 cell. Friends burn too! Ignores Defend.",
	},
	"frost_nova": {
		"name": "Frost Nova", "weapon": "staff", "target": "self",
		"base": {"load": 1, "cooldown": 2, "mult": 1, "ranged": true},
		"ranks": [
			{"exp": 2, "cost": 4, "radius": 2, "stun": 2},
			{"exp": 5, "cost": 5, "radius": 2, "stun": 3},
			{"exp": 8, "cost": 6, "radius": 3, "stun": 3},
			{"exp": 12, "cost": 7, "radius": 3, "stun": 4},
		],
		"chains": ["fireball", "blink"],
		"desc": "Load 1. Freezes every enemy within {radius} cells: x1 damage, Stun {stun}. Ignores Defend. Cooldown 2.",
	},
	"blink": {
		"name": "Blink", "weapon": "staff", "target": "blink",
		"base": {"cost": 2, "range": 3, "teleport": true},
		"ranks": [],
		"chains": ["fireball"],
		"desc": "Teleport to an empty cell within 3, during the skill phase (after everyone has moved).",
	},
	"pounce": {
		"name": "Pounce", "weapon": "any", "target": "dir",
		"base": {"cost": 2, "charge": 3, "down": 1, "mult": 1.0, "cooldown": 1},
		"ranks": [],
		"chains": ["attack"],
		"desc": "Dash up to 3 cells and bite the first enemy: x1 damage, Down 1. Cooldown 1.",
	},
}


static func get_def(skill_id: String) -> Dictionary:
	return SKILLS.get(skill_id, {})


static func has_ranks(skill_id: String) -> bool:
	return not SKILLS[skill_id].ranks.is_empty()


static func max_rank(skill_id: String) -> int:
	return SKILLS[skill_id].ranks.size() - 1


## Merged parameters for a skill at the given rank (rank -1 = rankless skill).
static func params(skill_id: String, rank: int) -> Dictionary:
	var def: Dictionary = SKILLS[skill_id]
	var p: Dictionary = def.base.duplicate()
	if not def.ranks.is_empty():
		var r: int = clampi(rank, 0, def.ranks.size() - 1)
		for k in def.ranks[r]:
			if k != "exp":
				p[k] = def.ranks[r][k]
	p["cost"] = p.get("cost", 0)
	p["mult"] = p.get("mult", 1.0)
	return p


## Skill-point cost to raise a skill to rank `rank` (0..3).
static func rank_cost(skill_id: String, rank: int) -> int:
	var def: Dictionary = SKILLS[skill_id]
	if def.ranks.is_empty():
		return 0
	return def.ranks[clampi(rank, 0, def.ranks.size() - 1)].exp


static func rank_label(skill_id: String, rank: int) -> String:
	if not has_ranks(skill_id):
		return ""
	return RANK_NAMES[clampi(rank, 0, 3)]


## Human readable description with {param} placeholders filled in.
static func describe(skill_id: String, rank: int) -> String:
	var def: Dictionary = SKILLS[skill_id]
	var p := params(skill_id, rank)
	var text: String = def.desc
	for k in p:
		var v = p[k]
		if v is float:
			v = str(int(v)) if v == floor(v) else str(v)
		text = text.replace("{%s}" % k, str(v))
	return text


static func display_name(skill_id: String, rank: int) -> String:
	var def: Dictionary = SKILLS[skill_id]
	if has_ranks(skill_id):
		return "%s [%s]" % [def.name, rank_label(skill_id, rank)]
	return def.name
