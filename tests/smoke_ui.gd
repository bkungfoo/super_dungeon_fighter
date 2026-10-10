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
		Session.party_ids = [w.id, k.id, m.id]
		get_tree().change_scene_to_file("res://scenes/setup.tscn")
		await _frames(3)
		get_tree().current_scene._update()
		await _frames(1)

		for run in 3:
			print("[smoke] game run %d" % run)
			Session.difficulty = 1.0 + run
			get_tree().change_scene_to_file("res://scenes/game.tscn")
			await _frames(3)
			var gs = get_tree().current_scene
			while not gs.spawn_queue.is_empty():
				var cells: Array = gs.board.highlights.keys()
				gs._on_cell_tapped(cells[0])
				await _frames(1)
			var rounds := 0
			while gs.phase != gs.Phase.GAME_OVER and rounds < 80:
				rounds += 1
				for u in gs.engine.living(Unit.TEAM_HEROES):
					gs._select(u)
					_drive_hero(gs, u, rounds)
				gs._on_confirm()
				await _frames(3)
			print("[smoke] run %d finished after %d rounds, winner=%d, log lines=%d" % [run, rounds, gs.engine.winner(), gs.engine.history.size()])
			if gs.phase != gs.Phase.GAME_OVER:
				push_error("smoke: game did not finish")
			await _frames(2)
			get_tree().change_scene_to_file("res://scenes/town.tscn")
			await _frames(3)
		print("[smoke] done")
		get_tree().quit(0)

	## Plans one hero through the real tap handlers: move up, play a card, aim at a monster.
	func _drive_hero(gs, u: Unit, rounds: int) -> void:
		if gs.engine.can_move(u) and not gs.engine.is_ready(u):
			var cells: Array = gs.board.highlights.keys()
			if not cells.is_empty():
				var best: Vector2i = cells[0]
				for c in cells:
					if c.y < best.y:
						best = c
				gs._on_cell_tapped(best)
		if gs.engine.can_play(u) and not gs.pending_aim:
			var cards: Array = gs.engine.playable_cards(u)
			if not cards.is_empty():
				var pick: Dictionary = cards[(rounds + u.id) % cards.size()]
				var from: Vector2i = gs._from_pos(u)
				for c in cards:
					for d in GameEngine.DIRS:
						var v = gs.engine.unit_at(from + d)
						if v != null and not v.is_hero() and SkillDB.get_def(c.skill).target == "dir" and not SkillDB.params(c.skill, c.rank).has("load"):
							pick = c
				gs._on_card_pressed(pick)
		if gs.pending_aim:
			var cells: Array = gs.board.highlights.keys()
			if not cells.is_empty():
				var target: Vector2i = cells[0]
				for c in cells:
					var v = gs.engine.unit_at(c)
					if v != null and not v.is_hero():
						target = c
				gs._on_cell_tapped(target)
