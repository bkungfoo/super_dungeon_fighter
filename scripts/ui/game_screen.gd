extends Control
## The dungeon run: deploy heroes, then each round plan a move and/or a card
## for every hero and reveal against the AI Dungeon Master.

enum Phase { SPAWN, PLAN, GAME_OVER }

const COLS := 8
const ROWS := 8
const HL_MOVE := Color(0.4, 0.8, 1.0, 0.35)
const HL_TARGET := Color(1.0, 0.45, 0.3, 0.45)
const HL_SPAWN := Color(0.4, 1.0, 0.5, 0.3)

var engine: GameEngine
var ai: DMAI
var board: BoardView
var phase: int = Phase.SPAWN
var orders: Dictionary = {}          # hero unit id -> order (see GameEngine.resolve_round)
var selected: Unit = null
var pending_aim: bool = false        # waiting for a tap on an aim cell
var spawn_queue: Array = []
var dungeon_level: int = 1

var round_label: Label
var hint_label: Label
var info_label: Label
var hand_bar: HBoxContainer
var hand_scroll: ScrollContainer
var confirm_btn: Button
var clear_btn: Button
var log_box: RichTextLabel


func _ready() -> void:
	_build_ui()
	_new_run()


# ------------------------------------------------------------------ setup

func _build_ui() -> void:
	var m := UI.margin(16, 24, 16, 16)
	add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)

	var top := UI.hbox()
	round_label = UI.label("", "HeadingLabel")
	top.add_child(round_label)
	var retreat := UI.button("Retreat", _confirm_retreat, "DangerButton")
	retreat.size_flags_horizontal = 0
	top.add_child(retreat)
	v.add_child(top)

	hint_label = UI.label("", "SmallLabel")
	hint_label.custom_minimum_size.y = 90
	v.add_child(hint_label)

	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(0, 700)
	board.cell_tapped.connect(_on_cell_tapped)
	v.add_child(board)

	var panel := UI.panel()
	var pv := UI.vbox(10)
	panel.add_child(pv)
	info_label = UI.label("", "SmallLabel")
	info_label.custom_minimum_size.y = 80
	pv.add_child(info_label)
	hand_scroll = ScrollContainer.new()
	hand_scroll.custom_minimum_size.y = 120
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_bar = UI.hbox(12)
	hand_scroll.add_child(hand_bar)
	pv.add_child(hand_scroll)
	var row := UI.hbox()
	clear_btn = UI.button("Clear", _clear_selected_order)
	clear_btn.size_flags_horizontal = 0
	row.add_child(clear_btn)
	confirm_btn = UI.button("Reveal", _on_confirm, "PrimaryButton")
	row.add_child(confirm_btn)
	pv.add_child(row)
	v.add_child(panel)

	log_box = RichTextLabel.new()
	log_box.custom_minimum_size.y = 230
	log_box.scroll_following = true
	log_box.bbcode_enabled = true
	v.add_child(log_box)


func _new_run() -> void:
	engine = GameEngine.new(COLS, ROWS)
	engine.hidden_team = Unit.TEAM_MONSTERS
	engine.log_msg.connect(_on_log)
	ai = DMAI.new(engine.rng)
	var budget: int = Session.dm_budget()
	dungeon_level = Session.dungeon_level()
	var monsters := ai.choose_monsters(budget, Save.dm_level())
	ai.build_dungeon(engine, monsters, engine.rng.randi_range(4, 8))
	for id in Session.party_ids:
		var h: Dictionary = Save.hero_by_id(id)
		if h.is_empty():
			continue
		var u := engine.add_unit(Save.make_unit(h))
		engine.setup_deck(u, Save.deck_cards(h))
		spawn_queue.append(u)
	if spawn_queue.is_empty():
		UI.go("res://scenes/town.tscn")
		return
	board.bind(engine)
	var names: Array[String] = []
	for u in engine.living(Unit.TEAM_MONSTERS):
		names.append(u.name)
	_on_log("Dungeon level %d. The Dark Lord (level %d, %d points) summons: %s." % [dungeon_level, Save.dm_level(), budget, ", ".join(names)])
	_on_log("Place your heroes on the green cells.")
	_set_phase(Phase.SPAWN)


# ------------------------------------------------------------------ phases

func _set_phase(p: int) -> void:
	phase = p
	selected = null
	pending_aim = false
	board.selected_id = -1
	board.highlights = {}
	board.plan_labels = {}
	board.move_arrows = {}
	board.aim_marks = {}
	match phase:
		Phase.SPAWN:
			_spawn_highlights()
			confirm_btn.visible = false
			clear_btn.visible = false
			hand_scroll.visible = false
			round_label.text = "Deployment"
		Phase.PLAN:
			orders = {}
			confirm_btn.visible = true
			confirm_btn.text = "Reveal"
			clear_btn.visible = true
			hand_scroll.visible = true
			round_label.text = "Round %d" % engine.round_no
			_auto_select_next()
		Phase.GAME_OVER:
			confirm_btn.visible = false
			clear_btn.visible = false
			hand_scroll.visible = false
	_refresh()


func _spawn_highlights() -> void:
	board.highlights = {}
	for y in range(ROWS - 2, ROWS):
		for x in COLS:
			var c := Vector2i(x, y)
			if engine.is_free(c):
				board.highlights[c] = HL_SPAWN


func _needs_order(u: Unit) -> bool:
	if orders.has(u.id):
		return false
	return engine.can_move(u) or engine.can_play(u) or engine.is_ready(u)


func _auto_select_next() -> void:
	for u in engine.living(Unit.TEAM_HEROES):
		if _needs_order(u):
			_select(u)
			return


func _begin_round() -> void:
	engine.start_round()
	_set_phase(Phase.PLAN)


func _check_game_over() -> bool:
	var w := engine.winner()
	if w < 0:
		return false
	_finish(w == Unit.TEAM_HEROES)
	return true


func _finish(heroes_won: bool) -> void:
	_set_phase(Phase.GAME_OVER)
	var lines := Save.apply_run(engine, heroes_won, dungeon_level)
	Session.last_result_lines = lines
	Session.last_result_won = heroes_won
	var md := UI.modal(self, "VICTORY!" if heroes_won else "DEFEAT")
	md.vbox.add_child(UI.label("The dungeon is cleared. Each hero draws a new card from the loot." if heroes_won else "The party has fallen. They will recover in town.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	for line in lines:
		md.vbox.add_child(UI.label(line, "SmallLabel"))
	md.vbox.add_child(UI.button("Return to Town", func(): UI.go("res://scenes/town.tscn"), "PrimaryButton"))


func _confirm_retreat() -> void:
	if phase == Phase.GAME_OVER:
		return
	var md := UI.modal(self, "Retreat from the dungeon?")
	md.vbox.add_child(UI.label("Heroes keep XP from kills, but there is no card reward and the Dark Lord grows from the damage dealt.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox()
	row.add_child(UI.button("Keep fighting", func(): md.overlay.queue_free()))
	row.add_child(UI.button("Retreat", func():
		md.overlay.queue_free()
		_finish(false), "DangerButton"))
	md.vbox.add_child(row)


# ------------------------------------------------------------------ planning

## Where the selected hero will be when its skill fires.
func _from_pos(u: Unit) -> Vector2i:
	var o: Dictionary = orders.get(u.id, {})
	return o.get("move", u.pos)


func _order(u: Unit) -> Dictionary:
	if not orders.has(u.id):
		orders[u.id] = {}
	return orders[u.id]


## The skill this hero will fire this round (card picked or charged skill), if any.
func _firing_skill(u: Unit) -> Dictionary:
	if engine.is_ready(u):
		return {"skill": u.loading.skill, "rank": u.loading.rank}
	var o: Dictionary = orders.get(u.id, {})
	if o.has("skill"):
		return {"skill": o.skill, "rank": o.rank}
	return {}


func _needs_aim(u: Unit) -> bool:
	var f := _firing_skill(u)
	if f.is_empty():
		return false
	var target: String = SkillDB.get_def(f.skill).target
	if target == "self":
		return false
	var o: Dictionary = orders.get(u.id, {})
	return not (o.has("aim_dir") or o.has("aim_cell"))


func _show_move_highlights(u: Unit) -> void:
	board.highlights = {}
	if not engine.can_move(u):
		return
	var f := _firing_skill(u)
	if not f.is_empty() and not engine.is_ready(u) and SkillDB.params(f.skill, f.rank).get("load", 0) > 0:
		return  # charge-up cards are played standing still
	for c in engine.movement_options(u):
		board.highlights[c] = HL_MOVE


func _show_aim_highlights(u: Unit) -> void:
	board.highlights = {}
	var f := _firing_skill(u)
	if f.is_empty():
		return
	for c in engine.skill_targets(u, f.skill, f.rank, _from_pos(u)):
		board.highlights[c] = HL_TARGET
	pending_aim = true


func _select(u: Unit) -> void:
	selected = u
	pending_aim = false
	board.selected_id = u.id if u != null else -1
	board.highlights = {}
	if u != null and u.is_hero() and phase == Phase.PLAN:
		if _needs_aim(u):
			_show_aim_highlights(u)
		else:
			_show_move_highlights(u)
	_refresh()


func _on_cell_tapped(cell: Vector2i) -> void:
	match phase:
		Phase.SPAWN:
			_spawn_tap(cell)
		Phase.PLAN:
			_plan_tap(cell)


func _spawn_tap(cell: Vector2i) -> void:
	if not board.highlights.has(cell) or spawn_queue.is_empty():
		return
	var u: Unit = spawn_queue.pop_front()
	u.pos = cell
	board._anim_pos[u.id] = Vector2(cell)
	if spawn_queue.is_empty():
		_begin_round()
	else:
		_spawn_highlights()
		_refresh()


func _plan_tap(cell: Vector2i) -> void:
	var u := engine.unit_at(cell)
	if pending_aim and selected != null and board.highlights.has(cell):
		_set_aim(selected, cell)
		return
	if u != null and u != selected:
		_select(u)
		return
	if selected == null or not selected.is_hero():
		return
	if u == selected:
		# Tap yourself: cancel the planned move.
		var o := _order(selected)
		if o.has("move"):
			o.erase("move")
			board.move_arrows.erase(selected.id)
			_after_move_change(selected)
		else:
			_select(selected)
		return
	if board.highlights.has(cell) and not pending_aim:
		_order(selected).move = cell
		board.move_arrows[selected.id] = cell
		_after_move_change(selected)


## A move changes where skills fire from, so any aim has to be redone.
func _after_move_change(u: Unit) -> void:
	var o := _order(u)
	o.erase("aim_dir")
	o.erase("aim_cell")
	board.aim_marks.erase(u.id)
	_update_plan_label(u)
	if _needs_aim(u):
		_show_aim_highlights(u)
		_refresh()
	else:
		_advance_or_keep(u)


func _set_aim(u: Unit, cell: Vector2i) -> void:
	var f := _firing_skill(u)
	var o := _order(u)
	var from := _from_pos(u)
	match SkillDB.get_def(f.skill).target:
		"dir":
			o.aim_dir = GameEngine.dir_to(from, cell)
			board.aim_marks[u.id] = from + o.aim_dir
		_:
			o.aim_cell = cell
			board.aim_marks[u.id] = cell
	pending_aim = false
	_update_plan_label(u)
	_advance_or_keep(u)


func _on_card_pressed(card: Dictionary) -> void:
	if selected == null or not selected.is_hero() or phase != Phase.PLAN:
		return
	var u := selected
	var o := _order(u)
	o.skill = card.skill
	o.rank = card.rank
	o.erase("aim_dir")
	o.erase("aim_cell")
	board.aim_marks.erase(u.id)
	var p := SkillDB.params(card.skill, card.rank)
	if p.get("load", 0) > 0 and o.has("move"):
		o.erase("move")
		board.move_arrows.erase(u.id)
	_update_plan_label(u)
	if _needs_aim(u):
		_show_aim_highlights(u)
		_refresh()
	else:
		_advance_or_keep(u)


func _update_plan_label(u: Unit) -> void:
	var o: Dictionary = orders.get(u.id, {})
	var parts: Array[String] = []
	if o.has("move"):
		parts.append("Move")
	var f := _firing_skill(u)
	if not f.is_empty():
		parts.append(SkillDB.get_def(f.skill).name)
	if parts.is_empty():
		board.plan_labels.erase(u.id)
	else:
		board.plan_labels[u.id] = " + ".join(parts)


## After finishing one hero's plan, jump to the next undecided hero.
func _advance_or_keep(u: Unit) -> void:
	var prev := selected
	selected = null
	_auto_select_next()
	if selected == null:
		_select(prev)


func _clear_selected_order() -> void:
	if selected == null:
		return
	orders.erase(selected.id)
	board.move_arrows.erase(selected.id)
	board.plan_labels.erase(selected.id)
	board.aim_marks.erase(selected.id)
	pending_aim = false
	_select(selected)


func _on_confirm() -> void:
	if phase != Phase.PLAN:
		return
	var all := ai.orders(engine, Unit.TEAM_MONSTERS)
	for id in orders:
		if not orders[id].is_empty():
			all[id] = orders[id]
	engine.resolve_round(all)
	if _check_game_over():
		return
	_begin_round()


# ------------------------------------------------------------------ display

func _on_log(text: String) -> void:
	if text.begins_with("---"):
		log_box.append_text("\n[color=#f9c24d][b]%s[/b][/color]\n" % text)
	else:
		log_box.append_text("%s\n" % text)


func _refresh() -> void:
	board.queue_redraw()
	_refresh_hint()
	_refresh_info()
	_refresh_hand()


func _refresh_hint() -> void:
	match phase:
		Phase.SPAWN:
			if not spawn_queue.is_empty():
				hint_label.text = "Deploy %s: tap a green cell." % spawn_queue[0].name
		Phase.PLAN:
			var pending := 0
			for u in engine.living(Unit.TEAM_HEROES):
				if _needs_order(u):
					pending += 1
			if selected != null and selected.is_hero():
				var f := _firing_skill(selected)
				if pending_aim:
					hint_label.text = "Aim %s: tap a red cell. (%d undecided)" % [SkillDB.get_def(f.skill).name, pending]
				elif engine.is_ready(selected):
					hint_label.text = "%s is charged! Move (blue) first if you like; it fires after the move." % SkillDB.get_def(f.skill).name
				elif not f.is_empty() and SkillDB.params(f.skill, f.rank).get("load", 0) > 0:
					hint_label.text = "%s will be played face down. No moving this turn. (%d undecided)" % [SkillDB.get_def(f.skill).name, pending]
				else:
					hint_label.text = "Tap a blue cell to move and/or a card to play. Tap %s to stay. (%d undecided)" % [selected.name, pending]
			else:
				hint_label.text = "Tap a hero to plan. Reveal when everyone is set; monsters act at the same time."
		Phase.GAME_OVER:
			hint_label.text = ""


func _refresh_info() -> void:
	if selected == null or not selected.alive:
		info_label.text = ""
		return
	var u := selected
	var kind: String = HeroDB.get_def(u.cls).name if u.is_hero() else "Monster, worth %d" % u.summon_value
	var line := "%s (%s)  Life %d/%d  Stam %d/%d  Atk %d  Move %d" % [u.name, kind, u.life, u.max_life, u.stam, u.max_stam, u.attack, u.move]
	var st: String = u.short_status()
	if st != "":
		line += "   " + st
	if u.is_hero():
		line += "\nDeck %d  Hand %d  Discard %d" % [u.deck.size(), u.hand.size(), u.discard.size()]
		var o: Dictionary = orders.get(u.id, {})
		if o.has("move") or o.has("skill") or engine.is_ready(u):
			line += "   Plan: " + board.plan_labels.get(u.id, "")
	elif u.loading.is_empty():
		var names: Array[String] = []
		for s in u.skills:
			names.append(SkillDB.get_def(s).name)
		line += "\nKnows: " + ", ".join(names)
	info_label.text = line


func _refresh_hand() -> void:
	UI.clear_children(hand_bar)
	if phase != Phase.PLAN or selected == null or not selected.is_hero():
		return
	var u := selected
	if engine.is_ready(u):
		hand_bar.add_child(UI.label("%s fires this round." % SkillDB.display_name(u.loading.skill, u.loading.rank), "DimLabel"))
		return
	if not engine.can_play(u):
		hand_bar.add_child(UI.label("%s cannot play a card this round (%s)." % [u.name, u.short_status()], "DimLabel"))
		return
	var o: Dictionary = orders.get(u.id, {})
	for card in u.hand:
		var p := SkillDB.params(card.skill, card.rank)
		var txt := SkillDB.display_name(card.skill, card.rank)
		var bits: Array[String] = []
		if p.cost > 0:
			bits.append("%d st" % p.cost)
		if p.get("life_cost", 0) > 0:
			bits.append("%d life" % p.life_cost)
		if p.get("load", 0) > 0:
			bits.append("load %d" % p.load)
		if engine.is_chain_available(u, card.skill):
			txt = "CHAIN " + txt
		txt += "\n" + (", ".join(bits) if not bits.is_empty() else "free")
		var b := Button.new()
		b.text = txt
		b.theme_type_variation = "SkillButton"
		b.disabled = not engine.card_playable(u, card)
		b.custom_minimum_size.x = 200
		b.tooltip_text = SkillDB.describe(card.skill, card.rank)
		if o.get("skill", "") == card.skill and o.get("rank", -2) == card.rank:
			b.add_theme_color_override("font_color", UI.ACCENT)
		b.pressed.connect(_on_card_pressed.bind(card))
		hand_bar.add_child(b)
	var help := Button.new()
	help.text = "?"
	help.theme_type_variation = "SkillButton"
	help.custom_minimum_size.x = 90
	help.pressed.connect(_show_hand_help.bind(u))
	hand_bar.add_child(help)


func _show_hand_help(u: Unit) -> void:
	var md := UI.modal(self, "%s's hand" % u.name)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 1000)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(10)
	scroll.add_child(v)
	for card in u.hand:
		var def := SkillDB.get_def(card.skill)
		var title := UI.label("%s  (%s, priority %d)" % [SkillDB.display_name(card.skill, card.rank), SkillDB.rarity_name(card.skill, card.rank), SkillDB.params(card.skill, card.rank).get("priority", 0)])
		title.add_theme_color_override("font_color", SkillDB.RARITY_COLORS[SkillDB.rarity(card.skill, card.rank)])
		v.add_child(title)
		v.add_child(UI.label(SkillDB.describe(card.skill, card.rank), "DimLabel"))
		if not def.chains.is_empty():
			var names: Array[String] = []
			for c in def.chains:
				names.append(SkillDB.get_def(c).name)
			v.add_child(UI.label("Chains into: " + ", ".join(names), "SmallLabel"))
	md.vbox.add_child(scroll)
	md.vbox.add_child(UI.button("Close", func(): md.overlay.queue_free()))
