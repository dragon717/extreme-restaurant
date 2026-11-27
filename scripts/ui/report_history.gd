extends VBoxContainer

const Style = preload("res://scripts/ui/style.gd")
const REPORT_PANEL = preload("res://scenes/ui/report_panel.tscn")
const METRICS = [
	{"title": "营收", "tint": Color("ebba79")},
	{"title": "午夜前完餐率", "tint": Color("9dd9b9")},
	{"title": "平均等餐", "tint": Color("bac6f0")},
]

var reports: Array
var catalog: Dictionary
var day_index := 0
var metric := 0
var graph: Trend
var value: Label
var day_picker: OptionButton
var previous_button: Button
var next_button: Button
var detail: VBoxContainer
var tabs: Array[Button] = []

func populate(history: Array, definitions: Dictionary) -> void:
	reports = history.duplicate()
	catalog = definitions
	add_theme_constant_override("separation", 12)
	var card = Style.card()
	card.add_theme_stylebox_override("panel", Style.inset(10,8))
	add_child(card)
	var block = VBoxContainer.new()
	block.add_theme_constant_override("separation", 9)
	card.add_child(block)
	var controls = HBoxContainer.new()
	block.add_child(controls)
	var buttons = ButtonGroup.new()
	for i in range(METRICS.size()):
		var button = Style.button(METRICS[i].title)
		button.custom_minimum_size.y = 30
		button.toggle_mode = true
		button.button_group = buttons
		button.pressed.connect(_select_metric.bind(i))
		controls.add_child(button)
		tabs.append(button)
	var spacer = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	value = Style.text("", 22, Style.GOLD)
	var navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 5)
	controls.add_child(navigation)
	previous_button = Style.button("‹")
	previous_button.accessibility_name = tr("前一天")
	previous_button.tooltip_text = tr("前一天")
	previous_button.pressed.connect(func(): _select_day(day_index - 1))
	navigation.add_child(previous_button)
	day_picker = OptionButton.new()
	day_picker.name = "ReportDay"
	day_picker.custom_minimum_size.x = 165
	day_picker.add_theme_stylebox_override("normal", Style.inset(7,6))
	for report in reports:
		day_picker.add_item(tr("第 %d 天 · 经营明细") % int(report.day))
	day_picker.item_selected.connect(_select_day)
	navigation.add_child(day_picker)
	next_button = Style.button("›")
	next_button.accessibility_name = tr("后一天")
	next_button.tooltip_text = tr("后一天")
	next_button.pressed.connect(func(): _select_day(day_index + 1))
	navigation.add_child(next_button)
	value.custom_minimum_size.x = 108
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(value)
	graph = Trend.new()
	graph.name = "HistoryTrend"
	graph.reports = reports
	graph.day_picked.connect(_select_day)
	block.add_child(graph)
	detail = VBoxContainer.new()
	add_child(detail)
	_select_metric(0)
	_select_day(reports.size() - 1)

func _select_metric(index: int) -> void:
	metric = index
	for i in range(tabs.size()): tabs[i].set_pressed_no_signal(i == index)
	graph.set_metric(index)
	_refresh_value()

func _select_day(index: int) -> void:
	if index < 0 or index >= reports.size(): return
	day_index = index
	graph.selected = index
	graph.queue_redraw()
	day_picker.select(index)
	previous_button.disabled = index == 0
	next_button.disabled = index == reports.size() - 1
	_refresh_value()
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	var panel = REPORT_PANEL.instantiate()
	panel.name = "ArchivedReport"
	detail.add_child(panel)
	var previous = reports[index - 1] if index > 0 else {}
	panel.populate(reports[index], previous, catalog, [], "", true)

func _refresh_value() -> void:
	value.text = Trend.format_value(Trend.sample(reports[day_index], metric), metric)
	value.add_theme_color_override("font_color", METRICS[metric].tint)

class Trend extends Control:
	signal day_picked(index: int)
	var reports: Array
	var metric := 0
	var selected := 0
	var hovered := -1
	var amplitude := 1.0
	var points: Array = []
	var animation: Tween
	var reveal := 1.0:
		set(progress):
			reveal = progress
			queue_redraw()

	func _ready() -> void:
		custom_minimum_size.y = 125
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_exited.connect(func():
			hovered = -1
			queue_redraw()
		)

	static func sample(report: Dictionary, index: int):
		match index:
			0: return float(report.income)
			1: return 100.0 * int(report.get("completed_before_midnight", report.completed)) / maxi(1, int(report.planned))
			2:
				var waits = report.get("food_wait_summary", {})
				if int(waits.get("count", 0)) > 0: return float(waits.average)
		return null

	static func format_value(amount, index: int) -> String:
		if amount == null: return TranslationServer.translate("暂无记录")
		match index:
			0: return "%d$" % roundi(amount)
			1: return "%.1f%%" % amount
			_: return TranslationServer.translate("%.1f 秒") % amount

	func set_metric(index: int) -> void:
		metric = index
		points.clear()
		amplitude = 100.0 if metric == 1 else 1.0
		for report in reports:
			var amount = sample(report, metric)
			points.append(amount)
			if amount != null: amplitude = maxf(amplitude, amount * 1.14 if metric != 1 else amount)
		if is_instance_valid(animation) and animation.is_valid(): animation.kill()
		reveal = .12
		animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		animation.tween_property(self, "reveal", 1.0, .46)

	func _area() -> Rect2:
		return Rect2(Vector2(50, 8), Vector2(maxf(1, size.x - 71), maxf(1, size.y - 32)))

	func _x(area: Rect2, index: int) -> float:
		return area.get_center().x if points.size() == 1 else area.position.x + area.size.x * index / float(points.size() - 1)

	func _gui_input(event: InputEvent) -> void:
		if points.is_empty(): return
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
			var area = _area()
			var index = clampi(roundi((event.position.x - area.position.x) / area.size.x * (points.size() - 1)), 0, points.size() - 1)
			hovered = index
			tooltip_text = tr("第 %d 天 · %s") % [int(reports[index].day), format_value(points[index], metric)]
			queue_redraw()
			if event is InputEventMouseButton:
				day_picked.emit(index)
				accept_event()

	func _draw() -> void:
		if points.is_empty(): return
		var area = _area()
		var font = Style.font()
		var tint = METRICS[metric].tint
		draw_rect(area, Color("1e353b"))
		for i in range(3):
			var fraction = .5 * i
			var y = area.end.y - area.size.y * fraction
			draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color("40595e"), 1)
			var caption = format_value(amplitude * fraction, metric)
			draw_string(font, Vector2(area.position.x - 5 - font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, y + 4), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Style.MUTED)
		if hovered >= 0 and hovered != selected:
			var x = _x(area, hovered)
			draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(tint, .5), 1)
		var ruler = _x(area, selected)
		draw_line(Vector2(ruler, area.position.y), Vector2(ruler, area.end.y), Color(tint, .6), 2)
		var skip = maxi(1, ceili(points.size() / 8.0))
		var prior: Variant = null
		for i in range(points.size()):
			var x = _x(area, i)
			if (i % skip == 0 and i < points.size() - skip) or i == points.size() - 1:
				draw_string(font, Vector2(x - 7, area.end.y + 17), str(int(reports[i].day)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint if i == selected else Style.MUTED)
			if points[i] == null:
				prior = null
				continue
			var point = Vector2(x, area.end.y - area.size.y * minf(1.0, points[i] / amplitude) * reveal)
			if prior != null:
				draw_colored_polygon(PackedVector2Array([prior, point, Vector2(point.x, area.end.y), Vector2(prior.x, area.end.y)]), Color(tint, .12))
				draw_line(prior, point, tint, 2.1, true)
			if i == selected or i == hovered or prior == null:
				draw_circle(point, 4.4 if i == selected else 3.0, tint, true, -1, true)
			prior = point
