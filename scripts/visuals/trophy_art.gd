extends RefCounted

const Trophies = preload("res://scripts/core/trophies.gd")
const PLINTH = Color("302c39")
const BRASS = Color("c9a173")

static func _polygon(canvas: CanvasItem, points: Array, tint: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), tint)

static func paint(canvas: CanvasItem, item: Dictionary) -> void:
	var grade = int(item.rarity)
	var accent = Trophies.grade_color(grade)
	var metal = Color(str(item.color)).lerp(accent, .18 + grade * .042)
	var light = metal.lightened(.46)
	var shadow = metal.darkened(.38)
	canvas.draw_rect(Rect2(-18, 12, 36, 9), PLINTH)
	canvas.draw_rect(Rect2(-16, 12, 32, 3), BRASS.lerp(accent, .34))
	canvas.draw_rect(Rect2(-15, 17, 30, 2), BRASS.darkened(.30))
	canvas.draw_rect(Rect2(-5, 16, 10, 3), Color("edcf9c").lerp(accent, .25))
	match str(item.art):
		"clock":
			canvas.draw_rect(Rect2(-4, 3, 8, 11), shadow)
			canvas.draw_circle(Vector2(0, -6), 15, shadow, true, -1, true)
			canvas.draw_circle(Vector2(0, -7), 13, metal, true, -1, true)
			canvas.draw_circle(Vector2(0, -7), 10, Color("fff1d5"), true, -1, true)
			canvas.draw_line(Vector2(0, -14), Vector2(0, -7), shadow, 2, true)
			canvas.draw_line(Vector2(0, -7), Vector2(5, -4), shadow, 2, true)
			for side in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
				canvas.draw_circle(Vector2(0, -7) + side * 7.8, 1, metal, true, -1, true)
		"cup":
			canvas.draw_arc(Vector2(-11, -11), 7, PI * .5, PI * 1.5, 16, metal, 2.8, true)
			canvas.draw_arc(Vector2(11, -11), 7, -PI * .5, PI * .5, 16, metal, 2.8, true)
			_polygon(canvas, [Vector2(-13,-17), Vector2(13,-17), Vector2(8,-2), Vector2(3,2), Vector2(3,8), Vector2(9,12), Vector2(-9,12), Vector2(-3,8), Vector2(-3,2), Vector2(-8,-2)], metal)
			canvas.draw_line(Vector2(-13, -17), Vector2(13, -17), light, 3, true)
			canvas.draw_line(Vector2(-8, -13), Vector2(-4, -1), light, 2, true)
		"gem":
			_polygon(canvas, [Vector2(-7,-21), Vector2(7,-21), Vector2(16,-11), Vector2(0,11), Vector2(-16,-11)], shadow)
			_polygon(canvas, [Vector2(-7,-21), Vector2(7,-21), Vector2(16,-11), Vector2(-16,-11)], light)
			_polygon(canvas, [Vector2(-7,-21), Vector2(-4,-11), Vector2(0,11), Vector2(-16,-11)], metal)
			_polygon(canvas, [Vector2(7,-21), Vector2(4,-11), Vector2(0,11), Vector2(16,-11)], metal.darkened(.13))
			_polygon(canvas, [Vector2(-4,-11), Vector2(4,-11), Vector2(0,11)], accent)
		"spoon":
			canvas.draw_line(Vector2(-11, 10), Vector2(7, -13), shadow, 7, true)
			canvas.draw_line(Vector2(-11, 9), Vector2(7, -14), metal, 4.5, true)
			canvas.draw_circle(Vector2(9,-14), 8, metal, true, -1, true)
			canvas.draw_arc(Vector2(9,-14), 5, 2.2, 4.9, 12, light, 2, true)
		"crown":
			_polygon(canvas, [Vector2(-16,4), Vector2(-18,-14), Vector2(-8,-7), Vector2(0,-21), Vector2(8,-7), Vector2(18,-14), Vector2(16,4)], metal)
			canvas.draw_rect(Rect2(-17,4,34,4), shadow)
			canvas.draw_line(Vector2(-15,3), Vector2(15,3), light, 2, true)
			canvas.draw_circle(Vector2(0,-6), 3.4, accent.lightened(.20), true, -1, true)
		"bell":
			canvas.draw_circle(Vector2(0,6), 5, BRASS, true, -1, true)
			canvas.draw_circle(Vector2(0,-10), 10, metal, true, -1, true)
			_polygon(canvas,[Vector2(-9,-11), Vector2(9,-11), Vector2(16,5), Vector2(-16,5)], metal)
			canvas.draw_line(Vector2(-15,5), Vector2(15,5), light, 3, true)
			canvas.draw_arc(Vector2(0,-10), 6, PI, PI * 1.6, 12, light, 2, true)
		"hourglass":
			_polygon(canvas,[Vector2(-11,-18), Vector2(11,-18), Vector2(2,-4), Vector2(11,9), Vector2(-11,9), Vector2(-2,-4)], Color("fff0d9"))
			_polygon(canvas,[Vector2(-8,7), Vector2(0,-3), Vector2(8,7)], metal)
			canvas.draw_rect(Rect2(-14,-21,28,4), shadow)
			canvas.draw_rect(Rect2(-14,9,28,4), shadow)
			canvas.draw_line(Vector2(-13,-21), Vector2(13,-21), light, 1.4, true)
		"boot":
			_polygon(canvas,[Vector2(-12,-20), Vector2(4,-20), Vector2(2,-6), Vector2(13,-3), Vector2(17,1), Vector2(17,8), Vector2(-14,8)], metal)
			canvas.draw_rect(Rect2(-15,6,33,4), shadow)
			for y in [-15,-10,-5]: canvas.draw_line(Vector2(-9,y), Vector2(2,y+1), light, 1.7, true)
		"feather":
			_polygon(canvas,[Vector2(-13,8), Vector2(-7,-8), Vector2(1,-18), Vector2(17,-22), Vector2(14,-10), Vector2(4,0)], metal)
			canvas.draw_line(Vector2(-13,12), Vector2(12,-17), shadow, 2, true)
			for p in [Vector2(-3,1),Vector2(1,-5),Vector2(7,-11)]:
				canvas.draw_line(p, p + Vector2(6,.2), light, 1.4, true)
		"fan":
			_polygon(canvas,[Vector2(0,9), Vector2(-18,-6), Vector2(-13,-14), Vector2(-4,-18), Vector2(7,-18), Vector2(16,-13), Vector2(18,-6)], metal)
			for x in [-16,-8,0,8,16]: canvas.draw_line(Vector2(0,10), Vector2(x,-16 + absf(x) * .38), shadow, 1.3, true)
			canvas.draw_circle(Vector2(0,8), 2.5, light, true, -1, true)
		"book":
			_polygon(canvas,[Vector2(-16,-19), Vector2(0,-15), Vector2(15,-20), Vector2(15,6), Vector2(0,11), Vector2(-16,6)], shadow)
			_polygon(canvas,[Vector2(-14,-21), Vector2(0,-16), Vector2(13,-21), Vector2(13,4), Vector2(0,9), Vector2(-14,4)], light)
			canvas.draw_line(Vector2(0,-15), Vector2(0,8), shadow, 2, true)
			for y in [-12,-7,-2]:
				canvas.draw_line(Vector2(-11,y),Vector2(-3,y+2),metal,1.5,true)
				canvas.draw_line(Vector2(3,y+2),Vector2(10,y),metal,1.5,true)
		"pen":
			canvas.draw_line(Vector2(-13,9), Vector2(11,-17), shadow, 8, true)
			canvas.draw_line(Vector2(-13,9), Vector2(11,-17), metal, 5.5, true)
			_polygon(canvas,[Vector2(8,-14),Vector2(12,-21),Vector2(17,-22),Vector2(16,-17),Vector2(11,-12)], light)
			canvas.draw_circle(Vector2(-10,7),3,accent,true,-1,true)
		"tray":
			canvas.draw_rect(Rect2(-18,2,36,6), shadow)
			canvas.draw_line(Vector2(-19,1), Vector2(19,1), light, 2, true)
			canvas.draw_circle(Vector2(0,-2), 13, metal, true, -1, true)
			canvas.draw_rect(Rect2(-16,-1,32,4), metal)
			canvas.draw_circle(Vector2(0,-16), 3, light, true, -1, true)
			canvas.draw_arc(Vector2(0,-2), 9, -2.8, -1.6, 10, light, 1.5, true)
		"cart":
			canvas.draw_polyline(PackedVector2Array([Vector2(-17,-16), Vector2(-13,-16), Vector2(-10,5), Vector2(13,5), Vector2(17,-12)]), shadow, 3, true)
			canvas.draw_rect(Rect2(-12,-12,27,4), metal)
			canvas.draw_rect(Rect2(-10,-2,25,4), light)
			for x in [-8,11]: canvas.draw_circle(Vector2(x,9), 3, accent, true, -1, true)
		"pot":
			_polygon(canvas,[Vector2(-16,-13),Vector2(16,-13),Vector2(16,-8),Vector2(12,8),Vector2(-12,8),Vector2(-16,-8)], metal)
			canvas.draw_rect(Rect2(-10,-17,20,5), shadow)
			canvas.draw_rect(Rect2(-4,-21,8,5), light)
			canvas.draw_line(Vector2(-15,-11), Vector2(15,-11), light, 3, true)
			canvas.draw_line(Vector2(-8,4), Vector2(8,4), shadow, 2, true)
		"shelf":
			canvas.draw_rect(Rect2(-15,-18,30,24), shadow)
			canvas.draw_rect(Rect2(-12,-15,24,17), Color("352b3a"))
			for y in [-9,1]: canvas.draw_line(Vector2(-13,y), Vector2(13,y), light, 2, true)
			for x in [-8,0,8]: canvas.draw_circle(Vector2(x,-3),3,metal,true,-1,true)
		"coin":
			canvas.draw_circle(Vector2(0,-5), 15, shadow, true, -1, true)
			canvas.draw_circle(Vector2(0,-7), 13, metal, true, -1, true)
			canvas.draw_circle(Vector2(0,-7), 9, light, false, 2, true)
			_polygon(canvas,[Vector2(0,-14),Vector2(5,-7),Vector2(0,0),Vector2(-5,-7)], shadow)
		"lantern":
			canvas.draw_line(Vector2(0,-21), Vector2(0,10), shadow, 3, true)
			canvas.draw_circle(Vector2(0,-7), 13, metal, true, -1, true)
			canvas.draw_circle(Vector2(0,-7), 9, light, true, -1, true)
			for x in [-5,0,5]: canvas.draw_line(Vector2(x,-18), Vector2(x,4), metal, 1.5, true)
			canvas.draw_rect(Rect2(-7,4,14,3),shadow)
		"ribbon":
			_polygon(canvas,[Vector2(-17,-17),Vector2(16,-17),Vector2(16,7),Vector2(4,7),Vector2(0,12),Vector2(-4,7),Vector2(-17,7)], metal)
			_polygon(canvas,[Vector2(-15,-15),Vector2(0,-3),Vector2(14,-15)], light)
			canvas.draw_circle(Vector2(0,-3), 4.5, accent, true, -1, true)
	if grade >= 4:
		for x in [-14, 14]:
			canvas.draw_circle(Vector2(x, 17), 1.65, accent, true, -1, true)

static func thumbnail(item: Dictionary, extent: Vector2) -> Control:
	var face := Control.new()
	face.custom_minimum_size = extent
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(_paint_thumbnail.bind(face, item))
	face.resized.connect(face.queue_redraw)
	return face

static func _paint_thumbnail(face: Control, item: Dictionary) -> void:
	face.draw_set_transform(face.size * .5, 0.0, Vector2.ONE * minf(face.size.x, face.size.y) / 46.0)
	paint(face, item)
