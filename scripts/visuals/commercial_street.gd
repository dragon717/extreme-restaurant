extends RefCounted

const Lighting = preload("res://scripts/visuals/restaurant_lighting.gd")
const Buildings = preload("res://scripts/visuals/district_buildings.gd")
const ROAD_LEFT := -7.85
const ROAD_RIGHT := -2.85
const ROAD_CENTER := -5.35
const CARS_PER_LANE := 3
const WEST_EDGE := -16.0
const NORTH_EDGE := -8.0
const ORCHARD := Color("9bab79")
const GRASS := Color("b5bd8c")
const PAVERS := Color("bcb29e")
const ASPHALT := Color("526671")
const MARKING := Color("eee0c2")
const CAR_COLORS := [Color("a85d4d"), Color("c5a85d"), Color("869e98"), Color("c3c1b1"), Color("65818b"), Color("a68a79")]
const COATS := [Color("a85346"), Color("567d73"), Color("caa05a"), Color("587799"), Color("8a6680"), Color("667d51")]

var dimensions := Vector2i.ZERO
var bounds := Rect2()
var entrance_y := 12.0
var buildings: Array[Dictionary] = []
var storefronts: Array[Rect2] = []
var warm_windows: Array[Rect2] = []
var lamps: Array[Vector2] = []
var elapsed := 0.0

func configure(map_dimensions: Vector2i, gate := 12.0) -> void:
	dimensions = map_dimensions
	entrance_y = gate
	bounds = Rect2(WEST_EDGE, NORTH_EDGE, dimensions.x - WEST_EDGE + 8.0, dimensions.y - NORTH_EDGE + 9.4)
	buildings.clear()
	storefronts.clear()
	warm_windows.clear()
	lamps.clear()
	# West-side homes open onto a pocket park and a market passage.
	_build(-15.0, -6.35, 5.55, 3.2, "书铺", "hip", "687d83", "d2b394")
	_build(-14.9, -1.84, 5.05, 3.85, "面包房", "gable", "ae745a", "dbc19b", 3, 2)
	_build(-12.9, 3.1, 3.99, 2.8, "花房", "glass", "7c9a82", "d0c19a", 0)
	_build(-15.0, gate + 2.12, 5.7, 4.15, "茶馆", "hip", "607d78", "c6a88a", 1, 3)
	_build(-14.35, gate + 7.0, 3.8, 3.12, "木器铺", "gable", "a07c63", "cbb291", 1)
	_build(-14.92, gate + 11.27, 5.68, 3.65, "", "hip", "7a8588", "bca889", 2)

	# The north lane separates larger workshops from the restaurant frontage.
	var w = float(dimensions.x)
	_build(-1.80, -7.25, 6.28, 3.3, "邮局", "flat", "827f8d", "d6c5a2", 2)
	_build(5.24, -7.05, 5.7, 3.17, "", "gable", "8a6364", "d4b79c", 0)
	_build(13.15, -6.62, 5.35, 2.95, "茶叶行", "hip", "877b73", "c8ab84", 3)
	_build(19.24, -7.13, 7.35, 3.46, "", "gable", "a07368", "c2a17f", 3)
	_build(w - 3.90, -7.07, 6.33, 3.55, "", "hip", "607c88", "d7b595", 2)
	_build(0.20, -2.91, 4.9, 2.5, "咖啡", "gable", "87664f", "d1b594", 2)
	_build(5.77, -2.70, 3.75, 2.28, "钟表", "flat", "647b8e", "c4b599", 0)
	_build(11.87, -2.87, 6.03, 2.43, "玻璃花室", "glass", "729579", "d4bf97", 1)
	_build(20.48, -2.54, 2.90, 2.18, "果摊", "stall", "bb8273", "c6a47f", 3)
	_build(24.15, -2.95, 5.54, 2.63, "杂货铺", "gable", "a28659", "d7b596", 0)
	_build(w + 1.44, 1.8, 5.55, 4.31, "糕团铺", "hip", "a16d68", "cdb99e", 3)
	_build(w + 1.30, 7.10, 3.1, 3.61, "修鞋", "flat", "738c80", "cdb99e", 0)
	_build(w + 1.65, 12.45, 3.43, 3.13, "", "gable", "b38d70", "cdbb9d", 0)
	_build(w + 1.7, 19.25, 4.15, 2.46, "", "hip", "679291", "c6b094", 2)

	var h = float(dimensions.y)
	_build(-.4, h + 5.93, 4.66, 2.54, "夜市", "stall", "ae785f", "d2b18c", 1)
	_build(5.35, h + 6.12, 2.94, 2.16, "", "stall", "7c8c61", "caad89", 0)
	_build(10.32, h + 5.62, 5.68, 2.78, "照相馆", "flat", "7c8292", "d1b79f", 0)
	_build(19.42, h + 5.78, 4.61, 2.74, "", "gable", "a27d65", "c5b398", 2)
	_build(w - 4.70, h + 5.46, 6.45, 2.92, "南街茶摊", "stall", "8e6a72", "d4b797", 1)
	for y in [1.6, 6.8, entrance_y + 2.3, 19.4, h + 1.01]:
		lamps.append(Vector2(ROAD_RIGHT + .44, y))
	for x in [3.4, 9.7, 17.3, 25.2, 33.5]:
		if x < w + 7.0: lamps.append(Vector2(x, h + 1.62))
	lamps.append_array([Vector2(-13.47, entrance_y - 1.22), Vector2(-10, entrance_y + 1.25),
		Vector2(w + 4.22, 17.73), Vector2(18.88, -3.25)])

func _build(x: float, y: float, w: float, h: float, caption: String, kind: String, roof: String, wall: String, door := 1, steps := 0) -> void:
	var box = Rect2(x, y, w, h)
	var lot = {"box": box, "name": caption, "kind": kind, "roof": Color(roof), "wall": Color(wall), "door": door, "steps": steps, "side_entry": x < ROAD_LEFT and str(kind) != "stall"}
	buildings.append(lot)
	storefronts.append(box)
	var face = Buildings.facade(box, kind)
	warm_windows.append(Rect2(face.position + Vector2(.15,.36), Vector2(face.size.x - .30,maxf(.25,face.size.y-.42))))

func rain_paving() -> Array[Rect2]:
	var width = float(dimensions.x)
	var height = float(dimensions.y)
	return [
		Rect2(ROAD_LEFT, bounds.position.y, ROAD_RIGHT - ROAD_LEFT, bounds.size.y),
		Rect2(ROAD_RIGHT, height + 2.0, bounds.end.x - ROAD_RIGHT, 3.27),
		Rect2(ROAD_RIGHT, 0.0, -ROAD_RIGHT, height + 1.92),
		Rect2(0.0, -3.80, width, 1.0),
		Rect2(width, .24, 1.22, height + 1.52)
	]

func advance(delta: float, paused: bool) -> void:
	if not paused: elapsed += delta

func vehicle_position(index: int) -> Vector2:
	var lane = index % 2
	var slot = floori(float(index) / 2.0)
	var margin = 1.8
	var length = bounds.size.y + margin * 2
	var direction = 1.0 if lane == 0 else -1.0
	var y = fposmod(elapsed * 2.6 * direction + slot * length / CARS_PER_LANE + lane * 5 + 2.4, length) + NORTH_EDGE - margin
	return Vector2(lerpf(ROAD_LEFT, ROAD_RIGHT, .25 + lane * .50), y)

func pedestrian_position(index: int) -> Vector2:
	var stride = elapsed * (.85 + (index % 3) * .16)
	var offset = index * 3.19
	var direction = 1.0 if index % 2 == 0 else -1.0
	var short_y = fposmod(stride * direction + offset, bounds.size.y) + NORTH_EDGE
	if index < 7: return Vector2(-1.88 + (index % 2) * .45, short_y)
	if index < 11: return Vector2(ROAD_LEFT - .49, short_y)
	if index < 16:
		var x = fposmod(stride * direction + offset, bounds.end.x - ROAD_RIGHT) + ROAD_RIGHT
		return Vector2(x, -3.45 + (index % 2) * .21)
	var x = fposmod(stride * direction + offset, bounds.end.x - ROAD_RIGHT) + ROAD_RIGHT
	return Vector2(x, dimensions.y + .78 + (index % 2) * .37)

# Positions here share the restaurant's cell coordinates. The cut starts half
# a tile beyond the paving edge so actors can fade on either side of it.
func gate_route(progress: float, target: Vector2) -> Vector2:
	var start = Vector2(WEST_EDGE - .78, entrance_y + clampf(target.y - entrance_y, -.18, .87) * .44)
	var curb = Vector2(-2.38, entrance_y + clampf(target.y - entrance_y, -.18, .87) * .61)
	return _along_gate_route(start, curb, target, progress)

func exit_route(progress: float, start: Vector2) -> Vector2:
	var end = Vector2(WEST_EDGE - .78, entrance_y + .46)
	return _along_gate_route(start, Vector2(minf(-2.38, start.x - .17), entrance_y + .63), end, progress)

func _along_gate_route(start: Vector2, corner: Vector2, end: Vector2, progress: float) -> Vector2:
	var first = start.distance_to(corner)
	var distance = clampf(progress,0,1) * (first + corner.distance_to(end))
	if distance <= first:
		return start.move_toward(corner, distance)
	return corner.move_toward(end, distance - first)

func threshold_alpha(cell: Vector2) -> float:
	return smoothstep(WEST_EDGE - .78, WEST_EDGE + .18, cell.x)

func paint_scenery(board: Control, evening: float) -> void:
	if dimensions == Vector2i.ZERO: return
	_ground(board)
	_draw_roads(board)
	_draw_yards(board)
	_draw_market(board)
	for lot in buildings: Buildings.draw(board, lot, evening)
	_draw_furniture(board, evening)

func paint_activity(board: Control, origin: Vector2, unit: float, evening: float, flat_scenery := true) -> void:
	if dimensions == Vector2i.ZERO: return
	var view = Rect2(-origin / unit, board.size / unit).grow(2.1)
	if not view.intersects(bounds.grow(1.0)): return
	board.draw_set_transform(origin, 0, Vector2.ONE * unit)
	if flat_scenery: _draw_water(board)
	var street_limit = Rect2(ROAD_LEFT, NORTH_EDGE, ROAD_RIGHT - ROAD_LEFT, bounds.size.y)
	for index in range(CARS_PER_LANE * 2 if flat_scenery else 0):
		var point = vehicle_position(index)
		# Keep the whole vehicle and its lights inside the road cutoff.
		if street_limit.grow(-1.08).has_point(point) and view.has_point(point):
			_draw_car(board, point, index, evening)
	for index in range(21):
		var point = pedestrian_position(index)
		if bounds.grow(-.35).has_point(point) and view.has_point(point):
			_draw_pedestrian(board, point, index)
	board.draw_set_transform(Vector2.ZERO)

func paint_signs(board: Control, origin: Vector2, unit: float, font: Font) -> void:
	if unit < 15.0: return
	var view = Rect2(-origin / unit, board.size / unit)
	var font_size = clampi(roundi(unit * .38), 8, 17)
	for lot in buildings:
		if str(lot.name).is_empty() or not view.intersects(lot.box): continue
		var sign = Buildings.sign_rect(lot)
		var center = origin + sign.get_center() * unit
		var caption := str(tr(str(lot.name)))
		var width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		board.draw_string(font, center + Vector2(-width*.5, font_size*.34), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("f5e3b9"))

func _ground(board: Control) -> void:
	var x = bounds.position.x
	var y = bounds.position.y
	var right = bounds.end.x
	var bottom = bounds.end.y
	var edge = PackedVector2Array([Vector2(x+2.0,y),Vector2(right-2.1,y),Vector2(right,y+1.45),Vector2(right,bottom-1.38),
		Vector2(right-1.65,bottom),Vector2(x+2.22,bottom),Vector2(x,bottom-1.55),Vector2(x,y+1.92)])
	var thickness = Transform2D(0.0, Vector2(.06,.52))
	board.draw_colored_polygon(thickness * edge, Color("66756c", .42))
	board.draw_colored_polygon(Transform2D(0.0,Vector2(0,.36)) * edge, Color("837e67"))
	board.draw_colored_polygon(edge, GRASS)
	edge.append(edge[0])
	board.draw_polyline(edge, Color("d0cf9e"), .09, true)
	var w = float(dimensions.x)
	var h = float(dimensions.y)
	_paved(board, Rect2(-15.45, -6.4, 7.36, entrance_y + 5.58), PAVERS.darkened(.03), .77)
	_paved(board, Rect2(-15.5, entrance_y + 1.62, 7.40, bounds.end.y - entrance_y - 3.05), PAVERS.darkened(.02), .78)
	_paved(board, Rect2(ROAD_RIGHT, -3.85, w - ROAD_RIGHT + .15, h + 5.91), PAVERS, .70)
	_paved(board, Rect2(-2.72, -7.71, w + 8.31, 4.02), Color("b5b396"), .86)
	_paved(board, Rect2(w + .0, .27, 7.52, h + 1.50), Color("bbb59c"), .69)
	_paved(board, Rect2(ROAD_RIGHT, h + 5.20, w + 8.45, 3.68), PAVERS, .73)

func _paved(board: Control, r: Rect2, color: Color, size: float) -> void:
	board.draw_rect(r, color)
	for row in range(1, floori(r.size.y / size)):
		var y = r.position.y + row * size
		board.draw_line(Vector2(r.position.x,y),Vector2(r.end.x,y),Color("666c60", .17),.032)
		var x = r.position.x + (.25 if row % 2 == 0 else .67)
		while x < r.end.x - .19:
			board.draw_line(Vector2(x,y),Vector2(x,minf(y+size,r.end.y)),Color("747463",.13),.028)
			x += size * 1.17

func _draw_roads(board: Control) -> void:
	var bottom = bounds.end.y
	var h = float(dimensions.y)
	var right = bounds.end.x
	var south = h + 2.0
	var main = Rect2(ROAD_LEFT,NORTH_EDGE,ROAD_RIGHT-ROAD_LEFT,bounds.size.y)
	var cross = Rect2(ROAD_RIGHT, south, right - ROAD_RIGHT, 3.27)
	board.draw_rect(main, ASPHALT)
	board.draw_rect(cross, ASPHALT)
	board.draw_rect(Rect2(ROAD_LEFT,.0,.17,bottom), Color("939c90"))
	board.draw_rect(Rect2(ROAD_RIGHT - .12,NORTH_EDGE,.14,bottom - NORTH_EDGE), Color("b7b6a0"))
	board.draw_rect(Rect2(ROAD_RIGHT, south - .08,right - ROAD_RIGHT,.09), Color("c4bda4"))
	board.draw_rect(Rect2(ROAD_RIGHT, cross.end.y,right - ROAD_RIGHT,.09), Color("c4bda4"))
	board.draw_rect(Rect2(ROAD_RIGHT - .2,south,.23,cross.size.y), ASPHALT)
	board.draw_rect(Rect2(ROAD_LEFT+.10,NORTH_EDGE,.073,-NORTH_EDGE), Color("bed0ae"))
	for y in range(ceili(NORTH_EDGE)+1, floori(bottom)-1, 3):
		if absf(y - entrance_y) < 2.05 or (y > south - .75 and y < cross.end.y + .8): continue
		board.draw_rect(Rect2(ROAD_CENTER-.034,y,.068,1.33), Color(MARKING,.79))
	for x in range(-1,floori(right),3):
		board.draw_rect(Rect2(x, south+1.6,minf(1.22,right-x),.067),Color(MARKING,.81))
	var mouth = Rect2(WEST_EDGE, entrance_y - .96, ROAD_LEFT - WEST_EDGE, 2.72)
	_paved(board, mouth, Color("cbbb9e"), .63)
	board.draw_line(mouth.position + Vector2(0,.07),Vector2(mouth.end.x,mouth.position.y+.07),Color("8f8c73"),.075)
	board.draw_line(Vector2(mouth.position.x,mouth.end.y-.06),mouth.end-Vector2(0,.06),Color("8f8c73"),.080)
	for stripe in range(7):
		board.draw_rect(Rect2(ROAD_LEFT + .27 + stripe*.66,entrance_y-.06,.34,1.47), MARKING)
	board.draw_rect(Rect2(ROAD_RIGHT+.07,entrance_y-.14,.42,1.60), Color("b58b5d"))
	board.draw_rect(Rect2(ROAD_LEFT-.49,entrance_y-.14,.42,1.60), Color("b58b5d"))
	board.draw_rect(Rect2(ROAD_LEFT+.23,entrance_y-.51,1.96,.085), MARKING)
	board.draw_rect(Rect2(ROAD_CENTER+.23,entrance_y+1.56,1.96,.085), MARKING)
	for stripe in range(5):
		board.draw_rect(Rect2(16.9,south+.28+stripe*.56,1.42,.24),Color(MARKING,.80))
	board.draw_rect(Rect2(16.84,south-.16,1.54,.22),Color("b8a379"))
	board.draw_rect(Rect2(16.84,cross.end.y-.06,1.54,.23),Color("b8a379"))
	var alley = Rect2(ROAD_RIGHT,-3.75,right-ROAD_RIGHT, .94)
	board.draw_rect(alley, Color("9d9c86"), false,.075)
	for x in range(-2, floori(right)):
		board.draw_rect(Rect2(x + .30,-3.30,.46,.03),Color("d3c7aa", .62))
	_cap(board, Vector2(WEST_EDGE,entrance_y-.96), Vector2(0.0,1.0), mouth.size.y)
	_cap(board, Vector2(ROAD_LEFT,NORTH_EDGE), Vector2.RIGHT, main.size.x)
	_cap(board, Vector2(ROAD_LEFT,bottom), Vector2.RIGHT, main.size.x)
	_cap(board, Vector2(right,south), Vector2.DOWN, cross.size.y)

func _cap(board: Control, start: Vector2, direction: Vector2, length: float) -> void:
	board.draw_line(start,start+direction*length,Color("505a50"),.13)
	board.draw_line(start+direction*.12,start+direction*(length-.12),Color("e3d4ab",.63),.046)

func _draw_yards(board: Control) -> void:
	var w = float(dimensions.x)
	var park = Rect2(-14.87,6.48,6.19,4.18)
	board.draw_rect(park.grow(.12), Color("dbca9f"))
	board.draw_rect(park, ORCHARD)
	var spring = Rect2(-13.02,7.42,2.23,1.86)
	board.draw_rect(spring.grow(.16), Color("867d68"))
	board.draw_rect(spring.grow(.07), Color("ccc5a4"))
	board.draw_rect(spring, Color("729c99"))
	board.draw_circle(spring.get_center(),.42,Color("d6ceb0"))
	board.draw_circle(spring.get_center(),.27,Color("87aba2"))
	for i in range(10):
		var location = park.position + Vector2(.22 + fposmod(i*1.71,5.6),.27+fposmod(i*1.16,3.6))
		if not spring.grow(.30).has_point(location):
			board.draw_circle(location,.12,Color("c7c792"))
	var corner = Rect2(w + 1.32, -.98, 5.92, 2.32)
	board.draw_rect(corner.grow(.10),Color("dad0a4"))
	board.draw_rect(corner,ORCHARD.lightened(.09))
	_paved(board,Rect2(corner.get_center().x-.55,corner.position.y,1.10,corner.size.y),Color("c7b89b"),.45)
	for x in [corner.position.x+.77,corner.end.x-.72]:
		for index in range(3):
			_planter(board,Vector2(x+.25*(index%2),corner.position.y+.55+index*.44),Color("c0a37f"))
	var canal = Rect2(w+5.46,7.8,2.27,15.76)
	board.draw_rect(canal.grow(.18), Color("827b67"))
	board.draw_rect(canal, Color("689597"))
	board.draw_rect(Rect2(canal.position + Vector2(.11,.16),Vector2(.40,canal.size.y-.31)),Color("a9c1ab",.42))
	var bridge = Rect2(w + 5.09, 16.40, 2.80, 1.27)
	board.draw_rect(bridge, Color("907d5c"))
	board.draw_rect(bridge.grow(-.09), Color("c4a575"))
	for i in range(13):
		var x = bridge.position.x + .17 + i * .23
		board.draw_line(Vector2(x,bridge.position.y+.14),Vector2(x,bridge.end.y-.13),Color("8a7457"),.040)
	for y in [bridge.position.y+.05, bridge.end.y-.06]:
		board.draw_line(Vector2(bridge.position.x,y),Vector2(bridge.end.x,y),Color("594e42"),.085)
	for point in [Vector2(-15.1,2.1),Vector2(-10.0,-7.22),Vector2(11.50,-5.03),Vector2(27.51,-6.43),Vector2(w+4.58,10.12),Vector2(w+2.82,17.72)]:
		board.draw_rect(Rect2(point-Vector2(.36,.25),Vector2(.75,.59)),Color("8b8067"))
		board.draw_rect(Rect2(point-Vector2(.28,.18),Vector2(.59,.45)),Color("a2ad79"))

func _draw_water(board: Control) -> void:
	var x0 = float(dimensions.x) + 5.46
	for i in range(26):
		var y = 7.98 + fposmod(float(i) * .68 + elapsed * .33, 15.38)
		if y >= 16.40 and y <= 17.67: continue
		var x = x0 + .47 + float((i * 3) % 6) * .17
		board.draw_line(Vector2(x, y), Vector2(x + .30 + (i % 3) * .13, y), Color("bfd3b6", .59), .036)

func _draw_market(board: Control) -> void:
	var y = float(dimensions.y) + 8.27
	var stripe = Color("ddcbac", .60)
	for x in [4.83, 9.01, 16.84, 25.33, 34.42]:
		var spot = Vector2(x,y)
		board.draw_rect(Rect2(spot-Vector2(.56,.30),Vector2(1.13,.58)),Color("b6a58b"))
		for index in range(3):
			var crate = Rect2(spot + Vector2(-.42 + index * .28,-.12 - (index%2) * .17), Vector2(.25,.26))
			board.draw_rect(crate, Color("8d6c52"))
			board.draw_rect(crate.grow(-.038), Color("bf996b"))
			board.draw_line(crate.position+Vector2(.04,.07),Vector2(crate.end.x-.04,crate.position.y+.07),stripe,.031)
		var mat = Rect2(spot+Vector2(-.5,.37),Vector2(1.02,.22))
		board.draw_rect(mat, Color("a17c6a"))
		board.draw_line(mat.position+Vector2(.10,.11),mat.end-Vector2(.10,.11),stripe,.024)

func lamp_head(position: Vector2) -> Vector2:
	return position + Vector2(.17, -.55)

func _draw_furniture(board: Control, evening: float) -> void:
	var h = float(dimensions.y)
	var w = float(dimensions.x)
	for lamp in lamps: _lamp(board, lamp, evening)
	for location in [Vector2(-14.24,7.88),Vector2(-9.32,8.48),Vector2(-14.61,9.91),Vector2(-13.21,5.58),
		Vector2(-10.03,entrance_y+6.93),Vector2(-15.13,entrance_y+10.86),Vector2(-1.01,3.8),
		Vector2(-.72,8.02),Vector2(-.70,17.4),Vector2(w+5.87,7.35),Vector2(w+4.19,18.26),
		Vector2(11.43,-4.42),Vector2(27.50,-5.55),Vector2(18.3,h+6.72),Vector2(23.58,h+8.65)]:
		board.draw_circle(location + Vector2(.14,.20),.61,Color("515c4f",.24))
		_flowering_tree(board,location,roundi((location.x+19)*17+location.y))
	for p in [Vector2(-14.01,9.70),Vector2(-10.35,7.35),Vector2(-12.15,entrance_y+6.5),Vector2(w+3.72,18.57)]:
		board.draw_rect(Rect2(p-Vector2(.52,.15),Vector2(1.0,.32)),Color("645b4b"))
		for offset in [-.42,.31]:
			board.draw_rect(Rect2(p + Vector2(offset,.08),Vector2(.11,.25)),Color("63594b"))
		board.draw_rect(Rect2(p-Vector2(.50,.14),Vector2(.97,.19)),Color("bc9368"))
		board.draw_line(p-Vector2(.46,.09),p+Vector2(.45,-.09),Color("e1b883"),.044)
	for p in [Vector2(-8.40,entrance_y-1.5),Vector2(-9.32,entrance_y+1.44), Vector2(-.68,9.13),
		Vector2(-.65,10.10),Vector2(22.41,-.14),Vector2(w+4.33,7.16),Vector2(16.88,h+6.27)]:
		_planter(board,p,Color("bd9585"))
	_draw_bicycle(board,Vector2(-.46,5.2),Color("76584c"))
	_draw_bicycle(board,Vector2(-.51,5.96),Color("526e67"))
	_draw_bicycle(board,Vector2(w+3.42,11.76),Color("694c51"))
	for i in range(6):
		var p = Vector2(-15.22 + i * 1.22, entrance_y+1.49)
		board.draw_rect(Rect2(p,Vector2(.10,.38)),Color("64675c"))
		board.draw_rect(Rect2(p,Vector2(.10,.096)),Color("d4c6a1"))
	for x in [1.97,5.27,8.86,17.51,26.01]:
		var p = Vector2(x, h + 1.24)
		board.draw_rect(Rect2(p,Vector2(.65,.38)),Color("93816b"),false,.07)
		board.draw_line(p+Vector2(.11,.1),p+Vector2(.54,.1),Color("d5be93"),.028)

func _flowering_tree(board: Control, base: Vector2, seed_index: int) -> void:
	board.draw_rect(Rect2(base - Vector2(.07, .64), Vector2(.15, .8)), Color("735549"))
	var crown = base - Vector2(.04, .64)
	board.draw_circle(crown + Vector2(.08, .13), .52, Color("536d68"))
	for i in range(7):
		var angle = i * 2.4 + seed_index
		var tuft = crown + Vector2(cos(angle) * .34, sin(angle) * .24)
		var tint = Color("8cae91") if i % 3 == 0 else Color("bd9194").lerp(Color("e8b4aa"), float(i) / 7.0)
		board.draw_circle(tuft, .30, tint)
		board.draw_circle(tuft + Vector2(-.08, -.10), .085, Color("f5d2bd"))
	for i in range(4):
		var petal = base + Vector2(sin(seed_index + i * 3.4) * .62, .22 + i * .11)
		board.draw_line(petal, petal + Vector2(.09, -.035), Color("ecc0b1"), .042)

func _planter(board: Control, p: Vector2, tint: Color) -> void:
	board.draw_rect(Rect2(p.x - 0.2, p.y - 0.07, 0.4, 0.26), Color("735e4d"))
	board.draw_circle(p - Vector2(0.02, 0.12), 0.23, Color("557554"))
	board.draw_circle(p - Vector2(0.08, 0.21), 0.12, tint.lightened(0.35))

func _lamp(board: Control, p: Vector2, evening: float) -> void:
	var head = p - Vector2(-0.17, 0.55)
	if evening > 0.0:
		board.draw_circle(head, .66, Color("ffc889", evening * .08))
		board.draw_circle(head, .36, Color("ffcb82", evening * .16))
		board.draw_circle(head, .15, Color("ffdd9f", evening * .36))
	board.draw_line(p, p - Vector2(0.0, 0.55), Color("47564e"), 0.065)
	board.draw_line(p - Vector2(0.0, 0.55), head, Color("47564e"), 0.065)
	board.draw_rect(Rect2(head - Vector2(0.06, 0.06), Vector2(0.19, 0.10)), Color("877d65").lerp(Color("ffda91"), evening))

func _draw_bicycle(board: Control, p: Vector2, color: Color) -> void:
	var front = p - Vector2(0.04, 0.27)
	var back = p + Vector2(0.05, 0.25)
	board.draw_circle(front, 0.16, Color("424c47"), false, 0.043)
	board.draw_circle(back, 0.16, Color("424c47"), false, 0.043)
	board.draw_polyline(PackedVector2Array([front, p - Vector2(0.14, 0.05), back, p + Vector2(0.13, -0.04), front]), color, 0.06)
	board.draw_line(p + Vector2(0.13, -0.04), p + Vector2(0.19, -0.14), Color("494e47"), 0.052)

func _draw_car(board: Control, p: Vector2, index: int, evening: float) -> void:
	var direction = 1.0 if index % 2 == 0 else -1.0
	var paint_color = CAR_COLORS[(index * 5) % CAR_COLORS.size()]
	var length = 2.02 if index % 4 == 2 else 1.64
	var half = length * 0.5
	var front = p.y + direction * half
	var back = p.y - direction * half
	for side in [-1.0, 1.0]:
		if evening > 0.0:
			var headlight = Vector2(p.x + side * 0.32, front)
			board.draw_colored_polygon(PackedVector2Array([headlight, headlight + Vector2(-0.3, direction * 1.2), headlight + Vector2(0.3, direction * 1.2)]), Color("f6d394", evening * 0.20))
		board.draw_rect(Rect2(p.x + side * 0.49 - 0.055, p.y - half + 0.22, 0.11, 0.29), Color("292f30"))
		board.draw_rect(Rect2(p.x + side * 0.49 - 0.055, p.y + half - 0.50, 0.11, 0.29), Color("292f30"))
	board.draw_rect(Rect2(p + Vector2(-0.49, -half + 0.09), Vector2(1.10, length)), Color("2b3434", 0.52))
	board.draw_rect(Rect2(p.x - 0.46, p.y - half + 0.08, 0.92, length - 0.16), paint_color.darkened(0.24))
	board.draw_rect(Rect2(p.x - 0.36, p.y - half, 0.72, length), paint_color)
	board.draw_rect(Rect2(p.x - 0.36, p.y - 0.40, 0.72, 0.80), Color("344d58"))
	board.draw_rect(Rect2(p.x - 0.28, p.y - 0.25, 0.56, 0.50), paint_color.lightened(0.13))
	board.draw_line(Vector2(p.x - 0.34, p.y + direction * 0.35), Vector2(p.x + 0.34, p.y + direction * 0.35), Color("9db3af"), 0.055)
	for side in [-1.0, 1.0]:
		board.draw_rect(Rect2(p.x + side * 0.29 - 0.085, front - direction * 0.11 - 0.041, 0.17, 0.082), Color("f0da9f"))
		board.draw_rect(Rect2(p.x + side * 0.32 - 0.065, back + direction * 0.11 - 0.039, 0.13, 0.078), Color("b04a44"))

func _draw_pedestrian(board: Control, p: Vector2, index: int) -> void:
	var coat = COATS[index % COATS.size()]
	var stride = sin(elapsed * 7.2 + index * 1.4) * 0.08
	var skin = Color("dfb18a").darkened(float(index % 4) * 0.09)
	board.draw_rect(Rect2(p.x - 0.12, p.y + 0.05, 0.34, 0.12), Color("313a36", 0.25))
	board.draw_rect(Rect2(p.x - 0.12, p.y - 0.015 + stride, 0.09, 0.18), Color("3c4543"))
	board.draw_rect(Rect2(p.x + 0.03, p.y - 0.015 - stride, 0.09, 0.18), Color("444744"))
	board.draw_rect(Rect2(p.x - 0.16, p.y - 0.23, 0.32, 0.26), coat)
	board.draw_rect(Rect2(p.x - 0.09, p.y - 0.41, 0.18, 0.19), skin)
	board.draw_rect(Rect2(p.x - 0.10, p.y - 0.41, 0.20, 0.075), Color("474138"))
	if index % 3 == 1:
		board.draw_rect(Rect2(p.x + 0.11, p.y - 0.13, 0.14, 0.20), Color("bf9d6f"))
