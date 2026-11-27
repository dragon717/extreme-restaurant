extends Control

const Style = preload("res://scripts/ui/style.gd")
const FRAME = Vector2(720, 450)

var steam_frame = 0
var steam_time = 0.0
var sign_font: Font

func _ready() -> void:
	sign_font = Style.font()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	steam_time += delta
	var frame = int(steam_time * 8.0)
	if frame != steam_frame:
		steam_frame = frame
		queue_redraw()

func _draw() -> void:
	var scale_factor = maxf(size.x / FRAME.x, size.y / FRAME.y)
	draw_set_transform((size - FRAME * scale_factor) * 0.5, 0.0, Vector2.ONE * scale_factor)
	_draw_skyline()
	_draw_street()
	_draw_diner()
	_draw_steam()

func _box(x: float, y: float, width: float, height: float, color: Color) -> void:
	draw_rect(Rect2(x, y, width, height), color)

func _shape(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func _draw_skyline() -> void:
	var top = Color("263950")
	var horizon = Color("b58c85")
	for y in range(0, 332, 4):
		_box(0, y, 720, 4, top.lerp(horizon, y / 332.0))
	for radius in [35.0, 25.0, 17.0]:
		draw_circle(Vector2(559, 75), radius, Color("ffdea6", .045), true, -1, true)
	_box(550, 63, 17, 24, Color("a5af96"))
	_box(546, 67, 25, 16, Color("a5af96"))
	_box(553, 65, 12, 19, Color("d8c8a4"))
	_box(550, 69, 19, 11, Color("d8c8a4"))
	for point in [Vector2(500, 41), Vector2(595, 48), Vector2(629, 72), Vector2(688, 45), Vector2(435, 54), Vector2(473, 94)]:
		draw_rect(Rect2(point, Vector2(2, 2)), Color("e0c49a", 0.65))
	for index in range(21):
		var x = index * 36
		var height = 56 + (index * 37) % 112
		var y = 302 - height
		var color = Color("2d4046").lerp(Color("435458"), float(index % 3) / 3.0)
		_box(x, y, 43, height + 18, color)
		_box(x + 3, y - 4, 35, 4, color.lightened(0.05))
		for row in range(y + 12, 286, 15):
			for column in range(x + 7, x + 37, 12):
				if (column + row + index) % 7 < 3:
					_box(column, row, 4, 6, Color("b09570", 0.31))
	_shape([Vector2(0, 90), Vector2(200, 111), Vector2(322, 184), Vector2(322, 336), Vector2(0, 336)], Color("202f36"))
	_box(273, 182, 77, 151, Color("293e41"))
	for x in range(278, 335, 16):
		_box(x, 201, 10, 26, Color("394d47"))
		_box(x + 3, 205, 1, 17, Color("526354"))
	_box(278, 251, 58, 64, Color("172a31"))
	_box(282, 260, 51, 3, Color("426056"))

func _draw_street() -> void:
	_shape([Vector2(0, 321), Vector2(720, 315), Vector2(720, 450), Vector2(0, 450)], Color("263735"))
	_shape([Vector2(0, 347), Vector2(659, 377), Vector2(720, 355), Vector2(720, 390), Vector2(659, 419), Vector2(0, 376)], Color("4a4b42"))
	_shape([Vector2(0, 376), Vector2(659, 419), Vector2(720, 390), Vector2(720, 395), Vector2(659, 424), Vector2(0, 382)], Color("83705a"))
	_shape([Vector2(381, 342), Vector2(638, 342), Vector2(682, 407), Vector2(367, 395)], Color("e5a96f", 0.16))
	for index in range(84):
		var x = (index * 83) % 720
		var y = 354 + (index * 17) % 92
		var near_diner = x >= 361 and x < 677 and y < 425
		var reflection = Color("dc9e5f", 0.26) if near_diner else Color("789387", 0.14)
		_box(x, y, 2 + (index * 7) % 19, 1 + index % 2, reflection)
	for x in range(355, 671, 38):
		var y = 376 + (x - 355) * 0.055
		draw_line(Vector2(x, y), Vector2(x - 9, y + 24), Color("8b7760", 0.35), 1.0)

func _draw_diner() -> void:
	_shape([Vector2(641, 176), Vector2(705, 149), Vector2(705, 340), Vector2(641, 370)], Color("333e36"))
	_shape([Vector2(649, 220), Vector2(694, 201), Vector2(694, 302), Vector2(649, 322)], Color("202f2c"))
	_shape([Vector2(654, 232), Vector2(689, 218), Vector2(689, 286), Vector2(654, 306)], Color("92805d"))
	for y in range(241, 288, 9):
		draw_line(Vector2(654, y + 15), Vector2(688, y), Color("d2a46d", 0.52), 1.0)
	_box(350, 176, 293, 194, Color("b89868"))
	_box(353, 294, 289, 76, Color("4f5e48"))
	_box(350, 358, 293, 13, Color("233b34"))
	_box(350, 353, 293, 4, Color("6f7353"))
	_box(353, 184, 289, 8, Color("776847"))
	_shape([Vector2(337, 177), Vector2(397, 137), Vector2(711, 137), Vector2(650, 177)], Color("354c44"))
	_shape([Vector2(344, 170), Vector2(400, 139), Vector2(707, 139), Vector2(647, 170)], Color("78816b"))
	for x in range(358, 647, 17):
		draw_line(Vector2(x, 168), Vector2(x + 47, 140), Color("4b5f51"), 1.0)
	_box(337, 174, 313, 11, Color("1e3532"))
	_box(337, 174, 313, 3, Color("c4a772"))
	_shape([Vector2(650, 174), Vector2(711, 137), Vector2(711, 148), Vector2(650, 185)], Color("223732"))
	_box(574, 133, 24, 14, Color("46594b"))
	_box(577, 120, 17, 17, Color("283d39"))
	_box(575, 118, 22, 5, Color("68735a"))

	_draw_window(370, 242, 156)
	_draw_window(590, 244, 42)
	_box(534, 238, 50, 124, Color("263a34"))
	_box(539, 243, 40, 115, Color("efb46c"))
	_box(543, 247, 32, 65, Color("9b613d"))
	_box(546, 251, 27, 44, Color("f0c580"))
	_box(544, 315, 32, 39, Color("556850"))
	_box(574, 306, 3, 10, Color("fff1ba"))
	_box(530, 361, 58, 7, Color("b78857"))
	_box(525, 368, 67, 5, Color("e0a96c"))

	_box(370, 191, 255, 35, Color("463b2d"))
	_box(374, 194, 247, 29, Color("6a3a2c"))
	_box(377, 196, 241, 1, Color("d29355"))
	_box(377, 220, 241, 1, Color("b47247"))
	_box(396, 208, 44, 2, Color("d49b5a", 0.7))
	_box(556, 208, 43, 2, Color("d49b5a", 0.7))
	draw_string(sign_font, Vector2(471, 217), tr("食 堂"), HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("ffdaa0"))
	for x in range(351, 641, 14):
		var is_light = (x - 351) % 28 == 0
		var awning = Color("bb6448") if is_light else Color("e5bb82")
		var y = 225 + (0 if is_light else 1)
		_shape([Vector2(x + 2, y), Vector2(x + 16, y), Vector2(x + 13, y + 17), Vector2(x - 1, y + 17)], awning)
		_box(x - 1, y + 17, 14, 4, awning.darkened(0.25))

	for x in [363, 635]:
		_box(x, 246, 7, 13, Color("6a4432"))
		_box(x + 1, 248, 5, 8, Color("fed391"))
		_box(x - 4, 246, 15, 15, Color("ffcb80", 0.14))
		_box(x + 1, 263, 5, 2, Color("b38752"))
	for x in [363, 623]:
		_box(x, 349, 17, 14, Color("644d3b"))
		_box(x - 1, 347, 19, 4, Color("a77955"))
		_box(x + 3, 339, 12, 8, Color("527051"))
		_box(x + 7, 334, 4, 11, Color("729063"))
		_box(x + 1, 342, 6, 5, Color("66865a"))

func _draw_window(x: int, y: int, width: int) -> void:
	_box(x - 3, y - 2, width + 6, 99, Color("304137"))
	_box(x, y, width, 94, Color("c57f4d"))
	_box(x + 3, y + 4, width - 6, 79, Color("e7a35f"))
	_box(x + 3, y + 14, width - 6, 26, Color("f2c27d"))
	_box(x + 4, y + 58, width - 8, 23, Color("b7774d"))
	for column in range(x + 5, x + width - 7, 12):
		_box(column, y + 16, 1, 38, Color("a6754f", 0.33))
	for column in range(x + 9, x + width - 16, 28):
		_box(column + 6, y + 5, 1, 14, Color("75543c"))
		_box(column + 2, y + 19, 9, 4, Color("754c36"))
		_box(column + 3, y + 23, 7, 3, Color("ffe7a6"))
		var seat = y + 43 + (column % 3) * 4
		var cloth = Color("6d7252") if column % 3 == 0 else Color("556052")
		_box(column, seat + 11, 13, 17, cloth)
		_box(column + 2, seat + 2, 9, 10, Color("c78b5b"))
		_box(column + 2, seat, 9, 4, Color("43382f"))
		_box(column - 3, seat + 19, 23, 4, Color("74503b"))
		_box(column + 13, seat + 16, 5, 3, Color("f5d4a0"))
		_box(column + 17, seat + 23, 2, 10, Color("534537"))
	for column in range(x + 38, x + width, 39):
		if column < x + width - 3: _box(column, y, 3, 93, Color("4d5743"))
	_box(x - 4, y + 83, width + 8, 6, Color("364c40"))
	_box(x - 4, y + 83, width + 8, 2, Color("ecc185"))
	_box(x - 2, y + 92, width + 4, 3, Color("293e35"))

func _draw_steam() -> void:
	for index in range(5):
		var rise = (steam_frame + index * 9) % 46
		var x = 583 + int(sin(float(rise) * 0.19) * (3.0 + rise * 0.22)) + index * 2
		var y = 112 - rise
		var alpha = 0.26 * (1.0 - rise / 46.0)
		_box(x, y, 5 + rise / 7.0, 3 + rise / 12.0, Color("d4bd9d", alpha))
