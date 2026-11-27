extends SceneTree

const GAME = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/core/save_store.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Grid = preload("res://scripts/core/layout.gd")
var passed := 0
var failed := 0
var app
var path: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func choice(parent: Node, caption: String) -> bool:
	for button in parent.find_children("*", "Button", true, false):
		if button.text == caption and button.is_visible_in_tree():
			button.pressed.emit()
			return true
	return false

func click_button(button: Button) -> void:
	var at = button.get_global_rect().get_center()
	var move = InputEventMouseMotion.new()
	move.position = at
	root.push_input(move, true)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func drag_table(start: Vector2, end: Vector2) -> void:
	var world = app.world
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = world.screen_point(start)
	root.push_input(press, true)
	world._process(world.HOLD_TO_DRAG)
	var release = press.duplicate()
	release.position = world.screen_point(end)
	release.pressed = false
	root.push_input(release, true)

func preview(label: String) -> void:
	if "--guide-preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/tutorial_%s.png" % label)

func load_game() -> void:
	app = GAME.instantiate()
	app.tutorial_path = path
	root.add_child(app)

func unload_game() -> void:
	root.remove_child(app)
	app.free()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Run with -- --ui-test to use isolated test checkpoints")
		quit(2)
		return
	if DisplayServer.get_name() == "headless": root.size = Vector2i(1100, 720)
	path = Store.default_path("guide_test_profile", true)
	if not Store.write_checkpoint({"mode":"ask", "seen":{}}, path).is_empty():
		quit(2)
		return
	load_game()
	app._restart_run(718)
	for i in 6: await process_frame
	var guide = app.guide
	check(guide.stage == "welcome" and guide.bubble.visible and app.world.guide_camera_active, "首次进店应有头顶气泡与镜头")
	if "--guide-preview" in OS.get_cmdline_user_args():
		for i in 50: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/tutorial_welcome.png")
	click_button(guide.bubble.actions.get_child(0))
	check(guide.stage == "order_counter", "点击气泡上的真实按钮选择跟随")
	check(choice(guide.bubble, "再看出餐口") and guide.stage == "pass_counter", "辨认两个交接口")
	check(choice(guide.bubble, "记住了") and guide.stage == "tables" and app.world.guide_markers.size() == 2, "交接口之后高亮可实际合成的两张桌")
	if guide.stage != "tables" or app.world.guide_markers.size() != 2:
		quit(1)
		return
	var markers = app.world.guide_markers.duplicate()
	var target_id = Grid.facility_at(app.sim.layout, Vector2i(markers[1])).id
	app.world._process(1.0)
	await process_frame
	await preview("merge")
	drag_table(markers[0], markers[1])
	check(guide.stage == "tables_done" and guide.seen.has("tables") and Grid.table_size(Grid.find(app.sim.layout, target_id)) == 2, "真实长按拖拽成功后讲解四人桌和拆分")
	if guide.stage != "tables_done":
		quit(1)
		return
	await preview("merge-done")
	app._split_selection()
	check(Grid.table_size(Grid.find(app.sim.layout, target_id)) == 1, "可在开店前拆回单人桌")
	check(choice(guide.bubble, "继续") and guide.stage == "open" and app.world.zoom == 1.0, "合桌课结束后回到原视野并提示开店")
	var practiced_layout = app.sim.layout.duplicate(true)
	app.ui.open.pressed.emit()
	app.fast_forward = true
	var guard := 0
	while not guide.blocks_clock and app.sim.phase == "DAY" and guard < 5000:
		app._process(0.08)
		guard += 1
	check(guide.stage == "guest", "真实点单事件触发引导")
	if guide.stage != "guest":
		quit(1)
		return
	var tick = app.sim.tick
	for i in 5: app._process(0.3)
	check(app.sim.tick == tick and app.fast_forward, "阅读不消耗耐心并保留快进")
	var id = guide.guest_id
	app.world._sync_actors()
	var guest_bubble = app.world.say("g_%d" % id, "客人", "我的菜快好了吗？", 0.4)
	check(guest_bubble.visible and guest_bubble != guide.bubble, "客人和服务员可同时使用通用气泡")
	var pan = app.world.camera_pan
	var drag = InputEventMouseMotion.new()
	drag.position = app.world.size / 2
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	drag.relative = Vector2(75, 20)
	app.world.dragging_camera = true
	app.world._gui_input(drag)
	app.world.dragging_camera = false
	check(not app.world.guide_camera_active and app.world.camera_pan == pan + drag.relative, "拖镜头立即接管")
	check(choice(guide.bubble, "查看客人") and app.inspected.get("id") == str(id) and guide.blocks_clock, "查看真实客人时仍暂停计时")
	app._process(.3)
	check(app.sim.tick == tick and choice(guide.bubble, "继续营业") and not guide.blocks_clock, "看完详情后主动恢复计时")
	guest_bubble._process(0.5)
	check(guest_bubble.is_queued_for_deletion(), "普通气泡超时自行回收")
	var vanished = app.world.say("g_missing", "客人", "稍后再来。", -1)
	vanished._process(0.1)
	check(vanished.is_queued_for_deletion(), "目标消失时回收常驻气泡")
	app.ui.info_panel.hide()
	var saw_carrier := false
	guard = 0
	while app.sim.phase == "DAY" and guard < 15000:
		app._process(0.025)
		if guide.stage == "delivery": saw_carrier = true
		guard += 1
	check(saw_carrier and guide.seen.has("delivery") and guide.seen.has("payment"), "实际端菜与首笔收入触发")
	check(app.modal_kind == "report" and app.modal_layer.find_child("ReportGuide", true, false) != null, "首份日报有阿禾注释")
	var reference = Sim.new()
	reference.new_run(718)
	reference.layout = practiced_layout
	reference.start_day()
	while reference.phase == "DAY": reference.step()
	check(JSON.stringify(reference.last_report) == JSON.stringify(app.sim.last_report), "相同种子的完整日报与无引导模拟一致")
	check(guide.report_text(app.sim.last_report, "12:00–14:00").contains("客流高峰") and guide.seen.has("rush"), "首次遇到客流预告时讲解")
	app._show_report()
	check(app.modal_layer.find_child("ReportGuide", true, false) != null, "返回同一份日报仍可读讲解")
	app._continue_night()
	check(guide.stage == "reputation" or not app.sim.upgrade_status("tables").ok, "确有可购买的升级时提示声望")
	guide.clear_line()
	app.sim.day = 3
	app.sim.stars = 0
	guide.night()
	app._show_plot_confirmation("purchase_annex")
	check(guide.seen.has("plot_purchase_annex") and app.modal_layer.find_child("ConfirmLandUnlock", true, false).disabled, "采购小厅提示开放与闪星差额")
	app._close_modal()
	app.sim.stars = 1
	app._unlock_land("purchase_annex")
	check(choice(guide.bubble, "查看采购处") and app.modal_kind == "purchase", "解锁后指向真实采购入口")
	app._close_modal()
	app._inspect("facility", "slot")
	check(app.modal_kind == "purchase" and guide.seen.has("purchase"), "点击柜台直接打开采购，并记录教学")
	var offer = {"type":"recipe", "id":"batch_snacks", "price":50, "bought":false}
	app.sim.shop[0] = offer
	app._buy(0)
	check(app.modal_kind == "buy" and guide.seen.has("menu_full"), "买新菜但菜单已满时提示替换")
	app._close_modal()
	app.sim.reputation = 1000
	app._upgrade("tables")
	check(not app.world.editing and app.ui.toast_label.text.contains("已摆好"), "购桌自动摆放，无需进入放置流程")
	app._close_modal()
	app.sim.day = 6
	app.world.cancel_placement()
	app.service_feedback.reset()
	app._refresh_all()
	guide.night()
	check(guide.stage == "major_event" and guide.highlighted == app.ui.major_event and not guide.seen.has("major_event"), "相关夜晚高亮真实重大事件按钮")
	await preview("event")
	var claims = app.sim.major_event_claims.duplicate()
	click_button(app.ui.major_event)
	check(app.modal_kind == "major_event" and guide.seen.has("major_event") and guide.stage.is_empty() and app.sim.major_event_claims == claims, "打开公告完成教学，奖励仍需手动领取")
	await process_frame
	await preview("event-panel")
	app._dismiss_modal()
	app.sim.day = 7
	app._refresh_all()
	guide.night()
	check(guide.stage == "rent", "缴租提醒优先于扩建")
	guide.clear_line()
	app.sim.stars = 30
	app._show_plot_confirmation("trophy_gallery")
	check(guide.seen.has("plot_trophy_gallery"), "满足前置条件后提示展廊")
	app._unlock_land("trophy_gallery")
	check(guide.stage == "gallery_gift" and app.sim.trophy_shop_unlocked(), "成功解锁展廊才提示独立商店")
	check(choice(guide.bubble, "查看奖杯盲盒") and app.modal_kind == "trophy_shop" and guide.seen.has("gallery_shop"), "阿禾的提示可打开独立商店")
	app._close_modal()
	app._show_plot_confirmation("decor_studio")
	check(guide.seen.has("plot_decor_studio"), "装饰工坊条件教学")
	app._unlock_land("decor_studio")
	check(choice(guide.bubble, "查看装饰商店") and app.modal_kind == "decor_shop", "阿禾引导打开独立装饰商店")
	app._close_modal()
	app.sim.day = 10
	guide.night()
	check(guide.stage == "kitchen", "厨房在商店后提供扩建引导")
	app._unlock_land("kitchen_extension")
	app.sim.day = 13
	app._show_plot_confirmation("south_dining")
	check(guide.seen.has("plot_south_dining"), "南侧客席条件教学")
	app._close_modal()
	unload_game()
	load_game()
	check(app.guide.seen.has("guest") and app.guide.seen.has("payment") and app.guide.stage != "welcome", "读档保留已学步骤")
	app._show_build_page()
	check(app.guide.seen.has("build_catalog") and app.ui.build_catalog.visible, "第一次打开底部目录时提示建造工具")
	app._close_build_page()
	app._show_settings()
	check(choice(app.modal_layer, "玩法指南") and app.modal_kind == "handbook", "设置可随时查阅玩法指南")
	await preview("handbook")
	check(choice(app.modal_layer, "返回设置") and app.modal_kind == "settings", "玩法指南返回设置")
	check(choice(app.modal_layer, "再听阿禾讲一遍") and app.guide.stage == "welcome", "设置从阿禾招手开始重听并保留经营进度")
	choice(app.guide.bubble, "跟你看看")
	choice(app.guide.bubble, "跳过引导")
	check(not app.guide.blocks_clock, "跳过释放引导暂停")
	app._open_day()
	app.sim.paused = true
	app.fast_forward = true
	var old_day = app.sim.day
	app._show_settings()
	choice(app.modal_layer, "再听阿禾讲一遍")
	choice(app.guide.bubble, "跟你看看")
	choice(app.guide.bubble, "再看出餐口")
	choice(app.guide.bubble, "记住了")
	check(app.sim.paused and app.fast_forward and app.sim.day == old_day and not app.guide.blocks_clock, "营业中重听后保留玩家原有暂停、倍速和天数")
	app.guide.skip()
	unload_game()
	load_game()
	check(app.guide.mode == "off" and app.guide.stage == "", "选择跳过后跨会话保留")
	unload_game()
	var legacy = Sim.new()
	legacy.day = 4
	var old_steps = {"tour": true, "guest": true, "delivery": true, "payment": true}
	Store.write_checkpoint({"mode": "on", "seen": old_steps}, path)
	Store.write_checkpoint(legacy.export_state(), Store.default_path("street_corner", true))
	load_game()
	check(app.guide.stage == "tables" and app.guide.seen == old_steps and app.sim.day == 4, "旧档保留已学步骤并自动补上合桌")
	choice(app.guide.bubble, "稍后再试")
	app.sim.day = 6
	app._save()
	unload_game()
	load_game()
	check(app.guide.stage == "major_event" and app.guide.seen.has("payment"), "重新进入旧档时仍能学到重大事件")
	unload_game()
	print("TUTORIAL RESULT: ", passed, " passed / ", failed, " failed")
	quit(1 if failed else 0)
