extends Control
## The dungeon run: spawn heroes, then alternate planning and reveal phases
## against the AI Dungeon Master.

enum Phase { SPAWN, PLAN_MOVE, PLAN_SKILL, GAME_OVER }

const COLS := 8
const ROWS := 8
const HL_MOVE := Color(0.4, 0.8, 1.0, 0.35)
const HL_TARGET := Color(1.0, 0.45, 0.3, 0.45)
const HL_SPAWN := Color(0.4, 1.0, 0.5, 0.3)

var engine: GameEngine
var ai: DMAI
var board: BoardView
var phase: int = Phase.SPAWN
var move_orders: Dictionary = {}
var skill_orders: Dictionary = {}
var selected: Unit = null
var pending_skill: String = ""
var spawn_queue: Array = []

var round_label: Label
var hint_label: Label
var info_label: Label
var skill_bar: HBoxContainer
var skill_scroll: ScrollContainer
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
	skill_scroll = ScrollContainer.new()
	skill_scroll.custom_minimum_size.y = 120
	skill_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skill_bar = UI.hbox(12)
	skill_scroll.add_child(skill_bar)
	pv.add_child(skill_scroll)
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
	var monsters := ai.choose_monsters(budget, Save.dm_level())
	ai.build_dungeon(engine, monsters, engine.rng.randi_range(4, 8))
	for id in Session.party_ids:
		var h: Dictionary = Save.hero_by_id(id)
		if h.is_empty():
			continue
		spawn_queue.append(engine.add_unit(Save.make_unit(h)))
	if spawn_queue.is_empty():
		UI.go("res://scenes/town.tscn")
		return
	board.bind(engine)
	var names: Array[String] = []
	for u in engine.living(Unit.TEAM_MONSTERS):
		names.append(u.name)
	_on_log("The Dark Lord (level %d, %d points) summons: %s." % [Save.dm_level(), budget, ", ".join(names)])
	_on_log("Place your heroes on the green cells.")
	_set_phase(Phase.SPAWN)


# ------------------------------------------------------------------ phases

func _set_phase(p: int) -> void:
	phase = p
	selected = null
	pending_skill = ""
	board.selected_id = -1
	board.highlights = {}
	board.plan_labels = {}
	board.move_arrows = {}
	match phase:
		Phase.SPAWN:
			_spawn_highlights()
			confirm_btn.visible = false
			clear_btn.visible = false
			skill_scroll.visible = false
			round_label.text = "Deployment"
		Phase.PLAN_MOVE:
			move_orders = {}
			confirm_btn.visible = true
			confirm_btn.text = "Reveal Moves"
			clear_btn.visible = true
			skill_scroll.visible = false
			round_label.text = "Round %d - Move" % engine.round_no
			_auto_select_next()
		Phase.PLAN_SKILL:
			skill_orders = {}
			confirm_btn.visible = true
			confirm_btn.text = "Reveal Skills"
			clear_btn.visible = true
			skill_scroll.visible = true
			round_label.text = "Round %d - Skills" % engine.round_no
			_auto_select_next()
		Phase.GAME_OVER:
			confirm_btn.visible = false
			clear_btn.visible = false
			skill_scroll.visible = false
	_refresh()


func _spawn_highlights() -> void:
	board.highlights = {}
	for y in range(ROWS - 2, ROWS):
		for x in COLS:
			var c := Vector2i(x, y)
			if engine.is_free(c):
				board.highlights[c] = HL_SPAWN


func _auto_select_next() -> void:
	for u in engine.living(Unit.TEAM_HEROES):
		if phase == Phase.PLAN_MOVE and engine.can_move(u) and not move_orders.has(u.id):
			_select(u)
			return
		if phase == Phase.PLAN_SKILL and engine.can_act(u) and not skill_orders.has(u.id):
			_select(u)
			return


func _begin_round() -> void:
	engine.start_round()
	if _check_game_over():
		return
	_set_phase(Phase.PLAN_MOVE)


func _check_game_over() -> bool:
	var w := engine.winner()
	if w < 0:
		return false
	_finish(w == Unit.TEAM_HEROES)
	return true


func _finish(heroes_won: bool) -> void:
	_set_phase(Phase.GAME_OVER)
	var lines := Save.apply_run(engine, heroes_won)
	Session.last_result_lines = lines
	Session.last_result_won = heroes_won
	var md := UI.modal(self, "VICTORY!" if heroes_won else "DEFEAT")
	md.vbox.add_child(UI.label("The dungeon is cleared. The towns of Halud are safe for now." if heroes_won else "The party has fallen. They will recover in town.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	for line in lines:
		md.vbox.add_child(UI.label(line, "SmallLabel"))
	md.vbox.add_child(UI.button("Return to Town", func(): UI.go("res://scenes/town.tscn"), "PrimaryButton"))


func _confirm_retreat() -> void:
	if phase == Phase.GAME_OVER:
		return
	var md := UI.modal(self, "Retreat from the dungeon?")
	md.vbox.add_child(UI.label("Heroes keep XP from kills, but there is no clear bonus and the Dark Lord grows from the damage dealt.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox()
	row.add_child(UI.button("Keep fighting", func(): md.overlay.queue_free()))
	row.add_child(UI.button("Retreat", func():
		md.overlay.queue_free()
		_finish(false), "DangerButton"))
	md.vbox.add_child(row)


# ------------------------------------------------------------------ input

func _on_cell_tapped(cell: Vector2i) -> void:
	match phase:
		Phase.SPAWN:
			_spawn_tap(cell)
		Phase.PLAN_MOVE:
			_move_tap(cell)
		Phase.PLAN_SKILL:
			_skill_tap(cell)


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


func _select(u: Unit) -> void:
	selected = u
	pending_skill = ""
	board.selected_id = u.id if u != null else -1
	board.highlights = {}
	if u != null and u.is_hero():
		if phase == Phase.PLAN_MOVE and engine.can_move(u):
			for c in engine.movement_options(u):
				board.highlights[c] = HL_MOVE
	_refresh()


func _move_tap(cell: Vector2i) -> void:
	var u := engine.unit_at(cell)
	if u != null and u != selected:
		_select(u)
		return
	if selected == null or not selected.is_hero():
		return
	if u == selected:
		move_orders.erase(selected.id)
		board.move_arrows.erase(selected.id)
		_refresh()
		return
	if board.highlights.has(cell):
		move_orders[selected.id] = cell
		board.move_arrows[selected.id] = cell
		_auto_select_next_or_keep()


func _skill_tap(cell: Vector2i) -> void:
	if pending_skill != "" and selected != null and board.highlights.has(cell):
		skill_orders[selected.id] = {"skill": pending_skill, "cell": cell}
		board.plan_labels[selected.id] = SkillDB.get_def(pending_skill).name
		pending_skill = ""
		board.highlights = {}
		_auto_select_next_or_keep()
		return
	var u := engine.unit_at(cell)
	if u != null:
		_select(u)


func _auto_select_next_or_keep() -> void:
	var prev := selected
	selected = null
	_auto_select_next()
	if selected == null:
		_select(prev)
		board.highlights = {}
		_refresh()


func _on_skill_pressed(sid: String) -> void:
	if selected == null or not selected.is_hero() or phase != Phase.PLAN_SKILL:
		return
	var def := SkillDB.get_def(sid)
	board.highlights = {}
	if def.target == "self":
		skill_orders[selected.id] = {"skill": sid, "cell": selected.pos}
		board.plan_labels[selected.id] = def.name
		pending_skill = ""
		_auto_select_next_or_keep()
		return
	pending_skill = sid
	for c in engine.skill_targets(selected, sid):
		board.highlights[c] = HL_TARGET
	_refresh()


func _clear_selected_order() -> void:
	if selected == null:
		return
	move_orders.erase(selected.id)
	board.move_arrows.erase(selected.id)
	skill_orders.erase(selected.id)
	board.plan_labels.erase(selected.id)
	pending_skill = ""
	_select(selected)


func _on_confirm() -> void:
	match phase:
		Phase.PLAN_MOVE:
			var orders := ai.move_orders(engine, Unit.TEAM_MONSTERS)
			for id in move_orders:
				orders[id] = move_orders[id]
			engine.resolve_movement(orders)
			_set_phase(Phase.PLAN_SKILL)
		Phase.PLAN_SKILL:
			var orders := ai.skill_orders(engine, Unit.TEAM_MONSTERS)
			for id in skill_orders:
				orders[id] = skill_orders[id]
			engine.resolve_skills(orders)
			engine.end_round()
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
	_refresh_skill_bar()


func _refresh_hint() -> void:
	match phase:
		Phase.SPAWN:
			if not spawn_queue.is_empty():
				hint_label.text = "Deploy %s: tap a green cell." % spawn_queue[0].name
		Phase.PLAN_MOVE:
			var pending := 0
			for u in engine.living(Unit.TEAM_HEROES):
				if engine.can_move(u) and not move_orders.has(u.id):
					pending += 1
			if pending_skill == "" and selected != null and selected.is_hero() and engine.can_move(selected):
				hint_label.text = "Tap a blue cell to move %s (tap them again to stay). %d hero%s undecided." % [selected.name, pending, "" if pending == 1 else "es"]
			else:
				hint_label.text = "Tap a hero to plan their move, then Reveal Moves. Monsters move at the same time!"
		Phase.PLAN_SKILL:
			if pending_skill != "":
				hint_label.text = "Tap a red cell to aim %s." % SkillDB.get_def(pending_skill).name
			elif selected != null and selected.is_hero():
				hint_label.text = "Pick a skill card for %s, or Reveal Skills to resolve the round." % selected.name
			else:
				hint_label.text = "Tap a hero to choose their skill."
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
		line += "\n" + st
	if u.is_hero():
		if move_orders.has(u.id):
			line += "   Move planned."
		if skill_orders.has(u.id):
			line += "   Skill: %s" % SkillDB.get_def(skill_orders[u.id].skill).name
	elif u.state == Unit.State.ACTIVE and u.loading.is_empty():
		var names: Array[String] = []
		for s in u.skills:
			names.append(SkillDB.get_def(s).name)
		line += "\nKnows: " + ", ".join(names)
	info_label.text = line


func _refresh_skill_bar() -> void:
	UI.clear_children(skill_bar)
	if phase != Phase.PLAN_SKILL or selected == null or not selected.is_hero():
		return
	var u := selected
	var avail := engine.available_skills(u)
	if not engine.can_act(u):
		skill_bar.add_child(UI.label("%s cannot act this round (%s)." % [u.name, u.short_status()], "DimLabel"))
		return
	for sid in u.skills:
		var def := SkillDB.get_def(sid)
		if not u.weapon_ok(def.weapon):
			continue
		var p := SkillDB.params(sid, u.skills[sid])
		var txt := SkillDB.display_name(sid, u.skills[sid])
		var cost_bits: Array[String] = []
		if p.cost > 0:
			cost_bits.append("%d st" % p.cost)
		if p.get("life_cost", 0) > 0:
			cost_bits.append("%d life" % p.life_cost)
		if p.get("load", 0) > 0:
			cost_bits.append("load %d" % p.load)
		if engine.is_chain_available(u, sid):
			txt = "CHAIN " + txt
		txt += "\n" + (", ".join(cost_bits) if not cost_bits.is_empty() else "free")
		var b := Button.new()
		b.text = txt
		b.theme_type_variation = "SkillButton"
		b.disabled = not (sid in avail)
		b.custom_minimum_size.x = 200
		b.tooltip_text = SkillDB.describe(sid, u.skills[sid])
		if skill_orders.has(u.id) and skill_orders[u.id].skill == sid:
			b.add_theme_color_override("font_color", UI.ACCENT)
		b.pressed.connect(_on_skill_pressed.bind(sid))
		skill_bar.add_child(b)
	var help := Button.new()
	help.text = "?"
	help.theme_type_variation = "SkillButton"
	help.custom_minimum_size.x = 90
	help.pressed.connect(_show_skill_help.bind(u))
	skill_bar.add_child(help)


func _show_skill_help(u: Unit) -> void:
	var md := UI.modal(self, "%s's skills" % u.name)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 1000)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(10)
	scroll.add_child(v)
	for sid in u.skills:
		var def := SkillDB.get_def(sid)
		if not u.weapon_ok(def.weapon):
			continue
		v.add_child(UI.label(SkillDB.display_name(sid, u.skills[sid])))
		v.add_child(UI.label(SkillDB.describe(sid, u.skills[sid]), "DimLabel"))
		if not def.chains.is_empty():
			var names: Array[String] = []
			for c in def.chains:
				names.append(SkillDB.get_def(c).name)
			v.add_child(UI.label("Chains into: " + ", ".join(names), "SmallLabel"))
	md.vbox.add_child(scroll)
	md.vbox.add_child(UI.button("Close", func(): md.overlay.queue_free()))
