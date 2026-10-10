class_name BattleSim
extends RefCounted
## Real-time rules engine for one dungeon run. No scene dependencies: the 3D
## scene feeds it input and ticks it; tests drive it headless.
##
## Units: positions are metres on the XZ plane (Vector2 = x, z); one board
## tile of the original design is TILE metres; load times, cooldowns and
## stun/down durations are the design document's turn counts in seconds.

signal log_msg(text: String)
signal event(kind: String, data: Dictionary)

const TILE := 1.5
const SEC_PER_LOAD := 1.2
const SEC_PER_COOLDOWN := 1.2
const SEC_PER_STUN := 1.0
const SEC_PER_DOWN := 1.3
const SEC_PER_IMMOBILE := 1.2
const GUARD_SECONDS := 2.0
const MELEE_GAP := 0.6               # gap between two actors at which melee connects
const KNOCKBACK_METRES := 1.0        # per knockback point
const PATH_REFRESH := 0.4
const HAND_SIZE := 5
const MAX_STEP := 0.05               # simulation substep

var map: BattleMap
var actors: Array = []
var time: float = 0.0
var rng := RandomNumberGenerator.new()
var damage_to_heroes: int = 0
var hero_kos: int = 0
var history: Array[String] = []
var brain: MonsterAI
var _next_id: int = 1


func _init(seed_value: int = -1) -> void:
	map = BattleMap.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	brain = MonsterAI.new()


# ------------------------------------------------------------------ queries

func add_actor(a: Actor) -> Actor:
	a.id = _next_id
	_next_id += 1
	actors.append(a)
	return a


func actor_by_id(id: int) -> Actor:
	for a in actors:
		if a.id == id:
			return a
	return null


func living(team: int = -1) -> Array:
	var out: Array = []
	for a in actors:
		if a.alive and (team < 0 or a.team == team):
			out.append(a)
	return out


func hero() -> Actor:
	for a in actors:
		if a.is_hero():
			return a
	return null


func enemies_of(a: Actor) -> Array:
	return living(1 - a.team)


func nearest_enemy(a: Actor) -> Actor:
	var best: Actor = null
	var bd := INF
	for e in enemies_of(a):
		var d := a.pos.distance_to(e.pos)
		if d < bd:
			bd = d
			best = e
	return best


func dist(a: Actor, b: Actor) -> float:
	return a.pos.distance_to(b.pos)


func melee_reach(a: Actor, b: Actor) -> float:
	return a.radius + b.radius + MELEE_GAP


## -1 = still fighting, 0 = heroes win, 1 = monsters win.
func winner() -> int:
	if living(Actor.TEAM_HEROES).is_empty():
		return Actor.TEAM_MONSTERS
	if living(Actor.TEAM_MONSTERS).is_empty():
		return Actor.TEAM_HEROES
	return -1


func _log(text: String) -> void:
	history.append(text)
	log_msg.emit(text)


func _emit(kind: String, data: Dictionary) -> void:
	event.emit(kind, data)


func _shuffled(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


# ------------------------------------------------------------------ ranges

func aoe_radius(p: Dictionary) -> float:
	return p.get("radius", 1) * TILE


func blast_radius(p: Dictionary) -> float:
	return (p.get("radius", 0) + 0.5) * TILE


## How close the caster must get (centre to centre) before a skill can be cast.
func engage_range(a: Actor, sid: String, rank: int, target: Actor) -> float:
	var def := SkillDB.get_def(sid)
	var p := SkillDB.params(sid, rank)
	var reach: float = (melee_reach(a, target) if target != null else a.radius + 0.45 + MELEE_GAP)
	match def.target:
		"dir":
			if p.has("charge"):
				return p.charge * TILE + reach
			return reach
		"self":
			if p.has("radius"):
				return maxf(0.8, aoe_radius(p) - 0.3)
			return 0.0
		"cell", "blink":
			return p.range * TILE
	return reach


## Skills that can be aimed at a spot on the ground.
static func targets_point(sid: String) -> bool:
	var t: String = SkillDB.get_def(sid).get("target", "")
	return t == "cell" or t == "blink"


# ------------------------------------------------------------------ decks

func setup_deck(a: Actor, cards: Array) -> void:
	a.uses_deck = true
	a.deck = _shuffled(cards)
	a.hand = []
	a.discard = []
	_draw(a)


func _draw(a: Actor) -> void:
	while a.hand.size() < HAND_SIZE:
		if a.deck.is_empty():
			if a.discard.is_empty():
				return
			a.deck = _shuffled(a.discard)
			a.discard = []
			_log("%s reshuffles the discard pile." % a.name)
		a.hand.append(a.deck.pop_back())


func is_chain_available(a: Actor, sid: String) -> bool:
	return a.cooldown > 0.0 and sid in a.chain_allowed and time <= a.chain_until


func skill_usable(a: Actor, sid: String, rank: int) -> bool:
	if not a.can_act() or a.is_charging():
		return false
	var def := SkillDB.get_def(sid)
	if def.is_empty() or not a.weapon_ok(def.weapon):
		return false
	var p := SkillDB.params(sid, rank)
	if a.cooldown > 0.0 and not is_chain_available(a, sid):
		return false
	if a.stam < p.cost:
		return false
	if p.get("life_cost", 0) >= a.life:
		return false
	return true


func card_playable(a: Actor, card: Dictionary) -> bool:
	return skill_usable(a, card.skill, card.rank)


## Hero plays a card from the hand: it is discarded, the hand refills, and the
## skill starts charging (or is ready at once if it has no load time).
func play_card(a: Actor, card: Dictionary) -> bool:
	if not card_playable(a, card):
		return false
	var idx := -1
	for i in a.hand.size():
		if a.hand[i].skill == card.skill and a.hand[i].rank == card.rank:
			idx = i
			break
	if idx < 0:
		return false
	a.discard.append(a.hand[idx])
	a.hand.remove_at(idx)
	_draw(a)
	return play_skill(a, card.skill, card.rank)


## Starts a skill (hero card or monster skill). Charge-up skills pause the
## actor while they load; instant skills are ready immediately. Defend needs
## no target and fires at once.
func play_skill(a: Actor, sid: String, rank: int) -> bool:
	if not skill_usable(a, sid, rank):
		return false
	var def := SkillDB.get_def(sid)
	var p := SkillDB.params(sid, rank)
	a.stam -= p.cost
	a.life -= p.get("life_cost", 0)
	a.chain_allowed = []
	a.loaded = {}
	a.path = []
	if p.get("load", 0) > 0:
		a.loading = {"skill": sid, "rank": rank, "timer": 0.0, "need": p.load * SEC_PER_LOAD}
		_log("%s starts charging %s." % [a.name, SkillDB.display_name(sid, rank)])
		_emit("charge", {"actor": a, "name": def.name})
		return true
	if p.get("defend", false):
		_cast(a, sid, rank, null, a.pos)
		return true
	a.loaded = {"skill": sid, "rank": rank}
	_log("%s readies %s." % [a.name, SkillDB.display_name(sid, rank)])
	_emit("ready", {"actor": a, "name": def.name})
	return true


# ------------------------------------------------------------------ commands

func command_move(a: Actor, p: Vector2) -> void:
	a.target_id = -1
	a.has_point = false
	a.has_goal = true
	a.goal = map.nearest_free(map.clamp_inside(p, a.radius))
	a.path = []


func command_target(a: Actor, enemy_id: int) -> void:
	var e := actor_by_id(enemy_id)
	if e == null or not e.alive or e.team == a.team:
		return
	a.target_id = enemy_id
	a.has_point = false
	a.has_goal = false
	a.path = []


## Aim a loaded area skill at a spot on the ground. Without a point-targetable
## skill loaded this is just a move.
func command_point(a: Actor, p: Vector2) -> void:
	if a.loaded.is_empty() or not targets_point(a.loaded.skill):
		command_move(a, p)
		return
	a.target_id = -1
	a.has_goal = false
	a.has_point = true
	a.point = map.clamp_inside(p, 0.1)
	a.path = []


func command_stop(a: Actor) -> void:
	a.clear_intent()


# ------------------------------------------------------------------ tick

func tick(dt: float) -> void:
	while dt > 0.0:
		var step := minf(dt, MAX_STEP)
		_step(step)
		dt -= step


func _step(dt: float) -> void:
	time += dt
	for a in living():
		_tick_timers(a, dt)
	for a in living():
		if a.team == Actor.TEAM_MONSTERS:
			brain.think(self, a, dt)
	for a in living():
		_tick_actor(a, dt)
	_separate()


func _tick_timers(a: Actor, dt: float) -> void:
	a.stam = minf(a.max_stam, a.stam + a.stam_regen * dt)
	a.cooldown = maxf(0.0, a.cooldown - dt)
	a.immobile = maxf(0.0, a.immobile - dt)
	a.invuln = maxf(0.0, a.invuln - dt)
	a.guard = maxf(0.0, a.guard - dt)
	a.resist_timer = maxf(0.0, a.resist_timer - dt)
	a.attack_timer = maxf(0.0, a.attack_timer - dt)
	if a.state != Actor.State.ACTIVE:
		a.status_timer -= dt
		if a.status_timer <= 0.0:
			a.status_timer = 0.0
			a.state = Actor.State.ACTIVE
			_log("%s is back on their feet." % a.name)
			_emit("text", {"actor": a, "text": "UP", "color": Color(0.8, 1, 0.8)})
	if time > a.chain_until:
		a.chain_allowed = []
	if a.is_charging() and a.state == Actor.State.ACTIVE:
		a.loading.timer += dt
		if a.loading.timer >= a.loading.need:
			a.loaded = {"skill": a.loading.skill, "rank": a.loading.rank}
			_log("%s's %s is charged!" % [a.name, SkillDB.get_def(a.loading.skill).name])
			_emit("ready", {"actor": a, "name": SkillDB.get_def(a.loading.skill).name})
			a.loading = {}


func _tick_actor(a: Actor, dt: float) -> void:
	if not a.can_act() or a.is_charging():
		return
	if a.target_id >= 0:
		var t := actor_by_id(a.target_id)
		if t == null or not t.alive:
			a.target_id = -1
			return
		var sid := "attack"
		var rank := -1
		var basic := true
		if not a.loaded.is_empty():
			sid = a.loaded.skill
			rank = a.loaded.rank
			basic = false
		var need := engage_range(a, sid, rank, t)
		var d := dist(a, t)
		if d > need:
			_move_toward(a, t.pos, dt, need * 0.9)
			return
		a.facing = (t.pos - a.pos).normalized() if d > 0.01 else a.facing
		a.path = []
		if basic:
			if a.attack_timer <= 0.0 and a.cooldown <= 0.0 and a.immobile <= 0.0:
				a.attack_timer = a.swing_interval
				_cast(a, "attack", -1, t, t.pos)
		else:
			a.loaded = {}
			_cast(a, sid, rank, t, t.pos)
		return
	if a.has_point:
		if a.loaded.is_empty():
			a.has_point = false
			return
		var need := engage_range(a, a.loaded.skill, a.loaded.rank, null)
		if a.pos.distance_to(a.point) > need:
			_move_toward(a, a.point, dt, need * 0.9)
			return
		var sid: String = a.loaded.skill
		var rank: int = a.loaded.rank
		a.loaded = {}
		a.has_point = false
		a.facing = (a.point - a.pos).normalized() if a.pos.distance_to(a.point) > 0.01 else a.facing
		_cast(a, sid, rank, null, a.point)
		return
	if a.has_goal:
		if a.pos.distance_to(a.goal) < 0.2:
			a.has_goal = false
			a.path = []
		else:
			_move_toward(a, a.goal, dt, 0.1)


func _move_toward(a: Actor, dest: Vector2, dt: float, stop_dist: float) -> void:
	if a.immobile > 0.0:
		return
	if a.pos.distance_to(dest) <= stop_dist:
		a.path = []
		return
	a.path_timer -= dt
	# Re-plan at most every PATH_REFRESH seconds, or sooner only if the path
	# is gone; a moving target just gets the final waypoint nudged.
	var stale: bool = a.path.is_empty() or a.path[a.path.size() - 1].distance_to(dest) > 0.75
	if a.path.is_empty() or (a.path_timer <= 0.0 and stale):
		a.path = map.find_path(a.pos, dest)
		a.path_timer = PATH_REFRESH + rng.randf() * 0.2
		if a.path.is_empty():
			return
	elif stale and a.path.size() == 1 and map.line_free(a.pos, dest):
		a.path[0] = dest
	var wp: Vector2 = a.path[0]
	var to_wp := wp - a.pos
	if to_wp.length() < 0.12:
		a.path.pop_front()
		return
	var dir := to_wp.normalized()
	a.facing = dir
	var step := minf(a.speed * dt, to_wp.length())
	var np := a.pos + dir * step
	if map.is_blocked_point(np, a.radius):
		var nx := Vector2(np.x, a.pos.y)
		var nz := Vector2(a.pos.x, np.y)
		if not map.is_blocked_point(nx, a.radius):
			np = nx
		elif not map.is_blocked_point(nz, a.radius):
			np = nz
		else:
			a.path = []
			return
	a.pos = np
	if a.pos.distance_to(wp) < 0.12:
		a.path.pop_front()


## Keeps actors from overlapping.
func _separate() -> void:
	var live := living()
	for i in live.size():
		for j in range(i + 1, live.size()):
			var a: Actor = live[i]
			var b: Actor = live[j]
			var d := a.pos.distance_to(b.pos)
			var min_d := a.radius + b.radius
			if d >= min_d:
				continue
			var push: Vector2
			if d < 0.001:
				push = Vector2(1, 0).rotated(rng.randf() * TAU) * (min_d * 0.5)
			else:
				push = (a.pos - b.pos) / d * ((min_d - d) * 0.5)
			var na := map.clamp_inside(a.pos + push, a.radius)
			var nb := map.clamp_inside(b.pos - push, b.radius)
			if not map.is_blocked_point(na, a.radius):
				a.pos = na
			if not map.is_blocked_point(nb, b.radius):
				b.pos = nb


# ------------------------------------------------------------------ casting

func _cast(a: Actor, sid: String, rank: int, target: Actor, point: Vector2) -> void:
	var def := SkillDB.get_def(sid)
	var p := SkillDB.params(sid, rank)
	if sid == "attack" and not a.basic_stun:
		p = p.duplicate()
		p.erase("stun")
	var base_dmg: int = maxi(0, int(round(a.attack * float(p.mult))))
	if sid == "attack":
		_log("%s attacks." % a.name)
	else:
		_log("%s unleashes %s!" % [a.name, SkillDB.display_name(sid, rank)])
	_emit("cast", {"actor": a, "name": def.name, "skill": sid})

	if p.get("teleport", false):
		var dest := point
		var max_d: float = p.range * TILE
		if a.pos.distance_to(dest) > max_d:
			dest = a.pos + (dest - a.pos).normalized() * max_d
		dest = map.nearest_free(map.clamp_inside(dest, a.radius))
		var from := a.pos
		a.pos = dest
		_emit("blink", {"actor": a, "from": from, "to": dest})
		_log("%s blinks away." % a.name)
	elif p.has("charge"):
		_dash(a, sid, p, target, base_dmg)
	elif def.target == "dir":
		if target != null and dist(a, target) <= melee_reach(a, target) + 0.5:
			_apply_hit(a, target, sid, p, base_dmg, (target.pos - a.pos).normalized())
		else:
			_log("%s swings at empty air." % a.name)
	elif def.target == "self" and p.has("radius"):
		var hit_any := false
		for e in enemies_of(a):
			if dist(a, e) <= aoe_radius(p) + e.radius:
				hit_any = true
				_apply_hit(a, e, sid, p, base_dmg, (e.pos - a.pos).normalized())
		if not hit_any:
			_log("%s's %s hits nothing." % [a.name, def.name])
	elif def.target == "cell":
		var hit_any := false
		_emit("blast", {"pos": point, "radius": blast_radius(p)})
		for v in living():
			if v == a:
				continue
			if v.pos.distance_to(point) <= blast_radius(p) + v.radius * 0.5:
				hit_any = true
				var kd: Vector2 = (v.pos - point).normalized() if v.pos.distance_to(point) > 0.01 else a.facing
				_apply_hit(a, v, sid, p, base_dmg, kd)
		if not hit_any:
			_log("%s's %s scorches empty ground." % [a.name, def.name])
	elif p.get("defend", false):
		a.guard = GUARD_SECONDS
		_log("%s raises their guard." % a.name)
		_emit("text", {"actor": a, "text": "GUARD", "color": Color(0.6, 0.9, 1)})

	if p.get("cooldown", 0) > 0:
		a.cooldown = maxf(a.cooldown, p.cooldown * SEC_PER_COOLDOWN)
	if p.get("immobile", 0) > 0:
		a.immobile = maxf(a.immobile, p.immobile * SEC_PER_IMMOBILE)
	if p.get("invuln", 0) > 0:
		a.invuln = maxf(a.invuln, p.invuln * 1.0)
	if not def.chains.is_empty():
		a.chain_allowed = def.chains.duplicate()
		a.chain_until = time + p.get("cooldown", 0) * SEC_PER_COOLDOWN + 0.5


## Charging skills: dash along the facing direction. Final Slash runs the whole
## lane and splits its hits among every enemy it passes; Pounce stops at the
## first enemy and bites it.
func _dash(a: Actor, sid: String, p: Dictionary, target: Actor, base_dmg: int) -> void:
	var dir := a.facing
	if target != null and dist(a, target) > 0.01:
		dir = (target.pos - a.pos).normalized()
	var max_d: float = p.charge * TILE
	var start := a.pos
	var end := start
	var travelled := 0.0
	while travelled < max_d:
		var nxt := end + dir * 0.2
		travelled += 0.2
		if map.is_blocked_point(nxt, a.radius):
			break
		end = nxt
		if sid != "final_slash" and target != null and nxt.distance_to(target.pos) <= melee_reach(a, target):
			break
	if sid == "final_slash":
		var hits_on: Array = []
		for e in enemies_of(a):
			if _dist_to_segment(e.pos, start, end) <= a.radius + e.radius + 0.4:
				hits_on.append(e)
		# Do not stop inside an enemy.
		var dest := end
		var guard := 0
		while guard < 20 and _occupied(dest, a):
			dest -= dir * 0.3
			guard += 1
		if dest.distance_to(start) > 0.3:
			a.pos = dest
			_emit("dash", {"actor": a, "from": start, "to": dest})
		if hits_on.is_empty():
			_log("%s dashes through empty space." % a.name)
			return
		hits_on.sort_custom(func(x, y): return x.pos.distance_to(start) < y.pos.distance_to(start))
		var per_hit: int = maxi(1, int(round(a.attack * p.hitpct / 10.0)))
		var counts := {}
		for i in p.split:
			var t: Actor = hits_on[i % hits_on.size()]
			counts[t] = counts.get(t, 0) + 1
		for t in counts:
			_log("%s slashes %s %d times!" % [a.name, t.name, counts[t]])
			_apply_hit(a, t, sid, p, per_hit * counts[t], dir)
	else:
		if end.distance_to(start) > 0.3:
			a.pos = end
			_emit("dash", {"actor": a, "from": start, "to": end})
		if target != null and dist(a, target) <= melee_reach(a, target) + 0.5:
			_apply_hit(a, target, sid, p, base_dmg, dir)
		else:
			_log("%s charges but finds no one." % a.name)


func _occupied(p: Vector2, except: Actor) -> bool:
	for o in living():
		if o != except and o.pos.distance_to(p) < o.radius + except.radius:
			return true
	return false


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _apply_hit(att: Actor, v: Actor, sid: String, p: Dictionary, dmg: int, kdir: Vector2) -> void:
	if not v.alive:
		return
	if v.team == Actor.TEAM_MONSTERS:
		alert(v)
	if v.invuln > 0.0:
		_log("%s is invulnerable!" % v.name)
		_emit("text", {"actor": v, "text": "IMMUNE", "color": Color(0.7, 0.9, 1)})
		return
	var status_ok := true
	if v.guard > 0.0 and not p.get("ranged", false) and not p.get("unblockable", false):
		if p.get("guard_break", false):
			dmg = int(ceil(dmg / 2.0))
			status_ok = false
			_log("%s's guard is broken by %s: half damage." % [v.name, SkillDB.get_def(sid).name])
		else:
			_log("%s blocks %s's %s!" % [v.name, att.name, SkillDB.get_def(sid).name])
			_emit("text", {"actor": v, "text": "BLOCK", "color": Color(0.6, 0.9, 1)})
			if sid == "attack":
				_log("%s is parried!" % att.name)
				_apply_status(att, "stun", 1)
			return
	if dmg > 0:
		v.life -= dmg
		att.damage_dealt += dmg
		if v.is_hero():
			damage_to_heroes += dmg
		_log("%s hits %s for %d." % [att.name, v.name, dmg])
		_emit("damage", {"actor": v, "amount": dmg})
	if status_ok:
		if p.get("stun", 0) > 0:
			_apply_status(v, "stun", p.stun)
		elif p.get("down", 0) > 0:
			_apply_status(v, "down", p.down)
		if p.get("knockback", 0) > 0 and v.alive and v.life > 0:
			_knockback(v, kdir, p.knockback, att)
	if v.life <= 0 and v.alive:
		_kill(v, att)


## Combo state machine: Active -> Stunned -> Down -> Reset -> Active.
func _apply_status(v: Actor, kind: String, x: int) -> void:
	if v.resist_timer > 0.0:
		_log("%s shrugs it off (Reset)." % v.name)
		_emit("text", {"actor": v, "text": "RESIST", "color": Color(1, 1, 0.6)})
		return
	if v.is_charging():
		_log("%s's %s is interrupted!" % [v.name, SkillDB.get_def(v.loading.skill).name])
		v.loading = {}
	v.path = []
	match v.state:
		Actor.State.ACTIVE:
			if kind == "stun":
				v.state = Actor.State.STUNNED
				v.status_timer = x * SEC_PER_STUN
				v.stun_stamp = time
				_log("%s is stunned (%d)." % [v.name, x])
				_emit("text", {"actor": v, "text": "STUN %d" % x, "color": Color(1, 0.9, 0.3)})
			else:
				v.state = Actor.State.DOWN
				v.status_timer = x * SEC_PER_DOWN
				_log("%s is knocked down (%d)." % [v.name, x])
				_emit("text", {"actor": v, "text": "DOWN %d" % x, "color": Color(1, 0.5, 0.3)})
		Actor.State.STUNNED:
			var y := x
			if time - v.stun_stamp < 0.35:
				y = maxi(x, int(round(v.status_timer / SEC_PER_STUN)))
			v.state = Actor.State.DOWN
			v.status_timer = y * SEC_PER_DOWN
			_log("%s is knocked down (%d)!" % [v.name, y])
			_emit("text", {"actor": v, "text": "DOWN %d" % y, "color": Color(1, 0.5, 0.3)})
		Actor.State.DOWN:
			v.state = Actor.State.ACTIVE
			v.status_timer = 0.0
			v.resist_timer = (x + 1) * 1.0
			v.cooldown = 0.0
			v.immobile = 0.0
			_log("%s was kicked while down and springs back up: Reset %d!" % [v.name, x])
			_emit("text", {"actor": v, "text": "RESET!", "color": Color(0.5, 1, 0.5)})


func _knockback(v: Actor, dir: Vector2, n: int, att: Actor) -> void:
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var total := n * KNOCKBACK_METRES
	var moved := 0.0
	var p := v.pos
	while moved < total:
		var nxt := p + dir * 0.1
		if map.is_blocked_point(nxt, v.radius):
			break
		p = nxt
		moved += 0.1
	if moved > 0.0:
		var from := v.pos
		v.pos = p
		_emit("dash", {"actor": v, "from": from, "to": p})
	var blocked := total - moved
	if blocked > 0.05:
		var extra: int = maxi(1, int(round(2.0 * blocked)))
		v.life -= extra
		att.damage_dealt += extra
		if v.is_hero():
			damage_to_heroes += extra
		_log("%s slams into an obstacle for %d extra damage." % [v.name, extra])
		_emit("damage", {"actor": v, "amount": extra})
	if v.life <= 0 and v.alive:
		_kill(v, att)


func _kill(v: Actor, att: Actor) -> void:
	v.alive = false
	v.life = 0
	v.clear_intent()
	_log("%s is defeated!" % v.name)
	_emit("death", {"actor": v})
	if v.is_hero():
		hero_kos += 1
	elif att.is_hero():
		att.kill_xp += v.summon_value
	for o in living():
		if o.target_id == v.id:
			o.target_id = -1


## Wakes a monster and its nearby pack.
func alert(m: Actor) -> void:
	if m.aggro:
		return
	m.aggro = true
	m.think_timer = minf(m.think_timer, 0.3)
	for o in living(Actor.TEAM_MONSTERS):
		if o != m and not o.aggro and o.pos.distance_to(m.pos) < 4.0:
			o.aggro = true
			o.think_timer = minf(o.think_timer, 0.5)


# ------------------------------------------------------------------ dungeon

## Builds the arena: spawns monsters in the far half, the hero near the bottom,
## and lays obstacles that keep everyone reachable.
func generate(hero_actor: Actor, monster_keys: Array[String], obstacle_count: int = 12) -> void:
	add_actor(hero_actor)
	hero_actor.pos = map.hero_spawn
	var keep: Array = [map.hero_spawn]
	for k in monster_keys:
		var m := MonsterDB.make_actor(k)
		var tries := 0
		var ok := false
		while tries < 100 and not ok:
			tries += 1
			var p := Vector2(rng.randf_range(2.0, map.width - 2.0), rng.randf_range(2.0, map.height * 0.6))
			ok = p.distance_to(map.hero_spawn) >= 9.0
			for q in keep:
				if p.distance_to(q) < 2.0:
					ok = false
			if ok:
				m.pos = p
		if not ok:
			m.pos = Vector2(map.width * 0.5, 3.0)
		keep.append(m.pos)
		add_actor(m)
	map.generate(rng, obstacle_count, keep)
	var counts := {}
	for m in living(Actor.TEAM_MONSTERS):
		counts[m.cls] = counts.get(m.cls, 0) + 1
	var seen := {}
	for m in living(Actor.TEAM_MONSTERS):
		if counts[m.cls] > 1:
			seen[m.cls] = seen.get(m.cls, 0) + 1
			m.name = "%s %d" % [m.name, seen[m.cls]]
