extends Node
## Captures screenshots of each screen (needs a display, not --headless).
## Run:  godot --path . res://tests/screenshot.tscn -- /absolute/output/dir


func _ready() -> void:
	var d := Driver.new()
	get_tree().root.call_deferred("add_child", d)


class Driver extends Node:
	var out_dir := "/tmp"

	func _ready() -> void:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var args := OS.get_cmdline_user_args()
		if not args.is_empty():
			out_dir = args[0]
		call_deferred("_run")

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	## Advances the battle by `seconds` of simulated time (frames are not
	## tied to wall-clock time in this driver).
	func _sim_seconds(gs, seconds: float) -> void:
		var target: float = gs.sim.time + seconds
		var guard := 0
		while gs.sim.time < target and not gs._finished and guard < 100000:
			guard += 1
			await get_tree().process_frame

	func _shot(name: String) -> void:
		await _frames(4)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(name + ".png"))
		print("[shot] " + name)

	func _run() -> void:
		Save.save_path = "user://test_save.json"
		Save.data = Save._default_data()
		var w: Dictionary = Save.new_hero("Ardin", "warrior")
		var k: Dictionary = Save.new_hero("Bryn", "knight")
		var m: Dictionary = Save.new_hero("Cassia", "mage")
		Save.grant_card(w, "final_slash:2")
		Save.grant_card(k, "bash:1")
		Save.grant_card(k, "full_swing:3")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		await _shot("01_menu")
		get_tree().current_scene._show_rules()
		await _shot("02_rules")
		get_tree().change_scene_to_file("res://scenes/town.tscn")
		await _shot("03_town")
		get_tree().current_scene._deck_editor(k)
		await _shot("04_deck")
		Session.hero_id = k.id
		get_tree().change_scene_to_file("res://scenes/setup.tscn")
		await _shot("05_setup")
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
		await _frames(3)
		var gs = get_tree().current_scene
		await _shot("06_battle_start")
		var hero: Actor = gs.hero
		var e: Actor = gs.sim.nearest_enemy(hero)
		gs.sim.command_target(hero, e.id)
		await _sim_seconds(gs, 3.0)
		await _shot("07_engaging")
		for b in gs.hand_bar.get_children():
			if b is Button and not b.disabled and b.text.begins_with("Bash"):
				b.pressed.emit()
				break
		await _sim_seconds(gs, 0.5)
		await _shot("08_charging")
		await _sim_seconds(gs, 1.0)
		e = gs.sim.nearest_enemy(hero)
		if e != null:
			gs.sim.command_target(hero, e.id)
		await _sim_seconds(gs, 0.6)
		await _shot("09_skill_fired")
		await _sim_seconds(gs, 2.5)
		await _shot("10_mid_battle")
		gs._confirm_retreat()
		await _shot("11_retreat")
		get_tree().quit(0)
