extends RefCounted

const Icon = preload("res://scripts/ui/ui_icon.gd")
const BUNDLED_FONT = preload("res://assets/fonts/CanyonUISans.ttf")
const DISPLAY_FONT = preload("res://assets/fonts/UncialAntiqua-Regular.ttf")
const PIGMENT = preload("res://assets/interface/menu-pigment.webp")
const PANEL_ART = preload("res://assets/interface/oiled-slate.png")
const ENAMEL = preload("res://assets/interface/enamel.png")
const PAPER = preload("res://assets/canyon/paper.webp")
const GOLD_THREAD = preload("res://assets/interface/brass_thread.tres")
const REVEAL = preload("res://scenes/ui/art_motion.tscn")
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
	cached_font = BUNDLED_FONT
	return cached_font

static func box(color: Color = PANEL, border: Color = GOLD, radius: int = 10, margin: int = 14) -> StyleBoxTexture:
	return frame(color, border, margin, radius)

static func surface(accent: Color, margin := 14) -> StyleBoxTexture:
	return frame(Color("16272e", .96).lerp(accent, .08), accent.darkened(.56), margin, 7)

static func frame(fill: Color, border: Color, margin := 16, radius := 7) -> StyleBoxTexture:
	var surface := StyleBoxTexture.new()
	var bright := fill.get_luminance() > .44
	var focus := fill.a == 0.0
	surface.texture = PAPER if bright else ENAMEL
	if bright:
		surface.region_rect = Rect2(22, 22, 52, 52)
		surface.modulate_color = fill.lightened(.16)
	elif focus:
		surface.region_rect = Rect2(Vector2.ZERO, ENAMEL.get_size())
		surface.modulate_color = border.lightened(.4)
		surface.draw_center = false
	else:
		surface.region_rect = Rect2(50, 40, 1436, 940)
		surface.modulate_color = Color(fill.r * 8.5 + .46, fill.g * 3.1 + .46, fill.b * 3.4 + .46, fill.a)
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		surface.set_content_margin(edge, margin)
		if focus: surface.set_texture_margin(edge, clampi(radius, 4, 9))
	return surface

static func art_plate() -> StyleBoxTexture:
	var plate := StyleBoxTexture.new()
	plate.texture = PANEL_ART
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		plate.set_content_margin(edge, 5)
	return plate

# Rows borrow space from the enclosing plate. Only the current choice receives ink.
static func inset(horizontal := 9, vertical := 6) -> StyleBoxEmpty:
	var space := StyleBoxEmpty.new()
	for edge in [SIDE_LEFT,SIDE_RIGHT]: space.set_content_margin(edge,horizontal)
	for edge in [SIDE_TOP,SIDE_BOTTOM]: space.set_content_margin(edge,vertical)
	return space

static func wash(opacity: float, horizontal := 9, vertical := 6) -> StyleBoxTexture:
	var mark := StyleBoxTexture.new()
	mark.texture = PIGMENT
	mark.modulate_color = Color(1.,.93,.77,opacity)
	for edge in [SIDE_LEFT,SIDE_RIGHT]: mark.set_content_margin(edge,horizontal)
	for edge in [SIDE_TOP,SIDE_BOTTOM]: mark.set_content_margin(edge,vertical)
	return mark

static func quiet_button(b: Button, selected := false) -> void:
	b.add_theme_stylebox_override("normal",wash(.19) if selected else inset())
	b.add_theme_stylebox_override("disabled",inset())
	b.add_theme_stylebox_override("hover",wash(.22))
	b.add_theme_stylebox_override("pressed",wash(.31))
	b.add_theme_color_override("font_focus_color",Color("fff0cb"))
	b.add_theme_color_override("font_hover_color",Color("fff0cb"))

static func list_theme() -> Theme:
	var t := theme()
	t.set_stylebox("panel","PanelContainer",inset())
	for kind in ["Button","OptionButton"]:
		t.set_stylebox("normal",kind,inset())
		t.set_stylebox("hover",kind,wash(.21))
		t.set_stylebox("pressed",kind,wash(.29))
		t.set_stylebox("disabled",kind,inset())
	t.set_stylebox("panel","PopupMenu",art_plate())
	t.set_stylebox("hover","PopupMenu",wash(.22))
	return t

static func theme() -> Theme:
	var t = Theme.new()
	t.default_font = font()
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("a5b6b3"))
	t.set_stylebox("normal", "Button", frame(Color("25383c"), Color("596d6a"), 10))
	t.set_stylebox("hover", "Button", frame(Color("31484a"), Color("b89a65"), 10))
	t.set_stylebox("pressed", "Button", frame(Color("16282d"), Color("bd975e"), 10))
	t.set_stylebox("disabled", "Button", frame(Color("263136"), Color("465655"), 10))
	var focus := frame(Color.TRANSPARENT, Color("ffd597"), 0, 7)
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		focus.set_expand_margin(edge, 2)
	t.set_stylebox("focus", "Button", focus)
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
	label.text = TranslationServer.translate(value)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func button(value: String, accent: bool = false) -> Button:
	var b = Button.new()
	b.text = TranslationServer.translate(value)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 38
	if accent: accent_button(b)
	return b

static func accent_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(Color("d6a65c"), Color("f1cd8b"), 7, 10))
	button.add_theme_stylebox_override("hover", box(Color("edbf78"), Color("f1cd8b"), 7, 10))
	button.add_theme_stylebox_override("pressed", box(Color("ba8d45"), Color("f1cd8b"), 7, 10))
	for color in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color, Color("213325"))

static func facility_name(value: String) -> String:
	var translated := str(TranslationServer.translate(value))
	if translated != value: return translated
	for prefix in ["餐桌 ", "灶台 "]:
		if value.begins_with(prefix): return TranslationServer.translate(prefix) + value.substr(prefix.length())
	return value

static func card() -> PanelContainer:
	return PanelContainer.new()

static func readout(parent: Control, glyph: String, value: String, description: String, tint: Color = GOLD, points := 17) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = TranslationServer.translate(description)
	parent.add_child(row)
	row.add_child(Icon.make(glyph, tint, 18.0))
	var label = text(value, points, tint)
	label.tooltip_text = row.tooltip_text
	row.add_child(label)
	return label
