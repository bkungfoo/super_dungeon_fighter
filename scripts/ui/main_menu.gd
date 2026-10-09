extends Control

const RULES_TEXT := """[b]Super Dungeon Fighter[/b] is D&D, chess, poker and a fighting game rolled into one. No dice: every unit secretly picks a move and a skill, then everything is revealed and resolved at once.

[b]A round[/b]
1. Charged skills: skills with load time gain a counter; ready ones fire first (random priority).
2. Movement: tap a hero, tap a destination. Reveal moves. Everyone moves at the same time.
3. Skills: tap a hero, pick a skill card, tap a target. Reveal skills. Everything resolves together.

[b]Counters[/b]
Attack beats Grab (an attack aimed at a grabber breaks the grab). Grab beats Defend (unblockable). Defend beats Attack (blocked and the attacker is parried: Stun 1). Big swings are guard-breaks: Defend only halves them. Spells ignore Defend.

[b]Combos[/b]
Active -> Stun X: skip X rounds. Stunned + any stun or down -> Down. Down + any stun or down -> RESET: the victim springs up, is immune to stun and down for a while, and acts first next round. Don't kick people while they're down unless it kills them.

[b]Chains[/b]
After a skill with a chain list resolves, you may play a chained skill next round even while on cooldown. Full Swing -> Whirlwind -> Full Swing is a classic knight loop.

[b]Load, cooldown, immobile[/b]
Load N: the skill fires N rounds later in the charged phase. Being stunned or knocked down interrupts it. Cooldown N: no skills for N rounds (except chains). Immobile N: no movement.

[b]Town[/b]
Heroes keep levels, XP and skills between runs. Spend skill points to learn and rank up skills (C, B, A, S). The Dark Lord levels too, unlocking nastier monsters.
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
