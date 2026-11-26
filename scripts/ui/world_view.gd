extends Control

const Lanterns = preload("res://scripts/visuals/restaurant_lanterns.gd")
const Lighting = preload("res://scripts/visuals/restaurant_lighting.gd")
const Weather = preload("res://scripts/visuals/restaurant_weather.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Decor = preload("res://scripts/core/decoration_effects.gd")
const DecorArt = preload("res://scripts/visuals/decoration_art.gd")
const GuestChatter = preload("res://scripts/ui/guest_chatter.gd")
const Bubble = preload("res://scripts/ui/speech_bubble.gd")
const Actor = preload("res://scripts/visuals/actor_view.gd")
const CommercialStreet = preload("res://scripts/visuals/commercial_street.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const HOLD_TO_DRAG = .30
const STREET_APPROACH_SECONDS := 4.5
const STREET_HANDOFF_SECONDS := 1.6
signal move_requested(entity_id: String, cell: Vector2i)
signal wall_requested(cells: Array, turns: int)
signal inspect_requested(kind: String, id: String)
signal selection_changed(facility_id: String)
signal drag_started
signal follow_changed(actor_id: String)

var chatter = GuestChatter.new()
var guide_voice
var sim:
	set(value):
		if sim == value: return
		if sim != null:
			sim.guest_moment.disconnect(_guest_moment)
			sim.service_bell.disconnect(_service_bell)
		stop_follow()
		actor_cells.clear()
		floor_style.clear()
		street_arrivals.clear()
		sim = value
		chatter.reset()
		pending_complaints.clear()
		cancel_drag()
		wall_preview.clear()
		reset_scene_time()
		shadow_revision = -1
		accessibility_revision = -1
		trophy_placement_revision = -1
		decor_preview_key.clear()
		preview_positions.clear()
		if sim != null:
			sim.guest_moment.connect(_guest_moment)
			sim.service_bell.connect(_service_bell)
var bottom_inset := 0.0
var editing = false
var placing_wall = false
var wall_preview: Dictionary = {}
var wall_anchor: Variant = null
var wall_brush_rotation = 0
var wall_axis_locked = false
var camera_input_enabled = true
var selected_id = ""
var trophy_placement_id := ""
var trophy_placement_revision := -1
var trophy_cells := {}
var decor_preview_turns := -1
var decor_preview_key := []
var decor_preview := {}
var hovered = Vector2i(-1, -1)
var camera_pan = Vector2.ZERO
var zoom = 1.0
var dragging_camera = false
var press_position = Vector2.ZERO
var pressed_entity = ""
var press_elapsed = 0.0
var drag_active = false
var grab_offset = Vector2i.ZERO
var actors: Dictionary = {}
var actor_cells := {}
var street_arrivals := {}
var sampled_tick := -1
var sampled_fraction := 1.0
var render_motion_paused := false
var follow_actor_id := ""
var follow_seconds := -1.0
var follow_zoom := 1.55
var follow_origin := Vector3.ZERO
var return_camera: Tween
var pending_complaints: Array[int] = []
var accessibility_cache: Dictionary = {}
var walkable_cells: Dictionary = {}
var navigation: Dictionary = {}
var preview_positions: Dictionary = {}
var accessibility_revision = -1
var font: Font
var sun_light: PointLight2D
var shadow_geometry: Node2D
var city_geometry: Node2D
var street = CommercialStreet.new()
var street_canvas := Control.new()
var street_backdrop := ColorRect.new()
var street_activity := Control.new()
var street_signs := Control.new()
var floor_canvas := Control.new()
var weather = Weather.new()
var weather_day := -1
var room_lamp_light := 0.0
var street_lamp_light := 0.0
var street_draw_bounds := Rect2()
var scene_light_band := -1
var floor_style := []
var sign_view := []
const FLOOR_DRAW_UNIT := 28.0
var plot_buttons: Dictionary = {}
var shadow_revision = -1
var shadow_layout_hash
var lamp_positions: Array[Vector2] = []
var lamps: Array[PointLight2D] = []
var glow: Texture2D
var lanterns = Lanterns.new()
var diagnostic_facilities: Array = []
var diagnostic_entrance = false
var greeting_actor := ""
var guide_markers: Array = []
var guide_camera_active := false
var guide_camera_manual := false
var guide_target := Vector2.ZERO
var guide_zoom := 1.0
var prior_pan := Vector2.ZERO
var prior_zoom := 1.0
var rendered_phase := ""
var rendered_hour := 22.0
var transition_from := 22.0
var transition_time := 0.0
var transition_duration := 0.0

func _ready() -> void:
	font = Style.font()
	light_mask = 2
	_add_scenery_layer(street_backdrop, "StreetBackdrop", 4, true)
	_add_scenery_layer(street_canvas, "OutdoorStreet", 4, false)
	street_canvas.draw.connect(_paint_street)
	_add_scenery_layer(weather.ground, "WetStreet", 0, false)
	_add_scenery_layer(street_activity, "StreetActivity", 4, true)
	street_activity.draw.connect(_paint_street_activity)
	_add_scenery_layer(street_signs, "StreetSigns", 4, true)
	street_signs.draw.connect(_paint_street_signs)
	_add_scenery_layer(weather, "StreetWeather", 0, false)
	_add_scenery_layer(floor_canvas, "RestaurantFloor", light_mask, false)
	floor_canvas.draw.connect(_paint_floor)
	shadow_geometry = Node2D.new()
	shadow_geometry.name = "WallAndFurnitureOccluders"
	add_child(shadow_geometry)
	city_geometry = Node2D.new()
	city_geometry.name = "NeighborBuildingOccluders"
	add_child(city_geometry)
	sun_light = PointLight2D.new()
	sun_light.name = "MovingSun"
	glow = Lighting.radial_texture()
	sun_light.texture = glow
	sun_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	sun_light.shadow_filter_smooth = 2.0
	sun_light.shadow_color = Color("171b28", .86)
	sun_light.shadow_enabled = true
	sun_light.range_item_cull_mask = light_mask | street_canvas.light_mask
	sun_light.shadow_item_cull_mask = 2
	sun_light.range_z_min = -4096
	sun_light.range_z_max = 4096
	add_child(sun_light)
	lanterns.board = self
	lanterns.glow = glow
	add_child(lanterns)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(500, 450)
	set_process(true)

func _add_scenery_layer(layer: Control, layer_name: String, mask: int, full_rect: bool) -> void:
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	layer.light_mask = mask
	add_child(layer)
	if full_rect: layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _add_occluder(center: Vector2, half_size: Vector2, container: Node2D = null) -> void:
	var node = LightOccluder2D.new()
	var polygon = OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(-half_size.x,-half_size.y),Vector2(half_size.x,-half_size.y),Vector2(half_size.x,half_size.y),Vector2(-half_size.x,half_size.y)])
	node.occluder = polygon
	node.occluder_light_mask = 2
	node.position = center
	(shadow_geometry if container == null else container).add_child(node)

func _update_lighting() -> void:
	shadow_geometry.position = _origin()
	shadow_geometry.scale = Vector2.ONE * _unit()
	city_geometry.position = _origin()
	city_geometry.scale = Vector2.ONE * _unit()
	if shadow_revision != sim.revision:
		shadow_revision = sim.revision
		var geometry = hash(sim.layout)
		if geometry != shadow_layout_hash:
			shadow_layout_hash = geometry
			_rebuild_room_lighting()
	var hour = _scene_hour()
	var dusk = Lighting.lamplight(hour)
	var travel = 1.0 - smoothstep(0.0, 6.0, hour) if hour < 9.0 else clampf((hour - 9.0) / 12.0, 0.0, 1.0)
	var width = float(sim.layout.width)
	sun_light.position = _origin() + Vector2(lerpf(-5, width + 5, travel), -8) * _unit()
	sun_light.texture_scale = _unit() * (width + 26) * 2.4 / glow.get_width()
	var overcast = weather.cloud_cover
	var flash = weather.flash
	sun_light.color = Lighting.sample(hour, Lighting.KEY).lerp(Color("b9d4ee"), overcast * .54 + flash * .18)
	sun_light.energy = lerpf(.23, .12, dusk) * (1.0 - overcast * .76) + flash * .16
	var tint = _ambient_tint(hour)
	var sky = Color.WHITE.lerp(Color(tint, 1), tint.a)
	var open_air = sky.lerp(Color("839db5"), overcast * .77)
	street_canvas.self_modulate = open_air.lerp(Color("e1ebf9"), flash * .56)
	street_lamp_light = maxf(dusk, overcast * .43)
	room_lamp_light = maxf(dusk, overcast * .80) * weather.lamp_voltage
	self_modulate = sky.lerp(Color("94a8ba"), overcast * .43).lerp(Color("f7e4cc"), room_lamp_light * .66)
	self_modulate = self_modulate.lerp(Color("e1ebf9"), flash * .14)
	_sync_scenery(dusk)
	for i in range(lamps.size()):
		var lamp = lamps[i]
		lamp.enabled = room_lamp_light > .015
		lamp.position = screen_point(lamp_positions[i])
		lamp.texture_scale = _unit() * (7.5 if i == 0 else 9.5) / glow.get_width()
		lamp.energy = room_lamp_light * (.46 if i == 0 else .26)

func _sync_scenery(dusk: float) -> void:
	var origin = _origin()
	var unit = _unit()
	street_canvas.position = origin + street_draw_bounds.position * unit
	street_canvas.scale = Vector2.ONE * unit
	street_backdrop.self_modulate = street_canvas.self_modulate
	street_backdrop.color = Color("aebdb3").lerp(Color("586d7a"), dusk).lerp(Color("748997"), weather.cloud_cover * .58).lerp(Color("aebed8"), weather.flash * .52)
	street_activity.self_modulate = street_canvas.self_modulate
	street_signs.self_modulate = street_canvas.self_modulate
	floor_canvas.position = origin
	floor_canvas.scale = Vector2.ONE * (unit / FLOOR_DRAW_UNIT)
	floor_canvas.self_modulate = self_modulate
	var band = roundi(street_lamp_light * 8.0)
	if band != scene_light_band:
		scene_light_band = band
		street_canvas.queue_redraw()
	var floor_state = [sim.revision, sim.phase, editing or placing_wall, scene_light_band]
	if floor_state != floor_style:
		floor_style = floor_state
		floor_canvas.queue_redraw()
	var view = [origin, unit, size]
	if view != sign_view:
		sign_view = view
		street_signs.queue_redraw()

func _rebuild_room_lighting() -> void:
	var l = sim.layout
	var walls = {}
	for wall in Grid.facilities(l, "wall"): walls[Vector2i(Grid.vec(wall.pos))] = true
	for child in shadow_geometry.get_children():
		shadow_geometry.remove_child(child)
		child.queue_free()
	# A continuous wall casts one shadow, including at joins between neighboring tiles.
	for y in range(int(l.height)):
		var first = -1
		for x in range(int(l.width) + 1):
			var cell = Vector2i(x, y)
			var solid = x < int(l.width) and (walls.has(cell) or (Grid.structural_blocked(l, cell) and Grid.locked_plot_at(l, cell).is_empty()))
			if solid and first < 0: first = x
			if not solid and first >= 0:
				var length = float(x - first)
				_add_occluder(Vector2(first + length * .5, y + .5), Vector2(length * .5, .40))
				first = -1
	for f in l.facilities:
		if Grid.placed(f) and f.type != "wall":
			if f.type == "decoration" or (f.type == "table" and Grid.table_size(f) > 1):
				var area = Grid.footprint(f)
				_add_occluder(Vector2(area.position) + Vector2(area.size) * .5, Vector2(area.size) * .39)
				continue
			var half = Vector2(.34, .19) if f.type == "table" else Vector2(.31, .26)
			var turns = Grid.rotation(f)
			if turns % 2 == 1: half = Vector2(half.y, half.x)
			var offset = Vector2(0, .04).rotated(turns * PI / 2.0)
			_add_occluder(Grid.vec(f.pos) + Vector2(.5, .5) + offset, half)
	_place_ceiling_lights(l, walls)

func _place_ceiling_lights(l: Dictionary, walls: Dictionary) -> void:
	lamp_positions.assign([Grid.vec(l.entrance) + Vector2(.28, -.4)])
	var inner_size = Vector2(l.width - 2, l.height - 2)
	var columns = maxi(1, ceili(inner_size.x / 7.0))
	var rows = maxi(1, ceili(inner_size.y / 6.0))
	var spacing = inner_size / Vector2(columns, rows)
	for row in range(rows):
		for column in range(columns):
			var cell = Vector2i(Vector2.ONE + (Vector2(column, row) + Vector2(.5, .5)) * spacing)
			if Grid.structural_blocked(l, cell) or walls.has(cell): continue
			lamp_positions.append(Vector2(cell) + Vector2(0, -.41))

	while lamps.size() < lamp_positions.size():
		var lamp := PointLight2D.new()
		lamp.texture = glow
		lamp.range_item_cull_mask = light_mask
		lamp.shadow_item_cull_mask = light_mask
		lamp.shadow_color = Color("40343b", .55)
		lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		lamp.shadow_filter_smooth = 2.6
		add_child(lamp)
		lamps.append(lamp)
	while lamps.size() > lamp_positions.size():
		var unused: PointLight2D = lamps.pop_back()
		remove_child(unused)
		unused.queue_free()
	var kitchen = Grid.kitchen_bounds(l)
	var stove = Grid.facilities(l, "stove")
	var tables = Grid.facilities(l, "table")
	var shadow_lamps = [0]
	for fixtures in [stove, tables]:
		if fixtures.is_empty(): continue
		var target = Grid.vec(fixtures[0].pos)
		var nearest = 0
		for i in range(1, lamp_positions.size()):
			if lamp_positions[i].distance_squared_to(target) < lamp_positions[nearest].distance_squared_to(target):
				nearest = i
		shadow_lamps.append(nearest)
	for i in range(lamps.size()):
		var p = lamp_positions[i]
		var in_kitchen = p.x >= kitchen.left and p.x <= kitchen.right and p.y <= kitchen.bottom
		lamps[i].color = Color("fff1d5") if in_kitchen else Color("ffd39b")
		lamps[i].shadow_enabled = i in shadow_lamps

func _sync_neighbor_occluders() -> void:
	var dimensions = Vector2i(int(sim.layout.width), int(sim.layout.height))
	var gate = float(sim.layout.entrance[1])
	if street.dimensions == dimensions and is_equal_approx(street.entrance_y, gate): return
	street.configure(dimensions, gate)
	# Give the cached Controls concrete bounds, including the streets west and north of the restaurant.
	street_draw_bounds = street.bounds.grow(2.0)
	street_canvas.size = street_draw_bounds.size
	floor_canvas.size = Vector2(dimensions) * FLOOR_DRAW_UNIT
	street_canvas.queue_redraw()
	street_signs.queue_redraw()
	for node in city_geometry.get_children():
		city_geometry.remove_child(node)
		node.queue_free()
	for building in street.storefronts:
		_add_occluder(building.get_center(), building.size * 0.47, city_geometry)

func _advance_weather(delta: float) -> void:
	_sync_neighbor_occluders()
	weather.configure(street, int(sim.seed_value))
	if weather_day != int(sim.day):
		weather_day = int(sim.day)
		weather.set_preset(sim.weather_for().preset)
	weather.advance(delta, sim.phase == "DAY" and sim.paused)
	weather.align_to_world(_origin(), _unit(), size, Lighting.lamplight(_scene_hour()))

func reset_scene_time() -> void:
	weather_day = -1
	weather.reset()
	street_arrivals.clear()
	sampled_tick = -1
	rendered_phase = ""
	transition_time = 0.0
	transition_duration = 0.0

func _clock_hour() -> float:
	if sim.phase == "NIGHT": return 22.0
	if sim.phase == "REPORT": return 24.0
	return minf(24.0,9.0+float(sim.tick)*12.0/float(sim.day_ticks))

func _scene_hour() -> float:
	return rendered_hour if transition_time < transition_duration else _clock_hour()

func _advance_scene_time(delta: float) -> void:
	var target = _clock_hour()
	if rendered_phase != sim.phase:
		if not rendered_phase.is_empty():
			transition_from = rendered_hour
			transition_time = 0.0
			transition_duration = .92 if sim.phase == "DAY" else .64
		rendered_phase = sim.phase
	transition_time = minf(transition_time + delta, transition_duration)
	if transition_time == transition_duration:
		rendered_hour = target
	else:
		var blend = smoothstep(0.0, transition_duration, transition_time)
		# Opening advances through midnight and dawn, keeping the street and room on the same visual clock.
		if sim.phase == "DAY" and transition_from > target:
			rendered_hour = fposmod(lerpf(transition_from, target + 24.0, blend), 24.0)
		else:
			rendered_hour = lerpf(transition_from, target, blend)

func _ambient_tint(hour: float) -> Color:
	return Lighting.sample(hour, Lighting.WASH)

func camera_extent() -> Vector2:
	return Vector2(size.x, maxf(1.0, size.y - bottom_inset))

func _unit() -> float:
	var columns = float(sim.layout.width) + 12.0 if sim != null else 24.0
	var rows = float(sim.layout.height) + 8.6 if sim != null else 18.6
	return clampf(minf(size.x / columns, camera_extent().y / rows), 1.0, 130.0) * zoom

func _origin() -> Vector2:
	var unit = _unit()
	var columns = float(sim.layout.width) if sim != null else 12.0
	var rows = float(sim.layout.height) if sim != null else 10.0
	return (camera_extent() - Vector2(columns, rows) * unit) * 0.5 + Vector2(2.9, 0.45) * unit + camera_pan

func screen_point(cell: Vector2) -> Vector2:
	return _origin() + (cell + Vector2(0.5, 0.5)) * _unit()

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - _origin()) / _unit()).floor())

func _service_bell(midnight: bool) -> void:
	chatter.bell(sim, midnight)

func _guest_moment(id: int, moment: StringName) -> void:
	if moment == &"no_table": pending_complaints.append(id)
	else: chatter.enqueue(sim, id, moment)

## Speak from any visible actor, e.g. say("g_12", "客人", "我的菜快好了吗？").
func say(actor_id: String, speaker: String, message: String, seconds := 4.0, dock := false, accent := Color.TRANSPARENT):
	var bubble = Bubble.new()
	add_child(bubble)
	if accent.a > 0:
		bubble.set_remark(speaker, message, accent)
	else:
		bubble.set_line(speaker, message)
	if dock: guide_voice = bubble
	bubble.follow(_speech_anchor.bind(actor_id), seconds, dock)
	return bubble

func _speech_anchor(actor_id: String):
	var actor = actors.get(actor_id)
	if not is_instance_valid(actor) or actor.is_queued_for_deletion(): return null
	return actor.position + Vector2(0, actor.click_rect().position.y - 4)

func guide_shot(cell: Vector2, magnification: float, markers: Array = []) -> void:
	guide_markers = markers
	if guide_camera_manual: return
	if not guide_camera_active:
		prior_pan = camera_pan
		prior_zoom = zoom
	guide_camera_active = true
	guide_target = cell
	guide_zoom = magnification

func end_guide_shot(restore := true) -> void:
	if guide_camera_active and restore:
		camera_pan = prior_pan
		zoom = prior_zoom
	guide_camera_active = false
	guide_markers = []

func follow_actor(actor_id: String, seconds := -1.0) -> bool:
	if not camera_input_enabled or _follow_target(actor_id) == null: return false
	var origin = follow_origin if not follow_actor_id.is_empty() and follow_seconds >= 0.0 else Vector3(camera_pan.x, camera_pan.y, zoom)
	_manual_camera()
	follow_actor_id = actor_id
	follow_seconds = seconds
	follow_origin = origin
	follow_zoom = 1.52 if seconds >= 0.0 else 1.68
	follow_changed.emit(follow_actor_id)
	return true

func stop_follow(restore := false) -> void:
	var was_following = not follow_actor_id.is_empty()
	if is_instance_valid(return_camera) and return_camera.is_valid(): return_camera.kill()
	follow_actor_id = ""
	follow_seconds = -1.0
	if not was_following: return
	if restore:
		return_camera = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return_camera.tween_property(self, "zoom", follow_origin.z, .42)
		return_camera.tween_property(self, "camera_pan", Vector2(follow_origin.x, follow_origin.y), .42)
	follow_changed.emit("")

func _follow_target(actor_id: String) -> Variant:
	if sim == null: return null
	if actor_id.begins_with("s_"):
		if sim.phase != "DAY": return null
		var employee = sim.staff_member(int(actor_id.substr(2)))
		return _sample_position(employee, _render_fraction()) if not employee.is_empty() else null
	if actor_id.begins_with("g_"):
		var customer = sim.active_customers.get(int(actor_id.substr(2)), {})
		return actor_cells.get(actor_id, customer.pos) if not customer.is_empty() else null
	if actor_id.begins_with("preview_") and sim.phase == "NIGHT": return actor_cells.get(actor_id)
	return null

func _advance_follow(delta: float) -> void:
	if follow_actor_id.is_empty(): return
	var cell = _follow_target(follow_actor_id)
	if not camera_input_enabled or cell == null:
		stop_follow(camera_input_enabled and follow_seconds >= 0.0)
		return
	if follow_seconds >= 0.0:
		follow_seconds -= delta
		if follow_seconds <= 0.0:
			stop_follow(true)
			return
	var blend = 1.0 - exp(-6.0 * delta)
	zoom = lerpf(zoom, follow_zoom, blend)
	camera_pan += (camera_extent() * Vector2(.46, .55) - screen_point(cell)) * blend

func _manual_camera() -> void:
	stop_follow()
	if guide_camera_active:
		guide_camera_manual = true
		end_guide_shot(false)

func focus_restaurant() -> void:
	_manual_camera()
	zoom = 1.0
	camera_pan = Vector2.ZERO

func focus_district() -> void:
	if sim == null: return
	_manual_camera()
	_sync_neighbor_occluders()
	zoom = 1.0
	var available = camera_extent() - Vector2(62, 146)
	var required = street.bounds.size * _unit()
	zoom = maxf(.44, minf(available.x / required.x, available.y / required.y))
	camera_pan = Vector2.ZERO
	var center = _origin() + street.bounds.get_center() * _unit()
	camera_pan = camera_extent() * .5 - center

func set_diagnostic_targets(facilities: Array, entrance: bool, center := false) -> void:
	diagnostic_facilities = facilities
	diagnostic_entrance = entrance
	if center:
		focus_restaurant()
		var cells = _diagnostic_cells()
		if not cells.is_empty():
			var bounds = Rect2(cells[0], Vector2.ZERO)
			for cell in cells: bounds = bounds.expand(cell)
			camera_pan = size * 0.5 - screen_point(bounds.get_center())
	queue_redraw()

func _diagnostic_cells() -> Array[Vector2]:
	var cells: Array[Vector2] = []
	if diagnostic_entrance: cells.append(Grid.vec(sim.layout.entrance))
	for id in diagnostic_facilities:
		var facility = Grid.find(sim.layout, id)
		if not facility.is_empty() and Grid.placed(facility):
			cells.append(Grid.vec(facility.pos))
	return cells

func _make_plot_button(id: String) -> Dictionary:
	var button = Style.button("")
	button.mouse_filter = MOUSE_FILTER_PASS
	button.size = Vector2(72, 40)
	button.pressed.connect(func(): inspect_requested.emit("plot", id))
	add_child(button)
	var center = CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var contents = HBoxContainer.new()
	contents.mouse_filter = MOUSE_FILTER_IGNORE
	contents.add_theme_constant_override("separation", 2)
	center.add_child(contents)
	var glyph = Icon.make("lock", Style.MUTED, 22.0)
	contents.add_child(glyph)
	var star = Icon.make("star", Style.GOLD, 15.0)
	contents.add_child(star)
	var cost = Style.text("", 16, Style.INK)
	cost.mouse_filter = MOUSE_FILTER_IGNORE
	contents.add_child(cost)
	return {"button": button, "glyph": glyph, "star": star, "cost": cost, "ready": -1}

func _sync_plot_buttons() -> void:
	var next_plot = str(sim.next_land_plot().get("id", ""))
	for plot in sim.layout.plots:
		var id = str(plot.id)
		if not plot_buttons.has(id): plot_buttons[id] = _make_plot_button(id)
		var marker = plot_buttons[id]
		var button: Button = marker.button
		var bounds = plot.bounds
		var center = Vector2((float(bounds.left) + float(bounds.right)) * 0.5, (float(bounds.top) + float(bounds.bottom)) * 0.5)
		button.position = screen_point(center) - button.size * 0.5
		button.visible = id not in sim.layout.unlocked_plots and Rect2(Vector2.ZERO, size).intersects(button.get_rect())
		var current = id == next_plot and sim.phase == "NIGHT"
		var interactive = current and not editing and not placing_wall and pressed_entity.is_empty() and camera_input_enabled
		button.disabled = not interactive
		button.mouse_filter = MOUSE_FILTER_PASS if interactive else MOUSE_FILTER_IGNORE
		if not button.visible: continue
		var status = sim.land_plot_status(id) if current else {}
		var ready = bool(status.get("ok", false))
		marker.cost.text = str(int(plot.star_cost))
		button.tooltip_text = "%s · %d 闪星" % [plot.name, int(plot.star_cost)] if interactive else ""
		if interactive and not ready:
			button.tooltip_text += "\n" + str(status.error)
		var state = 2 if ready else (1 if current else 0)
		if marker.ready == state: continue
		marker.ready = state
		var shade = [Color("32383c"), Color("263837"), Color("e4ba72")][state]
		var trim = [Color("777c7d"), Color("d7b87c"), Color("f5d693")][state]
		var ink = [Color("b6b9b7"), Color("f2dfae"), Color("362d23")][state]
		button.add_theme_stylebox_override("normal", Style.box(shade, trim, 8, 6))
		button.add_theme_stylebox_override("hover", Style.box(shade.lightened(0.15), trim, 8, 6))
		button.add_theme_stylebox_override("pressed", Style.box(shade.darkened(0.12), trim, 8, 6))
		button.add_theme_stylebox_override("disabled", Style.box(shade, trim, 8, 6))
		marker.glyph.set_glyph("expand" if ready else "lock", ink)
		marker.star.set_glyph("star", Style.GOLD if state == 1 else ink)
		marker.cost.add_theme_color_override("font_color", ink)

func _process(delta: float) -> void:
	if sim == null:
		return
	if wall_anchor != null and (sim.phase != "NIGHT" or not camera_input_enabled): wall_anchor = null
	if not pressed_entity.is_empty():
		if sim.phase != "NIGHT" or not camera_input_enabled:
			cancel_drag()
		elif not drag_active and pressed_entity not in ["trophy_shop", "slot", "decor_shop"]:
			press_elapsed += delta
			if press_elapsed >= HOLD_TO_DRAG:
				drag_active = true
				selected_id = pressed_entity
				mouse_default_cursor_shape = Control.CURSOR_DRAG
				drag_started.emit()
	if camera_input_enabled and (get_viewport().gui_get_focus_owner() == null or not get_viewport().gui_get_focus_owner() is LineEdit):
		var movement = Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): movement.x += 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): movement.x -= 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): movement.y += 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): movement.y -= 1
		if movement != Vector2.ZERO:
			_manual_camera()
			camera_pan += movement * delta * 250.0
	_advance_follow(delta)
	if guide_camera_active and camera_input_enabled and follow_actor_id.is_empty():
		var blend = 1.0 - exp(-7.0 * delta)
		zoom = lerpf(zoom, guide_zoom, blend)
		camera_pan += (camera_extent() * Vector2(0.5, 0.57) - screen_point(guide_target)) * blend
	if accessibility_revision != sim.revision:
		accessibility_cache.clear()
		if sim.phase == "NIGHT":
			navigation = Grid.solid_cells(sim.layout)
			walkable_cells = Grid.walkable_region(sim.layout, navigation)
			preview_positions = Grid.staff_positions(sim.layout, sim.attributes, walkable_cells)
			for f in sim.layout.facilities:
				if Grid.placed(f): accessibility_cache[f.id] = not Grid.interaction_accessible(f, walkable_cells)
		accessibility_revision = sim.revision
	_advance_scene_time(delta)
	_advance_weather(delta)
	_sync_trophy_placement()
	_update_lighting()
	lanterns.queue_redraw()
	street.advance(delta, sim.paused)
	street_activity.queue_redraw()
	_sync_plot_buttons()
	_sync_actors()
	for id in pending_complaints:
		var c = sim.active_customers.get(id, {})
		var actor_id = "g_%d" % id
		if c.is_empty() or not actors.has(actor_id): continue
		var size = int(c.party_size)
		say(actor_id, "%d 人组" % size, "没有%s？我们换一家吧。" % Grid.table_label(size), 2.1, false, Color("b46c56"))
	pending_complaints.clear()
	chatter.advance(self, delta, not camera_input_enabled or (is_instance_valid(guide_voice) and not guide_voice.is_queued_for_deletion()))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseMotion:
		hovered = cell_at(event.position)
		if dragging_camera:
			if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_manual_camera()
				camera_pan += event.relative
			else:
				dragging_camera = false
		_update_cursor(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging_camera = event.pressed
			_update_cursor(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_manual_camera()
			zoom = clampf(zoom * 1.1, 0.44, 1.8)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_manual_camera()
			zoom = clampf(zoom / 1.1, 0.44, 1.8)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var cell = cell_at(event.position)
			hovered = cell
			if sim.phase == "NIGHT" and placing_wall:
				if event.pressed:
					cancel_drag()
					if camera_input_enabled: wall_anchor = cell
				elif wall_anchor != null:
					var stroke = _wall_row_to(cell)
					wall_anchor = null
					wall_brush_rotation = int(stroke.turns)
					if camera_input_enabled: wall_requested.emit(stroke.cells, wall_brush_rotation)
				return
			if event.pressed:
				cancel_drag()
				if not camera_input_enabled: return
				if sim.phase == "NIGHT" and editing and not selected_id.is_empty():
					move_requested.emit(selected_id, cell)
					return
				press_position = event.position
				var facility = Grid.facility_at(sim.layout, cell)
				var actor_id = _actor_at(event.position)
				var id = actor_id
				if not facility.is_empty() and (actor_id.is_empty() or sim.phase == "NIGHT"):
					id = str(facility.id)
				if _trophy_shop_hit(event.position): id = "trophy_shop"
				if sim.phase == "NIGHT":
					pressed_entity = id
					if not facility.is_empty(): grab_offset = cell - Grid.footprint(facility).position
				else:
					_inspect_entity(id)
			elif not pressed_entity.is_empty():
				var id = pressed_entity
				var moved = event.position.distance_to(press_position) > 7
				var drop = _drop_cell(id, cell)
				var was_dragging = drag_active
				cancel_drag()
				if not camera_input_enabled or sim.phase != "NIGHT": return
				if was_dragging and moved: move_requested.emit(id, drop)
				elif not moved: _inspect_entity(id)
				_update_cursor(event.position)

func cancel_drag() -> void:
	wall_anchor = null
	pressed_entity = ""
	press_elapsed = 0.0
	drag_active = false
	grab_offset = Vector2i.ZERO

func cancel_placement() -> void:
	decor_preview_turns = -1
	editing = false
	placing_wall = false
	wall_brush_rotation = 0
	wall_axis_locked = false
	selected_id = ""
	cancel_drag()
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func rotate_wall_brush() -> void:
	wall_brush_rotation = (int(_wall_row_to(hovered).turns) + 1) % 2
	wall_axis_locked = true

func _wall_row_to(end: Vector2i) -> Dictionary:
	var start = end if wall_anchor == null else Vector2i(wall_anchor)
	var delta = end - start
	var turns = wall_brush_rotation
	if not wall_axis_locked and delta != Vector2i.ZERO:
		turns = 1 if absi(delta.y) > absi(delta.x) else 0
	return {"turns":turns, "cells":Grid.wall_line(start, end, turns)}

func _drop_cell(id: String, cell: Vector2i) -> Vector2i:
	if not id.begins_with("preview_"):
		var hovered_facility = Grid.facility_at(sim.layout, cell)
		var source = Grid.find(sim.layout, id)
		if source.get("type") == "table" and hovered_facility.get("type") == "table" and hovered_facility.id != id:
			return cell
	return cell - grab_offset

func _actor_at(point: Vector2) -> String:
	var selected = ""
	var best_distance = INF
	for id in actors:
		var actor = actors[id]
		if actor.modulate.a < .15: continue
		if str(id).begins_with("g_") and not sim.active_customers.has(int(str(id).substr(2))): continue
		var local_bounds = actor.click_rect()
		var box = Rect2(actor.position + local_bounds.position, local_bounds.size)
		if box.has_point(point):
			var distance = actor.position.distance_squared_to(point)
			if distance < best_distance:
				selected = id
				best_distance = distance
	return selected

func _trophy_shop_at(cell: Vector2i) -> bool:
	return sim.phase == "NIGHT" and sim.trophy_shop_unlocked() and cell == sim.trophy_shop_cell()

func _trophy_shop_hit(point: Vector2) -> bool:
	if sim.phase != "NIGHT" or not sim.trophy_shop_unlocked(): return false
	var cell = sim.trophy_shop_cell()
	if cell_at(point) == cell: return true
	return _trophy_shop_sign(cell, _unit()).has_point(point)

func _trophy_shop_sign(cell: Vector2i, unit: float) -> Rect2:
	var font_size = clampi(roundi(unit * .43), 12, 16)
	var width = font.get_string_size("奖杯商店", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var start = screen_point(Vector2(cell)) - Vector2(width * .5 + 4, unit * .68 + font_size)
	return Rect2(start, Vector2(width + 8, font_size + 5))

func _update_cursor(point: Vector2) -> void:
	if dragging_camera:
		mouse_default_cursor_shape = Control.CURSOR_MOVE
		return
	if drag_active:
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		return
	if sim.phase == "NIGHT" and placing_wall:
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		return
	if sim.phase == "NIGHT" and editing and not selected_id.is_empty():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		return
	if _trophy_shop_hit(point) or not Grid.facility_at(sim.layout, cell_at(point)).is_empty():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		return
	if not _actor_at(point).is_empty():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		return
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _inspect_actor(point: Vector2) -> String:
	var nearest = _actor_at(point)
	_inspect_entity(nearest)
	return nearest

func _inspect_entity(id: String) -> void:
	if id.is_empty(): return
	if id == "trophy_shop":
		inspect_requested.emit("trophy_shop", id)
	elif id.begins_with("preview_"):
		selected_id = id
		inspect_requested.emit("preview", id)
	elif id.begins_with("s_"):
		inspect_requested.emit("staff", id.substr(2))
	elif id.begins_with("g_"):
		inspect_requested.emit("customer", id.substr(2))
	else:
		selected_id = id
		selection_changed.emit(id)
		inspect_requested.emit("facility", id)

func _actor(id: String, kind: String):
	if not actors.has(id):
		var actor = Actor.new()
		add_child(actor)
		actors[id] = actor
	actors[id].set_visual(kind)
	return actors[id]

func set_render_clock(tick: int, fraction: float, clock_held: bool) -> void:
	sampled_tick = tick
	sampled_fraction = fraction
	render_motion_paused = clock_held

func _render_fraction() -> float:
	return sampled_fraction if sampled_tick == sim.tick and sim.phase == "DAY" else 1.0

func _sample_position(entity: Dictionary, fraction: float) -> Vector2:
	if int(entity.get("position_tick", -1)) != sim.tick: return entity.pos
	return Vector2(entity.previous_pos).lerp(entity.pos, fraction)

func _street_approach_progress(arrival_tick: int, visual_tick: float) -> float:
	var lead = ceili(STREET_APPROACH_SECONDS * 1000.0 / sim.tick_ms)
	var handoff = ceili(STREET_HANDOFF_SECONDS * 1000.0 / sim.tick_ms)
	var start = maxi(0, arrival_tick - lead)
	return clampf((visual_tick - start) / maxi(1, arrival_tick + handoff - start), 0, 1)

func _place_actor(id: String, actor, cell: Vector2, origin: Vector2, unit: float) -> void:
	actor_cells[id] = cell
	actor.place_in_world(cell, origin + (cell + Vector2(.5, .5)) * unit, unit / 48.0)

func _set_street_actor(id: String, kind: String, cell: Vector2, origin: Vector2, unit: float) -> void:
	var actor = _actor(id, kind)
	_place_actor(id, actor, cell, origin, unit)
	actor.modulate.a = street.threshold_alpha(cell)
	actor.patience_ratio = -1.0
	actor.present("walk", "", -1.0, false, sim.guest_defs[kind].name if sim.guest_defs[kind].rarity == "special" else "")

func _sync_approaching_street(live: Dictionary, origin: Vector2, unit: float, visual_tick: float) -> void:
	if sim.phase == "DAY":
		var lead_ticks = ceili(STREET_APPROACH_SECONDS * 1000.0 / sim.tick_ms)
		for index in range(sim.arrival_cursor, sim.arrival_plan.size()):
			var plan = sim.arrival_plan[index]
			var arrival_tick = int(plan.tick)
			if arrival_tick > sim.tick + lead_ticks: break
			var id = int(plan.id)
			if sim.customers.has(id): continue
			var place = Grid.vec(sim.layout.entrance)
			var member = id - int(plan.get("party_id", id))
			place.y += .20 + .21 * (member % 2)
			street_arrivals[id] = {"tick": arrival_tick, "type": plan.type, "target": place}
	for id in street_arrivals.keys():
		var visit = street_arrivals[id]
		if sim.customers.has(id):
			street_arrivals.erase(id)
			continue
		var age = (visual_tick - int(visit.tick)) * sim.tick_ms / 1000.0
		if sim.phase != "DAY" or age >= STREET_APPROACH_SECONDS:
			street_arrivals.erase(id)
			continue
		var cell = street.gate_route(_street_approach_progress(int(visit.tick), visual_tick), visit.target)
		if age >= 0.0:
			var first = maxi(0, int(visit.tick) - ceili(STREET_APPROACH_SECONDS * 1000.0 / sim.tick_ms))
			var span = float(visit.tick - first) * sim.tick_ms / 1000.0
			var approach = span / (span + STREET_HANDOFF_SECONDS)
			var turned_at = street.gate_route(approach, visit.target)
			cell = street.exit_route(age / STREET_APPROACH_SECONDS, turned_at)
		var key = "g_%d" % id
		live[key] = true
		_set_street_actor(key, visit.type, cell, origin, unit)

var current_sprite: Sprite2D
const CURRENT_TEXTURE = preload("res://assets/canyon/current.webp")

func _sync_current(unit: float) -> void:
	if current_sprite == null:
		current_sprite = Sprite2D.new()
		current_sprite.texture = CURRENT_TEXTURE
		current_sprite.hframes = 4
		current_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		current_sprite.z_index = 1
		add_child(current_sprite)
	current_sprite.visible = sim.phase == "DAY" and sim.tick < sim.current_until
	if current_sprite.visible:
		current_sprite.position = screen_point(sim.current_cell)
		current_sprite.scale = Vector2.ONE * unit * 1.7 / 128.0
		current_sprite.frame = floori(sim.tick * sim.tick_ms / 135.0) % 4

func _sync_actors() -> void:
	var live = {}
	actor_cells.clear()
	var unit = _unit()
	var origin = _origin()
	_sync_current(unit)
	var fraction = _render_fraction()
	var visual_tick = maxf(0.0, sim.tick - 1.0 + fraction)
	if sim.phase == "NIGHT":
		street_arrivals.clear()
		var positions = Grid.staff_positions(sim.layout, sim.attributes) if preview_positions.is_empty() else preview_positions
		for role in positions:
			for i in range(positions[role].size()):
				var id = "preview_%s_%d" % [role, i]
				live[id] = true
				var actor = _actor(id, role)
				var cell = hovered if drag_active and id == pressed_entity else positions[role][i]
				_place_actor(id, actor, Vector2(cell), origin, unit)
				actor.present("wave" if id == greeting_actor else "idle", "阿禾" if id == greeting_actor else ("厨" if role == "chef" else "服"))
	else:
		for s in sim.staff:
			var id = "s_%d" % s.id
			live[id] = true
			var actor = _actor(id, s.role)
			_place_actor(id, actor, _sample_position(s, fraction), origin, unit)
			var action = "idle"
			var label = "厨" if s.role == "chef" else "服"
			var progress = -1.0
			if s.task.is_empty() and not s.path.is_empty() and sim.phase == "DAY":
				action = "walk"
			elif not s.task.is_empty():
				if s.task.stage == "MOVE":
					action = "carry" if not s.carry_food.is_empty() or s.carry_order != 0 else "walk"
				else:
					action = "cook" if s.task.kind == "COOK" else "order"
					label = "做" if s.task.kind == "COOK" else "单"
					progress = float(sim.tick - int(s.task.started_tick)) / maxi(1, int(s.task.done_tick) - int(s.task.started_tick))
			actor.show_flare(s.task.get("flare", false), sim.tick, sim.tick_ms)
			actor.present(action, label, progress, not s.carry_food.is_empty())
		_sync_approaching_street(live, origin, unit, visual_tick)
		var queue_index = 0
		var party_places = {}
		for c in sim.active_customers.values():
			if c.state == "GONE": continue
			var party = int(c.get("party_id", 0))
			if c.state == "QUEUE" and queue_index >= 56 and not party_places.has(party) and sim.guest_defs[c.type].rarity != "special": continue
			var id = "g_%d" % c.id
			live[id] = true
			var actor = _actor(id, c.type)
			var displayed = _sample_position(c, fraction)
			var phase = str(c.state)
			if phase == "QUEUE":
				displayed = sim.queue_spot(c, queue_index, party_places)
				queue_index += 1
			elif phase == "EXITING" and not c.path.is_empty():
				var departure = Vector2(c.path[0]) + Vector2(4.5, 0)
				displayed = street.exit_route((departure.x - displayed.x) / 4.5, departure)
			elif phase == "AT_EXIT":
				displayed += sim.party_offset(c)
			elif phase == "SEATING":
				displayed += sim.party_offset(c) * clampf(1.0 - c.pos.distance_to(Grid.vec(sim.layout.entrance)) / 2.5, 0.0, 1.0)
			var entering = phase in ["QUEUE", "SEATING", "CHOOSING", "APPROACHING"]
			var approach = _street_approach_progress(int(c.arrival_tick), visual_tick) if entering else 1.0
			if approach < 1.0:
				displayed = street.gate_route(approach, displayed)
			_place_actor(id, actor, displayed, origin, unit)
			actor.modulate.a = street.threshold_alpha(displayed)
			var action = "idle"
			var label = ""
			var progress = -1.0
			if approach < 1.0 or c.state in ["SEATING", "LEAVING", "EXITING", "APPROACHING"]: action = "walk"
			elif c.state in ["READY", "TAKING"]:
				action = "order"
				label = "点单"
			elif c.state == "CHOOSING":
				label = "选菜"
			elif c.state == "FOOD":
				label = "等餐"
				var cycle = maxf(1, sim._guest_seconds(c, "cycle") * 1000.0 / sim.tick_ms)
				progress = fmod(float(sim.tick - int(c.food_start)), cycle) / cycle
			elif c.state == "EATING":
				action = "eat"
				label = "用餐"
				progress = 1.0 - float(int(c.deadline) - sim.tick) / maxf(1, sim._guest_seconds(c, "eat") * 1000.0 / sim.tick_ms)
			elif c.state == "STAYING": label = "等同桌"
			actor.patience_ratio = float(int(c.food_max)-sim.tick) / maxf(1,sim._guest_seconds(c,"food_max")*1000/sim.tick_ms) if c.state=="FOOD" and not sim.guest_defs[c.type].get("unlimited_food_wait", false) else -1.0
			actor.present(action, label, progress, false, sim.guest_defs[c.type].name if sim.guest_defs[c.type].rarity != "normal" else "")
	var minute = _scene_hour() * 60.0
	var frozen = sim.phase == "DAY" and (sim.paused or (sampled_tick == sim.tick and render_motion_paused))
	for id in actors.keys():
		var actor = actors[id]
		if not live.has(id):
			actor.queue_free()
			actors.erase(id)
			continue
		actor.set_sunlight(minute)
		actor.sprite.speed_scale = 0.0 if frozen else 1.0

func _paint_street() -> void:
	street_canvas.draw_set_transform(-street_draw_bounds.position)
	street.paint_scenery(street_canvas, maxf(0.0, scene_light_band / 8.0))

func _paint_street_activity() -> void:
	if sim == null: return
	street.paint_activity(street_activity, _origin(), _unit(), street_lamp_light)

func _paint_street_signs() -> void:
	if sim != null and font != null:
		street.paint_signs(street_signs, _origin(), _unit(), font)

func _paint_floor() -> void:
	if sim == null: return
	var unit = FLOOR_DRAW_UNIT
	var origin = Vector2.ZERO
	var l = sim.layout
	var kitchen = Grid.kitchen_bounds(l)
	var next_plot = str(sim.next_land_plot().get("id", "")) if sim.phase == "NIGHT" else ""
	var blueprint_tint = street_canvas.self_modulate / self_modulate
	for y in range(int(l.height)):
		for x in range(int(l.width)):
			var rect = Rect2(origin + Vector2(x, y) * unit, Vector2.ONE * unit)
			var base_color = Color("e1bf94").lerp(Color("efd5ac"), float((x * 5 + y * 3) % 7) / 7.0)
			if x >= int(kitchen.left) and x <= int(kitchen.right) and y >= int(kitchen.top) and y <= int(kitchen.bottom):
				base_color = Color("bcd7c9") if (x+y)%2==0 else Color("c4dfd2")
			elif x > int(kitchen.right) and y >= 1 and y <= int(kitchen.bottom):
				base_color = Color("cadabb") if (x+y)%2==0 else Color("bfd2b8")
			var locked = Grid.locked_plot_at(l,Vector2i(x,y))
			var wall = Grid.structural_blocked(l,Vector2i(x,y))
			var inner_wall = wall and locked.is_empty() and x>0 and y>0 and x<int(l.width)-1 and y<int(l.height)-1
			if not locked.is_empty():
				var blueprint = Color("5b7681") if str(locked.id) == next_plot else Color("62696b")
				base_color = (blueprint if y % 2 == 0 else blueprint.lightened(.025)) * blueprint_tint
			elif wall: base_color = Color("74978b") if inner_wall else Color("587b76")
			floor_canvas.draw_rect(rect,base_color)
			if not locked.is_empty():
				floor_canvas.draw_line(rect.position, rect.position + Vector2(unit, 0), Color("c8dfd6", .17), 1)
				floor_canvas.draw_line(rect.position, rect.position + Vector2(0, unit), Color("c8dfd6", .17), 1)
				if x % 3 == 0 and y % 3 == 0:
					floor_canvas.draw_line(rect.position - Vector2(unit*.12, 0),rect.position + Vector2(unit*.12, 0),Color("e1e5c9",.5),1)
					floor_canvas.draw_line(rect.position - Vector2(0, unit*.12),rect.position + Vector2(0, unit*.12),Color("e1e5c9",.5),1)
			elif inner_wall:
				floor_canvas.draw_rect(Rect2(rect.position+Vector2(5,5),rect.size-Vector2(10,10)),Color("a9c5b7"))
				floor_canvas.draw_line(rect.position+Vector2(6,unit*.3),rect.position+Vector2(unit-6,unit*.3),Color("e0e9d7"),2)
			elif wall:
				floor_canvas.draw_rect(Rect2(rect.position+Vector2(2,unit-8),Vector2(unit-4,5)),Color("526a56"))
				if y==0 and x>1 and x<int(l.width)-2 and x%3==0:
					floor_canvas.draw_rect(Rect2(rect.position+Vector2(unit*.18,unit*.12),Vector2(unit*.64,unit*.53)),Color("405d66"))
					floor_canvas.draw_rect(Rect2(rect.position+Vector2(unit*.24,unit*.16),Vector2(unit*.5,unit*.42)),Color("a5c9bd"))
					floor_canvas.draw_line(rect.position+Vector2(unit*.49,unit*.16),rect.position+Vector2(unit*.49,unit*.58),Color("e6d9ad"),maxf(1,unit*.04))
			else:
				if y > int(kitchen.bottom):
					# Half-length staggered joints keep the dining room floor legible as timber.
					for side in [0.0, .5]:
						var edge = rect.position + Vector2(0, side * unit)
						floor_canvas.draw_line(edge, edge + Vector2(unit, 0), Color("825f49", .22), 1)
						if (x + y + int(side * 2)) % 3 == 0:
							floor_canvas.draw_line(edge, edge + Vector2(0, unit * .5), Color("825f49", .23), 1)
					if (x + y) % 4 == 0:
						floor_canvas.draw_line(rect.position + Vector2(.21,.72)*unit, rect.position + Vector2(.77,.72)*unit, Color("ffebc1",.5), 1)
				else:
					floor_canvas.draw_rect(rect, Color("77998c", .23), false, 1)
					if x % 3 == 1 and y % 3 == 1:
						var p = rect.get_center()
						var d = unit * .09
						floor_canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-d,0),p+Vector2(0,-d),p+Vector2(d,0),p+Vector2(0,d)]),Color("66a598",.39))
			if not wall and y==int(kitchen.bottom)+1 and x in [5,10]:
				floor_canvas.draw_rect(Rect2(rect.position+Vector2(3,unit*.42),Vector2(unit-6,unit*.18)),Color("748e77"))
			elif (editing or placing_wall) and not wall:
				floor_canvas.draw_rect(rect,Color(0.45,0.4,0.3,0.2),false,1)

func _draw() -> void:
	if sim == null or font == null: return
	var unit = _unit()
	var origin = _origin()
	var l = sim.layout
	var kitchen = Grid.kitchen_bounds(l)
	var next_plot = str(sim.next_land_plot().get("id", "")) if sim.phase == "NIGHT" else ""
	_draw_window_light(origin, unit, l)
	var zone = sim.chapter.trophy_zone
	if sim.trophy_shop_unlocked():
		_draw_unlocked_trophy_zone(origin,unit,zone)
		if not trophy_placement_id.is_empty(): _draw_trophy_placement(origin, unit, zone)
		_draw_trophy_shop(unit)
	_draw_locked_plots(origin,unit,l,next_plot)
	_draw_frontage(origin, unit, l)
	draw_rect(Rect2(origin + Vector2(kitchen.left,kitchen.top) * unit, Vector2(int(kitchen.right)-int(kitchen.left)+1,int(kitchen.bottom)-int(kitchen.top)+1) * unit), Color(0.24,0.36,0.27,0.24), false, 2)
	for f in l.facilities:
		if Grid.placed(f) and f.type != "trophy_shop" and (not drag_active or f.id != pressed_entity): _draw_facility(f)
	var moving_staff = selected_id.begins_with("preview_")
	if sim.phase == "NIGHT" and moving_staff and actors.has(selected_id):
		draw_circle(actors[selected_id].position, unit * .37, Color("ffe19a"), false, 2.0, true)
	if sim.phase == "NIGHT" and not pressed_entity.is_empty() and not drag_active:
		var fraction = clampf(press_elapsed / HOLD_TO_DRAG, 0.0, 1.0)
		if fraction > 0.12:
			draw_arc(press_position, unit * .55, -PI * .5, -PI * .5 + TAU * fraction, 20, Style.GOLD, 2.2, true)
	if sim.phase == "NIGHT" and (editing or drag_active) and not selected_id.is_empty():
		var f = Grid.find(l, selected_id)
		if editing and not f.is_empty() and f.type not in ["trophy", "decoration"] and Grid.placed(f):
			var route = Grid.approach_cells(l, Grid.vec(l.waiter_spawn), Grid.interaction_cells(f), navigation).get("path", [])
			var last = screen_point(Grid.vec(l.waiter_spawn))
			for cell in route:
				var next = screen_point(cell)
				draw_line(last, next, Color("698f65"), 2)
				draw_circle(next, 3, Color("55774f"))
				last = next
		if hovered.x >= 1 and hovered.x < int(l.width)-1 and hovered.y >= 1 and hovered.y < int(l.height)-1:
			_draw_drop_preview(f, moving_staff, origin, unit)
	if sim.phase == "NIGHT" and placing_wall and Rect2i(0, 0, int(l.width), int(l.height)).has_point(hovered):
		_draw_wall_preview(origin, unit)
	if actor_cells.has(follow_actor_id):
		var target = screen_point(actor_cells[follow_actor_id])
		var accent = Color("f5cf8c", .76 * actors[follow_actor_id].modulate.a)
		draw_arc(target + Vector2(0, unit * .31), unit * .38, PI * .12, PI * .88, 18, accent, 2.0, true)
	var gate = screen_point(Grid.vec(l.entrance))
	draw_polyline(PackedVector2Array([gate + Vector2(-unit*.78, -unit*.17), gate + Vector2(-unit*.52, 0), gate + Vector2(-unit*.78, unit*.17)]), Color("f2dfad"), 2.5, true)
	for cell in guide_markers:
		var rect = Rect2(screen_point(cell) - Vector2.ONE * unit * 0.55, Vector2.ONE * unit * 1.1)
		draw_rect(rect, Color("49351d"), false, 6)
		draw_rect(rect, Style.GOLD, false, 3)
	if diagnostic_entrance or not diagnostic_facilities.is_empty():
		for cell in _diagnostic_cells():
			var f = Grid.facility_at(l, Vector2i(cell))
			var extent = Vector2(Grid.footprint(f).size) if not f.is_empty() else Vector2.ONE
			var bounds = Rect2(origin + (cell + Vector2.ONE * .04) * unit, (extent - Vector2.ONE * .08) * unit)
			draw_rect(bounds, Color("302a1c"), false, 6.0)
			draw_rect(bounds, Color("ffcf68"), false, 3.0)

func _draw_drop_preview(f: Dictionary, moving_staff: bool, origin: Vector2, unit: float) -> void:
	var area = Rect2i(hovered, Vector2i.ONE)
	var valid = walkable_cells.has(hovered)
	var merging = false
	if moving_staff:
		valid = valid and not preview_positions.get("chef", []).has(hovered) and not preview_positions.get("waiter", []).has(hovered)
	elif not f.is_empty():
		var placement = _drop_cell(str(f.id), hovered) if drag_active else hovered
		var ghost = f.duplicate()
		ghost.pos = [placement.x, placement.y]
		if f.type == "decoration":
			if decor_preview_turns >= 0: ghost.rotation = decor_preview_turns
			_draw_decoration_preview(ghost, origin, unit)
			return
		area = Grid.footprint(ghost)
		var hit = Grid.facility_at(sim.layout, hovered)
		merging = not hit.is_empty() and hit.id != f.id and hit.type == "table" and f.type == "table" and Grid.table_size(f) < 4 and Grid.table_size(hit) == Grid.table_size(f)
		if merging: area = Grid.footprint(hit)
		else:
			valid = Grid.footprint_cells(ghost).all(func(cell):
				var occupying = Grid.facility_at(sim.layout, cell)
				return not Grid.structural_blocked(sim.layout, cell) and (occupying.is_empty() or occupying.id == f.id)
			)
			if f.type == "trophy":
				valid = trophy_cells.has(placement)
			if drag_active or not Grid.placed(f): _draw_facility(ghost)
	var tint = Color("efc774", .45) if merging else (Color("74ac66", .32) if valid else Color("de5e4a", .45))
	var bounds = Rect2(origin + Vector2(area.position) * unit, Vector2(area.size) * unit)
	draw_rect(bounds, tint)
	draw_rect(bounds, Color(tint, .9), false, 2)

func _draw_decoration_preview(ghost: Dictionary, origin: Vector2, unit: float) -> void:
	var definition = sim.decoration_defs[ghost.decoration_id]
	var key = [ghost.id, ghost.pos, ghost.rotation, sim.revision]
	if key != decor_preview_key:
		decor_preview_key = key
		var cells = Decor.coverage(ghost, definition, sim.layout)
		var affected = sim.layout.facilities.filter(func(f): return Grid.placed(f) and Decor.affects(f, definition, cells))
		decor_preview = {"cells": cells, "affected": affected, "valid": sim.decoration_can_place(ghost)}
	var tint = Color("f5df87") if decor_preview.valid else Color("ef9577")
	for cell in decor_preview.cells:
		var area = Rect2(origin + Vector2(cell) * unit, Vector2.ONE * unit)
		draw_rect(area, Color(tint, .35))
		for side in Grid.DIRECTIONS:
			if decor_preview.cells.has(cell + side): continue
			var normal = Vector2(side)
			var edge_center = area.get_center() + normal * unit * .5
			var half_edge = normal.orthogonal() * unit * .5
			draw_line(edge_center - half_edge, edge_center + half_edge, tint, 2.25, true)
	if decor_preview.valid:
		for target in decor_preview.affected:
			var footprint = Grid.footprint(target)
			var rect = Rect2(origin + Vector2(footprint.position) * unit, Vector2(footprint.size) * unit).grow(-2)
			draw_rect(rect, Color("2b3330"), false, 6)
			draw_rect(rect, tint, false, 3)
		if definition.effect == "waiter_speed":
			for cell in preview_positions.get("waiter", []):
				if decor_preview.cells.has(cell):
					draw_circle(screen_point(Vector2(cell)), unit * .43, tint, false, 3, true)
	_draw_facility(ghost)
	var occupation = Grid.footprint(ghost)
	draw_rect(Rect2(origin + Vector2(occupation.position) * unit, Vector2(occupation.size) * unit), tint, false, 2)

func _draw_wall_preview(origin: Vector2, unit: float) -> void:
	var stroke = _wall_row_to(hovered)
	if wall_preview.get("cells") != stroke.cells or wall_preview.get("revision") != sim.revision:
		wall_preview = {"cells":stroke.cells, "revision":sim.revision, "valid":sim.wall_row_status(stroke.cells).ok}
	for cell in stroke.cells:
		var bounds = Rect2(origin + Vector2(cell) * unit, Vector2.ONE * unit)
		if wall_preview.valid:
			draw_set_transform(bounds.get_center(), float(stroke.turns) * PI / 2.0, Vector2.ONE * unit / 48.0)
			_draw_wall_tile(.68)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(bounds, Color("b86156", .38))
		draw_rect(bounds.grow(-1), Style.GREEN if wall_preview.valid else Style.RED, false, 2.0)

func _draw_window_light(origin: Vector2, unit: float, l: Dictionary) -> void:
	var hour = _scene_hour()
	var strength = (1.0 - Lighting.lamplight(hour)) * .20
	if strength < .01: return
	var offset = Lighting.cast_direction(hour).x * .88
	for x in range(3, int(l.width) - 2, 3):
		if not Grid.locked_plot_at(l, Vector2i(x, 1)).is_empty(): continue
		var start = origin + Vector2(x + .22, 1) * unit
		var length = (1.55 + absf(offset)) * unit
		for pane in [0.0, .32]:
			var a = start + Vector2(pane * unit, 0)
			var b = a + Vector2(unit * .23, 0)
			var shift = Vector2(offset * unit, length)
			draw_polygon(PackedVector2Array([a,b,b+shift,a+shift]), PackedColorArray([
				Color("ffedba",strength), Color("ffedba",strength), Color("ffedba",.0), Color("ffedba",.0)]))

func _draw_trophy_shop(unit: float) -> void:
	var cell = sim.trophy_shop_cell()
	var center = screen_point(Vector2(cell))
	draw_set_transform(center, 0, Vector2.ONE * unit / 48.0)
	draw_rect(Rect2(-21, -16, 44, 38), Color("443445"))
	draw_rect(Rect2(-19, -20, 40, 22), Color("9a6654"))
	draw_rect(Rect2(-17, -3, 36, 20), Color("775379"))
	draw_rect(Rect2(-13, 0, 28, 13), Color("f2ce8b"))
	draw_rect(Rect2(-16, -20, 34, 3), Color("e5ad78"))
	for x in range(-15, 19, 8):
		draw_rect(Rect2(x, -15, 4, 9), Color("e3b68a"))
	draw_circle(Vector2(0, 4), 5, Color("72544b"))
	draw_line(Vector2(0, 8), Vector2(0, 11), Color("72544b"), 2)
	draw_line(Vector2(-5, 11), Vector2(5, 11), Color("72544b"), 2)
	if _trophy_shop_at(hovered):
		draw_rect(Rect2(-22, -22, 46, 46), Style.GOLD, false, 2)
	draw_set_transform(Vector2.ZERO)
	var sign = _trophy_shop_sign(cell, unit)
	var font_size = int(sign.size.y) - 5
	draw_rect(sign, Color("3e3143", .95))
	draw_string(font, sign.position + Vector2(4, font_size), "奖杯商店", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("ffe4b4"))

func _sync_trophy_placement() -> void:
	var next_id := ""
	if sim.phase == "NIGHT" and (editing or drag_active):
		var fixture = Grid.find(sim.layout, selected_id)
		if fixture.get("type") == "trophy": next_id = selected_id
	if next_id == trophy_placement_id and trophy_placement_revision == sim.revision: return
	trophy_placement_id = next_id
	trophy_placement_revision = sim.revision
	trophy_cells = {} if next_id.is_empty() else sim.trophy_placement_cells(next_id)

func _draw_trophy_placement(origin: Vector2, unit: float, zone: Dictionary) -> void:
	var first = Vector2(zone.left, zone.top)
	var size_in_cells = Vector2(zone.right - zone.left + 1, zone.bottom - zone.top + 1)
	var area = Rect2(origin + first * unit, size_in_cells * unit)
	draw_rect(area, Color("13342d", .58))
	draw_rect(area, Color("184132"), false, 6)
	draw_rect(area, Color("b0ffe7"), false, 3)
	for cell in trophy_cells:
		var bounds = Rect2(origin + Vector2(cell) * unit, Vector2.ONE * unit).grow(-1.5)
		draw_rect(bounds, Color("59cc96", .62))
		draw_rect(bounds, Color("c9ffe4", .86), false, 1.5)
		draw_circle(bounds.get_center(), 2.2, Color("e2fff0"))
	var text = "奖杯展示区 · 亮格可放" if not trophy_cells.is_empty() else "奖杯展示区 · 暂无空位"
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var caption = Rect2(area.get_center().x - width * .5 - 7, area.position.y - 26, width + 14, 23)
	draw_rect(caption, Color("183d36"))
	draw_rect(caption, Color("90c5b1"), false, 1)
	draw_string(font, caption.position + Vector2(7, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e1ffee"))

func _draw_unlocked_trophy_zone(origin: Vector2, unit: float, zone: Dictionary) -> void:
	var display_area = Rect2(origin+Vector2(float(zone.left),float(zone.top))*unit,Vector2(float(int(zone.right)-int(zone.left)+1),float(int(zone.bottom)-int(zone.top)+1))*unit)
	draw_rect(display_area,Color("7b668c",.15))
	draw_rect(display_area,Color("d5af73",.8),false,2)

func _draw_locked_plots(origin: Vector2, unit: float, l: Dictionary, next_plot: String) -> void:
	for plot in l.plots:
		if plot.id in l.unlocked_plots: continue
		var b = plot.bounds
		var top = origin+Vector2(float(b.left),float(b.top))*unit
		var area = Rect2(top,Vector2(float(int(b.right)-int(b.left)+1),float(int(b.bottom)-int(b.top)+1))*unit)
		draw_rect(area, Color("252c32", .15))
		var current = str(plot.id) == next_plot
		var outline = Color("a7adae", .5)
		if current: outline = Color("efc17a", .92) if sim.land_plot_status(next_plot).ok else Color("d3b78a", .70)
		draw_rect(area, outline, false, maxf(1.5, unit * .065))
		for f in plot.fixtures:
			var center = screen_point(Grid.vec(f.pos))
			var ghost = Color("eee2bb", .39) if current else Color("c4c8c7", .36)
			if f.type == "trophy":
				draw_circle(center - Vector2(0, unit * .07), unit * .19, ghost, false, 1.5, true)
				draw_line(center + Vector2(-unit * .22, unit * .19), center + Vector2(unit * .22, unit * .19), ghost, 2.0)
			else:
				draw_rect(Rect2(center - Vector2(unit * .30, unit * .25), Vector2(unit * .60, unit * .47)), ghost, false, 1.5)
				if f.type == "stove":
					for dx in [-.13, .13]:
						draw_circle(center + Vector2(unit * dx, 0), unit * .058, ghost)

func _draw_frontage(origin: Vector2, unit: float, l: Dictionary) -> void:
	var door_y = float(l.entrance[1])
	var entrance = origin + Vector2(0,door_y)*unit
	# Two walkable gate cells stay clear; the arch and glass panels frame them.
	draw_rect(Rect2(entrance+Vector2(-unit*.23,-unit*.41),Vector2(unit*1.42,unit*.39)),Color("374f4a"))
	draw_rect(Rect2(entrance+Vector2(-unit*.24,-unit*.52),Vector2(unit*1.45,unit*.16)),Color("c58b54"))
	draw_rect(Rect2(entrance+Vector2(unit*.96,0),Vector2(unit*.12,unit*2.0)),Color("495f50"))
	draw_rect(Rect2(entrance+Vector2(-unit*.19,0),Vector2(unit*.12,unit*2.0)),Color("495f50"))
	for stripe in range(7):
		var awning = Color("aa654c") if stripe % 2 == 0 else Color("e1c89d")
		draw_rect(Rect2(entrance + Vector2((-0.29 + stripe * 0.22) * unit, -0.28 * unit), Vector2(unit * 0.22, unit * 0.32)), awning)
	for yy in [0.14,1.14]:
		draw_rect(Rect2(entrance+Vector2(unit*.04,unit*yy),Vector2(unit*.84,unit*.62)),Color("7aa3a0",.25))
		draw_line(entrance+Vector2(unit*.45,unit*yy),entrance+Vector2(unit*.45,unit*(yy+.62)),Color("eee2bd",.7),maxf(1,unit*.035))
	var title = str(sim.chapter.title)
	var sign = entrance + Vector2(-unit * .26, -unit * .60)
	var title_width = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_rect(Rect2(sign - Vector2(4, 15), Vector2(title_width + 8, 20)), Color("544137"))
	draw_string(font, sign, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f5deb2"))


func _draw_trophy(id: String) -> void:
	var definition = sim.relic_defs[id]
	var metal = Color(str(definition.color))
	draw_rect(Rect2(-20,14,40,8),Color("544a49"))
	draw_rect(Rect2(-16,10,32,6),Color("c4a56f"))
	match id:
		"bronze_clock":
			draw_circle(Vector2(0,-5),15,metal)
			draw_circle(Vector2(0,-5),11,Color("fff5d5"))
			draw_line(Vector2(0,-5),Vector2(0,-13),metal,2)
			draw_line(Vector2(0,-5),Vector2(7,-2),metal,2)
		"ember_cup":
			draw_rect(Rect2(-11,-17,22,23),metal)
			draw_arc(Vector2(11,-8),8,-PI/2,PI/2,12,metal,3)
			draw_rect(Rect2(-2,5,4,7),metal)
		"silver_bell":
			draw_circle(Vector2(0,-4),14,metal)
			draw_rect(Rect2(-15,-4,30,13),metal)
			draw_circle(Vector2(0,10),4,Color("e9c479"))
		"jade_medal":
			draw_colored_polygon(PackedVector2Array([Vector2(-15,-8),Vector2(0,-23),Vector2(15,-8),Vector2(0,7)]),metal)
			draw_circle(Vector2(0,-7),5,Color("e7dfba"))
		"golden_spoon":
			draw_line(Vector2(-8,9),Vector2(6,-8),metal,6)
			draw_circle(Vector2(9,-13),9,metal)
		"laurel_crown":
			draw_rect(Rect2(-15,-5,30,13),metal)
			for x in [-12,0,12]: draw_colored_polygon(PackedVector2Array([Vector2(x-5,-5),Vector2(x,-20),Vector2(x+5,-5)]),metal)
		"dining_hourglass":
			draw_colored_polygon(PackedVector2Array([Vector2(-11,-20),Vector2(11,-20),Vector2(0,-6)]),Color("fff1ce"))
			draw_colored_polygon(PackedVector2Array([Vector2(0,-6),Vector2(11,9),Vector2(-11,9)]),Color("fff1ce"))
			draw_colored_polygon(PackedVector2Array([Vector2(-8,7),Vector2(0,-1),Vector2(8,7)]),metal)
			draw_circle(Vector2(0,-6),1.5,metal)
			draw_rect(Rect2(-14,-22,28,4),metal)
			draw_rect(Rect2(-14,8,28,4),metal)

func _draw_facility(f: Dictionary) -> void:
	if f.type == "decoration":
		var footprint = Grid.footprint(f)
		var bounds = Rect2(_origin() + Vector2(footprint.position) * _unit(), Vector2(footprint.size) * _unit())
		var selected = selected_id == f.id or footprint.has_point(hovered)
		DecorArt.paint(self, bounds, sim.decoration_defs[f.decoration_id], Grid.rotation(f))
		if selected and not editing and not drag_active: draw_rect(bounds.grow(-2), Style.GOLD, false, 2)
		_draw_facility_label(f, bounds.get_center(), bounds.position.y, selected)
		return
	if f.type == "table" and Grid.table_size(f) > 1:
		_draw_large_table(f)
		return
	var unit = _unit()
	var center = screen_point(Grid.vec(f.pos))
	var scale_value = unit / 48.0
	draw_set_transform(center, 0, Vector2.ONE * scale_value)
	var cast = Lighting.cast_direction(_scene_hour()) * 5.0
	draw_rect(Rect2(Vector2(-15, -7) + cast, Vector2(32, 24)), Color("514559", .19))
	draw_set_transform(center, Grid.rotation(f) * PI / 2.0, Vector2.ONE * scale_value)
	if f.type == "table":
		draw_rect(Rect2(-18,-12,38,26), Color("795b3f"))
		draw_rect(Rect2(-16,-14,34,24), Color("b68a56"))
		draw_rect(Rect2(-12,-10,26,16), Color("e6d3a4"))
		draw_rect(Rect2(-3,-12,8,20), Color("74998a"))
		draw_line(Vector2(-3,5), Vector2(5,5), Color("e6dbc3"), 1)
		draw_circle(Vector2(9,-6),3.6, Color("fbefd3"))
		draw_circle(Vector2(9,-6),2.1, Color("b67b4e"))
		draw_rect(Rect2(-6,21,15,5), Color("98784e"))
		if sim.seats.has(f.id) and int(sim.seats[f.id]) != 0:
			var c = sim.customers[int(sim.seats[f.id])]
			if c.state == "EATING":
				draw_circle(Vector2(1,-3),8,Color("faf0d6"))
				draw_circle(Vector2(1,-3),5,Color("d3a751"))
	elif f.type == "wall":
		_draw_wall_tile()
	elif f.type == "stove":
		draw_rect(Rect2(-18,-18,36,36),Color("526352"))
		draw_rect(Rect2(-15,-15,30,25),Color("7b8976"))
		for point in [Vector2(-7,-7),Vector2(7,-7),Vector2(-7,5),Vector2(7,5)]:
			draw_circle(point,5,Color("384638"))
			draw_circle(point,2,Color("c98a48") if sim.stoves.has(f.id) and sim.stoves[f.id].owner != 0 else Color("879478"))
		draw_rect(Rect2(-10,13,21,3),Color("cfcead"))
	elif f.type == "order":
		draw_rect(Rect2(-20,-17,40,34),Color("8b704b"))
		draw_rect(Rect2(-13,-11,24,21),Color("f5e6bd"))
		for i in range(3): draw_line(Vector2(-8,-5+i*5),Vector2(6,-5+i*5),Color("9e986e"),2)
	elif f.type == "cashier":
		draw_rect(Rect2(-20,-20,40,40),Color("68543b"))
		draw_rect(Rect2(-16,-17,32,28),Color("cfb16c"))
		draw_rect(Rect2(-11,-10,22,15),Color("293e36"))
		draw_string(font,Vector2(-7,2),"$",HORIZONTAL_ALIGNMENT_CENTER,14,15,Color("f0bb63"))
	elif f.type == "trophy":
		_draw_trophy(str(f.relic_id))
	elif f.type in ["slot", "decor_shop"]:
		draw_rect(Rect2(-20,-23,40,46),Color("4f7467") if f.type == "decor_shop" else Color("794c54"))
		draw_rect(Rect2(-15,-17,30,25),Color("a9c79a") if f.type == "decor_shop" else Color("ebc978"))
		for pos in [Vector2(-9,-10),Vector2(-1,-10),Vector2(7,-10)]:
			draw_rect(Rect2(pos,Vector2(6,12)),Color("fbf4da"))
		draw_rect(Rect2(-12,13,24,4),Color("514340"))
	else:
		draw_rect(Rect2(-22,-17,44,34),Color("709372"))
		draw_rect(Rect2(-18,-12,36,21),Color("b5c4a0"))
		for point in [Vector2(-9,-2),Vector2(8,-2)]:
			draw_circle(point,7,Color("eee5cc"))
	draw_set_transform(center, 0, Vector2.ONE * scale_value)
	if f.type in ["cashier","slot","decor_shop"]:
		draw_rect(Rect2(-23,-26,46,52),Color(0.94,0.73,0.39,0.45),false,2)
	if hovered == Vector2i(Grid.vec(f.pos)) and not editing:
		draw_rect(Rect2(-25,-27,50,54),Color("ffda84"),false,3)
	if selected_id == f.id:
		draw_rect(Rect2(-24,-24,48,48),Color("c99d4c"),false,3)
	if sim.phase == "NIGHT" and bool(accessibility_cache.get(f.id,false)):
		draw_line(Vector2(-16,-16),Vector2(16,16),Color("cb6650"),3)
		draw_line(Vector2(-16,16),Vector2(16,-16),Color("cb6650"),3)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	if sim.phase == "NIGHT" and (f.id == selected_id or hovered == Vector2i(Grid.vec(f.pos))) and (Grid.can_rotate(f) or f.type in ["order", "pass"]):
		for cell in Grid.interaction_cells(f):
			if walkable_cells.has(cell):
				var marker = center.lerp(screen_point(Vector2(cell)), .67)
				draw_circle(marker, maxf(2.5, unit * .085), Color("365750"))
				draw_circle(marker, maxf(1.5, unit * .048), Color("e9e3a6"))
	_draw_facility_label(f, center, center.y - unit * .5, hovered == Vector2i(Grid.vec(f.pos)))

func _draw_wall_tile(opacity: float = 1.0) -> void:
	draw_rect(Rect2(-24, -24, 48, 48), Color("4d6256", opacity))
	draw_rect(Rect2(-24, -24, 48, 10), Color("acbf9f", opacity))
	draw_rect(Rect2(-24, -24, 48, 3), Color("d0d9b6", opacity))
	draw_rect(Rect2(-24, -13, 48, 29), Color("758f7a", opacity))
	for x in [-21, -7, 7]:
		draw_rect(Rect2(x, -7, 12, 18), Color("8ea890", opacity))
		draw_line(Vector2(x + 2, -6), Vector2(x + 2, 8), Color("adc0a3", opacity), 1.0)
	draw_rect(Rect2(-24, 16, 48, 4), Color("cfb287", opacity))
	draw_rect(Rect2(-24, 20, 48, 4), Color("526658", opacity))

func _draw_large_table(f: Dictionary) -> void:
	var area = Grid.footprint(f)
	var unit = _unit()
	var bounds = Rect2(_origin() + Vector2(area.position) * unit, Vector2(area.size) * unit)
	var tabletop = bounds.grow(-unit * .12)
	draw_rect(Rect2(tabletop.position + Vector2(unit * .07, unit * .10), tabletop.size), Color("514559", .23))
	draw_rect(tabletop, Color("855e40"))
	draw_rect(tabletop.grow(-unit * .055), Color("bc925f") if Grid.table_size(f) == 2 else Color("97654e"))
	draw_rect(tabletop.grow(-unit * .12), Color("ebd6a7"))
	var center = tabletop.get_center()
	var runner = Vector2(tabletop.size.x - unit * .22, unit * .16) if Grid.rotation(f) % 2 == 0 else Vector2(unit * .16, tabletop.size.y - unit * .22)
	draw_rect(Rect2(center - runner * .5, runner), Color("74998a") if Grid.table_size(f) == 2 else Color("9c6c67"))
	var slots = sim.table_slots.get(f.id, [])
	var chairs = Grid.interaction_cells(f)
	for i in range(chairs.size()):
		var cell = chairs[i]
		var nearest = Vector2i(clampi(cell.x, area.position.x, area.end.x - 1), clampi(cell.y, area.position.y, area.end.y - 1))
		var outward = Vector2(cell - nearest)
		var chair = screen_point(Vector2(nearest)) + outward * unit * .55
		var chair_size = Vector2(.35, .18) * unit if outward.y != 0 else Vector2(.18, .35) * unit
		draw_rect(Rect2(chair - chair_size * .5, chair_size), Color("aa8058"))
		var plate = screen_point(Vector2(nearest)) + outward * unit * .09
		draw_circle(plate, unit * .12, Color("fff0d3"))
		if i < slots.size():
			var guest = sim.customers.get(int(sim.seats[slots[i]]), {})
			if guest.get("state") == "EATING": draw_circle(plate, unit * .075, Color("d3a751"))
	var hovering = area.has_point(hovered)
	if f.id == selected_id or hovering: draw_rect(bounds.grow(-1), Color("ffda84"), false, 2.5)
	_draw_facility_label(f, center, bounds.position.y, hovering)

func _draw_facility_label(f: Dictionary, center: Vector2, top: float, hovering: bool) -> void:
	if f.type not in ["cashier", "slot", "decor_shop"] and f.id != selected_id and not hovering and f.id not in diagnostic_facilities:
		return
	var font_size = clampi(roundi(_unit() * 0.27), 13, 17)
	var width = font.get_string_size(str(f.name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_origin = Vector2(roundf(center.x - (width + 8) * .5), roundf(top - font_size - 11))
	draw_rect(Rect2(label_origin, Vector2(width + 8, font_size + 8)), Color(0.11, 0.19, 0.15, 0.86))
	draw_string(font, label_origin + Vector2(4, font_size + 1), str(f.name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Style.INK)
