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
##   priority    resolution order in the skill phase (higher fires first)

const RANK_NAMES: Array[String] = ["C", "B", "A", "S"]
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic"]
const RARITY_COLORS: Array[Color] = [Color(0.8, 0.8, 0.8), Color(0.45, 0.85, 0.5), Color(0.4, 0.65, 1.0), Color(0.85, 0.5, 1.0)]
## Power-score thresholds for Uncommon / Rare / Epic.
const RARITY_THRESHOLDS: Array[float] = [3.2, 5.0, 6.8]

const SKILLS: Dictionary = {
	"attack": {
		"name": "Attack", "weapon": "melee", "target": "dir",
		"base": {"priority": 5, "cost": 1, "stun": 1, "mult": 1.0},
		"ranks": [],
		"chains": ["attack", "whirlwind"],
		"desc": "Basic strike: x1 damage, Stun 1. Beats Grab; parried by Defend.",
	},
	"defend": {
		"name": "Defend", "weapon": "any", "target": "self",
		"base": {"priority": 7, "cost": 0, "defend": true},
		"ranks": [],
		"chains": [],
		"desc": "Guard for 2 seconds: blocks melee damage and status. Parries basic attacks (attacker is stunned). Loses to Grab. Guard-break skills still deal half damage.",
	},
	"grab": {
		"name": "Grab", "weapon": "any", "target": "dir",
		"base": {"priority": 4, "cost": 1, "down": 1, "mult": 0.5, "unblockable": true},
		"ranks": [],
		"chains": ["attack"],
		"desc": "Throw a nearby enemy to the floor: x0.5 damage, Down 1. Goes straight through Defend.",
	},
	"bash": {
		"name": "Bash", "weapon": "blunt", "target": "dir",
		"base": {"priority": 3, "load": 1, "cooldown": 2, "mult": 1.0},
		"ranks": [
			{"exp": 1, "cost": 2, "stun": 2},
			{"exp": 3, "cost": 3, "stun": 3},
			{"exp": 6, "cost": 4, "stun": 4},
			{"exp": 10, "cost": 5, "stun": 5},
		],
		"chains": ["attack", "whirlwind"],
		"desc": "Charge up, then club a nearby enemy for x1 damage and Stun {stun}. Short cooldown.",
	},
	"full_swing": {
		"name": "Full Swing", "weapon": "blunt", "target": "dir",
		"base": {"priority": 1, "load": 2, "down": 2, "knockback": 2, "cooldown": 2, "immobile": 2, "guard_break": true},
		"ranks": [
			{"exp": 1, "cost": 2, "mult": 2},
			{"exp": 5, "cost": 3, "mult": 3},
			{"exp": 9, "cost": 4, "mult": 4},
			{"exp": 12, "cost": 5, "mult": 5},
		],
		"chains": ["whirlwind", "defend"],
		"desc": "Long charge. Smash a nearby enemy for x{mult} damage, Down 2, Knockback 2. Leaves you slow to recover (cooldown, rooted).",
	},
	"final_slash": {
		"name": "Final Slash", "weapon": "sword", "target": "dir",
		"base": {"priority": 2, "load": 2, "load_immobile": true, "cooldown": 2, "guard_break": true},
		"ranks": [
			{"exp": 3, "cost": 2, "split": 3, "hitpct": 10, "charge": 4},
			{"exp": 7, "cost": 4, "split": 5, "hitpct": 9, "charge": 5},
			{"exp": 12, "cost": 6, "split": 7, "hitpct": 8, "charge": 6},
			{"exp": 18, "cost": 8, "split": 10, "hitpct": 7, "charge": 7},
		],
		"chains": [],
		"desc": "Long charge. Dash through enemies up to {charge} tiles away, dealing {split} hits of {hitpct}0% damage split among everyone in the lane. Cooldown afterwards.",
	},
	"whirlwind": {
		"name": "Whirlwind", "weapon": "melee", "target": "self",
		"base": {"priority": 2, "load": 1, "load_immobile": true, "knockback": 2, "down": 1, "invuln": 1, "cooldown": 2, "immobile": 2, "life_cost": 1, "guard_break": true},
		"ranks": [
			{"exp": 1, "cost": 2, "radius": 2, "mult": 1},
			{"exp": 5, "cost": 3, "radius": 3, "mult": 1},
			{"exp": 10, "cost": 4, "radius": 3, "mult": 2},
			{"exp": 15, "cost": 5, "radius": 4, "mult": 2},
		],
		"chains": ["full_swing", "defend"],
		"desc": "Charge up (costs 1 life). Hits every enemy within {radius} tiles for x{mult} damage, Down 1, Knockback 2. Invulnerable while spinning, then slow to recover.",
	},
	"fireball": {
		"name": "Fireball", "weapon": "staff", "target": "cell",
		"base": {"priority": 2, "load": 1, "range": 4, "radius": 1, "ranged": true},
		"ranks": [
			{"exp": 2, "cost": 3, "mult": 2},
			{"exp": 4, "cost": 4, "mult": 3},
			{"exp": 7, "cost": 5, "mult": 4},
			{"exp": 10, "cost": 6, "mult": 5},
		],
		"chains": ["blink"],
		"desc": "Charge up, then double-tap the ground (or tap an enemy) within 4 tiles: explodes for x{mult} damage to everything nearby. Ignores Defend.",
	},
	"frost_nova": {
		"name": "Frost Nova", "weapon": "staff", "target": "self",
		"base": {"priority": 3, "load": 1, "cooldown": 2, "mult": 1, "ranged": true},
		"ranks": [
			{"exp": 2, "cost": 4, "radius": 2, "stun": 2},
			{"exp": 5, "cost": 5, "radius": 2, "stun": 3},
			{"exp": 8, "cost": 6, "radius": 3, "stun": 3},
			{"exp": 12, "cost": 7, "radius": 3, "stun": 4},
		],
		"chains": ["fireball", "blink"],
		"desc": "Charge up, then freeze every enemy within {radius} tiles: x1 damage, Stun {stun}. Ignores Defend. Short cooldown.",
	},
	"blink": {
		"name": "Blink", "weapon": "staff", "target": "blink",
		"base": {"priority": 6, "cost": 2, "range": 3, "teleport": true},
		"ranks": [],
		"chains": ["fireball"],
		"desc": "Instant. Double-tap the ground to teleport up to 3 tiles away, or tap an enemy to blink next to it.",
	},
	"pounce": {
		"name": "Pounce", "weapon": "any", "target": "dir", "monster_only": true,
		"base": {"priority": 4, "cost": 2, "charge": 3, "down": 1, "mult": 1.0, "cooldown": 1},
		"ranks": [],
		"chains": ["attack"],
		"desc": "Dash up to 3 tiles and bite the first enemy: x1 damage, Down 1.",
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


# ------------------------------------------------------------------ cards

static func card_key(skill_id: String, rank: int) -> String:
	return "%s:%d" % [skill_id, rank]


static func parse_key(key: String) -> Dictionary:
	var parts := key.split(":")
	return {"skill": parts[0], "rank": int(parts[1]) if parts.size() > 1 else -1}


## Every card that can exist (rankless skills have rank -1). Monster-only
## skills are excluded.
static func all_cards() -> Array:
	var out: Array = []
	for sid in SKILLS:
		if SKILLS[sid].get("monster_only", false):
			continue
		if has_ranks(sid):
			for r in SKILLS[sid].ranks.size():
				out.append({"skill": sid, "rank": r})
		else:
			out.append({"skill": sid, "rank": -1})
	return out


## Average strength of a card: expected damage (hits x multiplier x area),
## status strength, and resolution priority, minus a penalty for load time.
## Cards with higher damage and higher priority score higher and are rarer.
static func power_score(skill_id: String, rank: int) -> float:
	var p := params(skill_id, rank)
	var dmg: float = float(p.mult)
	if p.has("split"):
		dmg = p.split * p.hitpct / 10.0
	var area := 1.0
	if p.has("radius"):
		area = 2.0 if SKILLS[skill_id].target == "cell" else 1.0 + 0.5 * p.radius
	if p.has("charge"):
		area += 0.3
	if p.get("defend", false) or p.get("teleport", false):
		dmg = 0.0
	var status: float = 0.8 * p.get("stun", 0) + 0.8 * p.get("down", 0) + (0.5 if p.get("knockback", 0) > 0 else 0.0)
	var speed: float = 0.25 * p.get("priority", 0) - 0.5 * p.get("load", 0)
	return dmg * area + status + speed


static func rarity(skill_id: String, rank: int) -> int:
	var score := power_score(skill_id, rank)
	var r := 0
	for t in RARITY_THRESHOLDS:
		if score >= t:
			r += 1
	return r


static func rarity_name(skill_id: String, rank: int) -> String:
	return RARITY_NAMES[rarity(skill_id, rank)]


static func display_name(skill_id: String, rank: int) -> String:
	var def: Dictionary = SKILLS[skill_id]
	if has_ranks(skill_id):
		return "%s [%s]" % [def.name, rank_label(skill_id, rank)]
	return def.name
