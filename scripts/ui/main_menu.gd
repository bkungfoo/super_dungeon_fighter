extends Control

const RULES_TEXT := """[b]Super Dungeon Fighter[/b] is a real-time dungeon brawl with a deck of skill cards. You control one hero; the Dark Lord's monsters hunt you across the arena.

[b]Moving and attacking[/b]
Tap the ground to walk there, or hold your finger down to keep walking toward it. Tap an enemy to engage: your hero closes in and swings basic attacks until you say otherwise. The camera follows you; the dungeon is bigger than the screen.

[b]Cards[/b]
Your deck has 30 cards and you hold 5. Tap a card to play it: your hero stops and flashes while it charges (a few seconds for big skills, instant for Defend, Grab and Blink). When it is READY, tap an enemy: the hero moves into range and unleashes it. Area skills that can be aimed (Fireball, Blink) can also be cast by double-tapping a spot on the ground. Skills centred on the hero (Whirlwind, Frost Nova) fire once you are just within range of the tapped enemy.

[b]Counters[/b]
Basic attacks beat Grab (an attack landing on a grabber breaks the grab). Grab beats Defend (unblockable). Defend beats attacks (blocked, and the attacker is parried: stunned). Big swings are guard-breaks: Defend only halves them. Spells ignore Defend.

[b]Combos[/b]
Stun X: helpless for X seconds. Stunned + any stun or down -> Down. Down + any stun or down -> RESET: the victim springs up and is immune to stun and down for a while. Don't kick people while they're down unless it kills them.

[b]Chains and cooldowns[/b]
Heavy skills leave you unable to act for a cooldown. Cards on a skill's chain list can be played during that cooldown: Full Swing -> Whirlwind -> Full Swing is a classic knight loop.

[b]Town[/b]
Heroes keep levels, XP and card collections. Win a dungeon and you earn a random card; deeper dungeons drop rarer cards. Build your 30-card deck in town.
"""


func _ready() -> void:
	var m := UI.margin(48, 96, 48, 64)
	add_child(m)
	var v := UI.vbox(28)
	m.add_child(v)
	v.add_child(UI.label("Super Dungeon Fighter", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Heroes of Halud versus the Dark Lord", "DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.spacer(40))
	var summary := UI.label(_summary(), "", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(summary)
	v.add_child(UI.spacer(20))
	v.add_child(UI.button("Play", func(): UI.go("res://scenes/town.tscn"), "PrimaryButton"))
	v.add_child(UI.button("How to Play", _show_rules))
	v.add_child(UI.spacer())
	v.add_child(UI.button("Reset Save", _confirm_reset, "DangerButton"))


func _summary() -> String:
	var d: Dictionary = Save.data
	if d.heroes.is_empty():
		return "No heroes yet. Recruit a party in town."
	return "%d hero%s   |   %d run%s, %d won   |   Dark Lord level %d" % [
		d.heroes.size(), "" if d.heroes.size() == 1 else "es",
		d.runs, "" if d.runs == 1 else "s", d.wins, Save.dm_level()]


func _show_rules() -> void:
	var md := UI.modal(self, "How to Play")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 1200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = RULES_TEXT
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(880, 0)
	scroll.add_child(rt)
	md.vbox.add_child(scroll)
	md.vbox.add_child(UI.button("Close", func(): md.overlay.queue_free()))


func _confirm_reset() -> void:
	var md := UI.modal(self, "Delete all heroes and progress?")
	var h := UI.hbox()
	h.add_child(UI.button("Cancel", func(): md.overlay.queue_free()))
	h.add_child(UI.button("Delete", func():
		Save.reset()
		md.overlay.queue_free()
		UI.go("res://scenes/main_menu.tscn"), "DangerButton"))
	md.vbox.add_child(h)
