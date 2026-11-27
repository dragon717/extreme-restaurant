extends Control

const Style = preload("res://scripts/ui/style.gd")
var day = 1
var phase = "NIGHT"
var progress = 0.0
var font: Font
var icon_motion: Tween
var rainy := false
var storm := false
var daylight := 0.0:
	set(value):
		daylight = value
		queue_redraw()

func _ready() -> void:
	font = Style.font()
	custom_minimum_size = Vector2(60, 60)
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_state(value: int, mode: String, ratio: float) -> void:
	if day == value and phase == mode and is_equal_approx(progress, ratio): return
	if (phase == "DAY") != (mode == "DAY"):
		if icon_motion != null and icon_motion.is_valid(): icon_motion.kill()
		icon_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		icon_motion.tween_property(self, "daylight", 1.0 if mode == "DAY" else 0.0, .38)
	day = value
	phase = mode
	progress = ratio
	queue_redraw()

func set_weather(has_rain: bool, has_thunder: bool) -> void:
	if rainy == has_rain and storm == has_thunder: return
	rainy = has_rain
	storm = has_thunder
	queue_redraw()

const Icon = preload("res://scripts/ui/ui_icon.gd")
const PLATE = preload("res://assets/canyon/panel.webp")

func _draw() -> void:
	if font == null: return
	var center := size * 0.5
	var icon_bounds := Rect2(center - Vector2(12,23), Vector2(24,24))
	if rainy:
		draw_texture_rect_region(Icon.SHEET, icon_bounds, Icon.region("rain"), Color("ddd6ff") if storm else Color.WHITE)
	else:
		draw_texture_rect_region(Icon.SHEET, icon_bounds, Icon.region("moon"), Color(Color.WHITE, 1.0 - daylight))
		draw_texture_rect_region(Icon.SHEET, icon_bounds, Icon.region("sun"), Color(Color.WHITE, daylight))
	draw_string(font, center + Vector2(-25,18), str(day), HORIZONTAL_ALIGNMENT_CENTER, 50, 18, Style.INK)
