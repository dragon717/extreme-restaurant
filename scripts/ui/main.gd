extends Control

const Actor = preload("res://scripts/visuals/actor_view.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const SeasonalMusic = preload("res://scripts/audio/seasonal_music.gd")
const Catalog = preload("res://scripts/core/catalog.gd")
const Store = preload("res://scripts/core/save_store.gd")
const ChapterProgress = preload("res://scripts/core/chapter_progress.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Decor = preload("res://scripts/core/decoration_effects.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const World = preload("res://scripts/ui/world_view.gd")
const DayBadge = preload("res://scripts/ui/day_badge.gd")
const HUB = preload("res://scenes/ui/service_hub.tscn")
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
const MODAL_FRAME = preload("res://scenes/ui/modal_frame.tscn")
const CREW_SELECT = preload("res://scenes/ui/crew_select.tscn")
const PAUSE_MENU = preload("res://scenes/ui/pause_menu.tscn")
const REPORT_PANEL = preload("res://scenes/ui/report_panel.tscn")
const EVENT_PANEL = preload("res://scenes/ui/major_event_panel.tscn")
const ServiceFeedback = preload("res://scripts/ui/service_feedback.gd")
const Guide = preload("res://scripts/ui/restaurant_guide.gd")
const ReportPanel = preload("res://scripts/ui/report_panel.gd")
const ReportHistory = preload("res://scripts/ui/report_history.gd")
const GuestProfile = preload("res://scripts/ui/guest_profile.gd")
const MajorEventPanel = preload("res://scripts/ui/major_event_panel.gd")
const KeyBindings = preload("res://scripts/ui/key_bindings.gd")
const BuildCatalog = preload("res://scripts/ui/build_catalog.gd")
const GamepadCursor = preload("res://scripts/ui/gamepad_cursor.gd")
const Trophies = preload("res://scripts/core/trophies.gd")
const TrophyArt = preload("res://scripts/visuals/trophy_art.gd")
const TrophyBox = preload("res://scripts/ui/trophy_box.gd")
const ManagementCard = preload("res://scripts/ui/management_card.gd")

signal return_to_title

var chapter_id = Catalog.DEFAULT_CHAPTER
var starting_crew: Array = []
var starting_helpers := {}
var arrive_from_hub := false
var entry_stage: SubViewportContainer
var entry_actors := {}
var entry_atmosphere := {}
var landmark_context := ""
var sim:
	set(value):
		if sim == value: return
		if sim != null:
			sim.payment_received.disconnect(_on_guest_payment)
			sim.guest_moment.disconnect(_on_guest_moment)
		sim = value
		if sim != null:
			sim.payment_received.connect(_on_guest_payment)
			sim.guest_moment.connect(_on_guest_moment)
var world
var gamepad: Node2D
var soundtrack: SeasonalMusic
var service_feedback
var ui: Dictionary = {}
var accumulator = 0.0
var refresh_timer = 0.0
var opening_check_revision := -1
var opening_issue := ""
var status_timer = 0.0
var fast_forward = false
var report_shown_day = -1
var modal_layer: CanvasLayer
var modal_kind = ""
var modal_frame
var trophy_box: TrophyBox
var modal_opener: Control
var fading_modal: CanvasLayer
var save_path = ""
var testing = false
var inspected: Dictionary = {}
var guide
var tutorial_path := ""
var keys
var binding_action := ""
var binding_buttons: Dictionary = {}
var major_notice: Dictionary = {}
var major_notice_state := ""
var major_notice_pulse: Tween
var pending_major_event := ""
var major_event_delay := 0.0
const MAJOR_EVENT_DELAY := 3.0
const SPECIAL_NOTICE_SECONDS := 4.5
const MAX_SIM_TICKS_PER_FRAME := 12
const SIM_FRAME_BUDGET_US := 4800
var special_notice_motion: Tween

func _ready() -> void:
	get_window().title = tr("峡谷餐厅")
	theme = Style.theme()
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		DisplayServer.window_set_min_size(Vector2i(1100, 720))
	sim = Sim.new(Catalog.load_all(chapter_id))
	if not sim.catalog.errors.is_empty():
		var box = _new_modal("config_error", tr("无法载入章节"), 640)
		box.add_child(Style.text("\n".join(sim.catalog.errors), 16, Style.INK, true))
		var leave = Style.button(tr("返回章节"), true)
		leave.pressed.connect(_return_to_title)
		box.add_child(leave)
		set_process(false)
		sim = null
		return
	testing = "--ui-test" in OS.get_cmdline_user_args()
	keys = KeyBindings.new(Store.default_path("keyboard_bindings", testing))
	if save_path.is_empty(): save_path = Store.default_path(chapter_id, testing)
	var saved = Store.read_checkpoint(save_path)
	var load_message = ""
	if not starting_crew.is_empty():
		sim.set_crew(starting_crew)
		sim.helper_staff=starting_helpers.duplicate(true)
	elif not saved.is_empty():
		var result = sim.restore_state(saved)
		if not result.ok: load_message = result.error
		else: load_message=Store.archive_v7(save_path,saved)
	if soundtrack == null:
		soundtrack = SeasonalMusic.new()
		add_child(soundtrack)
	_build_interface()
	var pointer_layer := CanvasLayer.new()
	pointer_layer.layer = 30
	add_child(pointer_layer)
	gamepad = GamepadCursor.new()
	pointer_layer.add_child(gamepad)
	gamepad.pointer_canceled.connect(world.cancel_drag)
	guide = Guide.new()
	add_child(guide)
	if tutorial_path.is_empty(): tutorial_path = Store.default_path("tutorial_progress", testing)
	guide.setup(self, tutorial_path)
	get_window().focus_exited.connect(_on_focus_lost)
	if load_message.is_empty(): _save()
	_refresh_all()
	if load_message.is_empty():
		if arrive_from_hub:
			ui.overlay.hide()
			world.entry_finished.connect(_begin_visit, CONNECT_ONE_SHOT)
			world.enter_from_threshold()
		else:
			_begin_visit()
	if not load_message.is_empty():
		var box = _new_modal("restore_error", tr("无法恢复旧检查点"), 650)
		box.add_child(Style.text(load_message + tr("\n旧存档不会自动迁移或覆盖。"),16,Style.MUTED,true))
		var restart = Style.button(tr("建立新局（旧档留作备份）"),true)
		restart.pressed.connect(func(): _choose_restart_crew(int(Time.get_ticks_usec() % 1000000000)))
		box.add_child(restart)
		var leave = Style.button(tr("暂不更改，返回主界面"))
		leave.pressed.connect(_return_to_title)
		box.add_child(leave)

func _begin_visit() -> void:
	ui.overlay.show()
	guide.start_visit()
	if sim.phase == "REPORT": _show_report()

func _fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _rect(control: Control, left: float, top: float, right: float, bottom: float, ax: float = 0, ay: float = 0) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom

func _icon_button(glyph: String, description: String) -> Button:
	var button = Style.button("")
	button.tooltip_text = description
	button.accessibility_name = description
	Icon.center_in(button, glyph, Style.INK, 21.0)
	return button

func _build_interface() -> void:
	world = World.new(entry_atmosphere)
	entry_atmosphere = {}
	world.sim = sim
	world.district_3d = entry_stage
	world.actors = entry_actors
	for actor in entry_actors.values(): world.add_child(actor)
	entry_actors = {}
	entry_stage = null
	add_child(world)
	_fill(world)
	world.move_requested.connect(_move_facility)
	world.wall_requested.connect(_place_wall)
	world.drag_started.connect(func():
		ui.info_panel.hide()
		_sync_build_tools()
	)
	world.inspect_requested.connect(_inspect)
	world.follow_changed.connect(_sync_follow_button)
	var hud = CanvasLayer.new()
	hud.layer = 1
	add_child(hud)
	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(overlay)
	_fill(overlay)
	overlay.theme = theme
	ui.overlay = overlay
	ui.hub = HUB.instantiate()
	overlay.add_child(ui.hub)
	ui.rent_card = Style.card()
	ui.rent_card.add_theme_stylebox_override("panel", Style.surface(Style.GREEN, 8))
	overlay.add_child(ui.rent_card)
	_rect(ui.rent_card, 14, 83, 184, 124)
	var rent_row = HBoxContainer.new()
	ui.rent_card.add_child(rent_row)
	ui.rent_label = Style.readout(rent_row, "rent", "", tr("下次房租"))
	ui.rent_days = Style.readout(rent_row, "clock", "", tr("离下次缴租的天数"), Style.MUTED, 14)
	ui.peak_card = Style.card()
	ui.peak_card.add_theme_stylebox_override("panel", Style.surface(Style.GOLD, 8))
	overlay.add_child(ui.peak_card)
	_rect(ui.peak_card, 14, 130, 216, 172)
	ui.peak_label = Style.readout(ui.peak_card, "crowd", "", tr("客流高峰"), Style.GOLD, 14)
	ui.peak_card.hide()
	ui.diagnostic_card = Style.card()
	ui.diagnostic_card.add_theme_stylebox_override("panel", Style.surface(Style.GOLD, 8))
	overlay.add_child(ui.diagnostic_card)
	_rect(ui.diagnostic_card, 14, 181, 240, 265)
	var diagnostic_body = VBoxContainer.new()
	ui.diagnostic_card.add_child(diagnostic_body)
	ui.diagnostic_label = Style.text("", 15, Style.GOLD)
	diagnostic_body.add_child(ui.diagnostic_label)
	ui.diagnostic_button = Style.button("")
	ui.diagnostic_button.pressed.connect(_dismiss_diagnostic)
	diagnostic_body.add_child(ui.diagnostic_button)
	ui.diagnostic_card.hide()
	var top_row: HBoxContainer = ui.hub.get_node("Service")
	ui.badge = DayBadge.new()
	top_row.add_child(ui.badge)
	top_row.move_child(ui.badge,0)
	var time_row := HBoxContainer.new()
	top_row.add_child(time_row)
	ui.clock = Style.readout(time_row, "clock", "09:00", "")
	ui.cleanup = Icon.make("door", Style.GOLD, 18.0)
	time_row.add_child(ui.cleanup)
	ui.cleanup.hide()
	var resources_row: HBoxContainer = ui.hub.get_node("Resources")
	ui.income_label = Style.readout(resources_row, "income", "0$", tr("今日收入"))
	ui.gold_label = Style.readout(resources_row, "coins", "0$", tr("持有金币"))
	ui.rep_label = Style.readout(resources_row, "reputation", "0", tr("声望"), Style.GREEN)
	ui.star_label = Style.readout(resources_row, "star", "0", tr("闪星 · 扩建地块和购买装饰"))
	ui.gear = _icon_button("settings", tr("设置"))
	overlay.add_child(ui.gear)
	_rect(ui.gear, -61, 14, -14, 61, 1, 0)
	ui.gear.pressed.connect(_show_settings)
	ui.shift = _icon_button("chef", tr("今日排班"))
	overlay.add_child(ui.shift)
	_rect(ui.shift, -115, 14, -68, 61, 1, 0)
	ui.shift.pressed.connect(_show_shift_roster)
	ui.history = _icon_button("history", tr("历史日报"))
	ui.history.name = "OpenReportHistory"
	overlay.add_child(ui.history)
	_rect(ui.history, -232, 14, -179, 61, 1, 0)
	ui.history.pressed.connect(_show_report_history)
	ui.district = _icon_button("district", tr("街区全景 · F 返回餐厅"))
	ui.district.name = "DistrictOverview"
	overlay.add_child(ui.district)
	_rect(ui.district, -290, 14, -237, 61, 1, 0)
	ui.district.pressed.connect(world.focus_district)
	ui.major_event = Style.button("")
	ui.major_event.name = "MajorEventNotice"
	ui.major_event.add_theme_stylebox_override("normal", Style.box(Color("953f36"), Style.GOLD, 9, 6))
	ui.major_event.add_theme_stylebox_override("hover", Style.box(Color("b15846"), Color("ffd597"), 9, 6))
	ui.major_event.add_theme_stylebox_override("pressed", Style.box(Color("7c382f"), Style.GOLD, 9, 6))
	overlay.add_child(ui.major_event)
	_rect(ui.major_event, -201, 77, -17, 133, 1, 0)
	ui.major_event.pivot_offset = Vector2(92, 28)
	ui.major_event.pressed.connect(_show_major_event)
	ui.major_event.hide()
	_build_special_notice(overlay)
	ui.fast = Style.button("8×")
	overlay.add_child(ui.fast)
	_rect(ui.fast, -174, 14, -120, 61, 1, 0)
	ui.fast.pressed.connect(_toggle_fast)
	ui.pause = Style.button("")
	ui.pause_icon = Icon.center_in(ui.pause, "pause", Style.INK, 20.0)
	overlay.add_child(ui.pause)
	_rect(ui.pause, -112, 14, -65, 61, 1, 0)
	ui.pause.pressed.connect(_toggle_pause)
	var actions: HBoxContainer = ui.hub.get_node("Actions")
	ui.roof = Style.button(tr("看屋顶"))
	ui.roof.name = "RoofView"
	ui.roof.custom_minimum_size = Vector2(68,36)
	actions.add_child(ui.roof)
	ui.roof.pressed.connect(func():
		if world.overview:
			world.focus_restaurant()
			world.set_roof_view(false)
		else:
			world.set_roof_view(not world.inspect_roof)
	)
	world.roof_view_changed.connect(func(closed): ui.roof.text = tr("看室内") if closed else tr("看屋顶"))
	for state in ["normal","hover","pressed"]:
		ui.roof.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for command: Button in [ui.district, ui.fast, ui.pause, ui.gear]:
		command.reparent(actions,false)
		command.custom_minimum_size = Vector2(39,40)
		command.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for state in ["normal","hover","pressed","disabled"]:
			command.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	_rect(ui.history, -66, 82, -18, 126, 1, 0)
	_rect(ui.shift, -120, 82, -72, 126, 1, 0)
	ui.rent_card.hide()
	ui.history.hide()
	ui.shift.hide()
	ui.open = Style.button(tr("开店"),true)
	ui.open.add_theme_font_size_override("font_size",21)
	overlay.add_child(ui.open)
	_rect(ui.open, -104, -67, 104, -19, .5, 1)
	ui.open.pressed.connect(_open_day)
	ui.skills = preload("res://scenes/service_skills.tscn").instantiate()
	overlay.add_child(ui.skills)
	_rect(ui.skills, -255, -67, 255, -19, .5, 1)
	ui.linked_fire = ui.skills.get_node("LinkedFire")
	ui.linked_fire.pressed.connect(func():
		if guide.blocks_clock or not modal_kind.is_empty(): return
		if sim.call_linked_fire(): _update_hud()
	)
	ui.rush = ui.skills.get_node("Rush")
	ui.rush.pressed.connect(func():
		if guide.blocks_clock or not modal_kind.is_empty(): return
		if sim.call_current(): _update_hud()
	)
	ui.menu = _icon_button("recipe", tr("菜谱"))
	overlay.add_child(ui.menu)
	_rect(ui.menu, -65, -67, -18, -19, 1, 1)
	ui.menu.pressed.connect(_show_menu_page)
	ui.build = _icon_button("build", tr("建造"))
	ui.build.name = "OpenBuildInventory"
	overlay.add_child(ui.build)
	_rect(ui.build, -124, -67, -77, -19, 1, 1)
	ui.build.pressed.connect(_show_build_page)
	ui.trophy_bag = _icon_button("bag", tr("奖杯背包"))
	ui.trophy_bag.name = "OpenTrophyBag"
	overlay.add_child(ui.trophy_bag)
	ui.trophy_bag.pressed.connect(_show_trophy_bag)
	ui.trophy_bag.hide()
	ui.build_catalog = BuildCatalog.new()
	ui.build_catalog.name = "BuildCatalog"
	overlay.add_child(ui.build_catalog)
	ui.build_catalog.anchor_right = 1
	ui.build_catalog.anchor_top = 1
	ui.build_catalog.anchor_bottom = 1
	ui.build_catalog.offset_left = 14
	ui.build_catalog.offset_right = -14
	ui.build_catalog.offset_top = -BuildCatalog.HEIGHT - 12
	ui.build_catalog.offset_bottom = -12
	ui.build_catalog.item_picked.connect(_pick_catalog_item)
	ui.build_catalog.closed.connect(_close_build_page)
	ui.build_catalog.hide()
	ui.toast_card = Style.card()
	ui.toast_card.add_theme_stylebox_override("panel", Style.surface(Style.GREEN, 10))
	overlay.add_child(ui.toast_card)
	_rect(ui.toast_card, 14, -77, 399, -19, 0, 1)
	ui.toast_label = Style.text("",14,Style.INK,true)
	var toast_row = HBoxContainer.new()
	ui.toast_card.add_child(toast_row)
	ui.toast_glyph = Icon.make("check", Style.GREEN, 18)
	toast_row.add_child(ui.toast_glyph)
	ui.toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_row.add_child(ui.toast_label)
	ui.toast_card.visible = false
	ui.info_panel = Style.card()
	ui.info_panel.add_theme_stylebox_override("panel",Style.surface(Style.GREEN, 15))
	overlay.add_child(ui.info_panel)
	_rect(ui.info_panel,-360,145,-18,369,1,0)
	var panel_body = VBoxContainer.new()
	ui.info_panel.add_child(panel_body)
	var info_header = HBoxContainer.new()
	panel_body.add_child(info_header)
	ui.info_title = Style.text("",20,Style.GOLD)
	ui.info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.info_glyph = Icon.make("table", Style.GREEN, 22)
	info_header.add_child(ui.info_glyph)
	info_header.add_child(ui.info_title)
	ui.info_follow = _icon_button("follow", tr("镜头跟随"))
	ui.info_follow.name = "FollowNpc"
	ui.info_follow.custom_minimum_size.x = 40
	info_header.add_child(ui.info_follow)
	ui.info_follow.pressed.connect(_follow_inspected)
	ui.info_follow.hide()
	var close = _icon_button("close", tr("关闭"))
	close.custom_minimum_size.x = 40
	close.pressed.connect(_clear_inspector)
	info_header.add_child(close)
	ui.info_body = Style.text("",15,Style.INK,true)
	ui.info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var details = ScrollContainer.new()
	details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_body.add_child(details)
	ui.info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.info_body.add_theme_constant_override("line_spacing", 4)
	var profile_body = VBoxContainer.new()
	profile_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(profile_body)
	profile_body.add_child(ui.info_body)
	ui.guest_profile = GuestProfile.new()
	profile_body.add_child(ui.guest_profile)
	ui.guest_profile.hide()
	ui.action_bar = HBoxContainer.new()
	ui.action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.action_bar.alignment = BoxContainer.ALIGNMENT_END
	ui.action_bar.add_theme_constant_override("separation", 6)
	overlay.add_child(ui.action_bar)
	_rect(ui.action_bar, -272, -119, -18, -73, 1, 1)
	for tool in [
		["move", "move", tr("移动"), _begin_move],
		["rotate", "rotate", tr("旋转"), _rotate_selection],
		["split", "split", tr("拆分餐桌"), _split_selection],
		["store", "store", tr("收起"), _store_selection],
		["cancel_placement", "close", tr("取消布置 [Esc]"), _cancel_placement],
	]:
		var button = _icon_button(tool[1], tool[2])
		button.custom_minimum_size = Vector2(44, 44)
		button.pressed.connect(tool[3])
		ui.action_bar.add_child(button)
		ui[tool[0]] = button
		button.hide()
	ui.info_panel.visible = false
	service_feedback = ServiceFeedback.new()
	service_feedback.wallet = ui.gold_label
	service_feedback.z_index = 2
	overlay.add_child(service_feedback)
	_fill(service_feedback)
	for label in [ui.income_label, ui.gold_label, ui.rep_label, ui.star_label]:
		service_feedback.attach_counter(label)

func _process(delta: float) -> void:
	if sim == null: return
	gamepad.move(delta, world)
	if status_timer > 0: status_timer -= delta
	_advance_major_event_popup(delta)
	var tick_seconds = float(sim.tick_ms) / 1000.0
	var clock_held = sim.paused or guide.blocks_clock or modal_kind in ["settings", "key_settings", "handbook", "restart", "report_history"]
	if sim.phase == "DAY" and not clock_held:
		var speed = float(sim.chapter.fast_forward_multiplier) if fast_forward else 1.0
		accumulator = minf(accumulator + delta * speed, tick_seconds * MAX_SIM_TICKS_PER_FRAME)
		var started = Time.get_ticks_usec()
		var count = 0
		while accumulator >= tick_seconds and sim.phase == "DAY" and count < MAX_SIM_TICKS_PER_FRAME:
			accumulator -= tick_seconds
			sim.step()
			guide.after_step()
			count += 1
			if guide.blocks_clock or Time.get_ticks_usec() - started >= SIM_FRAME_BUDGET_US: break
	world.set_render_clock(sim.tick, clampf(accumulator / tick_seconds, 0.0, 1.0), clock_held or guide.blocks_clock)
	if sim.phase == "REPORT" and report_shown_day != sim.day:
		_save()
		_refresh_all()
		_show_report(true)
	refresh_timer += delta
	if refresh_timer >= 0.15:
		refresh_timer = 0
		_update_hud()

func _refresh_all() -> void:
	if sim == null: return
	soundtrack.set_day(sim.day)
	ui.hub.get_node("Service/Season").text = tr(Seasons.NAMES[Seasons.at_day(sim.day)])
	var night = sim.phase == "NIGHT"
	if not night and ui.build_catalog.visible: _close_build_page()
	_sync_build_dock()
	ui.fast.visible = sim.phase == "DAY"
	if sim.phase != "DAY": _hide_special_notice()
	ui.pause.visible = sim.phase == "DAY"
	if not night:
		ui.info_panel.hide()
	_update_hud()

func _update_hud() -> void:
	if sim == null: return
	if sim.phase == "NIGHT" and opening_check_revision != sim.revision:
		var errors = sim.opening_errors()
		opening_issue = "" if errors.is_empty() else str(errors[0])
		opening_check_revision = sim.revision
	ui.open.disabled = sim.phase != "NIGHT" or not opening_issue.is_empty()
	ui.skills.visible = sim.phase == "DAY"
	ui.shift.visible = false
	ui.rent_card.visible = sim.phase == "NIGHT" and int(sim.next_rent().get("day",99))-sim.day <= 1
	ui.hub.get_node("Service/Phase").text = tr("夜间规划") if sim.phase == "NIGHT" else (tr("营业中") if sim.phase == "DAY" else tr("营业复盘"))
	ui.rush.visible = sim.crew_lineup.is_empty() or sim.crew_on_duty("ferrier", "waiter")
	ui.linked_fire.visible = sim.crew_on_duty("kilnkeeper", "chef")
	if ui.skills.visible:
		var remaining := maxi(0, sim.current_ready - sim.tick)
		ui.rush.disabled = remaining > 0 or sim.paused or guide.blocks_clock or not modal_kind.is_empty()
		ui.rush.text = tr("河道急送") if remaining == 0 else tr("急送 · %d秒") % ceili(remaining * sim.tick_ms / 1000.0)
		if ui.linked_fire.visible:
			var ready_count: int = sim.linked_fire_targets().size()
			var cooldown := maxi(0, sim.linked_fire_ready - sim.tick)
			ui.linked_fire.disabled = cooldown > 0 or ready_count == 0 or sim.paused or guide.blocks_clock or not modal_kind.is_empty()
			ui.linked_fire.text = tr("飞火 · %d秒") % ceili(cooldown * sim.tick_ms / 1000.0) if cooldown > 0 else tr("连灶飞火 · %d 锅") % ready_count
	ui.history.disabled = sim.reports.is_empty()
	ui.history.tooltip_text = tr("历史日报") if not ui.history.disabled else tr("完成首日营业后可查看历史日报")
	if sim.phase == "NIGHT":
		var expected_groups = [tr("开店 [%s]") % keys.text("open")]
		var seats = Grid.facilities(sim.layout, "table")
		for group in sim.chapter.guest_groups:
			var size = int(group.size)
			if not seats.any(func(f): return Grid.table_size(f) == size):
				expected_groups.append(tr("第 %d 天起可能到店 %d 人组，需要%s") % [int(group.from_day), size, tr(Grid.table_label(size))])
		ui.open.tooltip_text = opening_issue if not opening_issue.is_empty() else "\n".join(expected_groups)
	var weather = sim.weather_for().preset
	ui.badge.set_state(sim.day,sim.phase,clampf(float(sim.tick)/maxi(1,sim.day_ticks),0,1))
	ui.badge.set_weather(float(weather.rain) > 0.0, weather.has("thunder"))
	service_feedback.show_resource(ui.income_label, int(sim.stats.get("income", 0)), "$")
	service_feedback.show_resource(ui.gold_label, int(sim.gold), "$")
	service_feedback.show_resource(ui.rep_label, int(sim.reputation))
	service_feedback.show_resource(ui.star_label, int(sim.stars))
	var rent = sim.next_rent()
	ui.rent_label.text = "$%d" % int(rent.amount) if not rent.is_empty() else tr("已付清")
	ui.rent_days.get_parent().visible = not rent.is_empty()
	ui.rent_days.text = tr("%d天") % maxi(0, int(rent.get("day", sim.day)) - sim.day)
	var event_names = []
	for event in sim.events_for(): event_names.append(tr(str(event.name)))
	_sync_major_notice()
	ui.rent_card.tooltip_text = (tr("房租 · 第 %d 天缴 %d 金币") % [int(rent.day), int(rent.amount)] if not rent.is_empty() else tr("本章房租已全部缴清")) + ("\n" + "、".join(event_names) if not event_names.is_empty() else "")
	ui.rent_label.tooltip_text = ui.rent_card.tooltip_text
	ui.rent_label.get_parent().tooltip_text = ui.rent_card.tooltip_text
	var peak = _peak_forecast(sim.day, true)
	ui.peak_card.visible = not peak.is_empty() and sim.phase in ["NIGHT", "DAY"]
	ui.peak_label.text = peak
	ui.peak_label.tooltip_text = _peak_forecast(sim.day)
	ui.peak_label.get_parent().tooltip_text = ui.peak_label.tooltip_text
	ui.clock.text = sim.clock_text() if sim.phase == "DAY" else ("09:00" if sim.phase == "NIGHT" else "00:00")
	ui.cleanup.visible = sim.phase == "DAY" and sim.tick >= sim.day_ticks
	ui.clock.tooltip_text = tr("午夜解散队伍，已入座客人继续用餐") if ui.cleanup.visible else tr("09:00–21:00 接客，00:00 解散队伍")
	ui.clock.get_parent().tooltip_text = ui.clock.tooltip_text
	ui.pause_icon.set_glyph("play" if sim.paused else "pause", Style.INK)
	ui.fast.text = "%d×" % int(sim.chapter.fast_forward_multiplier) if fast_forward else "1×"
	ui.fast.tooltip_text = (tr("当前8倍速 · 点击恢复正常") if fast_forward else tr("当前正常速度 · 点击快进")) + " [%s]" % keys.text("fast")
	if bool(ui.fast.get_meta("active_visual", false)) != fast_forward:
		ui.fast.set_meta("active_visual", fast_forward)
		if fast_forward:
			ui.fast.add_theme_stylebox_override("normal", Style.box(Style.GOLD, Color("f6d28c"), 9, 7))
			ui.fast.add_theme_color_override("font_color", Color("233729"))
		else:
			ui.fast.remove_theme_stylebox_override("normal")
			ui.fast.remove_theme_color_override("font_color")
	ui.pause.tooltip_text = (tr("继续营业") if sim.paused else tr("暂停观察")) + " [%s]" % keys.text("pause")
	ui.menu.tooltip_text = tr("菜谱 [%s]") % keys.text("menu")
	ui.build.tooltip_text = tr("建造 [%s]") % keys.text("build")
	ui.trophy_bag.tooltip_text = tr("奖杯背包 [%s]") % keys.text("trophy_bag")
	ui.rotate.tooltip_text = tr("顺时针旋转 [%s]") % keys.text("rotate")
	ui.split.tooltip_text = tr("拆分餐桌 [%s]") % keys.text("split")
	ui.store.tooltip_text = tr("收起 [%s]") % keys.text("store")
	_sync_build_tools()
	if sim.phase == "DAY" and sim.tick >= sim.day_ticks:
		ui.badge.tooltip_text = tr("21:00 停止新客到店 · 00:00 解散排队 · 等店内客人离开后结算")
	else:
		ui.badge.tooltip_text = tr("夜晚规划") if sim.phase == "NIGHT" else tr("营业接客中")
	ui.badge.tooltip_text += " · " + tr(str(weather.name))
	ui.toast_card.modulate.a = clampf(status_timer / 0.4, 0, 1) if status_timer > 0 else 1.0
	if sim.phase == "NIGHT" and not opening_issue.is_empty() and status_timer <= 0:
		ui.toast_card.show()
		_set_toast_text(tr("开店前需要处理：") + opening_issue, true)
	elif status_timer <= 0:
		ui.toast_card.hide()
	if not inspected.is_empty() and ui.info_panel.visible:
		_update_inspector()

func _build_special_notice(overlay: Control) -> void:
	var notice = Style.card()
	notice.name = "SpecialGuestNotice"
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin = Style.frame(Color("5b3134"), Style.RED, 10)
	notice.add_theme_stylebox_override("panel", skin)
	overlay.add_child(notice)
	_rect(notice, -326, 75, -17, 139, 1, 0)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_child(row)
	row.add_child(Icon.make("crowd", Color("f2bd91"), 29))
	var copy = VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	copy.add_child(Style.text(tr("特别来客"), 12, Color("ebbe9d")))
	ui.special_caption = Style.text("", 17, Style.INK)
	copy.add_child(ui.special_caption)
	ui.special_notice = notice
	notice.hide()

func _on_guest_moment(id: int, moment: StringName) -> void:
	if moment != &"arrival" or not ui.has("special_notice"): return
	var customer = sim.active_customers.get(id, {})
	if customer.is_empty(): return
	var profile = sim.guest_defs[customer.type]
	if profile.rarity != "special": return
	var size = int(customer.party_size)
	ui.special_caption.text = tr("%s 到店") % tr(str(profile.name)) if size == 1 else tr("%d 位%s同行到店") % [size, tr(str(profile.name))]
	world.follow_actor("g_%d" % id, SPECIAL_NOTICE_SECONDS)
	_hide_special_notice()
	var notice = ui.special_notice
	notice.show()
	notice.modulate.a = 0.0
	notice.offset_right = 9
	notice.offset_left = -300
	special_notice_motion = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	special_notice_motion.tween_property(notice, "modulate:a", 1.0, .24)
	special_notice_motion.tween_property(notice, "offset_right", -17.0, .24)
	special_notice_motion.tween_property(notice, "offset_left", -326.0, .24)
	special_notice_motion.chain().tween_interval(SPECIAL_NOTICE_SECONDS - .48)
	special_notice_motion.chain().tween_property(notice, "modulate:a", 0.0, .24)
	special_notice_motion.chain().tween_callback(notice.hide)

func _hide_special_notice() -> void:
	if is_instance_valid(special_notice_motion) and special_notice_motion.is_valid(): special_notice_motion.kill()
	if ui.has("special_notice"): ui.special_notice.hide()

func _on_guest_payment(cell: Vector2, amount: int) -> void:
	if service_feedback == null: return
	var point = world.get_global_transform_with_canvas() * world.screen_point(cell + Vector2(0, -.2))
	service_feedback.add_payment(point, amount)

func _save() -> bool:
	if sim.phase not in ["NIGHT","REPORT"]: return false
	var checkpoint = sim.export_state()
	var error = Store.write_checkpoint(checkpoint, save_path)
	if error.is_empty() and sim.phase == "REPORT" and sim.last_report.get("result", "") == "WIN":
		error = ChapterProgress.record_win(checkpoint, testing)
	if not error.is_empty(): _notice(error,true)
	return error.is_empty()

func _notice(message: String, error: bool = false) -> void:
	if not ui.has("toast_label"): return
	status_timer = 6.0
	ui.toast_card.show()
	_set_toast_text(message, error)

func _set_toast_text(message: String, error: bool) -> void:
	if error and modal_frame != null: modal_frame.show_error(message)
	ui.toast_glyph.set_glyph("alert" if error else "check", Style.RED if error else Style.GREEN)
	ui.toast_label.text = message
	ui.toast_label.add_theme_color_override("font_color",Style.RED if error else Style.INK)
	var width = Style.font().get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ui.toast_card.offset_right = ui.toast_card.offset_left + clampf(width + 54.0, 100.0, 385.0)

func _command(result: Dictionary, message: String = tr("已更新")) -> bool:
	if not result.ok:
		_notice(result.get("error",tr("操作失败")),true)
		return false
	_save()
	_refresh_all()
	_notice(message)
	return true

func _open_day() -> void:
	if sim.phase != "NIGHT" or modal_layer != null or ui.build_catalog.visible: return
	_save()
	if _command(sim.start_day(), tr("已开店")):
		guide.opened()
		_clear_diagnostic()
		accumulator = 0
		fast_forward = false
		world.cancel_placement()
		ui.info_panel.hide()
		_refresh_all()

func _on_focus_lost() -> void:
	if is_instance_valid(world):
		world.stop_follow()
		world.cancel_drag()
		world.cancel_touch()
	if is_instance_valid(gamepad):
		gamepad.release_pointer()
		gamepad.hide()
	if sim != null and sim.phase == "DAY":
		sim.paused = true
		accumulator = minf(accumulator, float(sim.tick_ms) / 1000.0)
		_update_hud()
		_notice(tr("窗口失去焦点，营业已暂停。"))

func _toggle_pause() -> void:
	if sim.phase != "DAY": return
	sim.paused = not sim.paused
	_update_hud()

func _toggle_fast() -> void:
	if sim.phase != "DAY": return
	fast_forward = not fast_forward
	_update_hud()

func _inspect(kind: String, id: String) -> void:
	if kind == "landmark":
		_visit_landmark(id)
		return
	if kind == "trophy_shop":
		_show_trophy_shop()
		return
	if kind == "facility":
		world.selected_id = id
		_sync_build_tools()
		match id:
			"cashier":
				_show_cashier_front()
				return
			"slot":
				_show_purchase_page()
				return
			"trophy_shop":
				_show_trophy_shop()
				return
			"decor_shop":
				_show_decoration_shop()
				return
	if kind == "plot":
		_show_plot_confirmation(id)
		return
	if kind == "customer" and not sim.customers.has(int(id)): return
	if kind == "staff" and (sim.phase != "DAY" or sim.staff_member(int(id)).is_empty()): return
	if kind == "preview" and sim.phase != "NIGHT": return
	if kind == "preview": world.selected_id = id
	var changed = kind != inspected.get("kind") or id != inspected.get("id") or not ui.info_panel.visible
	inspected = {"kind":kind,"id":id}
	_update_inspector(changed)
	ui.info_panel.show()
	_sync_build_tools()

func _clear_inspector() -> void:
	ui.info_panel.hide()
	inspected = {}
	if not world.editing and not world.drag_active: world.selected_id = ""
	_sync_build_tools()

func _inspected_actor() -> String:
	var id = str(inspected.get("id", ""))
	match str(inspected.get("kind", "")):
		"preview": return id
		"customer": return "g_" + id
		"staff": return "s_" + id if sim.phase == "DAY" and not sim.staff_member(int(id)).is_empty() else ""
	return ""

func _follow_inspected() -> void:
	world.follow_actor(_inspected_actor())

func _sync_follow_button(_actor_id := "") -> void:
	if not ui.has("info_follow"): return
	var following = not world.follow_actor_id.is_empty() and _inspected_actor() == world.follow_actor_id
	ui.info_follow.tooltip_text = tr("跟随中 · 点击场景或按键退出") if following else tr("镜头跟随")
	ui.info_follow.get_child(0).set_glyph("follow", Style.GOLD if following else Style.INK)

func _update_inspector(reveal := false) -> void:
	var id = str(inspected.get("id",""))
	var kind = str(inspected.get("kind", ""))
	var f = Grid.find(sim.layout, id) if kind == "facility" else {}
	var glyph = "crowd"
	if kind == "facility":
		var type = f.get("type", "")
		glyph = type if type in BuildCatalog.CATEGORIES else "recipe"
	ui.info_glyph.set_glyph(glyph, Style.GREEN)
	var is_guest = kind == "customer"
	ui.guest_profile.visible = is_guest
	ui.info_body.visible = not is_guest
	ui.info_panel.offset_bottom = 483 if is_guest else 369
	ui.info_follow.visible = not _inspected_actor().is_empty() and (not is_guest or sim.active_customers.has(int(id)))
	_sync_follow_button()
	match kind:
		"preview":
			var is_chef := id.begins_with("preview_chef_")
			var role = tr("厨师") if is_chef else tr("服务员")
			ui.info_title.text = tr("%s %d · 预备中") % [role, int(id.get_slice("_", 2)) + 1]
			var count = int(sim.attributes.chefs if is_chef else sim.attributes.waiters)
			ui.info_body.text = tr("已雇佣 %d 位 · 可拖动调整开店站位") % count
			var job := str(id.get_slice("_",1))
			var species := str(sim.helper_at(job,int(id.get_slice("_",2))))
			if not species.is_empty():
				ui.info_body.text += "\n"+tr(sim.Minions.NAMES[species])+" · "+tr(sim.Minions.TRAITS[job][species])
		"facility":
			if f.is_empty(): ui.info_panel.hide(); return
			ui.info_title.text = Style.facility_name(str(f.name))
			var detail = ""
			match str(f.type):
				"table":
					var size = Grid.table_size(f)
					detail = tr("%s · %d 座") % [tr(Grid.table_label(size)), size]
					if sim.phase == "NIGHT" and size < 4:
						detail += tr("\n长按拖到同规格餐桌可合成%s。") % tr(Grid.table_label(size * 2))
					if size > 1: detail += tr("\n为 %d 人组整桌留座。") % size
				"stove": detail = tr("厨师在此烹饪，做好后会把菜搬到出餐口。") + _efficiency_buff("cook")
				"order": detail = tr("服务员交单，厨师接单。四面可操作。")
				"pass": detail = tr("厨师放餐，服务员取餐。四面可操作。")
				"wall": detail = tr("隔开走道与用餐区域。可移动或收起。")
				"decoration":
					var definition = sim.decoration_defs[f.decoration_id]
					detail = Decor.description(definition)
					if sim.phase == "NIGHT":
						var affected = 0
						var cells = Decor.coverage(f, definition, sim.layout)
						for target in sim.layout.facilities:
							if Grid.placed(target) and Decor.affects(target, definition, cells): affected += 1
						if definition.effect != "waiter_speed": detail += tr("\n当前覆盖 %d 处") % affected
						detail += tr("\n点击移动工具可预览范围。")
				"trophy":
					var relic = sim.relic_defs[str(f.relic_id)]
					detail = "%s品质 · %s\n已展示 %d / %d" % [Trophies.grade_name(int(relic.rarity)), Trophies.description(relic), Grid.facilities(sim.layout,"trophy").size(), int(sim.attributes.relic_slots)]
					if sim.displayed_trophy_effects().get(relic.effect_type, {}).get("id") != relic.id:
						detail += "\n同类高品质奖杯正在生效"
			ui.info_body.text = detail
		"staff":
			var person = sim.staff_member(int(id))
			if person.is_empty():
				_clear_inspector()
				return
			var chef = person.role == "chef"
			ui.info_glyph.set_glyph("stove" if chef else "crowd", Style.GREEN)
			ui.info_title.text = "%s #%d" % [tr("厨师") if chef else tr("服务员"), person.id]
			var actions = {"ORDER":tr("给客人点单"),"SUBMIT":tr("送订单到厨房"),"COOK":tr("正在烹饪"),"COLLECT":tr("领取灶台食物"),"TRANSFER":tr("搬运到出餐口"),"PICKUP":tr("取餐"),"DELIVER":tr("给客人上菜"),"RETURN":tr("返还食物")}
			ui.info_body.text = tr("当前：%s\n手持食物：%d 份") % [tr(str(person.reason)) if person.task.is_empty() else actions.get(person.task.kind,tr("正在工作")), person.carry_food.size()]
			var species := str(person.get("minion",""))
			if not species.is_empty(): ui.info_body.text += "\n"+tr(sim.Minions.NAMES[species])+" · "+tr(sim.Minions.TRAITS[person.role][species])
		"customer":
			var customer_id = int(id)
			var customer = sim.customers.get(customer_id, {})
			if customer.is_empty():
				_clear_inspector()
				return
			var profile = sim.guest_defs[customer.type]
			ui.info_title.text = tr(str(profile.name))
			var traits = _guest_effect(profile) if profile.rarity != "normal" else ""
			if profile.get("unlimited_food_wait", false):
				traits = tr("会一直等到上菜 · 每轮扣 %d 声望") % int(profile.food_penalty_per_cycle)
			elif customer.type == "food_inspector":
				traits = tr("用餐时间为平时的 %d 倍 · 会评价餐品品质") % int(profile.eat_time_multiplier)
			if not profile.get("unlimited_food_wait", false):
				traits += _efficiency_buff("patience")
			traits += _efficiency_buff("eat_time_reduction")
			ui.guest_profile.present(sim, customer, traits.strip_edges(), reveal)

func _efficiency_buff(effect: String) -> String:
	var lines = ""
	var sign = "−" if effect == "eat_time_reduction" else "+"
	for id in sim.buff_states:
		var buff = sim.buff_defs[id]
		if str(buff.effect_type) == effect:
			var increase = int(round(float(buff.effect_per_stack) * int(sim.buff_states[id].stack_count) * 100.0))
			lines += tr("\n增益 (%s%d%%)：%s · %s") % [sign,increase,tr(str(buff.name)),tr(str(buff.description))]
	for trophy in Grid.facilities(sim.layout,"trophy"):
		var relic = sim.relic_defs[str(trophy.relic_id)]
		if str(relic.effect_type) == effect:
			lines += tr("\n常驻 (%s%d%%)：%s · %s") % [sign,int(round(float(relic.effect_value)*100.0)),tr(str(relic.name)),tr(Trophies.description(relic))]
	return lines

func _guest_effect(guest: Dictionary) -> String:
	var parts = []
	if guest.get("payment_override", "") == "ZERO":
		parts.append(tr("结账金币为0"))
	elif not is_equal_approx(float(guest.type_payment_multiplier),1.0):
		parts.append(tr("金币倍率 ×%.1f") % float(guest.type_payment_multiplier))
	if not is_equal_approx(float(guest.get("choose_time_multiplier",1)),1.0):
		parts.append(tr("选菜时间 ×%.1f") % float(guest.choose_time_multiplier))
	if not is_equal_approx(float(guest.get("eat_time_multiplier",1)),1.0):
		parts.append(tr("用餐时间 ×%.1f") % float(guest.eat_time_multiplier))
	if not is_equal_approx(float(guest.get("food_cycle_multiplier",1)),1.0):
		parts.append(tr("等餐扣分周期 ×%.1f") % float(guest.food_cycle_multiplier))
	if guest.get("unlimited_food_wait", false):
		parts.append(tr("等餐耐心无限"))
	elif not is_equal_approx(float(guest.get("food_max_multiplier",1)),1.0):
		parts.append(tr("等餐耐心 ×%.1f") % float(guest.food_max_multiplier))
	parts.append(tr("基础声望 %d") % int(guest.base_reputation))
	return " · ".join(parts)

func _begin_move() -> void:
	var id = world.selected_id
	if sim.phase != "NIGHT" or (not id.begins_with("preview_") and _selected_fixture().is_empty()): return
	world.cancel_placement()
	world.editing = true
	world.selected_id = id
	ui.info_panel.hide()
	_sync_build_tools()
	var rotation_hint = tr(" · %s 旋转") % keys.text("rotate") if Grid.can_rotate(Grid.find(sim.layout, world.selected_id)) else ""
	_notice(tr("点击空格放置") + rotation_hint + tr(" · Esc 取消"))

func _move_facility(id: String, cell: Vector2i) -> void:
	if id.begins_with("preview_"):
		var role = id.get_slice("_", 1)
		var index = int(id.get_slice("_", 2))
		if _command(sim.move_staff(role, index, cell), tr("员工开店站位已调整。")):
			world.cancel_placement()
			_inspect("preview", id)
		return
	var result = sim.move_facility(id, cell, world.decor_preview_turns)
	var merged_size = int(result.get("merged_size", 0))
	var message = tr("已合成%s。") % tr(Grid.table_label(merged_size)) if merged_size > 0 else tr("设施位置已调整。")
	if _command(result, message):
		world.cancel_placement()
		if id in ["cashier", "slot", "trophy_shop", "decor_shop"]:
			_sync_build_tools()
			return
		_inspect("facility", str(result.get("facility_id", id)))
		if merged_size > 0: guide.table_merged(merged_size)

func _selected_fixture() -> Dictionary:
	if sim.phase != "NIGHT" or world.placing_wall or world.drag_active: return {}
	return Grid.find(sim.layout, world.selected_id)

func _rotate_selection() -> void:
	if sim.phase == "NIGHT" and world.placing_wall:
		world.rotate_wall_brush()
		_notice(tr("墙体方向已调整 · 松开左键铺设"))
		return
	var fixture = _selected_fixture()
	if fixture.get("type") == "decoration" and world.editing:
		var current = Grid.rotation(fixture) if world.decor_preview_turns < 0 else world.decor_preview_turns
		world.decor_preview_turns = (current + 1) % 4
		_notice(tr("装饰朝向已调整"))
	elif Grid.can_rotate(fixture):
		_command(sim.rotate_facility(fixture.id), tr("设施朝向已调整。"))

func _split_selection() -> void:
	var fixture = _selected_fixture()
	if not Grid.can_split(fixture): return
	var result = sim.split_facility(fixture.id)
	var message = tr("已拆为两张%s。") % tr(Grid.table_label(result.size)) if result.ok else ""
	if _command(result, message) and not world.editing: _inspect("facility", fixture.id)

func _store_selection() -> void:
	var fixture = _selected_fixture()
	if not Grid.can_store(fixture): return
	var message = tr("隔墙已收起。") if fixture.type == "wall" else tr("设施已收起，可从建造目录重新放置。")
	if _command(sim.store_facility(fixture.id), message):
		world.cancel_placement()
		_clear_inspector()

func _select_pending(id: String) -> void:
	var facility = Grid.find(sim.layout, id)
	if sim.phase != "NIGHT" or facility.is_empty(): return
	world.cancel_placement()
	world.editing = true
	world.selected_id = id
	ui.info_panel.hide()
	_sync_build_tools()
	var hint = tr(" · %s 旋转") % keys.text("rotate") if Grid.can_rotate(facility) else ""
	if facility.type == "trophy":
		_notice(tr("在展廊内亮起的格子放置 ") + Style.facility_name(str(facility.name)))
	else:
		_notice(tr("放置 %s · 点击空格%s") % [Style.facility_name(str(facility.name)), hint])

func _start_wall_placement() -> void:
	if sim.phase != "NIGHT": return
	_close_modal()
	world.cancel_placement()
	_clear_inspector()
	world.placing_wall = true
	_sync_build_tools()
	_notice(tr("按住左键拖铺 · %s 转向 · Esc 退出") % keys.text("rotate"))

func _place_wall(cells: Array, turns: int) -> void:
	_command(sim.place_wall_row(cells, turns), tr("已铺设 %d 格隔墙 · Esc 退出") % cells.size())

func _show_plot_confirmation(id: String) -> void:
	if sim.phase != "NIGHT": return
	var plot = sim.next_land_plot()
	if plot.is_empty() or str(plot.id) != id: return
	ui.info_panel.hide()
	var box = _new_modal("plot_unlock", str(plot.name), 430)
	var status = sim.land_plot_status(id)
	var waiting_for_date = sim.day < int(plot.unlock_day)
	var conditions = HBoxContainer.new()
	conditions.add_theme_constant_override("separation", 20)
	box.add_child(conditions)
	Style.readout(conditions, "clock", tr("第 %d 天开放") % int(plot.unlock_day), tr("开放日"), Style.MUTED)
	Style.readout(conditions, "star", str(int(plot.star_cost)), tr("费用 %d 闪星 · 持有 %d") % [int(plot.star_cost), sim.stars])
	var gifts = HBoxContainer.new()
	gifts.add_theme_constant_override("separation", 16)
	box.add_child(gifts)
	if int(plot.grant_chefs) > 0:
		Style.readout(gifts, "chef", "+%d" % int(plot.grant_chefs), tr("赠送厨师"), Style.GREEN)
	var counts := {}
	for fixture in plot.fixtures:
		if fixture.type == "trophy":
			Style.readout(gifts, "trophy", str(fixture.name), tr("赠送奖杯"), Style.GREEN)
		elif fixture.type in ["slot", "trophy_shop", "decor_shop"]:
			Style.readout(gifts, "coins", str(fixture.name), tr("解锁商店"), Style.GREEN)
		else:
			counts[fixture.type] = int(counts.get(fixture.type, 0)) + 1
	for type in counts:
		Style.readout(gifts, str(type), "+%d" % int(counts[type]), tr("赠送灶台") if type == "stove" else tr("赠送餐桌"), Style.GREEN)
	if not status.ok and not waiting_for_date:
		box.add_child(Style.text(str(status.error), 15, Style.MUTED, true))
	guide.plot_note(box, id)
	var confirm = Style.button(tr("确认解锁"), true)
	confirm.name = "ConfirmLandUnlock"
	confirm.disabled = not status.ok
	confirm.pressed.connect(_unlock_land.bind(id))
	box.add_child(confirm)

func _sync_major_notice() -> void:
	var upcoming = sim.major_events_for() if sim.phase == "NIGHT" else []
	major_notice = upcoming[0] if not upcoming.is_empty() else {}
	for event in upcoming:
		if event.id not in sim.major_event_claims:
			major_notice = event
			break
	var eligible = not major_notice.is_empty() and int(major_notice.from_day) == sim.day and not major_notice.id in sim.major_event_views and not major_notice.id in sim.major_event_claims
	var scheduled = str(major_notice.id) if eligible else ""
	if scheduled != pending_major_event:
		pending_major_event = scheduled
		major_event_delay = MAJOR_EVENT_DELAY
	var fresh = not major_notice.is_empty() and major_notice.id not in sim.major_event_claims
	var state = "%s/%s" % [major_notice.id, fresh] if not major_notice.is_empty() else ""
	if state == major_notice_state: return
	major_notice_state = state
	if major_notice_pulse != null and major_notice_pulse.is_valid(): major_notice_pulse.kill()
	ui.major_event.scale = Vector2.ONE
	ui.major_event.visible = not major_notice.is_empty()
	if major_notice.is_empty(): return
	ui.major_event.text = tr("！重大事件\n") + tr(str(major_notice.name))
	ui.major_event.tooltip_text = tr("查看公告与生效规则")
	if fresh:
		major_notice_pulse = ui.major_event.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		major_notice_pulse.tween_property(ui.major_event, "scale", Vector2.ONE * 1.06, .43)
		major_notice_pulse.tween_property(ui.major_event, "scale", Vector2.ONE, .60)

func _advance_major_event_popup(delta: float) -> void:
	if pending_major_event.is_empty() or sim.phase != "NIGHT": return
	major_event_delay = maxf(0.0, major_event_delay - delta)
	if major_event_delay > 0 or modal_layer != null or fading_modal != null: return
	if ui.build_catalog.visible or world.editing or world.placing_wall or not world.pressed_entity.is_empty(): return
	_show_major_event()

func _show_major_event() -> void:
	if sim.phase != "NIGHT" or major_notice.is_empty(): return
	var event = major_notice
	pending_major_event = ""
	if event.id not in sim.major_event_views:
		sim.major_event_views.append(event.id)
		_save()
	guide.event_opened()
	var box = _new_modal("major_event", tr(str(event.name)), 680)
	var notice = EVENT_PANEL.instantiate()
	box.add_child(notice)
	notice.populate(event, sim.event_challenge(event), event.id in sim.major_event_claims, sim.guest_defs.get(event.get("special_guest", ""), {}))
	notice.confirmed.connect(_confirm_major_event.bind(str(event.id)))

func _confirm_major_event(id: String) -> void:
	var result = sim.confirm_major_event(id)
	var grant = result.get("grant", {})
	var message = tr("已查看重大事件") if grant.is_empty() else tr("收到 ") + MajorEventPanel.reward_text(grant)
	if _command(result, message): _close_modal(true, true)

func _unlock_land(id: String) -> void:
	if _command(sim.unlock_land_plot(id), tr("地块已解锁")):
		world.play_construction(id)
		_close_modal(true, true)
		match id:
			"purchase_annex": guide.show_new_shop("slot")
			"trophy_gallery": guide.show_gallery()
			"decor_studio": guide.show_new_shop("decor_shop")

func _show_cashier_front() -> void:
	ui.info_panel.hide()
	var box = _new_modal("cashier_front",tr("收银台"),550)
	box.add_child(Style.text(tr("升级同时花费声望与金币。"),16,Style.MUTED,true))
	var upgrades = Style.button(tr("招聘与改造"), true)
	upgrades.pressed.connect(_show_cashier_page)
	box.add_child(upgrades)

func _upgrade(key: String) -> void:
	var result = sim.upgrade(key)
	var id = str(result.get("facility_id", ""))
	var message = tr("已完成。")
	if result.ok and key == "tables":
		message = tr("新餐桌已摆好。") if Grid.placed(Grid.find(sim.layout, id)) else tr("没有合适空位，新餐桌已放入建造背包。")
	if _command(result, message):
		if key == "chefs" and not id.is_empty():
			_close_modal()
			_select_pending(id)
			guide.placement()
		else:
			_show_cashier_page()

func _rent_budget_text() -> String:
	var rent = sim.next_rent()
	if rent.is_empty(): return tr("本章房租已全部缴清")
	var missing = maxi(0, int(rent.amount) - sim.gold)
	var balance = tr("当前余额距房租还差 %d$") % missing if missing > 0 else tr("当前余额可覆盖房租")
	return tr("第 %d 天房租 %d$ · %s") % [int(rent.day), int(rent.amount), balance]

func _management_header(box: VBoxContainer, summary := "", hiring := false) -> void:
	var strip = Style.card()
	strip.add_theme_stylebox_override("panel", Style.box(ManagementCard.INSET, ManagementCard.EDGE, 9, 9))
	box.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	strip.add_child(row)
	if not hiring:
		var portrait := Control.new()
		portrait.custom_minimum_size = Vector2(59, 50)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
		var chef = Actor.new()
		chef.name = "PurchaseChef"
		chef.position = Vector2(28, 39)
		chef.z_index = 2
		portrait.add_child(chef)
		chef.set_visual("chef")
		chef.set_display_zoom(1.50)
		chef.present("idle")
	var coins = Style.readout(row, "coins", "%d 金币" % sim.gold, _rent_budget_text())
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if hiring:
		Style.readout(row, "reputation", "%d 声望" % sim.reputation, "可用于招聘与改造的声望", Style.GREEN)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if not summary.is_empty():
		var state = Style.text(summary, 15, Style.GREEN if not sim.purchase_spent() else Style.MUTED)
		state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(state)

func _show_cashier_page() -> void:
	ui.info_panel.hide()
	var box = _new_modal("cashier", "招聘与改造", 746)
	_management_header(box, "", true)
	var entries = {"waiters": ["服务员", "crowd"], "chefs": ["厨师与灶台", "chef"], "tables": ["桌位", "table"],
		"menu_slots": ["菜单上架槽", "recipe"], "queue_capacity": ["排队容量", "door"], "relic_slots": ["奖杯展示位", "trophy"]}
	var progression = sim.upgrade_progression()
	for key in progression.unlocked:
		box.add_child(_upgrade_card(key, entries[key]))
	if not progression.next_key.is_empty():
		var key = progression.next_key
		box.add_child(_upgrade_card(key, entries[key], int(progression.next_day)))
	var waiting = sim.stored_facilities().filter(func(f): return f.type in ["table", "stove"])
	if sim.phase == "NIGHT" and not waiting.is_empty():
		box.add_child(Style.text("待放置", 15, Style.GOLD))
		var row = HFlowContainer.new()
		box.add_child(row)
		for f in waiting:
			var button = Style.button(tr("放置 ") + Style.facility_name(str(f.name)))
			button.pressed.connect(_pick_pending.bind(str(f.id)))
			row.add_child(button)

func _upgrade_card(key: String, entry: Array, unlock_day := 0) -> Control:
	var card = ManagementCard.new()
	card.name = "Upgrade_" + key
	var locked = unlock_day > 0
	card.build(entry[1], entry[0], Style.GREEN, locked)
	var count = int(sim.attributes[key])
	var cap = int(sim.chapter.attribute_caps[key])
	var count_label = Style.text("%d / %d" % [count, cap], 14, ManagementCard.GRAY_TEXT if locked else Style.MUTED)
	card.heading.add_child(count_label)
	var capacity := ProgressBar.new()
	capacity.show_percentage = false
	capacity.custom_minimum_size.y = 5
	capacity.max_value = cap
	capacity.value = count
	capacity.add_theme_stylebox_override("background", Style.box(Color("23292a") if locked else ManagementCard.INSET, Color.TRANSPARENT, 2, 0))
	capacity.add_theme_stylebox_override("fill", Style.box(ManagementCard.GRAY_MUTED if locked else Style.GREEN, Color.TRANSPARENT, 2, 0))
	card.body.add_child(capacity)
	var status = sim.upgrade_status(key)
	var increase = mini(int(sim.chapter.upgrade_rules[key].get("step", 1)), cap - count)
	var caption = "+%d · %d 声望 + %d$" % [increase, sim.upgrade_cost(key), sim.upgrade_gold_cost(key)]
	if locked: caption = "第 %d 天解锁" % unlock_day
	elif increase <= 0: caption = "已达上限"
	var hint = "招聘" if key in ["chefs", "waiters"] else "改造"
	var button = card.action(caption, status.ok, hint if status.ok else str(status.error))
	button.name = "ApplyUpgrade"
	button.pressed.connect(_upgrade.bind(key))
	return card

func _show_build_page() -> void:
	if sim.phase != "NIGHT": return
	world.set_roof_view(false)
	if ui.build_catalog.visible:
		_close_build_page()
		return
	ui.info_panel.hide()
	ui.build_catalog.show()
	_sync_build_dock()
	_sync_build_tools()
	guide.build_opened()

func _close_build_page() -> void:
	ui.build_catalog.hide()
	_cancel_placement()
	_sync_build_dock()

func _sync_build_dock() -> void:
	var night = sim.phase == "NIGHT"
	var building = ui.build_catalog.visible
	world.bottom_inset = BuildCatalog.HEIGHT + 18 if building else 0.0
	ui.open.visible = night and not building
	ui.menu.visible = night and not building
	ui.build.visible = night and not building
	ui.trophy_bag.visible = sim.trophy_shop_unlocked() and sim.phase != "REPORT"
	var bag_left = -330 if building else -183
	var bag_bottom = -21 - world.bottom_inset if building else -19.0
	_rect(ui.trophy_bag, bag_left, bag_bottom - 47, bag_left + 47, bag_bottom, 1, 1)
	var toolbar_bottom = -21 - world.bottom_inset if building else -73.0
	_rect(ui.action_bar, -272, toolbar_bottom - 46, -18, toolbar_bottom, 1, 1)
	ui.toast_card.offset_top = -77 - world.bottom_inset
	ui.toast_card.offset_bottom = -19 - world.bottom_inset

func _sync_build_tools() -> void:
	var night = sim.phase == "NIGHT" and not world.drag_active
	var fixture = _selected_fixture()
	var placing = world.editing or world.placing_wall
	ui.move.visible = night and not placing and (world.selected_id.begins_with("preview_") or (not fixture.is_empty() and Grid.placed(fixture)))
	ui.rotate.visible = night and (world.placing_wall or Grid.can_rotate(fixture))
	ui.split.visible = night and not placing and Grid.can_split(fixture)
	ui.store.visible = night and not placing and Grid.can_store(fixture)
	ui.cancel_placement.visible = night and placing
	if ui.build_catalog.visible:
		var current = ""
		var status = tr("选一件物件，再到地图上放置")
		if world.placing_wall:
			current = "@wall"
			status = tr("按住左键拖铺隔墙")
		elif world.editing:
			current = world.selected_id
			status = tr("点击空格放置 ") + str(fixture.get("name", ""))
		ui.build_catalog.refresh(sim, current, status)

func _cancel_placement() -> void:
	world.cancel_placement()
	_clear_inspector()

func _pick_catalog_item(id: String) -> void:
	if id == "@wall":
		_start_wall_placement()
	else:
		_select_pending(id)

func _pick_pending(id: String) -> void:
	_close_modal()
	_select_pending(id)

func _show_trophy_shop() -> void:
	if sim.phase != "NIGHT" or modal_kind == "trophy_shop": return
	if not sim.trophy_shop_unlocked():
		_notice(tr("解锁奖杯展廊后即可打开奖杯盲盒。"))
		return
	ui.info_panel.hide()
	guide.trophy_shop_opened()
	var box = _new_modal("trophy_shop",tr("海克斯奖杯盲盒"),910)
	trophy_box = TrophyBox.new()
	box.add_child(trophy_box)
	trophy_box.configure(sim)
	trophy_box.draw_requested.connect(_open_trophy_box)
	trophy_box.bag_requested.connect(_show_trophy_bag)
	trophy_box.place_requested.connect(_pick_pending)

func _open_trophy_box() -> void:
	if modal_kind != "trophy_shop" or not is_instance_valid(trophy_box) or trophy_box.opening: return
	var offer = sim.trophy_box_offer()
	var checkpoint = sim.export_state()
	var result = sim.draw_trophy()
	if not result.ok:
		_notice(result.error, true)
		trophy_box.refresh()
		return
	if not _save():
		sim.restore_state(checkpoint)
		_refresh_all()
		trophy_box.refresh()
		return
	if modal_frame != null: modal_frame.show_error("")
	_refresh_all()
	if world.district_3d!=null: world.district_3d.open_gallery_coffer()
	trophy_box.animate_opening(result, offer)

func _show_trophy_bag() -> void:
	if not sim.trophy_shop_unlocked():
		_notice(tr("解锁奖杯展廊后开放奖杯背包。"))
		return
	var box = _new_modal("trophy_bag", "奖杯背包", 710)
	var displayed = sim.displayed_trophy_effects()
	var placed_count = Grid.facilities(sim.layout, "trophy").size()
	box.add_child(Style.text(tr("已展示 %d / %d 件 · 同类奖杯只生效最高档") % [placed_count, int(sim.attributes.relic_slots)], 15, Style.GOLD))
	if sim.owned_relics.is_empty():
		box.add_child(Style.text("打开盲盒后，可从这里取出奖杯。", 15, Style.MUTED))
		return
	var search := LineEdit.new()
	search.placeholder_text = tr("搜索名称、品质或效果")
	search.visible = sim.owned_relics.size() > 7
	box.add_child(search)
	var entries = []
	for id in sim.owned_relics:
		var definition = sim.relic_defs[id]
		var fixture = Grid.find(sim.layout, "trophy_" + str(id))
		entries.append({"item": definition, "id": fixture.id, "placed": Grid.placed(fixture)})
	entries.sort_custom(func(a, b): return a.placed if a.placed != b.placed else int(a.item.rarity) > int(b.item.rarity))
	var rows := VBoxContainer.new()
	box.add_child(rows)
	for entry in entries:
		var tile = _trophy_bag_row(entry, displayed, placed_count)
		rows.add_child(tile)
	search.text_changed.connect(func(query):
		var term = query.strip_edges()
		for row in rows.get_children():
			row.visible = term.is_empty() or str(row.get_meta("search")).contains(term)
	)

func _trophy_bag_row(entry: Dictionary, displayed: Dictionary, placed_count: int) -> Control:
	var relic = entry.item
	var grade = int(relic.rarity)
	var tint = Trophies.grade_color(grade)
	var row_wrap = Style.card()
	row_wrap.add_theme_stylebox_override("panel", Style.box(Color("223138"), Color("465b5c").lerp(tint, .30), 8, 8))
	var row := HBoxContainer.new()
	row_wrap.add_child(row)
	row.add_child(TrophyArt.thumbnail(relic, Vector2(52, 47)))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var state = ""
	if entry.placed:
		state = tr(" · 生效中") if displayed.get(relic.effect_type, {}).get("id") == relic.id else tr(" · 已展示")
	var label = tr("%s · %s品质%s") % [tr(relic.name), Trophies.grade_name(grade), state]
	var description = Trophies.description(relic)
	row_wrap.set_meta("search", label + description)
	info.add_child(Style.text(label, 16, tint, true))
	info.add_child(Style.text(description, 14, Style.MUTED, true))
	var action = _icon_button("move", "移动奖杯" if entry.placed else "摆放奖杯")
	action.custom_minimum_size.x = 42
	action.disabled = sim.phase != "NIGHT" or (not entry.placed and placed_count >= int(sim.attributes.relic_slots))
	action.tooltip_text = "夜晚可布置" if sim.phase != "NIGHT" else (tr("展示位已满，请先收起一件") if action.disabled else action.tooltip_text)
	action.pressed.connect(_pick_pending.bind(entry.id))
	row.add_child(action)
	if entry.placed:
		var store = _icon_button("store", "收起奖杯")
		store.custom_minimum_size.x = 42
		store.disabled = sim.phase != "NIGHT"
		store.pressed.connect(_store_trophy.bind(entry.id))
		row.add_child(store)
	return row_wrap

func _store_trophy(id: String) -> void:
	if _command(sim.store_facility(id),tr("奖杯已收起，常驻效果停止生效。")):
		_show_trophy_bag()

func _show_decoration_shop() -> void:
	if sim.phase != "NIGHT" or not sim.decoration_shop_unlocked(): return
	ui.info_panel.hide()
	guide.shop_opened("decor_shop")
	var box = _new_modal("decor_shop", tr("装饰商店"), 908)
	var summary = HBoxContainer.new()
	box.add_child(summary)
	Style.readout(summary, "star", "%d 闪星" % sim.stars, "持有闪星")
	summary.add_child(Style.text("同类效果覆盖时取最高值", 14, Style.MUTED))
	var offers = GridContainer.new()
	offers.columns = 1
	offers.add_theme_constant_override("h_separation", 8)
	offers.add_theme_constant_override("v_separation", 8)
	box.add_child(offers)
	for definition in sim.decoration_defs.values():
		var card = Style.card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Style.inset(9,7))
		offers.add_child(card)
		var row = HBoxContainer.new()
		card.add_child(row)
		var thumb = BuildCatalog.Thumbnail.new()
		thumb.kind = "decoration"
		thumb.decoration = definition
		thumb.custom_minimum_size = Vector2(65, 57)
		row.add_child(thumb)
		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 4)
		row.add_child(details)
		details.add_child(Style.text(definition.name, 16))
		details.add_child(Style.text(Decor.description(definition), 13, Style.MUTED, true))
		details.add_child(Style.text("%d×%d 格" % [definition.extent[0], definition.extent[1]], 12, Style.MUTED))
		var buy = Style.button("%d 闪星" % int(definition.star_cost))
		buy.name = "Buy_" + str(definition.id)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.disabled = sim.stars < int(definition.star_cost)
		buy.tooltip_text = "还差 %d 闪星" % (int(definition.star_cost) - sim.stars) if buy.disabled else "购买 " + str(definition.name)
		buy.pressed.connect(_buy_decoration.bind(str(definition.id)))
		row.add_child(buy)
	var bag = Style.button(tr("打开建造背包"))
	bag.pressed.connect(_open_decoration_inventory)
	box.add_child(bag)

func _buy_decoration(id: String) -> void:
	if _command(sim.buy_decoration(id), tr("装饰已放入建造背包。")):
		_show_decoration_shop()

func _open_decoration_inventory() -> void:
	_close_modal(false, true)
	if not ui.build_catalog.visible: _show_build_page()
	ui.build_catalog._select_category("decoration")

func _show_purchase_page() -> void:
	if sim.phase != "NIGHT": return
	if not sim.purchase_unlocked():
		_notice(tr("解锁采购小厅后可采购"), true)
		return
	ui.info_panel.hide()
	guide.shop_opened("slot")
	var box = _new_modal("purchase", "采购处", 746)
	_management_header(box, "今日已采购" if sim.purchase_spent() else "今日可购 1 件")
	var mods = sim.effective_modifiers()
	for index in sim.shop.size():
		box.add_child(_purchase_card(index, mods))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(actions)
	var menu = Style.button("查看菜谱")
	menu.pressed.connect(_show_menu_page)
	actions.add_child(menu)

func _purchase_card(index: int, mods: Dictionary) -> Control:
	var offer = sim.shop[index]
	var card = ManagementCard.new()
	card.name = "PurchaseOffer_%d" % index
	if offer.type in ["empty", "empty_buff"]:
		var recipe_slot = offer.type == "empty"
		card.build("recipe" if recipe_slot else "star_outline", "菜谱已集齐" if recipe_slot else "暂无增益", Style.MUTED)
		return card
	if offer.type == "recipe":
		var recipe = sim.recipes[offer.id]
		var quality = sim.preview_quality(offer.id)
		var price = sim.meal_price(str(offer.id), quality, mods)
		var seconds = float(recipe.cook_seconds) / (1.0 + float(mods.cook))
		card.build("recipe", recipe.name, Style.GOLD)
		card.heading.add_child(Style.text("菜谱", 13, Style.GOLD))
		var stats = Style.text("%d 金币/份 · %.1f 秒/锅 · %d 份/锅" % [price, seconds, int(recipe.batch_yield)], 14, Style.MUTED)
		stats.tooltip_text = "基础价值 %d 金币 · 当前品质 %d%%\n%s" % [int(recipe.base_value), roundi(quality * 100.0), recipe.description]
		stats.mouse_filter = Control.MOUSE_FILTER_PASS
		card.body.add_child(stats)
	else:
		var buff = sim.buff_defs[offer.id]
		var glyph = {"speed": "move", "cook": "stove", "patience": "clock", "quality": "star",
			"normal_arrivals": "crowd", "eat_time_reduction": "table", "flat_gold": "coins", "reputation": "reputation"}.get(buff.effect_type, "star")
		card.build(glyph, buff.name, Style.GREEN)
		card.heading.add_child(Style.text("%d★" % int(buff.level), 13, Style.GOLD))
		var summary = Style.text("%s · %d 天" % [buff.description, int(buff.duration_days)], 14, Style.MUTED, true)
		var active = sim.buff_states.get(offer.id, {})
		summary.tooltip_text = "当前 %d / %d 层" % [int(active.get("stack_count", 0)), int(buff.max_stacks)]
		summary.mouse_filter = Control.MOUSE_FILTER_PASS
		card.body.add_child(summary)
	var status = sim.purchase_offer_status(index)
	var buy = card.action("已采购" if offer.bought else "%d 金币" % int(offer.price), status.ok, "采购" if status.ok else str(status.error))
	buy.name = "PurchaseOfferAction"
	buy.pressed.connect(_buy.bind(index))
	return card

func _buy(index: int) -> void:
	var status = sim.purchase_offer_status(index)
	if not status.ok:
		_notice(status.error, true)
		return
	var offer = sim.shop[index]
	if offer.type == "buff":
		if _command(sim.buy_offer(index), "已采购，营业时生效。"):
			_show_purchase_page()
		return
	var recipe = sim.recipes[offer.id]
	var box = _new_modal("buy", "购买菜谱", 614)
	var card = ManagementCard.new()
	card.build("recipe", recipe.name, Style.GOLD)
	Style.readout(card.side, "coins", "%d 金币" % int(offer.price), "菜谱价格")
	box.add_child(card)
	if sim.menu.size() >= int(sim.attributes.menu_slots):
		guide.inline_note(box, "menu_full", "换下的菜谱会留在收藏，以后还能换回。")
		for index_to_replace in sim.menu.size():
			var replace = Style.button("替换 " + sim.recipes[sim.menu[index_to_replace]].name, true)
			replace.pressed.connect(_commit_purchase.bind(index, index_to_replace))
			box.add_child(replace)
	else:
		var confirm = Style.button("购买并上架", true)
		confirm.pressed.connect(_commit_purchase.bind(index, -1))
		box.add_child(confirm)
	var back = Style.button("返回采购处")
	back.pressed.connect(_show_purchase_page)
	box.add_child(back)

func _commit_purchase(index: int, slot: int) -> void:
	if _command(sim.buy_offer(index, slot), "新菜谱已上架。"):
		_show_purchase_page()

func _show_menu_page() -> void:
	if sim.phase != "NIGHT": return
	var box = _new_modal("menu",tr("当前菜单"),780)
	box.add_child(Style.text(tr("已上架 %d / %d 道菜。点击槽位换菜，新菜谱可在采购处购买。") % [sim.menu.size(),sim.attributes.menu_slots],15,Style.MUTED,true))
	for slot in range(int(sim.attributes.menu_slots)):
		var row = HBoxContainer.new()
		box.add_child(row)
		var name = tr(str(sim.recipes[sim.menu[slot]].name)) if slot<sim.menu.size() else tr("空槽")
		var button = Style.button(tr("%d  ·  %s    →  选择") % [slot+1,name])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_collection.bind(slot))
		row.add_child(button)
		if slot<sim.menu.size() and sim.menu.size()>1:
			var remove = Style.button(tr("下架"))
			remove.pressed.connect(_remove_menu.bind(slot))
			row.add_child(remove)

func _show_collection(slot: int) -> void:
	if sim.phase != "NIGHT": return
	var box = _new_modal("collection",tr("菜单槽 %d · 选择菜谱") % (slot+1),790)
	box.add_child(Style.text(tr("更换已解锁菜谱免费。菜单多样性会影响客人的随机选菜。"),14,Style.MUTED,true))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = minf(420,get_viewport_rect().size.y-360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id in sim.owned_recipes:
		var r = sim.recipes[id]
		var row = HBoxContainer.new()
		list.add_child(row)
		var label = Style.text(tr("%s\n%d 基础金币 · %.0f 秒 / 锅 · %d 份") % [tr(str(r.name)),r.base_value,r.cook_seconds,r.batch_yield],14,Style.INK,true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button = Style.button(tr("已上架") if id in sim.menu else tr("换入"),id not in sim.menu)
		button.disabled = id in sim.menu
		button.pressed.connect(_commit_menu.bind(slot,id))
		row.add_child(button)
	var back = Style.button(tr("返回菜单"))
	back.pressed.connect(_show_menu_page)
	box.add_child(back)

func _commit_menu(slot: int, id: String) -> void:
	if _command(sim.change_menu(slot,id),tr("菜单已更新。")):
		_show_menu_page()

func _remove_menu(slot: int) -> void:
	if _command(sim.remove_menu(slot),tr("这道菜已下架，仍在收藏中。")):
		_show_menu_page()

func _show_settings() -> void:
	var during_service = sim.phase == "DAY"
	var box = _new_modal("settings", tr("营业已暂停") if during_service else tr("设置"), 560)
	var menu := PAUSE_MENU.instantiate()
	box.add_child(menu)
	menu.get_node("%Chapter").text = tr("%s  ·  第 %d 天") % [tr(str(sim.chapter.title)), sim.day]
	var resume := menu.get_node("%Resume") as Button
	resume.text = tr("继续营业") if during_service else tr("返回餐厅")
	Style.accent_button(resume)
	resume.pressed.connect(func():
		if during_service: sim.paused = false
		_dismiss_modal()
	)
	var focus := menu.get_node("%ResetCamera") as Button
	focus.text = tr("复位视野 [%s]") % keys.text("focus")
	focus.pressed.connect(func(): world.focus_restaurant(); _dismiss_modal())
	var save_run := menu.get_node("%SaveRun") as Button
	save_run.disabled = sim.phase not in ["NIGHT","REPORT"]
	save_run.text = tr("打烊后自动存档") if save_run.disabled else tr("保存进度")
	save_run.pressed.connect(func():
		if _save(): save_run.text = tr("进度已保存")
	)
	menu.get_node("%OpenKeySettings").pressed.connect(_show_key_settings)
	menu.get_node("%Handbook").pressed.connect(_show_handbook)
	var music := menu.get_node("%Music") as Button
	music.text = tr("音乐已关闭") if soundtrack.muted else tr("音乐已开启")
	music.pressed.connect(func():
		soundtrack.set_muted(not soundtrack.muted)
		music.text = tr("音乐已关闭") if soundtrack.muted else tr("音乐已开启")
	)
	menu.get_node("%ReplayGuide").pressed.connect(func(): _close_modal(); guide.replay())
	var disable := menu.get_node("%DisableGuide") as Button
	disable.visible = guide.mode != "off"
	disable.pressed.connect(func(): guide.skip(); _dismiss_modal())
	menu.get_node("%Restart").pressed.connect(_confirm_restart)
	menu.get_node("%TitleMenu").pressed.connect(_return_to_title)
	if sim.phase == "NIGHT":
		var staff_button := Style.button(tr("今日排班"))
		menu.add_child(staff_button)
		staff_button.pressed.connect(_show_shift_roster)
	if not sim.reports.is_empty():
		var history_button := Style.button(tr("历史日报"))
		menu.add_child(history_button)
		history_button.pressed.connect(_show_report_history)
	resume.grab_focus()

func _show_handbook() -> void:
	var box = _new_modal("handbook", tr("阿禾的玩法指南"), 680)
	guide.populate_handbook(box)
	var actions = HFlowContainer.new()
	box.add_child(actions)
	if sim.phase == "NIGHT":
		var practice = Style.button(tr("练习合桌"), true)
		practice.pressed.connect(func(): _close_modal(); guide.teach_tables())
		actions.add_child(practice)
		if not major_notice.is_empty():
			var event = Style.button(tr("查看重大事件"))
			event.pressed.connect(_show_major_event)
			actions.add_child(event)
	var back = Style.button(tr("返回设置"))
	back.pressed.connect(_show_settings)
	actions.add_child(back)

func _show_key_settings() -> void:
	var box = _new_modal("key_settings", tr("按键设置"), 720)
	box.add_child(Style.text(tr("点按右侧键位，再按一个键。Esc 取消改键。"), 15, Style.MUTED))
	box.add_child(Style.text(tr("键盘：Shift＋方向键移动地图指针，Enter 点按或长按，Tab 返回界面。"), 15, Style.MUTED, true))
	box.add_child(Style.text(tr("手柄：方向键切换焦点，A／✕ 确认，B／○ 返回。左摇杆移镜头，右摇杆移指针，肩键缩放。"), 15, Style.MUTED, true))
	box.add_child(Style.text(tr("触屏：点按选择，长按拖动设施。拖动空地平移，双指移动或捏合可平移、缩放。"), 15, Style.MUTED, true))
	var columns = HBoxContainer.new()
	box.add_child(columns)
	var grids = []
	for title in [tr("营业与布置"), tr("打开页面")]:
		var card = Style.card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Style.inset(10,7))
		columns.add_child(card)
		var content = VBoxContainer.new()
		card.add_child(content)
		content.add_child(Style.text(title, 15, Style.GREEN))
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("v_separation", 5)
		grid.add_theme_constant_override("h_separation", 12)
		content.add_child(grid)
		grids.append(grid)
	for action in KeyBindings.ACTIONS:
		var rows = grids[1] if action in ["build", "menu", "upgrades", "trophy_bag", "trophy_shop", "purchase"] else grids[0]
		var label = Style.text(tr(KeyBindings.ACTIONS[action][0]), 15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(label)
		var button = Style.button(keys.text(action))
		button.name = "KeyBind_" + action
		button.custom_minimum_size.x = 102
		button.pressed.connect(_begin_key_binding.bind(action))
		rows.add_child(button)
		binding_buttons[action] = button
	var footer = HBoxContainer.new()
	box.add_child(footer)
	var reset = Style.button(tr("恢复默认"))
	reset.name = "ResetKeyBindings"
	reset.pressed.connect(_reset_key_bindings)
	footer.add_child(reset)
	var back = Style.button(tr("返回设置"))
	back.pressed.connect(_show_settings)
	footer.add_child(back)

func _begin_key_binding(action: String) -> void:
	_end_key_binding()
	binding_action = action
	binding_buttons[action].text = tr("请按键")

func _end_key_binding() -> void:
	if binding_buttons.has(binding_action): binding_buttons[binding_action].text = keys.text(binding_action)
	binding_action = ""
	if modal_frame != null: modal_frame.show_error("")

func _reset_key_bindings() -> void:
	_end_key_binding()
	var error = keys.reset()
	if not error.is_empty():
		modal_frame.show_error(error)
		return
	for action in binding_buttons: binding_buttons[action].text = keys.text(action)
	_update_hud()

func _return_to_title() -> void:
	if sim != null and modal_kind != "restore_error": _save()
	if return_to_title.has_connections():
		return_to_title.emit()
	else:
		get_tree().change_scene_to_file("res://scenes/title.tscn")

func _new_modal(kind: String, title: String, width: int = 780) -> VBoxContainer:
	if world != null: world.stop_follow()
	var opener = modal_opener if modal_layer != null else get_viewport().gui_get_focus_owner()
	var previous_layer = modal_layer if modal_layer != null else fading_modal
	var backdrop_opacity = float(previous_layer.get_child(0).modulate.a) if previous_layer != null else 0.0
	var feature = _modal_feature(kind)
	_close_modal(false, false, feature != null)
	_discard_fading_modal()
	modal_opener = opener
	modal_kind = kind
	if world != null:
		world.cancel_touch()
		if gamepad != null: gamepad.release_pointer()
		world.camera_input_enabled = false
		if feature != null: world.enter_feature(feature, .58 if (not landmark_context.is_empty() and kind != "trophy_shop") or (kind == "major_event" and major_notice.get("id") == "river_lantern_run") else (1.84 if kind == "major_event" else 2.08))
		world.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		ui.overlay.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 20
	add_child(modal_layer)
	var dark = ColorRect.new()
	dark.color = Color("101820", .26 if feature != null else .68)
	modal_layer.add_child(dark)
	_fill(dark)
	modal_frame = MODAL_FRAME.instantiate()
	modal_frame.theme = theme
	modal_layer.add_child(modal_frame)
	_fill(modal_frame)
	if feature != null:
		modal_frame.anchor_left = .38
		modal_frame.offset_right = -14
	modal_frame.build(kind, title, width, _dismiss_modal)
	modal_frame.animate_in(dark, backdrop_opacity)
	return modal_frame.body

func _visit_landmark(id: String) -> void:
	if modal_layer != null: return
	if id == "tavern":
		world.visit_threshold()
		return
	landmark_context = id
	match id:
		"freight":
			if sim.phase == "NIGHT": _show_shift_roster()
			else: _show_settings()
		"supply", "gallery", "workshop":
			var required := str({"supply":"purchase_annex","gallery":"trophy_gallery","workshop":"decor_studio"}[id])
			if sim.phase == "NIGHT" and required in sim.layout.unlocked_plots:
				match id:
					"supply": _show_purchase_page()
					"gallery": _show_trophy_shop()
					"workshop": _show_decoration_shop()
			else:
				var detail := _new_modal("landmark", tr(Plan.LABELS[id]), 480)
				var plot_info := {}
				for plot in sim.layout.plots:
					if plot.id == required: plot_info = plot
				var hint := tr("仅在夜晚采购；白天请观察经营。") if required in sim.layout.unlocked_plots else tr("第 %d 天开放") % int(plot_info.get("open_day",plot_info.get("unlock_day",1)))
				detail.add_child(Style.text(hint,17,Style.INK,true))
				if sim.phase == "NIGHT" and sim.next_land_plot().get("id","") == required:
					var expand := Style.button(tr("确认解锁"))
					detail.add_child(expand)
					expand.pressed.connect(_show_plot_confirmation.bind(required))
		"dock":
			if not sim.reports.is_empty(): _show_report_history()
			else:
				var notice := _new_modal("landmark",tr("下游河埠"),480)
				notice.add_child(Style.text(tr("来客从东岸出发，过木桥，经前场进入餐厅。"),17,Style.INK,true))
				var forecast = _peak_forecast(sim.day)
				if not forecast.is_empty(): notice.add_child(Style.text(forecast,18,Style.GOLD,true))

func _modal_feature(kind: String) -> Variant:
	if not landmark_context.is_empty() and kind != "trophy_shop": return Plan.landmark(landmark_context)
	if world == null or sim == null: return null
	var fixture_id := ""
	match kind:
		"purchase", "buy": fixture_id = "slot"
		"decor_shop": fixture_id = "decor_shop"
		"cashier_front", "cashier": fixture_id = "cashier"
		"trophy_shop": return Vector2(sim.trophy_shop_cell())
		"major_event":
			match str(major_notice.get("id", "")):
				"food_inspection": fixture_id = "pass"
				"group_booking":
					for table in Grid.facilities(sim.layout, "table"):
						if Grid.placed(table) and Grid.table_size(table) == 4:
							return Grid.vec(table.pos)
					fixture_id = "table_3"
				"bad_weather": return Grid.vec(sim.layout.entrance) + Vector2(-5, -2)
				"river_lantern_run": return Plan.landmark("wood_bridge") + Vector2(4,8)
				_: return Grid.vec(sim.layout.entrance) + Vector2(-.8, .65)
	if fixture_id.is_empty(): return null
	var fixture := Grid.find(sim.layout, fixture_id)
	return Grid.vec(fixture.pos) if not fixture.is_empty() else null

func _discard_fading_modal() -> void:
	if fading_modal == null: return
	remove_child(fading_modal)
	fading_modal.queue_free()
	fading_modal = null

func _close_modal(restore_focus := true, animate := false, preserve_feature := false) -> void:
	if modal_layer != null:
		binding_action = ""
		binding_buttons.clear()
		if animate:
			_discard_fading_modal()
			fading_modal = modal_layer
			modal_frame.animate_out(fading_modal.get_child(0), _discard_fading_modal)
		else:
			remove_child(modal_layer)
			modal_layer.queue_free()
		modal_layer = null
		modal_frame = null
		trophy_box = null
		if world != null:
			ui.overlay.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
			world.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		if restore_focus and is_instance_valid(modal_opener) and modal_opener.is_visible_in_tree():
			modal_opener.grab_focus()
		modal_opener = null
	modal_kind = ""
	if world != null:
		world.camera_input_enabled = true
		if not preserve_feature:
			landmark_context = ""
			world.end_feature()

func _dismiss_modal() -> void:
	landmark_context = ""
	_close_modal(true, sim.phase != "REPORT")
	if sim.phase == "REPORT": _show_report()

func _peak_forecast(for_day: int, compact := false) -> String:
	for event in sim.events_for(for_day):
		if not event.has("arrival_peak"): continue
		var peak = event.arrival_peak
		var period = MajorEventPanel.peak_time(peak)
		var share = roundi(float(peak.share) * 100)
		if compact: return "%s · %d%%" % [period, share]
		return tr("%s\n%s 集中约 %d%%") % [tr(str(event.name)), period, share]
	return ""

func _show_diagnostic_on_map(r: Dictionary) -> void:
	var key = str(r.diagnosis.focus)
	if key.is_empty(): return
	var description = ReportPanel.DIAGNOSTIC_TEXT[key]
	var facilities = description.facilities + r.diagnosis.stages[key].tables
	world.set_diagnostic_targets(facilities, key == "queue", true)
	ui.diagnostic_label.text = tr(str(description.label))
	ui.diagnostic_button.text = tr("返回日报")
	ui.diagnostic_card.show()

func _preview_report_diagnosis() -> void:
	_close_modal(true, true)
	_show_diagnostic_on_map(sim.last_report)
	ui.diagnostic_button.grab_focus()

func _clear_diagnostic() -> void:
	world.set_diagnostic_targets([], false)
	ui.diagnostic_card.hide()

func _dismiss_diagnostic() -> void:
	if sim.phase == "REPORT":
		_show_report()
	else:
		_clear_diagnostic()

func _show_report(reveal_rewards := false) -> void:
	_clear_diagnostic()
	ui.info_panel.hide()
	status_timer = 0.0
	ui.toast_card.hide()
	report_shown_day = sim.day
	var report = sim.last_report.merged({
		"gold_after": sim.gold, "reputation_after": sim.reputation, "stars_after": sim.stars, "day": sim.day,
	}, true)
	var outcome = tr("营业复盘") if report.result == "CONTINUE" else (tr("章节胜利") if report.result == "WIN" else tr("房租不足"))
	var box = _new_modal("report",tr("第 %d 天 · %s") % [sim.day,outcome],1060)
	var panel = REPORT_PANEL.instantiate()
	box.add_child(panel)
	panel.locate_requested.connect(_preview_report_diagnosis)
	panel.continue_requested.connect(_continue_night)
	panel.restart_requested.connect(_confirm_restart)
	panel.return_requested.connect(_return_to_title)
	panel.history_requested.connect(_show_report_history)
	var previous: Dictionary = sim.reports[-2] if sim.reports.size() >= 2 else {}
	var next_day = sim.day + 1
	var peak = _peak_forecast(next_day) if report.result == "CONTINUE" else ""
	var notices: Array[String] = []
	if not peak.is_empty():
		notices.append(peak.replace("\n", "  "))
	if report.result == "CONTINUE":
		for event in sim.major_events_for(next_day):
			if int(event.from_day) == next_day and not peak.begins_with(tr(str(event.name)) + "\n"):
				notices.append(tr(str(event.name)))
	panel.populate(report, previous, sim.catalog, notices, guide.report_text(report, peak))
	if reveal_rewards: panel.reveal_earned_goals()

func _show_report_history() -> void:
	if sim.reports.is_empty(): return
	var box = _new_modal("report_history", tr("历史日报"), 970)
	var panel = ReportHistory.new()
	box.add_child(panel)
	panel.populate(sim.reports, sim.catalog)

func _continue_night() -> void:
	if _command(sim.continue_night(), tr("夜晚准备")):
		_close_modal(true, true)
		report_shown_day = -1
		accumulator = 0
		fast_forward = false
		world.cancel_placement()
		inspected = {}
		_refresh_all()
		guide.night()

func _confirm_restart() -> void:
	var box = _new_modal("restart",tr("重新开始本章？"),570)
	box.add_child(Style.text(tr("会替换当前检查点。旧版本档案在首次覆盖前会留作备份。"),15,Style.MUTED,true))
	var seed_input = LineEdit.new()
	seed_input.placeholder_text = tr("可选：输入整数种子复现同一局")
	box.add_child(seed_input)
	var confirm = Style.button(tr("确认重新开局"))
	confirm.add_theme_stylebox_override("normal", Style.box(Color("643f3e"), Style.RED.darkened(.28), 7, 10))
	confirm.add_theme_color_override("font_color", Color("ffe1cf"))
	confirm.pressed.connect(func(): _choose_restart_crew(int(seed_input.text) if seed_input.text.is_valid_int() else int(Time.get_ticks_usec()%1000000000)))
	box.add_child(confirm)
	var cancel = Style.button(tr("取消"), true)
	cancel.pressed.connect(_dismiss_modal)
	box.add_child(cancel)

func _show_shift_roster() -> void:
	if sim.phase != "NIGHT": return
	var body := _new_modal("crew_setup", tr("今日排班"), 810)
	var chooser := CREW_SELECT.instantiate()
	chooser.initial_lineup = sim.crew_lineup
	chooser.shift_only = true
	chooser.helper_staff = sim.helper_staff.duplicate(true)
	chooser.capacity = {"chef":sim.attributes.chefs,"waiter":sim.attributes.waiters}
	body.add_child(chooser)
	chooser.cancelled.connect(_dismiss_modal)
	chooser.accepted.connect(func(lineup):
		if not lineup.is_empty() and not sim.set_crew(lineup): return
		sim.helper_staff=chooser.helper_staff.duplicate(true)
		_save()
		_refresh_all()
		_dismiss_modal()
	)

func _choose_restart_crew(new_seed: int) -> void:
	_new_modal("crew_setup",tr("选择本局英雄"),810)
	modal_frame.hide()
	var chooser := preload("res://scenes/ui/opening_draft.tscn").instantiate()
	chooser.chapter_caption = tr(str(sim.chapter.title))
	modal_layer.add_child(chooser)
	chooser.cancelled.connect(_dismiss_modal)
	chooser.accepted.connect(func(lineup):
		if sim.set_crew(lineup):
			sim.helper_staff=chooser.helper_staff.duplicate(true)
			_restart_run(new_seed)
	)

func _restart_run(new_seed: int) -> void:
	_close_modal()
	_discard_fading_modal()
	_clear_diagnostic()
	sim.new_run(new_seed)
	pending_major_event = ""
	service_feedback.reset()
	world.reset_scene_time()
	report_shown_day = -1
	fast_forward = false
	accumulator = 0
	_close_build_page()
	world.focus_restaurant()
	ui.info_panel.hide()
	inspected = {}
	_save()
	_refresh_all()
	guide.start_visit()
	if guide.stage.is_empty(): _notice(tr("新开局"))

func _input(event: InputEvent) -> void:
	if world != null and world.entering_canyon: return
	if gamepad != null: gamepad.handle(event, self)
	if world != null and (event.is_pressed() or event is InputEventGesture):
		world.stop_follow()
	if sim == null or keys == null or not event is InputEventKey or not event.pressed or event.echo: return
	var key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var modified = event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed
	if binding_action.is_empty():
		if modal_layer != null or modified or get_viewport().gui_get_focus_owner() is LineEdit: return
		var action = keys.action_for(key)
		if not action.is_empty():
			get_viewport().set_input_as_handled()
			_activate_shortcut(action)
		return
	get_viewport().set_input_as_handled()
	var error = ""
	if key != KEY_ESCAPE:
		error = tr("请直接按一个键。") if modified else keys.bind(binding_action, key)
	if not error.is_empty():
		modal_frame.show_error(error)
		return
	_end_key_binding()
	_update_hud()

func _unhandled_key_input(event: InputEvent) -> void:
	if sim == null or not event is InputEventKey or not event.pressed or event.echo: return
	var key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_TAB and _focus_controls():
		get_viewport().set_input_as_handled()
		return
	if key != KEY_ESCAPE: return
	_go_back()

func _focus_controls() -> bool:
	if get_viewport().gui_get_focus_owner() != null or sim == null: return false
	var target: Control = null
	if world.signs.is_visible_in_tree() and modal_frame == null:
		world.signs.focus_tavern()
		return true
	if modal_frame != null:
		modal_frame._focus_first()
		return get_viewport().gui_get_focus_owner() != null
	if is_instance_valid(guide) and is_instance_valid(guide.bubble):
		for child in guide.bubble.actions.get_children():
			if child is Button and child.is_visible_in_tree() and not child.disabled:
				target = child
				break
	if target == null:
		target = ui.open if ui.open.is_visible_in_tree() and not ui.open.disabled else ui.gear
	target.grab_focus()
	return true

func _go_back() -> void:
	if modal_layer != null:
		if not binding_action.is_empty(): _end_key_binding()
		elif modal_kind in ["key_settings", "handbook"]: _show_settings()
		elif modal_kind not in ["report", "restore_error", "config_error"]: _dismiss_modal()
	elif world.overview:
		world.focus_restaurant()
	elif world.editing or world.placing_wall or world.drag_active:
		_cancel_placement()
	elif ui.build_catalog.visible:
		_close_build_page()
	elif ui.diagnostic_card.visible:
		_dismiss_diagnostic()
	else:
		var had_inspector: bool = ui.info_panel.visible or not inspected.is_empty()
		world.cancel_placement()
		_clear_inspector()
		if not had_inspector: _show_settings()

func _activate_shortcut(action: String) -> void:
	match action:
		"open": _open_day()
		"pause": _toggle_pause()
		"focus": world.focus_restaurant()
		"fast": _toggle_fast()
		"menu": _show_menu_page()
		"rotate": _rotate_selection()
		"split": _split_selection()
		"store": _store_selection()
		"build": _show_build_page()
		"upgrades": _show_cashier_page()
		"trophy_bag": _show_trophy_bag()
		"trophy_shop": _show_trophy_shop()
		"purchase": _show_purchase_page()
