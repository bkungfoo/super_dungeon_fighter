extends Node
## Captures screenshots of each screen (needs a display, not --headless).
## Run:  godot --path . res://tests/screenshot.tscn -- /absolute/output/dir


func _ready() -> void:
	var d := Driver.new()
	get_tree().root.call_deferred("add_child", d)


class Driver extends Node:
	var out_dir := "/tmp"

	func _ready() -> void:
		var args := OS.get_cmdline_user_args()
		if not args.is_empty():
			out_dir = args[0]
		call_deferred("_run")

	func _frames(n: int) -> void:
		for i in n:
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
		Save.learn(w, "final_slash")
		Save.learn(k, "full_swing")
		Save.learn(k, "bash")
		Save.learn(m, "fireball")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		await _shot("01_menu")
		get_tree().current_scene._show_rules()
		await _shot("02_rules")
		get_tree().change_scene_to_file("res://scenes/town.tscn")
		await _shot("03_town")
		get_tree().current_scene._skill_shop(k)
		await _shot("04_skills")
		Session.party_ids = [w.id, k.id, m.id]
		get_tree().change_scene_to_file("res://scenes/setup.tscn")
		await _shot("05_setup")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await _frames(3)
		var gs = get_tree().current_scene
		await _shot("06_deploy")
		var cells: Array = gs.board.highlights.keys()
		cells.sort()
		gs._spawn_tap(cells[1])
		gs._spawn_tap(cells[3])
		gs._spawn_tap(cells[5])
		await _shot("07_move_phase")
		# Play a few rounds so the board has some state.
		for r in 4:
			for u in gs.engine.living(Unit.TEAM_HEROES):
				gs._select(u)
				var opts: Array = gs.board.highlights.keys()
				if not opts.is_empty():
					var best: Vector2i = opts[0]
					for c in opts:
						if c.y < best.y:
							best = c
					gs._move_tap(best)
			if r == 1:
				await _shot("08_move_planned")
			gs._on_confirm()
			await _frames(2)
			if gs.phase == gs.Phase.GAME_OVER:
				break
			for u in gs.engine.living(Unit.TEAM_HEROES):
				gs._select(u)
				var avail: Array = gs.engine.available_skills(u)
				if avail.is_empty():
					continue
				var pick: String = avail[0]
				for sid in avail:
					if sid in ["final_slash", "full_swing", "fireball", "bash"]:
						pick = sid
				gs._on_skill_pressed(pick)
				if gs.pending_skill != "":
					var tc: Array = gs.board.highlights.keys()
					if not tc.is_empty():
						var target: Vector2i = tc[0]
						for c in tc:
							var v = gs.engine.unit_at(c)
							if v != null and not v.is_hero():
								target = c
						gs._skill_tap(target)
			if r == 2:
				await _shot("09_skill_phase")
			gs._on_confirm()
			await _frames(2)
		await _shot("10_mid_battle")
		gs._confirm_retreat()
		await _shot("11_retreat")
		get_tree().quit(0)
