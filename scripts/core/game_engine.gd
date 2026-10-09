class_name GameEngine
extends RefCounted
## Pure rules engine for one dungeon run. No scene dependencies, so it can be
## driven by the UI, by AI-vs-AI simulations, and by the headless test runner.
##
## Round structure (from the design document):
##   1. Charged skill phase  – loaded skills gain a counter; ready ones fire.
##   2. Movement phase       – all units reveal movement simultaneously.
##   3. Skill phase          – all units reveal skills simultaneously.
##   4. End of round         – tokens, cooldowns and stamina tick.

signal log_msg(text: String)
signal event(kind: String, data: Dictionary)

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var grid: BoardGrid
var units: Array = []           # Array[Unit]
var round_no: int = 0
var rng := RandomNumberGenerator.new()
var phase_id: int = 0
var damage_to_heroes: int = 0
var hero_kos: int = 0
var _next_id: int = 1
# Timers set during the skill phase get +1 because the end-of-round tick
# happens right after; timers set in the charged phase (before the unit's
# turn) do not.
var _tick_bonus: int = 0
var history: Array[String] = []
## Team whose face-down (loading) cards stay hidden in the log; -1 shows all.
var hidden_team: int = -1


func _loading_name(u: Unit, sid: String) -> String:
	if u.team == hidden_team:
		return "a face-down skill"
	return SkillDB.get_def(sid).name


func _init(cols: int = 8, rows: int = 8, seed_value: int = -1) -> void:
	grid = BoardGrid.new(cols, rows)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


# ------------------------------------------------------------------ queries

func add_unit(u: Unit) -> Unit:
	u.id = _next_id
	_next_id += 1
	units.append(u)
	return u


func unit_by_id(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func unit_at(c: Vector2i) -> Unit:
	for u in units:
		if u.alive and u.pos == c:
			return u
	return null


func living(team: int = -1) -> Array:
	var out: Array = []
	for u in units:
		if u.alive and (team < 0 or u.team == team):
			out.append(u)
	return out


func is_free(c: Vector2i) -> bool:
	return grid.passable(c) and unit_at(c) == null


## -1 = still fighting, 0 = heroes win, 1 = monsters win.
func winner() -> int:
	if living(Unit.TEAM_HEROES).is_empty():
		return Unit.TEAM_MONSTERS
	if living(Unit.TEAM_MONSTERS).is_empty():
		return Unit.TEAM_HEROES
	return -1


func has_initiative(u: Unit) -> bool:
	return u.initiative_until == round_no


func can_move(u: Unit) -> bool:
	if not u.alive or u.state != Unit.State.ACTIVE or u.immobile > 0 or u.move <= 0:
		return false
	if not u.loading.is_empty() and u.loading.get("immobile", false):
		return false
	return true


func can_act(u: Unit) -> bool:
	return u.alive and u.state == Unit.State.ACTIVE and u.loading.is_empty()


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


## Random activation priority ("roll a die"); units with initiative go first.
func _priority_order(arr: Array) -> Array:
	var first: Array = []
	var rest: Array = []
	for u in arr:
		if has_initiative(u):
			first.append(u)
		else:
			rest.append(u)
	return _shuffled(first) + _shuffled(rest)


# ------------------------------------------------------------------ rounds

func start_round() -> void:
	round_no += 1
	phase_id += 1
	_tick_bonus = 0
	_log("--- Round %d ---" % round_no)
	_charged_phase()


func _charged_phase() -> void:
	var ready: Array = []
	for u in living():
		if u.loading.is_empty():
			continue
		u.loading.counters += 1
		if u.loading.counters >= u.loading.need:
			ready.append(u)
		else:
			_log("%s keeps charging %s (%d/%d)." % [u.name, _loading_name(u, u.loading.skill), u.loading.counters, u.loading.need])
	for u in _priority_order(ready):
		if not u.alive or u.state != Unit.State.ACTIVE or u.loading.is_empty():
			if u.alive:
				_log("%s's charged skill was interrupted!" % u.name)
				u.loading = {}
			continue
		var L: Dictionary = u.loading
		u.loading = {}
		_log("%s unleashes %s!" % [u.name, SkillDB.display_name(L.skill, L.rank)])
		_emit("skill", {"unit": u, "name": SkillDB.get_def(L.skill).name})
		_execute(u, L.skill, L.rank, L.dir, L.cell)


# ------------------------------------------------------------------ movement

## Reachable cells for a unit: cell -> path (excluding the start cell).
func movement_options(u: Unit, occupied: Dictionary = {}) -> Dictionary:
	var out := {}
	if not can_move(u):
		return out
	var occ := occupied
	if occ.is_empty():
		for o in living():
			occ[o.pos] = o.id
	var dist := {u.pos: 0}
	var paths := {u.pos: []}
	var frontier: Array[Vector2i] = [u.pos]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if dist[c] >= u.move:
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if not grid.passable(n) or dist.has(n):
				continue
			var blocker = occ.get(n, -1)
			if blocker != -1 and blocker != u.id:
				continue
			dist[n] = dist[c] + 1
			var p: Array = paths[c].duplicate()
			p.append(n)
			paths[n] = p
			out[n] = p
			frontier.append(n)
	return out


## Shortest path ignoring units (used to truncate blocked moves).
func _path_ignoring_units(from: Vector2i, to: Vector2i, limit: int) -> Array:
	var prev := {from: from}
	var frontier: Array[Vector2i] = [from]
	var dist := {from: 0}
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if c == to:
			break
		if dist[c] >= limit:
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if grid.passable(n) and not prev.has(n):
				prev[n] = c
				dist[n] = dist[c] + 1
				frontier.append(n)
	if not prev.has(to):
		return []
	var path: Array = []
	var c := to
	while c != from:
		path.push_front(c)
		c = prev[c]
	return path


## orders: unit_id -> destination cell. Units reveal and move simultaneously;
## conflicts are settled by random priority (initiative first).
func resolve_movement(orders: Dictionary) -> void:
	phase_id += 1
	var movers: Array = []
	for id in orders:
		var u := unit_by_id(id)
		if u != null and can_move(u) and orders[id] != u.pos:
			movers.append(u)
	var occ := {}
	for o in living():
		occ[o.pos] = o.id
	for u in _priority_order(movers):
		var dest: Vector2i = orders[u.id]
		var opts := movement_options(u, occ)
		var path: Array = opts.get(dest, [])
		if path.is_empty():
			path = _path_ignoring_units(u.pos, dest, u.move)
		occ.erase(u.pos)
		var from: Vector2i = u.pos
		var cur: Vector2i = u.pos
		for step in path:
			if occ.has(step):
				break
			cur = step
		occ[cur] = u.id
		if cur != from:
			u.pos = cur
			_emit("move", {"unit": u, "from": from, "to": cur})
		elif not path.is_empty():
			_log("%s is blocked and stays put." % u.name)


# ------------------------------------------------------------------ skills

func available_skills(u: Unit) -> Array:
	var out: Array = []
	if not can_act(u):
		return out
	for sid in u.skills:
		var def := SkillDB.get_def(sid)
		if def.is_empty() or not u.weapon_ok(def.weapon):
			continue
		var p := SkillDB.params(sid, u.skills[sid])
		var chained: bool = sid in u.chain_allowed and round_no <= u.chain_expires
		if u.cooldown > 0 and not chained:
			continue
		if u.stam < p.cost:
			continue
		if p.get("life_cost", 0) >= u.life:
			continue
		out.append(sid)
	return out


func is_chain_available(u: Unit, sid: String) -> bool:
	return u.cooldown > 0 and sid in u.chain_allowed and round_no <= u.chain_expires


## Cells the player may tap to target a skill. For "dir" skills these are the
## four neighbours (plus the whole lane for charging skills).
func skill_targets(u: Unit, sid: String) -> Array[Vector2i]:
	var def := SkillDB.get_def(sid)
	var p := SkillDB.params(sid, u.skills[sid])
	var out: Array[Vector2i] = []
	match def.target:
		"dir":
			for d in DIRS:
				var reach: int = p.get("charge", 1)
				for i in range(1, reach + 1):
					var c: Vector2i = u.pos + d * i
					if not grid.passable(c):
						break
					out.append(c)
		"cell":
			for c in grid.all_cells():
				if grid.passable(c) and BoardGrid.manhattan(c, u.pos) <= p.range:
					out.append(c)
		"blink":
			for c in grid.all_cells():
				if is_free(c) and c != u.pos and BoardGrid.manhattan(c, u.pos) <= p.range:
					out.append(c)
	return out


static func dir_to(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i.ZERO
	return Vector2i(0, signi(d.y))


## orders: unit_id -> {"skill": id, "cell": Vector2i (target or any cell in a direction)}
func resolve_skills(orders: Dictionary) -> void:
	phase_id += 1
	_tick_bonus = 1
	var plays: Array = []
	for id in orders:
		var u := unit_by_id(id)
		if u == null or not can_act(u):
			continue
		var sid: String = orders[id].get("skill", "")
		if sid == "" or not (sid in available_skills(u)):
			continue
		var def := SkillDB.get_def(sid)
		var rank: int = u.skills[sid]
		var p := SkillDB.params(sid, rank)
		var cell: Vector2i = orders[id].get("cell", u.pos)
		var dir := Vector2i.ZERO
		if def.target == "dir":
			dir = dir_to(u.pos, cell)
			if dir == Vector2i.ZERO:
				dir = Vector2i(0, 1)
		u.stam -= p.cost
		u.life -= p.get("life_cost", 0)
		u.chain_allowed = []
		if u.team == hidden_team and p.get("load", 0) > 0:
			_log("%s plays a card face down." % u.name)
		else:
			_log("%s plays %s." % [u.name, SkillDB.display_name(sid, rank)])
			_emit("skill", {"unit": u, "name": def.name})
		plays.append({"u": u, "sid": sid, "rank": rank, "p": p, "dir": dir, "cell": cell, "cancelled": false})

	# Defend is declared before anything resolves.
	for pl in plays:
		if pl.p.get("defend", false):
			pl.u.defending = true

	# Counter: an Attack aimed at a grabber breaks the Grab.
	for pl in plays:
		if pl.sid != "grab":
			continue
		var victim := unit_at(pl.u.pos + pl.dir)
		if victim == null:
			continue
		for other in plays:
			if other.u == victim and other.sid == "attack" and victim.pos + other.dir == pl.u.pos:
				pl.cancelled = true
				_log("%s's Grab is broken by %s's Attack!" % [pl.u.name, victim.name])
				_emit("text", {"pos": pl.u.pos, "text": "BROKEN", "color": Color(1, 0.6, 0.2)})

	var instant: Array = []
	var instant_units: Array = []
	for pl in plays:
		if pl.cancelled:
			continue
		if pl.p.get("load", 0) > 0:
			pl.u.loading = {"skill": pl.sid, "rank": pl.rank, "dir": pl.dir, "cell": pl.cell,
				"counters": 0, "need": pl.p.load, "immobile": pl.p.get("load_immobile", false)}
			_log("%s starts charging %s (ready in %d)." % [pl.u.name, _loading_name(pl.u, pl.sid), pl.p.load])
			_emit("text", {"pos": pl.u.pos, "text": "CHARGING", "color": Color(0.8, 0.8, 1)})
		else:
			instant.append(pl)
			instant_units.append(pl.u)

	var order := _priority_order(instant_units)
	for u in order:
		for pl in instant:
			if pl.u != u:
				continue
			if not u.alive or u.state != Unit.State.ACTIVE:
				_log("%s's %s is interrupted!" % [u.name, SkillDB.get_def(pl.sid).name])
				continue
			_execute(u, pl.sid, pl.rank, pl.dir, pl.cell)
	_tick_bonus = 0


func _execute(u: Unit, sid: String, rank: int, dir: Vector2i, cell: Vector2i) -> void:
	var def := SkillDB.get_def(sid)
	var p := SkillDB.params(sid, rank)
	var base_dmg: int = maxi(0, int(round(u.attack * float(p.mult))))

	if p.get("teleport", false):
		if is_free(cell):
			var from: Vector2i = u.pos
			u.pos = cell
			_emit("move", {"unit": u, "from": from, "to": cell})
			_log("%s blinks away." % u.name)
		else:
			_log("%s's Blink fizzles: the cell is occupied." % u.name)
	elif p.has("charge"):
		_execute_charge(u, sid, p, dir, base_dmg)
	elif def.target == "dir":
		var v := unit_at(u.pos + dir)
		if v != null and v.team != u.team:
			_apply_hit(u, v, sid, p, base_dmg, dir)
		else:
			_log("%s swings at empty air." % u.name)
			_emit("text", {"pos": u.pos + dir, "text": "MISS", "color": Color(0.7, 0.7, 0.7)})
	elif def.target == "self" and p.has("radius"):
		var hit_any := false
		for v in living():
			if v == u or v.team == u.team:
				continue
			if BoardGrid.manhattan(v.pos, u.pos) <= p.radius:
				hit_any = true
				_apply_hit(u, v, sid, p, base_dmg, dir_to(u.pos, v.pos))
		if not hit_any:
			_log("%s's %s hits nothing." % [u.name, def.name])
	elif def.target == "cell":
		var hit_any := false
		_emit("text", {"pos": cell, "text": "BOOM", "color": Color(1, 0.5, 0.1)})
		for v in living():
			if v == u:
				continue
			if BoardGrid.chebyshev(v.pos, cell) <= p.get("radius", 0):
				hit_any = true
				_apply_hit(u, v, sid, p, base_dmg, dir_to(cell, v.pos))
		if not hit_any:
			_log("%s's %s scorches empty floor." % [u.name, def.name])
	elif p.get("defend", false):
		_log("%s raises their guard." % u.name)
		_emit("text", {"pos": u.pos, "text": "GUARD", "color": Color(0.6, 0.9, 1)})

	if p.get("cooldown", 0) > 0:
		u.cooldown = maxi(u.cooldown, p.cooldown + _tick_bonus)
	if p.get("immobile", 0) > 0:
		u.immobile = maxi(u.immobile, p.immobile + _tick_bonus)
	if p.get("invuln", 0) > 0:
		u.invuln = maxi(u.invuln, p.invuln + _tick_bonus)
	if not def.chains.is_empty():
		u.chain_allowed = def.chains.duplicate()
		u.chain_expires = round_no + _tick_bonus


func _execute_charge(u: Unit, sid: String, p: Dictionary, dir: Vector2i, base_dmg: int) -> void:
	var lane: Array[Vector2i] = []
	var c: Vector2i = u.pos
	for i in p.charge:
		c += dir
		if not grid.passable(c):
			break
		lane.append(c)
	if sid == "final_slash":
		# Dash through the lane; every enemy in it shares the hits.
		var targets: Array = []
		for cell in lane:
			var v := unit_at(cell)
			if v != null and v.team != u.team:
				targets.append(v)
		var dest: Vector2i = u.pos
		for i in range(lane.size() - 1, -1, -1):
			if unit_at(lane[i]) == null:
				dest = lane[i]
				break
		if dest != u.pos:
			var from: Vector2i = u.pos
			u.pos = dest
			_emit("move", {"unit": u, "from": from, "to": dest})
		if targets.is_empty():
			_log("%s dashes through empty space." % u.name)
			return
		var per_hit: int = maxi(1, int(round(u.attack * p.hitpct / 10.0)))
		var hits: Dictionary = {}
		for i in p.split:
			var t: Unit = targets[i % targets.size()]
			hits[t] = hits.get(t, 0) + 1
		for t in hits:
			_log("%s slashes %s %d times!" % [u.name, t.name, hits[t]])
			_apply_hit(u, t, sid, p, per_hit * hits[t], dir)
	else:
		# Dash until blocked, then hit whatever is directly ahead.
		var dest: Vector2i = u.pos
		for cell in lane:
			if unit_at(cell) != null:
				break
			dest = cell
		if dest != u.pos:
			var from: Vector2i = u.pos
			u.pos = dest
			_emit("move", {"unit": u, "from": from, "to": dest})
		var v := unit_at(u.pos + dir)
		if v != null and v.team != u.team:
			_apply_hit(u, v, sid, p, base_dmg, dir)
		else:
			_log("%s charges but finds no one." % u.name)


func _apply_hit(att: Unit, v: Unit, sid: String, p: Dictionary, dmg: int, kdir: Vector2i) -> void:
	if not v.alive:
		return
	if v.invuln > 0:
		_log("%s is invulnerable!" % v.name)
		_emit("text", {"pos": v.pos, "text": "IMMUNE", "color": Color(0.7, 0.9, 1)})
		return
	var status_ok := true
	if v.defending and not p.get("ranged", false) and not p.get("unblockable", false):
		if p.get("guard_break", false):
			dmg = int(ceil(dmg / 2.0))
			status_ok = false
			_log("%s's guard is broken by %s: half damage." % [v.name, SkillDB.get_def(sid).name])
		else:
			dmg = 0
			status_ok = false
			_log("%s blocks %s's %s!" % [v.name, att.name, SkillDB.get_def(sid).name])
			_emit("text", {"pos": v.pos, "text": "BLOCK", "color": Color(0.6, 0.9, 1)})
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
		_emit("damage", {"unit": v, "amount": dmg, "pos": v.pos})
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
func _apply_status(v: Unit, kind: String, x: int) -> void:
	if v.resist > 0:
		_log("%s shrugs it off (Reset)." % v.name)
		_emit("text", {"pos": v.pos, "text": "RESIST", "color": Color(1, 1, 0.6)})
		return
	if not v.loading.is_empty():
		_log("%s's %s is interrupted!" % [v.name, _loading_name(v, v.loading.skill)])
		v.loading = {}
	match v.state:
		Unit.State.ACTIVE:
			if kind == "stun":
				v.state = Unit.State.STUNNED
				v.tokens = x + _tick_bonus
				v.stun_phase = phase_id
				_log("%s is stunned (%d)." % [v.name, x])
				_emit("text", {"pos": v.pos, "text": "STUN %d" % x, "color": Color(1, 0.9, 0.3)})
			else:
				v.state = Unit.State.DOWN
				v.tokens = x + _tick_bonus
				_log("%s is knocked down (%d)." % [v.name, x])
				_emit("text", {"pos": v.pos, "text": "DOWN %d" % x, "color": Color(1, 0.5, 0.3)})
		Unit.State.STUNNED:
			var y := x
			if v.stun_phase == phase_id:
				y = maxi(v.tokens - _tick_bonus, x)
			v.state = Unit.State.DOWN
			v.tokens = y + _tick_bonus
			_log("%s is knocked down (%d)!" % [v.name, y])
			_emit("text", {"pos": v.pos, "text": "DOWN %d" % y, "color": Color(1, 0.5, 0.3)})
		Unit.State.DOWN:
			v.state = Unit.State.ACTIVE
			v.tokens = 0
			v.resist = x + 1 + _tick_bonus
			v.initiative_until = round_no + 1
			v.cooldown = 0
			v.immobile = 0
			_log("%s was kicked while down and springs back up: Reset %d! Immune to stun/down, acts first next round." % [v.name, x])
			_emit("text", {"pos": v.pos, "text": "RESET!", "color": Color(0.5, 1, 0.5)})


func _knockback(v: Unit, dir: Vector2i, n: int, att: Unit) -> void:
	if dir == Vector2i.ZERO:
		return
	var c: Vector2i = v.pos
	var moved := 0
	for i in n:
		var nc := c + dir
		if is_free(nc):
			c = nc
			moved += 1
		else:
			break
	if moved > 0:
		var from: Vector2i = v.pos
		v.pos = c
		_emit("move", {"unit": v, "from": from, "to": c})
	var blocked := n - moved
	if blocked > 0:
		var extra := 2 * blocked
		v.life -= extra
		att.damage_dealt += extra
		if v.is_hero():
			damage_to_heroes += extra
		_log("%s slams into an obstacle for %d extra damage." % [v.name, extra])
		_emit("damage", {"unit": v, "amount": extra, "pos": v.pos})
	if v.life <= 0 and v.alive:
		_kill(v, att)


func _kill(v: Unit, att: Unit) -> void:
	v.alive = false
	v.life = 0
	_log("%s is defeated!" % v.name)
	_emit("death", {"unit": v, "pos": v.pos})
	if v.is_hero():
		hero_kos += 1
	elif att.is_hero():
		att.kill_xp += v.summon_value


# ------------------------------------------------------------------ end of round

func end_round() -> void:
	for u in living():
		if u.state != Unit.State.ACTIVE:
			u.tokens -= 1
			if u.tokens <= 0:
				u.tokens = 0
				u.state = Unit.State.ACTIVE
				_log("%s is back on their feet." % u.name)
		u.resist = maxi(0, u.resist - 1)
		u.cooldown = maxi(0, u.cooldown - 1)
		u.immobile = maxi(0, u.immobile - 1)
		u.invuln = maxi(0, u.invuln - 1)
		u.defending = false
		u.stam = mini(u.max_stam, u.stam + u.stam_regen)
		if round_no > u.chain_expires:
			u.chain_allowed = []
