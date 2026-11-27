extends Control
const District = preload("res://scripts/visuals/district_3d.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
signal selected(place: String)
signal door_tapped
signal at_door
signal door_crossed
signal march_ended
var march
var marching := false
var march_camera := 0.
var reveal_started := false
var reveal_finished := false
var arrived_overhead := false
var door_mix := 0.
var aperture := 0.
var crossing := 0.
var movement: Tween
var door_preview := false
var fingers := {}
var touch_start := Vector2.ZERO
var was_pinch := false
var model
var weather
var street := preload("res://scripts/visuals/canyon_paths.gd").new()
var preview_hour := 22.
var migration := false
var preview_staff := {}
var staff_cells := {}
var overview_mix := 1.0
var target_mix := 1.0
var _preview_layout := {}
var building := Rect2(1,1,12,14)
var active := true


func _ready() -> void:
	# An exported instance can inherit zero-sized root offsets from its packed scene.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if DisplayServer.get_name() != "headless":
		model = District.new()
		add_child(model)
		move_child(model,0)
		model.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		model.show_exterior(1,0)
		model.light_at(9,0,0,1)
	$Places.landmark_pressed.connect(selected.emit)
	resized.connect(fit)
	fit()

func show_layout(layout: Dictionary) -> void:
	_preview_layout = layout
	building = Rect2(Grid.occupied_bounds(layout))
	if model != null:
		model.sync_layout(layout, null, "")
		fit()

func preview_workers(sim) -> void:
	if model == null: return
	if weather == null:
		_adopt_weather(preload("res://scripts/visuals/restaurant_weather.gd").new())
	street.configure(Vector2i(sim.layout.width,sim.layout.height),float(sim.layout.entrance[1]))
	weather.configure(street,int(sim.seed_value))
	weather.set_preset(sim.weather_for().preset)
	preview_hour = 24. if sim.phase == "REPORT" else 22.
	migration = sim.events_for().any(func(event): return event.id == "river_lantern_run")
	var positions := Grid.staff_positions(sim.layout,sim.attributes)
	var current := {}
	for role in positions:
		for i in range(positions[role].size()):
			var id := "preview_%s_%d" % [role,i]
			current[id] = true
			var staff = preview_staff.get(id)
			if staff == null:
				staff = preload("res://scripts/visuals/actor_view.gd").new()
				add_child(staff)
				staff.hide()
				preview_staff[id] = staff
			staff.set_visual(sim.staff_skin(role,i))
			staff.present("idle")
			staff_cells[id] = Vector2(positions[role][i])
	for id in preview_staff.keys():
		if current.has(id): continue
		preview_staff[id].queue_free()
		preview_staff.erase(id)
		staff_cells.erase(id)
		model.remove_actor(id)

func _adopt_weather(climate) -> void:
	weather = climate
	weather.use_spatial_rain = true
	add_child(weather.ground)
	add_child(weather)
	weather.ground.hide()
	weather.hide()

func take_atmosphere() -> Dictionary:
	if weather == null: return {}
	var atmosphere := {"weather":weather,"elapsed":street.elapsed}
	remove_child(weather.ground)
	remove_child(weather)
	weather = null
	return atmosphere

func restore_atmosphere(atmosphere: Dictionary) -> void:
	if not atmosphere.is_empty():
		_adopt_weather(atmosphere.weather)
		street.elapsed = atmosphere.elapsed

func attach_stage(stage) -> void:
	model = stage
	add_child(stage)
	move_child(stage,0)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model.show_exterior(1,0)
	fit()

func take_stage():
	var stage = model
	model = null
	if stage != null: remove_child(stage)
	return stage

func take_workers() -> Dictionary:
	var actors := preview_staff
	preview_staff = {}
	staff_cells = {}
	for actor in actors.values(): remove_child(actor)
	return actors

func fit() -> void:
	if not is_node_ready(): return
	var bounds := Plan.bounds()
	var wide := minf(size.x / bounds.size.x, size.y / bounds.size.y)
	var close := minf(size.x / (building.size.x + 12), size.y / (building.size.y + 13))
	var unit := exp(lerpf(log(maxf(1,close)),log(maxf(1,wide)),overview_mix))
	var at := (building.get_center() - Vector2(1.4,.35)).lerp(bounds.get_center(), smoothstep(.12,1,overview_mix))
	var origin := size*.5 - at*unit
	if model != null:
		model.frame(origin,unit)
		model.show_exterior(smoothstep(.12,.66,door_mix) if reveal_started else 1.,0)
		model.open_door(aperture)
		model.frame_door(door_mix,crossing)
		if march_camera>0.: model.frame_procession(march_camera)
	$Places.project(origin,unit)
	for sign in $Places.get_children():
		sign.visible = sign.name == &"tavern" or overview_mix > .68

func _stop_motion() -> void:
	if movement != null: movement.kill()
	fingers.clear()

func approach() -> void:
	_stop_motion()
	active = false
	door_preview = false
	target_mix = overview_mix
	$Places.hide()
	movement = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement.tween_property(self,"door_mix",1.,1.1)
	movement.tween_property(self,"aperture",.64,.45)
	movement.tween_callback(func():
		fit()
		door_preview = true
		at_door.emit()
	)

func preview_open(opened: bool) -> void:
	if not door_preview: return
	_stop_motion()
	movement = create_tween().set_trans(Tween.TRANS_SINE)
	movement.tween_property(self,"aperture",.82 if opened else 0.,.52)
	movement.tween_callback(fit)

func enter(lineup_walk := false) -> void:
	arrived_overhead=false
	reveal_started=false
	reveal_finished=false
	_stop_motion()
	active = false
	door_preview = false
	if lineup_walk and not staff_cells.is_empty():
		# The full-page selection still covers the initial placement at the road.
		march=preload("res://scripts/visuals/crew_arrival.gd").new(model.site_layout if model!=null else _preview_layout,staff_cells)
		marching=true
		for id in preview_staff: preview_staff[id].gait.reset()
		_apply_procession()
		movement=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		movement.tween_property(self,"aperture",1.,.54)
		movement.tween_property(self,"march_camera",1.,.72)
		return
	_cross_threshold()

func _cross_threshold() -> void:
	_stop_motion()
	movement = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement.tween_property(self,"aperture",1.,.50)
	movement.tween_property(self,"march_camera",0.,.64)
	movement.tween_property(self,"crossing",1.,.76).set_delay(.12)
	movement.chain().tween_callback(func():
		fit()
		door_crossed.emit()
	)

func _apply_procession() -> void:
	var occupied := PackedVector2Array()
	for member in march.members:
		staff_cells[member.id]=member.cell
		var worker=preview_staff[member.id]
		worker.present("walk" if member.moving else "idle")
		occupied.append(member.cell)
	if model!=null: model.procession_cells=occupied

func _raise_after_march() -> void:
	if reveal_started:return
	reveal_started=true
	overview_mix=0.
	target_mix=0.
	_stop_motion()
	movement=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement.tween_property(self,"door_mix",0.,1.18)
	movement.tween_property(self,"march_camera",0.,1.18)
	movement.tween_property(self,"aperture",1.,.32)
	movement.chain().tween_callback(func():
		reveal_finished=true
		fit()
	)

func end_procession() -> void:
	if not marching:return
	_stop_motion()
	march.finish()
	_apply_procession()
	door_mix=0.
	overview_mix=0.
	target_mix=0.
	march_camera=0.
	aperture=1.
	reveal_started=true
	reveal_finished=true
	fit()
	_admit_staff()

func _admit_staff() -> void:
	marching=false
	march=null
	arrived_overhead=true
	if model!=null:model.procession_cells.clear()
	march_ended.emit()
	door_crossed.emit()

func back_to_map() -> void:
	reveal_started=false
	reveal_finished=false
	arrived_overhead=false
	_stop_motion()
	door_preview = false
	crossing = 0.
	if door_mix <= 0.:
		active = true
		$Places.show()
		$Places.focus_tavern()
		return
	active = false
	movement = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement.tween_property(self,"aperture",0.,.4)
	movement.tween_property(self,"door_mix",0.,.85)
	movement.tween_property(self,"overview_mix",1.,.85)
	movement.chain().tween_callback(func():
		target_mix = 1.
		active = true
		$Places.show()
		$Places.focus_tavern()
	)

func _zoom_by(factor: float) -> void:
	var bounds := Plan.bounds()
	var wide := minf(size.x/bounds.size.x,size.y/bounds.size.y)
	var close := minf(size.x/(building.size.x+12),size.y/(building.size.y+13))
	if close <= wide or factor <= 0.: return
	var intended := target_mix - log(factor)/log(close/wide)
	if factor > 1. and intended <= .001:
		selected.emit("tavern")
	else: target_mix = clampf(intended,0,1)

func _gui_input(event: InputEvent) -> void:
	if door_preview:
		var tap: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION
		tap = tap or (event is InputEventScreenTouch and not event.pressed)
		if tap and model != null and model.hit_door(event.position):
			door_tapped.emit()
			accept_event()
		return
	if not active: return
	if event is InputEventScreenTouch:
		if event.pressed:
			if fingers.is_empty():
				touch_start = event.position
				was_pinch = false
			else: was_pinch = true
			fingers[event.index] = event.position
		elif fingers.erase(event.index) and fingers.is_empty() and not was_pinch:
			if touch_start.distance_to(event.position) < 13. and _house_hit(event.position):
				selected.emit("tavern")
				accept_event()
		return
	if event is InputEventScreenDrag and fingers.has(event.index):
		var before: Vector2 = fingers[event.index]
		fingers[event.index] = event.position
		if fingers.size() == 2:
			for id in fingers:
				if id != event.index:
					var other: Vector2 = fingers[id]
					_zoom_by(other.distance_to(event.position)/maxf(1.,other.distance_to(before)))
					break
			accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _house_hit(event.position):
			selected.emit("tavern")
			accept_event()
		return
	var factor := 1.0
	if event is InputEventMagnifyGesture: factor = event.factor
	elif event is InputEventPanGesture: factor = exp(-clampf(event.delta.y,-8,8)*.085)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		factor = pow(1.16, clampf(absf(event.factor),.02,5.) * (1. if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.))
	else: return
	_zoom_by(factor)
	accept_event()

func _house_hit(point: Vector2) -> bool:
	if model == null: return false
	var unit: float = size.y / model.camera.size
	var rect := Rect2((model.house_bounds.position-model.ground_view.position)*unit,model.house_bounds.size*unit)
	return rect.has_point(point)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if marching:
		march.advance(delta)
		_apply_procession()
		if march.cleared_door: _raise_after_march()
		if march.complete and reveal_finished:
			_admit_staff()
			return
	if model != null:
		if not active and movement != null and movement.is_running(): fit()
		model.advance_outdoors(delta,false)
		if weather != null:
			weather.advance(delta,false)
			street.advance(delta,false)
			model.sync_atmosphere(street,weather,preview_hour,migration,false)
		for id in preview_staff:
			model.sync_actor(id,preview_staff[id],staff_cells[id],false)
	if not active: return
	if is_equal_approx(target_mix,overview_mix): return
	overview_mix = lerpf(overview_mix,target_mix,1.-exp(-18.*delta))
	if absf(overview_mix-target_mix) < .0005: overview_mix = target_mix
	fit()
