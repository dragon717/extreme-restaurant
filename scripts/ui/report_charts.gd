extends RefCounted

class GuestRing extends Control:
	const Style = preload("res://scripts/ui/style.gd")

	var segments: Array = []
	var arrivals := 0
	var reveal := 0.0:
		set(value):
			reveal = value
			queue_redraw()

	func _ready() -> void:
		custom_minimum_size = Vector2(138, 138)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func animate() -> void:
		create_tween().tween_property(self, "reveal", 1.0, .85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var center = size * .5
		var radius = minf(size.x, size.y) * .5 - 12
		if radius <= 0: return
		draw_circle(center, radius - 9, Color("192e33"), true, -1, true)
		draw_arc(center, radius, 0, TAU, 72, Color("3a5457"), 14, true)
		if arrivals > 0:
			var angle := 0.0
			for entry in segments:
				var span = TAU * float(entry.count) / arrivals
				var gap = minf(.032, span * .18)
				var end = minf(angle + span - gap, reveal * TAU)
				if end > angle + gap:
					draw_arc(center, radius, angle + gap - PI * .5, end - PI * .5, 72, entry.tint, 14, true)
				angle += span
		var font = Style.font()
		var amount = str(roundi(arrivals * reveal))
		var width = font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, center + Vector2(-width * .5, 2), amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Style.INK)
		width = font.get_string_size(tr("到店"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, center + Vector2(-width * .5, 23), tr("到店"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.MUTED)

class ComparisonBar extends Control:
	var today := 0.0
	var yesterday := 0.0
	var has_previous := false
	var change := Color.TRANSPARENT
	var reveal := 0.0:
		set(value):
			reveal = value
			queue_redraw()

	func _ready() -> void:
		custom_minimum_size.y = 12
		mouse_filter = Control.MOUSE_FILTER_PASS
		create_tween().tween_property(self, "reveal", 1.0, .6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var width = maxf(0, size.x - 5)
		var start = Vector2(2.5, size.y * .5)
		var current = width * today * reveal
		var prior = width * yesterday
		draw_line(start, start + Vector2(width, 0), Color("395459"), 8, true)
		if current > 0:
			draw_line(start, start + Vector2(current, 0), Color("6fa09a"), 8, true)
		if has_previous:
			if change.a > 0 and reveal > .02:
				var comparison_end = lerpf(prior, width * today, reveal)
				draw_line(start + Vector2(prior, 0), start + Vector2(comparison_end, 0), change, 8, true)
			draw_line(start + Vector2(prior, -5), start + Vector2(prior, 5), Color("f2ddbb"), 2, true)

