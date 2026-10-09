class_name BoardView
extends Control
## Draws the dungeon grid and units, animates moves, shows floating text,
## and turns taps into cell signals.

signal cell_tapped(cell: Vector2i)

const FLOOR := Color(0.24, 0.22, 0.30)
const FLOOR_ALT := Color(0.27, 0.25, 0.34)
const WALL := Color(0.09, 0.08, 0.12)
const GRID_LINE := Color(0.14, 0.13, 0.19)

var engine: GameEngine
var highlights: Dictionary = {}       # Vector2i -> Color
var move_arrows: Dictionary = {}      # unit_id -> Vector2i dest
var plan_labels: Dictionary = {}      # unit_id -> String
var selected_id: int = -1
var _anim_pos: Dictionary = {}        # unit_id -> Vector2 (cell coordinates, fractional)
var _dead_fade: Dictionary = {}       # unit_id -> float remaining
var _floaters: Array = []             # {pos: Vector2, text, color, t, delay, big}
var _queue_time: float = 0.0          # staggers floaters so a reveal plays back as a sequence
var _font: Font

const FLOATER_STEP := 0.28
const FLOATER_LIFE := 1.4


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func bind(e: GameEngine) -> void:
	engine = e
	engine.event.connect(_on_event)
	_anim_pos.clear()
	for u in engine.units:
		_anim_pos[u.id] = Vector2(u.pos)
	queue_redraw()


func cell_size() -> float:
	if engine == null:
		return 100.0
	return minf(size.x / engine.grid.cols, size.y / engine.grid.rows)


func origin() -> Vector2:
	if engine == null:
		return Vector2.ZERO
	var cs := cell_size()
	return Vector2((size.x - cs * engine.grid.cols) * 0.5, (size.y - cs * engine.grid.rows) * 0.5)


func cell_rect(c: Vector2i) -> Rect2:
	var cs := cell_size()
	return Rect2(origin() + Vector2(c) * cs, Vector2(cs, cs))


func cell_center(c: Vector2) -> Vector2:
	var cs := cell_size()
	return origin() + (c + Vector2(0.5, 0.5)) * cs


func cell_from_point(p: Vector2) -> Vector2i:
	var cs := cell_size()
	var local := (p - origin()) / cs
	return Vector2i(floori(local.x), floori(local.y))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_from_point(event.position)
		if engine != null and engine.grid.in_bounds(c):
			cell_tapped.emit(c)
			accept_event()


func _push_floater(pos: Vector2i, text: String, color: Color, big: bool) -> void:
	_floaters.append({"pos": Vector2(pos), "text": text, "color": color, "t": FLOATER_LIFE, "delay": _queue_time, "big": big})
	_queue_time += FLOATER_STEP


func _on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"move":
			var u: Unit = data.unit
			if not _anim_pos.has(u.id):
				_anim_pos[u.id] = Vector2(data.from)
		"damage":
			_push_floater(data.pos, "-%d" % data.amount, Color(1, 0.35, 0.35), true)
		"text":
			_push_floater(data.pos, data.text, data.get("color", Color.WHITE), false)
		"skill":
			var u: Unit = data.unit
			_push_floater(u.pos, data.name, Color(1, 1, 1), false)
		"death":
			var u: Unit = data.unit
			_dead_fade[u.id] = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if engine == null:
		return
	var busy := false
	for u in engine.units:
		if not _anim_pos.has(u.id):
			_anim_pos[u.id] = Vector2(u.pos)
		var target := Vector2(u.pos)
		var cur: Vector2 = _anim_pos[u.id]
		if cur.distance_to(target) > 0.01:
			_anim_pos[u.id] = cur.move_toward(target, delta * 6.0)
			busy = true
	for id in _dead_fade.keys():
		_dead_fade[id] -= delta
		if _dead_fade[id] <= 0:
			_dead_fade.erase(id)
		busy = true
	var i := 0
	while i < _floaters.size():
		var f: Dictionary = _floaters[i]
		if f.delay > 0.0:
			f.delay -= delta
		else:
			f.t -= delta
		if f.t <= 0:
			_floaters.remove_at(i)
		else:
			i += 1
		busy = true
	if _floaters.is_empty():
		_queue_time = 0.0
	else:
		_queue_time = maxf(0.0, _queue_time - delta)
	if busy:
		queue_redraw()


func is_animating() -> bool:
	return not _floaters.is_empty()


func _draw() -> void:
	if engine == null:
		return
	var cs := cell_size()
	var g := engine.grid
	for c in g.all_cells():
		var r := cell_rect(c)
		var col := FLOOR if (c.x + c.y) % 2 == 0 else FLOOR_ALT
		if g.is_wall(c):
			col = WALL
		draw_rect(r, col)
		if highlights.has(c):
			draw_rect(r.grow(-3), highlights[c])
		draw_rect(r, GRID_LINE, false, 2.0)
		if g.is_wall(c):
			draw_line(r.position + Vector2(cs * 0.25, cs * 0.25), r.position + Vector2(cs * 0.75, cs * 0.75), Color(0.2, 0.18, 0.26), 3.0)
			draw_line(r.position + Vector2(cs * 0.75, cs * 0.25), r.position + Vector2(cs * 0.25, cs * 0.75), Color(0.2, 0.18, 0.26), 3.0)

	# Planned movement arrows.
	for id in move_arrows:
		var u := engine.unit_by_id(id)
		if u == null:
			continue
		var a := cell_center(Vector2(u.pos))
		var b := cell_center(Vector2(move_arrows[id]))
		draw_line(a, b, Color(1, 1, 1, 0.6), 5.0)
		draw_circle(b, cs * 0.12, Color(1, 1, 1, 0.8))

	# Units.
	var fs_big := int(cs * 0.34)
	var fs_small := int(cs * 0.17)
	for u in engine.units:
		var alpha := 1.0
		if not u.alive:
			if not _dead_fade.has(u.id):
				continue
			alpha = _dead_fade[u.id]
		var p: Vector2 = _anim_pos.get(u.id, Vector2(u.pos))
		var center := cell_center(p)
		var color: Color = _unit_color(u)
		color.a = alpha
		var radius := cs * 0.36
		if u.id == selected_id:
			draw_circle(center, radius + 7, Color(1, 1, 1, 0.9))
		if u.state == Unit.State.DOWN:
			draw_set_transform(center, 0.0, Vector2(1.25, 0.6))
			draw_circle(Vector2.ZERO, radius, color.darkened(0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(center, radius, color)
			if u.is_boss:
				draw_arc(center, radius + 3, 0, TAU, 32, Color(1, 0.9, 0.3, alpha), 4.0)
		if u.defending:
			draw_arc(center, radius + 4, 0, TAU, 32, Color(0.6, 0.9, 1.0, alpha), 5.0)
		if u.has_shield:
			draw_arc(center, radius - 5, PI * 0.3, PI * 0.7, 12, Color(0.9, 0.9, 1.0, alpha * 0.8), 4.0)
		var initial: String = u.name.substr(0, 1).to_upper()
		var text_col := Color(0.08, 0.07, 0.1, alpha)
		draw_string(_font, center + Vector2(-cs * 0.5, fs_big * 0.36), initial, HORIZONTAL_ALIGNMENT_CENTER, cs, fs_big, text_col)
		# Life bar.
		var bar_w := cs * 0.8
		var bar := Rect2(center + Vector2(-bar_w * 0.5, radius + 4), Vector2(bar_w, cs * 0.08))
		draw_rect(bar, Color(0, 0, 0, 0.7 * alpha))
		var frac: float = clampf(float(u.life) / float(u.max_life), 0.0, 1.0)
		var life_col := Color(0.3, 0.9, 0.4, alpha) if frac > 0.5 else (Color(1, 0.8, 0.2, alpha) if frac > 0.25 else Color(1, 0.3, 0.3, alpha))
		draw_rect(Rect2(bar.position, Vector2(bar_w * frac, bar.size.y)), life_col)
		# Status text.
		var status: String = u.short_status()
		if status != "":
			draw_string(_font, center + Vector2(-cs * 0.5, -radius - 6), status, HORIZONTAL_ALIGNMENT_CENTER, cs, fs_small, Color(1, 0.95, 0.6, alpha))
		if plan_labels.has(u.id):
			draw_string(_font, center + Vector2(-cs * 0.6, radius + cs * 0.08 + fs_small + 6), plan_labels[u.id], HORIZONTAL_ALIGNMENT_CENTER, cs * 1.2, fs_small, Color(1, 1, 1, alpha))

	# Floating text, played back in order. Text near the top edge drops below the unit instead.
	var board_top: float = origin().y
	for f in _floaters:
		if f.delay > 0.0:
			continue
		var life: float = f.t
		var progress: float = (FLOATER_LIFE - life) / FLOATER_LIFE
		var rise: float = progress * cs * 0.5
		var col: Color = f.color
		col.a = clampf(life * 1.5, 0.0, 1.0)
		var fsz := int(cs * (0.32 if f.big else 0.22))
		var center := cell_center(f.pos)
		var y: float = center.y - cs * 0.15 - rise
		if y - fsz < board_top:
			y = center.y + cs * 0.45 + rise
		var pos := Vector2(center.x - cs, y)
		draw_string(_font, pos + Vector2(2, 2), f.text, HORIZONTAL_ALIGNMENT_CENTER, cs * 2, fsz, Color(0, 0, 0, col.a))
		draw_string(_font, pos, f.text, HORIZONTAL_ALIGNMENT_CENTER, cs * 2, fsz, col)


func _unit_color(u: Unit) -> Color:
	if u.is_hero():
		return HeroDB.get_def(u.cls).get("color", Color(0.4, 0.6, 1.0))
	return MonsterDB.get_def(u.cls).get("color", Color(0.9, 0.3, 0.3))
