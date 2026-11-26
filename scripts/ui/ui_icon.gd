extends Control

var glyph := ""
var tint := Color.WHITE
var extent := 20.0

static func make(name: String, color: Color, pixels := 20.0) -> Control:
	var icon = new()
	icon.glyph = name
	icon.tint = color
	icon.extent = pixels
	icon.custom_minimum_size = Vector2.ONE * pixels
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	return icon

static func center_in(button: Button, name: String, color: Color, pixels := 20.0) -> Control:
	var icon = make(name, color, pixels)
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(PRESET_CENTER)
	icon.offset_left = -pixels * 0.5
	icon.offset_top = -pixels * 0.5
	icon.offset_right = pixels * 0.5
	icon.offset_bottom = pixels * 0.5
	return icon

func set_glyph(name: String, color: Color) -> void:
	if glyph == name and tint == color: return
	glyph = name
	tint = color
	queue_redraw()

const SHEET = preload("res://assets/canyon/glyphs.webp")
const GLYPHS = ["district","history","follow","income","coins","reputation",
	"star","star_outline","clock","rent","settings","play",
	"pause","recipe","close","lock","expand","alert",
	"check","table","build","wall","move","rotate",
	"split","store","keys","stove","bag","trophy",
	"chef","crowd","door","sun","moon","rain"]

static func region(name: String) -> Rect2:
	var i := GLYPHS.find(name)
	if i < 0: return Rect2()
	return Rect2((i % 6) * 64, floori(i / 6.0) * 64, 64, 64)

func _draw() -> void:
	var source := region(glyph)
	if source.has_area():
		var bounds := Rect2((size - Vector2.ONE * extent) * 0.5, Vector2.ONE * extent)
		draw_texture_rect_region(SHEET, bounds, source, Color.WHITE.lerp(tint, 0.25))
