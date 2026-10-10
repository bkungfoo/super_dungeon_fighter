extends Control
## Roster management: recruit heroes, build decks, head to the dungeon.

var _roster: VBoxContainer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var m := UI.margin(32, 48, 32, 40)
	add_child(m)
	var v := UI.vbox(20)
	m.add_child(v)
	var top := UI.hbox()
	var back := UI.button("<", func(): UI.go("res://scenes/main_menu.tscn"))
	back.size_flags_horizontal = 0
	back.custom_minimum_size.x = 120
	top.add_child(back)
	top.add_child(UI.label("Town of Halud", "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var pad := Control.new()
	pad.custom_minimum_size.x = 120
	top.add_child(pad)
	v.add_child(top)
	v.add_child(UI.label("Dark Lord level %d   |   Runs: %d (won %d)" % [Save.dm_level(), Save.data.runs, Save.data.wins], "DimLabel", HORIZONTAL_ALIGNMENT_CENTER))

	if not Session.last_result_lines.is_empty():
		var p := UI.panel()
		var pv := UI.vbox(8)
		pv.add_child(UI.label("Run complete: %s" % ("VICTORY" if Session.last_result_won else "DEFEAT"), "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
		for line in Session.last_result_lines:
			pv.add_child(UI.label(line, "SmallLabel"))
		p.add_child(pv)
		v.add_child(p)
		Session.last_result_lines = []

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster = UI.vbox(16)
	scroll.add_child(_roster)
	v.add_child(scroll)

	var actions := UI.hbox()
	actions.add_child(UI.button("Recruit Hero", _recruit_dialog))
	actions.add_child(UI.button("Enter Dungeon", func(): UI.go("res://scenes/setup.tscn"), "PrimaryButton"))
	v.add_child(actions)
	_refresh()


func _refresh() -> void:
	UI.clear_children(_roster)
	if Save.heroes().is_empty():
		_roster.add_child(UI.label("Your guild hall is empty. Recruit a hero to begin.", "DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	for h in Save.heroes():
		_roster.add_child(_hero_card(h))


func _hero_card(h: Dictionary) -> Control:
	var p := UI.panel()
	var v := UI.vbox(10)
	p.add_child(v)
	var def := HeroDB.get_def(h.cls)
	var st: Dictionary = Save.hero_stats(h)
	var name_l := UI.label("%s  -  %s Lv %d" % [h.name, def.name, h.level], "HeadingLabel")
	name_l.add_theme_color_override("font_color", def.color)
	v.add_child(name_l)
	v.add_child(UI.label("Life %d   Stam %d (+%d)   Atk %d   Move %d" % [st.life, st.stam, st.regen, st.attack, st.move], "SmallLabel"))
	v.add_child(UI.label("XP %d / %d   Kills: %d   Runs: %d" % [h.xp, Save.xp_to_next(h.level), h.kills, h.runs], "DimLabel"))
	var deck_n: int = Save.deck_size(h)
	var spare: int = Save.collection_size(h) - deck_n
	var deck_line := UI.label("Deck %d / %d cards   |   %d spare card%s in the collection" % [deck_n, Save.DECK_SIZE, spare, "" if spare == 1 else "s"], "SmallLabel")
	if deck_n != Save.DECK_SIZE:
		deck_line.add_theme_color_override("font_color", UI.DANGER)
	v.add_child(deck_line)
	var row := UI.hbox()
	var deck_btn := UI.button("Deck", func(): _deck_editor(h))
	if spare > 0 or deck_n != Save.DECK_SIZE:
		deck_btn.theme_type_variation = "OkButton"
	row.add_child(deck_btn)
	var dismiss := UI.button("Dismiss", func(): _confirm_dismiss(h), "DangerButton")
	dismiss.size_flags_horizontal = 0
	row.add_child(dismiss)
	v.add_child(row)
	return p


func _confirm_dismiss(h: Dictionary) -> void:
	var md := UI.modal(self, "Dismiss %s forever?" % h.name)
	var row := UI.hbox()
	row.add_child(UI.button("Keep", func(): md.overlay.queue_free()))
	row.add_child(UI.button("Dismiss", func():
		Save.remove_hero(h.id)
		md.overlay.queue_free()
		_refresh(), "DangerButton"))
	md.vbox.add_child(row)


func _recruit_dialog() -> void:
	var md := UI.modal(self, "Recruit a Hero")
	var name_edit := LineEdit.new()
	name_edit.text = HeroDB.random_name(_rng)
	name_edit.placeholder_text = "Name"
	name_edit.max_length = 14
	md.vbox.add_child(name_edit)
	md.vbox.add_child(UI.label("Choose a class:", "SmallLabel"))
	for cls in HeroDB.CLASSES:
		var def := HeroDB.get_def(cls)
		var b := UI.button("%s\n%s" % [def.name, def.desc], func():
			var n: String = name_edit.text.strip_edges()
			if n == "":
				n = HeroDB.random_name(_rng)
			Save.new_hero(n, cls)
			md.overlay.queue_free()
			_refresh())
		b.add_theme_color_override("font_color", def.color)
		b.add_theme_font_size_override("font_size", 30)
		md.vbox.add_child(b)
	md.vbox.add_child(UI.button("Cancel", func(): md.overlay.queue_free()))


## Deck builder: every card the hero owns, with +/- to move copies in and out
## of the 30-card deck.
func _deck_editor(h: Dictionary) -> void:
	var md := UI.modal(self, "%s's Deck" % h.name)
	var count_label := UI.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	md.vbox.add_child(count_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 1100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	scroll.add_child(list)
	md.vbox.add_child(scroll)
	md.vbox.add_child(UI.button("Done", func():
		md.overlay.queue_free()
		_refresh()))
	var rebuild := func() -> void: pass
	rebuild = func() -> void:
		UI.clear_children(list)
		var n: int = Save.deck_size(h)
		count_label.text = "Deck: %d / %d cards" % [n, Save.DECK_SIZE]
		count_label.add_theme_color_override("font_color", UI.OK if n == Save.DECK_SIZE else UI.DANGER)
		var keys: Array = h.collection.keys()
		keys.sort_custom(func(a, b):
			var ca := SkillDB.parse_key(a)
			var cb := SkillDB.parse_key(b)
			var ra := SkillDB.rarity(ca.skill, ca.rank)
			var rb := SkillDB.rarity(cb.skill, cb.rank)
			if ra != rb:
				return ra < rb
			if ca.skill != cb.skill:
				return ca.skill < cb.skill
			return ca.rank < cb.rank)
		for key in keys:
			var c := SkillDB.parse_key(key)
			var owned: int = h.collection[key]
			var in_deck: int = h.deck.get(key, 0)
			var p := UI.panel()
			var v := UI.vbox(6)
			p.add_child(v)
			var head := UI.hbox()
			var title := UI.label(SkillDB.display_name(c.skill, c.rank))
			title.add_theme_color_override("font_color", SkillDB.RARITY_COLORS[SkillDB.rarity(c.skill, c.rank)])
			head.add_child(title)
			var rarity := UI.label(SkillDB.rarity_name(c.skill, c.rank), "DimLabel", HORIZONTAL_ALIGNMENT_RIGHT)
			rarity.autowrap_mode = TextServer.AUTOWRAP_OFF
			rarity.size_flags_horizontal = Control.SIZE_SHRINK_END
			rarity.custom_minimum_size.x = 200
			head.add_child(rarity)
			v.add_child(head)
			v.add_child(UI.label(SkillDB.describe(c.skill, c.rank), "DimLabel"))
			var row := UI.hbox()
			var minus := UI.button("-", func():
				if Save.remove_from_deck(h, key):
					rebuild.call())
			minus.size_flags_horizontal = 0
			minus.custom_minimum_size.x = 130
			minus.disabled = in_deck <= 0
			row.add_child(minus)
			row.add_child(UI.label("In deck: %d   /   Owned: %d" % [in_deck, owned], "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
			var plus := UI.button("+", func():
				if Save.add_to_deck(h, key):
					rebuild.call())
			plus.size_flags_horizontal = 0
			plus.custom_minimum_size.x = 130
			plus.disabled = in_deck >= owned or n >= Save.DECK_SIZE
			row.add_child(plus)
			v.add_child(row)
			list.add_child(p)
	rebuild.call()
