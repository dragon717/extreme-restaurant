extends PanelContainer

const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")

const EDGE := Color("4d6768")
const INSET := Color("1c2d34")
const GRAY_TEXT := Color("c3c6c4")
const GRAY_MUTED := Color("a4a9a7")

var body := VBoxContainer.new()
var side := VBoxContainer.new()
var heading := HBoxContainer.new()
var locked := false

func build(glyph: String, title: String, accent: Color, sealed := false) -> void:
	locked = sealed
	custom_minimum_size.y = 78
	add_theme_stylebox_override("panel", Style.inset(10,9))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	var stamp := PanelContainer.new()
	stamp.custom_minimum_size = Vector2(52, 52)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tint = GRAY_TEXT if locked else accent
	stamp.add_theme_stylebox_override("panel", Style.box(Color("2d3234") if locked else INSET, tint.darkened(.48), 8, 0))
	var center := CenterContainer.new()
	stamp.add_child(center)
	center.add_child(Icon.make(glyph, tint, 27))
	row.add_child(stamp)

	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_theme_constant_override("separation", 5)
	row.add_child(body)
	body.add_child(heading)
	var label = Style.text(title, 17, tint if locked else Style.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)

	side.custom_minimum_size.x = 172
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side.add_theme_constant_override("separation", 4)
	row.add_child(side)
	if locked: _lock_mark()

func action(caption: String, allowed: bool, hint := "") -> Button:
	var button = Style.button(caption, allowed)
	button.tooltip_text = hint
	button.disabled = not allowed
	if locked:
		button.add_theme_stylebox_override("disabled", Style.box(Color("303638"), Color("62696a"), 7, 8))
		button.add_theme_color_override("font_disabled_color", GRAY_TEXT)
	side.add_child(button)
	return button

func _lock_mark() -> void:
	var layer := CenterContainer.new()
	layer.name = "UnlockMark"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", Style.box(Color("262b2e"), Color("838a89"), 9, 8))
	layer.add_child(badge)
	badge.add_child(Icon.make("lock", GRAY_TEXT, 23))
