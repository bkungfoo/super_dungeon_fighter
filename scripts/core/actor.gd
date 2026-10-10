class_name Actor
extends RefCounted
## One hero or monster in a real-time battle. Positions are metres on the XZ
## plane; timers are seconds.

enum State { ACTIVE, STUNNED, DOWN }

const TEAM_HEROES := 0
const TEAM_MONSTERS := 1

var id: int = 0
var name: String = ""
var team: int = TEAM_HEROES
var cls: String = ""
var hero_id: int = -1

var pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2(0, -1)
var radius: float = 0.45
var speed: float = 3.0           # metres per second

var max_life: int = 10
var life: int = 10
var max_stam: int = 5
var stam: float = 5.0
var stam_regen: float = 1.0      # per second
var attack: int = 3
var weapon: String = "sword"
var has_shield: bool = false
var skills: Dictionary = {}      # monsters: skill_id -> rank
var summon_value: int = 1
var is_boss: bool = false

# ---- deck (heroes) ----
var uses_deck: bool = false
var deck: Array = []
var hand: Array = []
var discard: Array = []

# ---- combat state ----
var state: int = State.ACTIVE
var status_timer: float = 0.0    # seconds left stunned / down
var resist_timer: float = 0.0    # Reset immunity
var cooldown: float = 0.0
var immobile: float = 0.0
var invuln: float = 0.0
var guard: float = 0.0           # Defend active
var stun_stamp: float = -1.0     # sim time of the current stun (simultaneous-stun rule)
var loading: Dictionary = {}     # {skill, rank, timer, need}
var loaded: Dictionary = {}      # {skill, rank} charged and waiting for a target
var attack_timer: float = 0.0    # basic attack swing timer
var chain_allowed: Array = []
var chain_until: float = -1.0
var alive: bool = true
var kill_xp: int = 0
var damage_dealt: int = 0

# ---- intent ----
var target_id: int = -1          # enemy to engage
var has_point: bool = false      # point target for area skills / blink
var point: Vector2 = Vector2.ZERO
var has_goal: bool = false       # plain movement
var goal: Vector2 = Vector2.ZERO
var path: Array[Vector2] = []
var path_timer: float = 0.0
var think_timer: float = 0.0     # monster AI cadence


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


func can_act() -> bool:
	return alive and state == State.ACTIVE


func is_charging() -> bool:
	return not loading.is_empty()


func status_text() -> String:
	var parts: Array[String] = []
	if state == State.STUNNED:
		parts.append("STUNNED")
	elif state == State.DOWN:
		parts.append("DOWN")
	if is_charging():
		parts.append("CHARGING")
	elif not loaded.is_empty():
		parts.append(SkillDB.get_def(loaded.skill).name.to_upper() + " READY")
	if guard > 0.0:
		parts.append("GUARD")
	if resist_timer > 0.0:
		parts.append("RESET")
	if invuln > 0.0:
		parts.append("IMMUNE")
	return " ".join(parts)


func clear_intent() -> void:
	target_id = -1
	has_point = false
	has_goal = false
	path = []
