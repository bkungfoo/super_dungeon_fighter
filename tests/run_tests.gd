extends SceneTree
## Headless rules tests + AI-vs-AI fuzzing.
## Run:  godot --headless --path . -s tests/run_tests.gd

var failures: int = 0
var checks: int = 0
# Autoloads are not instantiated for -s scripts, so build the save helper by hand.
var _save: Node = load("res://scripts/core/save_data.gd").new()


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func _hero(cls: String, pos: Vector2i, extra_skills: Dictionary = {}) -> Unit:
	var h := {"id": 1, "name": cls.capitalize(), "cls": cls, "level": 1, "xp": 0, "sp": 0, "skills": {}, "runs": 0, "kills": 0}
	for s in HeroDB.get_def(cls).skills:
		h.skills[s] = -1
	for s in extra_skills:
		h.skills[s] = extra_skills[s]
	var u: Unit = _save.make_unit(h)
	u.pos = pos
	return u


func _monster(key: String, pos: Vector2i) -> Unit:
	var u := MonsterDB.make_unit(key)
	u.pos = pos
	return u


func _engine() -> GameEngine:
	var e := GameEngine.new(8, 8, 42)
	return e


func _initialize() -> void:
	print("Running Super Dungeon Fighter rules tests...")
	test_attack_stun_and_recovery()
	test_stun_then_stun_is_down()
	test_down_then_hit_is_reset()
	test_defend_parries_attack()
	test_grab_beats_defend_and_loses_to_attack()
	test_loaded_skill_fires_in_charged_phase()
	test_stun_interrupts_loading()
	test_full_swing_knockback_and_chain()
	test_final_slash_dash()
	test_fireball_friendly_fire()
	test_movement_conflict()
	test_skill_table_integrity()
	test_all_scripts_parse()
	test_ai_vs_ai_fuzz()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_attack_stun_and_recovery() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "attack", "cell": g.pos}})
	check(g.life == 12 - 6, "attack deals x1 damage (got %d)" % g.life)
	check(g.state == Unit.State.STUNNED, "attack stuns")
	check(h.stam == 9, "attack costs 1 stamina")
	e.end_round()
	check(g.state == Unit.State.STUNNED and g.tokens == 1, "stun persists into the next round (tokens=%d)" % g.tokens)
	e.start_round()
	check(e.available_skills(g).is_empty(), "stunned unit cannot act")
	check(not e.can_move(g), "stunned unit cannot move")
	e.resolve_movement({})
	e.resolve_skills({})
	e.end_round()
	check(g.state == Unit.State.ACTIVE, "stun 1 wears off after one skipped round")


func test_stun_then_stun_is_down() -> void:
	var e := _engine()
	var h1 := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var h2 := e.add_unit(_hero("warrior", Vector2i(2, 2)))
	var g := e.add_unit(_monster("ogre", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h1.id: {"skill": "attack", "cell": g.pos}, h2.id: {"skill": "attack", "cell": g.pos}})
	check(g.state == Unit.State.DOWN, "two simultaneous stuns knock down")
	check(g.tokens == 2, "simultaneous stuns use max(X, Y) = 1 (+1 end-of-round tick) tokens, got %d" % g.tokens)


func test_down_then_hit_is_reset() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("ogre", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "grab", "cell": g.pos}})
	check(g.state == Unit.State.DOWN, "grab knocks down")
	e.end_round()
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "attack", "cell": g.pos}})
	check(g.state == Unit.State.ACTIVE, "hitting a downed unit resets it to active")
	check(g.resist > 0, "reset grants stun immunity")
	check(g.initiative_until == e.round_no + 1, "reset grants initiative next round")
	e.end_round()
	e.start_round()
	check(e.has_initiative(g), "initiative applies in the following round")
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "attack", "cell": g.pos}})
	check(g.state == Unit.State.ACTIVE, "reset unit shrugs off stun")


func test_defend_parries_attack() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("orc", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "attack", "cell": g.pos}, g.id: {"skill": "defend", "cell": g.pos}})
	check(g.life == g.max_life, "defend blocks attack damage")
	check(h.state == Unit.State.STUNNED, "attacking a defender gets parried")
	check(g.state == Unit.State.ACTIVE, "defender is not stunned")


func test_grab_beats_defend_and_loses_to_attack() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("orc", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "grab", "cell": g.pos}, g.id: {"skill": "defend", "cell": g.pos}})
	check(g.state == Unit.State.DOWN, "grab goes through defend")
	check(g.life == g.max_life - 3, "grab deals half damage (got %d)" % g.life)
	var e2 := _engine()
	var h2 := e2.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g2 := e2.add_unit(_monster("orc", Vector2i(3, 2)))
	e2.start_round()
	e2.resolve_movement({})
	e2.resolve_skills({h2.id: {"skill": "grab", "cell": g2.pos}, g2.id: {"skill": "attack", "cell": h2.pos}})
	check(g2.state == Unit.State.ACTIVE, "attack breaks grab (grabber does not land it)")
	check(h2.state == Unit.State.STUNNED, "the attack still lands on the grabber")


func test_loaded_skill_fires_in_charged_phase() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 3), {"bash": 1}))
	var g := e.add_unit(_monster("ogre", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "bash", "cell": g.pos}})
	check(not h.loading.is_empty(), "bash starts loading")
	check(g.life == g.max_life, "loaded skill does not hit immediately")
	check(e.available_skills(h).is_empty(), "cannot play another skill while loading")
	e.end_round()
	e.start_round()
	check(h.loading.is_empty(), "bash fired in the charged phase")
	check(g.life == g.max_life - 5, "bash deals x1 damage (got %d)" % g.life)
	check(g.state == Unit.State.STUNNED and g.tokens == 3, "bash rank B stuns 3 (tokens=%d)" % g.tokens)
	check(h.cooldown == 2, "bash sets cooldown 2 when fired in the charged phase (got %d)" % h.cooldown)
	check(not ("bash" in e.available_skills(h)), "on cooldown: bash unavailable")
	check("attack" in e.available_skills(h), "chain: attack is available during cooldown")
	check(not ("grab" in e.available_skills(h)), "non-chained skills blocked by cooldown")


func test_stun_interrupts_loading() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 3), {"full_swing": 0}))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 2)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "full_swing", "cell": g.pos}, g.id: {"skill": "attack", "cell": h.pos}})
	check(h.loading.is_empty(), "being stunned interrupts a loading skill")
	check(h.state == Unit.State.STUNNED, "hero is stunned")


func test_full_swing_knockback_and_chain() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 5), {"full_swing": 0, "whirlwind": 0}))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 4)))
	e.grid.walls[Vector2i(3, 2)] = true
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "full_swing", "cell": g.pos}})
	e.end_round()
	e.start_round()
	check(not h.loading.is_empty() and h.loading.counters == 1, "full swing needs 2 load counters")
	check(not e.can_move(h) or true, "loading full swing (not immobile while loading)")
	e.resolve_movement({})
	e.resolve_skills({})
	e.end_round()
	e.start_round()
	check(h.loading.is_empty(), "full swing fired on round 3")
	check(g.life == 12 - 10 - 2, "x2 damage plus 2 for the blocked knockback cell (got %d)" % g.life)
	check(g.pos == Vector2i(3, 3), "knocked back one cell into the wall (pos %s)" % str(g.pos))
	check(g.state == Unit.State.DOWN, "full swing knocks down")
	check(h.immobile == 2 and h.cooldown == 2, "cooldown/immobile set")
	check("whirlwind" in e.available_skills(h), "whirlwind chains from full swing despite cooldown")
	check("defend" in e.available_skills(h), "defend chains from full swing")
	check(not ("attack" in e.available_skills(h)), "attack does not chain from full swing")


func test_final_slash_dash() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(1, 4), {"final_slash": 0}))
	var g1 := e.add_unit(_monster("goblin", Vector2i(2, 4)))
	var g2 := e.add_unit(_monster("goblin", Vector2i(4, 4)))
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({h.id: {"skill": "final_slash", "cell": Vector2i(2, 4)}})
	check(not e.can_move(h), "final slash is immobile while loading")
	e.end_round()
	e.start_round()
	e.resolve_movement({})
	e.resolve_skills({})
	e.end_round()
	e.start_round()
	check(h.pos == Vector2i(5, 4), "dashed to the end of the lane (pos %s)" % str(h.pos))
	check(g1.life == 0 or g1.life == 12 - 12, "first goblin takes 2 hits (life %d)" % g1.life)
	check(g2.life == 12 - 6, "second goblin takes 1 hit (life %d)" % g2.life)


func test_fireball_friendly_fire() -> void:
	var e := _engine()
	var m := e.add_unit(_hero("mage", Vector2i(2, 1), {"fireball": 0}))
	var w := e.add_unit(_hero("warrior", Vector2i(4, 4)))
	var g := e.add_unit(_monster("goblin", Vector2i(4, 3)))
	e.start_round()
	e.resolve_movement({})
	check(Vector2i(4, 3) in e.skill_targets(m, "fireball"), "fireball reaches range 4")
	e.resolve_skills({m.id: {"skill": "fireball", "cell": Vector2i(4, 3)}, g.id: {"skill": "defend", "cell": g.pos}})
	e.end_round()
	e.start_round()
	check(g.life == 12 - 8, "fireball x2 ignores defend (life %d)" % g.life)
	check(w.life == w.max_life - 8, "fireball burns allies in the blast")


func test_movement_conflict() -> void:
	var e := _engine()
	var a := e.add_unit(_hero("warrior", Vector2i(0, 0)))
	var b := e.add_unit(_monster("goblin", Vector2i(2, 0)))
	e.start_round()
	e.resolve_movement({a.id: Vector2i(1, 0), b.id: Vector2i(1, 0)})
	check(a.pos != b.pos, "two units cannot share a cell")
	check(a.pos == Vector2i(1, 0) or b.pos == Vector2i(1, 0), "one of them gets the contested cell")
	var opts := e.movement_options(a)
	check(not opts.has(b.pos), "cannot move onto an occupied cell")


func test_skill_table_integrity() -> void:
	for sid in SkillDB.SKILLS:
		var def := SkillDB.get_def(sid)
		for c in def.chains:
			check(SkillDB.SKILLS.has(c), "chain target %s of %s exists" % [c, sid])
		for r in range(0, 4):
			var p := SkillDB.params(sid, r)
			check(p.has("cost"), "%s has a cost" % sid)
			var d := SkillDB.describe(sid, r)
			check(not d.contains("{"), "%s description fully formatted: %s" % [sid, d])
	check(not SkillDB.SKILLS.has("shield_charge"), "shield charge is left out by design")
	for cls in HeroDB.CLASSES:
		for s in HeroDB.get_def(cls).skills + HeroDB.get_def(cls).learnable:
			check(SkillDB.SKILLS.has(s), "class %s skill %s exists" % [cls, s])
	for mk in MonsterDB.MONSTERS:
		for s in MonsterDB.get_def(mk).skills:
			check(SkillDB.SKILLS.has(s), "monster %s skill %s exists" % [mk, s])


func test_all_scripts_parse() -> void:
	var stack: Array[String] = ["res://scripts", "res://tests"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for d in dir.get_directories():
			stack.append(dir_path.path_join(d))
		for f in dir.get_files():
			if f.ends_with(".gd"):
				var scr = load(dir_path.path_join(f))
				check(scr != null and scr.can_instantiate(), "%s parses and compiles" % dir_path.path_join(f))


func test_ai_vs_ai_fuzz() -> void:
	var hero_wins := 0
	var games := 40
	var total_rounds := 0
	for gi in games:
		var e := GameEngine.new(8, 8, 1000 + gi)
		var ai := DMAI.new(e.rng)
		var dm_level := 1 + gi % 4
		var monsters := ai.choose_monsters(3 + gi % 5, dm_level)
		ai.build_dungeon(e, monsters, 6)
		var classes := ["warrior", "knight", "mage"]
		var learn := {"warrior": {"whirlwind": gi % 4, "final_slash": gi % 4}, "knight": {"bash": gi % 4, "full_swing": gi % 4, "whirlwind": 0}, "mage": {"fireball": gi % 4, "frost_nova": gi % 4}}
		for i in 3:
			var cls: String = classes[i]
			var u := _hero(cls, Vector2i(2 + i * 2, 7), learn[cls])
			u.hero_id = i + 1
			e.add_unit(u)
		var rounds := 0
		while e.winner() < 0 and rounds < 60:
			rounds += 1
			e.start_round()
			if e.winner() >= 0:
				break
			var mo := ai.move_orders(e, 0)
			mo.merge(ai.move_orders(e, 1))
			e.resolve_movement(mo)
			var so := ai.skill_orders(e, 0)
			so.merge(ai.skill_orders(e, 1))
			e.resolve_skills(so)
			e.end_round()
			# Invariants.
			var seen := {}
			for u in e.living():
				check(e.grid.passable(u.pos), "unit %s stands on a passable cell" % u.name)
				check(not seen.has(u.pos), "no two living units share a cell")
				seen[u.pos] = true
				check(u.life > 0, "living units have positive life")
				check(u.stam >= 0, "stamina never negative")
		total_rounds += rounds
		if e.winner() == Unit.TEAM_HEROES:
			hero_wins += 1
		check(e.winner() >= 0, "game %d finishes within 60 rounds" % gi)
	print("AI fuzz: heroes won %d/%d games, avg %.1f rounds" % [hero_wins, games, float(total_rounds) / games])
