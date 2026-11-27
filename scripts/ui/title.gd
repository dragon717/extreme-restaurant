extends Control

const Catalog = preload("res://scripts/core/catalog.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/chapter_progress.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const GAME = preload("res://scenes/main.tscn")
const CREW_SELECT = preload("res://scenes/ui/crew_select.tscn")
const MODAL_FRAME = preload("res://scenes/ui/modal_frame.tscn")
const CHAPTER_ROW = preload("res://scenes/ui/chapter_row.tscn")
const TITLE_SERIF = preload("res://assets/fonts/CanyonTitleSerif.ttf")
const UNCIAL = preload("res://assets/fonts/UncialAntiqua-Regular.ttf")
const LANGUAGE_PATH = "user://language.cfg"

@onready var register: Control = $RegistryViewport/Register
@onready var page: SubViewport = $RegistryViewport
var register_enabled := false
var register_pointer := false
const PAGE_INK := Color("302924")
const PAGE_MUTED := Color("61584c")
const PAGE_RUST := Color("763d25")
var slot_index := -1
var register_section := "ServicePage"
const REGISTER_TABS := {"ServiceTab":"ServicePage","ChaptersTab":"ChapterPage","More":"Options"}
var menu: Control
var crew_layer: CanvasLayer
var crew_opener: BaseButton
var game
var chapter_panel := false
var starting := false
var last_slot := {}
var selected_save := ""
var pending_crew: Array = []
var pending_helpers := {}
var slots: Array = []
var door_is_open := true
var place_opener: Control
var place_layer: CanvasLayer
var start_button: Button
var language_button: Button
var chapter_buttons: Dictionary = {}
var options: Array = []
var completed_chapters: Array = []
var selected_chapter = Catalog.DEFAULT_CHAPTER
var testing = false

func _ready() -> void:
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		DisplayServer.window_set_min_size(Vector2i(1100, 720))
	testing = "--ui-test" in OS.get_cmdline_user_args()
	_load_language()
	get_window().focus_exited.connect(_release_page)
	theme = Style.list_theme()
	options = Catalog.chapter_options()
	completed_chapters = Progress.completed(options, testing)
	_build_menu()
	_select_chapter(selected_chapter)
	Input.joy_connection_changed.connect(_on_joy_connection)
	$Menu/CanyonHub.selected.connect(_select_place)
	$Menu/CanyonHub.at_door.connect(_at_door)
	$Menu/CanyonHub.door_tapped.connect(_toggle_door)
	$Menu/CanyonHub.door_crossed.connect(_launch_game)
	$Menu/CanyonHub.march_ended.connect(func(): $Menu/ArrivalControls.hide())
	$Menu/ArrivalControls/Skip.pressed.connect($Menu/CanyonHub.end_procession)
	$Menu/ArrivalControls/Rate.pressed.connect(_march_rate)
	for command in $Menu/ArrivalControls.get_children():
		command.add_theme_stylebox_override("normal",Style.surface(Style.GOLD,9))
		command.add_theme_font_size_override("font_size",19)
	register.get_node("%BackToCanyon").pressed.connect(_show_canyon)
	_show_canyon()

func _build_menu() -> void:
	menu = $Menu
	register.theme = Style.list_theme()
	register.theme.set_color("font_color","Label",PAGE_INK)
	for state in ["font_color","font_pressed_color","font_hover_color","font_focus_color"]:
		register.theme.set_color(state,"Button",PAGE_INK if state=="font_color" else PAGE_RUST)
	register.theme.set_color("font_disabled_color","Button",PAGE_MUTED)
	if $Menu/CanyonHub.model != null: $Menu/CanyonHub.model.install_register(page.get_texture())
	var chapters: VBoxContainer = register.get_node("%Chapters")
	var previous = ""
	for option in options:
		_add_chapter(chapters, option, previous)
		previous = str(option.id)
	if chapter_buttons.is_empty():
		chapters.add_child(Style.text("无法加载章节列表。", 17, Style.RED))

	start_button = register.get_node("%Start")
	start_button.add_theme_stylebox_override("normal",Style.inset(4,8))
	for state in ["hover","pressed","focus"]:
		var ink_wash := Style.wash(.16,4,8)
		ink_wash.modulate_color = Color(.51,.30,.16,.19 if state=="focus" else .12)
		start_button.add_theme_stylebox_override(state,ink_wash)
	for state in ["font_color","font_focus_color","font_hover_color","font_pressed_color"]:
		start_button.add_theme_color_override(state,PAGE_RUST)
	start_button.pressed.connect(_start_chapter)
	register.get_node("%NewRun").pressed.connect(func(): _choose_crew(false,register.get_node("%NewRun")))
	register.get_node("%Previous").pressed.connect(_cycle_save.bind(-1))
	register.get_node("%Next").pressed.connect(_cycle_save.bind(1))
	register.get_node("%DoorToggle").pressed.connect(_toggle_door)
	language_button = register.get_node("%Language")
	language_button.pressed.connect(_toggle_language)
	register.get_node("%ServiceTab").pressed.connect(_set_section.bind("ServicePage"))
	register.get_node("%ChaptersTab").pressed.connect(_set_section.bind("ChapterPage"))
	register.get_node("%More").pressed.connect(_set_section.bind("Options"))
	var quit_button := register.get_node("%Quit") as Button
	quit_button.visible = not OS.has_feature("web")
	quit_button.pressed.connect(func(): get_tree().quit())
	register.get_node("%CrewGroups").pressed.connect(func(): _choose_crew(true,register.get_node("%CrewGroups")))
	_refresh_language()

func _load_language() -> void:
	if testing or "--language" in OS.get_cmdline_args() or "-l" in OS.get_cmdline_args(): return
	var preferences := ConfigFile.new()
	if preferences.load(LANGUAGE_PATH) == OK:
		var locale := str(preferences.get_value("game", "language", "zh_CN"))
		if locale in ["zh_CN", "en"]: TranslationServer.set_locale(locale)

func _toggle_language() -> void:
	var locale := "zh_CN" if _english() else "en"
	TranslationServer.set_locale(locale)
	if not testing:
		var preferences := ConfigFile.new()
		preferences.set_value("game", "language", locale)
		preferences.save(LANGUAGE_PATH)
	_refresh_language()
	_select_chapter(selected_chapter)

func _english() -> bool:
	return TranslationServer.get_locale().begins_with("en")

func _refresh_language() -> void:
	var english := _english()
	get_window().title = tr("峡谷餐厅")
	var heading := register.get_node("%Heading") as Label
	heading.text = tr("营业簿")
	heading.add_theme_font_override("font", UNCIAL if english else TITLE_SERIF)
	for label in ["CoverName","SlotText","ChapterHeading","OptionsHeading"]:
		register.get_node("%"+label).add_theme_font_override("font",Style.font() if english else TITLE_SERIF)
	language_button.text = "简体中文" if english else "English"
	language_button.tooltip_text = tr("切换游戏语言")
	_refresh_controls()

func _on_joy_connection(_device: int, _connected: bool) -> void:
	_refresh_controls()

func _refresh_controls() -> void:
	var joypads := Input.get_connected_joypads()
	var hint := tr("方向键选项 · Enter 确认")
	if not joypads.is_empty():
		var name := Input.get_joy_name(joypads[0]).to_lower()
		var confirm := "✕" if "playstation" in name or "dualshock" in name or "dualsense" in name or "ps4" in name or "ps5" in name else "A"
		hint = tr("方向键选项 · %s 确认") % confirm
	elif DisplayServer.is_touchscreen_available():
		hint = tr("点按选择")
	register.get_node("%Controls").text = hint

func _add_chapter(list: VBoxContainer, option: Dictionary, previous: String) -> void:
	var id := str(option.id)
	var button := CHAPTER_ROW.instantiate() as Button
	button.pressed.connect(func():
		_select_chapter(id)
		if not _chapter_locked(id): _set_section("ServicePage")
	)
	list.add_child(button)
	button.custom_minimum_size.y = 95
	button.get_node("%Heading").add_theme_font_size_override("font_size",31)
	button.get_node("%Summary").add_theme_font_size_override("font_size",20)
	button.get_node("%Emblem").add_child(Icon.make("rent" if previous.is_empty() else "crowd", PAGE_RUST, 25.0))
	var status = Icon.make("lock", PAGE_MUTED, 21.0)
	button.get_node("%Status").add_child(status)
	chapter_buttons[id] = {
		"button": button, "label": button.get_node("%Heading"), "summary": button.get_node("%Summary"),
		"status": status, "option": option, "previous": previous
	}

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
		Style.quiet_button(item.button,active)
		item.label.add_theme_color_override("font_color", PAGE_MUTED if locked else (PAGE_RUST if active else PAGE_INK))
		item.summary.add_theme_color_override("font_color",PAGE_MUTED)
		item.label.text = tr(str(item.option.name))
		item.summary.text = tr("通关「%s」解锁") % tr(str(chapter_buttons[item.previous].option.name)) if locked else tr(str(item.option.summary))
		item.button.tooltip_text = item.label.text + "\n" + item.summary.text
		item.status.visible = locked or won
		item.status.set_glyph("lock" if locked else "check", PAGE_MUTED if locked else PAGE_RUST)
	start_button.disabled = not chapter_buttons.has(id) or _chapter_locked(id)
	var current: Dictionary = chapter_buttons[id].option
	var ordinal: int = options.find_custom(func(entry): return entry.id==id)+1
	register.get_node("%ChapterNumber").text = tr("第 %d 章") % ordinal
	var heading := register.get_node("%CoverName") as Label
	heading.text = tr(str(current.name))
	var measured := heading.get_theme_font("font").get_string_size(heading.text,HORIZONTAL_ALIGNMENT_LEFT,-1,54).x
	heading.add_theme_font_size_override("font_size",mini(54,floori(54.*521./maxf(1.,measured))))
	register.get_node("%CoverSummary").text = tr(str(current.summary))
	slots = [] if _chapter_locked(id) else Store.chapter_slots(id,testing)
	register.get_node("%SlotRow").visible = not slots.is_empty()
	start_button.offset_top = 248. if slots.is_empty() else 365.
	start_button.offset_bottom = start_button.offset_top+72.
	register.get_node("%ActionRule").offset_top = start_button.offset_bottom
	register.get_node("%ActionRule").offset_bottom = start_button.offset_bottom+3.
	var first := slots.find_custom(func(slot): return slot.valid and slot.path == last_slot.get(id,""))
	if first < 0: first = slots.find_custom(func(slot): return slot.valid)
	_select_save(first)

func _cycle_save(direction: int) -> void:
	if slots.is_empty(): return
	_select_save(posmod(slot_index+direction,slots.size()))

func _select_save(index: int) -> void:
	slot_index = index
	register.get_node("%Previous").visible = slots.size() > 1
	register.get_node("%Next").visible = slots.size() > 1
	if index >= 0 and index < slots.size():
		var slot: Dictionary = slots[index]
		register.get_node("%SlotCaption").text = tr("存档 %d") % maxi(1,slot.number)
		register.get_node("%SlotText").text = tr("第 %d 天") % slot.day if slot.valid else tr("存档无法读取")
	var locked := _chapter_locked(selected_chapter)
	selected_save = str(slots[index].path) if index >= 0 and index < slots.size() and slots[index].valid else ""
	if not selected_save.is_empty(): last_slot[selected_chapter] = selected_save
	var saved := Store.read_checkpoint(selected_save) if not selected_save.is_empty() else {}
	var catalog := Catalog.load_all(selected_chapter)
	if catalog.chapter.has("initial_layout"):
		var preview = preload("res://scripts/core/simulation.gd").new(catalog)
		if not saved.is_empty(): preview.restore_state(saved)
		$Menu/CanyonHub.show_layout(preview.layout)
		$Menu/CanyonHub.preview_workers(preview)
	if not locked:
		$Soundtrack.set_day(int(saved.get("day",1)))
		if $Menu/CanyonHub.model != null:
			$Menu/CanyonHub.model.set_day(int(saved.get("day",1)))
			$Menu/CanyonHub.model.light_at(24. if saved.get("phase","NIGHT") == "REPORT" else 22.,0,0,1)
	start_button.disabled = locked or (not slots.is_empty() and selected_save.is_empty())
	start_button.text = tr("尚未解锁") if locked else tr("新开游戏")
	if not saved.is_empty():
		start_button.text = tr("查看结算" if saved.get("last_report",{}).get("result","") in ["WIN","LOSE"] else "继续经营")
	register.get_node("%NewRun").visible = not locked and not slots.is_empty()

func _show_canyon() -> void:
	$Menu/ArrivalControls.hide()
	_release_page()
	register_enabled = false
	register_pointer = false
	chapter_panel = false
	starting = false
	$Menu/CanyonHub.back_to_map()


func _select_place(id: String) -> void:
	if crew_layer != null or place_layer != null: return
	if starting or chapter_panel: return
	if id == "tavern":
		chapter_panel = true
		$Menu/CanyonHub.approach()
		return
	if id == "freight":
		_choose_crew(true,$Menu/CanyonHub/Places/freight)
		return
	var details = {"supply":"采购小厅开放后，可在这里购买菜谱和营业增益。","workshop":"装饰工坊开放后，可在这里购买餐厅陈设。","gallery":"展廊开放后，可在这里用金币开启海克斯奖杯盲盒。","dock":"来客从东岸出发，过木桥，经前场进入餐厅。"}
	place_opener = $Menu/CanyonHub/Places.get_node(id)
	$Menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	place_layer = CanvasLayer.new()
	place_layer.layer = 16
	add_child(place_layer)
	var shade := ColorRect.new()
	shade.color = Color("101820",.44)
	place_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := MODAL_FRAME.instantiate()
	frame.theme = theme
	place_layer.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.build(id,tr($Menu/CanyonHub.Plan.LABELS[id]),480,_close_place)
	frame.body.add_child(Style.text(tr(details[id]),17,Style.INK,true))
	var back := Style.button(tr("返回峡谷"),true)
	frame.body.add_child(back)
	back.pressed.connect(_close_place)
	back.grab_focus()

func _close_place() -> void:
	if place_layer != null:
		place_layer.queue_free()
		place_layer = null
	$Menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_show_canyon()
	if is_instance_valid(place_opener): place_opener.grab_focus()

func _set_section(section: String) -> void:
	var changed := section != register_section
	register_section = section
	for key in ["ServicePage","ChapterPage","Options"]:
		register.get_node("%"+key).visible = (key==section)
	for key in REGISTER_TABS:
		var tab := register.get_node("%"+key) as Button
		var target: String = REGISTER_TABS[key]
		var selected := target==section
		Style.quiet_button(tab)
		tab.get_node("Current").visible = selected
		tab.add_theme_color_override("font_color",PAGE_RUST if selected else PAGE_MUTED)
		tab.add_theme_color_override("font_hover_color",PAGE_RUST)
		tab.add_theme_color_override("font_focus_color",PAGE_RUST)
	if changed and register_enabled:
		var stage = $Menu/CanyonHub.model
		if stage != null: stage.board.riffle()
		if section=="ServicePage": _focus_start()
		elif section=="ChapterPage" and chapter_buttons.has(selected_chapter): chapter_buttons[selected_chapter].button.grab_focus()
		else: register.get_node("%DoorToggle").grab_focus()

func _toggle_door() -> void:
	if not chapter_panel or starting or crew_layer != null: return
	door_is_open = not door_is_open
	$Menu/CanyonHub.preview_open(door_is_open)
	register.get_node("%DoorToggle").text = tr("合上店门") if door_is_open else tr("推开店门")

func _at_door() -> void:
	if not chapter_panel or starting: return
	_set_section("ServicePage")
	door_is_open = true
	register.get_node("%DoorToggle").text = tr("合上店门")
	register_enabled = true
	_focus_start()

func _start_chapter() -> void:
	if game != null or crew_layer != null or not chapter_buttons.has(selected_chapter) or _chapter_locked(selected_chapter): return
	if not chapter_panel or not register_enabled or starting: return
	if selected_save.is_empty():
		_choose_crew(false, start_button)
	else:
		_enter_chapter([])

func _choose_crew(manage: bool, opener: BaseButton) -> void:
	_release_page()
	if crew_layer != null or starting or (not manage and _chapter_locked(selected_chapter)): return
	crew_opener = opener
	$Menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	register_enabled = false
	crew_layer = CanvasLayer.new()
	crew_layer.layer = 16
	add_child(crew_layer)
	var shade := ColorRect.new()
	shade.color = Color("0a1219", .74)
	crew_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if manage:
		var frame := MODAL_FRAME.instantiate()
		frame.theme = theme
		crew_layer.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.build("crew_setup",tr("阵容分组"),810,_leave_crew)
		var editor := CREW_SELECT.instantiate()
		editor.management_only = true
		frame.body.add_child(editor)
		editor.cancelled.connect(_leave_crew)
		frame.animate_in(shade,0.0)
	else:
		var draft := preload("res://scenes/ui/opening_draft.tscn").instantiate()
		draft.chapter_caption = tr(str(chapter_buttons[selected_chapter].option.name))
		crew_layer.add_child(draft)
		draft.cancelled.connect(_leave_crew)
		draft.accepted.connect(func(lineup): _enter_chapter(lineup,draft.helper_staff))

func _leave_crew() -> void:
	if crew_layer == null: return
	crew_layer.queue_free()
	crew_layer = null
	$Menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	register_enabled = chapter_panel and not starting
	if is_instance_valid(crew_opener): crew_opener.grab_focus()
	crew_opener = null

# Forward through the physical sign. SubViewport owns its text layout and focus;
# these events are dispatched only when the ray intersects the printed face.
func _release_page() -> void:
	var stage = $Menu/CanyonHub.model
	if stage != null and is_instance_valid(stage.board): stage.board.release_grip()
	register_pointer = false

func _input(event: InputEvent) -> void:
	if starting and $Menu/CanyonHub.marching:
		if event.is_action_pressed("ui_cancel"):
			$Menu/CanyonHub.end_procession()
			get_viewport().set_input_as_handled()
		return
	if not register_enabled or crew_layer != null or place_layer != null or game != null: return
	var translated_event := event.duplicate() as InputEvent
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		var stage = $Menu/CanyonHub.model
		if stage == null: return
		if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
		if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT: return
		var id: int = event.index if event is InputEventScreenTouch or event is InputEventScreenDrag else -1
		var contact: bool = event is InputEventMouseButton or event is InputEventScreenTouch
		if stage.board.grip >= 0:
			if stage.board.pointer_id == id:
				if contact and not event.pressed: stage.board.release_grip()
				elif not contact: stage.drag_register(event.position)
			get_viewport().set_input_as_handled()
			return
		var pixel: Vector2 = stage.register_pixel(event.position)
		var inside := Rect2(Vector2.ZERO,Vector2(page.size)).has_point(pixel)
		if not inside and not register_pointer: return
		if contact and event.pressed and inside:
			if stage.board.can_grip(pixel):
				stage.board.grasp(pixel,id)
				get_viewport().set_input_as_handled()
				return
			stage.board.press_ink(pixel)
		if event is InputEventScreenTouch:
			var tap := InputEventMouseButton.new()
			tap.button_index = MOUSE_BUTTON_LEFT
			tap.pressed = event.pressed
			translated_event = tap
		elif event is InputEventScreenDrag:
			translated_event = InputEventMouseMotion.new()
		if translated_event is InputEventMouseButton and translated_event.pressed:
			var motion := InputEventMouseMotion.new()
			motion.position = pixel
			motion.global_position = pixel
			page.push_input(motion,true)
		translated_event.position = pixel
		if translated_event is InputEventMouse: translated_event.global_position = pixel
		if event is InputEventMouseButton or event is InputEventScreenTouch: register_pointer = event.pressed
	elif not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion): return
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index==JOY_BUTTON_B): return
	page.push_input(translated_event,true)
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if game != null or starting: return
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		if crew_layer != null: _leave_crew()
		elif register_enabled and register_section!="ServicePage": _set_section("ServicePage")
		elif place_layer != null: _close_place()
		elif chapter_panel: _show_canyon()
		else: return
		get_viewport().set_input_as_handled()

func _enter_chapter(lineup: Array,helpers: Dictionary = {}) -> void:
	_release_page()
	if starting or _chapter_locked(selected_chapter): return
	if lineup.is_empty() and selected_save.is_empty(): return
	starting = true
	pending_crew = lineup.duplicate(true)
	pending_helpers = helpers.duplicate(true)
	if not lineup.is_empty():
		var preview = preload("res://scripts/core/simulation.gd").new(Catalog.load_all(selected_chapter))
		preview.set_crew(lineup)
		preview.helper_staff = pending_helpers.duplicate(true)
		$Menu/CanyonHub.show_layout(preview.layout)
		$Menu/CanyonHub.preview_workers(preview)
		if $Menu/CanyonHub.model != null: $Menu/CanyonHub.model.set_day(1)
	_leave_crew()
	register_enabled = false
	$Menu/ArrivalControls.visible = not lineup.is_empty() and $Menu/CanyonHub.model!=null
	$Menu/ArrivalControls/Rate.text=tr("加速 ×3")
	$Menu/CanyonHub.enter(not lineup.is_empty())
	if $Menu/ArrivalControls.visible:
		$Menu/ArrivalControls/Rate.focus_neighbor_right = $Menu/ArrivalControls/Rate.get_path_to($Menu/ArrivalControls/Skip)
		$Menu/ArrivalControls/Skip.focus_neighbor_left = $Menu/ArrivalControls/Skip.get_path_to($Menu/ArrivalControls/Rate)
		$Menu/ArrivalControls/Rate.grab_focus()

func _march_rate() -> void:
	var hub=$Menu/CanyonHub
	if not hub.marching: return
	hub.march.rate = 3. if hub.march.rate==1. else 1.
	$Menu/ArrivalControls/Rate.text=tr("恢复原速") if hub.march.rate==3. else tr("加速 ×3")

func _launch_game() -> void:
	if not starting or game != null: return
	game = GAME.instantiate()
	game.soundtrack = $Soundtrack
	game.chapter_id = selected_chapter
	game.starting_crew = pending_crew
	game.starting_helpers = pending_helpers
	game.save_path = selected_save if pending_crew.is_empty() else Store.new_slot(selected_chapter,testing)
	last_slot[selected_chapter] = game.save_path
	game.arrive_from_hub = not $Menu/CanyonHub.arrived_overhead
	game.entry_actors = $Menu/CanyonHub.take_workers()
	game.entry_stage = $Menu/CanyonHub.take_stage()
	game.entry_atmosphere = $Menu/CanyonHub.take_atmosphere()
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
		var stage = game.world.release_stage() if game.world != null else game.entry_stage
		if stage != null: $Menu/CanyonHub.attach_stage(stage)
		$Menu/CanyonHub.restore_atmosphere(game.world.release_atmosphere() if game.world != null else game.entry_atmosphere)
		remove_child(game)
		game.queue_free()
		game = null
	menu.show()
	$Menu/CanyonHub.door_mix = 0.
	$Menu/CanyonHub.aperture = 0.
	$Menu/CanyonHub.overview_mix = 1.
	$Menu/CanyonHub.target_mix = 1.
	_select_chapter(selected_chapter)
	_show_canyon()

func _focus_start() -> void:
	if start_button.disabled and chapter_buttons.has(selected_chapter):
		chapter_buttons[selected_chapter].button.grab_focus()
	else:
		start_button.grab_focus()
