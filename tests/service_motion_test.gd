extends SceneTree

const Grid = preload("res://scripts/core/layout.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Routes = preload("res://scripts/core/service_routes.gd")
const Store = preload("res://scripts/core/save_store.gd")

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(description)

func _check_routes(simulation) -> void:
	var layout = simulation.layout
	var solid = Grid.solid_cells(layout)
	var routes = Routes.new()
	routes.prepare(layout, solid)
	var points = Grid.walkable_region(layout, solid).keys()
	var destinations = [Grid.interaction_cells(Grid.find(layout, "pass")), Grid.interaction_cells(Grid.find(layout, "order"))]
	destinations.append([Vector2i(Grid.vec(layout.exit))])
	destinations.append([Vector2i(-1,-1)])
	for i in range(0, points.size(), 17):
		var source = Vector2(points[i]) + Vector2(.09, .03)
		for targets in destinations:
			check(routes.approach(source, targets) == Grid.approach_cells(layout, source, targets, solid), "缓存寻路与原寻路完全相同")
		var goal = Vector2i(points[(i * 5 + 3) % points.size()])
		var original = Grid.path(layout, source, Vector2(goal), solid)
		var cached = routes.path(source, goal)
		check(cached == original and routes.distance(source, goal) == original.size(), "点到点距离与路线一致")
		if not cached.is_empty():
			cached.pop_front()
			check(routes.path(source, goal) == original, "移动消耗路径不会污染其他角色")

func _check_idle_waiter() -> void:
	var sim = Sim.new()
	sim.start_day()
	sim.arrival_plan.clear()
	var waiter = sim.staff[int(sim.attributes.chefs)]
	var origin = waiter.pos
	var chef_origin = sim.staff[0].pos
	while waiter.path.is_empty() and sim.tick < 240: sim.step()
	check(waiter.task.is_empty() and waiter.pos != origin and waiter.reason == "在餐厅走动", "白天空闲服务员会沿餐厅过道散步")
	check(sim.staff[0].pos == chef_origin and sim.staff[0].path.is_empty(), "空闲厨师留在厨房")
	for point in waiter.path:
		check(sim.idle_walk_aisles.has(Vector2i(point)), "散步路线避开厨房、墙和门")
	var seat = str(sim.seats.keys().front())
	var customer = sim._create_guest({"id": 1, "type": "normal"}, 1, 0, 0)
	customer.state = "READY"
	customer.seat = seat
	customer.seat_key = seat
	sim.seats[seat] = 1
	sim._dispatch_waiter(waiter)
	check(waiter.task.get("kind") == "ORDER" and int(customer.reserved_by) == int(waiter.id), "待点单客人立即打断闲逛")
	check(waiter.time.idle > 0 and waiter.time.move == 0, "散步期间统计为空闲")

func _check_staff_follow(game) -> void:
	var world = game.world
	world._sync_actors()
	for person in [game.sim.staff[0], game.sim.staff[int(game.sim.attributes.chefs)]]:
		var id = "s_%d" % int(person.id)
		var actor = world.actors[id]
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = actor.position + actor.click_rect().get_center()
		click.pressed = true
		world._gui_input(click)
		check(game.inspected.get("kind") == "staff" and game.inspected.get("id") == str(person.id) and game.ui.info_follow.visible, "营业中点员工可打开带镜头图标的资料")
		game.ui.info_follow.pressed.emit()
		world._advance_follow(.5)
		check(world.follow_actor_id == id and world.zoom > 1.4, "厨师与服务员都能放大跟随")
		var start: Vector2 = person.pos
		person.path = [start + Vector2.RIGHT]
		game.sim._move(person, 4.0)
		world.set_render_clock(game.sim.tick, .42, false)
		check(Vector2(world._follow_target(id)).is_equal_approx(start.lerp(person.pos, .42)), "镜头取员工当帧的插值位置")
		person.pos = start
		person.path.clear()
		person.position_tick = -1
		game._input(click)
		check(world.follow_actor_id.is_empty(), "点击场景解除员工跟随")
		world.focus_restaurant()
		world._sync_actors()
	game._clear_inspector()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	var simulation = Sim.new()
	_check_routes(simulation)
	simulation.day = 22
	simulation.stars = 100
	for plot in simulation.chapter.land_plots:
		check(simulation.unlock_land_plot(plot.id).ok, "可测试营业时的满扩建路网")
	_check_routes(simulation)
	_check_idle_waiter()

	var state = Sim.new().export_state()
	Store.write_checkpoint(state, Store.default_path("street_corner", true))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.guide.skip()
	game.set_process(false)
	root.focus_exited.disconnect(game._on_focus_lost)
	game._open_day()
	_check_staff_follow(game)
	var sim = game.sim
	var world = game.world
	var walker = sim.staff[0]
	var start: Vector2 = walker.pos
	walker.path = [start + Vector2.RIGHT]
	sim._move(walker, 4.0)
	var end: Vector2 = walker.pos
	world.set_render_clock(sim.tick, .25, false)
	world._sync_actors()
	check(world.actor_cells["s_1"].is_equal_approx(start.lerp(end, .25)), "同一逻辑步的第一帧落在连续轨迹上")
	world.set_render_clock(sim.tick, .75, false)
	world._sync_actors()
	check(world.actor_cells["s_1"].is_equal_approx(start.lerp(end, .75)) and walker.pos == end, "后续渲染帧继续移动，经营坐标仍使用固定步长")
	world.set_render_clock(sim.tick, .75, true)
	world._sync_actors()
	check(world.actors["s_1"].sprite.speed_scale == 0.0 and world.actor_cells["s_1"].is_equal_approx(start.lerp(end, .75)), "暂停时位置与步行动画一起冻结")
	var sprite = world.actors["s_1"].sprite
	for direction in ["walk","walk_side","walk_away"]:
		check(sprite.sprite_frames.has_animation(direction) and sprite.sprite_frames.get_frame_count(direction)>=4,"行程驱动的独立步态 "+direction)
	game.accumulator = .75 * float(sim.tick_ms) / 1000.0
	game._on_focus_lost()
	game._process(1.0 / 60.0)
	world._sync_actors()
	check(sim.paused and world.actor_cells["s_1"].is_equal_approx(start.lerp(end, .75)), "窗口失焦时暂停且保持当前插值位置")
	game._toggle_pause()
	game.fast_forward = true
	var previous_tick = sim.tick
	game._process(.7)
	check(sim.tick > previous_tick and sim.tick - previous_tick <= game.MAX_SIM_TICKS_PER_FRAME, "慢帧只执行有限数量的经营步")
	previous_tick = sim.tick
	game._process(1.0 / 60.0)
	check(sim.tick > previous_tick, "未处理的经营步在后续帧续跑")
	game.queue_free()
	await process_frame
	print("MOTION RESULT: %d passed / %d failed" % [passed, failed])
	quit(1 if failed else 0)
