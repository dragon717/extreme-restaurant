extends CenterContainer

const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const SECTIONS = {
	"cashier_front": "coins", "cashier": "reputation", "trophy_shop": "trophy",
	"trophy_bag": "trophy", "decor_shop": "star_outline", "purchase": "coins", "buy": "recipe", "menu": "recipe",
	"collection": "recipe", "settings": "settings", "crew_setup": "chef", "key_settings": "keys", "handbook": "recipe", "report": "income", "report_history": "history",
	"plot_unlock": "expand", "major_event": "alert", "restart": "door", "restore_error": "lock", "config_error": "alert",
}

@onready var panel: PanelContainer = %Plate
@onready var scroll: ScrollContainer = %Scroll
@onready var body: VBoxContainer = %Body
@onready var header: MarginContainer = %Header
@onready var feedback: Label = %Feedback
var preferred_width: float
var motion: Tween
var closing := false
var show_art_motion := false

func build(kind: String, caption: String, width: float, dismiss: Callable) -> void:
	theme = Style.list_theme()
	preferred_width = width
	show_art_motion = kind in ["report", "major_event"]
	var accent := Style.GOLD
	if kind in ["restart", "restore_error", "config_error"]: accent = Style.RED
	elif kind in ["cashier", "plot_unlock"]: accent = Style.GREEN
	panel.add_theme_stylebox_override("panel", Style.art_plate())
	%GoldThread.texture = Style.GOLD_THREAD
	%GoldThread.modulate.a = .64
	%Seal.add_child(Icon.make(SECTIONS.get(kind, "recipe"), accent, 26))
	%Heading.text = caption
	%Heading.add_theme_font_size_override("font_size", 31 if kind in ["settings", "report", "major_event"] else 25)
	if TranslationServer.get_locale().begins_with("en"):
		%Heading.add_theme_font_override("font", Style.DISPLAY_FONT)
	%Close.visible = kind not in ["report", "restore_error", "config_error"]
	Icon.center_in(%Close, "close", Style.INK, 16)
	%Close.pressed.connect(dismiss)
	feedback.add_theme_color_override("font_color", Style.RED)
	%Inset.minimum_size_changed.connect(_fit)
	resized.connect(_fit)
	_fit()
	_focus_first.call_deferred()

func animate_in(backdrop: ColorRect, backdrop_opacity: float) -> void:
	position.y = 23.0
	modulate.a = .12
	backdrop.modulate.a = backdrop_opacity
	motion = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var settle := .38 if show_art_motion else .25
	motion.tween_property(self, "position:y", 0.0, settle).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "modulate:a", 1.0, .20)
	motion.tween_property(backdrop, "modulate:a", 1.0, .22)
	if show_art_motion: _reveal_art.call_deferred()

func _reveal_art() -> void:
	if closing or DisplayServer.get_name() == "headless": return
	var burst := Style.REVEAL.instantiate() as Node2D
	%Seal.add_child(burst)
	burst.position = Vector2(16, 22)

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
	if not is_visible_in_tree() or closing: return
	var focused = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): return
	for button in find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return
