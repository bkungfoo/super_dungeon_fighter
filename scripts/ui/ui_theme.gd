extends Node
## Builds a touch-friendly theme in code and applies it to the root window.
## Also provides small helpers for building UI from scripts.

const BG := Color(0.11, 0.10, 0.16)
const PANEL := Color(0.17, 0.16, 0.24)
const PANEL_LIGHT := Color(0.23, 0.22, 0.32)
const ACCENT := Color(0.98, 0.76, 0.30)
const DANGER := Color(0.90, 0.33, 0.33)
const OK := Color(0.40, 0.80, 0.50)
const TEXT := Color(0.94, 0.93, 0.98)
const TEXT_DIM := Color(0.70, 0.69, 0.78)

var theme: Theme


func _ready() -> void:
	theme = _build_theme()
	get_tree().root.theme = theme
	RenderingServer.set_default_clear_color(BG)


func _flat(color: Color, radius: int = 18, border: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 34

	# Buttons: big tap targets.
	t.set_stylebox("normal", "Button", _flat(PANEL_LIGHT))
	t.set_stylebox("hover", "Button", _flat(PANEL_LIGHT.lightened(0.08)))
	t.set_stylebox("pressed", "Button", _flat(PANEL_LIGHT.darkened(0.2)))
	t.set_stylebox("disabled", "Button", _flat(PANEL.darkened(0.1)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_font_size("font_size", "Button", 36)

	for variation in ["PrimaryButton", "DangerButton", "OkButton"]:
		t.set_type_variation(variation, "Button")
	t.set_stylebox("normal", "PrimaryButton", _flat(ACCENT))
	t.set_stylebox("hover", "PrimaryButton", _flat(ACCENT.lightened(0.1)))
	t.set_stylebox("pressed", "PrimaryButton", _flat(ACCENT.darkened(0.2)))
	t.set_stylebox("disabled", "PrimaryButton", _flat(ACCENT.darkened(0.55)))
	t.set_color("font_color", "PrimaryButton", Color(0.12, 0.1, 0.08))
	t.set_color("font_pressed_color", "PrimaryButton", Color(0.12, 0.1, 0.08))
	t.set_color("font_hover_color", "PrimaryButton", Color(0.12, 0.1, 0.08))
	t.set_font_size("font_size", "PrimaryButton", 40)
	t.set_stylebox("normal", "DangerButton", _flat(DANGER))
	t.set_stylebox("hover", "DangerButton", _flat(DANGER.lightened(0.1)))
	t.set_stylebox("pressed", "DangerButton", _flat(DANGER.darkened(0.2)))
	t.set_stylebox("normal", "OkButton", _flat(OK))
	t.set_stylebox("hover", "OkButton", _flat(OK.lightened(0.1)))
	t.set_stylebox("pressed", "OkButton", _flat(OK.darkened(0.2)))
	t.set_stylebox("disabled", "OkButton", _flat(OK.darkened(0.55)))
	t.set_color("font_color", "OkButton", Color(0.08, 0.14, 0.1))

	t.set_type_variation("SkillButton", "Button")
	var sb := _flat(PANEL_LIGHT, 14, ACCENT, 0)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	t.set_stylebox("normal", "SkillButton", sb)
	var sb2 := sb.duplicate()
	sb2.bg_color = ACCENT.darkened(0.35)
	t.set_stylebox("pressed", "SkillButton", sb2)
	t.set_stylebox("hover", "SkillButton", sb)
	var sb3 := sb.duplicate()
	sb3.bg_color = PANEL.darkened(0.1)
	t.set_stylebox("disabled", "SkillButton", sb3)
	t.set_font_size("font_size", "SkillButton", 30)

	# Labels.
	t.set_color("font_color", "Label", TEXT)
	for variation in ["TitleLabel", "HeadingLabel", "SmallLabel", "DimLabel"]:
		t.set_type_variation(variation, "Label")
	t.set_font_size("font_size", "TitleLabel", 72)
	t.set_color("font_color", "TitleLabel", ACCENT)
	t.set_font_size("font_size", "HeadingLabel", 46)
	t.set_font_size("font_size", "SmallLabel", 28)
	t.set_font_size("font_size", "DimLabel", 28)
	t.set_color("font_color", "DimLabel", TEXT_DIM)

	# Panels and containers.
	var panel := _flat(PANEL, 22)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_constant("separation", "VBoxContainer", 16)
	t.set_constant("separation", "HBoxContainer", 16)
	t.set_stylebox("normal", "RichTextLabel", _flat(BG.darkened(0.2), 14))
	t.set_color("default_color", "RichTextLabel", TEXT_DIM)
	t.set_font_size("normal_font_size", "RichTextLabel", 26)
	t.set_stylebox("normal", "LineEdit", _flat(BG.darkened(0.2), 14, ACCENT, 2))
	t.set_stylebox("focus", "LineEdit", _flat(BG.darkened(0.2), 14, ACCENT, 3))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font_size("font_size", "LineEdit", 36)
	t.set_font_size("font_size", "CheckBox", 36)
	t.set_font_size("font_size", "CheckButton", 36)
	t.set_font_size("font_size", "OptionButton", 36)
	t.set_stylebox("normal", "OptionButton", _flat(PANEL_LIGHT))
	t.set_stylebox("hover", "OptionButton", _flat(PANEL_LIGHT.lightened(0.08)))
	t.set_stylebox("pressed", "OptionButton", _flat(PANEL_LIGHT.darkened(0.2)))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "PopupMenu", 36)
	t.set_stylebox("grabber", "VScrollBar", _flat(PANEL_LIGHT, 8))
	t.set_stylebox("scroll", "VScrollBar", _flat(BG, 8))
	return t


# ------------------------------------------------------------------ helpers

func label(text: String, variation: String = "", align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != "":
		l.theme_type_variation = variation
	return l


func button(text: String, callback: Callable, variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(callback)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func vbox(sep: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func hbox(sep: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


func margin(left: int = 32, top: int = 32, right: int = 32, bottom: int = 32) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	return m


func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func spacer(min_height: int = 0) -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.y = min_height
	return c


func clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func go(scene_path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", scene_path)


## Full-screen modal overlay with a centred panel. Returns the panel's VBox.
func modal(parent: Node, title: String) -> Dictionary:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := panel()
	p.custom_minimum_size = Vector2(960, 0)
	center.add_child(p)
	var m := margin(32, 32, 32, 32)
	p.add_child(m)
	var v := vbox(20)
	m.add_child(v)
	if title != "":
		v.add_child(label(title, "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	parent.add_child(overlay)
	return {"overlay": overlay, "vbox": v}
