class_name Unit
extends RefCounted
## One hero or monster on the board, plus all of its combat state.

enum State { ACTIVE, STUNNED, DOWN }

const TEAM_HEROES := 0
const TEAM_MONSTERS := 1

var id: int = 0
var name: String = ""
var team: int = TEAM_HEROES
var cls: String = ""          # hero class key or monster key
var pos: Vector2i = Vector2i(-1, -1)

var max_life: int = 10
var life: int = 10
var max_stam: int = 5
var stam: int = 5
var stam_regen: int = 2
var attack: int = 3
var move: int = 2
var weapon: String = "sword"  # sword | blunt | staff | claw
var has_shield: bool = false
var skills: Dictionary = {}   # skill_id -> rank index (0..3); -1 for rankless skills
var summon_value: int = 1
var is_boss: bool = false
var hero_id: int = -1         # roster id for heroes, -1 for monsters

# ---- combat state ----
var state: int = State.ACTIVE
var tokens: int = 0           # remaining stun / down tokens
var resist: int = 0           # rounds of immunity to stun/down after a Reset
var initiative_until: int = -1
var cooldown: int = 0
var immobile: int = 0
var invuln: int = 0
var defending: bool = false
var loading: Dictionary = {}  # {skill, rank, dir, cell, counters, need, immobile}
var chain_allowed: Array = []
var chain_expires: int = -1
var stun_phase: int = -1      # phase id in which the current stun was applied
var alive: bool = true
var kill_xp: int = 0
var damage_dealt: int = 0


func is_hero() -> bool:
	return team == TEAM_HEROES


func weapon_ok(req: String) -> bool:
	match req:
		"any", "melee":
			return true
		"shield":
			return has_shield
		_:
			return weapon == req


func state_name() -> String:
	match state:
		State.STUNNED:
			return "Stunned %d" % tokens
		State.DOWN:
			return "Down %d" % tokens
		_:
			return "Active"


func short_status() -> String:
	var parts: Array[String] = []
	if state == State.STUNNED:
		parts.append("STUN %d" % tokens)
	elif state == State.DOWN:
		parts.append("DOWN %d" % tokens)
	if not loading.is_empty():
		parts.append("LOAD %d/%d" % [loading.counters, loading.need])
	if cooldown > 0:
		parts.append("CD %d" % cooldown)
	if immobile > 0:
		parts.append("ROOT %d" % immobile)
	if resist > 0:
		parts.append("RESET %d" % resist)
	if invuln > 0:
		parts.append("IMMUNE")
	return " ".join(parts)


func rank_of(skill_id: String) -> int:
	return skills.get(skill_id, -1)
