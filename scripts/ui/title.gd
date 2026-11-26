extends Control

const Catalog = preload("res://scripts/core/catalog.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/chapter_progress.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const GAME = preload("res://scenes/main.tscn")

var menu: Control
var game
var start_button: Button
var chapter_buttons: Dictionary = {}
var options: Array = []
var completed_chapters: Array = []
var selected_chapter = Catalog.DEFAULT_CHAPTER
var testing = false

func _ready() -> void:
	if not OS.has_feature("web"):
		DisplayServer.window_set_min_size(Vector2i(1100, 720))
	testing = "--ui-test" in OS.get_cmdline_user_args()
	theme = Style.theme()
	options = Catalog.chapter_options()
	completed_chapters = Progress.completed(options, testing)
	_build_menu()
	_select_chapter(selected_chapter)

func _build_menu() -> void:
	menu = $Menu
	var chapters := $Menu/Left/Stack/Chapters
	var previous = ""
	for option in options:
		_add_chapter(chapters, option, previous)
		previous = str(option.id)
	if chapter_buttons.is_empty():
		chapters.add_child(Style.text("无法加载章节列表。", 17, Style.RED))

	start_button = $Menu/Left/Stack/Start
	start_button.pressed.connect(_start_chapter)
	$Menu/Left/Stack/Quit.pressed.connect(func(): get_tree().quit())

func _add_chapter(list: VBoxContainer, option: Dictionary, previous: String) -> void:
	var id = str(option.id)
	var button = Button.new()
	button.custom_minimum_size.y = 66
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_select_chapter.bind(id))
	list.add_child(button)
	var content = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_top = 7
	content.offset_right = -14
	content.offset_bottom = -7
	content.add_theme_constant_override("separation", 12)
	content.add_child(Icon.make("rent" if previous.is_empty() else "crowd", Style.GOLD, 25.0))
	var captions = VBoxContainer.new()
	captions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	captions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	captions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	captions.add_theme_constant_override("separation", 2)
	content.add_child(captions)
	var name_label = Style.text(str(option.name), 20, Style.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	captions.add_child(name_label)
	var summary = Style.text(str(option.summary), 14, Color("c8d1ba"))
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	captions.add_child(summary)
	var status = Icon.make("lock", Style.MUTED, 21.0)
	content.add_child(status)
	chapter_buttons[id] = {"button": button, "label": name_label, "summary": summary, "status": status, "option": option, "previous": previous}

func _chapter_locked(id: String) -> bool:
	var previous = str(chapter_buttons[id].previous)
	return not previous.is_empty() and previous not in completed_chapters

func _select_chapter(id: String) -> void:
	selected_chapter = id
	for key in chapter_buttons:
		var item = chapter_buttons[key]
		var active = key == id
		var locked = _chapter_locked(key)
		var won = key in completed_chapters
		item.button.add_theme_stylebox_override("normal", Style.box(Color("594635") if active else Color("263d42"), Color("e8af62") if active else Color("536e70"), 8, 8))
		item.button.add_theme_stylebox_override("hover", Style.box(Color("51432d") if active else Color("2c4135"), Color("e8af62") if active else Color("83a48b"), 8, 8))
		item.button.add_theme_stylebox_override("pressed", item.button.get_theme_stylebox("hover"))
		item.label.add_theme_color_override("font_color", Style.MUTED if locked else (Color("ffdfa1") if active else Style.INK))
		item.summary.text = "通关「%s」解锁" % chapter_buttons[item.previous].option.name if locked else str(item.option.summary)
		item.button.tooltip_text = str(item.label.text) + "\n" + str(item.summary.text)
		item.status.visible = locked or won
		item.status.set_glyph("lock" if locked else "check", Style.MUTED if locked else Style.GOLD)
	start_button.disabled = not chapter_buttons.has(id) or _chapter_locked(id)
	var saved = Store.read_checkpoint(Store.default_path(id, testing)) if not start_button.disabled else {}
	start_button.text = "尚未解锁" if start_button.disabled else "开始经营"
	if not saved.is_empty():
		var terminal = saved.get("last_report", {}).get("result", "") in ["WIN", "LOSE"]
		start_button.text = ("查看结算 · 第 %d 天" if terminal else "继续经营 · 第 %d 天") % int(saved.get("day", 1))

func _start_chapter() -> void:
	if game != null or not chapter_buttons.has(selected_chapter) or _chapter_locked(selected_chapter): return
	game = GAME.instantiate()
	game.chapter_id = selected_chapter
	game.return_to_title.connect(func(): _show_menu.call_deferred())
	menu.hide()
	add_child(game)

func _show_menu() -> void:
	completed_chapters = Progress.completed(options, testing)
	if game != null:
		if game.sim != null and game.sim.phase == "REPORT" and game.sim.last_report.get("result", "") == "WIN":
			for id in chapter_buttons:
				if chapter_buttons[id].previous == selected_chapter and not _chapter_locked(id):
					selected_chapter = id
					break
		remove_child(game)
		game.queue_free()
		game = null
	menu.show()
	_select_chapter(selected_chapter)
	start_button.grab_focus()
