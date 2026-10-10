class_name MonsterAI
extends RefCounted
## Real-time brains for the Dark Lord's monsters: chase the hero, swing basic
## attacks, and occasionally charge a skill (which pauses them, giving the
## player an opening).

func think(sim: BattleSim, m: Actor, dt: float) -> void:
	var rng := sim.rng
	m.think_timer -= dt
	if m.think_timer > 0.0:
		return
	m.think_timer = 0.35 + rng.randf() * 0.3
	if not m.can_act() or m.is_charging():
		return
	var h := sim.nearest_enemy(m)
	if h == null:
		m.clear_intent()
		return
	# Monsters loiter until the hero comes close (or hits them).
	if not m.aggro:
		if sim.dist(m, h) <= m.aggro_range:
			sim.alert(m)
		else:
			m.clear_intent()
			return
	m.target_id = h.id
	if not m.loaded.is_empty():
		return
	var d := sim.dist(m, h)
	var low_life: bool = m.life * 100 < m.max_life * 40
	var candidates: Array = []
	for sid in m.skills:
		if sid == "attack":
			continue
		var rank: int = m.skills[sid]
		if not sim.skill_usable(m, sid, rank):
			continue
		var def := SkillDB.get_def(sid)
		var p := SkillDB.params(sid, rank)
		var w := 0.0
		if p.get("defend", false):
			w = 2.0
			if d < 4.0 and (h.is_charging() or not h.loaded.is_empty()):
				w = 18.0
			if low_life and d < 3.0:
				w += 8.0
		elif def.target == "self" and p.has("radius"):
			w = 22.0 if d <= sim.aoe_radius(p) + 1.0 else 3.0
			if p.get("life_cost", 0) > 0 and low_life:
				w *= 0.3
		elif p.has("charge"):
			w = 24.0 if (d <= p.charge * BattleSim.TILE + 1.0 and d > 2.0) else 4.0
		elif def.target == "dir":
			w = 16.0 if d <= 3.5 else 2.0
			if h.state == Actor.State.DOWN:
				w *= 0.1
			elif h.state == Actor.State.STUNNED:
				w *= 1.5
		if w > 0.0:
			candidates.append({"sid": sid, "rank": rank, "w": w})
	var basic_w: float = 40.0 if d < 3.0 else 30.0
	candidates.append({"basic": true, "w": basic_w})
	var total := 0.0
	for c in candidates:
		total += c.w
	var roll := rng.randf() * total
	for c in candidates:
		roll -= c.w
		if roll <= 0.0:
			if not c.get("basic", false):
				sim.play_skill(m, c.sid, c.rank)
			return
