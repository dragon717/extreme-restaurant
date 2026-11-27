extends SceneTree

const Store = preload("res://scripts/core/save_store.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Roster = preload("res://scripts/core/crew_roster.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(result: bool, message: String) -> void:
	checks += 1
	if result: return
	failures += 1
	push_error(message)

func wheel(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.factor = 3.
	root.push_input(event,true)

func snap(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if "--capture-door" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("res://.local/entry-"+label+".png")

func click_page(title, control: String, touch := false) -> void:
	await process_frame
	await process_frame
	var stage = title.get_node("Menu/CanyonHub").model
	var button: Control = title.register.get_node("%"+control)
	var px := button.get_global_rect().get_center()
	var at: Vector2 = stage.camera.unproject_position(stage.board.to_global(stage.board.point_for_pixel(px)))
	var press: InputEvent = InputEventScreenTouch.new() if touch else InputEventMouseButton.new()
	if not touch:
		press.button_index=MOUSE_BUTTON_LEFT
		press.global_position=at
	press.position=at
	press.pressed=true
	root.push_input(press,true)
	await process_frame
	press.pressed=false
	root.push_input(press,true)

func visit(title) -> void:
	title.get_node("Menu/CanyonHub/Places/tavern").pressed.emit()
	await create_timer(1.7).timeout

func run() -> void:
	if not "--ui-test" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		quit(1)
		return
	var legacy := Store.default_path("street_corner",true)
	var old := Sim.new()
	old.day = 4
	old.gold = 841
	Store.write_checkpoint(old.export_state(),legacy)
	Store.write_checkpoint({"mode":"off","seen":{}},Store.default_path("tutorial_progress",true))
	var original := FileAccess.get_file_as_string(legacy)
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	var hub = title.get_node("Menu/CanyonHub")
	for i in range(18):
		if title.chapter_panel: break
		wheel(Vector2(root.size)*Vector2(.55,.72))
		await process_frame
	await create_timer(1.7).timeout
	check(title.chapter_panel and hub.door_preview and title.register_enabled,"通过窗口滚轮从峡谷进入门厅")
	if not hub.door_preview:
		quit(1)
		return
	var d = hub.model
	check(not title.has_node("Menu/Left") and not title.has_node("Menu/Scrim") and not title.has_node("Menu/Cover"),"首页不含旧平面菜单")
	check(d.board.texture==title.page.get_texture() and d.actor_planes.size()>=6,"营业簿是世界空间中的可交互网格，门口已有真实当班员工")
	var actor_ref: Sprite3D = d.actor_planes["preview_waiter_0"]
	var lamp_ref: OmniLight3D = d.lanterns[0]
	var lamp_pose := lamp_ref.global_transform
	var actor_pose := actor_ref.global_position
	var since: float = d.walkway_time
	var sky = hub.weather
	var focused: Control = title.page.gui_get_focus_owner()
	var tab := InputEventKey.new()
	tab.keycode=KEY_TAB
	tab.pressed=true
	root.push_input(tab,true)
	tab.pressed=false
	root.push_input(tab,true)
	check(title.page.gui_get_focus_owner()!=focused and title.page.gui_get_focus_owner()!=null,"键盘焦点在场景营业簿中导航")
	await click_page(title,"More",true)
	check(title.register.get_node("%Options").visible and title.register.get_node("%Quit").is_visible_in_tree(),"站务功能在营业簿内展开")
	await click_page(title,"Language")
	check(TranslationServer.get_locale().begins_with("en"),"营业簿可切换语言")
	await click_page(title,"Language")
	await click_page(title,"CrewGroups")
	check(title.crew_layer != null,"从营业簿进入阵容分组")
	title._leave_crew()
	await click_page(title,"ServiceTab")
	check(d.camera.projection==Camera3D.PROJECTION_PERSPECTIVE and absf(d.camera.global_basis.z.y)<.20,"镜头到达实际门口的平视位置")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = d.camera.unproject_position(d.doorway.to_global(Vector3(0,1.45,0)))
	click.global_position = click.position
	click.pressed = true
	root.push_input(click,true)
	click.pressed = false
	root.push_input(click,true)
	await create_timer(.60).timeout
	check(absf(d.left_hinge.rotation.y)<.02 and absf(d.right_hinge.rotation.y)<.02,"能把两扇门合上")
	await click_page(title,"More")
	await click_page(title,"DoorToggle")
	await click_page(title,"ServiceTab")
	await create_timer(.60).timeout
	check(d.left_hinge.rotation.y>.9 and d.right_hinge.rotation.y<-.9 and d.fixtures.is_visible_in_tree(),"两扇实体门向内开，保留原餐厅陈设")
	await snap("door")
	await click_page(title,"NewRun")
	var draft = title.crew_layer.find_child("OpeningDraft",true,false)
	check(draft!=null and draft.get_node("%Confirm").disabled,"已有存档也可进入新局预选")
	draft.cards["ovenhand"].pick.pressed.emit()
	check(draft.lineup.is_empty(),"预览英雄不会误锁定")
	draft.get_node("%Cancel").pressed.emit()
	check(FileAccess.get_file_as_string(legacy)==original and title.register_enabled,"取消选将回到门厅并保留存档")
	await click_page(title,"NewRun")
	check(title.crew_layer!=null,"取消之后仍可从实体营业簿重新选择新局")
	if title.crew_layer==null:
		quit(1)
		return
	draft = title.crew_layer.find_child("OpeningDraft",true,false)
	for id in Roster.STARTERS:
		draft.cards[id].pick.pressed.emit()
		draft.get_node("%Pick").pressed.emit()
	draft.cards["ovenhand"].pick.pressed.emit()
	draft.get_node("%Position").pressed.emit()
	check(draft.lineup.size()==5 and draft.lineup[draft._index("ovenhand")].role=="waiter" and not draft.get_node("%Confirm").disabled,"五位可上场，潘森可切换岗位")
	draft.get_node("%EditGroups").pressed.emit()
	draft.get_node("%GroupName").text = "门厅回归班组 %d" % Time.get_ticks_usec()
	draft.get_node("%SaveGroup").pressed.emit()
	var group_index: int = draft.get_node("%GroupList").selected
	draft.get_node("%Clear").pressed.emit()
	check(draft.lineup.is_empty() and not draft.get_node("%GroupDrawer").visible,"手动重选返回候选角色")
	draft.get_node("%EditGroups").pressed.emit()
	draft.get_node("%GroupList").select(group_index)
	draft.get_node("%GroupList").item_selected.emit(group_index)
	draft.get_node("%Apply").pressed.emit()
	check(draft.lineup.size()==5 and not draft.get_node("%GroupDrawer").visible and draft.lineup[draft._index("ovenhand")].role=="waiter","套用自定义分组后仍可修改名单")
	await snap("draft")
	draft.get_node("%Confirm").pressed.emit()
	await process_frame
	check(hub.marching and title.get_node("Menu/ArrivalControls").visible,"新局先从正门入场")
	title.get_node("Menu/ArrivalControls/Skip").pressed.emit()
	await create_timer(.30).timeout
	var game = title.game
	check(game!=null and game.sim.day==1 and game.sim.crew_lineup.size()==5 and not game.world.entering_canyon,"确认后开门入店，新局载入五位并恢复俯视")
	if game == null:
		quit(1)
		return
	var extra: String = game.save_path
	check(game.world.district_3d == d and game.world.district_3d.lanterns.has(lamp_ref) and lamp_ref.global_transform.is_equal_approx(lamp_pose),"开门抬镜保留同一场景、同一盏灯及其世界坐标")
	check(d.actor_planes["preview_waiter_0"] == actor_ref and d.walkway_time>since and d.weather_field.visible,"同一人物实例和环境时钟贯穿转场，天气保持世界空间渲染")
	check(game.world.weather==sky and sky.time>0.,"天气和环境音也沿用同一个时钟")
	check(actor_ref.global_position.distance_to(actor_pose)<.1,"员工脚点没有随抬镜滑动")
	check(extra!=legacy and FileAccess.file_exists(extra) and FileAccess.get_file_as_string(legacy)==original,"新局写入独立存档")
	game.guide.skip()
	check(game.world.district_3d.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and game.world.district_3d.camera.basis.z.y>.75,"营业镜头恢复上帝视角")
	await snap("service")
	game._show_settings()
	game.sim.gold=765
	game.modal_layer.find_child("SaveRun",true,false).pressed.emit()
	check(Store.read_checkpoint(extra).gold==765,"保存进度作用于本局档位")
	game._return_to_title()
	await process_frame
	await process_frame
	await visit(title)
	var idx: int = title.slots.find_custom(func(s): return s.path==legacy)
	check(idx>=0 and title.slots.size()>=2,"门厅可选择已有档位")
	for turn in range(title.slots.size()):
		if title.slot_index == idx: break
		await click_page(title,"Next")
	title.start_button.pressed.emit()
	await create_timer(2.45).timeout
	game=title.game
	check(game.save_path==legacy and game.sim.gold==841 and game.sim.day==4 and game.sim.crew_lineup.is_empty(),"旧档直接恢复原日期、余额和名单")
	game.guide.skip()
	var world=game.world
	world.set_roof_view(true)
	world.zoom_at(world.size*.5,100.)
	await create_timer(.5).timeout
	world.zoom_at(world.size*.5,1.15)
	check(world.entering_canyon,"经营中越过屋顶最大倍率可以继续进门")
	await create_timer(3.1).timeout
	check(not world.entering_canyon and not world.inspect_roof and is_equal_approx(world.zoom,1.) and title.game==game,"进店回到原局经营镜头")
	for id in ["supply","workshop","gallery","dock"]:
		world.signs.get_node(id).pressed.emit()
		check(game.modal_layer!=null,"场景招牌可以打开 "+id)
		game._close_modal()
	world.signs.get_node("freight").pressed.emit()
	check(game.modal_kind=="crew_setup","货运驿站可以打开当日排班")
	game._close_modal()
	game.sim.stars=99
	game.sim.day=22
	for plot in game.sim.layout.plots: game.sim.unlock_land_plot(plot.id)
	for pair in [["supply","purchase"],["workshop","decor_shop"],["gallery","trophy_shop"]]:
		world.signs.get_node(pair[0]).pressed.emit()
		check(game.modal_kind==pair[1],"解锁后场景招牌直达 "+pair[1])
		game._close_modal()
	game._open_day()
	var before_tick: int=game.sim.tick
	world.visit_threshold()
	await create_timer(.75).timeout
	check(game.sim.tick>before_tick and world.entering_canyon,"白天转场时订单和员工继续按营业时钟运行")
	title.queue_free()
	await create_timer(.6).timeout
	print("DOOR ENTRY %d passed / %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
