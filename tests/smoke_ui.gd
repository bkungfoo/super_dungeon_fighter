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
		Save.learn(w, "final_slash")
		Save.learn(k, "full_swing")
		Save.learn(k, "bash")
		Save.learn(m, "fireball")
		Save.learn(m, "frost_nova")
		get_tree().change_scene_to_file("res://scenes/town.tscn")
		await _frames(3)
		get_tree().current_scene._recruit_dialog()
		await _frames(2)
		get_tree().current_scene._skill_shop(w)
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
			# Deploy.
			while not gs.spawn_queue.is_empty():
				var cells: Array = gs.board.highlights.keys()
				gs._spawn_tap(cells[0])
				await _frames(1)
			var rounds := 0
			while gs.phase != gs.Phase.GAME_OVER and rounds < 80:
				rounds += 1
				# Movement: every hero moves toward the top of the board.
				for u in gs.engine.living(Unit.TEAM_HEROES):
					gs._select(u)
					var cells: Array = gs.board.highlights.keys()
					if not cells.is_empty():
						var best: Vector2i = cells[0]
						for c in cells:
							if c.y < best.y:
								best = c
						gs._move_tap(best)
				gs._on_confirm()
				await _frames(2)
				if gs.phase == gs.Phase.GAME_OVER:
					break
				# Skills: use whatever is available, aimed at the first target.
				for u in gs.engine.living(Unit.TEAM_HEROES):
					gs._select(u)
					var avail: Array = gs.engine.available_skills(u)
					if avail.is_empty():
						continue
					var pick: String = avail[(rounds + u.id) % avail.size()]
					for sid in avail:
						for d in GameEngine.DIRS:
							var v = gs.engine.unit_at(u.pos + d)
							if v != null and not v.is_hero() and SkillDB.get_def(sid).target == "dir":
								pick = sid
					gs._on_skill_pressed(pick)
					if gs.pending_skill != "":
						var cells: Array = gs.board.highlights.keys()
						if not cells.is_empty():
							var target: Vector2i = cells[0]
							for c in cells:
								var v = gs.engine.unit_at(c)
								if v != null and not v.is_hero():
									target = c
							gs._skill_tap(target)
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
