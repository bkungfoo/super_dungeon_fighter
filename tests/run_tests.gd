extends SceneTree
## Headless rules tests + AI-vs-AI fuzzing.
## Run:  godot --headless --path . -s tests/run_tests.gd

var failures: int = 0
var checks: int = 0
# Autoloads are not instantiated for -s scripts, so build the save helper by hand.
var _save: Node = load("res://scripts/core/save_data.gd").new()

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const RIGHT := Vector2i(1, 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


## A hero that plays straight from a skill list (no deck) to keep tests simple.
func _hero(cls: String, pos: Vector2i, extra_skills: Dictionary = {}) -> Unit:
	var h := {"id": 1, "name": cls.capitalize(), "cls": cls, "level": 1, "xp": 0, "runs": 0, "kills": 0, "deck": {}, "collection": {}}
	var u: Unit = _save.make_unit(h)
	u.pos = pos
	for s in HeroDB.get_def(cls).skills:
		if SkillDB.has_ranks(s):
			continue
		u.skills[s] = -1
	for s in extra_skills:
		u.skills[s] = extra_skills[s]
	return u


func _monster(key: String, pos: Vector2i) -> Unit:
	var u := MonsterDB.make_unit(key)
	u.pos = pos
	return u


func _engine() -> GameEngine:
	return GameEngine.new(8, 8, 42)


## One full round with the given orders.
func _round(e: GameEngine, orders: Dictionary) -> void:
	e.start_round()
	e.resolve_round(orders)


func _card(sid: String, rank: int, aim_dir: Vector2i = Vector2i.ZERO) -> Dictionary:
	var o := {"skill": sid, "rank": rank}
	if aim_dir != Vector2i.ZERO:
		o.aim_dir = aim_dir
	return o


func _initialize() -> void:
	print("Running Super Dungeon Fighter rules tests...")
	test_attack_stun_and_recovery()
	test_move_and_instant_skill_same_turn()
	test_charge_up_card_locks_movement()
	test_charged_skill_moves_then_fires()
	test_load_immobile()
	test_priority_interrupts_slow_skill()
	test_stun_then_stun_is_down()
	test_down_then_hit_is_reset()
	test_defend_parries_attack()
	test_grab_beats_defend_and_loses_to_attack()
	test_stun_interrupts_loading()
	test_full_swing_knockback_and_chain()
	test_final_slash_dash()
	test_fireball_friendly_fire()
	test_movement_conflict()
	test_deck_draw_and_reshuffle()
	test_rarity_table()
	test_card_rewards()
	test_skill_table_integrity()
	test_all_scripts_parse()
	test_ai_vs_ai_fuzz()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_attack_stun_and_recovery() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 2)))
	_round(e, {h.id: _card("attack", -1, UP)})
	check(g.life == 12 - 6, "attack deals x1 damage (got %d)" % g.life)
	check(g.state == Unit.State.STUNNED and g.tokens == 1, "attack stuns; one token left after the tick (tokens=%d)" % g.tokens)
	check(h.stam == 10, "attack costs 1 stamina, then regen refills it")
	e.start_round()
	check(e.playable_cards(g).is_empty(), "stunned unit cannot play")
	check(not e.can_move(g), "stunned unit cannot move")
	e.resolve_round({})
	check(g.state == Unit.State.ACTIVE, "stun 1 wears off after one skipped round")


func test_move_and_instant_skill_same_turn() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 5)))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 2)))
	_round(e, {h.id: {"move": Vector2i(3, 3), "skill": "attack", "rank": -1, "aim_dir": UP}})
	check(h.pos == Vector2i(3, 3), "hero moved before attacking")
	check(g.life == 6, "attack landed from the destination (life %d)" % g.life)


func test_charge_up_card_locks_movement() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 5), {"bash": 0}))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 1)))
	_round(e, {h.id: {"move": Vector2i(3, 3), "skill": "bash", "rank": 0, "aim_dir": UP}})
	check(h.pos == Vector2i(3, 5), "playing a charge-up card means standing still")
	check(not h.loading.is_empty(), "bash is loading")
	check(e.can_move(h), "bash (no immobile flag) allows moving while it charges")


func test_charged_skill_moves_then_fires() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 5), {"bash": 1}))
	var g := e.add_unit(_monster("ogre", Vector2i(3, 2)))
	_round(e, {h.id: _card("bash", 1, UP)})
	e.start_round()
	check(e.is_ready(h), "bash is ready one round later")
	check(e.playable_cards(h).is_empty(), "cannot play another card while a skill is charged")
	e.resolve_round({h.id: {"move": Vector2i(3, 3), "aim_dir": UP}})
	check(h.pos == Vector2i(3, 3), "moved before firing")
	check(h.loading.is_empty(), "bash fired")
	check(g.life == g.max_life - 5, "bash deals x1 damage after the move (life %d)" % g.life)
	check(g.state == Unit.State.STUNNED and g.tokens == 3, "bash rank B stuns 3 (tokens=%d)" % g.tokens)
	check(h.cooldown == 2, "cooldown 2 remains after the tick (got %d)" % h.cooldown)
	e.start_round()
	var ids: Array = []
	for c in e.playable_cards(h):
		ids.append(c.skill)
	check("attack" in ids, "chain: attack is available during cooldown")
	check(not ("grab" in ids), "non-chained skills blocked by cooldown")


func test_load_immobile() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(1, 4), {"final_slash": 0}))
	_round(e, {h.id: _card("final_slash", 0, RIGHT)})
	e.start_round()
	check(not e.can_move(h), "final slash is immobile while loading")
	e.resolve_round({h.id: {"move": Vector2i(1, 3)}})
	check(h.pos == Vector2i(1, 4), "the move was refused while immobile")
	e.start_round()
	check(e.is_ready(h) and e.can_move(h), "once charged the unit may move again")


func test_priority_interrupts_slow_skill() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 3), {"full_swing": 0}))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 2)))
	_round(e, {h.id: _card("full_swing", 0, UP)})
	_round(e, {})
	e.start_round()
	check(e.is_ready(h), "full swing charged after 2 rounds")
	e.resolve_round({h.id: {"aim_dir": UP}, g.id: _card("attack", -1, DOWN)})
	check(h.state == Unit.State.STUNNED, "goblin's attack (priority 5) lands first")
	check(g.life == 12 and g.state == Unit.State.ACTIVE, "full swing (priority 1) was interrupted")


func test_stun_then_stun_is_down() -> void:
	var e := _engine()
	var h1 := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var h2 := e.add_unit(_hero("warrior", Vector2i(2, 2)))
	var g := e.add_unit(_monster("ogre", Vector2i(3, 2)))
	_round(e, {h1.id: _card("attack", -1, UP), h2.id: _card("attack", -1, RIGHT)})
	check(g.state == Unit.State.DOWN, "two simultaneous stuns knock down")
	check(g.tokens == 1, "simultaneous stuns use max(X, Y) = 1 (tokens=%d after tick)" % g.tokens)


func test_down_then_hit_is_reset() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("ogre", Vector2i(3, 2)))
	_round(e, {h.id: _card("grab", -1, UP)})
	check(g.state == Unit.State.DOWN, "grab knocks down")
	_round(e, {h.id: _card("attack", -1, UP)})
	check(g.state == Unit.State.ACTIVE, "hitting a downed unit resets it to active")
	check(g.resist > 0, "reset grants stun immunity")
	e.start_round()
	check(e.has_initiative(g), "initiative applies in the following round")
	e.resolve_round({h.id: _card("attack", -1, UP)})
	check(g.state == Unit.State.ACTIVE, "reset unit shrugs off stun")


func test_defend_parries_attack() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("orc", Vector2i(3, 2)))
	_round(e, {h.id: _card("attack", -1, UP), g.id: _card("defend", -1)})
	check(g.life == g.max_life, "defend blocks attack damage")
	check(h.state == Unit.State.STUNNED, "attacking a defender gets parried")
	check(g.state == Unit.State.ACTIVE, "defender is not stunned")


func test_grab_beats_defend_and_loses_to_attack() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g := e.add_unit(_monster("orc", Vector2i(3, 2)))
	_round(e, {h.id: _card("grab", -1, UP), g.id: _card("defend", -1)})
	check(g.state == Unit.State.DOWN, "grab goes through defend")
	check(g.life == g.max_life - 3, "grab deals half damage (got %d)" % g.life)
	var e2 := _engine()
	var h2 := e2.add_unit(_hero("warrior", Vector2i(3, 3)))
	var g2 := e2.add_unit(_monster("orc", Vector2i(3, 2)))
	_round(e2, {h2.id: _card("grab", -1, UP), g2.id: _card("attack", -1, DOWN)})
	check(g2.state == Unit.State.ACTIVE, "attack breaks grab (grabber does not land it)")
	check(h2.state == Unit.State.STUNNED, "the attack still lands on the grabber")


func test_stun_interrupts_loading() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 3), {"full_swing": 0}))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 2)))
	_round(e, {h.id: _card("full_swing", 0, UP), g.id: _card("attack", -1, DOWN)})
	check(h.loading.is_empty(), "being stunned interrupts a loading skill")
	check(h.state == Unit.State.STUNNED, "hero is stunned")


func test_full_swing_knockback_and_chain() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("knight", Vector2i(3, 5), {"full_swing": 0, "whirlwind": 0}))
	var g := e.add_unit(_monster("goblin", Vector2i(3, 4)))
	e.grid.walls[Vector2i(3, 2)] = true
	_round(e, {h.id: _card("full_swing", 0, UP)})
	e.start_round()
	check(h.loading.counters == 1 and not e.is_ready(h), "full swing needs 2 load counters")
	e.resolve_round({})
	e.start_round()
	check(e.is_ready(h), "full swing ready on round 3")
	e.resolve_round({h.id: {"aim_dir": UP}})
	check(g.life == 12 - 10 - 2, "x2 damage plus 2 for the blocked knockback cell (got %d)" % g.life)
	check(g.pos == Vector2i(3, 3), "knocked back one cell into the wall (pos %s)" % str(g.pos))
	check(g.state == Unit.State.DOWN, "full swing knocks down")
	check(h.immobile == 2 and h.cooldown == 2, "cooldown/immobile set")
	e.start_round()
	var ids: Array = []
	for c in e.playable_cards(h):
		ids.append(c.skill)
	check("whirlwind" in ids, "whirlwind chains from full swing despite cooldown")
	check("defend" in ids, "defend chains from full swing")
	check(not ("attack" in ids), "attack does not chain from full swing")


func test_final_slash_dash() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(1, 4), {"final_slash": 0}))
	var g1 := e.add_unit(_monster("goblin", Vector2i(2, 4)))
	var g2 := e.add_unit(_monster("goblin", Vector2i(4, 4)))
	_round(e, {h.id: _card("final_slash", 0, RIGHT)})
	_round(e, {})
	_round(e, {h.id: {"aim_dir": RIGHT}})
	check(h.pos == Vector2i(5, 4), "dashed to the end of the lane (pos %s)" % str(h.pos))
	check(g1.life == 0, "first goblin takes 2 hits (life %d)" % g1.life)
	check(g2.life == 12 - 6, "second goblin takes 1 hit (life %d)" % g2.life)


func test_fireball_friendly_fire() -> void:
	var e := _engine()
	var m := e.add_unit(_hero("mage", Vector2i(2, 1), {"fireball": 0}))
	var w := e.add_unit(_hero("warrior", Vector2i(4, 4)))
	var g := e.add_unit(_monster("goblin", Vector2i(4, 3)))
	check(Vector2i(4, 3) in e.skill_targets(m, "fireball", 0, m.pos), "fireball reaches range 4")
	_round(e, {m.id: {"skill": "fireball", "rank": 0, "aim_cell": Vector2i(4, 3)}})
	_round(e, {m.id: {"aim_cell": Vector2i(4, 3)}, g.id: _card("defend", -1)})
	check(g.life == 12 - 8, "fireball x2 ignores defend (life %d)" % g.life)
	check(w.life == w.max_life - 8, "fireball burns allies in the blast")


func test_movement_conflict() -> void:
	var e := _engine()
	var a := e.add_unit(_hero("warrior", Vector2i(0, 0)))
	var b := e.add_unit(_monster("goblin", Vector2i(2, 0)))
	_round(e, {a.id: {"move": Vector2i(1, 0)}, b.id: {"move": Vector2i(1, 0)}})
	check(a.pos != b.pos, "two units cannot share a cell")
	check(a.pos == Vector2i(1, 0) or b.pos == Vector2i(1, 0), "one of them gets the contested cell")
	var opts := e.movement_options(a)
	check(not opts.has(b.pos), "cannot move onto an occupied cell")


func test_deck_draw_and_reshuffle() -> void:
	var e := _engine()
	var h := e.add_unit(_hero("warrior", Vector2i(3, 3)))
	var cards: Array = []
	for i in 30:
		cards.append({"skill": "attack", "rank": -1})
	e.setup_deck(h, cards)
	check(h.hand.size() == 5 and h.deck.size() == 25, "opening hand of 5 (hand %d, deck %d)" % [h.hand.size(), h.deck.size()])
	_round(e, {h.id: _card("attack", -1, UP)})
	check(h.hand.size() == 5 and h.deck.size() == 24 and h.discard.size() == 1, "played card is discarded and the hand refills")
	for i in 30:
		_round(e, {h.id: _card("attack", -1, UP)})
	check(h.hand.size() == 5, "hand stays at 5 after reshuffling the discard pile")
	check(h.deck.size() + h.hand.size() + h.discard.size() == 30, "no cards are lost")
	var e2 := _engine()
	var h2 := e2.add_unit(_hero("warrior", Vector2i(3, 3)))
	e2.setup_deck(h2, [{"skill": "defend", "rank": -1}])
	_round(e2, {h2.id: _card("attack", -1, UP)})
	check(h2.discard.is_empty(), "a card not in hand cannot be played")


func test_rarity_table() -> void:
	print("Card rarity table (power score):")
	for c in SkillDB.all_cards():
		print("  %-18s %5.2f  %s" % [SkillDB.display_name(c.skill, c.rank), SkillDB.power_score(c.skill, c.rank), SkillDB.rarity_name(c.skill, c.rank)])
	check(SkillDB.rarity("attack", -1) == 0, "attack is common")
	check(SkillDB.rarity("defend", -1) == 0, "defend is common")
	check(SkillDB.rarity("final_slash", 3) == 3, "final slash S is epic")
	check(SkillDB.rarity("full_swing", 3) >= 2, "full swing S is at least rare")
	for sid in SkillDB.SKILLS:
		if not SkillDB.has_ranks(sid):
			continue
		for r in range(1, 4):
			check(SkillDB.rarity(sid, r) >= SkillDB.rarity(sid, r - 1), "%s rarity never drops with rank" % sid)
		check(SkillDB.rarity(sid, 0) <= 1, "%s rank C is common or uncommon" % sid)


func test_card_rewards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var h := {"id": 1, "name": "T", "cls": "knight", "level": 1, "xp": 0, "runs": 0, "kills": 0,
		"deck": HeroDB.get_def("knight").starter_deck.duplicate(), "collection": HeroDB.get_def("knight").starter_deck.duplicate()}
	check(_save.deck_size(h) == 30, "starter decks hold 30 cards")
	for cls in HeroDB.CLASSES:
		var n := 0
		for k in HeroDB.get_def(cls).starter_deck:
			n += HeroDB.get_def(cls).starter_deck[k]
		check(n == 30, "%s starter deck is 30 cards (%d)" % [cls, n])
	var low := [0, 0, 0, 0]
	var high := [0, 0, 0, 0]
	for i in 400:
		low[_save.roll_rarity(2, rng)] += 1
		high[_save.roll_rarity(12, rng)] += 1
	check(low[0] > high[0], "commons are likelier at low dungeon level (%s vs %s)" % [str(low), str(high)])
	check(high[3] > low[3], "epics are likelier at high dungeon level")
	for i in 50:
		var key: String = _save.random_card(h, 1 + i % 15, rng)
		var c := SkillDB.parse_key(key)
		check(c.skill in HeroDB.get_def("knight").skills, "reward card %s is usable by the class" % key)
	_save.grant_card(h, "bash:2")
	check(h.collection["bash:2"] == 1, "granted card lands in the collection")
	check(not _save.add_to_deck(h, "bash:2"), "a full deck refuses another card")
	check(_save.remove_from_deck(h, "attack:-1") and _save.add_to_deck(h, "bash:2"), "swap a card in after removing one")
	check(_save.deck_size(h) == 30, "deck is back to 30")


func test_skill_table_integrity() -> void:
	for sid in SkillDB.SKILLS:
		var def := SkillDB.get_def(sid)
		for c in def.chains:
			check(SkillDB.SKILLS.has(c), "chain target %s of %s exists" % [c, sid])
		for r in range(0, 4):
			var p := SkillDB.params(sid, r)
			check(p.has("cost"), "%s has a cost" % sid)
			check(p.has("priority"), "%s has a priority" % sid)
			var d := SkillDB.describe(sid, r)
			check(not d.contains("{"), "%s description fully formatted: %s" % [sid, d])
	check(not SkillDB.SKILLS.has("shield_charge"), "shield charge is left out by design")
	for cls in HeroDB.CLASSES:
		for s in HeroDB.get_def(cls).skills:
			check(SkillDB.SKILLS.has(s), "class %s skill %s exists" % [cls, s])
		for key in HeroDB.get_def(cls).starter_deck:
			var c := SkillDB.parse_key(key)
			check(c.skill in HeroDB.get_def(cls).skills, "starter card %s belongs to %s" % [key, cls])
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
		for i in 3:
			var cls: String = classes[i]
			var h := {"id": i + 1, "name": cls, "cls": cls, "level": 1 + gi % 3, "xp": 0, "runs": 0, "kills": 0,
				"deck": HeroDB.get_def(cls).starter_deck.duplicate(), "collection": {}}
			# Upgrade some cards so every rank gets exercised.
			var deck: Array = _save.deck_cards(h)
			for c in deck:
				if SkillDB.has_ranks(c.skill):
					c.rank = gi % 4
			var u: Unit = _save.make_unit(h)
			u.pos = Vector2i(2 + i * 2, 7)
			e.add_unit(u)
			e.setup_deck(u, deck)
		var rounds := 0
		while e.winner() < 0 and rounds < 60:
			rounds += 1
			e.start_round()
			var o := ai.orders(e, 0)
			o.merge(ai.orders(e, 1))
			e.resolve_round(o)
			var seen := {}
			for u in e.living():
				check(e.grid.passable(u.pos), "unit %s stands on a passable cell" % u.name)
				check(not seen.has(u.pos), "no two living units share a cell")
				seen[u.pos] = true
				check(u.life > 0, "living units have positive life")
				check(u.stam >= 0, "stamina never negative")
				if u.uses_deck:
					check(u.hand.size() <= 5, "hand never exceeds 5")
					check(u.deck.size() + u.hand.size() + u.discard.size() == 30, "deck conserves 30 cards")
		total_rounds += rounds
		if e.winner() == Unit.TEAM_HEROES:
			hero_wins += 1
		check(e.winner() >= 0, "game %d finishes within 60 rounds" % gi)
	print("AI fuzz: heroes won %d/%d games, avg %.1f rounds" % [hero_wins, games, float(total_rounds) / games])
