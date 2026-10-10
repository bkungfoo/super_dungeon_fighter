class_name DMAI
extends RefCounted
## The Dungeon Master: builds the dungeon and plays the monsters. The same
## planner works for either team, which lets tests run AI vs AI.

var rng: RandomNumberGenerator


func _init(r: RandomNumberGenerator = null) -> void:
	rng = r if r != null else RandomNumberGenerator.new()
	if r == null:
		rng.randomize()


# ------------------------------------------------------------------ dungeon

## Picks monsters worth up to `budget` summoning points from the DM's roster.
func choose_monsters(budget: int, dm_level: int) -> Array[String]:
	var pool := MonsterDB.available(dm_level)
	var picks: Array[String] = []
	var left := budget
	for k in pool:
		var d := MonsterDB.get_def(k)
		if d.get("boss", false) and d.value <= left and rng.randf() < 0.75:
			picks.append(k)
			left -= d.value
			break
	var guard := 0
	while left > 0 and guard < 100:
		guard += 1
		var options: Array[String] = []
		for k in pool:
			var d := MonsterDB.get_def(k)
			if d.value <= left and not d.get("boss", false):
				options.append(k)
		if options.is_empty():
			break
		var weighted: Array[String] = []
		for k in options:
			for i in MonsterDB.get_def(k).value:
				weighted.append(k)
		var k: String = weighted[rng.randi_range(0, weighted.size() - 1)]
		picks.append(k)
		left -= MonsterDB.get_def(k).value
	if picks.is_empty():
		picks.append("goblin")
	return picks


## Places walls (keeping the board connected) and monsters in the top rows.
func build_dungeon(engine: GameEngine, monster_keys: Array[String], wall_count: int) -> void:
	var g := engine.grid
	var tries := 0
	while g.walls.size() < wall_count and tries < 200:
		tries += 1
		var c := Vector2i(rng.randi_range(0, g.cols - 1), rng.randi_range(2, g.rows - 3))
		if g.walls.has(c):
			continue
		g.walls[c] = true
		if not g.all_connected():
			g.walls.erase(c)
	var spawn_cells: Array[Vector2i] = []
	for y in range(0, 3):
		for x in g.cols:
			var c := Vector2i(x, y)
			if g.passable(c):
				spawn_cells.append(c)
	for k in monster_keys:
		if spawn_cells.is_empty():
			break
		var u := MonsterDB.make_unit(k)
		var i := rng.randi_range(0, spawn_cells.size() - 1)
		u.pos = spawn_cells[i]
		spawn_cells.remove_at(i)
		engine.add_unit(u)
	var counts := {}
	for u in engine.living(Unit.TEAM_MONSTERS):
		counts[u.cls] = counts.get(u.cls, 0) + 1
	var seen := {}
	for u in engine.living(Unit.TEAM_MONSTERS):
		if counts[u.cls] > 1:
			seen[u.cls] = seen.get(u.cls, 0) + 1
			u.name = "%s %d" % [u.name, seen[u.cls]]


# ------------------------------------------------------------------ helpers

func _enemies(engine: GameEngine, team: int) -> Array:
	return engine.living(1 - team)


func _nearest_enemy_dist(engine: GameEngine, c: Vector2i, team: int) -> int:
	var best := 999
	for e in _enemies(engine, team):
		best = mini(best, BoardGrid.manhattan(c, e.pos))
	return best


func _nearest_enemy(engine: GameEngine, c: Vector2i, team: int) -> Unit:
	var best: Unit = null
	var bd := 999
	for e in _enemies(engine, team):
		var d := BoardGrid.manhattan(c, e.pos)
		if d < bd:
			bd = d
			best = e
	return best


## First direction from `from` whose lane (up to `reach`) contains an enemy.
func _charge_target_dir(engine: GameEngine, u: Unit, from: Vector2i, reach: int) -> Vector2i:
	for d in GameEngine.DIRS:
		var c := from
		for i in reach:
			c += d
			if not engine.grid.passable(c):
				break
			var v := engine.unit_at(c)
			if v != null and v != u:
				if v.team != u.team:
					return d
				break
	return Vector2i.ZERO


func _adjacent_enemies(engine: GameEngine, u: Unit, from: Vector2i) -> Array:
	var out: Array = []
	for d in GameEngine.DIRS:
		var v := engine.unit_at(from + d)
		if v != null and v.team != u.team:
			out.append(v)
	return out


func _max_charge(engine: GameEngine, u: Unit) -> int:
	var best := 0
	for c in engine.hand(u):
		var p := SkillDB.params(c.skill, c.rank)
		if p.has("charge"):
			best = maxi(best, p.charge)
	return best


func _best_move(engine: GameEngine, u: Unit, claimed: Dictionary) -> Vector2i:
	var opts := engine.movement_options(u)
	var best_cell: Vector2i = u.pos
	var best_score := -INF
	var candidates: Array = opts.keys()
	candidates.append(u.pos)
	var charge := _max_charge(engine, u)
	for c in candidates:
		if claimed.has(c) and c != u.pos:
			continue
		var dist := _nearest_enemy_dist(engine, c, u.team)
		var score := -dist * 10.0
		if dist == 1:
			score += 25.0
		if charge > 0 and _charge_target_dir(engine, u, c, charge) != Vector2i.ZERO:
			score += 18.0 - dist
		if u.weapon == "staff" and dist == 1:
			score -= 20.0
		if u.weapon == "staff" and dist >= 2 and dist <= 3:
			score += 12.0
		if c == u.pos:
			score += 1.0
		score += rng.randf() * 4.0
		if score > best_score:
			best_score = score
			best_cell = c
	return best_cell


## Fills in aim_dir / aim_cell for a skill fired from `from`. Returns false if
## there is nothing worth aiming at.
func _aim(engine: GameEngine, u: Unit, sid: String, rank: int, from: Vector2i, o: Dictionary) -> bool:
	var def := SkillDB.get_def(sid)
	var p := SkillDB.params(sid, rank)
	match def.target:
		"dir":
			if p.has("charge"):
				var d := _charge_target_dir(engine, u, from, p.charge)
				if d != Vector2i.ZERO:
					o.aim_dir = d
					return true
				return false
			var adj := _adjacent_enemies(engine, u, from)
			if adj.is_empty():
				var e := _nearest_enemy(engine, from, u.team)
				if e == null:
					return false
				o.aim_dir = GameEngine.dir_to(from, e.pos)
				return false
			var target: Unit = adj[0]
			for v in adj:
				if v.life < target.life:
					target = v
			o.aim_dir = GameEngine.dir_to(from, target.pos)
			return true
		"cell":
			var best_cell := Vector2i(-1, -1)
			var best_n := 0
			for c in engine.skill_targets(u, sid, rank, from):
				var n := 0
				for v in engine.living():
					if v == u:
						continue
					if BoardGrid.chebyshev(v.pos, c) <= p.get("radius", 0):
						n += 1 if v.team != u.team else -2
				if n > best_n:
					best_n = n
					best_cell = c
			if best_n > 0:
				o.aim_cell = best_cell
				return true
			return false
		"blink":
			var best_cell := from
			var best_d := _nearest_enemy_dist(engine, from, u.team)
			for c in engine.skill_targets(u, sid, rank, from):
				var dd := _nearest_enemy_dist(engine, c, u.team)
				if dd > best_d:
					best_d = dd
					best_cell = c
			if best_cell != from:
				o.aim_cell = best_cell
				return true
			return false
	return true


# ------------------------------------------------------------------ orders

## One order per unit on `team`: see GameEngine.resolve_round for the format.
func orders(engine: GameEngine, team: int) -> Dictionary:
	var out := {}
	var claimed := {}
	for u in engine.living(team):
		var o := _plan_unit(engine, u, claimed)
		if not o.is_empty():
			out[u.id] = o
	return out


func _plan_unit(engine: GameEngine, u: Unit, claimed: Dictionary) -> Dictionary:
	var o := {}
	var dest: Vector2i = u.pos
	if engine.can_move(u):
		dest = _best_move(engine, u, claimed)
	claimed[dest] = true

	if engine.is_ready(u):
		if dest != u.pos:
			o.move = dest
		_aim(engine, u, u.loading.skill, u.loading.rank, dest, o)
		return o

	var low_life: bool = u.life * 100 < u.max_life * 40
	var candidates: Array = []
	var seen := {}
	for c in engine.playable_cards(u):
		var key := SkillDB.card_key(c.skill, c.rank)
		if seen.has(key):
			continue
		seen[key] = true
		var p := SkillDB.params(c.skill, c.rank)
		var def := SkillDB.get_def(c.skill)
		var from: Vector2i = u.pos if p.get("load", 0) > 0 else dest
		var aim := {}
		var has_target := _aim(engine, u, c.skill, c.rank, from, aim)
		var adj := _adjacent_enemies(engine, u, from)
		var dmg: int = int(round(u.attack * float(p.mult)))
		var applies_status: bool = p.get("stun", 0) > 0 or p.get("down", 0) > 0
		var w := 0.0
		if p.get("defend", false):
			w = 2.0
			if not adj.is_empty():
				w = 10.0
			if low_life:
				w += 8.0
			for e in adj:
				if not e.loading.is_empty():
					w += 10.0
		elif p.get("teleport", false):
			w = 15.0 if (has_target and low_life and not _adjacent_enemies(engine, u, u.pos).is_empty()) else 0.0
		elif def.target == "self" and p.has("radius"):
			var n := 0
			for e in _enemies(engine, u.team):
				if BoardGrid.manhattan(e.pos, from) <= p.radius:
					n += 1
			w = 12.0 * n * (1.0 if p.get("load", 0) == 0 else 0.8)
			if p.get("life_cost", 0) > 0 and low_life:
				w *= 0.3
		elif def.target == "cell":
			w = 14.0 * 2 if has_target else 0.0
		elif has_target:
			var e: Unit = engine.unit_at(from + aim.get("aim_dir", Vector2i.ZERO))
			if p.has("charge"):
				w = 28.0 + dmg
			else:
				w = 30.0
				if c.skill == "grab":
					w = 16.0
				elif c.skill != "attack":
					w = 22.0 + dmg
				if p.get("load", 0) > 0:
					w *= 0.8
				if e != null:
					if dmg >= e.life and p.get("load", 0) == 0:
						w *= 3.0
					elif applies_status and e.state == Unit.State.DOWN:
						w *= 0.1
					elif applies_status and e.state == Unit.State.STUNNED:
						w *= 1.4
					if e.defending and c.skill == "attack":
						w *= 0.5
		if w > 0.0:
			candidates.append({"card": c, "weight": w, "from": from, "aim": aim})

	var move_w := 1.0
	if dest != u.pos:
		move_w = 30.0 if _adjacent_enemies(engine, u, dest).is_empty() else 6.0
	candidates.append({"move_only": true, "weight": move_w})

	var total := 0.0
	for c in candidates:
		total += c.weight
	var roll := rng.randf() * total
	var pick: Dictionary = candidates[candidates.size() - 1]
	for c in candidates:
		roll -= c.weight
		if roll <= 0.0:
			pick = c
			break
	if pick.get("move_only", false):
		if dest != u.pos:
			o.move = dest
		return o
	o.skill = pick.card.skill
	o.rank = pick.card.rank
	if pick.from == dest and dest != u.pos:
		o.move = dest
	for k in pick.aim:
		o[k] = pick.aim[k]
	return o
