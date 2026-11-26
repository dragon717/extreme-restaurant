extends Control

const Sim = preload("res://scripts/core/simulation.gd")
const Catalog = preload("res://scripts/core/catalog.gd")
const Store = preload("res://scripts/core/save_store.gd")
const ChapterProgress = preload("res://scripts/core/chapter_progress.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Decor = preload("res://scripts/core/decoration_effects.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const World = preload("res://scripts/ui/world_view.gd")
const DayBadge = preload("res://scripts/ui/day_badge.gd")
const Actor = preload("res://scripts/visuals/actor_view.gd")
const ModalFrame = preload("res://scripts/ui/modal_frame.gd")
const ServiceFeedback = preload("res://scripts/ui/service_feedback.gd")
const Guide = preload("res://scripts/ui/restaurant_guide.gd")
const ReportPanel = preload("res://scripts/ui/report_panel.gd")
const ReportHistory = preload("res://scripts/ui/report_history.gd")
const GuestProfile = preload("res://scripts/ui/guest_profile.gd")
const MajorEventPanel = preload("res://scripts/ui/major_event_panel.gd")
const KeyBindings = preload("res://scripts/ui/key_bindings.gd")
const BuildCatalog = preload("res://scripts/ui/build_catalog.gd")

signal return_to_title

var chapter_id = Catalog.DEFAULT_CHAPTER
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
var modal_opener: Control
var fading_modal: CanvasLayer
var save_path = ""
var testing = false
var inspected: Dictionary = {}
var selected_offer = 0
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
	theme = Style.theme()
	if not OS.has_feature("web"):
		DisplayServer.window_set_min_size(Vector2i(1100, 720))
	sim = Sim.new(Catalog.load_all(chapter_id))
	if not sim.catalog.errors.is_empty():
		var box = _new_modal("config_error", "无法载入章节", 640)
		box.add_child(Style.text("\n".join(sim.catalog.errors), 16, Style.INK, true))
		var leave = Style.button("返回章节", true)
		leave.pressed.connect(_return_to_title)
		box.add_child(leave)
		set_process(false)
		sim = null
		return
	testing = "--ui-test" in OS.get_cmdline_user_args()
	keys = KeyBindings.new(Store.default_path("keyboard_bindings", testing))
	save_path = Store.default_path(chapter_id, testing)
	var saved = Store.read_checkpoint(save_path)
	var load_message = ""
	if not saved.is_empty():
		var result = sim.restore_state(saved)
		if not result.ok: load_message = result.error
	_build_interface()
	guide = Guide.new()
	add_child(guide)
	if tutorial_path.is_empty(): tutorial_path = Store.default_path("tutorial_progress", testing)
	guide.setup(self, tutorial_path)
	get_window().focus_exited.connect(_on_focus_lost)
	if load_message.is_empty(): _save()
	_refresh_all()
	if load_message.is_empty():
		guide.start_visit()
		if sim.phase == "REPORT": _show_report()
	if not load_message.is_empty():
		var box = _new_modal("restore_error", "无法恢复旧检查点", 650)
		box.add_child(Style.text(load_message + "\n旧存档不会自动迁移或覆盖。",16,Style.MUTED,true))
		var restart = Style.button("建立新局（旧档留作备份）",true)
		restart.pressed.connect(func(): _restart_run(int(Time.get_ticks_usec() % 1000000000)))
		box.add_child(restart)
		var leave = Style.button("暂不更改，返回主界面")
		leave.pressed.connect(_return_to_title)
		box.add_child(leave)

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
	world = World.new()
	world.sim = sim
	add_child(world)
	_fill(world)
	world.move_requested.connect(_move_facility)
	world.wall_requested.connect(_place_wall)
	world.drag_started.connect(func():
		ui.info_panel.hide()
		ui.slot_panel.hide()
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
	ui.rent_card = Style.card()
	ui.rent_card.add_theme_stylebox_override("panel", Style.surface(Style.GREEN, 8))
	overlay.add_child(ui.rent_card)
	_rect(ui.rent_card, 14, 14, 184, 61)
	var rent_row = HBoxContainer.new()
	ui.rent_card.add_child(rent_row)
	ui.rent_label = Style.readout(rent_row, "rent", "", "下次房租")
	ui.rent_days = Style.readout(rent_row, "clock", "", "离下次缴租的天数", Style.MUTED, 14)
	ui.peak_card = Style.card()
	ui.peak_card.add_theme_stylebox_override("panel", Style.surface(Style.GOLD, 8))
	overlay.add_child(ui.peak_card)
	_rect(ui.peak_card, 14, 70, 203, 112)
	ui.peak_label = Style.readout(ui.peak_card, "crowd", "", "客流高峰", Style.GOLD, 14)
	ui.peak_card.hide()
	ui.diagnostic_card = Style.card()
	ui.diagnostic_card.add_theme_stylebox_override("panel", Style.surface(Style.GOLD, 8))
	overlay.add_child(ui.diagnostic_card)
	_rect(ui.diagnostic_card, 14, 123, 240, 207)
	var diagnostic_body = VBoxContainer.new()
	ui.diagnostic_card.add_child(diagnostic_body)
	ui.diagnostic_label = Style.text("", 15, Style.GOLD)
	diagnostic_body.add_child(ui.diagnostic_label)
	ui.diagnostic_button = Style.button("")
	ui.diagnostic_button.pressed.connect(_dismiss_diagnostic)
	diagnostic_body.add_child(ui.diagnostic_button)
	ui.diagnostic_card.hide()
	var top_center = CenterContainer.new()
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(top_center)
	_rect(top_center, -272, 8, 272, 72, .5, 0)
	var top_row = HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(top_row)
	ui.badge = DayBadge.new()
	top_row.add_child(ui.badge)
	var time_card = Style.card()
	time_card.custom_minimum_size.y = 45
	time_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_card.add_theme_stylebox_override("panel", Style.surface(Style.MUTED, 7))
	top_row.add_child(time_card)
	var time_row = HBoxContainer.new()
	time_card.add_child(time_row)
	ui.clock = Style.readout(time_row, "clock", "09:00", "")
	ui.cleanup = Icon.make("door", Style.GOLD, 18.0)
	time_row.add_child(ui.cleanup)
	ui.cleanup.hide()
	var resources = Style.card()
	resources.custom_minimum_size.y = 45
	resources.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resources.add_theme_stylebox_override("panel", Style.surface(Style.MUTED, 8))
	top_row.add_child(resources)
	var resources_row = HBoxContainer.new()
	resources_row.add_theme_constant_override("separation", 13)
	resources.add_child(resources_row)
	ui.income_label = Style.readout(resources_row, "income", "0$", "今日收入")
	ui.gold_label = Style.readout(resources_row, "coins", "0$", "持有金币")
	ui.rep_label = Style.readout(resources_row, "reputation", "0", "声望", Style.GREEN)
	ui.star_label = Style.readout(resources_row, "star", "0", "闪星 · 购买地块扩建和奖杯")
	ui.gear = _icon_button("settings", "设置")
	overlay.add_child(ui.gear)
	_rect(ui.gear, -61, 14, -14, 61, 1, 0)
	ui.gear.pressed.connect(_show_settings)
	ui.history = _icon_button("history", "历史日报")
	ui.history.name = "OpenReportHistory"
	overlay.add_child(ui.history)
	_rect(ui.history, -232, 14, -179, 61, 1, 0)
	ui.history.pressed.connect(_show_report_history)
	ui.district = _icon_button("district", "街区全景 · F 返回餐厅")
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
	ui.open = Style.button("开店",true)
	ui.open.add_theme_font_size_override("font_size",21)
	overlay.add_child(ui.open)
	_rect(ui.open, -104, -67, 104, -19, .5, 1)
	ui.open.pressed.connect(_open_day)
	ui.skills = preload("res://scenes/service_skills.tscn").instantiate()
	overlay.add_child(ui.skills)
	_rect(ui.skills, -158, -67, 158, -19, .5, 1)
	ui.rush = ui.skills.get_node("Rush")
	ui.rush.pressed.connect(func():
		if guide.blocks_clock or not modal_kind.is_empty(): return
		if sim.call_current(): _update_hud()
	)
	ui.menu = _icon_button("recipe", "菜谱")
	overlay.add_child(ui.menu)
	_rect(ui.menu, -65, -67, -18, -19, 1, 1)
	ui.menu.pressed.connect(_show_menu_page)
	ui.build = _icon_button("build", "建造")
	ui.build.name = "OpenBuildInventory"
	overlay.add_child(ui.build)
	_rect(ui.build, -124, -67, -77, -19, 1, 1)
	ui.build.pressed.connect(_show_build_page)
	ui.trophy_bag = _icon_button("bag", "奖杯背包")
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
	ui.info_follow = _icon_button("follow", "镜头跟随")
	ui.info_follow.name = "FollowNpc"
	ui.info_follow.custom_minimum_size.x = 40
	info_header.add_child(ui.info_follow)
	ui.info_follow.pressed.connect(_follow_inspected)
	ui.info_follow.hide()
	var close = _icon_button("close", "关闭")
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
		["move", "move", "移动", _begin_move],
		["rotate", "rotate", "旋转", _rotate_selection],
		["split", "split", "拆分餐桌", _split_selection],
		["store", "store", "收起", _store_selection],
		["cancel_placement", "close", "取消布置 [Esc]", _cancel_placement],
	]:
		var button = _icon_button(tool[1], tool[2])
		button.custom_minimum_size = Vector2(44, 44)
		button.pressed.connect(tool[3])
		ui.action_bar.add_child(button)
		ui[tool[0]] = button
		button.hide()
	ui.info_panel.visible = false
	ui.slot_panel = Style.card()
	ui.slot_panel.add_theme_stylebox_override("panel",Style.surface(Style.GOLD, 15))
	overlay.add_child(ui.slot_panel)
	_rect(ui.slot_panel,-360,150,-18,347,1,0)
	var slot_body = VBoxContainer.new()
	ui.slot_panel.add_child(slot_body)
	var slot_header = HBoxContainer.new()
	slot_body.add_child(slot_header)
	var slot_title = Style.text("采购处",22,Style.GOLD)
	slot_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_header.add_child(Icon.make("coins", Style.GOLD, 22))
	slot_header.add_child(slot_title)
	var slot_close = _icon_button("close", "关闭")
	slot_close.pressed.connect(func():
		ui.slot_panel.hide()
		_clear_inspector()
	)
	slot_header.add_child(slot_close)
	slot_body.add_child(Style.text("每晚到货一道菜谱、两项增益。选中商品即可查看价格和效果。",15,Style.INK,true))
	ui.slot_hint = Style.text("",14,Style.MUTED,true)
	slot_body.add_child(ui.slot_hint)
	ui.enter_shop = Style.button("进入采购",true)
	ui.enter_shop.pressed.connect(_show_purchase_page)
	slot_body.add_child(ui.enter_shop)
	ui.slot_panel.visible = false
	service_feedback = ServiceFeedback.new()
	service_feedback.wallet = ui.gold_label
	service_feedback.z_index = 2
	overlay.add_child(service_feedback)
	_fill(service_feedback)
	for label in [ui.income_label, ui.gold_label, ui.rep_label, ui.star_label]:
		service_feedback.attach_counter(label)

func _process(delta: float) -> void:
	if sim == null: return
	if status_timer > 0: status_timer -= delta
	_advance_major_event_popup(delta)
	var tick_seconds = float(sim.tick_ms) / 1000.0
	var clock_held = sim.paused or guide.blocks_clock or modal_kind == "report_history"
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
	var night = sim.phase == "NIGHT"
	if not night and ui.build_catalog.visible: _close_build_page()
	_sync_build_dock()
	ui.fast.visible = sim.phase == "DAY"
	if sim.phase != "DAY": _hide_special_notice()
	ui.pause.visible = sim.phase == "DAY"
	ui.slot_hint.text = "仅在夜晚采购；白天请观察经营。" if not night else "今晚商品已准备好，价格在采购页查看。"
	ui.enter_shop.disabled = not night
	if not night:
		ui.info_panel.hide()
		ui.slot_panel.hide()
	_update_hud()

func _update_hud() -> void:
	if sim == null: return
	if sim.phase == "NIGHT" and opening_check_revision != sim.revision:
		var errors = sim.opening_errors()
		opening_issue = "" if errors.is_empty() else str(errors[0])
		opening_check_revision = sim.revision
	ui.open.disabled = sim.phase != "NIGHT" or not opening_issue.is_empty()
	ui.skills.visible = sim.phase == "DAY"
	if ui.skills.visible:
		var remaining := maxi(0, sim.current_ready - sim.tick)
		ui.rush.disabled = remaining > 0 or sim.paused or guide.blocks_clock or not modal_kind.is_empty()
		ui.rush.text = "河道急送" if remaining == 0 else "急送 · %d秒" % ceili(remaining * sim.tick_ms / 1000.0)
	ui.history.disabled = sim.reports.is_empty()
	ui.history.tooltip_text = "历史日报" if not ui.history.disabled else "完成首日营业后可查看历史日报"
	if sim.phase == "NIGHT":
		var expected_groups = ["开店 [%s]" % keys.text("open")]
		var seats = Grid.facilities(sim.layout, "table")
		for group in sim.chapter.guest_groups:
			var size = int(group.size)
			if not seats.any(func(f): return Grid.table_size(f) == size):
				expected_groups.append("第 %d 天起可能到店 %d 人组，需要%s" % [int(group.from_day), size, Grid.table_label(size)])
		ui.open.tooltip_text = opening_issue if not opening_issue.is_empty() else "\n".join(expected_groups)
	var weather = sim.weather_for().preset
	ui.badge.set_state(sim.day,sim.phase,clampf(float(sim.tick)/maxi(1,sim.day_ticks),0,1))
	ui.badge.set_weather(float(weather.rain) > 0.0, weather.has("thunder"))
	service_feedback.show_resource(ui.income_label, int(sim.stats.get("income", 0)), "$")
	service_feedback.show_resource(ui.gold_label, int(sim.gold), "$")
	service_feedback.show_resource(ui.rep_label, int(sim.reputation))
	service_feedback.show_resource(ui.star_label, int(sim.stars))
	var rent = sim.next_rent()
	ui.rent_label.text = "$%d" % int(rent.amount) if not rent.is_empty() else "已付清"
	ui.rent_days.get_parent().visible = not rent.is_empty()
	ui.rent_days.text = "%d天" % maxi(0, int(rent.get("day", sim.day)) - sim.day)
	var event_names = []
	for event in sim.events_for(): event_names.append(str(event.name))
	_sync_major_notice()
	ui.rent_card.tooltip_text = ("房租 · 第 %d 天缴 %d 金币" % [int(rent.day), int(rent.amount)] if not rent.is_empty() else "本章房租已全部缴清") + ("\n" + "、".join(event_names) if not event_names.is_empty() else "")
	ui.rent_label.tooltip_text = ui.rent_card.tooltip_text
	ui.rent_label.get_parent().tooltip_text = ui.rent_card.tooltip_text
	var peak = _peak_forecast(sim.day, true)
	ui.peak_card.visible = not peak.is_empty() and sim.phase in ["NIGHT", "DAY"]
	ui.peak_label.text = peak
	ui.peak_label.tooltip_text = _peak_forecast(sim.day)
	ui.peak_label.get_parent().tooltip_text = ui.peak_label.tooltip_text
	ui.clock.text = sim.clock_text() if sim.phase == "DAY" else ("09:00" if sim.phase == "NIGHT" else "00:00")
	ui.cleanup.visible = sim.phase == "DAY" and sim.tick >= sim.day_ticks
	ui.clock.tooltip_text = "午夜解散队伍，已入座客人继续用餐" if ui.cleanup.visible else "09:00–21:00 接客，00:00 解散队伍"
	ui.clock.get_parent().tooltip_text = ui.clock.tooltip_text
	ui.pause_icon.set_glyph("play" if sim.paused else "pause", Style.INK)
	ui.fast.text = "%d×" % int(sim.chapter.fast_forward_multiplier) if fast_forward else "1×"
	ui.fast.tooltip_text = ("当前8倍速 · 点击恢复正常" if fast_forward else "当前正常速度 · 点击快进") + " [%s]" % keys.text("fast")
	if bool(ui.fast.get_meta("active_visual", false)) != fast_forward:
		ui.fast.set_meta("active_visual", fast_forward)
		if fast_forward:
			ui.fast.add_theme_stylebox_override("normal", Style.box(Style.GOLD, Color("f6d28c"), 9, 7))
			ui.fast.add_theme_color_override("font_color", Color("233729"))
		else:
			ui.fast.remove_theme_stylebox_override("normal")
			ui.fast.remove_theme_color_override("font_color")
	ui.pause.tooltip_text = ("继续营业" if sim.paused else "暂停观察") + " [%s]" % keys.text("pause")
	ui.menu.tooltip_text = "菜谱 [%s]" % keys.text("menu")
	ui.build.tooltip_text = "建造 [%s]" % keys.text("build")
	ui.trophy_bag.tooltip_text = "奖杯背包 [%s]" % keys.text("trophy_bag")
	ui.rotate.tooltip_text = "顺时针旋转 [%s]" % keys.text("rotate")
	ui.split.tooltip_text = "拆分餐桌 [%s]" % keys.text("split")
	ui.store.tooltip_text = "收起 [%s]" % keys.text("store")
	_sync_build_tools()
	if sim.phase == "DAY" and sim.tick >= sim.day_ticks:
		ui.badge.tooltip_text = "21:00 停止新客到店 · 00:00 解散排队 · 等店内客人离开后结算"
	else:
		ui.badge.tooltip_text = "夜晚规划" if sim.phase == "NIGHT" else "营业接客中"
	ui.badge.tooltip_text += " · " + str(weather.name)
	ui.toast_card.modulate.a = clampf(status_timer / 0.4, 0, 1) if status_timer > 0 else 1.0
	if sim.phase == "NIGHT" and not opening_issue.is_empty() and status_timer <= 0:
		ui.toast_card.show()
		_set_toast_text("开店前需要处理：" + opening_issue, true)
	elif status_timer <= 0:
		ui.toast_card.hide()
	if not inspected.is_empty() and ui.info_panel.visible:
		_update_inspector()

func _build_special_notice(overlay: Control) -> void:
	var notice = Style.card()
	notice.name = "SpecialGuestNotice"
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin = Style.surface(Color("e2a78e"), 10)
	skin.modulate_color = Color("e6cabf")
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
	copy.add_child(Style.text("特别来客", 12, Color("ebbe9d")))
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
	ui.special_caption.text = "%s 到店" % profile.name if size == 1 else "%d 位%s同行到店" % [size, profile.name]
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

func _save() -> void:
	if sim.phase not in ["NIGHT","REPORT"]: return
	var checkpoint = sim.export_state()
	var error = Store.write_checkpoint(checkpoint, save_path)
	if error.is_empty() and sim.phase == "REPORT" and sim.last_report.get("result", "") == "WIN":
		error = ChapterProgress.record_win(checkpoint, testing)
	if not error.is_empty(): _notice(error,true)

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

func _command(result: Dictionary, message: String = "已更新") -> bool:
	if not result.ok:
		_notice(result.get("error","操作失败"),true)
		return false
	_save()
	_refresh_all()
	_notice(message)
	return true

func _open_day() -> void:
	if sim.phase != "NIGHT" or modal_layer != null or ui.build_catalog.visible: return
	_save()
	if _command(sim.start_day(), "已开店"):
		guide.opened()
		_clear_diagnostic()
		accumulator = 0
		fast_forward = false
		world.cancel_placement()
		ui.info_panel.hide()
		ui.slot_panel.hide()
		_refresh_all()

func _on_focus_lost() -> void:
	if is_instance_valid(world):
		world.stop_follow()
		world.cancel_drag()
	if sim != null and sim.phase == "DAY":
		sim.paused = true
		accumulator = minf(accumulator, float(sim.tick_ms) / 1000.0)
		_update_hud()
		_notice("窗口失去焦点，营业已暂停。")

func _toggle_pause() -> void:
	if sim.phase != "DAY": return
	sim.paused = not sim.paused
	_update_hud()

func _toggle_fast() -> void:
	if sim.phase != "DAY": return
	fast_forward = not fast_forward
	_update_hud()

func _inspect(kind: String, id: String) -> void:
	if kind == "trophy_shop":
		_show_trophy_shop()
		return
	if kind == "facility":
		if id == "decor_shop":
			_show_decoration_shop()
			return
		world.selected_id = id
		if id == "cashier":
			_sync_build_tools()
			_show_cashier_front()
			return
		if id == "slot":
			ui.info_panel.hide()
			ui.slot_panel.show()
			_sync_build_tools()
			guide.purchase()
			return
	if kind == "plot":
		_show_plot_confirmation(id)
		return
	if kind == "customer" and not sim.customers.has(int(id)): return
	if kind == "staff" and (sim.phase != "DAY" or sim.staff_member(int(id)).is_empty()): return
	if kind == "preview" and sim.phase != "NIGHT": return
	if kind == "preview": world.selected_id = id
	ui.slot_panel.hide()
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
	ui.info_follow.tooltip_text = "跟随中 · 点击场景或按键退出" if following else "镜头跟随"
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
			var role = "厨师" if id.begins_with("preview_chef_") else "服务员"
			ui.info_title.text = "%s %d · 预备中" % [role, int(id.get_slice("_", 2)) + 1]
			var count = int(sim.attributes.chefs if role == "厨师" else sim.attributes.waiters)
			ui.info_body.text = "已雇佣 %d 位 · 可拖动调整开店站位" % count
		"facility":
			if f.is_empty(): ui.info_panel.hide(); return
			ui.info_title.text = f.name
			var detail = ""
			match str(f.type):
				"table":
					var size = Grid.table_size(f)
					detail = "%s · %d 座" % [Grid.table_label(size), size]
					if sim.phase == "NIGHT" and size < 4:
						detail += "\n长按拖到同规格餐桌可合成%s。" % Grid.table_label(size * 2)
					if size > 1: detail += "\n为 %d 人组整桌留座。" % size
				"stove": detail = "厨师在此烹饪，做好后会把菜搬到出餐口。" + _efficiency_buff("cook")
				"order": detail = "服务员交单，厨师接单。四面可操作。"
				"pass": detail = "厨师放餐，服务员取餐。四面可操作。"
				"wall": detail = "隔开走道与用餐区域。可移动或收起。"
				"decoration":
					var definition = sim.decoration_defs[f.decoration_id]
					detail = Decor.description(definition)
					if sim.phase == "NIGHT":
						var affected = 0
						var cells = Decor.coverage(f, definition, sim.layout)
						for target in sim.layout.facilities:
							if Grid.placed(target) and Decor.affects(target, definition, cells): affected += 1
						if definition.effect != "waiter_speed": detail += "\n当前覆盖 %d 处" % affected
						detail += "\n点击移动工具可预览范围。"
				"trophy":
					var relic = sim.relic_defs[str(f.relic_id)]
					detail = relic.description + "\n常驻效果仅在展示区放下后生效。\n已展示 %d / %d" % [Grid.facilities(sim.layout,"trophy").size(),int(sim.attributes.relic_slots)]
			ui.info_body.text = detail
		"staff":
			var person = sim.staff_member(int(id))
			if person.is_empty():
				_clear_inspector()
				return
			var chef = person.role == "chef"
			ui.info_glyph.set_glyph("stove" if chef else "crowd", Style.GREEN)
			ui.info_title.text = "%s #%d" % ["厨师" if chef else "服务员", person.id]
			var actions = {"ORDER":"给客人点单","SUBMIT":"送订单到厨房","COOK":"正在烹饪","COLLECT":"领取灶台食物","TRANSFER":"搬运到出餐口","PICKUP":"取餐","DELIVER":"给客人上菜","RETURN":"返还食物"}
			ui.info_body.text = "当前：%s\n手持食物：%d 份" % [person.reason if person.task.is_empty() else actions.get(person.task.kind,"正在工作"), person.carry_food.size()]
		"customer":
			var customer_id = int(id)
			var customer = sim.customers.get(customer_id, {})
			if customer.is_empty():
				_clear_inspector()
				return
			var profile = sim.guest_defs[customer.type]
			ui.info_title.text = str(profile.name)
			var traits = _guest_effect(profile) if profile.rarity != "normal" else ""
			if profile.get("unlimited_food_wait", false):
				traits = "会一直等到上菜 · 每轮扣 %d 声望" % int(profile.food_penalty_per_cycle)
			elif customer.type == "food_inspector":
				traits = "用餐时间为平时的 %d 倍 · 会评价餐品品质" % int(profile.eat_time_multiplier)
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
			lines += "\n增益 (%s%d%%)：%s · %s" % [sign,increase,str(buff.name),str(buff.description)]
	for trophy in Grid.facilities(sim.layout,"trophy"):
		var relic = sim.relic_defs[str(trophy.relic_id)]
		if str(relic.effect_type) == effect:
			lines += "\n常驻 (%s%d%%)：%s · %s" % [sign,int(round(float(relic.effect_value)*100.0)),str(relic.name),str(relic.description)]
	return lines

func _guest_effect(guest: Dictionary) -> String:
	var parts = []
	if guest.get("payment_override", "") == "ZERO":
		parts.append("结账金币为0")
	elif not is_equal_approx(float(guest.type_payment_multiplier),1.0):
		parts.append("金币倍率 ×%.1f" % float(guest.type_payment_multiplier))
	if not is_equal_approx(float(guest.get("choose_time_multiplier",1)),1.0):
		parts.append("选菜时间 ×%.1f" % float(guest.choose_time_multiplier))
	if not is_equal_approx(float(guest.get("eat_time_multiplier",1)),1.0):
		parts.append("用餐时间 ×%.1f" % float(guest.eat_time_multiplier))
	if not is_equal_approx(float(guest.get("food_cycle_multiplier",1)),1.0):
		parts.append("等餐扣分周期 ×%.1f" % float(guest.food_cycle_multiplier))
	if guest.get("unlimited_food_wait", false):
		parts.append("等餐耐心无限")
	elif not is_equal_approx(float(guest.get("food_max_multiplier",1)),1.0):
		parts.append("等餐耐心 ×%.1f" % float(guest.food_max_multiplier))
	parts.append("基础声望 %d" % int(guest.base_reputation))
	return " · ".join(parts)

func _begin_move() -> void:
	var id = world.selected_id
	if sim.phase != "NIGHT" or (not id.begins_with("preview_") and _selected_fixture().is_empty()): return
	world.cancel_placement()
	world.editing = true
	world.selected_id = id
	ui.info_panel.hide()
	ui.slot_panel.hide()
	_sync_build_tools()
	var rotation_hint = " · %s 旋转" % keys.text("rotate") if Grid.can_rotate(Grid.find(sim.layout, world.selected_id)) else ""
	_notice("点击空格放置" + rotation_hint + " · Esc 取消")

func _move_facility(id: String, cell: Vector2i) -> void:
	if id.begins_with("preview_"):
		var role = id.get_slice("_", 1)
		var index = int(id.get_slice("_", 2))
		if _command(sim.move_staff(role, index, cell), "员工开店站位已调整。"):
			world.cancel_placement()
			_inspect("preview", id)
		return
	var result = sim.move_facility(id, cell, world.decor_preview_turns)
	var merged_size = int(result.get("merged_size", 0))
	var message = "已合成%s。" % Grid.table_label(merged_size) if merged_size > 0 else "设施位置已调整。"
	if _command(result, message):
		world.cancel_placement()
		if id in ["cashier","slot"]:
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
		_notice("墙体方向已调整 · 松开左键铺设")
		return
	var fixture = _selected_fixture()
	if fixture.get("type") == "decoration" and world.editing:
		var current = Grid.rotation(fixture) if world.decor_preview_turns < 0 else world.decor_preview_turns
		world.decor_preview_turns = (current + 1) % 4
		_notice("装饰朝向已调整")
	elif Grid.can_rotate(fixture):
		_command(sim.rotate_facility(fixture.id), "设施朝向已调整。")

func _split_selection() -> void:
	var fixture = _selected_fixture()
	if not Grid.can_split(fixture): return
	var result = sim.split_facility(fixture.id)
	var message = "已拆为两张%s。" % Grid.table_label(result.size) if result.ok else ""
	if _command(result, message) and not world.editing: _inspect("facility", fixture.id)

func _store_selection() -> void:
	var fixture = _selected_fixture()
	if not Grid.can_store(fixture): return
	var message = "隔墙已收起。" if fixture.type == "wall" else "设施已收起，可从建造目录重新放置。"
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
	ui.slot_panel.hide()
	_sync_build_tools()
	var hint = " · %s 旋转" % keys.text("rotate") if Grid.can_rotate(facility) else ""
	if facility.type == "trophy":
		_notice("在展廊内亮起的格子放置 " + str(facility.name))
	else:
		_notice("放置 %s · 点击空格%s" % [facility.name, hint])

func _start_wall_placement() -> void:
	if sim.phase != "NIGHT": return
	_close_modal()
	world.cancel_placement()
	_clear_inspector()
	ui.slot_panel.hide()
	world.placing_wall = true
	_sync_build_tools()
	_notice("按住左键拖铺 · %s 转向 · Esc 退出" % keys.text("rotate"))

func _place_wall(cells: Array, turns: int) -> void:
	_command(sim.place_wall_row(cells, turns), "已铺设 %d 格隔墙 · Esc 退出" % cells.size())

func _show_plot_confirmation(id: String) -> void:
	if sim.phase != "NIGHT": return
	var plot = sim.next_land_plot()
	if plot.is_empty() or str(plot.id) != id: return
	ui.info_panel.hide()
	ui.slot_panel.hide()
	var box = _new_modal("plot_unlock", str(plot.name), 430)
	var status = sim.land_plot_status(id)
	var waiting_for_date = sim.day < int(plot.unlock_day)
	var conditions = HBoxContainer.new()
	conditions.add_theme_constant_override("separation", 20)
	box.add_child(conditions)
	Style.readout(conditions, "clock", "第 %d 天开放" % int(plot.unlock_day), "开放日", Style.MUTED)
	Style.readout(conditions, "star", str(int(plot.star_cost)), "费用 %d 闪星 · 持有 %d" % [int(plot.star_cost), sim.stars])
	var gifts = HBoxContainer.new()
	gifts.add_theme_constant_override("separation", 16)
	box.add_child(gifts)
	if int(plot.grant_chefs) > 0:
		Style.readout(gifts, "chef", "+%d" % int(plot.grant_chefs), "赠送厨师", Style.GREEN)
	var counts := {}
	for fixture in plot.fixtures:
		if fixture.type == "trophy":
			Style.readout(gifts, "trophy", str(fixture.name), "赠送奖杯", Style.GREEN)
		elif fixture.type in ["slot", "trophy_shop", "decor_shop"]:
			Style.readout(gifts, "coins", str(fixture.name), "解锁商店", Style.GREEN)
		else:
			counts[fixture.type] = int(counts.get(fixture.type, 0)) + 1
	for type in counts:
		Style.readout(gifts, str(type), "+%d" % int(counts[type]), "赠送灶台" if type == "stove" else "赠送餐桌", Style.GREEN)
	if not status.ok and not waiting_for_date:
		box.add_child(Style.text(str(status.error), 15, Style.MUTED, true))
	guide.plot_note(box, id)
	var confirm = Style.button("确认解锁", true)
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
	ui.major_event.text = "！重大事件\n" + str(major_notice.name)
	ui.major_event.tooltip_text = "查看公告与生效规则"
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
	var box = _new_modal("major_event", str(event.name), 916)
	var notice = MajorEventPanel.new()
	box.add_child(notice)
	notice.populate(event, sim.event_challenge(event), event.id in sim.major_event_claims, sim.guest_defs.get(event.get("special_guest", ""), {}))
	notice.confirmed.connect(_confirm_major_event.bind(str(event.id)))

func _confirm_major_event(id: String) -> void:
	var result = sim.confirm_major_event(id)
	var grant = result.get("grant", {})
	var message = "已查看重大事件" if grant.is_empty() else "收到 " + MajorEventPanel.reward_text(grant)
	if _command(result, message): _close_modal(true, true)

func _unlock_land(id: String) -> void:
	if _command(sim.unlock_land_plot(id), "地块已解锁"):
		_close_modal(true, true)
		match id:
			"purchase_annex": guide.show_new_shop("slot")
			"trophy_gallery": guide.show_gallery()
			"decor_studio": guide.show_new_shop("decor_shop")

func _show_cashier_front() -> void:
	ui.info_panel.hide()
	var box = _new_modal("cashier_front","收银台",550)
	box.add_child(Style.text("升级同时花费声望与金币。",16,Style.MUTED,true))
	var upgrades = Style.button("招聘与改造", true)
	upgrades.pressed.connect(_show_cashier_page)
	box.add_child(upgrades)

func _upgrade(key: String) -> void:
	var result = sim.upgrade(key)
	var id = str(result.get("facility_id", ""))
	var message = "已完成。"
	if result.ok and key == "tables":
		message = "新餐桌已摆好。" if Grid.placed(Grid.find(sim.layout, id)) else "没有合适空位，新餐桌已放入建造背包。"
	if _command(result, message):
		if key == "chefs" and not id.is_empty():
			_close_modal()
			_select_pending(id)
			guide.placement()
		else:
			_show_cashier_page()

func _rent_budget_text() -> String:
	var rent = sim.next_rent()
	if rent.is_empty(): return "本章房租已全部缴清"
	var missing = maxi(0, int(rent.amount) - sim.gold)
	var balance = "当前余额距房租还差 %d$" % missing if missing > 0 else "当前余额可覆盖房租"
	return "第 %d 天房租 %d$ · %s" % [int(rent.day), int(rent.amount), balance]

func _show_cashier_page() -> void:
	ui.info_panel.hide()
	ui.slot_panel.hide()
	var box = _new_modal("cashier", "招聘与改造", 590)
	box.add_child(Style.text("可用声望 %d  ·  金币 %d$  ·  本晚已花 %d$" % [sim.reputation, sim.gold, sim.night_spend], 17, Style.GREEN))
	box.add_child(Style.text(_rent_budget_text(), 14, Style.MUTED, true))
	var entries = {"waiters": ["服务员", "crowd"], "chefs": ["厨师与灶台", "chef"], "tables": ["桌位", "table"],
		"menu_slots": ["菜单上架槽", "recipe"], "queue_capacity": ["排队容量", "door"], "relic_slots": ["奖杯展示位", "trophy"]}
	var progression = sim.upgrade_progression()
	for key in progression.unlocked:
		var rule = sim.chapter.upgrade_rules[key]
		var cap = int(sim.chapter.attribute_caps[key])
		var count = int(sim.attributes[key])
		var capped = count >= cap
		var gate = sim.upgrade_gate(key)
		var status = sim.upgrade_status(key)
		var card = Style.card()
		card.add_theme_stylebox_override("panel", Style.box(Color("2d464a"), Color("59817a"), 9, 11))
		box.add_child(card)
		var header = HBoxContainer.new()
		card.add_child(header)
		var seal = Style.card()
		seal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		seal.add_theme_stylebox_override("panel", Style.box(Style.BG, Color("658683"), 8, 9))
		seal.add_child(Icon.make(entries[key][1], Style.GOLD, 30))
		header.add_child(seal)
		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 5)
		header.add_child(details)
		var title = HBoxContainer.new()
		details.add_child(title)
		var name_label = Style.text(entries[key][0], 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_child(name_label)
		title.add_child(Style.text("%d / %d" % [count, cap], 14, Style.MUTED))
		var capacity = ProgressBar.new()
		capacity.show_percentage = false
		capacity.custom_minimum_size.y = 5
		capacity.max_value = cap
		capacity.value = count
		details.add_child(capacity)
		var increase = mini(int(rule.get("step", 1)), cap - count)
		var price = "+%d  ·  %d 声望 + %d$" % [increase, sim.upgrade_cost(key), sim.upgrade_gold_cost(key)]
		var caption = "已满" if capped else (str(gate.error) if not gate.ok else price)
		var button = Style.button(caption, status.ok)
		button.disabled = not status.ok
		button.tooltip_text = "立即招聘" if status.ok and key in ["chefs", "waiters"] else ("立即改造" if status.ok else str(status.error))
		button.pressed.connect(_upgrade.bind(key))
		details.add_child(button)
		if not status.ok and sim.phase == "NIGHT" and gate.ok and not capped:
			details.add_child(Style.text(str(status.error), 13, Style.RED, true))
	if not progression.next_key.is_empty():
		var feature = "厨师" if progression.next_key == "chefs" else str(entries[progression.next_key][0])
		var preview = HBoxContainer.new()
		box.add_child(preview)
		preview.add_child(Icon.make("lock", Style.MUTED, 18))
		preview.add_child(Style.text("%s · 第 %d 天解锁" % [feature, progression.next_day], 15, Style.MUTED))
	var waiting = sim.stored_facilities().filter(func(f): return f.type in ["table", "stove"])
	if sim.phase == "NIGHT" and not waiting.is_empty():
		box.add_child(Style.text("待放置设施",16,Style.GOLD))
		var row = HFlowContainer.new()
		box.add_child(row)
		for f in waiting:
			var button = Style.button("放置 " + f.name)
			button.pressed.connect(_pick_pending.bind(str(f.id)))
			row.add_child(button)

func _show_build_page() -> void:
	if sim.phase != "NIGHT": return
	if ui.build_catalog.visible:
		_close_build_page()
		return
	ui.info_panel.hide()
	ui.slot_panel.hide()
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
	ui.move.visible = night and not placing and (world.selected_id.begins_with("preview_") or (not fixture.is_empty() and Grid.placed(fixture) and fixture.type not in ["slot", "decor_shop", "trophy_shop"]))
	ui.rotate.visible = night and (world.placing_wall or Grid.can_rotate(fixture))
	ui.split.visible = night and not placing and Grid.can_split(fixture)
	ui.store.visible = night and not placing and Grid.can_store(fixture)
	ui.cancel_placement.visible = night and placing
	if ui.build_catalog.visible:
		var current = ""
		var status = "选一件物件，再到地图上放置"
		if world.placing_wall:
			current = "@wall"
			status = "按住左键拖铺隔墙"
		elif world.editing:
			current = world.selected_id
			status = "点击空格放置 " + str(fixture.get("name", ""))
		ui.build_catalog.refresh(sim, current, status)

func _cancel_placement() -> void:
	world.cancel_placement()
	_clear_inspector()
	ui.slot_panel.hide()

func _pick_catalog_item(id: String) -> void:
	if id == "@wall":
		_start_wall_placement()
	else:
		_select_pending(id)

func _pick_pending(id: String) -> void:
	_close_modal()
	_select_pending(id)

func _trophy_glyph(id: String) -> String:
	return {"bronze_clock":"◷","ember_cup":"♨","silver_bell":"♬","jade_medal":"◇","golden_spoon":"♜","laurel_crown":"♛","dining_hourglass":"⌛"}.get(id,"◆")

func _show_trophy_shop() -> void:
	if sim.phase != "NIGHT": return
	if not sim.trophy_shop_unlocked():
		_notice("解锁奖杯展廊后，奖杯商店才会开门。")
		return
	ui.slot_panel.hide()
	ui.info_panel.hide()
	guide.trophy_shop_opened()
	var box = _new_modal("trophy_shop","奖杯商店 · 永久遗物",720)
	box.add_child(Style.text("★ %d 闪星  ·  每晚自动换货  ·  同款奖杯只可拥有一件" % sim.stars,16,Style.GOLD))
	for index in range(sim.trophy_shop.size()):
		var offer = sim.trophy_shop[index]
		var card = Style.card()
		card.add_theme_stylebox_override("panel",Style.box(Color("2c4051"),Color("66869b"),8,9))
		box.add_child(card)
		var row = HBoxContainer.new()
		card.add_child(row)
		var description = "已售罄"
		if not str(offer.id).is_empty():
			var relic = sim.relic_defs[str(offer.id)]
			description = "%s · %d★\n%s" % [relic.name, int(relic.star_cost), relic.description]
			var relic_badge = Style.text(_trophy_glyph(str(offer.id)),28,Color(str(relic.color)))
			relic_badge.custom_minimum_size.x = 42
			row.add_child(relic_badge)
		var info = Style.text(description,15,Style.INK,true)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var buy = Style.button("已购买" if offer.bought else "★ %d" % int(offer.price))
		buy.disabled = str(offer.id).is_empty() or bool(offer.bought) or sim.stars < int(offer.price)
		buy.tooltip_text = "已购入" if offer.bought else ("已售罄" if str(offer.id).is_empty() else ("还差 %d 闪星" % (int(offer.price) - sim.stars) if buy.disabled else "购买奖杯"))
		buy.pressed.connect(_buy_trophy.bind(index))
		row.add_child(buy)
	var refresh = Style.button("换一批奖杯 · 1 闪星")
	refresh.disabled = sim.stars < 1 or sim._available_trophy_count() <= 3
	refresh.tooltip_text = "暂无其他奖杯可换" if sim._available_trophy_count() <= 3 else ("需要 1 闪星" if sim.stars < 1 else "换一批奖杯")
	refresh.pressed.connect(_refresh_trophy_shop)
	box.add_child(refresh)
	var bag = Style.button("奖杯背包（%d 件 / 展示 %d）" % [sim.owned_relics.size(),int(sim.attributes.relic_slots)])
	bag.pressed.connect(_show_trophy_bag)
	box.add_child(bag)

func _buy_trophy(index: int) -> void:
	if _command(sim.buy_trophy(index),"奖杯已加入背包；放在展示区才会生效。"):
		_show_trophy_shop()

func _refresh_trophy_shop() -> void:
	if _command(sim.refresh_trophies(),"奖杯列表已刷新。"):
		_show_trophy_shop()

func _show_trophy_bag() -> void:
	if not sim.trophy_shop_unlocked():
		_notice("解锁奖杯展廊后开放奖杯背包。")
		return
	var box = _new_modal("trophy_bag","奖杯背包",650)
	box.add_child(Style.text("已展示 %d / %d 件 · 只能放在展廊的展示区" % [Grid.facilities(sim.layout,"trophy").size(),int(sim.attributes.relic_slots)],15,Style.GOLD))
	if sim.owned_relics.is_empty(): box.add_child(Style.text("尚未拥有奖杯。解锁奖杯展廊后，可在旁边的奖杯商店购买。",15,Style.MUTED))
	for id in sim.owned_relics:
		var relic = sim.relic_defs[id]
		var entity = Grid.find(sim.layout,"trophy_"+str(id))
		var row = HBoxContainer.new()
		box.add_child(row)
		var info = Style.text("%s %s · %d★ · %s" % [_trophy_glyph(str(id)), relic.name, int(relic.star_cost), relic.description],15,Color(str(relic.color)),true)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var action = _icon_button("move", "移动奖杯" if Grid.placed(entity) else "摆放奖杯")
		action.custom_minimum_size.x = 42
		action.disabled = sim.phase != "NIGHT" or (not Grid.placed(entity) and Grid.facilities(sim.layout,"trophy").size()>=int(sim.attributes.relic_slots))
		action.tooltip_text = "夜晚可布置" if sim.phase != "NIGHT" else ("展示位已满，请先收起一件" if action.disabled else action.tooltip_text)
		action.pressed.connect(_pick_pending.bind("trophy_"+str(id)))
		row.add_child(action)
		if Grid.placed(entity):
			var store = _icon_button("store", "收起奖杯")
			store.custom_minimum_size.x = 42
			store.disabled = sim.phase != "NIGHT"
			store.pressed.connect(_store_trophy.bind("trophy_"+str(id)))
			row.add_child(store)

func _store_trophy(id: String) -> void:
	if _command(sim.store_facility(id),"奖杯已收起，常驻效果停止生效。"):
		_show_trophy_bag()

func _show_decoration_shop() -> void:
	if sim.phase != "NIGHT" or not sim.decoration_shop_unlocked(): return
	ui.info_panel.hide()
	ui.slot_panel.hide()
	guide.shop_opened("decor_shop")
	var box = _new_modal("decor_shop", "装饰商店", 908)
	var summary = HBoxContainer.new()
	box.add_child(summary)
	Style.readout(summary, "coins", "%d$" % sim.gold, "持有金币")
	summary.add_child(Style.text("同类效果覆盖时取最高值", 14, Style.MUTED))
	var offers = GridContainer.new()
	offers.columns = 2
	offers.add_theme_constant_override("h_separation", 8)
	offers.add_theme_constant_override("v_separation", 8)
	box.add_child(offers)
	for definition in sim.decoration_defs.values():
		var card = Style.card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Style.box(Style.BG, Color("4c6567"), 7, 9))
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
		var buy = Style.button("%d$" % int(definition.price))
		buy.name = "Buy_" + str(definition.id)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.disabled = sim.gold < int(definition.price)
		buy.pressed.connect(_buy_decoration.bind(str(definition.id)))
		row.add_child(buy)
	var bag = Style.button("打开建造背包")
	bag.pressed.connect(_open_decoration_inventory)
	box.add_child(bag)

func _buy_decoration(id: String) -> void:
	if _command(sim.buy_decoration(id), "装饰已放入建造背包。"):
		_show_decoration_shop()

func _open_decoration_inventory() -> void:
	_close_modal(false, true)
	if not ui.build_catalog.visible: _show_build_page()
	ui.build_catalog._select_category("decoration")

func _show_purchase_page(index: int = 0) -> void:
	if sim.phase != "NIGHT": return
	if not sim.purchase_unlocked():
		_notice("解锁采购小厅后可采购", true)
		return
	guide.shop_opened("slot")
	selected_offer = clampi(index,0,2)
	ui.slot_panel.hide()
	var box = _new_modal("purchase","采购处 · 今晚商品",1090)
	var balance = HBoxContainer.new()
	box.add_child(balance)
	Style.readout(balance, "coins", "可用 %d$" % sim.gold, "可用于采购的金币")
	balance.add_child(Style.text("每日收摊后换货", 14, Style.MUTED))
	box.add_child(Style.text(_rent_budget_text(), 14, Style.MUTED, true))
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation",18)
	box.add_child(content)
	var portrait = Style.card()
	portrait.custom_minimum_size = Vector2(265,445)
	portrait.add_theme_stylebox_override("panel",Style.box(Color("415e4b"),Color("769877"),10,14))
	content.add_child(portrait)
	var hero_column = VBoxContainer.new()
	portrait.add_child(hero_column)
	hero_column.add_child(Style.text("本店厨师",16,Style.GOLD))
	var staging = Control.new()
	staging.custom_minimum_size.y = 294
	hero_column.add_child(staging)
	var chef = Actor.new()
	staging.add_child(chef)
	chef.position = Vector2(122,205)
	chef.z_index = 2 # Child sprite is z=-1; keep the portrait above the card background.
	chef.set_visual("chef")
	chef.set_display_zoom(5.2)
	chef.present("idle")
	var lines = ["今天的菜要热乎乎地出锅。","看看晚上的新货吧！","多留点金币交房租哦。","好菜也要有人及时送到桌上。"]
	var speech = Style.card()
	speech.add_theme_stylebox_override("panel",Style.box(Color("f1e8d2"),Color("d8b885"),9,10))
	hero_column.add_child(speech)
	speech.add_child(Style.text(lines[randi_range(0,lines.size()-1)],14,Color("39483b"),true))
	var products = VBoxContainer.new()
	products.custom_minimum_size.x = 565
	products.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(products)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = clampf(get_viewport_rect().size.y-340,330,490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	products.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var mods = sim.effective_modifiers()
	for slot in range(sim.shop.size()):
		var offer = sim.shop[slot]
		var card = Style.card()
		card.add_theme_stylebox_override("panel",Style.box(Color("304b4d") if slot==selected_offer else Style.BG,Style.GOLD if slot==selected_offer else Color("516969"),9,12))
		list.add_child(card)
		var product_row = HBoxContainer.new()
		card.add_child(product_row)
		var column = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",5)
		product_row.add_child(column)
		if offer.type in ["empty","empty_buff"]:
			column.add_child(Style.text("%02d  ·  %s" % [slot+1,"本章菜谱已收集完" if slot==0 else "暂无可购买增益"],16,Style.MUTED))
			continue
		if offer.type == "recipe":
			var recipe = sim.recipes[offer.id]
			var quality = sim.preview_quality(offer.id)
			var sample_price = sim.meal_price(str(offer.id), quality, mods)
			column.add_child(Style.text("菜谱 · " + str(recipe.name),19,Style.INK))
			column.add_child(Style.text(recipe.description,13,Style.MUTED,true))
			column.add_child(Style.text("基础价值 %d$   ·   当前品质 %d%%   ·   普通客估价 %d$\n制作 %.1f 秒/锅   ·   每锅 %d 份" % [recipe.base_value,int(quality*100),sample_price,float(recipe.cook_seconds)/(1.0+float(mods.cook)),recipe.batch_yield],14,Style.GOLD,true))
		else:
			var buff = sim.buff_defs[offer.id]
			var active = sim.buff_states.get(offer.id,{"stack_count":0,"remaining_days":0})
			column.add_child(Style.text("%s · %d★" % [buff.name, int(buff.level)],19,Style.INK))
			column.add_child(Style.text(buff.description,14,Style.MUTED,true))
			column.add_child(Style.text("生效 %d 个营业日   ·   购买后 %d / %d 层   ·   累计剩余 %d 天" % [buff.duration_days,int(active.stack_count)+1,buff.max_stacks,int(active.remaining_days)+int(buff.duration_days)],13,Style.GOLD,true))
		var buy = Style.button("已买入" if offer.bought else "购买  %d$" % offer.price,true)
		buy.disabled = offer.bought or sim.gold < int(offer.price)
		buy.tooltip_text = "本晚已购买" if offer.bought else ("还差 %d 金币" % (int(offer.price)-sim.gold) if sim.gold < int(offer.price) else "购买并确认")
		buy.pressed.connect(_buy.bind(slot))
		var action = VBoxContainer.new()
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		product_row.add_child(action)
		action.add_child(buy)
		if buy.disabled and not offer.bought:
			action.add_child(Style.text(buy.tooltip_text, 13, Style.RED))
	var menu = Style.button("管理已拥有菜谱")
	menu.pressed.connect(_show_menu_page)
	products.add_child(menu)

func _buy(index: int) -> void:
	var offer = sim.shop[index]
	if offer.type == "buff":
		if _command(sim.buy_offer(index),"增益已购买，下一场营业生效。"):
			_show_purchase_page(index)
		return
	if offer.type != "recipe": return
	var recipe = sim.recipes[offer.id]
	var box = _new_modal("buy","确认解锁 · " + recipe.name,620)
	box.add_child(Style.text("%d 金币  ·  %d 基础价值  ·  %.0f 秒/锅  ·  每锅%d份\n旧菜会留在收藏，取消不会扣款。" % [offer.price,recipe.base_value,recipe.cook_seconds,recipe.batch_yield],15,Style.MUTED,true))
	if sim.menu.size()>=int(sim.attributes.menu_slots):
		guide.inline_note(box, "menu_full", "菜单已满。选一道在售菜替换，旧菜谱会留在收藏，之后可从「菜谱」换回。")
		box.add_child(Style.text("菜单已满，选一道替换：",16,Style.GOLD))
		for i in range(sim.menu.size()):
			var replace = Style.button("替换 " + sim.recipes[sim.menu[i]].name,true)
			replace.pressed.connect(_commit_purchase.bind(index,i))
			box.add_child(replace)
	else:
		var confirm = Style.button("确认购买并上架",true)
		confirm.pressed.connect(_commit_purchase.bind(index,-1))
		box.add_child(confirm)
	var back = Style.button("返回采购页")
	back.pressed.connect(_show_purchase_page.bind(index))
	box.add_child(back)

func _commit_purchase(index: int, slot: int) -> void:
	if _command(sim.buy_offer(index,slot),"新菜已上架，旧菜仍可在菜单中换回。"):
		_show_purchase_page(index)

func _show_menu_page() -> void:
	if sim.phase != "NIGHT": return
	var box = _new_modal("menu","当前菜单",780)
	box.add_child(Style.text("已上架 %d / %d 道菜。点击槽位换菜，新菜谱可在采购处购买。" % [sim.menu.size(),sim.attributes.menu_slots],15,Style.MUTED,true))
	for slot in range(int(sim.attributes.menu_slots)):
		var row = HBoxContainer.new()
		box.add_child(row)
		var name = sim.recipes[sim.menu[slot]].name if slot<sim.menu.size() else "空槽"
		var button = Style.button("%d  ·  %s    →  选择" % [slot+1,name])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_collection.bind(slot))
		row.add_child(button)
		if slot<sim.menu.size() and sim.menu.size()>1:
			var remove = Style.button("下架")
			remove.pressed.connect(_remove_menu.bind(slot))
			row.add_child(remove)

func _show_collection(slot: int) -> void:
	if sim.phase != "NIGHT": return
	var box = _new_modal("collection","菜单槽 %d · 选择菜谱" % (slot+1),790)
	box.add_child(Style.text("更换已解锁菜谱免费。菜单多样性会影响客人的随机选菜。",14,Style.MUTED,true))
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
		var label = Style.text("%s\n%d 基础金币 · %.0f 秒 / 锅 · %d 份" % [r.name,r.base_value,r.cook_seconds,r.batch_yield],14,Style.INK,true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button = Style.button("已上架" if id in sim.menu else "换入",id not in sim.menu)
		button.disabled = id in sim.menu
		button.pressed.connect(_commit_menu.bind(slot,id))
		row.add_child(button)
	var back = Style.button("返回菜单")
	back.pressed.connect(_show_menu_page)
	box.add_child(back)

func _commit_menu(slot: int, id: String) -> void:
	if _command(sim.change_menu(slot,id),"菜单已更新。"):
		_show_menu_page()

func _remove_menu(slot: int) -> void:
	if _command(sim.remove_menu(slot),"这道菜已下架，仍在收藏中。"):
		_show_menu_page()

func _show_settings() -> void:
	var box = _new_modal("settings","设置",530)
	box.add_child(Style.text("%s  ·  第 %d 天" % [sim.chapter.title, sim.day], 17, Style.INK))
	box.add_child(Style.text("本章进度仅在夜晚与结算点存档", 15, Style.MUTED))
	if sim.phase == "DAY":
		var pause = Style.button("继续营业" if sim.paused else "暂停营业")
		pause.pressed.connect(func(): _toggle_pause(); _show_settings())
		box.add_child(pause)
	var focus = Style.button("复位视野 [%s]" % keys.text("focus"))
	focus.pressed.connect(func(): world.focus_restaurant(); _dismiss_modal())
	box.add_child(focus)
	var keyboard = Style.button("按键设置")
	keyboard.name = "OpenKeySettings"
	keyboard.pressed.connect(_show_key_settings)
	box.add_child(keyboard)
	var handbook = Style.button("玩法指南")
	handbook.pressed.connect(_show_handbook)
	box.add_child(handbook)
	var replay = Style.button("再听阿禾讲一遍")
	replay.pressed.connect(func(): _close_modal(); guide.replay())
	box.add_child(replay)
	if guide.mode != "off":
		var disable = Style.button("关闭阿禾引导")
		disable.pressed.connect(func(): guide.skip(); _dismiss_modal())
		box.add_child(disable)
	var restart = Style.button("重新开始本章")
	restart.pressed.connect(_confirm_restart)
	box.add_child(restart)
	var leave = Style.button("返回主界面")
	leave.pressed.connect(_return_to_title)
	box.add_child(leave)
	var done = Style.button("返回餐厅", true)
	done.pressed.connect(_dismiss_modal)
	box.add_child(done)

func _show_handbook() -> void:
	var box = _new_modal("handbook", "阿禾的玩法指南", 680)
	guide.populate_handbook(box)
	var actions = HFlowContainer.new()
	box.add_child(actions)
	if sim.phase == "NIGHT":
		var practice = Style.button("练习合桌", true)
		practice.pressed.connect(func(): _close_modal(); guide.teach_tables())
		actions.add_child(practice)
		if not major_notice.is_empty():
			var event = Style.button("查看重大事件")
			event.pressed.connect(_show_major_event)
			actions.add_child(event)
	var back = Style.button("返回设置")
	back.pressed.connect(_show_settings)
	actions.add_child(back)

func _show_key_settings() -> void:
	var box = _new_modal("key_settings", "按键设置", 720)
	box.add_child(Style.text("点按右侧键位，再按一个键。Esc 取消改键。", 15, Style.MUTED))
	var columns = HBoxContainer.new()
	box.add_child(columns)
	var grids = []
	for title in ["营业与布置", "打开页面"]:
		var card = Style.card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Style.box(Style.BG, Color("547071"), 8, 12))
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
		var label = Style.text(KeyBindings.ACTIONS[action][0], 15)
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
	var reset = Style.button("恢复默认")
	reset.name = "ResetKeyBindings"
	reset.pressed.connect(_reset_key_bindings)
	footer.add_child(reset)
	var back = Style.button("返回设置")
	back.pressed.connect(_show_settings)
	footer.add_child(back)

func _begin_key_binding(action: String) -> void:
	_end_key_binding()
	binding_action = action
	binding_buttons[action].text = "请按键"

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
	_close_modal(false)
	_discard_fading_modal()
	modal_opener = opener
	modal_kind = kind
	if world != null:
		world.camera_input_enabled = false
		world.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		ui.overlay.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 20
	add_child(modal_layer)
	var dark = ColorRect.new()
	dark.color = Color("142532", 0.70)
	modal_layer.add_child(dark)
	_fill(dark)
	modal_frame = ModalFrame.new()
	modal_frame.theme = theme
	modal_layer.add_child(modal_frame)
	_fill(modal_frame)
	modal_frame.build(kind, title, width, _dismiss_modal)
	modal_frame.animate_in(dark, backdrop_opacity)
	return modal_frame.body

func _discard_fading_modal() -> void:
	if fading_modal == null: return
	remove_child(fading_modal)
	fading_modal.queue_free()
	fading_modal = null

func _close_modal(restore_focus := true, animate := false) -> void:
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
		if world != null:
			ui.overlay.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
			world.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		if restore_focus and is_instance_valid(modal_opener) and modal_opener.is_visible_in_tree():
			modal_opener.grab_focus()
		modal_opener = null
	modal_kind = ""
	if world != null: world.camera_input_enabled = true

func _dismiss_modal() -> void:
	_close_modal(true, sim.phase != "REPORT")
	if sim.phase == "REPORT": _show_report()

func _peak_forecast(for_day: int, compact := false) -> String:
	for event in sim.events_for(for_day):
		if not event.has("arrival_peak"): continue
		var peak = event.arrival_peak
		var period = MajorEventPanel.peak_time(peak)
		var share = roundi(float(peak.share) * 100)
		if compact: return "%s · %d%%" % [period, share]
		return "%s\n%s 集中约 %d%%" % [event.name, period, share]
	return ""

func _show_diagnostic_on_map(r: Dictionary) -> void:
	var key = str(r.diagnosis.focus)
	if key.is_empty(): return
	var description = ReportPanel.DIAGNOSTIC_TEXT[key]
	var facilities = description.facilities + r.diagnosis.stages[key].tables
	world.set_diagnostic_targets(facilities, key == "queue", true)
	ui.diagnostic_label.text = str(description.label)
	ui.diagnostic_button.text = "返回日报"
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
	ui.slot_panel.hide()
	status_timer = 0.0
	ui.toast_card.hide()
	report_shown_day = sim.day
	var report = sim.last_report.merged({
		"gold_after": sim.gold, "reputation_after": sim.reputation, "stars_after": sim.stars, "day": sim.day,
	}, true)
	var outcome = "营业复盘" if report.result == "CONTINUE" else ("章节胜利" if report.result == "WIN" else "房租不足")
	var box = _new_modal("report","第 %d 天 · %s" % [sim.day,outcome],920)
	var panel = ReportPanel.new()
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
			if int(event.from_day) == next_day and not peak.begins_with(str(event.name) + "\n"):
				notices.append(str(event.name))
	panel.populate(report, previous, sim.catalog, notices, guide.report_text(report, peak))
	if reveal_rewards: panel.reveal_earned_goals()

func _show_report_history() -> void:
	if sim.reports.is_empty(): return
	var box = _new_modal("report_history", "历史日报", 970)
	var panel = ReportHistory.new()
	box.add_child(panel)
	panel.populate(sim.reports, sim.catalog)

func _continue_night() -> void:
	if _command(sim.continue_night(), "夜晚准备"):
		_close_modal(true, true)
		report_shown_day = -1
		accumulator = 0
		fast_forward = false
		world.cancel_placement()
		inspected = {}
		_refresh_all()
		guide.night()

func _confirm_restart() -> void:
	var box = _new_modal("restart","重新开始本章？",570)
	box.add_child(Style.text("会替换当前检查点。旧版本档案在首次覆盖前会留作备份。",15,Style.MUTED,true))
	var seed_input = LineEdit.new()
	seed_input.placeholder_text = "可选：输入整数种子复现同一局"
	box.add_child(seed_input)
	var confirm = Style.button("确认重新开局")
	confirm.add_theme_stylebox_override("normal", Style.box(Color("643f3e"), Style.RED.darkened(.28), 7, 10))
	confirm.add_theme_color_override("font_color", Color("ffe1cf"))
	confirm.pressed.connect(func(): _restart_run(int(seed_input.text) if seed_input.text.is_valid_int() else int(Time.get_ticks_usec()%1000000000)))
	box.add_child(confirm)
	var cancel = Style.button("取消", true)
	cancel.pressed.connect(_dismiss_modal)
	box.add_child(cancel)

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
	ui.slot_panel.hide()
	inspected = {}
	_save()
	_refresh_all()
	guide.start_visit()
	if guide.stage.is_empty(): _notice("新开局")

func _input(event: InputEvent) -> void:
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
		error = "请直接按一个键。" if modified else keys.bind(binding_action, key)
	if not error.is_empty():
		modal_frame.show_error(error)
		return
	_end_key_binding()
	_update_hud()

func _unhandled_key_input(event: InputEvent) -> void:
	if sim == null or not event is InputEventKey or not event.pressed or event.echo: return
	var key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key != KEY_ESCAPE: return
	if modal_layer != null:
		if modal_kind in ["key_settings", "handbook"]: _show_settings()
		elif modal_kind not in ["report", "restore_error", "config_error"]: _dismiss_modal()
	elif world.editing or world.placing_wall or world.drag_active:
		_cancel_placement()
	elif ui.build_catalog.visible:
		_close_build_page()
	elif ui.diagnostic_card.visible:
		_dismiss_diagnostic()
	else:
		world.cancel_placement()
		_clear_inspector()
		ui.slot_panel.hide()

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
