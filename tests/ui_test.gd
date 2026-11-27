extends SceneTree

const Grid = preload("res://scripts/core/layout.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/chapter_progress.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const KeyBindings = preload("res://scripts/ui/key_bindings.gd")
var passed = 0
var failed = 0
var checks: Array = []

func expect(value: bool, name: String) -> void:
	checks.append({"name":name,"passed":value})
	if value: passed += 1
	else: failed += 1; push_error("UI FAIL: " + name)

func _initialize() -> void:
	call_deferred("execute")

func click(board, location: Vector2) -> void:
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = location
	board._gui_input(e)
	e.pressed = false
	board._gui_input(e)

func click_control(control: Control) -> void:
	click_at(control.get_global_rect().get_center())

func click_at(location: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = location
	root.push_input(motion, true)
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = location
	press.pressed = true
	root.push_input(press, true)
	var release = press.duplicate()
	release.pressed = false
	root.push_input(release, true)

func press_key(code: Key) -> void:
	var key = InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	root.push_input(key, true)
	var release = key.duplicate()
	release.pressed = false
	root.push_input(release, true)

func drag_on_board(board: Control, origin: Vector2, destination: Vector2, hold: bool = true) -> Dictionary:
	var transform = board.get_global_transform_with_canvas()
	var hover = InputEventMouseMotion.new()
	hover.position = transform * origin
	root.push_input(hover, true)
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = hover.position
	press.pressed = true
	root.push_input(press, true)
	var picked = str(board.pressed_entity)
	if hold:
		var deadline = Time.get_ticks_msec() + 1600
		while not board.drag_active and not board.pressed_entity.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
	var armed = bool(board.drag_active)
	var motion = InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = transform * destination
	motion.relative = motion.position - press.position
	root.push_input(motion, true)
	var release = press.duplicate()
	release.position = motion.position
	release.pressed = false
	root.push_input(release, true)
	return {"picked": picked, "armed": armed}

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var output = "res://.local/preview_street_%dx%d_%s.png" % [root.size.x, root.size.y, name]
	expect(image.save_png(ProjectSettings.globalize_path(output))==OK,"原生截图："+name)

func verify_shortcuts(scene) -> void:
	await process_frame
	var keyboard = scene.modal_layer.find_child("OpenKeySettings", true, false)
	click_control(keyboard)
	expect(scene.modal_kind == "key_settings" and scene.binding_buttons.size() == 13, "设置菜单可打开操作与页面的键位列表")
	await process_frame
	click_control(scene.binding_buttons.build)
	press_key(KEY_M)
	expect(scene.binding_action == "build" and scene.modal_frame.feedback.visible and scene.modal_frame.feedback.text.contains("菜谱") and scene.keys.action_for(KEY_B) == "build", "重新绑定会提示重复键，原键位可继续使用")
	press_key(KEY_J)
	var restored = KeyBindings.new(scene.keys.save_path)
	expect(scene.binding_action.is_empty() and scene.binding_buttons.build.text == "J" and restored.action_for(KEY_J) == "build" and scene.ui.build.tooltip_text.contains("[J]"), "新键位已保存，重新读取与界面提示一致")
	await shot("keyboard_settings")
	press_key(KEY_ESCAPE)
	expect(scene.modal_kind == "settings", "Esc 从按键设置回到设置页")
	scene._dismiss_modal()
	press_key(KEY_B)
	expect(not scene.ui.build_catalog.visible, "修改后旧建造键停止响应")
	press_key(KEY_J)
	expect(scene.ui.build_catalog.visible and scene.modal_layer == null, "修改后的键打开底部建造目录")
	press_key(KEY_J)
	press_key(KEY_Y)
	expect(scene.modal_layer == null, "奖杯商店捷径不能绕过展廊解锁")
	press_key(KEY_P)
	expect(scene.modal_layer == null, "采购快捷键不能绕过采购小厅解锁")
	for item in [[KEY_M, "menu"], [KEY_U, "cashier"]]:
		press_key(item[0])
		expect(scene.modal_kind == item[1], "快捷键打开页面 " + str(item[1]))
		scene._dismiss_modal()
	scene._show_key_settings()
	scene.modal_layer.find_child("ResetKeyBindings", true, false).pressed.emit()
	expect(scene.keys.action_for(KEY_B) == "build" and scene.keys.action_for(KEY_J).is_empty(), "可恢复默认键位")
	scene._dismiss_modal()

func verify_building(scene) -> void:
	scene.sim.move_facility("table_9", Vector2i(2, 9))
	scene._refresh_all()
	click(scene.world, scene.world.screen_point(Vector2(6, 12)))
	await process_frame
	expect(scene.ui.split.visible and scene.ui.split.text.is_empty() and scene.ui.split.tooltip_text.contains("拆分") and scene.ui.split.global_position.y > scene.size.y * .75, "多人桌在右下角显示带悬停说明的拆分图标")
	click_control(scene.ui.split)
	var halves = Grid.facilities(scene.sim.layout, "table").filter(func(f): return Grid.table_size(f) == 2)
	expect(halves.size() == 2 and scene.ui.info_title.text == "双人桌", "点击拆分后四人桌变成两张双人桌")
	if halves.size() != 2: return
	press_key(KEY_X)
	expect(Grid.table_size(Grid.find(scene.sim.layout, "table_1")) == 1 and not scene.ui.split.visible, "选中双人桌时按 X 变成单人桌，按钮随之隐藏")
	var spare = halves.filter(func(f): return f.id != "table_1")[0]
	var spare_id = str(spare.id)
	var anchor = Grid.vec(spare.pos)
	click(scene.world, scene.world.screen_point(anchor))
	press_key(KEY_BACKSPACE)
	expect(scene.sim.stored_facilities("table").any(func(f): return f.id == spare_id), "按 Backspace 收起选中的桌子")
	await process_frame
	click_control(scene.ui.build)
	await process_frame
	var catalog = scene.ui.build_catalog
	var entry = catalog.find_child("Build_" + spare_id, true, false)
	expect(scene.modal_layer == null and catalog.visible and catalog.category_buttons.size() == 6 and is_instance_valid(entry) and entry.is_visible_in_tree(), "底部目录打开时显示库存并保留场景输入")
	if not is_instance_valid(entry): return
	check_catalog_search(catalog, spare_id)
	entry = catalog.find_child("Build_" + spare_id, true, false)
	await process_frame
	click(scene.world, scene.world.screen_point(Grid.vec(Grid.find(scene.sim.layout, "table_1").pos)))
	check_build_tools(scene)
	await shot("build_inventory")
	click_control(entry)
	expect(scene.world.editing and scene.world.selected_id == spare_id and scene.modal_layer == null and catalog.visible, "选中背包物块后进入场景放置模式")
	click(scene.world, scene.world.screen_point(anchor))
	expect(Grid.placed(Grid.find(scene.sim.layout, spare_id)) and scene.sim.stored_facilities("table").is_empty(), "场景成功放下选中的双人桌并从背包移出")
	press_key(KEY_BACKSPACE)
	click_control(catalog.category_buttons.wall)
	await process_frame
	var wall_button = catalog.find_child("BuildWall", true, false)
	expect(catalog.active_category == "wall" and wall_button.is_visible_in_tree(), "可切换到隔墙分类")
	click_control(wall_button)
	var cash = scene.sim.gold
	await drag_on_board(scene.world, scene.world.screen_point(Vector2(2, 14)), scene.world.screen_point(Vector2(4, 14)), false)
	expect(scene.world.placing_wall and Grid.facilities(scene.sim.layout, "wall").size() == 3 and scene.sim.gold == cash, "按住左键横拖一次铺下三格墙")
	press_key(KEY_R)
	await drag_on_board(scene.world, scene.world.screen_point(Vector2(8, 12)), scene.world.screen_point(Vector2(11, 14)), false)
	var turned = Grid.facility_at(scene.sim.layout, Vector2i(8, 14))
	expect(turned.get("type") == "wall" and Grid.rotation(turned) == 1 and Grid.facilities(scene.sim.layout, "wall").size() == 6, "按 R 后拖动会沿竖向铺墙")
	var chair = Grid.interaction(Grid.find(scene.sim.layout, "table_1"))
	click(scene.world, scene.world.screen_point(chair))
	expect(Grid.facilities(scene.sim.layout, "wall").size() == 6 and scene.ui.toast_label.text.contains("阻断"), "封堵座位的墙体会被拒绝并提示")
	await drag_on_board(scene.world, scene.world.screen_point(Vector2(1, 12)), scene.world.screen_point(Vector2(1, 13)), false)
	expect(Grid.facilities(scene.sim.layout, "wall").size() == 6 and scene.ui.toast_label.text.contains("阻断"), "封路的整排墙不产生部分放置")
	press_key(KEY_ESCAPE)
	expect(not scene.world.placing_wall and catalog.visible, "第一次 Esc 取消建墙并保留目录")
	await process_frame
	await shot("build_wall")
	click(scene.world, scene.world.screen_point(Vector2(2, 14)))
	press_key(KEY_R)
	expect(Grid.rotation(Grid.facility_at(scene.sim.layout, Vector2i(2, 14))) == 1, "选中已铺好的墙体后可用 R 旋转")
	press_key(KEY_BACKSPACE)
	expect(Grid.facilities(scene.sim.layout, "wall").size() == 5 and not Grid.blocked(scene.sim.layout, Vector2i(2, 14)), "已建的隔墙可选中收起并立即恢复通行")
	press_key(KEY_ESCAPE)
	expect(not catalog.visible and scene.world.bottom_inset == 0, "关闭目录后全场景视野恢复")

func check_build_tools(scene) -> void:
	expect(scene.ui.move.visible and scene.ui.rotate.visible and scene.ui.store.visible and scene.ui.action_bar.global_position.y < scene.ui.build_catalog.global_position.y and scene.ui.rotate.text.is_empty() and scene.ui.rotate.tooltip_text.contains("旋转"), "目录打开时右下角图标停在目录上方并显示悬停说明")

func check_catalog_search(catalog, item_id: String) -> void:
	catalog.search.text = "隔墙"
	catalog.search.text_changed.emit("隔墙")
	expect(catalog.tiles.has("@wall") and not catalog.tiles.has(item_id), "搜索按名称筛选当前目录")
	catalog.search.text = ""
	catalog.search.text_changed.emit("")

func verify_major_notice(scene) -> void:
	var checkpoint = scene.sim.export_state()
	expect(not scene.ui.major_event.visible, "无重大事件的夜晚隐藏事件按钮")
	scene.sim.day = 6
	scene._refresh_all()
	await create_timer(.21).timeout
	expect(scene.ui.major_event.visible and scene.ui.major_event.text.contains("重大事件") and scene.ui.major_event.scale.x > 1.0, "第五天夜晚右侧重大事件有可见呼吸动效")
	click_control(scene.ui.major_event)
	await process_frame
	var art = scene.modal_layer.find_child("MajorEventArtwork", true, false)
	var confirm = scene.modal_layer.find_child("ConfirmMajorEvent", true, false)
	var labels = scene.modal_layer.find_children("*", "Label", true, false)
	var reward = int(scene.sim.chapter.events.food_festival.notice.grant.reputation)
	expect(scene.modal_kind == "major_event" and art.texture.get_size() == Vector2(960, 540) and confirm.text.contains("%d 声望" % reward), "美食节公告显示正式海报和领取按钮")
	expect(labels.any(func(label): return label.text.contains("+15%") and label.text.contains("+30%")) and labels.any(func(label): return label.text.contains("每天各获 3 闪星")) and not labels.any(func(label): return label.text.contains("新增不足")), "海报下方显示客流规则和三天任务")
	await shot("major_event_festival")
	var reputation = scene.sim.reputation
	scene._dismiss_modal()
	expect(scene.sim.reputation == reputation, "关闭公告不会领取确认奖励")
	scene._show_major_event()
	await process_frame
	click_control(scene.modal_layer.find_child("ConfirmMajorEvent", true, false))
	expect(scene.modal_layer == null and scene.sim.reputation == reputation + reward and scene.sim.major_event_claims.has("food_festival"), "点击确认后领取配置声望并留下存档记录")
	scene._show_major_event()
	expect(scene.modal_layer.find_child("ConfirmMajorEvent", true, false).text == "确定", "再次查看已领取公告不再显示领取按钮")
	scene._dismiss_modal()
	for item in [[11, "地痞出没"], [13, "团餐预约"], [15, "食品安全检查"], [16, "恶劣天气"], [24, "街区品鉴"]]:
		scene.sim.day = item[0]
		scene._refresh_all()
		scene._show_major_event()
		var artwork = scene.modal_layer.find_child("MajorEventArtwork", true, false)
		expect(scene.major_notice.name == item[1] and artwork != null and (not artwork is TextureRect or artwork.texture != null), "加载事件新闻或海报 " + str(item[1]))
		scene._dismiss_modal()
	scene.sim.restore_state(checkpoint)
	scene._refresh_all()

func execute() -> void:
	Store.write_checkpoint({"completed": []}, Progress.path(true))
	Store.write_checkpoint(Sim.new().export_state(), Store.default_path("street_corner", true))
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	for i in range(5): await process_frame
	title.get_node("Menu/CanyonHub/Places/tavern").pressed.emit()
	await title.get_node("Menu/CanyonHub").at_door
	var start_bounds = title.start_button.get_global_rect()
	expect(title.menu.visible and start_bounds.position.x >= 0 and start_bounds.end.x <= title.page.size.x and start_bounds.end.y <= title.page.size.y and title.register_enabled, "主界面章节入口完整显示在窗口内")
	expect(title.chapter_buttons.market_lane.status.visible and title.chapter_buttons.market_lane.status.glyph == "lock", "主界面用锁图标表达第二章尚未解锁")
	await shot("title")
	title.queue_free()
	await process_frame
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in range(5): await process_frame
	scene.keys.reset()
	scene.guide.skip()
	scene._restart_run(123456)
	for i in range(5): await process_frame
	expect(scene.theme.default_font.has_char("餐".unicode_at(0)),"PC字体包含中文")
	expect(scene.world.get_global_rect().size==scene.size,"地图覆盖视口")
	expect(scene.ui.rent_label.text == "$%d" % int(scene.sim.next_rent().amount) and scene.ui.rent_days.text == "6天", "房租和天数图标组完整显示")
	expect(scene.ui.badge.phase=="NIGHT" and scene.ui.income_label.text=="0$","夜晚圆标和收入位置正确")
	expect(scene.ui.gold_label.text=="600$" and scene.ui.rep_label.text=="0","金币与声望余额分开显示且夜晚金币不归零")
	expect(scene.ui.star_label.text.contains("0") and scene.world.sun_light.shadow_enabled and scene.world.shadow_geometry.get_child_count()>10,"闪星资源和墙/家具实时遮挡灯光已显示")
	for actor in scene.world.actors.values(): actor.hide()
	await RenderingServer.frame_post_draw
	var shadow_pixels = root.get_texture().get_image().get_data()
	scene.world.sun_light.shadow_enabled = false
	await RenderingServer.frame_post_draw
	var unshadowed_pixels = root.get_texture().get_image().get_data()
	expect(shadow_pixels != unshadowed_pixels,"真实遮挡体在画面产生可检测的灯光阴影")
	scene.world.sun_light.shadow_enabled = true
	for actor in scene.world.actors.values(): actor.show()
	var sun_cell = (scene.world.sun_light.position-scene.world._origin())/scene.world._unit()
	var road_center = scene.world.screen_point(Vector2(-3.1,7.8))
	expect(Rect2(Vector2.ZERO, scene.world.size).has_point(road_center), "默认视野能看见门外的井台和石径")
	await shot("street")
	scene.world.camera_pan = Vector2(-220,110)
	scene.world._update_lighting()
	expect(((scene.world.sun_light.position-scene.world._origin())/scene.world._unit()).is_equal_approx(sun_cell) and scene.world.district_3d.light.shadow_enabled and scene.world.district_3d.district.get_node("workshop").is_visible_in_tree(),"移动视野时太阳固定在世界坐标，峡谷使用同一套实体建筑与光源")
	for i in range(2): await process_frame
	await shot("neighborhood")
	scene.world.focus_restaurant()
	expect(scene.world.actors.values().all(func(actor): return actor.scale==Vector2.ONE),"角色文字处于未缩放的世界坐标")
	var preview_id = scene.world.actors.keys().filter(func(id): return str(id).begins_with("preview_"))[0]
	scene.world._inspect_actor(scene.world.actors[preview_id].position)
	expect(scene.ui.info_panel.visible and scene.ui.info_title.text.contains("预备中"),"夜晚角色占位也能打开对应角色详情")
	scene.ui.info_panel.hide()
	scene.world._inspect_actor(scene.world.actors[preview_id].position - Vector2(0,22*scene.world.actors[preview_id].scale.y))
	expect(scene.ui.info_panel.visible and scene.ui.info_title.text.contains("预备中"),"点击像素角色上半身也能查看对应详情")
	scene.ui.info_panel.hide()
	scene.inspected = {}
	await RenderingServer.frame_post_draw
	var waiter = scene.world.actors.preview_waiter_0
	var waiter_cell = Vector2i(12, 9)
	await drag_on_board(scene.world, waiter.position, scene.world.screen_point(Vector2(waiter_cell)), false)
	expect(Grid.vec(scene.sim.layout.waiter_starts[0]) == Vector2(3, 9), "短按拖过空格时保持服务员站位")
	var waiter_drag = await drag_on_board(scene.world, waiter.position, scene.world.screen_point(Vector2(waiter_cell)))
	await process_frame
	await RenderingServer.frame_post_draw
	var waiter_moved = Grid.vec(scene.sim.layout.waiter_starts[0]) == Vector2(waiter_cell) and waiter.position.is_equal_approx(scene.world.screen_point(Vector2(waiter_cell)))
	expect(waiter_drag.picked == "preview_waiter_0" and waiter_drag.armed and waiter_moved, "鼠标拖动服务员后，夜晚角色显示在新站位")
	var chef = scene.world.actors.preview_chef_0
	click(scene.world, chef.position)
	await process_frame
	expect(scene.ui.move.visible and not scene.ui.rotate.visible, "夜晚员工详情提供移动按钮")
	click_control(scene.ui.move)
	click(scene.world, scene.world.screen_point(Vector2(4, 4)))
	expect(scene.sim.layout.chef_starts[0] == [4, 4], "使用移动按钮后可以点击空格安排厨师站位")
	scene._move_facility("preview_waiter_0", Vector2i(3, 9))
	scene._move_facility("preview_chef_0", Vector2i(3, 4))
	var table = Grid.find(scene.sim.layout, "table_1")
	click(scene.world, scene.world.screen_point(Grid.vec(table.pos)))
	await process_frame
	click_control(scene.ui.rotate)
	expect(scene.ui.rotate.visible and Grid.rotation(table) == 1 and Grid.interaction(table) == Grid.vec(table.pos) + Vector2.LEFT, "在餐桌详情点击旋转按钮后，操作格跟随座位转动")
	for i in range(3):
		if Grid.rotation(table) == 0: break
		scene._rotate_selection()
	var stove = Grid.find(scene.sim.layout, "stove_1")
	click(scene.world, scene.world.screen_point(Grid.vec(stove.pos)))
	var key = InputEventKey.new()
	key.keycode = KEY_R
	key.physical_keycode = KEY_R
	key.pressed = true
	root.push_input(key, true)
	expect(Grid.rotation(stove) == 1 and Grid.interaction(stove) == Vector2(1, 2), "选中灶台后可用 R 键旋转")
	for i in range(3):
		if Grid.rotation(stove) == 0: break
		scene._rotate_selection()
	scene.ui.info_panel.hide()
	scene.inspected = {}
	scene._show_settings()
	expect(scene.modal_kind=="settings","右上设置入口打开居中菜单")
	await verify_shortcuts(scene)
	await verify_major_notice(scene)
	await shot("night")
	var purchase_marker = scene.world.plot_buttons.purchase_annex.button
	scene.world._sync_plot_buttons()
	var marker_origin = purchase_marker.position
	scene.world.camera_pan += Vector2(23, 11)
	scene.world._sync_plot_buttons()
	expect(purchase_marker.position.is_equal_approx(marker_origin + Vector2(23, 11)), "地块按钮跟随地图而非 HUD，镜头平移位置正确")
	scene.world.focus_restaurant()
	scene.world._sync_plot_buttons()
	var inactive_gallery = scene.world.plot_buttons.trophy_gallery.button
	click_control(inactive_gallery)
	scene._inspect("plot", "trophy_gallery")
	expect(not inactive_gallery.visible and inactive_gallery.disabled and inactive_gallery.mouse_filter == Control.MOUSE_FILTER_IGNORE and scene.world.plot_buttons.trophy_gallery.ready == 0 and scene.modal_kind.is_empty(), "后续野地隐藏地块按钮，点击不会进入扩建确认")
	click_control(purchase_marker)
	await process_frame
	expect(scene.modal_kind == "plot_unlock" and scene.modal_layer.find_child("ConfirmLandUnlock", true, false).disabled, "鼠标点击锁定采购区上的按钮，只查看该地块且显示开放条件")
	await shot("locked_land")
	scene._dismiss_modal()
	var before_purchase = scene.sim.export_state()
	scene.sim.day = 3
	scene.sim.stars = 1
	scene.sim.unlock_land_plot("purchase_annex")
	scene._refresh_all()
	click(scene.world,scene.world.screen_point(Grid.vec(Grid.find(scene.sim.layout,"slot").pos)))
	var hover=InputEventMouseMotion.new()
	hover.position=scene.world.screen_point(Grid.vec(Grid.find(scene.sim.layout,"slot").pos))
	scene.world._gui_input(hover)
	expect(scene.world.mouse_default_cursor_shape==Control.CURSOR_POINTING_HAND,"场景物块悬停可识别点击")
	expect(Grid.find(scene.sim.layout,"slot").name=="采购处","场景采购物块已改名采购处")
	expect(scene.ui.slot_panel.visible,"采购处展示右侧简介")
	expect(not scene.ui.has("enter_trophies"), "采购处仅供金币采购")
	click(scene.world, scene.world.screen_point(Vector2(scene.sim.trophy_shop_cell())))
	expect(scene.modal_layer == null and not scene.sim.trophy_shop_unlocked(), "展廊未解锁时商店格不可访问")
	scene.ui.enter_shop.pressed.emit()
	expect(scene.modal_kind=="purchase","采购页面经右侧入口打开")
	var purchase_box = scene.modal_layer.find_children("*","PanelContainer",true,false)[0].get_global_rect()
	expect(purchase_box.position.x>=0 and purchase_box.position.y>=0 and purchase_box.end.x<=scene.size.x and purchase_box.end.y<=scene.size.y,"采购弹窗完整落在窗口内")
	var buttons = scene.modal_layer.find_children("*","Button",true,false).filter(func(b): return b.text.begins_with("购买  "))
	expect(buttons.size()==3,"三件商品纵向排列且分别有购买按钮")
	var recipe_stat = scene.modal_layer.find_children("*","Label",true,false).filter(func(label): return label.text.contains("基础价值") and label.text.contains("当前品质") and label.text.contains("制作"))
	expect(recipe_stat.size()==1,"菜品卡显示价值、品质、制作速度与产量")
	var buff_tiers = scene.modal_layer.find_children("*", "Label", true, false).filter(func(label): return label.text.ends_with("★"))
	expect(buff_tiers.size() == 2, "两格增益均标注星级")
	expect(scene._guest_effect(scene.sim.guest_defs.blogger).contains("金币倍率") and scene._guest_effect(scene.sim.guest_defs.elder).contains("用餐时间") and scene._guest_effect(scene.sim.guest_defs.thug).contains("等餐耐心"),"稀有与特别效果在信息窗可解释")
	if scene.modal_frame.motion.is_running(): await scene.modal_frame.motion.finished
	var counter_cell := Grid.vec(Grid.find(scene.sim.layout, "slot").pos)
	expect(scene.world.feature_active and scene.world.feature_cell == counter_cell, "采购页对准扩建得到的采购处")
	var district = scene.world.district_3d
	expect(district.wings.has("purchase_annex") and district.fixture_models.has("slot"), "采购小厅及真实设施已建成")
	await shot("purchase")
	var counter_point: Vector2 = scene.world.screen_point(counter_cell)
	expect(Rect2(Vector2.ZERO, root.size).has_point(counter_point) and not scene.modal_frame.panel.get_global_rect().has_point(counter_point), "采购处在交易窗旁可见")
	var money = scene.sim.gold
	scene._buy(0)
	expect(scene.modal_kind=="buy","新菜购买需要确认")
	scene._dismiss_modal()
	expect(scene.sim.gold==money,"取消购买不扣金币")
	scene.sim.restore_state(before_purchase)
	scene._refresh_all()
	click(scene.world,scene.world.screen_point(Grid.vec(Grid.find(scene.sim.layout,"cashier").pos)))
	expect(scene.sim.attributes.chefs==2 and scene.sim.attributes.waiters==4 and scene.sim.attributes.tables==8,"初始员工与客桌符合新布局")
	expect(scene.modal_kind=="cashier_front","点击收银台先打开功能入口")
	scene._show_cashier_page()
	expect(scene.modal_kind=="cashier","从收银台进入招聘与改造页面")
	var gate_labels = scene.modal_layer.find_children("*", "Label", true, false).map(func(label): return label.text)
	expect(gate_labels.any(func(label): return label.contains("桌位")) and gate_labels.any(func(label): return label.contains("服务员")) and "厨师 · 第 2 天解锁" in gate_labels and not gate_labels.any(func(label): return label.contains("菜单上架槽") or label.contains("排队容量")), "第一晚只显示桌位、服务员和下一项厨师预告")
	var cashier_box = scene.modal_layer.find_children("*","PanelContainer",true,false)[0].get_global_rect()
	expect(cashier_box.position.x>=0 and cashier_box.position.y>=0 and cashier_box.end.x<=scene.size.x and cashier_box.end.y<=scene.size.y,"招聘与改造页在当前窗口完整可见")
	var price_buttons = scene.modal_layer.find_children("*", "Button", true, false).filter(func(button): return button.text.contains("声望 +"))
	expect(price_buttons.size() == 2 and price_buttons.all(func(button): return button.disabled), "升级按钮展示声望与金币报价，并禁用买不起的项目")
	await shot("upgrades")
	scene.sim.reputation=400
	scene.sim.day = 3
	scene._show_cashier_page()
	gate_labels = scene.modal_layer.find_children("*", "Label", true, false).map(func(label): return label.text)
	expect(gate_labels.any(func(label): return label.begins_with("厨师与灶台")) and "菜单上架槽 · 第 4 天解锁" in gate_labels and not gate_labels.any(func(label): return label.contains("奖杯展示位") or label.contains("排队容量")), "第三天开放厨师，页面只多预告下一项菜单槽")
	scene.sim.day = 8
	var before_capacity_gold = scene.sim.gold
	var capacity_price = scene.sim.upgrade_gold_cost("queue_capacity")
	scene._upgrade("queue_capacity")
	expect(scene.sim.attributes.queue_capacity==224 and scene.sim.gold == before_capacity_gold - capacity_price,"声望购买队列容量+128")
	scene.sim.day = 1
	scene._upgrade("tables")
	expect(not scene.world.editing and Grid.placed(Grid.find(scene.sim.layout,"table_9")) and scene.sim.opening_errors().is_empty(),"新桌子自动摆放合法空位，保留招聘页")
	scene._dismiss_modal()
	var initial_pan: Vector2 = scene.world.camera_pan
	var right = InputEventMouseButton.new()
	right.button_index=MOUSE_BUTTON_RIGHT
	right.pressed=true
	right.position=Vector2(800,500)
	scene.world._gui_input(right)
	var motion = InputEventMouseMotion.new()
	motion.relative=Vector2(20,16)
	motion.button_mask=MOUSE_BUTTON_MASK_RIGHT
	motion.position=Vector2(820,516)
	scene.world._gui_input(motion)
	right.pressed=false
	scene.world._gui_input(right)
	expect(scene.world.camera_pan.is_equal_approx(initial_pan + Vector2(20,16)),"按住右键拖动场景")
	right.pressed=true
	scene.world._gui_input(right)
	var released_elsewhere=InputEventMouseMotion.new()
	released_elsewhere.position=Vector2(840,530)
	released_elsewhere.relative=Vector2(20,14)
	released_elsewhere.button_mask=0
	scene.world._gui_input(released_elsewhere)
	expect(scene.world.camera_pan.is_equal_approx(initial_pan + Vector2(20,16)) and not scene.world.dragging_camera,"右键在浮层外释放后不再卡住镜头")
	scene.world.focus_restaurant()
	scene.ui.open.pressed.emit()
	expect(scene.sim.phase=="DAY" and not scene.ui.open.visible,"开店并隐藏夜晚按钮")
	scene._toggle_fast()
	expect(scene.fast_forward and scene.ui.fast.text=="8×","快进按钮显示当前8倍率")
	scene._toggle_fast()
	expect(not scene.fast_forward and scene.ui.fast.text=="1×","恢复正常速度后按钮显示1倍率")
	scene._toggle_fast()
	scene._toggle_pause()
	var frozen=scene.sim.tick
	for i in range(3): await process_frame
	expect(scene.sim.tick==frozen,"暂停冻结模拟时间")
	scene.sim.paused=false
	while scene.sim.tick<900: scene.sim.step()
	for i in range(4): await process_frame
	expect(not scene.ui.has("live_stats"),"白天HUD不展示客流实时汇总")
	if not scene.sim.active_customers.is_empty():
		var current_id = str(scene.sim.active_customers.keys()[0])
		scene._inspect("customer",current_id)
		expect(scene.ui.info_panel.visible and scene.ui.guest_profile.visible and not scene.ui.guest_profile.phase_label.text.is_empty(),"点击客人展示新版经营状态卡")
		scene.ui.info_panel.hide()
	await shot("day")
	var rare_visits = scene.sim.arrival_plan.filter(func(p): return scene.sim.guest_defs[p.type].rarity == "rare")
	if not rare_visits.is_empty():
		while scene.sim.phase=="DAY" and scene.sim.tick<int(rare_visits[0].tick): scene.sim.step()
		scene._inspect("customer",str(rare_visits[0].id))
		expect(scene.ui.guest_profile.category.text.contains("稀有客人") and scene.ui.info_panel.visible,"稀有客详情弹窗实际展示特殊效果")
		scene.ui.info_panel.hide()
	while scene.sim.phase=="DAY" and scene.sim.tick<scene.sim.day_ticks: scene.sim.step()
	for i in range(3): await process_frame
	expect(scene.sim.phase=="DAY" and scene.ui.cleanup.visible,"120秒后提示清场中而非强制闭店")
	await shot("cleanup")
	scene.sim.paused = false
	var closing_steps = 0
	while scene.sim.phase=="DAY" and closing_steps<10000:
		scene.sim.step()
		closing_steps += 1
	expect(scene.sim.phase=="REPORT","白天在合理步数内完成清场")
	if scene.sim.phase!="REPORT":
		print("UI closure state: paused=",scene.sim.paused," tick=",scene.sim.tick," active=",scene.sim.active_customers.size()," cursor=",scene.sim.arrival_cursor,"/",scene.sim.arrival_plan.size())
		quit(1)
		return
	for i in range(6): await process_frame
	expect(scene.modal_kind=="report" and scene.sim.last_report.arrived==37,"清场后自动复盘")
	var report_box = scene.modal_layer.find_children("*","PanelContainer",true,false)[0].get_global_rect()
	expect(report_box.position.x>=0 and report_box.position.y>=0 and report_box.end.x<=scene.size.x and report_box.end.y<=scene.size.y,"复盘弹窗完整落在窗口内")
	await shot("report")
	var locate = scene.modal_layer.find_children("*", "Button", true, false).filter(func(button): return button.text.begins_with("在餐厅定位"))
	expect(locate.size() == 1, "复盘提供一个场景定位入口")
	if locate.size() == 1:
		locate[0].pressed.emit()
		await process_frame
		expect(scene.ui.diagnostic_card.visible and not scene.world._diagnostic_cells().is_empty(), "原生场景显示复盘定位卡与设施高亮")
		await shot("diagnosis")
		scene.ui.diagnostic_button.pressed.emit()
	scene._confirm_restart()
	scene._dismiss_modal()
	expect(scene.modal_kind=="report","取消重新开局返回复盘")
	scene._continue_night()
	expect(scene.sim.phase=="NIGHT" and scene.sim.day==2,"复盘后进入下一晚")
	expect(scene.service_feedback.amounts.get(scene.ui.gold_label) == scene.sim.gold and scene.service_feedback.amounts.get(scene.ui.income_label) == 0 and scene.sim.gold>600,"进入下一晚仍显示真实金币余额和重新开始的今日收入")
	scene.sim.day = 5
	scene.sim.stars = 12
	scene._refresh_all()
	scene.world._sync_plot_buttons()
	click_control(purchase_marker)
	await process_frame
	var purchase_confirm = scene.modal_layer.find_child("ConfirmLandUnlock", true, false)
	expect(not purchase_confirm.disabled and scene.sim.stars == 12, "点场景按钮只打开确认，闪星尚未扣除")
	await shot("plot_confirm")
	scene._dismiss_modal()
	expect(scene.sim.stars == 12 and "purchase_annex" not in scene.sim.layout.unlocked_plots, "关闭确认弹窗后保持余额和锁定状态")
	scene.world._sync_plot_buttons()
	click_control(purchase_marker)
	await RenderingServer.frame_post_draw
	var confirm = scene.modal_layer.find_child("ConfirmLandUnlock", true, false)
	click_control(confirm)
	for i in range(2): await process_frame
	expect(scene.sim.stars == 11 and not purchase_marker.visible and "purchase_annex" in scene.sim.layout.unlocked_plots, "确认后扣除一闪星，原地按钮消失")
	var gallery = scene.world.plot_buttons.trophy_gallery.button
	expect(not gallery.disabled and scene.world.plot_buttons.east_dining.button.disabled, "解锁后只启用下一个地块按钮")
	click_control(gallery)
	await process_frame
	var gallery_confirm = scene.modal_layer.find_child("ConfirmLandUnlock", true, false)
	click_control(gallery_confirm)
	for i in range(2): await process_frame
	expect("trophy_gallery" in scene.sim.layout.unlocked_plots and scene.sim.owned_relics.has("bronze_clock"), "解锁前一个地块后可继续确认展廊并领取铜摆钟")
	for i in range(3): await process_frame
	click(scene.world,scene.world.screen_point(Vector2(26,10)))
	expect(scene.ui.info_panel.visible and scene.ui.info_title.text.contains("铜摆钟"),"点击地块赠送的奖杯可查看详情")
	scene.ui.info_panel.hide()
	await shot("trophy_display")
	await process_frame
	click_at(scene.world.screen_point(Vector2(scene.sim.trophy_shop_cell())))
	expect(scene.modal_kind == "trophy_shop" and scene.sim.trophy_shop.size() == 3, "展廊内的独立商店块打开三格奖杯商店")
	var trophy_tiers = scene.modal_layer.find_children("*", "Label", true, false).filter(func(label): return label.text.contains("★\n"))
	expect(trophy_tiers.size() == 3, "奖杯名称旁保留价格等级")
	await shot("trophy_shop")
	scene._close_modal()
	click_at(scene.world._trophy_shop_sign(scene.sim.trophy_shop_cell(), scene.world._unit()).get_center())
	expect(scene.modal_kind == "trophy_shop", "地图上的商店招牌也可点击")
	var before_stars = scene.sim.stars
	scene._buy_trophy(0)
	scene._close_modal()
	click_control(scene.ui.trophy_bag)
	expect(scene.modal_kind == "trophy_bag" and scene.sim.stars < before_stars and scene.sim.owned_relics.size() == 2, "解锁后的商店正常出售奖杯")
	scene._close_modal()
	if scene.world.feature_motion != null and scene.world.feature_motion.is_running():
		await scene.world.feature_motion.finished
	await drag_on_board(scene.world, scene.world.screen_point(Vector2(7, 8)), scene.world.screen_point(Vector2(4, 8)))
	var first_pair = Grid.find(scene.sim.layout, "table_1")
	expect(Grid.table_size(first_pair) == 2 and scene.ui.toast_label.text.contains("合成双人桌"), "原生鼠标长按拖桌可合成双人桌")
	scene.ui.info_panel.hide()
	await drag_on_board(scene.world, scene.world.screen_point(Vector2(4, 10)), scene.world.screen_point(Vector2(10, 8)))
	var second_pair = Grid.find(scene.sim.layout, "table_3")
	expect(Grid.table_size(second_pair) == 2, "第二组单人桌也可合成双人桌")
	scene.ui.info_panel.hide()
	var block_front = scene.sim.place_wall(Vector2i(4, 7))
	var block_side = scene.sim.place_wall(Vector2i(3, 8))
	scene._refresh_all()
	await drag_on_board(scene.world, scene.world.screen_point(Vector2(10, 8)), scene.world.screen_point(Vector2(4, 8)))
	expect(Grid.vec(Grid.find(scene.sim.layout, "table_3").pos) == Vector2(10, 8) and Grid.table_size(Grid.find(scene.sim.layout, "table_1")) == 2 and scene.ui.toast_label.text.contains("空间不足"), "四人桌空间不足会弹提醒并退回原位")
	scene.sim.store_facility(block_front.facility_id)
	scene.sim.store_facility(block_side.facility_id)
	scene._refresh_all()
	await process_frame
	var moved_pair = await drag_on_board(scene.world, scene.world.screen_point(Vector2(4, 8)), scene.world.screen_point(Vector2(5, 11)))
	var moved_position = Grid.vec(Grid.find(scene.sim.layout, "table_1").pos)
	scene.ui.info_panel.hide()
	await process_frame
	var merged_pair = await drag_on_board(scene.world, scene.world.screen_point(Vector2(10, 8)), scene.world.screen_point(Vector2(5, 11)))
	var quad = Grid.find(scene.sim.layout, "table_1")
	expect(moved_pair.armed and moved_position == Vector2(5, 11) and merged_pair.armed and Grid.table_size(quad) == 4 and Grid.footprint(quad).size == Vector2i(2, 2), "在开阔区域拖放两张双人桌可合成四人桌")
	click(scene.world, scene.world.screen_point(Vector2(6, 12)))
	expect(scene.ui.info_panel.visible and scene.ui.info_title.text == "四人桌", "点击四人桌非锚点格也可查看详情")
	scene.ui.info_panel.hide()
	await process_frame
	await shot("party_table")
	await verify_building(scene)
	scene._open_day()
	scene.sim.arrival_plan = [{"id":1,"type":"student","tick":1,"party_id":1,"party_size":2}, {"id":2,"type":"commuter","tick":1,"party_id":1,"party_size":2}]
	scene.sim.paused = false
	for i in range(30): scene.sim.step()
	scene.world._process(0)
	await process_frame
	var remarks = scene.world.find_children("*", "Label", true, false)
	expect(remarks.any(func(label): return label.text.contains("没有双人桌")) and scene.sim.stats.refused_no_table == 2, "缺匹配餐桌的客人组在门口显示抱怨气泡")
	await shot("party_refusal")
	var file=FileAccess.open("res://.local/street_ui_%dx%d_results.json" % [root.size.x, root.size.y],FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"viewport":[root.size.x,root.size.y]},"\t"))
	file.close()
	print("STREET UI RESULT: ",passed," passed / ",failed," failed")
	quit(1 if failed>0 else 0)
