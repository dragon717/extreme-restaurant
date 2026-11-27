extends SceneTree

const Sim = preload("res://scripts/core/simulation.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Rules = preload("res://scripts/core/rules.gd")

var passed := 0
var failed := 0

func check(value: bool, description: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(description)

func _gallery(items: Array):
	var sim = Sim.new()
	sim.day = 22
	sim.stars = 100
	sim.gold = 10000
	sim.unlock_land_plot("purchase_annex")
	sim.unlock_land_plot("trophy_gallery")
	sim.attributes.relic_slots = 6
	for id in items:
		var fixture_id = "trophy_" + str(id)
		sim._add_trophy(id)
		var possible = sim.trophy_placement_cells(fixture_id)
		check(not possible.is_empty() and sim.move_facility(fixture_id, possible.keys().front()).ok, "测试奖杯可展示 " + str(id))
	return sim

func _seated(sim, id: int, seat: String, recipe := "starter_rice") -> Dictionary:
	var guest = sim._create_guest({"id": id, "type": "normal"}, 1, 0, 0)
	guest.seat = seat
	guest.seat_key = seat
	guest.recipe = recipe
	guest.state = "READY"
	guest.deadline = 600
	sim.seats[seat] = id
	return guest

func _complete_staff_task(sim, staff) -> void:
	sim._arrive_task(staff)
	if not staff.task.is_empty() and staff.task.stage == "ACTION":
		sim.tick = staff.task.done_tick
		sim._complete_action(staff)

func _check_service() -> void:
	var sim = _gallery(["double_book", "dual_tray", "sun_pen"])
	check(sim.start_day().ok and sim.waiter_order_limit == 2 and sim.waiter_food_limit == 2, "奖杯实际提高员工一次交单和取餐容量")
	var waiter = sim.staff[int(sim.attributes.chefs)]
	var visitors = []
	for i in range(1, 4): visitors.append(_seated(sim, i, "table_%d" % i))
	for i in range(2):
		sim._dispatch_waiter(waiter)
		check(waiter.task.kind == "ORDER", "有空位时服务员可以连续给两桌点单")
		sim._arrive_task(waiter)
		check(waiter.task.done_tick - sim.tick == Rules.ticks(float(sim.chapter.movement.interaction_seconds) * .72, sim.tick_ms), "快笔缩短真实点单交互")
		sim.tick = waiter.task.done_tick
		sim._complete_action(waiter)
	check(waiter.carry_orders == [1, 2], "两张订单留在同一位服务员手中")
	sim._dispatch_waiter(waiter)
	check(waiter.task.kind == "SUBMIT", "达到容量后前往交单口")
	_complete_staff_task(sim, waiter)
	check(waiter.carry_orders.is_empty() and sim.orders[1].submitted_tick == sim.orders[2].submitted_tick, "到交单口一次交出所有活跃订单")

	for id in [1, 2]:
		var order = sim.orders[id]
		order.supply = "AT_PASS"
		order.food = id
		sim.foods[id] = {"id": id, "recipe": order.recipe, "quality": 1.0, "location": "PASS", "location_id": "pass",
			"origin": "stove_1", "bound_order": id, "reserved_by": 0, "created_tick": sim.tick}
	sim.stats.produced = 2
	sim._dispatch_waiter(waiter)
	check(waiter.task.kind == "PICKUP" and waiter.task.food_ids == [1, 2], "同一趟可以在出餐口预留两份")
	var other = sim.staff[int(waiter.id)]
	sim._dispatch_waiter(other)
	check(other.task.get("kind", "") != "PICKUP" and sim.foods[1].reserved_by == waiter.id and sim.foods[2].reserved_by == waiter.id, "其他服务员不会重复取同一托盘的菜")
	var cancelled = sim.customers[int(sim.orders[1].customer)]
	sim._terminal(cancelled, "F")
	check(sim._task_valid(waiter), "托盘中一份退单时另一份继续配送")
	_complete_staff_task(sim, waiter)
	check(waiter.carry_food == [2] and sim.foods[1].location == "DISCARDED", "只取仍有效的菜，退单不残留预留")
	sim._dispatch_waiter(waiter)
	check(waiter.task.kind == "DELIVER", "可继续配送剩余菜品")
	_complete_staff_task(sim, waiter)
	check(sim.foods[2].location == "PLATE" and waiter.carry_food.is_empty() and sim.invariant_errors().is_empty(), "取多份、取消和上菜均守恒")

func _check_kitchen() -> void:
	var sim = _gallery(["feast_pot", "celestial_crystal", "jade_medal", "kiln_pot", "arc_shelf"])
	sim.relic_defs.feast_pot.chance = 1.0
	sim.relic_defs.celestial_crystal.chance = 1.0
	check(sim.start_day().ok and sim.stove_capacity == int(sim.chapter.movement.stove_capacity) + 3 and sim.pass_capacity == int(sim.chapter.movement.pass_capacity) + 6, "灶台和出餐口额外空间参与容量检查")
	for id in range(1, 6):
		var guest = _seated(sim, id, "table_%d" % id)
		guest.order = id
		guest.state = "FOOD"
		sim.orders[id] = {"id": id, "customer": id, "seat": guest.seat, "recipe": guest.recipe, "created_tick": 0, "submitted_tick": 0,
			"status": "ACTIVE", "supply": "NONE", "supply_owner": 0, "delivery_owner": 0, "food": 0}
	var chef = sim.staff[0]
	sim._dispatch_chef(chef)
	var stove = str(chef.task.stove_id)
	check(chef.task.batch == 5 and int(sim.stoves[stove].output_reserved) == 5, "增产按实际份数预留备餐位")
	_complete_staff_task(sim, chef)
	check(sim.stats.produced == 5 and chef.carry_food.size() == sim.chef_carry_limit and sim._active_foods("SHELF").size() == 1, "一锅实际出五份，多余的留在备餐处")
	check(sim.foods.values().all(func(food): return is_equal_approx(float(food.quality), 1.81)), "每锅统一应用全局品质与触发品质")
	check(sim.invariant_errors().is_empty(), "增产及品质触发后食品与容量守恒")

	var lower = _gallery(["twin_pot"])
	lower.relic_defs.twin_pot.chance = 1.0
	lower.owned_recipes.append("batch_snacks")
	lower.menu = ["batch_snacks"]
	lower.start_day()
	var guest = _seated(lower, 1, "table_1", "batch_snacks")
	guest.order = 1
	guest.state = "FOOD"
	lower.orders[1] = {"id":1,"customer":1,"seat":"table_1","recipe":"batch_snacks","created_tick":0,"submitted_tick":0,
		"status":"ACTIVE","supply":"NONE","supply_owner":0,"delivery_owner":0,"food":0}
	lower._dispatch_chef(lower.staff[0])
	check(lower.staff[0].task.batch == 4, "双份触发不会降低原本出四份的菜谱")

func _check_global_effects() -> void:
	var sim = _gallery(["spring_clock", "sky_clock", "dawn_glass", "silk_fan", "signature_list"])
	var mods = sim.effective_modifiers()
	check(is_equal_approx(float(mods.speed), .30) and sim.displayed_trophy_effects().size() == 4, "同类奖杯只采用最高品质，不重复叠加")
	sim.start_day()
	var normal = {"type": "normal"}
	var common = sim.chapter.common_guest_template
	check(is_equal_approx(sim._guest_seconds(normal, "order"), float(common.order_patience_seconds) * 1.30), "客人愿意多等一会儿再点单")
	check(is_equal_approx(sim._guest_seconds(normal, "choose"), float(common.choose_seconds) * .73) and is_equal_approx(sim.guest_eating_duration("normal"), float(common.eat_seconds) * .75), "选菜时间和用餐时间可独立缩短")

	var payout = _gallery(["fortune_spoon", "royal_coin", "orchid_crown", "moon_bell", "rainbow_invite"])
	payout.start_day()
	var paying = payout.meal_price("starter_rice", 1.0, payout.modifiers, payout.guest_defs.normal)
	check(paying == Rules.payment(24, 1.0, .14, 1.0, 7) and payout.modifiers.reputation == 5, "全体正常客人的固定金币、收入率和完餐声望生效")
	var free_guest = payout.guest_defs.values().filter(func(item): return item.get("payment_override", "") == "ZERO").front()
	check(payout.meal_price("starter_rice", 1.0, payout.modifiers, free_guest) == 0, "霸王餐保持零付款规则")
	check(is_equal_approx(payout._guest_seconds(normal, "food_max"), float(common.food_max_wait_seconds) * 1.48)
		and payout._regular_counts([]).rare == 11, "等餐耐心和稀有客人数进入模拟")

func _initialize() -> void:
	_check_service()
	_check_kitchen()
	_check_global_effects()
	print("TROPHY EFFECTS RESULT: %d passed / %d failed" % [passed, failed])
	quit(1 if failed else 0)
