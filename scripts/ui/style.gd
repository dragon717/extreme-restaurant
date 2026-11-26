extends RefCounted

const Icon = preload("res://scripts/ui/ui_icon.gd")
const INK = Color("fbf0dc")
const MUTED = Color("b6c9c2")
const BG = Color("162831")
const PANEL = Color("233b40")
const PANEL_LIGHT = Color("304b4e")
const GOLD = Color("f1c181")
const GREEN = Color("9cd7bd")
const RED = Color("ffad98")

static var cached_font: Font

static func font() -> Font:
	if cached_font != null: return cached_font
	var settings = JSON.parse_string(FileAccess.get_file_as_string("res://assets/skins.json"))
	var custom = str(settings.get("font", "")) if settings is Dictionary else ""
	if not custom.is_empty() and ResourceLoader.exists(custom):
		cached_font = load(custom)
		return cached_font
	var system = SystemFont.new()
	system.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "Arial"])
	system.font_weight = 400
	cached_font = system
	return cached_font

const PANEL_ART = preload("res://assets/canyon/panel.webp")
const BUTTON_ART = preload("res://assets/canyon/button.webp")
const PAPER_ART = preload("res://assets/canyon/paper.webp")

static func box(color: Color = PANEL, border: Color = GOLD, radius: int = 10, margin: int = 14) -> StyleBoxTexture:
	var skin := StyleBoxTexture.new()
	skin.texture = PAPER_ART
	skin.modulate_color = color
	var edge := clampi(radius, 1, 10)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		skin.set_texture_margin(side, edge)
		skin.set_content_margin(side, margin)
	if color.a == 0:
		skin.draw_center = false
		skin.modulate_color = border
	return skin

static func surface(accent: Color, margin := 14) -> StyleBoxTexture:
	var skin := box(Color.WHITE, accent, 9, margin)
	skin.texture = PANEL_ART
	skin.modulate_color = Color.WHITE.lerp(accent, 0.12)
	return skin

static func button_skin(tint: Color) -> StyleBoxTexture:
	var skin := box(tint, GOLD, 7, 10)
	skin.texture = BUTTON_ART
	return skin

static func theme() -> Theme:
	var t = Theme.new()
	t.default_font = font()
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("a5b6b3"))
	t.set_stylebox("normal", "Button", button_skin(Color("b8cccb")))
	t.set_stylebox("hover", "Button", button_skin(Color.WHITE))
	t.set_stylebox("pressed", "Button", button_skin(Color("94aaa0")))
	t.set_stylebox("disabled", "Button", button_skin(Color("859093")))
	t.set_stylebox("focus", "Button", box(Color(0,0,0,0), GOLD, 7, 2))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color("526b68")))
	t.set_stylebox("panel", "TooltipPanel", surface(GOLD, 10))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_stylebox("normal", "LineEdit", box(BG, MUTED.darkened(0.38), 7, 10))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("focus", "LineEdit", box(BG, GOLD, 7, 10))
	t.set_stylebox("scroll", "VScrollBar", box(BG, BG, 5, 4))
	t.set_stylebox("grabber", "VScrollBar", box(Color("658782"), Color("658782"), 5, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GREEN, GREEN, 5, 4))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_stylebox("background", "ProgressBar", box(Color("304536"), Color("304536"), 3, 0))
	t.set_stylebox("fill", "ProgressBar", box(GREEN, GREEN, 3, 0))
	return t

static func text(value: String, size: int = 15, color: Color = INK, wrap: bool = false) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func button(value: String, accent: bool = false) -> Button:
	var b = Button.new()
	b.text = value
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 38
	if accent:
		b.add_theme_stylebox_override("normal", box(Color("d6a65c"), Color("f1cd8b"), 7, 10))
		b.add_theme_stylebox_override("hover", box(Color("edbf78"), Color("f1cd8b"), 7, 10))
		b.add_theme_stylebox_override("pressed", box(Color("ba8d45"), Color("f1cd8b"), 7, 10))
		b.add_theme_color_override("font_color", Color("213325"))
		b.add_theme_color_override("font_hover_color", Color("213325"))
		b.add_theme_color_override("font_pressed_color", Color("213325"))
	return b

static func card() -> PanelContainer:
	return PanelContainer.new()

static func readout(parent: Control, glyph: String, value: String, description: String, tint: Color = GOLD, points := 17) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = description
	parent.add_child(row)
	row.add_child(Icon.make(glyph, tint, 18.0))
	var label = text(value, points, tint)
	label.tooltip_text = description
	row.add_child(label)
	return label
