extends CenterContainer

const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const SECTIONS = {
	"cashier_front": "coins", "cashier": "reputation", "trophy_shop": "trophy",
	"trophy_bag": "trophy", "decor_shop": "star_outline", "purchase": "coins", "buy": "recipe", "menu": "recipe",
	"collection": "recipe", "settings": "settings", "key_settings": "keys", "handbook": "recipe", "report": "income", "report_history": "history",
	"plot_unlock": "expand", "major_event": "alert", "restart": "door", "restore_error": "lock", "config_error": "alert",
}

var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var body := VBoxContainer.new()
var header := PanelContainer.new()
var feedback := Label.new()
var preferred_width: float
var motion: Tween
var closing := false

func build(kind: String, caption: String, width: float, dismiss: Callable) -> void:
	preferred_width = width
	var accent = Style.RED if kind in ["restart", "restore_error", "config_error"] else (Style.GREEN if kind in ["cashier", "plot_unlock"] else Style.GOLD)
	add_child(panel)
	var skin = Style.surface(accent, 3)
	panel.add_theme_stylebox_override("panel", skin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	panel.add_child(stack)
	stack.add_child(header)
	var band = Style.box(Color("f1dfbf"), Color("ebc893"), 9, 12)
	header.add_theme_stylebox_override("panel", band)
	var bar := HBoxContainer.new()
	header.add_child(bar)
	var seal := PanelContainer.new()
	seal.add_theme_stylebox_override("panel", Style.box(Style.PANEL, accent.darkened(0.32), 8, 6))
	bar.add_child(seal)
	seal.add_child(Icon.make(SECTIONS.get(kind, "recipe"), accent, 22))
	var heading = Style.text(caption, 23, Color("263d40"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(heading)
	if kind not in ["report", "restore_error", "config_error"]:
		var close = Style.button("")
		close.tooltip_text = "关闭 [Esc]"
		close.custom_minimum_size = Vector2(36, 36)
		Icon.center_in(close, "close", Style.INK, 16)
		close.pressed.connect(dismiss)
		bar.add_child(close)
	stack.add_child(scroll)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inset := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + edge, 18 if edge in ["left", "right"] else 14)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	body.add_theme_constant_override("separation", 10)
	inset.add_child(body)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color", Style.RED)
	stack.add_child(feedback)
	feedback.hide()
	inset.minimum_size_changed.connect(_fit)
	resized.connect(_fit)
	_fit()
	_focus_first.call_deferred()

func animate_in(backdrop: ColorRect, backdrop_opacity: float) -> void:
	position.y = 14.0
	modulate.a = .12
	backdrop.modulate.a = backdrop_opacity
	motion = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "position:y", 0.0, .24)
	motion.tween_property(self, "modulate:a", 1.0, .20)
	motion.tween_property(backdrop, "modulate:a", 1.0, .22)

func animate_out(backdrop: ColorRect, finished: Callable) -> void:
	if motion != null and motion.is_valid(): motion.kill()
	closing = true
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motion = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	motion.tween_property(self, "position:y", 11.0, .15)
	motion.tween_property(self, "modulate:a", 0.0, .15)
	motion.tween_property(backdrop, "modulate:a", 0.0, .15)
	motion.finished.connect(finished)

func _fit() -> void:
	panel.custom_minimum_size.x = minf(preferred_width, maxf(1, size.x - 40))
	var available = maxf(40, size.y - header.get_combined_minimum_size().y - 50)
	if feedback.visible: available -= feedback.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(scroll.get_child(0).get_combined_minimum_size().y, available)

func show_error(message: String) -> void:
	feedback.text = message
	feedback.visible = not message.is_empty()
	_fit()

func _focus_first() -> void:
	if not is_inside_tree() or closing: return
	var focused = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): return
	for button in find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return
