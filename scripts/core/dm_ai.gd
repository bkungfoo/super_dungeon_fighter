class_name DMAI
extends RefCounted
## The Dungeon Master: builds the dungeon and plays the monsters. The same
## order functions work for either team, which lets tests run AI vs AI.

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
	# A boss is always summoned if it fits and the DM is strong enough.
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
		# Bias toward spending points on bigger monsters when affordable.
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
	# Number duplicate monsters so the log is readable.
	var counts := {}
	for u in engine.living(Unit.TEAM_MONSTERS):
		counts[u.cls] = counts.get(u.cls, 0) + 1
	var seen := {}
	for u in engine.living(Unit.TEAM_MONSTERS):
		if counts[u.cls] > 1:
			seen[u.cls] = seen.get(u.cls, 0) + 1
			u.name = "%s %d" % [u.name, seen[u.cls]]


# ------------------------------------------------------------------ orders

func _enemies(engine: GameEngine, team: int) -> Array:
	return engine.living(1 - team)


func _nearest_enemy_dist(engine: GameEngine, c: Vector2i, team: int) -> int:
	var best := 999
	for e in _enemies(engine, team):
		best = mini(best, BoardGrid.manhattan(c, e.pos))
	return best


func _charge_target_dir(engine: GameEngine, u: Unit, from: Vector2i, reach: int) -> Vector2i:
	for d in GameEngine.DIRS:
		var c := from
		for i in reach:
			c += d
			if not engine.grid.passable(c):
				break
			var v := engine.unit_at(c)
			if v != null:
				if v.team != u.team:
					return d
				break
	return Vector2i.ZERO


func _max_charge(engine: GameEngine, u: Unit) -> int:
	var best := 0
	for sid in u.skills:
		var p := SkillDB.params(sid, u.skills[sid])
		if p.has("charge"):
			best = maxi(best, p.charge)
	return best


## Movement orders for every unit on `team`: unit_id -> destination.
func move_orders(engine: GameEngine, team: int) -> Dictionary:
	var orders := {}
	var claimed := {}
	for u in engine.living(team):
		if not engine.can_move(u):
			continue
		var opts := engine.movement_options(u)
		var best_cell: Vector2i = u.pos
		var best_score := -INF
		var candidates: Array = opts.keys()
		candidates.append(u.pos)
		var charge := _max_charge(engine, u)
		for c in candidates:
			if claimed.has(c) and c != u.pos:
				continue
			var dist := _nearest_enemy_dist(engine, c, team)
			var score := -dist * 10.0
			if dist == 1:
				score += 25.0
			if charge > 0 and _charge_target_dir(engine, u, c, charge) != Vector2i.ZERO:
				score += 18.0 - dist
			# Casters keep a little distance.
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
		claimed[best_cell] = true
		orders[u.id] = best_cell
	return orders


## Skill orders for every unit on `team`: unit_id -> {"skill", "cell"}.
func skill_orders(engine: GameEngine, team: int) -> Dictionary:
	var orders := {}
	for u in engine.living(team):
		var pick := _pick_skill(engine, u)
		if not pick.is_empty():
			orders[u.id] = pick
	return orders


func _pick_skill(engine: GameEngine, u: Unit) -> Dictionary:
	var avail := engine.available_skills(u)
	if avail.is_empty():
		return {}
	var candidates: Array = []  # {skill, cell, weight}
	var adjacent_enemies: Array = []
	for d in GameEngine.DIRS:
		var v := engine.unit_at(u.pos + d)
		if v != null and v.team != u.team:
			adjacent_enemies.append(v)
	var low_life: bool = u.life * 100 < u.max_life * 40

	for sid in avail:
		var def := SkillDB.get_def(sid)
		var p := SkillDB.params(sid, u.skills[sid])
		var dmg: int = int(round(u.attack * float(p.mult)))
		var applies_status: bool = p.get("stun", 0) > 0 or p.get("down", 0) > 0
		match def.target:
			"self":
				if p.get("defend", false):
					var w := 2.0
					if not adjacent_enemies.is_empty():
						w = 10.0
					if low_life:
						w += 8.0
					# Guarding is wise while an enemy is charging something.
					for e in adjacent_enemies:
						if not e.loading.is_empty():
							w += 10.0
					candidates.append({"skill": sid, "cell": u.pos, "weight": w})
				elif p.has("radius"):
					var n := 0
					for e in _enemies(engine, u.team):
						if BoardGrid.manhattan(e.pos, u.pos) <= p.radius:
							n += 1
					if n > 0:
						var w := 12.0 * n * (1.0 if p.get("load", 0) == 0 else 0.8)
						if p.get("life_cost", 0) > 0 and low_life:
							w *= 0.3
						candidates.append({"skill": sid, "cell": u.pos, "weight": w})
			"dir":
				if p.has("charge"):
					var d := _charge_target_dir(engine, u, u.pos, p.charge)
					if d != Vector2i.ZERO:
						candidates.append({"skill": sid, "cell": u.pos + d, "weight": 28.0 + dmg})
				else:
					for e in adjacent_enemies:
						var w := 30.0
						if sid == "grab":
							w = 16.0
						elif sid != "attack":
							w = 22.0 + dmg
						if p.get("load", 0) > 0:
							w *= 0.8
						if dmg >= e.life and p.get("load", 0) == 0:
							w *= 3.0
						elif applies_status and e.state == Unit.State.DOWN:
							w *= 0.1  # kicking while down hands them a Reset
						elif applies_status and e.state == Unit.State.STUNNED:
							w *= 1.4  # stun -> down combo
						if e.defending and sid == "attack":
							w *= 0.5
						candidates.append({"skill": sid, "cell": e.pos, "weight": w})
			"cell":
				var best_cell := Vector2i(-1, -1)
				var best_n := 0
				for c in engine.skill_targets(u, sid):
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
					candidates.append({"skill": sid, "cell": best_cell, "weight": 14.0 * best_n})
			"blink":
				if not adjacent_enemies.is_empty() and low_life:
					var cells := engine.skill_targets(u, sid)
					var best_cell: Vector2i = u.pos
					var best_d := -1
					for c in cells:
						var dd := _nearest_enemy_dist(engine, c, u.team)
						if dd > best_d:
							best_d = dd
							best_cell = c
					if best_cell != u.pos:
						candidates.append({"skill": sid, "cell": best_cell, "weight": 15.0})
	if candidates.is_empty():
		return {}
	var total := 0.0
	for c in candidates:
		total += c.weight
	var roll := rng.randf() * total
	for c in candidates:
		roll -= c.weight
		if roll <= 0.0:
			return {"skill": c.skill, "cell": c.cell}
	var last: Dictionary = candidates[candidates.size() - 1]
	return {"skill": last.skill, "cell": last.cell}
