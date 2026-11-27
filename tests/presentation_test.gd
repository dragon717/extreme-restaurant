extends SceneTree
# Native presentation regression. Launch with --script res://tests/presentation_test.gd -- --ui-test.
const Sim = preload("res://scripts/core/simulation.gd")
const Store = preload("res://scripts/core/save_store.gd")
var failures := 0
var passed := 0
var seen := {}

func check(value: bool, description: String) -> void:
	if value:
		passed += 1
	else:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path = "res://.local/preview_%dx%d_%s.png" % [root.size.x, root.size.y, label]
	check(root.get_texture().get_image().save_png(path) == OK, "截图 " + label)

func modal(scene, kind: String) -> void:
	await RenderingServer.frame_post_draw
	var frame = scene.modal_frame
	check(scene.modal_kind == kind and frame.panel.size.y > 80 and Rect2(Vector2.ZERO, root.size).encloses(frame.panel.get_global_rect()), "弹窗可见且完整 " + kind)
	check(frame.scroll.get_h_scroll_bar().max_value <= frame.scroll.size.x + 1, "无横向裁切 " + kind)

func canyon_preview() -> void:
	Store.write_checkpoint(Sim.new().export_state(), Store.default_path("street_corner", true))
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await RenderingServer.frame_post_draw
	await shot("canyon-title")
	title._select_place("tavern")
	await title.get_node("Menu/CanyonHub").at_door
	title.start_button.pressed.emit()
	await title.get_node("Menu/CanyonHub").door_crossed
	await title.game.world.entry_finished
	var game = title.game
	game.guide.skip()
	game.set_process(false)
	game._open_day()
	game.sim.paused = false
	for i in range(240): game.sim.step()
	game._update_hud()
	game.ui.rush.pressed.emit()
	game.world._process(0.0)
	check(game.ui.skills.visible and game.ui.rush.disabled and game.world.current_sprite.visible, "技能按钮触发水流并进入冷却")
	await shot("canyon-service")
	title.queue_free()
	await process_frame

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Pass --ui-test to use isolated test saves.")
		quit(1)
		return
	await canyon_preview()
	var invalid = load("res://scenes/main.tscn").instantiate()
	invalid.chapter_id = "missing_chapter_test"
	root.add_child(invalid)
	await modal(invalid, "config_error")
	var returned := [false]
	invalid.return_to_title.connect(func(): returned[0] = true)
	invalid.modal_frame.body.get_child(-1).pressed.emit()
	check(returned[0], "章节配置错误有返回入口")
	invalid.queue_free()
	await process_frame
	var path = Store.default_path("street_corner", true)
	Store.write_checkpoint({"version": "incompatible"}, path)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await modal(scene, "restore_error")
	scene._restart_run(123456)
	scene.guide.skip()
	scene.set_process(false)
	var opening = scene.sim.export_state()
	scene.sim.day = 3
	scene.sim.stars = 1
	scene.sim.unlock_land_plot("purchase_annex")
	for action in [
		[scene._show_cashier_front, "cashier_front"], [scene._show_cashier_page, "cashier"],
		[scene._show_purchase_page, "purchase"], [scene._buy.bind(0), "buy"],
		[scene._show_menu_page, "menu"], [scene._show_collection.bind(0), "collection"],
		[scene._show_plot_confirmation.bind("trophy_gallery"), "plot_unlock"],
		[scene._show_settings, "settings"], [scene._confirm_restart, "restart"],
	]:
		action[0].call()
		await modal(scene, action[1])
	scene._close_modal()
	scene.sim.restore_state(opening)
	scene._refresh_all()
	check(not scene.ui.trophy_bag.visible, "奖杯背包随展廊开放")
	var before_gallery = scene.sim.export_state()
	scene.sim.day = 5
	scene.sim.stars = 9
	scene.sim.unlock_land_plot("purchase_annex")
	scene.sim.unlock_land_plot("trophy_gallery")
	scene._show_trophy_shop()
	await modal(scene, "trophy_shop")
	await shot("trophy-case")
	var box = scene.trophy_box
	box.buy.pressed.emit()
	var opened_id = scene.sim.last_trophy_id
	var balance = scene.sim.gold
	box.buy.pressed.emit()
	check(box.opening and box.reel.rolling and scene.sim.trophy_draws_today == 1 and scene.sim.gold == balance, "开箱过程只扣费一次")
	check(box.reel.cards[box.reel.STOP_CARD].id == opened_id, "动画终点与已到账奖杯完全一致")
	await create_timer(.50).timeout
	await shot("trophy-spin")
	box.skip.pressed.emit()
	check(not box.opening and box.reel.reward.id == opened_id and box.ledger.text.contains("第 2 箱"), "揭晓后显示结果和下一箱")
	var result = Sim.new()
	check(result.restore_state(Store.read_checkpoint(path)).ok and result.last_trophy_id == opened_id and result.gold == balance, "开启动效前已完成存档")
	for reward in ["brass_spoon", "ember_cup", "dining_hourglass", "triad_pot", "feast_pot"]:
		box.reel.show_reward(scene.sim.relic_defs[reward])
		await shot("trophy-grade-" + str(int(scene.sim.relic_defs[reward].rarity)))
	scene._close_modal()
	scene._show_trophy_shop()
	check(scene.trophy_box.reel.reward.id == opened_id, "关闭再打开可看到已开出的奖杯")
	scene._close_modal()
	scene.sim.reputation = 1000
	scene._refresh_all()
	check(scene.sim.upgrade("relic_slots").ok, "可扩充展示位放置刚抽到的奖杯")
	scene._refresh_all()
	var hud = scene.service_feedback
	check(hud.rolls.has(scene.ui.gold_label) and hud.rolls.has(scene.ui.rep_label), "开箱和扩容覆盖金币、声望扣款动画")
	check(scene.ui.trophy_bag.visible, "已解锁展廊时显示独立背包")
	scene._show_trophy_bag()
	await modal(scene, "trophy_bag")
	scene._close_modal()
	scene._select_pending("trophy_" + str(scene.sim.owned_relics[-1]))
	scene.world._sync_trophy_placement()
	check(scene.world.trophy_cells.has(Vector2i(27, 10)) and not scene.world.trophy_cells.has(Vector2i(26, 10)) and not scene.world.trophy_cells.has(Vector2i(23, 8)), "展廊亮格匹配真实下放边界并排除已占用格")
	await shot("trophy-placement")
	scene._cancel_placement()
	scene.sim.day = 7
	check(scene.sim.unlock_land_plot("decor_studio").ok, "解锁装饰工坊")
	scene._inspect("facility", "decor_shop")
	await modal(scene, "decor_shop")
	await shot("decoration-shop")
	var stars_before = scene.sim.stars
	var coins_before = scene.sim.gold
	scene.modal_layer.find_child("Buy_meal_bell", true, false).pressed.emit()
	check(scene.sim.stored_facilities("decoration").size() == 1 and scene.sim.stars == stars_before - 1 and scene.sim.gold == coins_before, "装饰商店购买扣闪星并放入背包")
	var decoration = scene.sim.stored_facilities("decoration")[0]
	scene._close_modal()
	scene._select_pending(decoration.id)
	scene.world.hovered = Vector2i(4, 7)
	await RenderingServer.frame_post_draw
	check(scene.world.decor_preview.valid and scene.world.decor_preview.affected.any(func(f): return f.id == "table_1"), "摆放预览同步高亮被影响的餐桌")
	await shot("decoration-coverage")
	scene._move_facility(decoration.id, Vector2i(4, 7))
	check(scene.sim.Grid.placed(scene.sim.Grid.find(scene.sim.layout, decoration.id)), "展示中的装饰按预览落位")
	scene._store_selection()
	check(scene.sim.stored_facilities("decoration").size() == 1, "场景装饰可收回建造背包")
	scene.sim.day = 15
	scene._refresh_all()
	scene._show_major_event()
	await modal(scene, "major_event")
	await shot("food-inspection")
	scene._close_modal()
	scene.sim.restore_state(before_gallery)
	scene.service_feedback.reset()
	scene._refresh_all()
	scene.ui.gear.grab_focus()
	scene._show_settings()
	await RenderingServer.frame_post_draw
	check(scene.modal_frame.is_ancestor_of(root.gui_get_focus_owner()), "键盘焦点位于弹窗中")
	var original_size = root.size
	root.size = Vector2i(1440, 900) if original_size.x == 1100 else Vector2i(1100, 720)
	await modal(scene, "settings")
	root.size = original_size
	await RenderingServer.frame_post_draw
	scene._close_modal()
	check(root.gui_get_focus_owner() == scene.ui.gear, "关闭后焦点回到设置入口")
	scene._show_settings()
	var animated = scene.modal_frame
	check(animated.position.y > 0 and animated.modulate.a < 1.0, "弹窗从下方轻移并淡入")
	await create_timer(.29).timeout
	check(is_zero_approx(animated.position.y) and is_equal_approx(animated.modulate.a, 1.0), "弹窗在动画结束后稳定居中")
	scene._dismiss_modal()
	check(scene.modal_layer == null and scene.fading_modal != null and animated.closing and scene.world.camera_input_enabled, "关闭动画立即交还焦点和场景输入")
	scene._show_settings()
	check(scene.fading_modal == null and scene.modal_frame != animated, "快速重开不会留下旧弹窗")
	scene._dismiss_modal()
	await create_timer(.20).timeout
	check(scene.fading_modal == null, "淡出完成后回收弹窗")

	var world = scene.world
	world.set_process(false)
	world.chatter.rng.seed = 20261124
	world._update_lighting()
	var kitchen_lamps := 0
	var dining_lamps := 0
	for i in range(1, world.lamps.size()):
		var cell = Vector2i(world.lamp_positions[i].round())
		check(not world.Grid.structural_blocked(scene.sim.layout, cell), "室内灯位在已开放区域")
		var kitchen = scene.sim.layout.kitchen_bounds
		if cell.x <= kitchen.right and cell.y <= kitchen.bottom: kitchen_lamps += 1
		elif cell.y > kitchen.bottom: dining_lamps += 1
	check(kitchen_lamps >= 2 and dining_lamps >= 4, "厨房和客席均有多处照明")
	check(world.self_modulate.get_luminance() > world.street_canvas.self_modulate.get_luminance() + .20, "夜晚室内环境光高于街道")
	var occluder = world.shadow_geometry.get_child(0)
	scene.sim.revision += 1
	world._update_lighting()
	check(world.shadow_geometry.get_child(0) == occluder, "非布局变更复用遮挡体")
	var old_cell = world.screen_point(Vector2(3, 3))
	world.zoom *= 1.25
	world._update_lighting()
	check(not old_cell.is_equal_approx(world.screen_point(Vector2(3, 3))) and world.lamps[0].position.is_equal_approx(world.screen_point(world.lamp_positions[0])), "缩放后餐灯仍对准光源")
	world.focus_restaurant()
	world._process(0)
	await shot("night-interior")

	# Exercise the first patience penalty even when a third pot finishes early.
	scene.sim.chapter.common_guest_template.food_penalty_cycle_seconds = 5.0
	scene._open_day()
	scene.sim.paused = false
	scene.status_timer = 0
	world._process(0.0)
	check(world._scene_hour() >= 20.0 and scene.sim.clock_text() == "09:00", "开店立即开始营业，画面从夜色过渡")
	world._process(.68)
	check(world._scene_hour() > 5.0 and world._scene_hour() < 9.0 and scene.sim.tick == 0, "晨光过渡经过黎明，视觉时间不推进经营")
	await shot("dawn-motion")
	world._process(1.0)
	check(is_equal_approx(world._scene_hour(), 9.0), "过渡后画面回到营业时钟")
	var observed_bells: Array = []
	scene.sim.service_bell.connect(func(midnight): observed_bells.append([scene.sim.tick, midnight]))
	var saw_payment := false
	# Advance the same guest transitions as a live service, with several ticks between presentations.
	while scene.sim.phase == "DAY":
		scene.sim.paused = false # Native test windows can exchange OS focus during a screenshot.
		for n in range(5): scene.sim.step()
		if scene.sim.phase != "DAY": break
		if not saw_payment and not scene.service_feedback.flights.is_empty():
			saw_payment = true
			var effect = scene.service_feedback
			var payment = effect.flights[0]
			scene._update_hud()
			check(int(payment.amount) > 0 and Rect2(Vector2.ZERO, root.size).has_point(payment.origin), "画面内客人付费时启动金币飞行")
			check(effect.amounts.get(scene.ui.gold_label) == scene.sim.gold and effect.pulses.has(scene.ui.gold_label) and effect.rolls.has(scene.ui.gold_label), "余额向最新实收数字滚动并触发轻跳")
			check(effect.amounts.get(scene.ui.income_label) == scene.sim.stats.income and effect.pulses.has(scene.ui.income_label), "今日营收同步滚动并轻跳")
			var pulse = effect.pulses[scene.ui.gold_label]
			var samples: Array = []
			for _frame in range(8):
				await process_frame
				samples.append([pulse.get_total_elapsed_time(), scene.ui.gold_label.scale.y])
				if scene.ui.gold_label.scale.y > 1.05: break
			check(scene.ui.gold_label.scale.y > 1.05, "余额轻跳在画面中可见 " + str(samples))
			await shot("payment-motion")
		var previous_bubble = world.chatter.bubble
		if is_instance_valid(previous_bubble) and not previous_bubble.is_queued_for_deletion(): previous_bubble._process(.25)
		world._process(.25)
		var bubble = world.chatter.bubble
		if not is_instance_valid(bubble) or bubble.is_queued_for_deletion() or not bubble.visible: continue
		var moment = world.chatter.speaking.moment
		if seen.has(moment): continue
		seen[moment] = true
		scene._update_hud()
		check(bubble.compact and bubble.mouse_filter == Control.MOUSE_FILTER_IGNORE and bubble.anchor.call() != null, "气泡绑定活跃客人且不遮挡输入 " + str(moment))
		await shot(str(moment))
		check(bubble.size.x <= 108 and bubble.size.y <= 28, "客人短句为紧凑单行 " + str(moment))
		if moment == &"arrival":
			var voice = world.say("s_1", "阿禾", "这边请。", 4.0, true)
			world._process(0)
			check(world.chatter.bubble == null and world.chatter.pending.is_empty(), "阿禾开口立即让出气泡")
			voice.dismiss()
	for moment in [&"arrival", &"waiting", &"eating", &"after_meal", &"closing", &"midnight", &"impatient"]:
		check(seen.has(moment), "实机出现对应气泡 " + str(moment))
	check(observed_bells == [[scene.sim.day_ticks, false], [scene.sim.midnight_ticks, true]], "两次打烊提示各触发一次")
	check(saw_payment, "完整营业日触发实际付款反馈")
	var effect = scene.service_feedback
	effect.reset()
	for n in range(effect.MAX_FLIGHTS + 10):
		effect.add_payment(Vector2(root.size) * .5, 10)
	check(effect.flights.size() == effect.MAX_FLIGHTS, "密集结账时限制屏幕金币数量")
	effect._process(effect.TRAVEL_TIME + effect.RING_TIME + .02)
	check(effect.flights.is_empty(), "金币飞行及到达光圈结束后自动回收")
	for moment in world.chatter.LINES:
		var first = world.chatter._pick_line(moment)
		check(world.chatter._pick_line(moment) != first, "同一状态连续两句不同 " + str(moment))
	check(world.chatter.sequence <= 15, "普通速度完整营业日的发言次数受限")
	var control = Sim.new()
	control.new_run(123456)
	control.chapter.common_guest_template.food_penalty_cycle_seconds = 5.0
	control.start_day()
	while control.phase == "DAY": control.step()
	check(control.last_report == scene.sim.last_report and control.gold == scene.sim.gold, "气泡抽选不影响同种子经营结果")
	world._process(0)
	check(world.chatter.pending.is_empty() and not is_instance_valid(world.chatter.bubble), "结算清理气泡")
	scene._show_report(true)
	await modal(scene, "report")
	var report_panel = scene.modal_frame.body.get_child(0)
	var ring = report_panel.find_child("GuestOutcomes", true, false)
	check(ring.arrivals == scene.sim.last_report.arrived and ring.reveal < 1.0 and report_panel.find_child("coins_daily_change", true, false) != null, "日报环形图逐段展开，金币余额合并今日营收")
	var wallet = scene.ui.gold_label
	var pulse_effect = scene.service_feedback
	scene._update_hud()
	var prior_gold = scene.sim.gold
	pulse_effect.reset()
	pulse_effect.show_resource(wallet, prior_gold, "$")
	pulse_effect.show_resource(wallet, prior_gold - 40, "$")
	pulse_effect.rolls[wallet].custom_step(.15)
	check(pulse_effect.displayed[wallet] < prior_gold and pulse_effect.displayed[wallet] > prior_gold - 40 and pulse_effect.pulses.has(wallet), "扣除资源时实际出现中间数字和跳动")
	pulse_effect.rolls[wallet].custom_step(1.0)
	check(wallet.text == "%d$" % (prior_gold - 40), "扣款动画结束后落到目标值")
	check(not report_panel.earned_goals.is_empty() and report_panel.earned_goals[0].modulate.a < 1.0, "首次结算依次点亮已获得的闪星")
	world._process(1.0)
	scene._continue_night()
	world._process(0.0)
	check(is_equal_approx(world._scene_hour(), 24.0), "进入下一夜时灯光从结算场景接续")
	world._process(.32)
	check(world._scene_hour() > 22.0 and world._scene_hour() < 24.0, "次夜灯光平滑过渡")
	world._process(.50)
	check(is_equal_approx(world._scene_hour(), 22.0), "次夜过渡结束后光照稳定")
	scene._open_day()
	scene.sim.paused = false
	while scene.sim.phase == "DAY": scene.sim.step()
	scene._show_report()
	await modal(scene, "report")
	var bars = scene.modal_layer.find_children("ComparisonBar*", "Control", true, false)
	check(bars.size() == 4 and bars.any(func(bar): return bar.has_previous and bar.change.a > 0), "第二天进度条显示昨日刻线与变化颜色")
	await create_timer(.85).timeout
	await shot("report-comparison")
	var report_views = scene.modal_layer.find_child("ReportViews", true, false)
	report_views.current_tab = 1
	await modal(scene, "report")
	await shot("report-details")
	scene._continue_night()
	for plot in scene.sim.chapter.land_plots:
		scene.sim.day = plot.unlock_day
		scene.sim.stars += plot.star_cost
		check(scene.sim.unlock_land_plot(plot.id).ok, "解锁 " + str(plot.id))
		world._process(0)
		var lit := false
		for position in world.lamp_positions:
			var land = world.Grid.plot_at(scene.sim.layout, Vector2i(position.round()))
			if land.get("id", "") == plot.id: lit = true
		check(lit, "扩建后新区域亮灯 " + str(plot.id))
	scene.queue_free()
	await process_frame
	print("PRESENTATION RESULT: %d passed / %d failed" % [passed, failures])
	quit(1 if failures else 0)
