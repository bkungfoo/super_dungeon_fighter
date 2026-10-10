class_name SkillIcon
extends Control
## Draws a skill card as a symbol: a vector glyph for the action, a rank
## letter badge, stamina pips, a charge-time clock, and a rarity-coloured
## border. No text beyond the single rank letter, so it stays readable at
## phone sizes. Everything is drawn in a 100 x 100 design space.

var skill_id: String = "attack"
var rank: int = -1
var show_frame: bool = true
var chain: bool = false
var selected: bool = false
var dimmed: bool = false

const INK := Color(0.96, 0.95, 0.99)
const BG := Color(0.17, 0.16, 0.24)


func setup(sid: String, r: int) -> void:
	skill_id = sid
	rank = r
	queue_redraw()


func _s() -> float:
	return minf(size.x, size.y)


func _o() -> Vector2:
	return (size - Vector2.ONE * _s()) * 0.5


## Design-space point to pixels.
func P(x: float, y: float) -> Vector2:
	return _o() + Vector2(x, y) * (_s() / 100.0)


func W(w: float) -> float:
	return w * (_s() / 100.0)


func _poly(pts: Array, color: Color) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(P(p[0], p[1]))
	draw_colored_polygon(arr, color)


func _line(pts: Array, color: Color, w: float) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(P(p[0], p[1]))
	draw_polyline(arr, color, W(w), true)


func _arc(cx: float, cy: float, r: float, a0: float, a1: float, color: Color, w: float) -> void:
	draw_arc(P(cx, cy), W(r), deg_to_rad(a0), deg_to_rad(a1), 24, color, W(w), true)


func _dot(cx: float, cy: float, r: float, color: Color) -> void:
	draw_circle(P(cx, cy), W(r), color)


func _draw() -> void:
	var alpha := 0.35 if dimmed else 1.0
	var p := SkillDB.params(skill_id, rank) if SkillDB.get_def(skill_id).size() > 0 else {}
	var rarity_col: Color = SkillDB.RARITY_COLORS[SkillDB.rarity(skill_id, rank)] if not p.is_empty() else Color.WHITE
	if show_frame:
		var rect := Rect2(_o(), Vector2.ONE * _s())
		var sb := StyleBoxFlat.new()
		sb.bg_color = BG if not selected else BG.lightened(0.15)
		sb.set_corner_radius_all(int(W(12)))
		sb.border_color = Color(rarity_col, alpha) if not chain else Color(0.98, 0.76, 0.30, alpha)
		sb.set_border_width_all(int(W(6.0 if chain else 4.0)))
		draw_style_box(sb, rect)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ink := Color(INK, alpha)
	match skill_id:
		"attack":
			_glyph_sword(ink, false)
		"defend":
			_poly([[30, 18], [70, 18], [73, 50], [50, 84], [27, 50]], Color(0.55, 0.78, 1.0, alpha))
			_line([[50, 30], [50, 72]], Color(0.12, 0.2, 0.4, alpha), 5)
			_line([[36, 46], [64, 46]], Color(0.12, 0.2, 0.4, alpha), 5)
		"grab":
			_dot(50, 64, 17, Color(0.85, 0.55, 0.35, alpha))
			for f in [[26, 24, 40, 46], [42, 16, 47, 42], [58, 16, 53, 42], [74, 24, 60, 46]]:
				_line([[f[0], f[1]], [f[2], f[3]]], ink, 7)
		"bash":
			_line([[28, 82], [60, 46]], Color(0.75, 0.6, 0.4, alpha), 7)
			_dot(66, 38, 15, ink)
			for a in range(0, 360, 60):
				var r := deg_to_rad(a)
				_line([[66 + cos(r) * 15, 38 + sin(r) * 15], [66 + cos(r) * 22, 38 + sin(r) * 22]], ink, 4)
		"full_swing":
			_arc(28, 84, 56, 215, 335, Color(1, 0.8, 0.3, alpha), 5)
			_poly([[74, 24], [86, 36], [78, 44], [66, 32]], Color(1, 0.8, 0.3, alpha))
			_line([[24, 84], [60, 44]], Color(0.75, 0.6, 0.4, alpha), 7)
			_poly([[52, 28], [76, 52], [66, 62], [42, 38]], ink)
		"final_slash":
			_glyph_sword(ink, true)
		"whirlwind":
			var wind := Color(0.7, 0.9, 1.0, alpha)
			_arc(50, 30, 28, 190, 350, wind, 7)
			_arc(50, 48, 20, 190, 350, wind, 6)
			_arc(50, 64, 13, 190, 350, wind, 5)
			_arc(50, 78, 7, 190, 350, wind, 4)
		"fireball":
			_poly([[50, 10], [64, 34], [56, 30], [50, 42], [44, 30], [36, 34]], Color(1, 0.55, 0.15, alpha))
			_dot(50, 60, 24, Color(1, 0.45, 0.1, alpha))
			_dot(50, 62, 13, Color(1, 0.85, 0.3, alpha))
		"frost_nova":
			var ice := Color(0.7, 0.9, 1.0, alpha)
			for a in [0, 60, 120]:
				var r := deg_to_rad(a)
				_line([[50 - cos(r) * 36, 50 - sin(r) * 36], [50 + cos(r) * 36, 50 + sin(r) * 36]], ice, 5)
				for sgn in [-1, 1]:
					var tip := Vector2(50 + cos(r) * 26 * sgn, 50 + sin(r) * 26 * sgn)
					for b in [-1, 1]:
						var br: float = r + b * deg_to_rad(35)
						_line([[tip.x, tip.y], [tip.x + cos(br) * 10 * sgn, tip.y + sin(br) * 10 * sgn]], ice, 4)
			_dot(50, 50, 6, ice)
		"blink":
			var z := Color(0.85, 0.7, 1.0, alpha)
			_line([[22, 28], [46, 50], [22, 72]], z, 8)
			_line([[50, 28], [74, 50], [50, 72]], z, 8)
			for i in 3:
				_dot(14, 40 + i * 10, 2.5, z)
		"pounce":
			_dot(50, 62, 15, ink)
			for t in [[32, 42], [44, 34], [56, 34], [68, 42]]:
				_dot(t[0], t[1], 6, ink)
		_:
			_dot(50, 50, 20, ink)

	if p.is_empty() or not show_frame:
		return
	var font := ThemeDB.fallback_font
	# Rank badge.
	if SkillDB.has_ranks(skill_id):
		var br := Rect2(P(70, 6), Vector2(W(24), W(22)))
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(rarity_col, alpha)
		bsb.set_corner_radius_all(int(W(6)))
		draw_style_box(bsb, br)
		var fs := int(W(16))
		draw_string(font, P(70, 6 + 17), SkillDB.rank_label(skill_id, rank), HORIZONTAL_ALIGNMENT_CENTER, W(24), fs, Color(0.1, 0.08, 0.14, alpha))
	# Stamina pips.
	var cost: int = p.get("cost", 0)
	for i in mini(cost, 8):
		_dot(10 + i * 7, 92, 2.6, Color(0.98, 0.76, 0.30, alpha))
	# Charge clock.
	if p.get("load", 0) > 0:
		var c := Color(0.75, 0.8, 1.0, alpha)
		_arc(88, 90, 6, 0, 360, c, 2)
		_line([[88, 90], [88, 85]], c, 2)
		_line([[88, 90], [92, 90]], c, 2)


func _glyph_sword(ink: Color, speed: bool) -> void:
	_poly([[62, 12], [72, 22], [40, 64], [30, 54]], ink)
	_line([[26, 60], [46, 80]], Color(0.75, 0.6, 0.4, 1.0) * Color(1, 1, 1, ink.a), 6)
	_line([[34, 74], [20, 88]], Color(0.75, 0.6, 0.4, 1.0) * Color(1, 1, 1, ink.a), 7)
	if speed:
		for y in [30, 42, 54]:
			_line([[8, y], [26, y]], Color(1, 0.8, 0.3, ink.a), 3)
