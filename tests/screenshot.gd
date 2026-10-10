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
		Session.party_ids = [w.id, k.id, m.id]
		get_tree().change_scene_to_file("res://scenes/setup.tscn")
		await _shot("05_setup")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await _frames(3)
		var gs = get_tree().current_scene
		await _shot("06_deploy")
		var cells: Array = gs.board.highlights.keys()
		cells.sort()
		gs._on_cell_tapped(cells[1])
		gs._on_cell_tapped(cells[3])
		gs._on_cell_tapped(cells[5])
		await _shot("07_plan_phase")
		for r in 4:
			for u in gs.engine.living(Unit.TEAM_HEROES):
				gs._select(u)
				_drive_hero(gs, u, r)
			if r == 1:
				await _shot("08_plan_done")
			gs._on_confirm()
			await _frames(2)
			if gs.phase == gs.Phase.GAME_OVER:
				break
		if gs.phase != gs.Phase.GAME_OVER:
			for u in gs.engine.living(Unit.TEAM_HEROES):
				if gs.engine.can_play(u):
					gs._select(u)
					break
			await _shot("09_hand")
		await _shot("10_mid_battle")
		gs._confirm_retreat()
		await _shot("11_retreat")
		get_tree().quit(0)

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
				for c in cards:
					if c.skill in ["final_slash", "full_swing", "fireball", "bash"]:
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
