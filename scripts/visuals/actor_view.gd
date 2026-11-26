extends Node2D

const Lighting = preload("res://scripts/visuals/restaurant_lighting.gd")

const Style = preload("res://scripts/ui/style.gd")
var sprite = AnimatedSprite2D.new()
var visual_key = ""
var current_action = "idle"
var animation_map: Dictionary = {}
var indicator = ""
var progress = -1.0
var has_food = false
var patience_ratio = -1.0:
	set(value):
		if is_equal_approx(patience_ratio, value): return
		patience_ratio = value
		queue_redraw()
var rare_name = ""
var label_font: Font
var art_scale := 1.0
var faces_left := false
var sprite_base_scale = 1.55
var sprite_base_offset = Vector2(0, -6)
var display_zoom = 1.0
var shadow_direction = Vector2.ZERO
var shadow_opacity = 0.16
var world_cell := Vector2.INF
var light_band := -1
var animation_dirty := true
static var frame_cache: Dictionary = {}
static var manifest: Variant
static var shared_light_band := -1
static var shared_shadow_direction := Vector2.ZERO
static var shared_evening := 0.0
static var chip_skin = Style.box(Color("233940", .95), Color("667e76"), 6, 0)
static var rare_skin = Style.box(Color("334343", .95), Color("bc945e"), 6, 0)
static var special_skin = Style.box(Color("4a3542", .95), Color("be887e"), 6, 0)

func _init() -> void:
	add_child(sprite)
	sprite.z_index = -1
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.light_mask = 2
	label_font = Style.font()
	_apply_sprite_geometry()

func _apply_sprite_geometry() -> void:
	sprite.scale = Vector2.ONE * sprite_base_scale * art_scale * display_zoom
	sprite.position = sprite_base_offset * display_zoom

func place_in_world(cell: Vector2, point: Vector2, magnification: float) -> void:
	if world_cell.is_finite() and absf(cell.x - world_cell.x) > .01:
		sprite.flip_h = (cell.x < world_cell.x) != faces_left
	world_cell = cell
	position = point
	z_index = int(point.y)
	set_display_zoom(magnification)

func set_display_zoom(value: float) -> void:
	if is_equal_approx(value, display_zoom): return
	display_zoom = value
	_apply_sprite_geometry()
	queue_redraw()

func set_visual(kind: String) -> void:
	if visual_key == kind: return
	visual_key = kind
	animation_dirty = true
	if manifest == null:
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/skins.json"))
		manifest = data if data is Dictionary else {}
	var entry = manifest.get(kind, "") if manifest is Dictionary else ""
	var custom = str(entry.get("frames", "")) if entry is Dictionary else str(entry)
	art_scale = float(entry.get("art_scale", 1.0)) if entry is Dictionary else 1.0
	faces_left = bool(entry.get("faces_left", false)) if entry is Dictionary else false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if art_scale != 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	animation_map = entry.get("animation_map", {}).duplicate() if entry is Dictionary else {}
	sprite_base_scale = float(entry.get("scale", 1.55)) if entry is Dictionary else 1.55
	var offset = entry.get("offset", [0, -6]) if entry is Dictionary else [0, -6]
	sprite_base_offset = Vector2(float(offset[0]), float(offset[1]))
	_apply_sprite_geometry()
	if not custom.is_empty() and ResourceLoader.exists(custom):
		var resource = load(custom)
		if resource is SpriteFrames:
			sprite.sprite_frames = resource
			return
	if not frame_cache.has(kind): frame_cache[kind] = _make_frames(kind)
	sprite.sprite_frames = frame_cache[kind]

func present(action: String, state_label: String = "", amount: float = -1.0, carrying: bool = false, name_tag: String = "") -> void:
	var new_action = action != current_action or animation_dirty
	if not new_action and state_label == indicator and is_equal_approx(amount, progress) and carrying == has_food and name_tag == rare_name:
		return
	current_action = action
	indicator = state_label
	progress = amount
	has_food = carrying
	rare_name = name_tag
	animation_dirty = false
	if new_action and sprite.sprite_frames != null:
		var desired = str(animation_map.get(action, action))
		var animation = desired if sprite.sprite_frames.has_animation(desired) else str(animation_map.get("idle", "idle"))
		if not sprite.sprite_frames.has_animation(animation):
			var names = sprite.sprite_frames.get_animation_names()
			if names.is_empty(): return
			animation = names[0]
		if sprite.animation != animation or not sprite.is_playing(): sprite.play(animation)
	queue_redraw()

var flare_sprite: Sprite2D
const FLAME = preload("res://assets/canyon/flame.webp")

func show_flare(active: bool, tick: int, tick_ms: int) -> void:
	if active and flare_sprite == null:
		flare_sprite = Sprite2D.new()
		flare_sprite.texture = FLAME
		flare_sprite.hframes = 4
		flare_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(flare_sprite)
	if flare_sprite != null:
		flare_sprite.visible = active
		if active:
			flare_sprite.position = Vector2(12, -8) * display_zoom
			flare_sprite.scale = Vector2.ONE * display_zoom * 0.35
			flare_sprite.frame = floori(tick * tick_ms / 140.0) % 4

func set_sunlight(minutes: float) -> void:
	var band = floori(minutes / 3.0)
	if band == light_band: return
	light_band = band
	if band != shared_light_band:
		shared_light_band = band
		var hour = band / 20.0
		shared_shadow_direction = Lighting.cast_direction(hour)
		shared_evening = Lighting.lamplight(hour)
	shadow_direction = shared_shadow_direction
	shadow_opacity = lerpf(.22, .14, shared_evening)
	sprite.modulate = Color.WHITE.lerp(Color("c5c7dd"), shared_evening * .72)
	queue_redraw()

func _sprite_top() -> float:
	return sprite.position.y - 12.0 * sprite_base_scale * display_zoom

func _sprite_bottom() -> float:
	return sprite.position.y + 12.0 * sprite_base_scale * display_zoom

func click_rect() -> Rect2:
	var width = 16.0 * sprite_base_scale * display_zoom
	var top = _sprite_top()
	if not indicator.is_empty():
		top = minf(top, _sprite_top() - 39.0)
		var tag = 38.0 if indicator == "等餐" else label_font.get_string_size(indicator, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12
		width = maxf(width, tag)
	var bottom = _sprite_bottom()
	if not rare_name.is_empty():
		width = maxf(width, label_font.get_string_size(rare_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0)
		bottom = maxf(bottom, _sprite_bottom() + 26.0)
	return Rect2(Vector2(-width * 0.5, top), Vector2(width, bottom - top))

func _draw() -> void:
	var bottom = _sprite_bottom()
	var footprint = maxf(display_zoom, .5)
	var feet = Vector2(0, bottom - footprint)
	var cast = shadow_direction * Vector2(12, 8) * footprint
	draw_set_transform(feet + cast * .65, 0, Vector2(footprint * (1 + absf(shadow_direction.x) * .42), footprint * .33))
	draw_circle(Vector2.ZERO, 13, Color("37435c", shadow_opacity * .50), true, -1, true)
	draw_circle(Vector2.ZERO, 10, Color("37435c", shadow_opacity * .72), true, -1, true)
	draw_set_transform(feet, 0, Vector2(footprint, footprint * .3))
	draw_circle(Vector2.ZERO, 8, Color("393746", .24), true, -1, true)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if has_food:
		draw_rect(Rect2(9, -8, 13, 5), Color("efead6"))
		draw_rect(Rect2(11, -11, 9, 4), Color("edaa56"))
	var chip_top = _sprite_top() - 29.0
	if indicator == "等餐":
		var center = Vector2(0, chip_top + 10)
		draw_circle(center, 16, Color("21373d"), true, -1, true)
		draw_arc(center, 12, -PI / 2, 3 * PI / 2, 32, Color("657660"), 3)
		draw_arc(center, 12, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 32, Color("f0bb63"), 3)
		if patience_ratio >= 0:
			draw_arc(center, 19, -PI / 2, -PI / 2 + TAU * clampf(patience_ratio, 0, 1), 32, Color("ef917b") if patience_ratio < 0.3 else Color("8ec6a0"), 2)
		draw_string(label_font, center + Vector2(-7, 5), "餐", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Style.INK)
	elif not indicator.is_empty():
		var text_width = label_font.get_string_size(indicator, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var chip_width = text_width + 12
		draw_style_box(chip_skin, Rect2(-chip_width * 0.5, chip_top, chip_width, 21))
		draw_string(label_font, Vector2(-text_width * 0.5, chip_top + 16), indicator, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f6e5be"))
		if progress >= 0:
			draw_rect(Rect2(-chip_width * 0.5, chip_top - 4, chip_width * clampf(progress, 0, 1), 3), Color("ebbb62"))
	if not rare_name.is_empty():
		var text_width = label_font.get_string_size(rare_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var tag_width = text_width + 12
		var tag_top = bottom + 5
		var special = visual_key == "thug"
		draw_style_box(special_skin if special else rare_skin, Rect2(-tag_width * 0.5, tag_top, tag_width, 21))
		draw_string(label_font, Vector2(-text_width * 0.5, tag_top + 16), rare_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ef917b") if special else Color("f0bb63"))

static func _rect(image: Image, rectangle: Rect2i, color: Color) -> void:
	image.fill_rect(rectangle, color)

static func _make_frames(kind: String) -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	var clothes = {"chef": "70866c", "waiter": "c47750", "normal": "5d88a1", "commuter": "526887", "student": "6e9a86", "shopkeeper": "9471a4", "market_visitor": "c78262", "blogger": "b07798", "big_eater": "b79056", "freeloader": "768476", "elder": "737e9b", "thug": "825568"}
	var shirt = Color(clothes.get(kind, "5d88a1"))
	var actions = ["idle", "walk", "cook", "order", "carry", "eat"]
	if kind == "waiter": actions.append("wave")
	for action in actions:
		frames.add_animation(action)
		var walking = action in ["walk", "carry"]
		frames.set_animation_speed(action, 12.0 if walking else (6.0 if action != "idle" else 2.5))
		for i in range(8 if walking else 4):
			var img = Image.create(16, 24, false, Image.FORMAT_RGBA8)
			img.fill(Color.TRANSPARENT)
			var stride = roundi(sin(i * TAU / 8.0) * 1.65) if walking else 0
			var bob = int(abs(stride) > 1) if walking else (i % 2)
			var skin = Color("d9a976")
			_rect(img, Rect2i(5, 3 + bob, 7, 7), skin)
			_rect(img, Rect2i(4, 2 + bob, 8, 3), Color("4a3b33"))
			_rect(img, Rect2i(10, 6 + bob, 1, 1), Color("25312a"))
			_rect(img, Rect2i(4, 10 + bob, 9, 9), shirt)
			_rect(img, Rect2i(3, 11 + bob, 2, 6), skin)
			if action == "wave":
				_rect(img, Rect2i(12, 9 + bob, 2, 4), skin)
				_rect(img, Rect2i(13 + i % 2, 6 + bob, 2, 4), skin)
			else:
				_rect(img, Rect2i(12, 11 + bob, 2, 6), skin)
			_rect(img, Rect2i(5, 18 + maxi(0, -stride), 3, 4), Color("344037"))
			_rect(img, Rect2i(10, 18 + maxi(0, stride), 3, 4), Color("344037"))
			if kind == "chef":
				_rect(img, Rect2i(3, 0 + bob, 10, 4), Color("f2eee0"))
				_rect(img, Rect2i(5, 9 + bob, 6, 8), Color("e4e6d3"))
			elif kind == "waiter":
				_rect(img, Rect2i(6, 11 + bob, 5, 8), Color("efe2c0"))
			elif kind == "elder":
				_rect(img, Rect2i(4, 2 + bob, 8, 2), Color("c8cbba"))
			elif kind == "blogger":
				_rect(img, Rect2i(3, 14, 4, 3), Color("323c39"))
			if action == "cook" or action == "eat":
				_rect(img, Rect2i(11, 9 + i % 2, 4, 2), skin)
			frames.add_frame(action, ImageTexture.create_from_image(img))
	return frames
