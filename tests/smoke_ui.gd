extends Node
## UI smoke test: drives every scene for a few frames and plays a run against
## the AI by calling the game screen's handlers directly.
## Run:  godot --headless --path . res://tests/smoke_ui.tscn


func _ready() -> void:
	# The driver must live outside the current scene, which gets freed on
	# every scene change.
	var d := Driver.new()
	get_tree().root.call_deferred("add_child", d)


class Driver extends Node:
	func _ready() -> void:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		call_deferred("_run")
		var t := Timer.new()
		t.wait_time = 90.0
		t.one_shot = true
		t.timeout.connect(func():
			push_error("smoke: watchdog timeout")
			get_tree().quit(2))
		add_child(t)
		t.start()


	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame


	func _run() -> void:
		print("[smoke] main menu")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		await _frames(3)
		get_tree().current_scene._show_rules()
		await _frames(2)

		print("[smoke] town")
		Save.save_path = "user://test_save.json"
		Save.data = Save._default_data()
		var w: Dictionary = Save.new_hero("Smoke Warrior", "warrior")
		var k: Dictionary = Save.new_hero("Smoke Knight", "knight")
		var m: Dictionary = Save.new_hero("Smoke Mage", "mage")
		Save.grant_card(w, "final_slash:2")
		Save.remove_from_deck(w, "attack:-1")
		Save.add_to_deck(w, "final_slash:2")
		get_tree().change_scene_to_file("res://scenes/town.tscn")
		await _frames(3)
		get_tree().current_scene._recruit_dialog()
		await _frames(2)
		get_tree().current_scene._deck_editor(w)
		await _frames(2)

		print("[smoke] setup")
		Session.hero_id = w.id
		get_tree().change_scene_to_file("res://scenes/setup.tscn")
		await _frames(3)
		get_tree().current_scene._update()
		await _frames(1)

		var ids := [w.id, k.id, m.id]
		for run in 3:
			print("[smoke] battle run %d" % run)
			Session.hero_id = ids[run]
			Session.difficulty = 1.0 + run * 0.5
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
			await _frames(3)
			var gs = get_tree().current_scene
			gs.time_scale = 30.0
			var frames := 0
			while not gs._finished and frames < 2500:
				frames += 1
				if frames % 10 == 0:
					_drive_hero(gs)
				await _frames(1)
			print("[smoke] run %d finished after %d frames, winner=%d, sim time %.1fs" % [run, frames, gs.sim.winner(), gs.sim.time])
			if not gs._finished:
				push_error("smoke: battle did not finish")
			await _frames(2)
			get_tree().change_scene_to_file("res://scenes/town.tscn")
			await _frames(3)
		print("[smoke] done")
		get_tree().quit(0)

	## Drives the hero through the scene's own input handlers: card buttons,
	## taps on enemies, double taps on the ground.
	func _drive_hero(gs) -> void:
		var hero: Actor = gs.hero
		if not hero.alive:
			return
		if hero.loaded.is_empty() and not hero.is_charging():
			for b in gs.hand_bar.get_children():
				if b is Button and not b.disabled and gs.sim.rng.randf() < 0.6:
					gs._on_card_pressed(b.get_meta("card"))
					break
		var e: Actor = gs.sim.nearest_enemy(hero)
		if e == null:
			return
		var screen: Vector2 = gs.cam.unproject_position(Vector3(e.pos.x, 0.8, e.pos.y))
		if not hero.loaded.is_empty() and BattleSim.targets_point(hero.loaded.skill):
			var g = gs.ground_point(screen)
			if g != null:
				gs.sim.command_point(hero, g)
		elif gs.pick_enemy(screen) != null:
			gs._click(screen)
		else:
			gs.sim.command_target(hero, e.id)
