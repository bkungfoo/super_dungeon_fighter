extends Control
## Roster management: recruit heroes, spend skill points, head to the dungeon.

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
	var head := UI.hbox()
	var name_l := UI.label("%s  -  %s Lv %d" % [h.name, def.name, h.level], "HeadingLabel")
	name_l.add_theme_color_override("font_color", def.color)
	head.add_child(name_l)
	v.add_child(head)
	v.add_child(UI.label("Life %d   Stam %d (+%d)   Atk %d   Move %d" % [st.life, st.stam, st.regen, st.attack, st.move], "SmallLabel"))
	v.add_child(UI.label("XP %d / %d   Skill points: %d   Kills: %d   Runs: %d" % [h.xp, Save.xp_to_next(h.level), h.sp, h.kills, h.runs], "DimLabel"))
	var skill_names: Array[String] = []
	for s in h.skills:
		skill_names.append(SkillDB.display_name(s, h.skills[s]))
	v.add_child(UI.label("Skills: " + ", ".join(skill_names), "SmallLabel"))
	var row := UI.hbox()
	var skills_btn := UI.button("Skills (%d SP)" % h.sp, func(): _skill_shop(h))
	if h.sp > 0:
		skills_btn.theme_type_variation = "OkButton"
	row.add_child(skills_btn)
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


func _skill_shop(h: Dictionary) -> void:
	var md := UI.modal(self, "%s's Skills" % h.name)
	var sp_label := UI.label("Skill points: %d" % h.sp, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	md.vbox.add_child(sp_label)
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
		sp_label.text = "Skill points: %d" % h.sp
		var def := HeroDB.get_def(h.cls)
		var all: Array = []
		for s in def.skills:
			all.append(s)
		for s in def.learnable:
			all.append(s)
		for s in all:
			var cur: int = h.skills.get(s, -1)
			var p := UI.panel()
			var v := UI.vbox(6)
			p.add_child(v)
			var known: bool = h.skills.has(s)
			var title: String = SkillDB.display_name(s, cur) if known else SkillDB.get_def(s).name + "  (not learned)"
			v.add_child(UI.label(title, "", HORIZONTAL_ALIGNMENT_LEFT))
			var desc_rank: int = cur if known else 0
			v.add_child(UI.label(SkillDB.describe(s, desc_rank), "DimLabel"))
			var cost: int = Save.next_rank_cost(h, s)
			if cost >= 0:
				var nxt: int = cur + 1
				var txt: String = "Learn rank %s (%d SP)" % [SkillDB.rank_label(s, nxt), cost] if not known else "Rank up to %s (%d SP)" % [SkillDB.rank_label(s, nxt), cost]
				var b := UI.button(txt, func():
					if Save.learn(h, s):
						rebuild.call(), "OkButton")
				b.disabled = not Save.can_learn(h, s)
				if known:
					v.add_child(UI.label("Next: " + SkillDB.describe(s, nxt), "SmallLabel"))
				v.add_child(b)
			elif SkillDB.has_ranks(s):
				v.add_child(UI.label("Rank S: mastered", "SmallLabel"))
			list.add_child(p)
	rebuild.call()
