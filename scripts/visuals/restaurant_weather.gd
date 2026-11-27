extends Control

const DROP_FRINGE := 5.0
const RAIN_AUDIO := "res://assets/weather/rain.wav"
const THUNDER_AUDIO := "res://assets/weather/thunder.wav"

var ground := Control.new()
var rain := 0.0
var use_spatial_rain := false
var cloud_cover := 0.0
var flash := 0.0
var lamp_voltage := 1.0
var wetness := 0.0

var preset: Dictionary = {}
var time := 0.0
var wind := 0.0
var hour_dusk := 0.0
var seed_value: int
var bounds := Rect2()
var rain_draw_bounds := Rect2()
var roof := Rect2()
var paved: Array[Rect2] = []
var puddles: Array[Vector3] = []
var cells: Array[PackedFloat32Array] = []
var visible_drops: Array[PackedFloat32Array] = []
var world_view := Rect2()
var cell_grid := Rect2i()
var visible_cells := Rect2i()
var ground_style := Vector3i(-1, -1, -1)
var next_strike := INF
var strike_time := -INF
var rumble_time := INF
var bolt := PackedVector2Array()
var bolt_branch := PackedVector2Array()
var rng := RandomNumberGenerator.new()
var rain_audio := AudioStreamPlayer.new()
var thunder_audio := AudioStreamPlayer.new()

func _ready() -> void:
	ground.draw.connect(_draw_ground)
	rain_audio.name = "RainAmbience"
	thunder_audio.name = "ThunderRumble"
	add_child(rain_audio)
	add_child(thunder_audio)
	# The ambience follows the weather clock without using the game's simulation RNG.
	var loop = load(RAIN_AUDIO)
	if loop is AudioStreamWAV:
		loop = loop.duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
		rain_audio.stream = loop
	var rumble = load(THUNDER_AUDIO)
	if rumble is AudioStreamWAV:
		thunder_audio.stream = rumble

func reset() -> void:
	preset = {}
	rain = 0.0
	wind = 0.0
	cloud_cover = 0.0
	wetness = 0.0
	flash = 0.0
	lamp_voltage = 1.0
	time = 0.0
	next_strike = INF
	strike_time = -INF
	rumble_time = INF
	bounds = Rect2()
	visible_cells = Rect2i()
	ground_style = Vector3i(-1, -1, -1)
	rain_audio.stop()
	thunder_audio.stop()
	ground.queue_redraw()
	queue_redraw()

func configure(street, base_seed: int) -> void:
	var area: Rect2 = street.bounds
	if use_spatial_rain: area = area.intersection(Rect2(Vector2(-18,-12),Vector2(street.dimensions)+Vector2(36,27)))
	if bounds == area and seed_value == base_seed: return
	bounds = area
	rain_draw_bounds = bounds.grow(DROP_FRINGE + 1.0)
	size = rain_draw_bounds.size
	ground.size = bounds.size
	seed_value = base_seed
	roof = Rect2(Vector2.ZERO, Vector2(street.dimensions))
	paved = street.rain_paving()
	visible_cells = Rect2i()
	visible_drops.clear()
	var first = Vector2i(bounds.position.floor())
	var end = Vector2i(bounds.end.ceil())
	cell_grid = Rect2i(first, end - first)
	cells.resize(cell_grid.get_area())
	var surface_rng := RandomNumberGenerator.new()
	surface_rng.seed = hash([seed_value, "precipitation", bounds.size])
	rng.seed = hash([seed_value, "thunder"])
	for y in range(first.y, end.y):
		for x in range(first.x, end.x):
			var cell = Vector2i(x, y)
			var impact = Vector2(cell) + Vector2(surface_rng.randf(), surface_rng.randf())
			var sample := PackedFloat32Array()
			if bounds.has_point(impact) and not roof.has_point(impact):
				sample = PackedFloat32Array([impact.x, impact.y, surface_rng.randf(), surface_rng.randf_range(2.0, 5.0),
					surface_rng.randf_range(.96, 1.94), surface_rng.randf(), surface_rng.randf_range(.26, .59)])
			cells[_cell_index(cell)] = sample
	puddles.clear()
	for surface in paved:
		var center_area = surface.grow(-.52)
		if not center_area.has_area(): continue
		for i in range(ceili(center_area.get_area() * .085)):
			var p = Vector2(surface_rng.randf_range(center_area.position.x, center_area.end.x), surface_rng.randf_range(center_area.position.y, center_area.end.y))
			puddles.append(Vector3(p.x, p.y, surface_rng.randf_range(.19, .55)))
	ground.queue_redraw()
	queue_redraw()

func set_preset(value: Dictionary) -> void:
	var new_thunder = value.has("thunder")
	if new_thunder and not preset.has("thunder"):
		var first = value.thunder.first_delay_seconds
		next_strike = time + rng.randf_range(float(first[0]), float(first[1]))
	elif not new_thunder:
		next_strike = INF
	preset = value

func advance(delta: float, paused: bool) -> void:
	if rain_audio.stream != null and rain_audio.playing: rain_audio.stream_paused = paused
	if thunder_audio.stream != null and thunder_audio.playing: thunder_audio.stream_paused = paused
	if paused: return
	var prior_rain = rain
	var prior_flash = flash
	time += delta
	rain = move_toward(rain, float(preset.get("rain", 0.0)), delta * .31)
	cloud_cover = move_toward(cloud_cover, float(preset.get("cloud", 0.0)), delta * .24)
	wind = move_toward(wind, float(preset.get("wind", 0.0)), delta * .43)
	var wet_target = minf(1.0, rain * 1.45)
	wetness = move_toward(wetness, wet_target, delta * (.13 if wet_target > wetness else .054))
	if time >= next_strike: _strike()
	if time >= rumble_time:
		rumble_time = INF
		if thunder_audio.stream != null:
			thunder_audio.pitch_scale = rng.randf_range(.81, 1.08)
			thunder_audio.volume_db = -11.0
			thunder_audio.play()
	_update_flash()
	if rain_audio.stream != null:
		if rain > .022:
			rain_audio.volume_db = linear_to_db(rain * .34)
			if not rain_audio.playing: rain_audio.play()
		elif rain_audio.playing:
			rain_audio.stop()
	if rain > 0.0 or prior_rain > 0.0 or flash > 0.0 or prior_flash > 0.0: queue_redraw()

func align_to_world(at: Vector2, unit: float, viewport_size: Vector2, dusk: float) -> void:
	position = at + rain_draw_bounds.position * unit
	scale = Vector2.ONE * unit
	ground.position = at + bounds.position * unit
	ground.scale = scale
	world_view = Rect2(-at / unit, viewport_size / unit)
	hour_dusk = dusk
	var style = Vector3i(roundi(wetness * 24.0), roundi(dusk * 8.0) if wetness > 0.0 else 0, roundi(flash * 5.0))
	if style != ground_style:
		ground_style = style
		ground.queue_redraw()
	if rain <= 0.0 and not preset.has("thunder"): return
	var margin = world_view.grow(DROP_FRINGE)
	var first = Vector2i(margin.position.floor())
	var last = Vector2i(margin.end.ceil())
	var visible_area = Rect2i(first, last - first).intersection(cell_grid)
	if visible_area == visible_cells: return
	visible_cells = visible_area
	visible_drops.clear()
	for y in range(visible_area.position.y, visible_area.end.y):
		for x in range(visible_area.position.x, visible_area.end.x):
			var drop = cells[_cell_index(Vector2i(x, y))]
			if not drop.is_empty(): visible_drops.append(drop)
	queue_redraw()

func _cell_index(cell: Vector2i) -> int:
	var local = cell - cell_grid.position
	return local.y * cell_grid.size.x + local.x

func _strike() -> void:
	var cadence = preset.thunder.interval_seconds
	next_strike = time + rng.randf_range(float(cadence[0]), float(cadence[1]))
	strike_time = time
	rumble_time = time + rng.randf_range(.54, 1.12)
	var visible_left = maxf(bounds.position.x + 1.0, world_view.position.x + 1.8)
	var visible_right = minf(bounds.end.x - 1.0, world_view.end.x - 1.8)
	if not paved.is_empty():
		var road = paved[0]
		var left = maxf(visible_left, road.position.x + 1.3)
		var right = minf(visible_right, road.end.x - 1.3)
		if right > left:
			visible_left = left
			visible_right = right
	var x = rng.randf_range(visible_left, visible_right) if visible_right > visible_left else bounds.get_center().x
	var above = bounds.position.y - 1.9
	var horizon = minf(roof.position.y - 1.1, bounds.position.y + 7.0)
	bolt = PackedVector2Array([Vector2(x - .68, above)])
	for i in range(1, 10):
		bolt.append(Vector2(x + rng.randf_range(-1.18, 1.18), lerpf(above, horizon, i / 9.0)))
	var side = -1 if rng.randf() < .5 else 1
	var split = bolt[5]
	bolt_branch = PackedVector2Array([split, split + Vector2(side * .86, .51), split + Vector2(side * 1.48, .72), split + Vector2(side * 1.86, 1.48)])

func _update_flash() -> void:
	var age = time - strike_time
	var first = 1.0 - smoothstep(0.0, .22, age)
	var second = .54 * (1.0 - smoothstep(0.0, .16, age - .24)) if age >= .24 else 0.0
	flash = maxf(first, second)
	lamp_voltage = 1.0
	# Each dip starts after the flash, with an irregular recovery between dips.
	if age >= .11 and age < .28: lamp_voltage = .24
	elif age >= .38 and age < .54: lamp_voltage = .42
	elif age >= .66 and age < .78: lamp_voltage = .58

func _draw_ground() -> void:
	if ground_style.x <= 0: return
	var saturation = float(ground_style.x) / 24.0
	var night = float(ground_style.y) / 8.0
	var highlight = float(ground_style.z) / 5.0
	var damp = Color("304956", .19 * saturation)
	ground.draw_set_transform(-bounds.position)
	for surface in paved: ground.draw_rect(surface, damp)
	# Shallow puddles are stationary and catch the sky and the warm street light.
	for puddle in puddles:
		var point = Vector2(puddle.x, puddle.y)
		var radius = puddle.z
		ground.draw_set_transform(point - bounds.position, -.04, Vector2(1.0, .39))
		ground.draw_circle(Vector2.ZERO, radius, Color("243d4c", .34 * saturation))
		var sheen = Color("9dc1ca").lerp(Color("c4b18b"), night * .47).lerp(Color("d2ecff"), highlight * .62)
		ground.draw_circle(Vector2(0.0, -.09), radius * .81, Color(sheen, (.34 + highlight * .17) * saturation))
		ground.draw_line(Vector2(-.42, -.14) * radius, Vector2(.47, -.14) * radius, Color(sheen.lightened(.2), .46 * saturation), .032)
	ground.draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	draw_set_transform(-rain_draw_bounds.position)
	if flash > .04 and bolt.size() > 2:
		draw_polyline(bolt, Color("b1cfff", .20 * flash), .27, true)
		draw_polyline(bolt, Color("f2f6ff", .80 * flash), .065, true)
		draw_polyline(bolt_branch, Color("d1eaff", .61 * flash), .046, true)
	if rain <= .006: return
	var fine := PackedVector2Array()
	var close := PackedVector2Array()
	var splashes := PackedVector2Array()
	var visible_rain = world_view.grow(.7)
	var fall = Vector2(wind * (.60 + sin(time * 1.46) * .18) + sin(time * .56) * .047, 1.0)
	for drop in visible_drops:
		var depth = drop[2]
		if depth >= rain: continue
		var impact = Vector2(drop[0], drop[1])
		var phase = fposmod(time * drop[4] + drop[5], 1.0)
		if phase < .79:
			if use_spatial_rain: continue
			var height = drop[3] * (1.0 - phase / .79)
			var tip = impact - fall * height
			if not visible_rain.has_point(tip): continue
			var tail = tip - fall * drop[6]
			if depth < .23:
				close.append(tip)
				close.append(tail)
			else:
				fine.append(tip)
				fine.append(tail)
		elif depth < .40 and world_view.has_point(impact):
			var scatter = (phase - .79) / .21
			_add_splash(splashes, impact, scatter, depth < .12)
	if fine.size() > 2: draw_multiline(fine, Color("afcde0", rain * .51), .034, true)
	if close.size() > 2: draw_multiline(close, Color("d2e6ee", .33 + rain * .28), .052, true)
	if splashes.size() > 2: draw_multiline(splashes, Color("d0e4e8", rain * .47), .027, true)

func _add_splash(lines: PackedVector2Array, at: Vector2, progress: float, large: bool) -> void:
	var radius = lerpf(.043, .255 if large else .135, progress)
	if progress < .43:
		lines.append(at + Vector2(-.04, 0))
		lines.append(at + Vector2(-1.0, -1.2) * radius)
		lines.append(at + Vector2(.04, 0))
		lines.append(at + Vector2(.91, -1.34) * radius)
		return
	var previous = at + Vector2(radius, 0)
	for segment in range(1, 7):
		var direction = Vector2.from_angle(TAU * float(segment) / 6.0)
		var point = at + direction * Vector2(radius, radius * .38)
		lines.append(previous)
		lines.append(point)
		previous = point
