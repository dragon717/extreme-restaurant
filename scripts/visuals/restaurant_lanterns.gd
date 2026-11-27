extends Node2D

# Emissive glass and paper are painted after the ambient wash, below the actors and UI.
var board
var glow: Texture2D

func _pool(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_texture_rect(glow, Rect2(center - radius, radius * 2), false, color)

func _draw() -> void:
	if board == null or board.sim == null or board.lamp_positions.is_empty(): return
	var unit: float = board._unit()
	var indoor: float = board.room_lamp_light
	draw_set_transform(board._origin(), 0, Vector2.ONE * unit)
	for i in range(board.lamp_positions.size()):
		var fixture: Vector2 = board.lamp_positions[i] + Vector2(.5, .5)
		if indoor > .015:
			_pool(fixture + Vector2(0, .4), Vector2(3.8, 2.9), Color("ffdb9e", indoor * .19))
		if i == 0:
			for offset in [Vector2(-.63, -.04), Vector2(.40, -.04)]:
				_lantern(fixture + offset, indoor)
		else:
			var bulb = board.lamps[i].color
			var brass = Color("977354").lerp(Color("dbab73"), indoor)
			draw_line(fixture - Vector2(0, .64), fixture - Vector2(0, .22), Color("615851"), .04)
			draw_colored_polygon(PackedVector2Array([fixture + Vector2(-.29,-.07), fixture + Vector2(-.09,-.24),
				fixture + Vector2(.09,-.24), fixture + Vector2(.29,-.07)]), brass)
			draw_circle(fixture - Vector2(0, .04), .105, Color("846a55").lerp(bulb.lightened(.4), .36 + indoor * .64) if board.weather.cloud_cover > .01 else bulb.lightened(.4))
			draw_line(fixture + Vector2(-.25,-.06), fixture + Vector2(.25,-.06), brass.darkened(.18), .045)
			if indoor > .015: _pool(fixture, Vector2(.88,.61), Color(bulb, indoor * .50))

func _lantern(p: Vector2, evening: float) -> void:
	draw_line(p - Vector2(0,.38), p, Color("74513f"), .045)
	if evening > .015: _pool(p, Vector2(.66,.74), Color("ffb16c", evening * .54))
	draw_rect(Rect2(p - Vector2(.12,.20), Vector2(.24,.36)), Color("c77f63").lerp(Color("ffd596"), evening))
	draw_rect(Rect2(p - Vector2(.15,.18), Vector2(.30,.046)), Color("915c4a"))
	draw_rect(Rect2(p + Vector2(-.13,.13), Vector2(.26,.045)), Color("915c4a"))
	draw_line(p + Vector2(0,.17), p + Vector2(0,.30), Color("c16b51"), .042)
