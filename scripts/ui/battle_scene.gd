extends Node3D
## Real-time 3D dungeon run. Renders the BattleSim, turns taps and holds into
## hero commands, follows the hero with the camera, and draws the HUD.

const CAM_HEIGHT := 15.0
const CAM_BACK := 9.0
const HOLD_TIME := 0.22
const DRAG_PX := 24.0
const DOUBLE_TIME := 0.4
const DOUBLE_PX := 60.0
const PICK_PX := 70.0

var sim: BattleSim
var hero: Actor
var time_scale: float = 1.0
var dungeon_level: int = 1
var cam: Camera3D

var _views: Dictionary = {}        # actor id -> {root, mesh, mat, bar_fg, label, dead_t}
var _floaters: Array = []          # {node, t, delay}
var _floater_queue: float = 0.0    # staggers bursts of text so they stay readable
var _blasts: Array = []            # {node, t}
var _hero_ring: MeshInstance3D
var _target_ring: MeshInstance3D

# input state
var _pressed := false
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _dragging := false
var _hold_moving := false
var _hold_tick := 0.0
var _pointer := Vector2.ZERO
var _last_click_time := -10.0
var _last_click_pos := Vector2.ZERO

# HUD
var hud_root: Control
var name_label: Label
var enemies_label: Label
var status_label: Label
var hint_label: Label
var log_label: Label
var life_bar: ProgressBar
var stam_bar: ProgressBar
var charge_bar: ProgressBar
var hand_bar: HBoxContainer
var _hand_sig := ""
var _log_lines: Array[String] = []
var _finished := false


func _ready() -> void:
	_new_run()
	_build_world()
	_build_hud()


# ------------------------------------------------------------------ setup

func _new_run() -> void:
	sim = BattleSim.new()
	sim.log_msg.connect(_on_log)
	sim.event.connect(_on_event)
	var h: Dictionary = Save.hero_by_id(Session.hero_id)
	if h.is_empty():
		if Save.heroes().is_empty():
			UI.go("res://scenes/town.tscn")
			return
		h = Save.heroes()[0]
		Session.hero_id = h.id
	hero = Save.make_actor(h)
	var dm := DMAI.new(sim.rng)
	var budget: int = Session.dm_budget()
	dungeon_level = Session.dungeon_level()
	var monsters := dm.choose_monsters(budget, Save.dm_level())
	sim.generate(hero, monsters, sim.rng.randi_range(9, 14))
	sim.setup_deck(hero, Save.deck_cards(h))
	var names: Array[String] = []
	for m in sim.living(Actor.TEAM_MONSTERS):
		names.append(m.name)
	_on_log("Dungeon level %d. The Dark Lord summons: %s." % [dungeon_level, ", ".join(names)])


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _checker_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.30, 0.28, 0.36))
	img.set_pixel(1, 1, Color(0.30, 0.28, 0.36))
	img.set_pixel(1, 0, Color(0.26, 0.24, 0.32))
	img.set_pixel(0, 1, Color(0.26, 0.24, 0.32))
	return ImageTexture.create_from_image(img)


func _flat_material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_world() -> void:
	if sim == null:
		return
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.06, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.75)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(sim.map.width, sim.map.height)
	ground.mesh = plane
	ground.position = Vector3(sim.map.width * 0.5, 0, sim.map.height * 0.5)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _checker_texture()
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.uv1_scale = Vector3(sim.map.width / 4.0, sim.map.height / 4.0, 1)
	ground.material_override = gm
	add_child(ground)

	var wall_mat := _flat_material(Color(0.16, 0.14, 0.22))
	for r in sim.map.obstacles:
		add_child(_box(Vector3(r.position.x + r.size.x * 0.5, 0.8, r.position.y + r.size.y * 0.5), Vector3(r.size.x, 1.6, r.size.y), wall_mat))
	var w := sim.map.width
	var hgt := sim.map.height
	add_child(_box(Vector3(w * 0.5, 1.0, -0.5), Vector3(w + 2, 2, 1), wall_mat))
	add_child(_box(Vector3(w * 0.5, 1.0, hgt + 0.5), Vector3(w + 2, 2, 1), wall_mat))
	add_child(_box(Vector3(-0.5, 1.0, hgt * 0.5), Vector3(1, 2, hgt + 2), wall_mat))
	add_child(_box(Vector3(w + 0.5, 1.0, hgt * 0.5), Vector3(1, 2, hgt + 2), wall_mat))

	for a in sim.actors:
		_make_view(a)
	_hero_ring = _ring(Color(1, 1, 1, 0.9), hero.radius + 0.15)
	add_child(_hero_ring)
	_target_ring = _ring(Color(1, 0.35, 0.3, 0.95), 0.75)
	_target_ring.visible = false
	add_child(_target_ring)

	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)
	_update_camera()


func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	return mi


func _ring(color: Color, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.08
	t.outer_radius = radius + 0.08
	mi.mesh = t
	var m := _flat_material(color, true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.scale = Vector3(1, 0.25, 1)
	return mi


func _actor_color(a: Actor) -> Color:
	if a.is_hero():
		return HeroDB.get_def(a.cls).get("color", Color(0.4, 0.6, 1.0))
	return MonsterDB.get_def(a.cls).get("color", Color(0.9, 0.3, 0.3))


func _make_view(a: Actor) -> void:
	var root := Node3D.new()
	root.position = Vector3(a.pos.x, 0, a.pos.y)
	add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = a.radius * 0.9
	cap.height = 1.4 + a.radius
	mi.mesh = cap
	mi.position = Vector3(0, cap.height * 0.5, 0)
	var mat := _flat_material(_actor_color(a))
	mat.emission_enabled = true
	mat.emission = _actor_color(a).lightened(0.4)
	mat.emission_energy_multiplier = 0.0
	mi.material_override = mat
	body.add_child(mi)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.25, 0.25, 0.4)
	nose.mesh = nb
	nose.position = Vector3(0, cap.height * 0.6, -a.radius * 0.9)
	nose.material_override = _flat_material(_actor_color(a).darkened(0.4))
	body.add_child(nose)
	if a.has_shield:
		var sh := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.5, 0.6, 0.1)
		sh.mesh = sb
		sh.position = Vector3(-a.radius * 0.9, cap.height * 0.5, 0)
		sh.material_override = _flat_material(Color(0.85, 0.85, 0.95))
		body.add_child(sh)
	var bar_y := cap.height + 0.45
	var bg := _quad(Vector2(1.1, 0.14), Color(0.05, 0.05, 0.08, 0.9))
	bg.position = Vector3(0, bar_y, 0)
	root.add_child(bg)
	var fg := _quad(Vector2(1.0, 0.09), Color(0.3, 0.9, 0.4))
	fg.position = Vector3(0, bar_y, 0.01)
	root.add_child(fg)
	var label := Label3D.new()
	label.text = a.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.008
	label.position = Vector3(0, bar_y + 0.3, 0)
	label.modulate = Color(1, 1, 1) if a.is_hero() else Color(1, 0.85, 0.85)
	root.add_child(label)
	_views[a.id] = {"root": root, "body": body, "mesh": mi, "mat": mat, "bar_fg": fg, "label": label, "dead_t": -1.0}


func _quad(size: Vector2, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := _flat_material(color, true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	return mi


# ------------------------------------------------------------------ HUD

func _bar(color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size.y = 26
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(8)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return pb


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_root)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 16)
	top.add_theme_constant_override("margin_right", 16)
	top.add_theme_constant_override("margin_top", 20)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top)
	var panel := UI.panel()
	top.add_child(panel)
	var v := UI.vbox(8)
	panel.add_child(v)
	var row := UI.hbox()
	name_label = UI.label(hero.name, "HeadingLabel")
	row.add_child(name_label)
	enemies_label = UI.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(enemies_label)
	var retreat := UI.button("Retreat", _confirm_retreat, "DangerButton")
	retreat.size_flags_horizontal = 0
	row.add_child(retreat)
	v.add_child(row)
	life_bar = _bar(Color(0.3, 0.85, 0.4))
	v.add_child(life_bar)
	stam_bar = _bar(Color(0.95, 0.76, 0.3))
	stam_bar.custom_minimum_size.y = 16
	v.add_child(stam_bar)
	status_label = UI.label("", "DimLabel")
	v.add_child(status_label)

	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("margin_left", 16)
	bottom.add_theme_constant_override("margin_right", 16)
	bottom.add_theme_constant_override("margin_bottom", 20)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bottom)
	var bv := UI.vbox(8)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bv)
	log_label = UI.label("", "DimLabel")
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(log_label)
	var bpanel := UI.panel()
	bv.add_child(bpanel)
	var pv := UI.vbox(8)
	bpanel.add_child(pv)
	hint_label = UI.label("", "SmallLabel")
	pv.add_child(hint_label)
	charge_bar = _bar(Color(0.6, 0.7, 1.0))
	charge_bar.custom_minimum_size.y = 14
	charge_bar.visible = false
	pv.add_child(charge_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 130
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_bar = UI.hbox(12)
	scroll.add_child(hand_bar)
	pv.add_child(scroll)
	_refresh_hud()


func _refresh_hud() -> void:
	if hero == null:
		return
	life_bar.max_value = hero.max_life
	life_bar.value = hero.life
	stam_bar.max_value = hero.max_stam
	stam_bar.value = hero.stam
	enemies_label.text = "Enemies: %d" % sim.living(Actor.TEAM_MONSTERS).size()
	var st := "Life %d/%d   Stam %d/%d" % [hero.life, hero.max_life, int(hero.stam), hero.max_stam]
	var extra := hero.status_text()
	if hero.cooldown > 0.0:
		extra += "  cooldown %.1fs" % hero.cooldown
	status_label.text = st + ("   " + extra if extra != "" else "")
	if hero.is_charging():
		charge_bar.visible = true
		charge_bar.max_value = hero.loading.need
		charge_bar.value = hero.loading.timer
		hint_label.text = "Charging %s..." % SkillDB.get_def(hero.loading.skill).name
	else:
		charge_bar.visible = false
		if not hero.loaded.is_empty():
			var n: String = SkillDB.get_def(hero.loaded.skill).name
			if BattleSim.targets_point(hero.loaded.skill):
				hint_label.text = "%s READY: tap an enemy, or double-tap the ground to aim it there." % n
			else:
				hint_label.text = "%s READY: tap an enemy to close in and strike." % n
		elif not hero.can_act():
			hint_label.text = hero.status_text()
		else:
			hint_label.text = "Tap an enemy to attack. Tap or hold the ground to move. Tap a card to charge it."
	# Hand: rebuild only when something about it changes.
	var sig := ""
	for c in hero.hand:
		sig += "%s:%d:%d|" % [c.skill, c.rank, 1 if sim.card_playable(hero, c) else 0]
	if sig != _hand_sig:
		_hand_sig = sig
		UI.clear_children(hand_bar)
		for c in hero.hand:
			var p := SkillDB.params(c.skill, c.rank)
			var txt := SkillDB.display_name(c.skill, c.rank)
			var bits: Array[String] = []
			if p.cost > 0:
				bits.append("%d st" % p.cost)
			if p.get("load", 0) > 0:
				bits.append("%.1fs" % (p.load * BattleSim.SEC_PER_LOAD))
			if sim.is_chain_available(hero, c.skill):
				txt = "CHAIN " + txt
			var b := Button.new()
			b.text = txt + "\n" + (", ".join(bits) if not bits.is_empty() else "instant")
			b.theme_type_variation = "SkillButton"
			b.custom_minimum_size.x = 200
			b.disabled = not sim.card_playable(hero, c)
			b.add_theme_color_override("font_color", SkillDB.RARITY_COLORS[SkillDB.rarity(c.skill, c.rank)])
			b.pressed.connect(_on_card_pressed.bind(c))
			hand_bar.add_child(b)


func _on_card_pressed(card: Dictionary) -> void:
	if _finished or hero == null:
		return
	sim.play_card(hero, card)


func _on_log(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	if log_label != null:
		log_label.text = "\n".join(_log_lines)


func _confirm_retreat() -> void:
	if _finished:
		return
	var md := UI.modal(hud_root, "Retreat from the dungeon?")
	md.vbox.add_child(UI.label("You keep XP from kills, but there is no card reward and the Dark Lord grows from the damage dealt.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox()
	row.add_child(UI.button("Keep fighting", func(): md.overlay.queue_free()))
	row.add_child(UI.button("Retreat", func():
		md.overlay.queue_free()
		_finish(false), "DangerButton"))
	md.vbox.add_child(row)


func _finish(won: bool) -> void:
	if _finished:
		return
	_finished = true
	var lines := Save.apply_run(sim, won, dungeon_level)
	Session.last_result_lines = lines
	Session.last_result_won = won
	var md := UI.modal(hud_root, "VICTORY!" if won else "DEFEAT")
	md.vbox.add_child(UI.label("The dungeon is cleared. A new card joins your collection." if won else "You have fallen. You will recover in town.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	for line in lines:
		md.vbox.add_child(UI.label(line, "SmallLabel"))
	md.vbox.add_child(UI.button("Return to Town", func(): UI.go("res://scenes/town.tscn"), "PrimaryButton"))


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
			_pointer = event.position
			_press_time = _now()
			_dragging = false
			_hold_moving = false
			_hold_tick = 0.0
		else:
			if _pressed and not _hold_moving:
				_click(event.position)
			_pressed = false
			_hold_moving = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_pointer = event.position
		if _pressed and _pointer.distance_to(_press_pos) > DRAG_PX:
			_dragging = true


func ground_point(screen: Vector2) -> Variant:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if dir.y >= -0.0001:
		return null
	var t := -from.y / dir.y
	var p := from + dir * t
	return Vector2(p.x, p.z)


func pick_enemy(screen: Vector2) -> Actor:
	var best: Actor = null
	var bd := PICK_PX
	for m in sim.living(Actor.TEAM_MONSTERS):
		var world := Vector3(m.pos.x, 0.8, m.pos.y)
		if cam.is_position_behind(world):
			continue
		var d := cam.unproject_position(world).distance_to(screen)
		if d < bd:
			bd = d
			best = m
	return best


## A quick tap: enemy = engage; ground = move; double tap on the ground with
## an area skill loaded = cast it there.
func _click(screen: Vector2) -> void:
	var now := _now()
	var is_double := now - _last_click_time < DOUBLE_TIME and screen.distance_to(_last_click_pos) < DOUBLE_PX
	_last_click_time = now
	_last_click_pos = screen
	var enemy := pick_enemy(screen)
	if enemy != null:
		sim.command_target(hero, enemy.id)
		return
	var g = ground_point(screen)
	if g == null:
		return
	if is_double and not hero.loaded.is_empty() and BattleSim.targets_point(hero.loaded.skill):
		sim.command_point(hero, g)
		_last_click_time = -10.0
	else:
		sim.command_move(hero, g)


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if sim == null or hero == null:
		return
	if not _finished:
		sim.tick(delta * time_scale)
		var w := sim.winner()
		if w >= 0:
			_finish(w == Actor.TEAM_HEROES)
	if _pressed and not _finished and (_dragging or _now() - _press_time > HOLD_TIME):
		_hold_moving = true
		_hold_tick -= delta
		if _hold_tick <= 0.0:
			_hold_tick = 0.08
			var g = ground_point(_pointer)
			if g != null:
				sim.command_move(hero, g)
	_update_views(delta)
	_update_camera()
	_update_effects(delta)
	_refresh_hud()


func _update_views(delta: float) -> void:
	var t := _now()
	for a in sim.actors:
		var vw: Dictionary = _views.get(a.id, {})
		if vw.is_empty():
			continue
		var root: Node3D = vw.root
		if not a.alive:
			if vw.dead_t < 0.0:
				vw.dead_t = 0.6
			vw.dead_t -= delta
			if vw.dead_t <= 0.0:
				root.visible = false
				continue
			root.scale = Vector3.ONE * maxf(0.01, vw.dead_t / 0.6)
		root.position = Vector3(a.pos.x, 0, a.pos.y)
		var body: Node3D = vw.body
		if a.facing.length() > 0.01:
			body.basis = Basis.looking_at(Vector3(a.facing.x, 0, a.facing.y), Vector3.UP)
		var mesh: MeshInstance3D = vw.mesh
		mesh.rotation.x = PI * 0.5 if a.state == Actor.State.DOWN else 0.0
		mesh.position.y = (a.radius * 0.9 + 0.05) if a.state == Actor.State.DOWN else (mesh.mesh as CapsuleMesh).height * 0.5
		var mat: StandardMaterial3D = vw.mat
		if a.is_charging():
			mat.emission_energy_multiplier = 0.8 + 0.8 * sin(t * 18.0)
		elif not a.loaded.is_empty():
			mat.emission_energy_multiplier = 0.6
		elif a.guard > 0.0:
			mat.emission = Color(0.6, 0.9, 1.0)
			mat.emission_energy_multiplier = 0.5
		elif a.state == Actor.State.STUNNED:
			mat.emission = Color(1, 0.9, 0.3)
			mat.emission_energy_multiplier = 0.4 + 0.4 * sin(t * 10.0)
		else:
			mat.emission = _actor_color(a).lightened(0.4)
			mat.emission_energy_multiplier = 0.0
		var fg: MeshInstance3D = vw.bar_fg
		var frac: float = clampf(float(a.life) / float(a.max_life), 0.0, 1.0)
		fg.scale.x = maxf(0.01, frac)
		fg.position.x = -(1.0 - frac) * 0.5
		var fm: StandardMaterial3D = fg.material_override
		fm.albedo_color = Color(0.3, 0.9, 0.4) if frac > 0.5 else (Color(1, 0.8, 0.2) if frac > 0.25 else Color(1, 0.3, 0.3))
	_hero_ring.position = Vector3(hero.pos.x, 0.05, hero.pos.y)
	var tgt := sim.actor_by_id(hero.target_id)
	if tgt != null and tgt.alive:
		_target_ring.visible = true
		_target_ring.position = Vector3(tgt.pos.x, 0.06, tgt.pos.y)
		_target_ring.scale = Vector3(tgt.radius + 0.3, 0.25, tgt.radius + 0.3) / 0.75
	else:
		_target_ring.visible = false


func _update_camera() -> void:
	if cam == null or hero == null:
		return
	cam.position = Vector3(hero.pos.x, CAM_HEIGHT, hero.pos.y + CAM_BACK)
	cam.look_at(Vector3(hero.pos.x, 0.5, hero.pos.y), Vector3.UP)


func _on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"damage":
			_floater(data.actor, "-%d" % data.amount, Color(1, 0.35, 0.35), 56)
		"text":
			_floater(data.actor, data.text, data.get("color", Color.WHITE), 40)
		"cast":
			if data.skill != "attack":
				_floater(data.actor, data.name, Color(1, 1, 1), 40)
		"ready":
			_floater(data.actor, "READY", Color(0.8, 1, 0.8), 36)
		"blast":
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = data.radius
			cyl.bottom_radius = data.radius
			cyl.height = 0.08
			mi.mesh = cyl
			var m := _flat_material(Color(1, 0.5, 0.15, 0.7), true)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = m
			mi.position = Vector3(data.pos.x, 0.05, data.pos.y)
			add_child(mi)
			_blasts.append({"node": mi, "t": 0.5})


func _floater(a: Actor, text: String, color: Color, size: int) -> void:
	if cam == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.outline_size = 8
	l.position = Vector3(a.pos.x + sim.rng.randf_range(-0.4, 0.4), 3.1, a.pos.y)
	l.visible = false
	add_child(l)
	_floaters.append({"node": l, "t": 1.1, "delay": _floater_queue})
	_floater_queue += 0.22


func _update_effects(delta: float) -> void:
	_floater_queue = maxf(0.0, _floater_queue - delta)
	var i := 0
	while i < _floaters.size():
		var f: Dictionary = _floaters[i]
		var l: Label3D = f.node
		if f.delay > 0.0:
			f.delay -= delta
			i += 1
			continue
		l.visible = true
		f.t -= delta
		l.position.y += delta * 1.0
		var c: Color = l.modulate
		c.a = clampf(f.t * 1.5, 0.0, 1.0)
		l.modulate = c
		if f.t <= 0.0:
			l.queue_free()
			_floaters.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _blasts.size():
		var b: Dictionary = _blasts[i]
		b.t -= delta
		var n: MeshInstance3D = b.node
		var m: StandardMaterial3D = n.material_override
		m.albedo_color.a = clampf(b.t * 1.4, 0.0, 0.7)
		if b.t <= 0.0:
			n.queue_free()
			_blasts.remove_at(i)
		else:
			i += 1
