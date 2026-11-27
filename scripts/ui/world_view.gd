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
const CommercialStreet = preload("res://scripts/visuals/canyon_paths.gd")
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
const WorldSigns = preload("res://scenes/canyon/signs.tscn")
const District3D = preload("res://scripts/visuals/district_3d.gd")
const Crew = preload("res://scripts/core/crew_roster.gd")
const EMBER = preload("res://assets/interface/lantern-ember.png")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const HOLD_TO_DRAG = .30
const STREET_APPROACH_SECONDS := 4.5
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
var route_preview_key: Array = []
var route_preview: Array = []
var camera_pan = Vector2.ZERO
var zoom = 1.0
var dragging_camera = false
var press_position = Vector2.ZERO
var pressed_entity = ""
var press_elapsed = 0.0
var drag_active = false
var grab_offset = Vector2i.ZERO
var touches: Dictionary = {}
var touch_origin := Vector2.ZERO
var touch_panning := false
var touch_multitouch := false
var touch_primary_started := false
var actors: Dictionary = {}
var actor_cells := {}
var queue_motion := {}
var nearby_feet := {}
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
var district_3d: SubViewportContainer
var signs: Control
var overview := false
var overview_mix := 0.0
var flight: Tween
signal roof_view_changed(closed: bool)
var inspect_roof := false
var keep_cutaway := false
var roof_blend := 0.
var entering_canyon := false
var threshold_approach := false
var threshold_mix := 0.
var threshold_cross := 0.
var threshold_aperture := 0.
var traffic_aperture := 0.
var traffic_door_hold := 0.
var scroll_target := -1.0
var scroll_anchor := Vector2.ZERO
signal entry_finished
var sun_light: PointLight2D
var shadow_geometry: Node2D
var city_geometry: Node2D
var street = CommercialStreet.new()
var street_canvas := Control.new()
var street_backdrop := ColorRect.new()
var street_activity := Control.new()
var street_signs := Control.new()
var floor_canvas := Control.new()
var weather
var carry_weather := false
var weather_day := -1
var migration_today := false
var room_lamp_light := 0.0
var street_lamp_light := 0.0
var street_draw_bounds := Rect2()
var scene_light_band := -1
var floor_style := []
var sign_view := []
const FLOOR_DRAW_UNIT := 28.0
var plot_buttons: Dictionary = {}
var home_bounds := Rect2()
var home_target := Rect2()
var home_signature := 0
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
var feature_home := Vector3.ZERO
var feature_active := false
var feature_cell := Vector2.ZERO
var feature_zoom := 1.0
var feature_motion: Tween
var rendered_phase := ""
var rendered_hour := 22.0
var transition_from := 22.0
var transition_time := 0.0
var transition_duration := 0.0

func _init(atmosphere: Dictionary = {}) -> void:
	carry_weather = not atmosphere.is_empty()
	weather = atmosphere.weather if carry_weather else Weather.new()
	if carry_weather: street.elapsed = atmosphere.elapsed

func release_atmosphere() -> Dictionary:
	var atmosphere := {"weather":weather,"elapsed":street.elapsed}
	remove_child(weather.ground)
	remove_child(weather)
	weather = null
	return atmosphere

func release_stage():
	var stage = district_3d
	district_3d = null
	if stage != null:
		for id in stage.actor_planes.keys(): stage.remove_actor(id)
		remove_child(stage)
	return stage

func _ready() -> void:
	font = Style.font()
	light_mask = 2
	if DisplayServer.get_name() != "headless":
		if district_3d == null: district_3d = District3D.new()
		district_3d.name = "District3D"
		add_child(district_3d)
		district_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if district_3d != null:
		street_backdrop.hide()
		street_canvas.hide()
		floor_canvas.hide()
		street_activity.hide()
		street_signs.hide()
		weather.use_spatial_rain = true
		# Wetness and audio drive the 3D scene. The old TileMap puddle and lamp
		# canvases have no perspective transform.
		weather.ground.hide()
		weather.hide()
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
	signs = WorldSigns.instantiate()
	add_child(signs)
	signs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	signs.hide()
	signs.landmark_pressed.connect(func(id): inspect_requested.emit("landmark", id))
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
			var solid = Grid.has_room(l, cell) and (walls.has(cell) or Grid.structural_blocked(l, cell))
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
		migration_today = sim.events_for().any(func(event): return event.id == "river_lantern_run")
	weather.advance(delta, sim.phase == "DAY" and sim.paused)
	weather.align_to_world(_origin(), _unit(), size, Lighting.lamplight(_scene_hour()))

func reset_scene_time() -> void:
	home_bounds = Rect2()
	home_signature = 0
	if district_3d != null: district_3d.finish_construction()
	weather_day = -1
	if carry_weather: carry_weather = false
	else: weather.reset()
	street_arrivals.clear()
	queue_motion.clear()
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

func _sync_home_bounds(delta: float) -> void:
	var signature := hash([sim.layout.width, sim.layout.height, sim.layout.unlocked_plots])
	if home_signature != signature or not home_target.has_area():
		home_signature = signature
		home_target = Rect2(Grid.occupied_bounds(sim.layout))
	if not home_bounds.has_area():
		home_bounds = home_target
	elif home_bounds != home_target and not (dragging_camera or drag_active or editing or placing_wall or not pressed_entity.is_empty() or not touches.is_empty()):
		var blend := 1.0 - exp(-3.7 * delta)
		home_bounds = Rect2(home_bounds.position.lerp(home_target.position, blend), home_bounds.size.lerp(home_target.size, blend))
		if home_bounds.size.distance_to(home_target.size) < .015 and home_bounds.position.distance_to(home_target.position) < .015:
			home_bounds = home_target

func _home_unit() -> float:
	var dimensions := home_bounds.size if home_bounds.has_area() else Vector2(12,14)
	return clampf(minf(size.x / (dimensions.x + 12), camera_extent().y / (dimensions.y + 13)), 1.0, 130.0) * zoom

func _wide_unit() -> float:
	var bounds := Plan.bounds()
	return minf(size.x / bounds.size.x, size.y / bounds.size.y)

func _unit() -> float:
	return exp(lerpf(log(maxf(.01,_home_unit())), log(maxf(.01,_wide_unit())), overview_mix))

func _origin() -> Vector2:
	var home := home_bounds.get_center() if home_bounds.has_area() else Vector2(7,8)
	var anchor: Vector2 = home - Vector2(1.4,.35) - camera_pan / maxf(.01,_home_unit())
	return camera_extent().lerp(size,overview_mix) * .5 - anchor.lerp(Plan.bounds().get_center(), smoothstep(.12,1.0,overview_mix)) * _unit()

func play_construction(id: String) -> void:
	if district_3d == null: return
	_sync_neighbor_occluders()
	district_3d.sync_layout(sim.layout, street, pressed_entity if drag_active else "")
	district_3d.start_construction(id)

func screen_point(cell: Vector2) -> Vector2:
	if threshold_mix > .001 and district_3d != null:
		return district_3d.camera.unproject_position(Vector3(cell.x+.5,.10,(cell.y+.5)*District3D.DEPTH))
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
	if not feature_active and feature_motion != null:
		feature_motion.kill()
		feature_motion = null
	if guide_camera_active:
		guide_camera_manual = true
		end_guide_shot(false)

func enter_feature(cell: Vector2, magnification: float) -> void:
	if not feature_active and (feature_motion == null or not feature_motion.is_valid()):
		feature_home = Vector3(camera_pan.x, camera_pan.y, zoom)
	feature_active = true
	if overview_mix > .01: _fly(0.0, .85)
	feature_cell = cell
	feature_zoom = magnification
	if feature_motion != null: feature_motion.kill()
	feature_motion = null

func end_feature() -> void:
	if not feature_active: return
	feature_active = false
	if overview: _fly(1.0,.72)
	feature_motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	feature_motion.tween_property(self, "zoom", feature_home.z, .52)
	feature_motion.tween_property(self, "camera_pan", Vector2(feature_home.x, feature_home.y), .52)

func _advance_feature(delta: float) -> void:
	if not feature_active: return
	var blend := 1.0 - exp(-6.0 * delta)
	var anchor := Vector2(.25, .55)
	zoom = lerpf(zoom, feature_zoom, blend)
	var home := home_bounds.get_center() if home_bounds.has_area() else Vector2(7,8)
	var target := camera_extent() * (anchor - Vector2(.5,.5)) + (home - Vector2(1.4,.35) - feature_cell - Vector2(.5,.5)) * _home_unit()
	camera_pan = camera_pan.lerp(target, blend)

func pan_camera(amount: Vector2) -> void:
	if not camera_input_enabled: return
	_manual_camera()
	camera_pan += amount

# One continuous scale from the whole river valley through the entry court
# into the dining room. Wheel detents and trackpad gestures share this range.
func _zoom_limit() -> float:
	var size_in_cells := home_bounds.size if home_bounds.has_area() else Vector2(12,14)
	var base: float = _home_unit() / zoom
	# At least one dimension retains a strip of grounds at maximum magnification.
	var limit := maxf(size.x / (size_in_cells.x + 10), camera_extent().y / (size_in_cells.y + 9)) / base
	return clampf(limit, 1.0, 1.8)

func _roof_zoom_limit() -> float:
	var dims := home_bounds.size if home_bounds.has_area() else Vector2(12,14)
	var base: float = _home_unit() / zoom
	return clampf(minf(size.x/(dims.x+16),camera_extent().y/(dims.y+11))/base,1,1.8)

func set_roof_view(closed: bool, explicit := true) -> void:
	keep_cutaway = explicit and not closed
	if inspect_roof == closed: return
	inspect_roof = closed
	if closed:
		cancel_placement()
		stop_follow()
	roof_view_changed.emit(closed)

func _camera_scale() -> float:
	return _unit() / maxf(.01,_home_unit() / zoom)

func _apply_scale(point: Vector2, level: float) -> void:
	var base: float = _home_unit() / zoom
	var wide := minf(.99, _wide_unit() / base)
	if not keep_cutaway and not inspect_roof and (overview_mix > .65 or level >= _roof_zoom_limit()-.001):
		set_roof_view(true,false)
	level = clampf(level,wide,_roof_zoom_limit() if inspect_roof else _zoom_limit())
	var before := (point - _origin()) / _unit() - Vector2(.5,.5)
	var was_near := overview_mix <= .001
	zoom = maxf(1.0, level)
	overview_mix = clampf(log(minf(1.,level)) / log(wide),0,1)
	overview = overview_mix > .93
	if was_near and overview_mix <= .001 and not inspect_roof:
		camera_pan += point - screen_point(before)
	elif overview_mix > .995:
		camera_pan = Vector2.ZERO

func _push_through_roof(factor: float) -> bool:
	if factor <= 1. or not inspect_roof or overview_mix > .005: return false
	if _camera_scale() < _roof_zoom_limit()-.015: return false
	visit_threshold()
	return true

func zoom_at(point: Vector2, factor: float) -> void:
	if not camera_input_enabled or entering_canyon or feature_active or factor <= 0: return
	if _push_through_roof(factor): return
	_manual_camera()
	if flight != null: flight.kill()
	scroll_target = -1
	_apply_scale(point, _camera_scale() * factor)

func _wheel_zoom(point: Vector2, factor: float) -> void:
	if not camera_input_enabled or entering_canyon or feature_active: return
	if _push_through_roof(factor): return
	_manual_camera()
	if flight != null: flight.kill()
	var base: float = _home_unit() / zoom
	var start := _camera_scale() if scroll_target < 0 else scroll_target
	scroll_target = clampf(start * factor,minf(.99,_wide_unit()/base),_roof_zoom_limit() if inspect_roof or not keep_cutaway else _zoom_limit())
	scroll_anchor = point

func _advance_scroll(delta: float) -> void:
	if scroll_target <= 0: return
	var next := exp(lerpf(log(_camera_scale()),log(scroll_target),1.0-exp(-18.*delta)))
	if absf(next-scroll_target) < .001:
		next = scroll_target
		scroll_target = -1
	_apply_scale(scroll_anchor,next)

func _fly(amount: float, duration: float) -> void:
	scroll_target = -1
	if flight != null: flight.kill()
	flight = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flight.tween_property(self, "overview_mix", amount, duration)

func _door_flight() -> void:
	if flight != null: flight.kill()
	_manual_camera()
	cancel_placement()
	scroll_target = -1
	entering_canyon = true
	overview = false
	set_roof_view(false,true)
	flight = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _rise_from_door() -> void:
	flight.tween_callback(func(): threshold_approach = false)
	flight.tween_property(self,"threshold_mix",0.,1.18)
	flight.parallel().tween_property(self,"zoom",1.,1.18)
	flight.parallel().tween_property(self,"camera_pan",Vector2.ZERO,1.18)
	flight.tween_callback(func():
		entering_canyon = false
		keep_cutaway = false
		threshold_cross = 0.
		entry_finished.emit()
	)

func enter_from_threshold() -> void:
	_door_flight()
	threshold_mix = 1.
	threshold_cross = 1.
	threshold_aperture = 1.
	overview_mix = 0.
	_rise_from_door()

func visit_threshold() -> void:
	if entering_canyon or not camera_input_enabled: return
	_door_flight()
	threshold_approach = true
	threshold_aperture = 0.
	threshold_cross = 0.
	flight.tween_property(self,"threshold_mix",1.,.89)
	flight.parallel().tween_property(self,"overview_mix",0.,.89)
	flight.tween_property(self,"threshold_aperture",1.,.55)
	flight.parallel().tween_property(self,"threshold_cross",1.,.66)
	flight.tween_interval(.18)
	_rise_from_door()

func focus_restaurant() -> void:
	if entering_canyon: return
	set_roof_view(false,false)
	scroll_target = -1
	_manual_camera()
	zoom = 1.0
	camera_pan = Vector2.ZERO
	overview = false
	if overview_mix > 0.0: _fly(0.0, .85)

func focus_district() -> void:
	if sim == null or entering_canyon: return
	set_roof_view(true,false)
	_manual_camera()
	cancel_placement()
	overview = true
	_fly(1.0, .95)
	flight.finished.connect(func():
		signs.visible = camera_input_enabled and overview
		signs.focus_tavern()
	)

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
		if Grid.has_room(sim.layout, Vector2i(int(bounds.left)-1, floori(center.y))):
			center.x = float(bounds.left) + .6
		elif Grid.has_room(sim.layout, Vector2i(floori(center.x), int(bounds.top)-1)):
			center.y = float(bounds.top) + .6
		elif Grid.has_room(sim.layout, Vector2i(floori(center.x), int(bounds.bottom)+1)):
			center.y = float(bounds.bottom) - .6
		button.position = screen_point(center) - button.size * 0.5
		var current = id == next_plot and sim.phase == "NIGHT"
		button.visible = current and overview_mix < .40 and not inspect_roof and Rect2(Vector2.ZERO, size).intersects(button.get_rect())
		var interactive = current and not editing and not placing_wall and pressed_entity.is_empty() and camera_input_enabled
		button.disabled = not interactive
		button.mouse_filter = MOUSE_FILTER_PASS if interactive else MOUSE_FILTER_IGNORE
		if not button.visible:
			marker.ready = 0 if not current else -1
			continue
		var status = sim.land_plot_status(id) if current else {}
		var ready = bool(status.get("ok", false))
		marker.cost.text = str(int(plot.star_cost))
		button.tooltip_text = tr("%s · %d 闪星") % [tr(str(plot.name)), int(plot.star_cost)] if interactive else ""
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

func _update_traffic_door(delta: float) -> void:
	if sim.phase!="DAY":
		traffic_door_hold=0.
		traffic_aperture=0.
		return
	var near_gate:=Vector2(.355,float(sim.layout.entrance[1])+.5)
	traffic_door_hold=maxf(0.,traffic_door_hold-delta)
	for id in actor_cells:
		if str(id).begins_with("g_") and ((Vector2(actor_cells[id])-near_gate)*Vector2(1,Plan.DEPTH)).length_squared()<9.:
			traffic_door_hold=.70
			break
	traffic_aperture=move_toward(traffic_aperture,1. if traffic_door_hold>0. else 0.,delta*3.4)

func _process(delta: float) -> void:
	if sim == null:
		return
	_sync_home_bounds(delta)
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
	if not entering_canyon and camera_input_enabled and (get_viewport().gui_get_focus_owner() == null or not get_viewport().gui_get_focus_owner() is LineEdit):
		var movement = Vector2.ZERO
		var arrows_pan := get_viewport().gui_get_focus_owner() == null and not Input.is_physical_key_pressed(KEY_SHIFT)
		if Input.is_physical_key_pressed(KEY_A) or (arrows_pan and Input.is_physical_key_pressed(KEY_LEFT)): movement.x += 1
		if Input.is_physical_key_pressed(KEY_D) or (arrows_pan and Input.is_physical_key_pressed(KEY_RIGHT)): movement.x -= 1
		if Input.is_physical_key_pressed(KEY_W) or (arrows_pan and Input.is_physical_key_pressed(KEY_UP)): movement.y += 1
		if Input.is_physical_key_pressed(KEY_S) or (arrows_pan and Input.is_physical_key_pressed(KEY_DOWN)): movement.y -= 1
		if movement != Vector2.ZERO:
			_manual_camera()
			camera_pan += movement * delta * 250.0
	_advance_scroll(delta)
	_advance_follow(delta)
	if guide_camera_active and camera_input_enabled and follow_actor_id.is_empty():
		var blend = 1.0 - exp(-7.0 * delta)
		zoom = lerpf(zoom, guide_zoom, blend)
		camera_pan += (camera_extent() * Vector2(0.5, 0.57) - screen_point(guide_target)) * blend
	_advance_feature(delta)
	if accessibility_revision != sim.revision:
		accessibility_cache.clear()
		street.use_layout(sim.layout)
		if sim.phase == "NIGHT":
			navigation = Grid.solid_cells(sim.layout)
			walkable_cells = Grid.walkable_region(sim.layout, navigation)
			preview_positions = Grid.staff_positions(sim.layout, sim.attributes, walkable_cells)
			for f in sim.layout.facilities:
				if Grid.placed(f): accessibility_cache[f.id] = not Grid.interaction_accessible(f, walkable_cells)
		accessibility_revision = sim.revision
	_advance_scene_time(delta)
	_advance_weather(delta)
	if district_3d != null:
		district_3d.sync_layout(sim.layout, street, pressed_entity if drag_active else "")
		var closed: bool = inspect_roof and not feature_active
		if closed and overview_mix < .03:
			var ease := 1.0-exp(-9.0*delta)
			zoom = lerpf(zoom,minf(zoom,_roof_zoom_limit()),ease)
			var center := home_bounds.get_center() - Vector2(1.4,.35)
			var envelope := home_bounds.grow(1.8).merge(district_3d.house_bounds)
			var desired := (center-envelope.get_center()) * _home_unit() + Vector2(0,size.y*.025)
			camera_pan = camera_pan.lerp(desired,ease)
		var automatic := smoothstep(.12,.48,overview_mix)
		if entering_canyon: roof_blend = 1. if threshold_approach else maxf(automatic,smoothstep(.12,.66,threshold_mix))
		else: roof_blend = move_toward(roof_blend,1. if closed else automatic,delta*2.7)
		district_3d.show_exterior(roof_blend,sim.layout.unlocked_plots.size())
		district_3d.advance_construction(delta if sim.phase == "NIGHT" else district_3d.BUILD_SECONDS)
		district_3d.frame(_origin(), _unit())
		_update_traffic_door(delta)
		district_3d.open_door(threshold_aperture if entering_canyon else maxf(1.-roof_blend,traffic_aperture))
		if entering_canyon: district_3d.frame_door(threshold_mix,threshold_cross)
		district_3d.set_day(sim.day)
		district_3d.advance_outdoors(delta,render_motion_paused or (sim.phase == "DAY" and sim.paused))
		district_3d.sync_atmosphere(street, weather, _scene_hour(), migration_today, render_motion_paused)
	_sync_trophy_placement()
	_update_lighting()
	lanterns.visible = district_3d == null and overview_mix < .50 and roof_blend < .50
	lanterns.queue_redraw()
	street.advance(delta, sim.paused)
	street_activity.queue_redraw()
	_sync_plot_buttons()
	signs.visible = overview and overview_mix > .94 and camera_input_enabled
	if signs.visible: signs.project(_origin(),_unit())
	_sync_actors()
	for id in pending_complaints:
		var c = sim.active_customers.get(id, {})
		var actor_id = "g_%d" % id
		if c.is_empty() or not actors.has(actor_id): continue
		var size = int(c.party_size)
		say(actor_id, tr("%d 人组") % size, tr("没有%s？我们换一家吧。") % tr(Grid.table_label(size)), 2.1, false, Color("b46c56"))
	pending_complaints.clear()
	chatter.advance(self, delta, not camera_input_enabled or (is_instance_valid(guide_voice) and not guide_voice.is_queued_for_deletion()))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if sim == null or entering_canyon or not camera_input_enabled: return
	if event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
		accept_event()
		return
	if event is InputEventPanGesture:
		_wheel_zoom(event.position, exp(-clampf(event.delta.y,-8,8) * .085))
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var steps := clampf(absf(event.factor), .02, 5.0)
		_wheel_zoom(event.position, pow(1.16, steps if event.button_index == MOUSE_BUTTON_WHEEL_UP else -steps))
		accept_event()
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_drag_touch(event)
		accept_event()
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
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
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_primary_pointer(event.position, event.pressed)

func _primary_pointer(point: Vector2, pressed: bool) -> void:
	if overview_mix > .65 or inspect_roof:
		if pressed and district_3d != null and district_3d.house_bounds.has_point((point-_origin())/_unit()):
			visit_threshold()
		return
	var cell = cell_at(point)
	hovered = cell
	if sim.phase == "NIGHT" and placing_wall:
		if pressed:
			cancel_drag()
			if camera_input_enabled: wall_anchor = cell
		elif wall_anchor != null:
			var stroke = _wall_row_to(cell)
			wall_anchor = null
			wall_brush_rotation = int(stroke.turns)
			if camera_input_enabled: wall_requested.emit(stroke.cells, wall_brush_rotation)
		return
	if pressed:
		cancel_drag()
		if not camera_input_enabled: return
		if sim.phase == "NIGHT" and editing and not selected_id.is_empty():
			move_requested.emit(selected_id, cell)
			return
		press_position = point
		var facility = Grid.facility_at(sim.layout, cell)
		var actor_id = _actor_at(point)
		var id = actor_id
		if not facility.is_empty() and (actor_id.is_empty() or sim.phase == "NIGHT"):
			id = str(facility.id)
		if _trophy_shop_hit(point): id = "trophy_shop"
		if sim.phase == "NIGHT":
			pressed_entity = id
			if not id.is_empty() and feature_motion != null and feature_motion.is_running():
				feature_motion.pause()
			if not facility.is_empty(): grab_offset = cell - Grid.footprint(facility).position
		else:
			_inspect_entity(id)
	elif not pressed_entity.is_empty():
		var id = pressed_entity
		var moved = point.distance_to(press_position) > 7
		var drop = _drop_cell(id, cell)
		var was_dragging = drag_active
		cancel_drag()
		if not camera_input_enabled or sim.phase != "NIGHT": return
		if was_dragging and moved: move_requested.emit(id, drop)
		elif not moved: _inspect_entity(id)
		_update_cursor(point)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.canceled:
		cancel_touch()
		return
	if not camera_input_enabled: return
	if event.pressed:
		touches[event.index] = event.position
		if touches.size() == 1:
			touch_origin = event.position
			touch_panning = false
			touch_multitouch = false
			hovered = cell_at(event.position)
			touch_primary_started = sim.phase == "NIGHT" and (placing_wall or not editing)
			if touch_primary_started: _primary_pointer(event.position, true)
		else:
			touch_multitouch = true
			cancel_drag()
		return
	if not touches.erase(event.index) or not touches.is_empty(): return
	if not touch_multitouch and not touch_panning:
		if not touch_primary_started and event.position.distance_to(touch_origin) <= 9:
			_primary_pointer(event.position, true)
		_primary_pointer(event.position, false)
	else:
		cancel_drag()
	touch_primary_started = false

func _drag_touch(event: InputEventScreenDrag) -> void:
	if not camera_input_enabled or not touches.has(event.index): return
	var previous: Vector2 = touches[event.index]
	touches[event.index] = event.position
	if touch_multitouch:
		var fingers := touches.keys()
		if fingers.size() != 2: return
		var other: Vector2 = touches[fingers[1] if fingers[0] == event.index else fingers[0]]
		var before := (previous + other) * .5
		var after := (event.position + other) * .5
		var factor := event.position.distance_to(other) / maxf(1, previous.distance_to(other))
		zoom_at(before, factor)
		pan_camera(after - before)
		return
	if not placing_wall and not drag_active and event.position.distance_to(touch_origin) > 9:
		if not touch_panning: cancel_drag()
		touch_panning = true
	if touch_panning:
		pan_camera(event.position - previous)
	else:
		hovered = cell_at(event.position)

func cancel_touch() -> void:
	if not touches.is_empty(): cancel_drag()
	touches.clear()
	touch_panning = false
	touch_multitouch = false
	touch_primary_started = false

func cancel_drag() -> void:
	if not pressed_entity.is_empty() and feature_motion != null and feature_motion.is_valid() and not feature_motion.is_running():
		feature_motion.play()
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
		if not actor.visible or actor.modulate.a < .15: continue
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
	var width = font.get_string_size(tr("奖杯商店"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
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
	if not entity.get("turns_this_tick",[]).is_empty():
		var traversed: Array=[entity.previous_pos]
		traversed.append_array(entity.turns_this_tick)
		traversed.append(entity.pos)
		return Plan.route(traversed,fraction)
	return Vector2(entity.previous_pos).lerp(entity.pos, fraction)

func _street_approach_progress(arrival_tick: int, visual_tick: float) -> float:
	var lead := maxf(1.,street.approach_seconds(float(sim.chapter.movement.guest_speed))*1000./sim.tick_ms)
	return clampf(1.-(arrival_tick-visual_tick)/lead,0,1)

# Simulation ownership stays on the logical cell. Display bodies in the free
# portion of that cell at shared counters, keeping a small disc off furniture.
func _floor_room(at: Vector2,radius: float) -> bool:
	for dx in [-radius,radius]:
		for dy in [-radius,radius]:
			if street.solids.has(Vector2i((at+Vector2(dx,dy)).round())): return false
	return true

func _space_staff(actor,cell: Vector2) -> Vector2:
	var key:=Vector2i(cell.floor())
	var near: Array=[]
	for x in range(-1,2):
		for y in range(-1,2): near.append_array(nearby_feet.get(key+Vector2i(x,y),[]))
	var old: Vector2=actor.get_meta("spacing",Vector2.ZERO)
	var best:=cell
	var metric:=-INF
	var offsets: Array[Vector2]=[Vector2.ZERO,old]
	if not near.is_empty():
		for offset: Vector2 in [Vector2(.27,0),Vector2(-.27,0),Vector2(0,.26),Vector2(0,-.26),Vector2(.27,.26),Vector2(-.27,.26),Vector2(.27,-.26),Vector2(-.27,-.26)]:
			offsets.append(offset)
	for offset in offsets:
		var p:=cell+offset
		if not _floor_room(p,.17):continue
		var clearance:=.48
		for other: Vector2 in near:clearance=minf(clearance,((p-other)*Vector2(1.,Plan.DEPTH)).length())
		var score:=clearance-.065*old.distance_to(offset)-.035*offset.length()
		if score>metric:
			metric=score
			best=p
	var chosen:=best-cell
	# Ease lateral corrections; a stop in simulation time holds the pose.
	var stamp:=float(sim.tick)+_render_fraction()
	var dt: float=clampf(stamp-float(actor.get_meta("spacing_tick",stamp)),0.,3.)*sim.tick_ms/1000.
	chosen=old.move_toward(chosen,dt*2.5)
	if not _floor_room(cell+chosen,.17): chosen=best-cell
	actor.set_meta("spacing",chosen)
	actor.set_meta("spacing_tick",stamp)
	best=cell+chosen
	key=Vector2i(best.floor())
	if not nearby_feet.has(key):nearby_feet[key]=[]
	nearby_feet[key].append(best)
	return best

func _place_actor(id: String, actor, cell: Vector2, origin: Vector2, unit: float) -> void:
	actor_cells[id] = cell
	var visual:=cell
	if district_3d!=null and sim.phase=="DAY" and Grid.has_room(sim.layout,Vector2i(cell.round())):
		visual=_space_staff(actor,cell)
	var projected := screen_point(visual) if threshold_mix > .001 else origin + (visual + Vector2(.5, .5)) * unit
	actor.place_in_world(visual,projected,unit / 48.0)

func _set_street_actor(id: String, kind: String, cell: Vector2, origin: Vector2, unit: float) -> void:
	var actor = _actor(id, kind)
	_place_actor(id, actor, cell, origin, unit)
	actor.modulate.a = street.threshold_alpha(cell)
	actor.patience_ratio = -1.0
	actor.present("walk", "", -1.0, false, sim.guest_defs[kind].name if sim.guest_defs[kind].rarity == "special" else "")

func _sync_approaching_street(live: Dictionary, origin: Vector2, unit: float, visual_tick: float) -> void:
	if sim.phase == "DAY":
		var lead_ticks = ceili(street.approach_seconds(float(sim.chapter.movement.guest_speed))*1000.0 / sim.tick_ms)
		for index in range(sim.arrival_cursor, sim.arrival_plan.size()):
			var plan = sim.arrival_plan[index]
			var arrival_tick = int(plan.tick)
			if arrival_tick > sim.tick + lead_ticks: break
			var id = int(plan.id)
			if sim.customers.has(id) or street_arrivals.has(id): continue
			var place = Grid.vec(sim.layout.entrance)
			var member = id - int(plan.get("party_id", id))
			place.y += .20 + .21 * (member % 2)
			street_arrivals[id] = {"tick": arrival_tick, "type": plan.type, "target": place, "stagger":maxi(0,member)*.76}
	for id in street_arrivals.keys():
		var visit = street_arrivals[id]
		if sim.customers.has(id):
			street_arrivals.erase(id)
			continue
		var age = (visual_tick - int(visit.tick)) * sim.tick_ms / 1000.0
		if sim.phase != "DAY" or age >= STREET_APPROACH_SECONDS:
			street_arrivals.erase(id)
			continue
		var distance: float=street.inlet.length*_street_approach_progress(int(visit.tick),visual_tick)-float(visit.stagger)
		var cell = street.gate_route(distance/street.inlet.length,visit.target)
		if age >= 0.0:
			cell=street.exit_route(clampf(age/STREET_APPROACH_SECONDS,0,1),visit.target)
		var key = "g_%d" % id
		live[key] = true
		_set_street_actor(key, visit.type, cell, origin, unit)

var current_sprite
const CURRENT_TEXTURE = preload("res://assets/canyon/current.webp")

func _sync_current(unit: float) -> void:
	if current_sprite == null:
		if district_3d != null: current_sprite = district_3d.current_decal
		else:
			current_sprite = Sprite2D.new()
			current_sprite.texture = CURRENT_TEXTURE
			current_sprite.hframes = 4
			current_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			current_sprite.z_index = 1
			add_child(current_sprite)
	current_sprite.visible = sim.phase == "DAY" and sim.tick < sim.current_until
	if current_sprite.visible:
		if current_sprite is Sprite3D:
			current_sprite.position = Vector3(sim.current_cell.x+.5,.09,(sim.current_cell.y+.5)*District3D.DEPTH)
		else:
			current_sprite.position = screen_point(sim.current_cell)
			current_sprite.scale = Vector2.ONE * unit * 1.7 / 128.
		current_sprite.frame = floori(sim.tick * sim.tick_ms / 135.0) % 4

func _queue_display(id: String, actor, rank: int, visual_tick: float) -> Vector2:
	var target:=maxf(0.,street.inlet.length-1.05-rank*.84)
	if not queue_motion.has(id):
		var distance: float=street.inlet.distance_of(actor.world_cell) if actor.world_cell.is_finite() else target
		queue_motion[id]={"distance":distance,"tick":visual_tick}
	var entry: Dictionary=queue_motion[id]
	var dt: float=maxf(0.,visual_tick-float(entry.tick))*sim.tick_ms/1000.
	entry.distance=move_toward(entry.distance,target,dt*float(sim.chapter.movement.guest_speed))
	entry.tick=visual_tick
	return street.inlet.sample(entry.distance)

func _walk_from_queue(id: String,c: Dictionary,actual: Vector2,visual_tick: float) -> Vector2:
	var entry: Dictionary=queue_motion[id]
	if not entry.has("path"):
		var seat:=Vector2(sim.seat_cells.get(c.seat_key,actual.round()))
		entry.path=street.from_queue(float(entry.distance),seat)
		entry.distance=0.
	var dt: float=maxf(0.,visual_tick-float(entry.tick))*sim.tick_ms/1000.
	entry.tick=visual_tick
	entry.distance=minf(entry.path.length,entry.distance+dt*float(sim.chapter.movement.guest_speed)*1.12)
	var end: float=entry.path.distance_of(actual)
	if entry.distance>=end-.01:
		queue_motion.erase(id)
		return actual
	return entry.path.sample(entry.distance)

func _sync_actors() -> void:
	if street.inlet==null:
		_sync_neighbor_occluders()
		street.use_layout(sim.layout)
	var live = {}
	actor_cells.clear()
	nearby_feet.clear()
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
				var profile_id: String = sim.crew_at(role,i)
				var actor = _actor(id, sim.staff_skin(role,i))
				var cell = hovered if drag_active and id == pressed_entity else positions[role][i]
				_place_actor(id, actor, Vector2(cell), origin, unit)
				actor.present("wave" if id == greeting_actor else "idle", "阿禾" if id == greeting_actor else ("厨" if role == "chef" else "服"))
				_staff_plate(actor, sim.crew_at(role, i), role, tr("待命"), -1.0, Vector2i(cell) == hovered)
	else:
		for s in sim.staff:
			var id = "s_%d" % s.id
			live[id] = true
			var profile_id := str(s.get("crew_id",""))
			var actor = _actor(id, "minion_"+str(s.get("minion","melee")) if profile_id.is_empty() else profile_id)
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
			var status := _staff_activity(s)
			var attention: bool = Vector2i(Vector2(s.pos).round()) == hovered or id == follow_actor_id or bool(s.task.get("linked", false))
			_staff_plate(actor, str(s.get("crew_id","")), str(s.role), status, progress, attention)
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
				displayed = _queue_display(id,actor,queue_index,visual_tick)
				if party!=0: party_places[party]=true
				queue_index += 1
			elif phase == "EXITING" and not c.path.is_empty():
				var departure = Vector2(c.path[0]) + Vector2(4.5, 0)
				displayed = street.exit_route((departure.x - displayed.x) / 4.5, departure)
			elif phase == "AT_EXIT":
				displayed += sim.party_offset(c)
			elif phase == "SEATING":
				displayed += sim.party_offset(c) * clampf(1.0 - c.pos.distance_to(Grid.vec(sim.layout.entrance)) / 2.5, 0.0, 1.0)
			var joining: bool = phase in ["SEATING","CHOOSING","READY","TAKING","FOOD","EATING"] and queue_motion.has(id)
			if joining: displayed=_walk_from_queue(id,c,displayed,visual_tick)
			var entering = phase in ["SEATING", "CHOOSING", "APPROACHING"] and not joining
			var approach = _street_approach_progress(int(c.arrival_tick), visual_tick) if entering else 1.0
			if approach < 1.0:
				displayed = street.gate_route(approach, displayed)
			_place_actor(id, actor, displayed, origin, unit)
			actor.modulate.a = street.threshold_alpha(displayed)
			var action = "idle"
			var label = ""
			var progress = -1.0
			if joining or (phase=="QUEUE" and actor.gait.last.is_finite() and actor.gait.heading.length_squared()>.1) or approach < 1.0 or c.state in ["SEATING", "LEAVING", "EXITING", "APPROACHING"]: action = "walk"
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
			var guest: Dictionary = sim.guest_defs[c.type]
			var attention: bool = Vector2i(Vector2(displayed).round()) == hovered or id == follow_actor_id or guest.rarity == "special" or (actor.patience_ratio >= 0 and actor.patience_ratio < .22)
			if not sim.crew_lineup.is_empty() and attention:
				var meter: float = actor.patience_ratio if c.state == "FOOD" else progress
				actor.set_overhead(tr(str(guest.name)), tr("客人"), tr(label), meter, Style.RED if meter >= 0 and meter < .22 else Style.MUTED)
			else:
				actor.set_overhead("", "", "", -1, Style.MUTED)
	var minute = _scene_hour() * 60.0
	var frozen = sim.phase == "DAY" and (sim.paused or (sampled_tick == sim.tick and render_motion_paused))
	for id in actors.keys():
		var actor = actors[id]
		if not live.has(id):
			queue_motion.erase(id)
			if district_3d != null: district_3d.remove_actor(id)
			actor.queue_free()
			actors.erase(id)
			continue
		actor.set_sunlight(minute)
		actor.sprite.speed_scale = 0.0 if frozen else 1.0
		if district_3d != null:
			var cell: Vector2 = actor_cells[id]
			actor.visible = not entering_canyon and overview_mix < .13 and roof_blend < .65
			var hero_inside: bool = actor.specialty_staff and roof_blend < .65 and Grid.has_room(sim.layout, Vector2i(cell.round()))
			district_3d.sync_actor(id, actor, actor.world_cell, hero_inside)

func _staff_plate(actor, profile_id: String, role: String, state: String, progress: float, attention: bool) -> void:
	actor.specialty_staff = not profile_id.is_empty()
	var profile: Dictionary = Crew.PROFILES.get(profile_id, {})
	var helper := str(actor.visual_key).trim_prefix("minion_")
	var caption := tr(str(profile.get("name",sim.Minions.NAMES.get(helper,"小兵"))))
	if attention and not str(profile.get("title","")).is_empty(): caption += " · " + tr(profile.title)
	var job := tr("厨师") if role == "chef" else tr("服务员")
	var expanded: bool = zoom >= 1.40 or attention
	actor.set_overhead(caption if expanded or not profile.is_empty() else job, job if expanded else "", state if expanded or progress >= 0 else "", progress, Style.GOLD if role == "chef" else Style.GREEN)

func _staff_activity(person: Dictionary) -> String:
	var task: Dictionary = person.task
	if task.is_empty(): return tr("受阻") if str(person.reason).begins_with("等待") else tr("待命")
	if task.get("linked", false): return tr("连灶飞火")
	if person.role == "waiter" and sim.tick < int(person.get("haste_until", 0)): return tr("河道急送")
	if task.stage == "PREP": return tr("备锅")
	if task.kind == "COOK": return tr("移动") if task.stage == "MOVE" else tr("正在烹饪")
	match task.kind:
		"ORDER": return tr("点单")
		"COLLECT", "PICKUP": return tr("取餐")
		"TRANSFER", "DELIVER": return tr("给客人上菜")
		"SUBMIT": return tr("送订单到厨房")
	return tr("移动")

func _paint_street() -> void:
	street_canvas.draw_set_transform(-street_draw_bounds.position)
	street.paint_scenery(street_canvas, maxf(0.0, scene_light_band / 8.0))

func _paint_street_activity() -> void:
	if sim == null: return
	street.paint_activity(street_activity, _origin(), _unit(), street_lamp_light, district_3d == null)

func _paint_street_signs() -> void:
	if sim != null and font != null:
		street.paint_signs(street_signs, _origin(), _unit(), font)

func _paint_floor() -> void:
	if sim == null: return
	var unit = FLOOR_DRAW_UNIT
	var origin = Vector2.ZERO
	var l = sim.layout
	var kitchen = Grid.kitchen_bounds(l)
	for y in range(int(l.height)):
		for x in range(int(l.width)):
			if not Grid.has_room(l, Vector2i(x,y)): continue
			var rect = Rect2(origin + Vector2(x, y) * unit, Vector2.ONE * unit)
			var base_color = Color("e1bf94").lerp(Color("efd5ac"), float((x * 5 + y * 3) % 7) / 7.0)
			if x >= int(kitchen.left) and x <= int(kitchen.right) and y >= int(kitchen.top) and y <= int(kitchen.bottom):
				base_color = Color("bcd7c9") if (x+y)%2==0 else Color("c4dfd2")
			elif x > int(kitchen.right) and y >= 1 and y <= int(kitchen.bottom):
				base_color = Color("cadabb") if (x+y)%2==0 else Color("bfd2b8")
			var wall := Grid.structural_blocked(l, Vector2i(x,y))
			if wall: base_color = Color("74978b")
			floor_canvas.draw_rect(rect,base_color)
			if wall:
				floor_canvas.draw_rect(Rect2(rect.position+Vector2(5,5),rect.size-Vector2(10,10)),Color("a9c5b7"))
				floor_canvas.draw_line(rect.position+Vector2(6,unit*.3),rect.position+Vector2(unit-6,unit*.3),Color("e0e9d7"),2)
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
	if sim == null or font == null or entering_canyon or overview_mix > .18 or roof_blend > .65: return
	var unit = _unit()
	var origin = _origin()
	var l = sim.layout
	var kitchen = Grid.kitchen_bounds(l)
	var next_plot = str(sim.next_land_plot().get("id", "")) if sim.phase == "NIGHT" else ""
	if district_3d == null: _draw_window_light(origin, unit, l)
	var zone = sim.chapter.trophy_zone
	if sim.trophy_shop_unlocked() and (district_3d == null or float(district_3d.construction.get("trophy_gallery", 2.0)) >= 1.1):
		_draw_unlocked_trophy_zone(origin,unit,zone)
		if not trophy_placement_id.is_empty(): _draw_trophy_placement(origin, unit, zone)
		_draw_trophy_shop(unit)
	_draw_locked_plots(origin,unit,l,next_plot)
	if district_3d == null: _draw_frontage(origin, unit, l)
	draw_rect(Rect2(origin + Vector2(kitchen.left,kitchen.top) * unit, Vector2(int(kitchen.right)-int(kitchen.left)+1,int(kitchen.bottom)-int(kitchen.top)+1) * unit), Color(0.24,0.36,0.27,0.24), false, 2)
	if sim.phase == "NIGHT" and camera_input_enabled and not selected_id.is_empty():
		_draw_work_routes()
	_draw_linked_fire()
	for f in l.facilities:
		if not Grid.placed(f) or f.type == "trophy_shop" or (drag_active and f.id == pressed_entity): continue
		if district_3d == null:
			_draw_facility(f)
		elif district_3d.furniture_revealed(str(f.id)) and (f.type not in ["wall", "table"] or f.id == selected_id or Grid.footprint(f).has_point(hovered)):
			var center := screen_point(Grid.vec(f.pos))
			_draw_facility_label(f, center, center.y - unit * .52, f.id == selected_id or Grid.footprint(f).has_point(hovered))
	var moving_staff = selected_id.begins_with("preview_")
	if sim.phase == "NIGHT" and moving_staff and actors.has(selected_id):
		draw_circle(actors[selected_id].position, unit * .37, Color("ffe19a"), false, 2.0, true)
	if sim.phase == "NIGHT" and not pressed_entity.is_empty() and not drag_active:
		var fraction = clampf(press_elapsed / HOLD_TO_DRAG, 0.0, 1.0)
		if fraction > 0.12:
			draw_arc(press_position, unit * .55, -PI * .5, -PI * .5 + TAU * fraction, 20, Style.GOLD, 2.2, true)
	if sim.phase == "NIGHT" and (editing or drag_active) and not selected_id.is_empty():
		var f = Grid.find(l, selected_id)
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

func _draw_work_routes() -> void:
	var targeting: bool = editing or drag_active
	var key := [sim.revision, selected_id, hovered if targeting else Vector2i(-1, -1), targeting]
	if route_preview_key != key:
		route_preview_key = key
		route_preview = _preview_routes(targeting)
	var elapsed := fposmod(Time.get_ticks_msec() * .024, 16.0)
	for i in range(route_preview.size()):
		var route: Array = route_preview[i]
		var tint := Color("e3af68") if i == 0 else Color("92e0ca")
		for n in range(1, route.size()):
			var start := screen_point(Vector2(route[n-1]))
			var end := screen_point(Vector2(route[n]))
			var length := start.distance_to(end)
			if length < .2: continue
			var direction := start.direction_to(end)
			draw_line(start, end, Color("142723", .72), 5.0, true)
			var dash := elapsed - 16.0
			while dash < length:
				var from := clampf(dash, 0, length)
				var to := clampf(dash + 8.0, 0, length)
				if to > from: draw_line(start + direction * from, start + direction * to, tint, 2.5, true)
				dash += 16.0

func _preview_routes(targeting: bool) -> Array:
	var layout: Dictionary = sim.layout.duplicate(true) if targeting else sim.layout
	var selected := Grid.find(layout, selected_id)
	if selected.is_empty() and selected_id.begins_with("preview_") and targeting:
		var staff_target := "pass" if selected_id.begins_with("preview_chef") else "order"
		var obstacles := Grid.solid_cells(layout)
		return [_path_to(Vector2(hovered), Grid.find(layout, staff_target), layout, obstacles)]
	if selected.is_empty() or selected.type not in ["table", "stove", "order", "pass"]: return []
	if targeting:
		var landing: Vector2i = _drop_cell(selected_id, hovered) if drag_active else hovered
		var moving := selected.duplicate()
		moving.pos = [landing.x, landing.y]
		for cell in Grid.footprint_cells(moving):
			var occupying := Grid.facility_at(layout, cell)
			if Grid.structural_blocked(layout, cell) or (not occupying.is_empty() and occupying.id != selected_id): return []
		selected.pos = [landing.x, landing.y]
	var steps := Grid.solid_cells(layout)
	var order := Grid.find(layout, "order")
	var pickup := Grid.find(layout, "pass")
	var tables := Grid.facilities(layout, "table")
	var stoves := Grid.facilities(layout, "stove")
	var first_table: Dictionary = tables[0] if not tables.is_empty() else {}
	var first_stove: Dictionary = stoves[0] if not stoves.is_empty() else {}
	match selected.type:
		"table": return [_between(selected, order, layout, steps), _between(pickup, selected, layout, steps)]
		"order": return [_between(first_table, selected, layout, steps)]
		"stove": return [_between(selected, pickup, layout, steps)]
		"pass": return [_between(first_stove, selected, layout, steps), _between(selected, first_table, layout, steps)]
	return []

func _between(source: Dictionary, target: Dictionary, layout: Dictionary, obstacles: Dictionary) -> Array:
	if source.is_empty(): return []
	for approach in Grid.interaction_cells(source):
		var path := _path_to(Vector2(approach), target, layout, obstacles)
		if not path.is_empty(): return path
	return []

func _path_to(source: Vector2, target: Dictionary, layout: Dictionary, obstacles: Dictionary) -> Array:
	if target.is_empty(): return []
	var path: Array = Grid.approach_cells(layout, source, Grid.interaction_cells(target), obstacles).get("path", [])
	if not path.is_empty(): path.push_front(source)
	return path

func _draw_linked_fire() -> void:
	if sim.phase != "DAY" or sim.tick >= sim.linked_fire_until or sim.linked_fire_stoves.is_empty(): return
	var duration := maxf(1, .80 * 1000.0 / sim.tick_ms)
	var fraction := clampf(1.0 - float(sim.linked_fire_until - sim.tick) / duration, 0, 1)
	var origin := screen_point(Vector2(sim.linked_fire_origin)) - Vector2(0, _unit() * .53)
	var hops: Array[Vector2] = [origin]
	for pot in sim.linked_fire_stoves:
		hops.append(screen_point(Vector2(pot)) - Vector2(0, _unit() * .38))
		hops.append(origin)
	var position_along := fraction * (hops.size() - 1)
	var segment := mini(floori(position_along), hops.size() - 2)
	var along := clampf(position_along - segment, 0, 1)
	var spark := hops[segment].lerp(hops[segment + 1], along) - Vector2(0, sin(along * PI) * _unit() * .64)
	draw_line(hops[segment], spark, Color("df6b38", .49 * (1.0 - fraction)), 6.0, true)
	draw_texture_rect(EMBER, Rect2(spark - Vector2(22,22), Vector2(44,44)), false, Color(1,.77,.47,.86))

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
	draw_string(font, sign.position + Vector2(4, font_size), tr("奖杯商店"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("ffe4b4"))

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
	var text = tr("奖杯展示区 · 亮格可放") if not trophy_cells.is_empty() else tr("奖杯展示区 · 暂无空位")
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var caption = Rect2(area.get_center().x - width * .5 - 7, area.position.y - 26, width + 14, 23)
	draw_rect(caption, Color("183d36"))
	draw_rect(caption, Color("90c5b1"), false, 1)
	draw_string(font, caption.position + Vector2(7, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e1ffee"))

func _draw_unlocked_trophy_zone(origin: Vector2, unit: float, zone: Dictionary) -> void:
	var display_area = Rect2(origin+Vector2(float(zone.left),float(zone.top))*unit,Vector2(float(int(zone.right)-int(zone.left)+1),float(int(zone.bottom)-int(zone.top)+1))*unit)
	draw_rect(display_area,Color("7b668c",.15))
	draw_rect(display_area,Color("d5af73",.8),false,2)

func _draw_locked_plots(origin: Vector2, unit: float, layout: Dictionary, next_plot: String) -> void:
	if not plot_buttons.has(next_plot): return
	var button: Button = plot_buttons[next_plot].button
	if not button.visible or not (button.is_hovered() or button.has_focus()): return
	for plot in layout.plots:
		if str(plot.id) != next_plot: continue
		var b: Dictionary = plot.bounds
		var start := origin + Vector2(b.left, b.top) * unit
		var area := Rect2(start, Vector2(b.right - b.left + 1, b.bottom - b.top + 1) * unit)
		draw_rect(area, Color("e0bc80", .07))
		draw_rect(area, Color("e0bc80", .60), false, maxf(1, unit * .042))
		return

func _draw_frontage(origin: Vector2, unit: float, l: Dictionary) -> void:
	var door_y = float(l.entrance[1])
	var entrance = origin + Vector2(0,door_y)*unit
	if district_3d == null:
		# The headless canvas keeps the same projected gate cells.
		draw_rect(Rect2(entrance+Vector2(-unit*.23,-unit*.41),Vector2(unit*1.42,unit*.39)),Color("374f4a"))
		draw_rect(Rect2(entrance+Vector2(-unit*.24,-unit*.52),Vector2(unit*1.45,unit*.16)),Color("c58b54"))
	var title = tr(str(sim.chapter.title))
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
	var caption := Style.facility_name(str(f.name))
	var width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_origin = Vector2(roundf(center.x - (width + 8) * .5), roundf(top - font_size - 11))
	draw_rect(Rect2(label_origin, Vector2(width + 8, font_size + 8)), Color(0.11, 0.19, 0.15, 0.86))
	draw_string(font, label_origin + Vector2(4, font_size + 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Style.INK)
