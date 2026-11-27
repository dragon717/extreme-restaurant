extends RefCounted

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
var elapsed := 0.0

func advance(delta: float, paused: bool) -> void:
	if not paused: elapsed += delta

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

func paint_scenery(board: Control) -> void:
	if dimensions == Vector2i.ZERO: return
	_ground(board)
	_draw_roads(board)
	_draw_yards(board)
	_draw_market(board)
	_draw_furniture(board)

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

func _draw_furniture(board: Control) -> void:
	var h = float(dimensions.y)
	var w = float(dimensions.x)
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
