extends Control
## Pick the party and difficulty, then enter the dungeon.

const DIFFICULTIES := [["Normal", 1.0], ["Hard", 1.5], ["Nightmare", 2.0]]
const MAX_PARTY := 6

var _checks: Dictionary = {}
var _diff_index: int = 0
var _info: Label
var _start: Button
var _diff_buttons: Array = []


func _ready() -> void:
	var m := UI.margin(32, 48, 32, 40)
	add_child(m)
	var v := UI.vbox(20)
	m.add_child(v)
	var top := UI.hbox()
	var back := UI.button("<", func(): UI.go("res://scenes/town.tscn"))
	back.size_flags_horizontal = 0
	back.custom_minimum_size.x = 120
	top.add_child(back)
	top.add_child(UI.label("Dungeon Run", "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var pad := Control.new()
	pad.custom_minimum_size.x = 120
	top.add_child(pad)
	v.add_child(top)
	v.add_child(UI.label("Choose your party (up to %d heroes)" % MAX_PARTY, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	scroll.add_child(list)
	v.add_child(scroll)
	for h in Save.heroes():
		var def := HeroDB.get_def(h.cls)
		var cb := CheckBox.new()
		cb.text = "%s  -  %s Lv %d" % [h.name, def.name, h.level]
		cb.button_pressed = h.id in Session.party_ids
		cb.add_theme_color_override("font_color", def.color)
		cb.toggled.connect(func(_on): _update())
		_checks[h.id] = cb
		list.add_child(cb)
	if Save.heroes().is_empty():
		list.add_child(UI.label("No heroes. Go back and recruit some.", "DimLabel", HORIZONTAL_ALIGNMENT_CENTER))

	v.add_child(UI.label("Difficulty (scales the Dark Lord's summoning budget)", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox()
	for i in DIFFICULTIES.size():
		var b := UI.button(DIFFICULTIES[i][0], func():
			_diff_index = i
			_update())
		b.toggle_mode = true
		row.add_child(b)
		_diff_buttons.append(b)
	v.add_child(row)
	_info = UI.label("", "DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_info)
	_start = UI.button("Descend!", _start_run, "PrimaryButton")
	v.add_child(_start)
	_update()


func _selected_ids() -> Array:
	var ids: Array = []
	for id in _checks:
		if _checks[id].button_pressed:
			ids.append(id)
	return ids


func _update() -> void:
	var ids := _selected_ids()
	for i in _diff_buttons.size():
		_diff_buttons[i].button_pressed = (i == _diff_index)
		_diff_buttons[i].theme_type_variation = "PrimaryButton" if i == _diff_index else ""
	Session.party_ids = ids
	Session.difficulty = DIFFICULTIES[_diff_index][1]
	Session.difficulty_name = DIFFICULTIES[_diff_index][0]
	var ok := ids.size() >= 1 and ids.size() <= MAX_PARTY
	_start.disabled = not ok
	if ids.is_empty():
		_info.text = "Select at least one hero."
	elif ids.size() > MAX_PARTY:
		_info.text = "Too many heroes."
	else:
		_info.text = "The Dark Lord (level %d) gets %d summoning points." % [Save.dm_level(), Session.dm_budget()]


func _start_run() -> void:
	if _selected_ids().is_empty():
		return
	UI.go("res://scenes/game.tscn")
