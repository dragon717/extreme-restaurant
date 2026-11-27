extends SceneTree

const Sim = preload("res://scripts/core/simulation.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
const Crew = preload("res://scripts/core/crew_roster.gd")
var failed := 0
var passed := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, detail: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(detail)

func wheel(up: bool, point: Vector2, steps: float = 1.) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.factor = steps
	event.position = point
	return event

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if "--capture-canyon" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("res://.local/canyon-" + label + ".png")

func pixel_changes(a: Image,b: Image,area: Rect2i) -> int:
	var count := 0
	var clipped := area.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	for y in range(clipped.position.y,clipped.end.y):
		for x in range(clipped.position.x,clipped.end.x):
			var first := a.get_pixel(x,y)
			var other := b.get_pixel(x,y)
			if absf(first.g-other.g)+absf(first.b-other.b) > .08: count += 1
	return count

func snapshot(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func check_occlusion(world) -> void:
	var stage = world.district_3d
	var actor = world.actors["preview_chef_0"]
	var card: Sprite3D = stage.actor_planes["preview_chef_0"]
	var outline := card.get_node("ThroughWall") as Sprite3D
	var obstruction := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4,2.8,.24)
	var opaque := StandardMaterial3D.new()
	opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opaque.albedo_color = Color("353934")
	mesh.material = opaque
	obstruction.mesh = mesh
	obstruction.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.view.add_child(obstruction)
	obstruction.basis = stage.camera.basis
	obstruction.position = card.position + stage.camera.basis.z * 2 + stage.camera.basis.y * .54
	var at: Vector2 = stage.camera.unproject_position(card.position)
	var sample := Rect2i(Vector2i(at)-Vector2i(60,90),Vector2i(120,110))
	var behind := await snapshot(stage.view)
	outline.hide()
	var hidden := await snapshot(stage.view)
	check(pixel_changes(behind,hidden,sample) > 25, "室内员工被实体墙盖住时，深度测试会显示剪影")
	stage.sync_actor("preview_chef_0",actor,actor.world_cell,false)
	check(not outline.visible, "同一角色位于室外时遵守建筑遮挡")
	obstruction.hide()
	outline.show()
	var clear := await snapshot(stage.view)
	outline.hide()
	var natural := await snapshot(stage.view)
	check(pixel_changes(clear,natural,sample) < 12, "无遮挡时保持角色原色")
	obstruction.queue_free()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("需要图形窗口和 --ui-test")
		quit(1)
		return
	var sim := Sim.new()
	var crew := []
	for id in Crew.STARTERS: crew.append({"id":id,"role":Crew.PROFILES[id].roles[0]})
	sim.set_crew(crew)
	Store.write_checkpoint(sim.export_state(),Store.default_path("street_corner",true))
	Store.write_checkpoint({"mode":"off","seen":{}},Store.default_path("tutorial_progress",true))
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	var hub = title.get_node("Menu/CanyonHub")
	var court: Node = hub.model.view.find_child("gate_court",true,false)
	check(court != null and hub.model.roof_panels[0].visible, "峡谷首页绘制实物庭院和完整屋顶")
	for id in ["stone_bridge","timber_bridge","freight","gallery","workshop","dock"]:
		check(hub.model.district.has_node(id) or hub.get_node("Places").has_node(id), "地图建筑或入口 " + id)
	await capture("overview")
	hub.get_node("Places/dock").pressed.emit()
	check(title.place_layer != null,"河埠招牌可从场景直接打开")
	title._close_place()
	hub._gui_input(wheel(true,hub.size*.5,3.))
	hub._process(1.)
	check(hub.overview_mix < .90 and hub.overview_mix > 0, "标题页支持手动拉近")
	
	hub.get_node("Places/tavern").pressed.emit()
	await hub.at_door
	title.start_button.pressed.emit()
	await hub.door_crossed
	var game = title.game
	var world = game.world
	check(is_equal_approx(world.threshold_mix,1.) and world.entering_canyon,"入章镜头承接门口平视位置")
	await world.entry_finished
	game.guide.skip()
	game.set_process(false)
	world.set_process(false)
	world._process(.016)
	var stage = world.district_3d
	var shell: Node3D = stage.roof_panels[0]
	var shell_pose := shell.global_transform
	check(stage.wings.size() == 1 and not shell.visible and stage.rooms.visible, "第一个夜晚仅剖开小屋屋顶，保留实体外墙")
	check(Grid.occupied_bounds(game.sim.layout).size == Vector2i(12,14),"方格布局维持十二乘十四的经营区")
	check(world.actors["preview_waiter_1"].sprite.sprite_frames.resource_path.ends_with("Scuttler.tres"),"当班迅捷蟹使用专属四帧三动作")
	await capture("cutaway")
	await check_occlusion(world)
	var pin: Vector2 = world.screen_point(Vector2(5,7))
	for i in range(6):
		world._gui_input(wheel(false,pin,3))
		world._process(.18)
		var view_rect: Rect2 = stage.ground_view
		check(not Rect2(Grid.occupied_bounds(game.sim.layout)).encloses(view_rect), "第 %d 档可见餐厅外场景" % i)
		check(shell.global_transform.is_equal_approx(shell_pose),"缩放时屋顶与地基始终固定在同一位置")
	world._process(1)
	check(world.overview_mix > .99 and shell.visible and world.signs.visible,"滚轮拉远后看见完整屋顶、双桥和店铺招牌")
	world._gui_input(wheel(true,pin,3))
	world._process(.18)
	await capture("roof")
	var before: float = world._unit()
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.22
	pinch.position = pin
	world._gui_input(pinch)
	check(world._unit() > before,"macOS 双指捏合事件能从全景向餐厅连续放大")
	var gesture := InputEventPanGesture.new()
	gesture.delta = Vector2(0,1)
	gesture.position = pin
	before = world._unit()
	world._gui_input(gesture)
	world._process(1.)
	check(world._unit() < before,"触控板纵向双指滚动可拉远")
	world.zoom_at(pin,100)
	world._process(1.0)
	check(is_equal_approx(world.zoom,world._roof_zoom_limit()) and shell.visible and stage.exterior_amount == 1., "拉到最大仍显示与当前占地配套的大屋顶")
	await capture("largest-roof")
	game.ui.roof.pressed.emit()
	world._process(1.0)
	check(not shell.visible and not world.inspect_roof and stage.rooms.visible,"同一机位可手动查看室内，保留墙身和檐口")

	var entrance: Vector2 = Grid.vec(game.sim.layout.entrance)
	check(world.street.gate_route(1.,entrance).is_equal_approx(entrance) and world.street.threshold_alpha(world.street.gate_route(0,entrance)) == 0,"东岸进场与原经营入口连通")
	var crossing := false
	for sample in range(101):
		if world.street.gate_route(sample*.01,entrance).distance_to(Plan.landmark("wood_bridge")) < 2.5: crossing = true
	check(crossing,"来客从木桥桥面进入")
	game._open_day()
	var arrival := 250
	game.sim.arrival_plan = [{"id":1,"type":"normal","tick":arrival}]
	while game.sim.tick < arrival-22: game.sim.step()
	world._process(.1)
	check(world.actors.has("g_1") and game.sim.customers.is_empty(),"入场演出提前沿河道接近，经营时钟保持原计划")
	while game.sim.tick < arrival: game.sim.step()
	world._process(.1)
	check(game.sim.stats.arrived==1 and game.sim.customers.has(1),"一位客人只交接一次")
	while game.sim.phase == "DAY" and game.sim.tick < game.sim.day_ticks:
		game.sim.step()
		if not game.sim.active_customers.has(1): break
	world._process(.1)
	check(not world.actors.has("g_1") and game.sim.stats.completed == 1 and game.sim.invariant_errors().is_empty(),"离店后移除，同一订单正常结账")
	title.queue_free()
	await process_frame
	print("DISTRICT RESULT: %d passed / %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
