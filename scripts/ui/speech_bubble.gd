extends PanelContainer
## A speaker and a message. World bubbles follow an anchor in parent-local pixels;
## the same control can be placed inline in a menu without a world or simulation.

const Style = preload("res://scripts/ui/style.gd")
const Actor = preload("res://scripts/visuals/actor_view.gd")
const PAPER = Color("fff2d6")
const LETTERS = Color("302b24")
var content := VBoxContainer.new()
var actions := HBoxContainer.new()
var tail := Polygon2D.new()
var anchor: Callable
var remaining := -1.0
var keep_on_screen := false
var compact := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Style.box(PAPER, Color("8f6844"), 10, 12))
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	content.add_child(actions)
	actions.hide()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.color = PAPER
	add_child(tail)
	tail.hide()
	set_process(false)

func set_line(speaker: String, message: String, portrait := "") -> void:
	var header = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)
	if not portrait.is_empty():
		var face = TextureRect.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.custom_minimum_size = Vector2(28, 28)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var actor = Actor.new()
		actor.set_visual(portrait)
		actor.present("idle")
		if actor.sprite.sprite_frames.get_frame_count(actor.sprite.animation) > 0:
			face.texture = actor.sprite.sprite_frames.get_frame_texture(actor.sprite.animation, 0)
		actor.free()
		header.add_child(face)
	header.add_child(Style.text(speaker, 15, Color("72502f")))
	var line = Style.text(message, 16, LETTERS, true)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(line)
	content.move_child(actions, -1)

func set_remark(speaker: String, message: String, accent: Color) -> void:
	compact = true
	accessibility_name = speaker + "：" + message
	var skin = Style.box(Color("fff4df"), accent.darkened(.25), 5, 5)
	skin.content_margin_top = 2
	skin.content_margin_bottom = 2
	add_theme_stylebox_override("panel", skin)
	tail.color = Color("fff4df")
	var measured = Style.font().get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var line = Style.text(message, 12, LETTERS, measured + 12 > 108)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(line)
	custom_minimum_size.x = clampf(ceilf(measured) + 12, 36, 108)

func add_choice(caption: String, callback: Callable, primary := false) -> Button:
	var choice = Style.button(caption, primary)
	choice.pressed.connect(callback)
	actions.add_child(choice)
	actions.show()
	return choice

func follow(get_anchor: Callable, seconds: float, dock_if_offscreen := false) -> void:
	anchor = get_anchor
	remaining = seconds
	keep_on_screen = dock_if_offscreen
	if not compact: custom_minimum_size.x = 332
	size.x = custom_minimum_size.x
	z_index = 4095
	set_process(true)
	_place()

func dismiss() -> void:
	hide()
	set_process(false)
	queue_free()

func _process(delta: float) -> void:
	if remaining >= 0:
		remaining -= delta
		if remaining <= 0:
			dismiss()
			return
	_place(true)

func _place(after_world_update := false) -> void:
	var board = get_parent_control()
	var extent: Vector2 = board.camera_extent() if board.has_method("camera_extent") else board.size
	var point = anchor.call() if anchor.is_valid() else null
	var on_screen = point is Vector2 and Rect2(Vector2.ZERO, extent).has_point(point)
	if not on_screen and not keep_on_screen:
		hide()
		if point == null and after_world_update: dismiss()
		return
	show()
	size.y = get_combined_minimum_size().y
	var center: Vector2 = point if on_screen else Vector2(extent.x * 0.5, extent.y - 100)
	var tail_length = 5.0 if compact else 12.0
	var above = center.y - size.y - tail_length - 2 >= 78
	var bubble_y = center.y - size.y - tail_length if above else center.y + tail_length + (3 if compact else 10)
	position = Vector2(clampf(center.x - size.x * 0.5, 10, extent.x - size.x - 10),
		clampf(bubble_y, 76, maxf(76, extent.y - size.y - 76)))
	var inset = 7.0 if compact else 14.0
	var tip = clampf(center.x - position.x, inset, size.x - inset)
	var base = size.y - 2 if above else 2.0
	var end = base + tail_length if above else base - tail_length
	var half_width = 4.0 if compact else 9.0
	tail.polygon = PackedVector2Array([Vector2(tip - half_width, base), Vector2(tip + half_width, base), Vector2(tip, end)])
	tail.visible = on_screen and absf(center.x - position.x - tip) < 12
