extends SceneTree

const Grid = preload("res://scripts/core/layout.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/chapter_progress.gd")
var passed = 0
var failed = 0
var cases = []

class OpeningCheckSim extends "res://scripts/core/simulation.gd":
	var checks := 0

	func opening_errors() -> Array:
		checks += 1
		return super.opening_errors()

func expect(value: bool, label: String) -> void:
	cases.append({"label":label,"passed":value})
	if value: passed += 1
	else:
		failed += 1
		push_error("UI logic FAIL: " + label)

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var lots = Sim.new()
	expect(lots.catalog.errors.is_empty() and lots.opening_errors().is_empty(),"LAND: 扩建地图开局仍可营业")
	expect(Grid.structural_blocked(lots.layout,Vector2i(14,2)) and Grid.structural_blocked(lots.layout,Vector2i(26,3)),"LAND: 未解锁厨房和奖杯区均阻断通行")
	lots.stars = 30
	expect(not lots.unlock_land_plot("kitchen_extension").ok and not lots.unlock_land_plot("east_dining").ok,"LAND: 解锁日期和先后顺序同时生效")
	for plot in lots.layout.plots:
		lots.day = int(plot.unlock_day)
		expect(lots.unlock_land_plot(plot.id).ok and lots.opening_errors().is_empty(), "LAND: 解锁后通路有效 " + str(plot.id))
	expect(lots.attributes.chefs == 3 and Grid.facilities(lots.layout, "stove").size() == 3, "LAND: 厨房赠送灶台与配套厨师")
	expect("bronze_clock" in lots.owned_relics and lots.attributes.tables == 18, "LAND: 赠送奖杯和客桌")
	var lots_copy = Sim.new()
	expect(lots_copy.restore_state(lots.export_state()).ok and lots_copy.layout.unlocked_plots==lots.layout.unlocked_plots,"LAND: 扩建顺序与赠送资产能完整存档")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in range(3): await process_frame
	scene.guide.skip()
	var counted = OpeningCheckSim.new()
	scene.sim = counted
	scene.world.sim = counted
	scene._restart_run(123456)
	for i in range(3): await process_frame
	var stove_cell = Vector2i(Grid.vec(Grid.find(counted.layout, "stove_1").pos))
	var before = counted.checks
	for i in range(3): scene._update_hud()
	expect(counted.checks == before and not scene.ui.open.disabled, "OPEN: 有效布局闲置时 HUD 复用开店校验")
	counted.store_facility("stove_1")
	scene.status_timer = 0
	scene._refresh_all()
	for i in range(3): scene._update_hud()
	expect(counted.checks == before + 1 and scene.ui.open.disabled and scene.ui.toast_card.visible and scene.ui.toast_label.text.contains("灶台"), "OPEN: 收起灶台只重算一次，开店按钮和提示同步")
	expect(not counted.start_day().ok and counted.checks == before + 2, "OPEN: 正式开店独立校验并拒绝无效布局")
	counted.move_facility("stove_1", stove_cell)
	scene._refresh_all()
	expect(counted.checks == before + 3 and not scene.ui.open.disabled and not scene.ui.toast_card.visible, "OPEN: 放回灶台重新启用开店并清除提示")
	expect(scene.ui.rent_label.text == "$%d" % int(counted.next_rent().amount) and scene.ui.rent_days.text == "6天" and scene.ui.rent_card.tooltip_text.contains("房租"), "房租与剩余天数分栏，详情通过悬浮查看")
	expect(scene.ui.clock.text == "09:00" and scene.ui.rep_label.get_parent().get_parent().get_child(0).glyph == "reputation" and scene.ui.rep_label.tooltip_text == "声望", "营业时钟和声望使用图标与数字")
	expect(scene.world.sun_light.shadow_enabled and scene.world.shadow_geometry.get_child_count()>10,"LIGHT: 灯光和墙/家具真实遮挡体已创建")
	var geography = preload("res://scenes/canyon/geography.tscn").instantiate()
	var walls = geography.get_node("workshop").find_children("*", "MeshInstance3D",true,false)
	expect(not walls.is_empty() and walls.all(func(piece): return piece.mesh != null and piece.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),"工坊有独立的三维屋顶和墙体")
	geography.free()
	var street = scene.world.street
	var parked = street.vehicle_position(0)
	var walker = street.pedestrian_position(0)
	var previous_layout = scene.sim.layout.duplicate(true)
	street.advance(1.25, true)
	expect(street.vehicle_position(0) == parked and street.pedestrian_position(0) == walker, "CITY: 车辆与行人随营业暂停")
	street.advance(1.25, false)
	var car = street.vehicle_position(0)
	var pedestrian = street.pedestrian_position(0)
	expect(car.y != parked.y and pedestrian.y != walker.y and car.x < street.ROAD_RIGHT and pedestrian.x > street.ROAD_RIGHT and scene.sim.layout == previous_layout, "CITY: 车流和人流分道移动，与经营布局隔离")
	var sun_cell = (scene.world.sun_light.position-scene.world._origin())/scene.world._unit()
	scene.world.camera_pan = Vector2(91,37)
	scene.world._update_lighting()
	expect(((scene.world.sun_light.position-scene.world._origin())/scene.world._unit()).is_equal_approx(sun_cell),"LIGHT: 平移镜头不改变太阳相对于餐厅的世界位置")
	scene.world.camera_pan = Vector2.ZERO
	var original_world_size = scene.world.size
	scene.world.size = original_world_size * .78
	scene.world._update_lighting()
	expect(((scene.world.sun_light.position-scene.world._origin())/scene.world._unit()).is_equal_approx(sun_cell),"LIGHT: 调整窗口尺寸不改变太阳在地图上的位置")
	scene.world.size = original_world_size
	scene.world._update_lighting()
	expect(scene.world._ambient_tint(9.0).a > scene.world._ambient_tint(12.0).a and scene.world._ambient_tint(18.0)!=scene.world._ambient_tint(21.0),"LIGHT: 环境色调随时间连续插值")
	scene._inspect("facility","cashier")
	expect(scene.modal_kind=="cashier_front","CASHIER: 收银台先展示功能入口")
	scene._show_cashier_page()
	expect(scene.modal_kind=="cashier","CASHIER: 声望升级经按钮进入")
	scene._dismiss_modal()
	var before_gallery = scene.sim.export_state()
	scene.sim.stars = 9
	scene._show_trophy_shop()
	expect(scene.modal_layer == null, "锁定展廊时不能通过快捷按钮打开商店")
	scene.sim.day = 5
	scene.sim.unlock_land_plot("purchase_annex")
	scene.sim.unlock_land_plot("trophy_gallery")
	scene._inspect("facility", "trophy_shop")
	expect(scene.modal_kind == "trophy_shop", "独立奖杯盲盒在展廊开放时可用")
	var before_draw = scene.sim.gold
	var star_balance = scene.sim.stars
	scene.trophy_box.buy.pressed.emit()
	expect(scene.sim.owned_relics.size() == 2 and scene.service_feedback.amounts.get(scene.ui.gold_label) == scene.sim.gold and scene.sim.gold < before_draw and scene.sim.stars == star_balance, "TROPHY: 开箱同步金币 HUD 与背包")
	scene.trophy_box.skip.pressed.emit()
	var purchased_state = scene.sim.export_state()
	var working_path = scene.save_path
	scene.save_path = "res://project.godot/rejected_checkpoint.json"
	scene.trophy_box.buy.pressed.emit()
	expect(scene.sim.export_state() == purchased_state and not scene.trophy_box.opening, "TROPHY: 存档写入失败回滚当次扣款、奖杯和随机状态")
	scene.save_path = working_path
	scene._show_trophy_bag()
	expect(scene.modal_kind=="trophy_bag","TROPHY: 已购奖杯可在背包中管理")
	scene._dismiss_modal()
	scene.sim.restore_state(before_gallery)
	scene._refresh_all()
	scene.sim.grant_buff("high_heat",2)
	scene.sim.grant_buff("five_star_service",2)
	scene._inspect("facility","stove_1")
	expect(scene.ui.info_body.text.contains("出餐口") and scene.ui.info_body.text.contains("(+20%)") and scene.ui.info_body.text.contains("大火收汁"),"灶台详情显示基础效率与增益说明")
	scene.ui.info_panel.hide()
	expect(scene.service_feedback.amounts.get(scene.ui.gold_label) == 600 and scene.service_feedback.amounts.get(scene.ui.rep_label) == 0,"夜晚金币余额与当前声望不归零")
	var avatar_id = ""
	for id in scene.world.actors:
		if str(id).begins_with("preview_"):
			avatar_id = id
			break
	expect(not avatar_id.is_empty(),"夜晚角色已创建")
	if not avatar_id.is_empty():
		var avatar = scene.world.actors[avatar_id]
		var upper = avatar.position - Vector2(0,22*avatar.scale.y)
		expect(scene.world._actor_at(upper)==avatar_id,"角色头部属于点击热区")
		scene.world._inspect_actor(upper)
		expect(scene.ui.info_panel.visible and scene.ui.info_title.text.contains("预备中") and scene.ui.info_body.text.contains("已雇佣"),"夜晚人物详情显示本角色说明")
		scene.ui.info_panel.hide()
		avatar.rare_name = "探店博主"
		var foot_label = avatar.position + Vector2(20*avatar.scale.x,28*avatar.scale.y)
		expect(scene.world._actor_at(foot_label)==avatar_id,"名字标签左右区域可点击")
		avatar.rare_name = ""
	var hover = InputEventMouseMotion.new()
	scene.sim.day = 3
	scene.sim.stars = 1
	scene.sim.unlock_land_plot("purchase_annex")
	scene._refresh_all()
	hover.position = scene.world.screen_point(Grid.vec(Grid.find(scene.sim.layout,"slot").pos))
	scene.world._gui_input(hover)
	expect(scene.world.mouse_default_cursor_shape==Control.CURSOR_POINTING_HAND,"设施悬停变手形指针")
	var recipe_stats = []
	scene._show_purchase_page()
	for label in scene.modal_layer.find_children("*","Label",true,false):
		if label.text.contains("份/锅") and label.tooltip_text.contains("当前品质"): recipe_stats.append(label)
	expect(recipe_stats.size()==1,"菜谱卡保留产量，品质在悬停详情中显示")
	scene._dismiss_modal()
	var right = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = Vector2(800,480)
	scene.world._gui_input(right)
	var held = InputEventMouseMotion.new()
	held.position = Vector2(820,495)
	held.relative = Vector2(20,15)
	held.button_mask = MOUSE_BUTTON_MASK_RIGHT
	scene.world._gui_input(held)
	expect(scene.world.camera_pan==Vector2(20,15),"右键按住拖动正常")
	var released_elsewhere = InputEventMouseMotion.new()
	released_elsewhere.position = Vector2(840,495)
	released_elsewhere.relative = Vector2(20,0)
	released_elsewhere.button_mask = 0
	scene.world._gui_input(released_elsewhere)
	expect(scene.world.camera_pan==Vector2(20,15) and not scene.world.dragging_camera,"右键从UI外释放不会粘住")
	scene.world.focus_restaurant()
	scene._open_day()
	scene.sim._spawn_customer({"id":5000,"type":"normal"})
	scene.world._sync_actors()
	var queue_point: Vector2=scene.world.actor_cells["g_5000"]
	expect(queue_point.distance_to(Grid.vec(scene.sim.layout.entrance))<2.0,"临时来客在门外步道排队")
	scene.sim._assign_seats()
	scene.world._sync_actors()
	expect(scene.world.actor_cells["g_5000"].distance_to(queue_point)<.12,"获得座位后从当前队列位置连续进门")
	scene._inspect("customer","5000")
	expect(scene.ui.guest_profile.dish.text == "尚未选菜" and scene.ui.guest_profile.trait_label.text.contains("(+25%)") and scene.ui.guest_profile.trait_label.text.contains("5 星服务"),"客人详情显示菜名与耐心增益")
	scene.ui.info_panel.hide()
	scene.sim._terminal(scene.sim.customers[5000],"Q")
	scene._toggle_fast()
	expect(scene.fast_forward and scene.ui.fast.text=="8×" and bool(scene.ui.fast.get_meta("active_visual",false)),"快进显示当前倍率和高亮")
	scene._toggle_fast()
	expect(not scene.fast_forward and scene.ui.fast.text=="1×" and not bool(scene.ui.fast.get_meta("active_visual",false)),"回到1倍可恢复普通按钮")
	scene._restart_run(123456)
	scene.sim.day = 4
	for day in [4, 5]:
		scene._open_day()
		while scene.sim.phase == "DAY": scene.sim.step()
		for i in range(2): await process_frame
		var labels = scene.modal_layer.find_children("*", "Label", true, false)
		if day == 4:
			var buttons = scene.modal_layer.find_children("*", "Button", true, false)
			var locate = buttons.filter(func(button): return button.text.begins_with("在餐厅定位"))
			expect(locate.size() == 1, "REPORT: 日报突出一个可定位的营业问题")
			if locate.size() == 1:
				locate[0].pressed.emit()
				expect(scene.sim.phase == "REPORT" and scene.modal_kind.is_empty() and scene.ui.diagnostic_card.visible and not scene.world._diagnostic_cells().is_empty(), "REPORT: 点定位后在地图高亮目标并保留结算阶段")
				scene.ui.diagnostic_button.pressed.emit()
				expect(scene.modal_kind == "report", "REPORT: 从地图返回同一张日报")
		else:
			expect(labels.any(func(label): return label.is_visible_in_tree() and label.text == "明日预告") and labels.any(func(label): return label.is_visible_in_tree() and label.text.contains("12:00–14:00")), "EVENT: 第五天日报总览预告次日午市")
			var views = scene.modal_layer.find_child("ReportViews", true, false)
			var focus = str(scene.sim.reports[-2].diagnosis.focus)
			var breakdown = views.find_child("ServiceBreakdown", true, false)
			expect(views.current_tab == 0 and not breakdown.is_visible_in_tree(), "REPORT: 日报默认打开总览")
			views.current_tab = 1
			await process_frame
			var stage = scene.sim.reports[-2].diagnosis.stages[focus]
			var old_value = breakdown.find_child(focus + "_yesterday", false, false)
			var unit = "%" if focus == "queue" else " 秒"
			expect(breakdown.is_visible_in_tree() and old_value.text == "%.1f%s" % [stage.average, unit], "REPORT: 明细逐项对比同一环节的昨日数值")
		scene._continue_night()
	expect(scene.ui.peak_card.visible and scene.ui.peak_label.text.contains("45%"), "EVENT: 第六天开店前持续展示午市比例")
	scene._discard_fading_modal()
	scene._advance_major_event_popup(scene.MAJOR_EVENT_DELAY - .1)
	expect(scene.modal_layer == null and scene.pending_major_event == "food_festival", "EVENT: 未到延时不主动弹出")
	scene._show_settings()
	scene._advance_major_event_popup(.2)
	expect(scene.modal_kind == "settings", "EVENT: 主动公告等当前窗口关闭")
	scene._close_modal()
	scene._advance_major_event_popup(.1)
	expect(scene.modal_kind == "major_event" and "food_festival" in scene.sim.major_event_views and "food_festival" not in scene.sim.major_event_claims, "EVENT: 首次主动弹出并保留手动领取")
	scene._close_modal()
	scene._refresh_all()
	scene._advance_major_event_popup(4.0)
	expect(scene.modal_layer == null, "EVENT: 看过的公告不重复弹出")
	scene.queue_free()
	await process_frame
	Store.write_checkpoint({"completed": []}, Progress.path(true))
	Store.write_checkpoint(Sim.new().export_state(), Store.default_path("street_corner", true))
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	expect(title.menu.visible and title.chapter_buttons.size() == 2, "TITLE: 主界面提供两个章节")
	await _open_entry(title)
	title.chapter_buttons.market_lane.button.pressed.emit()
	title.start_button.pressed.emit()
	expect(title.game == null and title.start_button.disabled and title.chapter_buttons.market_lane.status.glyph == "lock", "TITLE: 首次打开时第二章显示锁定，无法从开始入口进入")
	title.chapter_buttons.street_corner.button.pressed.emit()
	title.start_button.pressed.emit()
	await _resume_game(title)
	var first = title.game
	first.sim.day = int(first.sim.chapter.chapter_days)
	first.sim.gold = 0
	first.sim.start_day()
	while first.sim.phase == "DAY": first.sim.step()
	for i in range(2): await process_frame
	expect(first.sim.last_report.result == "LOSE", "TITLE: 最终房租未缴清，产生失败结算")
	first._return_to_title()
	for i in range(2): await process_frame
	expect(title._chapter_locked("market_lane"), "TITLE: 第一章失败无法解锁下一章")
	await _open_entry(title)
	title.start_button.pressed.emit()
	await _resume_game(title)
	first = title.game
	first._restart_run(123456)
	first.sim.day = int(first.sim.chapter.chapter_days)
	first.sim.gold = int(first.sim.next_rent().amount)
	first.sim.start_day()
	while first.sim.phase == "DAY": first.sim.step()
	for i in range(2): await process_frame
	expect(first.sim.last_report.result == "WIN" and Progress.completed(title.options, true).has("street_corner"), "TITLE: 缴清最后一笔房租立即登记通关")
	var return_buttons = first.modal_layer.find_children("*", "Button", true, false).filter(func(button): return button.text == "返回章节")
	expect(return_buttons.size() == 1, "TITLE: 胜利结算提供返回章节入口")
	if return_buttons.size() == 1: return_buttons[0].pressed.emit()
	else: first._return_to_title()
	for i in range(2): await process_frame
	expect(title.selected_chapter == "market_lane" and not title.start_button.disabled and title.chapter_buttons.street_corner.status.glyph == "check", "TITLE: 返回主界面默认选中刚解锁的下一章")
	await _open_entry(title)
	var new_market: bool = title.selected_save.is_empty()
	title.start_button.pressed.emit()
	expect((title.crew_layer != null and title.game == null) == new_market, "TITLE: 新章先选将，已有存档直接续玩")
	if title.crew_layer != null:
		var chooser = title.crew_layer.find_child("OpeningDraft", true, false)
		for id in chooser.cards:
			chooser.cards[id].pick.pressed.emit()
			chooser.get_node("%Pick").pressed.emit()
		chooser.get_node("%Confirm").pressed.emit()
	await _resume_game(title)
	expect(title.game.sim.chapter.id == "market_lane" and title.game.sim.menu == ["batch_snacks"], "TITLE: 选择第二章会载入第二章的配置和菜谱")
	title.game._restart_run(123456)
	title.game.sim.gold = 761
	var market_save = str(title.game.save_path)
	title.game._return_to_title()
	for i in range(2): await process_frame
	expect(title.menu.visible and title.start_button.text.begins_with("继续经营"), "TITLE: 设置返回主界面后显示本章节继续入口")
	await _open_entry(title)
	title.start_button.pressed.emit()
	await _resume_game(title)
	expect(title.game.sim.gold == 761, "TITLE: 继续第二章恢复独立进度")
	title.game._return_to_title()
	for i in range(2): await process_frame
	await _open_entry(title)
	title.chapter_buttons.street_corner.button.pressed.emit()
	title.start_button.pressed.emit()
	await _resume_game(title)
	expect(title.game.sim.chapter.id == "street_corner" and title.game.save_path != market_save and title.game.sim.gold != 761, "TITLE: 切回第一章使用另一份存档")
	title.game._restart_run(123456)
	title.game._return_to_title()
	for i in range(2): await process_frame
	expect(not title._chapter_locked("market_lane"), "TITLE: 重开第一章不会撤销已经获得的解锁")
	var data = {"passed":passed,"failed":failed,"cases":cases}
	var file = FileAccess.open("res://.local/bugcheck_ui_logic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	print("UI LOGIC RESULT: ",passed," passed / ",failed," failed")
	title.queue_free()
	await create_timer(.6).timeout
	quit(1 if failed>0 else 0)

func _open_entry(title) -> void:
	title._select_place("tavern")
	await title.get_node("Menu/CanyonHub").at_door

func _resume_game(title) -> void:
	if title.game == null: await title.get_node("Menu/CanyonHub").door_crossed
	if title.game.world.entering_canyon: await title.game.world.entry_finished
