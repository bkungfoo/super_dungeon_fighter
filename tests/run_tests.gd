extends SceneTree
## Headless rules tests for the real-time sim + AI-vs-AI fuzzing.
## Run:  godot --headless --path . -s tests/run_tests.gd

var failures: int = 0
var checks: int = 0
var _save: Node = load("res://scripts/core/save_data.gd").new()


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func _hero(cls: String, pos: Vector2, deck: Array = []) -> Actor:
	var h := {"id": 1, "name": cls.capitalize(), "cls": cls, "level": 1, "xp": 0, "runs": 0, "kills": 0, "deck": {}, "collection": {}}
	var a: Actor = _save.make_actor(h)
	a.pos = pos
	return a


func _monster(key: String, pos: Vector2) -> Actor:
	var a := MonsterDB.make_actor(key)
	a.pos = pos
	a.think_timer = 1.0e9  # passive unless a test wants the brain
	return a


func _sim() -> BattleSim:
	return BattleSim.new(42)


func _cards(sid: String, rank: int, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"skill": sid, "rank": rank})
	return out


func _run(sim: BattleSim, seconds: float) -> void:
	sim.tick(seconds)


func _initialize() -> void:
	print("Running Super Dungeon Fighter real-time tests...")
	test_basic_attack_engagement()
	test_card_charging_pauses_and_fires()
	test_instant_card_and_point_cast()
	test_self_aoe_closes_to_range()
	test_defend_blocks_and_parries()
	test_grab_beats_guard()
	test_stun_down_reset_chain()
	test_knockback_into_wall()
	test_pathfinding_around_obstacle()
	test_pathfinding_speed()
	test_hold_move_and_retarget()
	test_final_slash_dash()
	test_deck_refill()
	test_stun_interrupts_charging()
	test_weak_monsters_do_not_stun_and_wait_for_aggro()
	test_rarity_table()
	test_card_rewards()
	test_skill_table_integrity()
	test_all_scripts_parse()
	test_ai_fuzz()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_basic_attack_engagement() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var g := sim.add_actor(_monster("goblin", Vector2(10, 14)))
	sim.command_target(h, g.id)
	_run(sim, 2.0)
	check(h.pos.distance_to(g.pos) < sim.melee_reach(h, g) + 0.1, "hero closes to melee range (d=%.2f)" % h.pos.distance_to(g.pos))
	_run(sim, 1.0)
	check(g.life < 8, "basic attacks land in real time (life %d)" % g.life)
	check(g.state == Actor.State.STUNNED or g.life <= 0, "hero's basic attack stuns")
	_run(sim, 6.0)
	check(not g.alive, "goblin eventually dies from repeated basic attacks")
	check(h.target_id == -1, "target cleared on death")


func test_card_charging_pauses_and_fires() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("knight", Vector2(10, 20)))
	var g := sim.add_actor(_monster("ogre", Vector2(10, 12)))
	sim.setup_deck(h, _cards("bash", 1, 30))
	sim.command_move(h, Vector2(10, 5))
	check(sim.play_card(h, {"skill": "bash", "rank": 1}), "bash card plays")
	check(h.is_charging(), "bash starts charging")
	var before := h.pos
	_run(sim, 0.6)
	check(h.pos == before, "hero stands still while charging")
	check(h.loaded.is_empty(), "not loaded yet at 0.6s")
	_run(sim, 0.7)
	check(not h.loaded.is_empty() and h.loaded.skill == "bash", "bash loaded after 1.2s")
	sim.command_target(h, g.id)
	_run(sim, 3.0)
	check(h.loaded.is_empty(), "loaded skill consumed on the target")
	check(g.life <= g.max_life - 5, "bash dealt x1 damage (life %d)" % g.life)
	check(g.state == Actor.State.STUNNED or g.state == Actor.State.DOWN, "bash stunned the ogre")
	check(h.cooldown > 0.0 or sim.time > 10, "bash set a cooldown")


func test_instant_card_and_point_cast() -> void:
	var sim := _sim()
	var m := sim.add_actor(_hero("mage", Vector2(10, 30)))
	var g1 := sim.add_actor(_monster("goblin", Vector2(10, 10)))
	var g2 := sim.add_actor(_monster("goblin", Vector2(11.5, 10)))
	sim.setup_deck(m, _cards("fireball", 0, 30))
	sim.play_card(m, {"skill": "fireball", "rank": 0})
	_run(sim, 1.3)
	check(not m.loaded.is_empty(), "fireball loaded")
	sim.command_point(m, Vector2(10.5, 10))
	check(m.has_point, "double tap sets a point target for an area skill")
	_run(sim, 6.0)
	check(m.loaded.is_empty(), "fireball cast once in range")
	check(m.pos.distance_to(Vector2(10.5, 10)) <= 4 * BattleSim.TILE + 0.5, "mage stopped within range")
	check(g1.life == 0 and g2.life == 0, "both goblins in the blast took x2 damage (%d, %d)" % [g1.life, g2.life])
	# Without an area skill loaded a point command is just a move.
	sim.command_point(m, Vector2(20, 30))
	check(m.has_goal and not m.has_point, "point command without area skill moves instead")


func test_self_aoe_closes_to_range() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 25)))
	var g := sim.add_actor(_monster("goblin", Vector2(10, 10)))
	sim.setup_deck(h, _cards("whirlwind", 0, 30))
	sim.play_card(h, {"skill": "whirlwind", "rank": 0})
	_run(sim, 1.3)
	sim.command_target(h, g.id)
	var waited := 0.0
	while not h.loaded.is_empty() and waited < 8.0:
		_run(sim, 0.1)
		waited += 0.1
	check(h.loaded.is_empty(), "whirlwind cast after closing in")
	# The goblin was knocked back 2 m by the hit, so allow for that.
	check(h.pos.distance_to(g.pos) <= sim.aoe_radius(SkillDB.params("whirlwind", 0)) + 2.0 + 0.3, "hero stopped just inside the AoE radius before the knockback (d=%.2f)" % h.pos.distance_to(g.pos))
	check(g.life < 8, "whirlwind hit the goblin from AoE range (life %d)" % g.life)
	check(g.state == Actor.State.DOWN, "whirlwind knocks down")


func test_defend_blocks_and_parries() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var g := sim.add_actor(_monster("orc", Vector2(10, 21.2)))
	sim.setup_deck(h, _cards("defend", -1, 30))
	sim.play_card(h, {"skill": "defend", "rank": -1})
	check(h.guard > 0.0, "defend is instant and raises guard")
	sim.alert(g)
	sim.command_target(g, h.id)
	_run(sim, 0.5)
	check(h.life == h.max_life, "guard blocks the basic attack")
	check(g.state == Actor.State.STUNNED, "attacker is parried")


func test_grab_beats_guard() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var g := sim.add_actor(_monster("orc", Vector2(10, 21.2)))
	sim.setup_deck(h, _cards("grab", -1, 30))
	g.guard = 2.0
	sim.play_card(h, {"skill": "grab", "rank": -1})
	sim.command_target(h, g.id)
	_run(sim, 0.5)
	check(g.state == Actor.State.DOWN, "grab goes through guard")
	check(g.life == g.max_life - 3, "grab deals half damage (life %d)" % g.life)


func test_stun_down_reset_chain() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var g := sim.add_actor(_monster("ogre", Vector2(10, 21.3)))
	sim._apply_status(g, "stun", 2)
	check(g.state == Actor.State.STUNNED and is_equal_approx(g.status_timer, 2.0), "stun 2 lasts 2 seconds")
	sim._apply_status(g, "stun", 1)
	check(g.state == Actor.State.DOWN, "a second stun knocks down")
	check(is_equal_approx(g.status_timer, 2 * BattleSim.SEC_PER_DOWN), "simultaneous stuns keep the larger value")
	sim._apply_status(g, "down", 1)
	check(g.state == Actor.State.ACTIVE and g.resist_timer > 0.0, "kicked while down: reset with immunity")
	sim._apply_status(g, "stun", 3)
	check(g.state == Actor.State.ACTIVE, "reset immunity shrugs off the stun")
	_run(sim, 3.0)
	check(g.resist_timer == 0.0, "immunity expires")


func test_knockback_into_wall() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("knight", Vector2(10, 20)))
	var g := sim.add_actor(_monster("goblin", Vector2(10, 18.8)))
	sim.map.obstacles.append(Rect2(8, 15.5, 4, 2))
	sim.map.rebuild()
	sim.setup_deck(h, _cards("full_swing", 0, 30))
	sim.play_card(h, {"skill": "full_swing", "rank": 0})
	_run(sim, 2.5)
	check(not h.loaded.is_empty(), "full swing loaded after 2.4s")
	sim.command_target(h, g.id)
	_run(sim, 0.3)
	check(g.life <= 0, "x2 damage plus wall slam kills the goblin (life %d)" % g.life)
	check(g.pos.y > 17.5, "goblin stopped at the wall (y=%.2f)" % g.pos.y)
	check(h.immobile > 0.0 and h.cooldown > 0.0, "cooldown and immobile set")
	check(sim.is_chain_available(h, "whirlwind"), "whirlwind chains from full swing during cooldown")
	check(not sim.is_chain_available(h, "grab"), "grab does not chain")


func test_pathfinding_around_obstacle() -> void:
	var sim := _sim()
	sim.map.obstacles.append(Rect2(6, 14, 10, 1.5))
	sim.map.rebuild()
	var h := sim.add_actor(_hero("warrior", Vector2(11, 20)))
	sim.command_move(h, Vector2(11, 10))
	var path := sim.map.find_path(h.pos, Vector2(11, 10))
	check(path.size() >= 2, "path routes around the wall (%d waypoints)" % path.size())
	_run(sim, 8.0)
	check(h.pos.distance_to(Vector2(11, 10)) < 0.5, "hero arrives around the obstacle (d=%.2f)" % h.pos.distance_to(Vector2(11, 10)))
	check(not sim.map.is_blocked_point(h.pos, h.radius), "hero never ends inside a wall")


func test_pathfinding_speed() -> void:
	var sim := BattleSim.new(99)
	var hero := _hero("warrior", Vector2(18, 31))
	sim.generate(hero, ["goblin", "wolf", "orc", "ogre", "skeleton"], 14)
	var t0 := Time.get_ticks_usec()
	var calls := 120
	var lengths := 0
	for i in calls:
		var a := Vector2(sim.rng.randf_range(1, 35), sim.rng.randf_range(1, 35))
		var b := Vector2(sim.rng.randf_range(1, 35), sim.rng.randf_range(1, 35))
		lengths += sim.map.find_path(sim.map.nearest_free(a), sim.map.nearest_free(b)).size()
	var ms_per_call := (Time.get_ticks_usec() - t0) / 1000.0 / calls
	print("pathfinding: %.2f ms per call (%d obstacles)" % [ms_per_call, sim.map.obstacles.size()])
	check(ms_per_call < 15.0, "A* stays fast enough for real time (%.2f ms per call)" % ms_per_call)
	check(lengths > 0, "paths were found")


func test_hold_move_and_retarget() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var g := sim.add_actor(_monster("goblin", Vector2(30, 20)))
	sim.command_target(h, g.id)
	_run(sim, 0.5)
	sim.command_move(h, Vector2(10, 10))
	check(h.target_id == -1 and h.has_goal, "moving cancels the engagement")
	_run(sim, 4.0)
	check(h.pos.distance_to(Vector2(10, 10)) < 0.5, "hero reaches the move goal")
	check(not h.has_goal, "goal cleared on arrival")


func test_final_slash_dash() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(5, 20)))
	var g1 := sim.add_actor(_monster("goblin", Vector2(7.5, 20)))
	var g2 := sim.add_actor(_monster("goblin", Vector2(10, 20.3)))
	sim.setup_deck(h, _cards("final_slash", 0, 30))
	sim.play_card(h, {"skill": "final_slash", "rank": 0})
	_run(sim, 2.5)
	sim.command_target(h, g1.id)
	_run(sim, 0.2)
	check(h.loaded.is_empty(), "final slash fired at range (dash)")
	check(h.pos.x > 9.0, "hero dashed down the lane (x=%.2f)" % h.pos.x)
	check(g1.life <= 0 or g1.life == 0, "first goblin took 2 hits (life %d)" % g1.life)
	check(g2.life == 2, "second goblin took 1 hit (life %d)" % g2.life)


func test_deck_refill() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var cards := _cards("defend", -1, 30)
	sim.setup_deck(h, cards)
	check(h.hand.size() == 5 and h.deck.size() == 25, "opening hand of 5")
	sim.play_card(h, {"skill": "defend", "rank": -1})
	check(h.hand.size() == 5 and h.deck.size() == 24 and h.discard.size() == 1, "hand refills right after playing")
	for i in 40:
		h.guard = 0.0
		h.stam = h.max_stam
		sim.play_card(h, {"skill": "defend", "rank": -1})
	check(h.deck.size() + h.hand.size() + h.discard.size() == 30, "cards are conserved through reshuffles")
	check(not sim.play_card(h, {"skill": "grab", "rank": -1}), "cannot play a card that is not in hand")


func test_stun_interrupts_charging() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("knight", Vector2(10, 20)))
	var g := sim.add_actor(_monster("orc", Vector2(10, 21.2)))
	sim.setup_deck(h, _cards("full_swing", 0, 30))
	sim.play_card(h, {"skill": "full_swing", "rank": 0})
	sim.alert(g)
	sim.command_target(g, h.id)
	_run(sim, 0.5)
	check(not h.is_charging() and h.loaded.is_empty(), "the orc's stunning attack interrupted the charge")
	check(h.state == Actor.State.STUNNED, "hero is stunned")


func test_weak_monsters_do_not_stun_and_wait_for_aggro() -> void:
	var sim := _sim()
	var h := sim.add_actor(_hero("warrior", Vector2(10, 20)))
	var g := sim.add_actor(_monster("goblin", Vector2(10, 21.2)))
	sim.command_target(g, h.id)
	_run(sim, 2.0)
	check(h.life < h.max_life, "goblin still deals damage (life %d)" % h.life)
	check(h.state == Actor.State.ACTIVE, "goblin basic attacks never stun")
	# Aggro: a goblin far away ignores the hero until they come close.
	var sim2 := BattleSim.new(5)
	var h2 := sim2.add_actor(_hero("warrior", Vector2(5, 30)))
	var far := sim2.add_actor(_monster("goblin", Vector2(30, 5)))
	far.think_timer = 0.0
	var start := far.pos
	sim2.tick(3.0)
	check(far.pos.distance_to(start) < 0.1 and not far.aggro, "distant goblin loiters")
	sim2.command_move(h2, Vector2(26, 8))
	sim2.tick(12.0)
	check(far.aggro, "goblin wakes when the hero comes within aggro range")
	# Being hit wakes a pack.
	var sim3 := BattleSim.new(6)
	sim3.add_actor(_hero("warrior", Vector2(5, 30)))
	var a := sim3.add_actor(_monster("goblin", Vector2(30, 5)))
	var b := sim3.add_actor(_monster("wolf", Vector2(32, 6)))
	sim3._apply_hit(sim3.hero(), a, "attack", SkillDB.params("attack", -1), 1, Vector2(1, 0))
	check(a.aggro and b.aggro, "a hit wakes the monster and its neighbour")


func test_rarity_table() -> void:
	print("Card rarity table (power score):")
	for c in SkillDB.all_cards():
		print("  %-18s %5.2f  %s" % [SkillDB.display_name(c.skill, c.rank), SkillDB.power_score(c.skill, c.rank), SkillDB.rarity_name(c.skill, c.rank)])
	check(SkillDB.rarity("defend", -1) == 0, "defend is common")
	check(SkillDB.rarity("final_slash", 3) == 3, "final slash S is epic")
	for sid in SkillDB.SKILLS:
		if not SkillDB.has_ranks(sid):
			continue
		for r in range(1, 4):
			check(SkillDB.rarity(sid, r) >= SkillDB.rarity(sid, r - 1), "%s rarity never drops with rank" % sid)


func test_card_rewards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var h := {"id": 1, "name": "T", "cls": "knight", "level": 1, "xp": 0, "runs": 0, "kills": 0,
		"deck": HeroDB.get_def("knight").starter_deck.duplicate(), "collection": HeroDB.get_def("knight").starter_deck.duplicate()}
	for cls in HeroDB.CLASSES:
		var n := 0
		for k in HeroDB.get_def(cls).starter_deck:
			n += HeroDB.get_def(cls).starter_deck[k]
		check(n == 30, "%s starter deck is 30 cards (%d)" % [cls, n])
		check(not HeroDB.get_def(cls).skills.has("attack"), "%s: attack is built in, not a card" % cls)
	var low := [0, 0, 0, 0]
	var high := [0, 0, 0, 0]
	for i in 400:
		low[_save.roll_rarity(2, rng)] += 1
		high[_save.roll_rarity(12, rng)] += 1
	check(low[0] > high[0], "commons likelier at low dungeon level")
	check(high[3] > low[3], "epics likelier at high dungeon level")
	for i in 50:
		var key: String = _save.random_card(h, 1 + i % 15, rng)
		var c := SkillDB.parse_key(key)
		check(c.skill in HeroDB.get_def("knight").skills, "reward card %s is usable by the class" % key)
	_save.grant_card(h, "bash:2")
	check(not _save.add_to_deck(h, "bash:2"), "a full deck refuses another card")
	check(_save.remove_from_deck(h, "bash:0") and _save.add_to_deck(h, "bash:2"), "swap a card in after removing one")
	# Migration of an old save that still had Attack cards.
	var old := {"id": 2, "name": "Old", "cls": "warrior", "level": 1, "xp": 0, "runs": 0, "kills": 0,
		"deck": {"attack:-1": 12, "defend:-1": 7, "grab:-1": 5, "whirlwind:0": 3, "final_slash:0": 3},
		"collection": {"attack:-1": 12, "defend:-1": 7, "grab:-1": 5, "whirlwind:0": 3, "final_slash:0": 3}}
	_save.data = _save._default_data()
	_save.data.heroes.append(old)
	_save.save_path = "user://test_migrate.json"
	_save.save_game()
	_save.load_game()
	var mh: Dictionary = _save.data.heroes[0]
	check(not mh.deck.has("attack:-1"), "migration drops attack cards")
	check(_save.deck_size(mh) == 30, "migration tops the deck back up to 30 (%d)" % _save.deck_size(mh))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_migrate.json"))


func test_skill_table_integrity() -> void:
	for sid in SkillDB.SKILLS:
		var def := SkillDB.get_def(sid)
		for c in def.chains:
			check(SkillDB.SKILLS.has(c), "chain target %s of %s exists" % [c, sid])
		for r in range(0, 4):
			var d := SkillDB.describe(sid, r)
			check(not d.contains("{"), "%s description fully formatted: %s" % [sid, d])
	check(not SkillDB.SKILLS.has("shield_charge"), "shield charge is left out by design")
	for cls in HeroDB.CLASSES:
		for s in HeroDB.get_def(cls).skills:
			check(SkillDB.SKILLS.has(s), "class %s skill %s exists" % [cls, s])
		for key in HeroDB.get_def(cls).starter_deck:
			check(SkillDB.parse_key(key).skill in HeroDB.get_def(cls).skills, "starter card %s belongs to %s" % [key, cls])
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


## Full dungeons with a scripted hero against the monster brains.
func test_ai_fuzz() -> void:
	var wins := 0
	var games := 24
	var total_time := 0.0
	for gi in games:
		var sim := BattleSim.new(500 + gi)
		var dm := DMAI.new(sim.rng)
		var classes := ["warrior", "knight", "mage"]
		var cls: String = classes[gi % 3]
		var h := {"id": 1, "name": cls, "cls": cls, "level": 1 + gi % 4, "xp": 0, "runs": 0, "kills": 0,
			"deck": HeroDB.get_def(cls).starter_deck.duplicate(), "collection": {}}
		var hero: Actor = _save.make_actor(h)
		var deck: Array = _save.deck_cards(h)
		for c in deck:
			if SkillDB.has_ranks(c.skill):
				c.rank = gi % 4
		sim.generate(hero, dm.choose_monsters(2 + gi % 6, 1 + gi % 4), 12)
		sim.setup_deck(hero, deck)
		for m in sim.living(Actor.TEAM_MONSTERS):
			check(sim.map.connected(hero.pos, m.pos), "monster %s reachable from spawn" % m.name)
		var t := 0.0
		var decide := 0.0
		while sim.winner() < 0 and t < 150.0:
			sim.tick(0.1)
			t += 0.1
			decide -= 0.1
			if decide <= 0.0 and hero.alive:
				decide = 0.5
				if hero.loaded.is_empty() and not hero.is_charging():
					for c in hero.hand:
						if sim.card_playable(hero, c) and sim.rng.randf() < 0.5:
							sim.play_card(hero, c)
							break
				var e := sim.nearest_enemy(hero)
				if e != null:
					if not hero.loaded.is_empty() and BattleSim.targets_point(hero.loaded.skill):
						sim.command_point(hero, e.pos)
					else:
						sim.command_target(hero, e.id)
			for a in sim.living():
				check(not sim.map.is_blocked_point(a.pos, a.radius * 0.5), "%s stays out of walls at t=%.1f" % [a.name, t])
				check(a.life > 0, "living actors have positive life")
				check(a.stam >= 0.0, "stamina never negative")
			check(hero.hand.size() <= 5, "hand never exceeds 5")
			check(hero.deck.size() + hero.hand.size() + hero.discard.size() == 30, "deck conserves 30 cards")
		total_time += t
		check(sim.winner() >= 0, "game %d finishes within 150s (hero life %d, enemies %d)" % [gi, hero.life, sim.living(Actor.TEAM_MONSTERS).size()])
		if sim.winner() == Actor.TEAM_HEROES:
			wins += 1
	print("AI fuzz: hero won %d/%d runs, avg %.1fs of battle" % [wins, games, total_time / games])
