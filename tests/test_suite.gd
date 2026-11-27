extends SceneTree

const Sim = preload("res://scripts/core/simulation.gd")
const Catalog = preload("res://scripts/core/catalog.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Store = preload("res://scripts/core/save_store.gd")
var passed = 0
var failed = 0
var results: Array = []

func expect(value: bool, name: String) -> void:
	results.append({"name":name,"passed":value})
	if value:
		passed += 1
		print("PASS ",name)
	else:
		failed += 1
		push_error("FAIL " + name)

func equivalent(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b

func run_day(sim) -> bool:
	if not sim.start_day().ok: return false
	while sim.phase=="DAY":
		sim.step()
		if not sim.invariant_errors().is_empty():
			push_error("tick %d: %s" % [sim.tick,sim.invariant_errors()])
			return false
	return true

func food_fixture(kind: String = "normal"):
	var s = Sim.new()
	# Boundary fixtures explicitly use 15/60; gameplay defaults are config-driven.
	s.chapter.common_guest_template.food_penalty_cycle_seconds = 15
	s.chapter.common_guest_template.food_max_wait_seconds = 60
	s.start_day()
	s.staff = []
	s.arrival_plan = [{"id":1,"type":kind,"tick":1}]
	s.arrival_cursor = 1
	s._spawn_customer({"id":1,"type":kind})
	var c = s.customers[1]
	c.state = "FOOD"
	c.recipe = "starter_rice"
	c.order = 1
	c.seat = "table_1"
	c.pos = Grid.interaction(Grid.find(s.layout,"table_1"))
	c.food_start = 0
	c.next_penalty = Rules.ticks(s._guest_seconds(c,"cycle"),s.tick_ms)
	c.food_max = Rules.ticks(s._guest_seconds(c,"food_max"),s.tick_ms)
	s.seats.table_1 = 1
	s.orders[1] = {"id":1,"customer":1,"seat":"table_1","recipe":"starter_rice","created_tick":0,"submitted_tick":0,"served_tick":-1,"status":"ACTIVE","supply":"NONE","supply_owner":0,"delivery_owner":0,"food":0}
	return s

func prepare_plate(s, quality: float = 1.0) -> void:
	var c = s.customers[1]
	c.state = "EATING"
	c.served_quality = quality
	s.orders[1].food = 1
	s.orders[1].supply = "SERVED"
	s.foods[1] = {"id":1,"recipe":"starter_rice","quality":quality,"location":"PLATE","location_id":"1","origin":"stove_1","bound_order":1,"reserved_by":0,"created_tick":0}
	s.stats.produced = 1

func draw_named_trophy(sim, id: String) -> Dictionary:
	var catalog = sim.relic_defs
	sim.relic_defs = {id: catalog[id]}
	var drawn = sim.draw_trophy()
	sim.relic_defs = catalog
	return drawn

func verify_shop_tiers() -> void:
	var invalid = Catalog.load_all()
	invalid.buffs.quick_dining.level = 0
	invalid.chapter.trophy_box.day_weights[0].weights[0] = -1
	var errors = Catalog.validate(invalid)
	expect(errors.any(func(error): return error.contains("星级")) and errors.any(func(error): return error.contains("奖杯品质权重")), "SHOP: 配置拒绝无效增益等级和盲盒权重")
	var sim = Sim.new()
	sim.chapter.buff_shop_weights = [{"from_day":1,"weights":{"1":100}}, {"from_day":8,"weights":{"3":100}}]
	sim.day = 7
	sim._refresh_shop()
	expect(sim.shop.slice(1).all(func(offer): return offer.type == "buff" and int(sim.buff_defs[offer.id].level) == 1), "SHOP: 阶段变更前按旧增益星级出货")
	sim.day = 8
	sim._refresh_shop()
	expect(sim.shop.slice(1).all(func(offer): return offer.type == "buff" and int(sim.buff_defs[offer.id].level) == 3) and sim.shop[1].id != sim.shop[2].id, "SHOP: 新阶段按高星级出货且两格增益不重复")
	var early = sim.trophy_box_offer()
	sim.day = 25
	var later_day = sim.trophy_box_offer()
	sim.trophy_draws_total = 20
	var later_draws = sim.trophy_box_offer()
	for grade in [2, 3, 4]:
		expect(early.odds[grade] < later_day.odds[grade] and later_day.odds[grade] < later_draws.odds[grade], "TROPHY: 天数与累计次数独立提高紫橙彩概率")
	expect(early.pools.size() == 5 and early.pools.all(func(pool): return not pool.is_empty() and "bronze_clock" not in pool), "TROPHY: 五档都有独立候选，展廊赠礼保留")

func verify_faster_dining() -> void:
	var sim = Sim.new()
	sim.day = 3
	sim.stars = 1
	sim.unlock_land_plot("purchase_annex")
	var normal = sim.guest_eating_duration("normal")
	var elder = sim.guest_eating_duration("elder")
	sim.shop[1] = {"type":"buff","id":"quick_dining","price":180,"bought":false}
	expect(sim.buy_offer(1).ok and is_equal_approx(sim.guest_eating_duration("normal"), normal * .8), "DINING: 购买快食节奏后用餐时间缩短 20%")
	sim.day = 5
	sim.stars = 24
	sim.reputation = 1000
	var exhibit = sim.unlock_land_plot("trophy_gallery").ok and sim.upgrade("relic_slots").ok
	sim.gold = 1000
	expect(draw_named_trophy(sim, "dining_hourglass").ok and sim.stars == 22 and is_equal_approx(sim.guest_eating_duration("normal"), normal * .8), "DINING: 流沙漏用金币抽取，放背包时暂未生效")
	expect(exhibit and sim.move_facility("trophy_dining_hourglass", Vector2i(27, 10)).ok and is_equal_approx(sim.guest_eating_duration("elder"), elder * .65), "DINING: 展示流沙漏与增益叠加并保留客人用餐倍率")
	var first_meal = {}
	if sim.start_day().ok:
		while sim.phase == "DAY" and first_meal.is_empty():
			sim.step()
			for guest in sim.active_customers.values():
				if guest.state == "EATING":
					first_meal = guest
					break
	expect(not first_meal.is_empty() and first_meal.deadline - sim.tick == Rules.ticks(float(sim.chapter.common_guest_template.eat_seconds) * float(sim.guest_defs[first_meal.type].get("eat_time_multiplier", 1.0)) * .65, sim.tick_ms), "DINING: 正式营业上菜时以缩短后的秒数设置用餐结束时间")

func verify_night_layout() -> void:
	var sim = Sim.new()
	var original_pass = Grid.find(sim.layout, "pass")
	var all_sides = Grid.interaction_cells(original_pass)
	expect(all_sides.size() == 4 and all_sides.all(func(cell): return Grid.approach(sim.layout, Vector2(cell), original_pass).get("target") == Vector2(cell)), "LAYOUT: 从柜台四个操作格均可直接操作")
	expect(sim.move_facility("order", Vector2i(4, 5)).ok and sim.move_facility("pass", Vector2i(7, 5)).ok and sim.opening_errors().is_empty(), "LAYOUT: 订单口和出餐口朝下受阻时可贴墙摆放")
	var walker = Vector2(6, 5)
	var route = Grid.approach(sim.layout, walker, original_pass)
	expect(route.get("target") == walker and route.path.is_empty() and Grid.blocked(sim.layout, Vector2i(7, 6)), "LAYOUT: 出餐口寻路就近使用可达侧面")
	var table = Grid.find(sim.layout, "table_1")
	var stove = Grid.find(sim.layout, "stove_2")
	expect(sim.rotate_facility(table.id).ok and sim.rotate_facility(stove.id).ok and Grid.interaction(table) == Grid.vec(table.pos) + Vector2.LEFT and Grid.interaction(stove) == Vector2(3, 2), "LAYOUT: 餐桌和灶台 90 度旋转改变实际操作格")
	var waiter_cell = Vector2i(1, 11)
	var chef_cell = Vector2i(5, 3)
	expect(sim.move_staff("waiter", 0, waiter_cell).ok and sim.move_staff("chef", 0, chef_cell).ok and not sim.move_staff("chef", 0, waiter_cell).ok and not sim.move_staff("waiter", 0, Vector2i(7, 6)).ok, "LAYOUT: 夜晚可移动两种员工，墙体和已占用站位不可选")
	var reloaded = Sim.new()
	var state = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = reloaded.restore_state(state).ok
	expect(restored and Grid.rotation(Grid.find(reloaded.layout, table.id)) == 1 and reloaded.start_day().ok and reloaded.staff[0].pos == Vector2(chef_cell) and reloaded.staff[int(reloaded.attributes.chefs)].pos == Vector2(waiter_cell), "LAYOUT: 设施朝向与员工开店站位正确读档")
	expect(not reloaded.move_staff("waiter", 0, Vector2i(2, 11)).ok and not reloaded.rotate_facility(table.id).ok, "LAYOUT: 白天锁定员工站位和设施朝向")
	while reloaded.phase == "DAY" and int(reloaded.stats.completed) == 0: reloaded.step()
	expect(int(reloaded.stats.get("completed", 0)) > 0 and reloaded.invariant_errors().is_empty(), "LAYOUT: 两个柜台贴墙后仍完成交单、取餐和用餐")
	var trapped = Sim.new()
	trapped.layout.wall_cells.append_array([[6,1],[7,2],[6,3],[5,2]])
	expect(not trapped.move_facility("pass", Vector2i(6, 2)).ok and Grid.vec(Grid.find(trapped.layout, "pass").pos) == Vector2(10, 3), "LAYOUT: 四面都封堵的柜台摆放被撤销")

func party_arrivals(size: int, first_id: int, at_tick: int) -> Array:
	var plans = []
	for index in range(size):
		var type = "commuter" if index % 2 == 0 else "market_visitor"
		plans.append({"id": first_id + index, "type": type, "tick": at_tick, "party_id": first_id, "party_size": size})
	return plans

func verify_group_dining() -> void:
	var sim = Sim.new()
	var merge = sim.move_facility("table_2", Vector2i(4, 8))
	var pair = Grid.find(sim.layout, "table_1")
	expect(merge.ok and Grid.table_size(pair) == 2 and Grid.footprint_cells(pair).size() == 2 and Grid.find(sim.layout, "table_2").is_empty() and sim.attributes.tables == 8, "TABLE: 两张单人桌合成双人桌，总座位数不变")
	var second = sim.move_facility("table_4", Vector2i(10, 8))
	sim.layout.wall_cells.append_array([[4, 7], [3, 8]])
	var before = sim.export_state()
	var blocked = sim.move_facility("table_3", Vector2i(4, 8))
	expect(second.ok and not blocked.ok and blocked.error.contains("空间不足") and equivalent(sim.export_state(), before), "TABLE: 四人桌空间不足时保留两张双人桌原位")
	var moved = sim.move_facility("table_1", Vector2i(5, 11))
	merge = sim.move_facility("table_3", Vector2i(5, 11))
	var quad = Grid.find(sim.layout, "table_1")
	expect(moved.ok and merge.ok and Grid.table_size(quad) == 4 and Grid.footprint_cells(quad).size() == 4 and Grid.interaction_cells(quad).size() == 4, "TABLE: 两张双人桌占用四格并形成四个独立座位")
	var mixed = sim.move_facility("table_5", Vector2i(6, 12))
	expect(not mixed.ok and Grid.find(sim.layout, "table_5").pos.size() == 2 and not sim.move_facility("cashier", Vector2i(6, 12)).ok, "TABLE: 多人桌的非锚点格也接收碰撞和合成规则")
	var pairs = sim.move_facility("table_6", Vector2i(7, 10))
	var saved = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = Sim.new()
	var opened = pairs.ok and restored.restore_state(saved).ok and restored.start_day().ok
	expect(opened and restored.seats.size() == 8 and restored.table_slots.table_1.size() == 4 and restored.table_slots.table_5.size() == 2, "TABLE: 读档后真实营业保留四人桌、双人桌和八座总容量")
	if not opened: return
	restored.arrival_plan = party_arrivals(2, 1, 1) + party_arrivals(2, 3, 1) + party_arrivals(4, 5, 1)
	restored.arrival_plan.append({"id": 9, "type": "normal", "tick": 30})
	var grouped_seating = false
	var first_waited = false
	var synced_exit = false
	var third_queue = false
	while restored.phase == "DAY" and restored.tick < restored.midnight_ticks + 2500:
		restored.step()
		if not restored.customers.has(9): continue
		var first = restored.customers[1]
		var last = restored.customers[2]
		if not grouped_seating:
			var quad_guest = restored.customers[5]
			grouped_seating = first.seat == "table_5" and first.seat == last.seat and first.seat_key != last.seat_key and quad_guest.seat == "table_1"
		if first.state == "STAYING" or last.state == "STAYING":
			first_waited = restored.seats[first.seat_key] == 1 and restored.seats[last.seat_key] == 2
		if first.state == "EXITING" and last.state == "EXITING": synced_exit = first.state_tick == last.state_tick
		if restored.customers[3].state == "QUEUE" and not restored.customers[9].seat.is_empty(): third_queue = true
	expect(grouped_seating and third_queue, "PARTY: 两人组和四人组整桌入座，满桌等待时单人仍可入座")
	expect(first_waited and synced_exit and restored.last_report.get("completed", 0) == 9 and restored.invariant_errors().is_empty(), "PARTY: 同桌吃完后共同离开，各自只付一次并保留守恒")
	var denied = Sim.new()
	denied.move_facility("table_2", Vector2i(4, 8))
	denied.start_day()
	denied.attributes.queue_capacity = 1
	denied.arrival_plan = party_arrivals(4, 1, 1) + party_arrivals(2, 5, 1)
	var remarks = []
	denied.guest_moment.connect(func(id, moment):
		if moment == &"no_table": remarks.append(id)
	)
	var at_door = false
	for i in range(150):
		denied.step()
		if not remarks.is_empty() and denied.customers[1].state == "REFUSING":
			at_door = absf(denied.customers[1].pos.x) < 1.2
	expect(denied.stats.arrived == 6 and denied.stats.refused == 6 and denied.stats.refused_no_table == 4 and denied.stats.admitted == 0 and denied.customers.size() == 4 and denied._queue_count() == 0, "PARTY: 缺四人桌或容量不足均整组拒绝，队满组不会创建演员")
	expect(remarks == [1] and at_door and denied.active_customers.is_empty(), "PARTY: 缺桌组走到门口抱怨一次才离开")

func verify_guest_mix() -> void:
	var sim = Sim.new()
	sim.start_day()
	var normals = {}
	for arrival in sim.arrival_plan:
		if sim.guest_defs[arrival.type].rarity == "normal": normals[arrival.type] = true
	expect(normals.size() >= 4 and int(sim.guest_defs.normal.pool_weight) < 100 and sim.guest_eating_duration("commuter") < sim.guest_eating_duration("market_visitor"), "GUEST: 同一餐段会抽到多种普通客，数值具有小幅差别")
	var later = Sim.new()
	later.day = 5
	later.start_day()
	var parties = {}
	for arrival in later.arrival_plan:
		if not arrival.has("party_id"): continue
		if not parties.has(arrival.party_id): parties[arrival.party_id] = []
		parties[arrival.party_id].append(arrival)
	var sizes = []
	var together = true
	for visit in parties.values():
		sizes.append(visit.size())
		if not visit.all(func(member): return member.tick == visit[0].tick and member.party_size == visit.size()): together = false
	expect(together and 2 in sizes and 4 in sizes and later.arrival_plan.size() == 44, "PARTY: 成员同刻到店，占用既有客流人数")

func verify_build_tools() -> void:
	var sim = Sim.new()
	var first_pair = sim.move_facility("table_2", Vector2i(4, 8))
	var double_table = Grid.find(sim.layout, "table_1")
	var original_seats = Grid.interaction_cells(double_table)
	var split = sim.split_facility("table_1")
	var pieces = [Grid.find(sim.layout, "table_1"), Grid.find(sim.layout, str(split.get("second_id", "")))]
	expect(first_pair.ok and split.ok and pieces.all(func(piece): return Grid.table_size(piece) == 1) and Grid.interaction_cells(pieces[0]) + Grid.interaction_cells(pieces[1]) == original_seats and sim.attributes.tables == 8, "BUILD: 双人桌拆成两张同朝向单人桌，保留座位与容量")
	var rejected = sim.export_state()
	expect(not sim.split_facility("table_1").ok and equivalent(sim.export_state(), rejected), "BUILD: 单人桌不能拆分且状态不变")
	var other = Sim.new()
	other.move_facility("table_2", Vector2i(4, 8))
	other.move_facility("table_4", Vector2i(10, 8))
	other.move_facility("table_1", Vector2i(5, 11))
	var merged = other.move_facility("table_3", Vector2i(5, 11))
	var rotated = other.rotate_facility("table_1")
	var quad = Grid.find(other.layout, "table_1")
	var occupied = Grid.footprint_cells(quad)
	var places = Grid.interaction_cells(quad)
	var halves = other.split_facility("table_1")
	var left = Grid.find(other.layout, "table_1")
	var right = Grid.find(other.layout, str(halves.get("second_id", "")))
	if merged.ok and rotated.ok and halves.ok:
		var footprint = Grid.footprint_cells(left) + Grid.footprint_cells(right)
		var chairs = Grid.interaction_cells(left) + Grid.interaction_cells(right)
		expect(Grid.table_size(left) == 2 and Grid.table_size(right) == 2 and occupied.all(func(cell): return cell in footprint) and places.all(func(cell): return cell in chairs) and other.opening_errors().is_empty(), "BUILD: 旋转后的四人桌可拆成两张双人桌，桌面和椅子位置不变")
	else:
		expect(false, "BUILD: 旋转后的四人桌可拆分")
	var stored = other.store_facility("table_1")
	var stored_split = other.split_facility("table_1")
	expect(stored.ok and stored_split.ok and other.stored_facilities("table").size() == 2 and other.stored_facilities("wall").is_empty(), "BUILD: 背包内的多人桌拆分后两张桌均留在背包")
	var walls = Sim.new()
	var first_wall = walls.place_wall(Vector2i(3, 12))
	var second_wall = walls.place_wall(Vector2i(4, 12))
	var detour = Grid.path(walls.layout, Vector2(2, 12), Vector2(5, 12))
	expect(first_wall.ok and second_wall.ok and walls.gold == 600 and walls.reputation == 0 and detour.size() > 3 and walls.opening_errors().is_empty(), "BUILD: 连续建墙免费，营业路线绕过新墙")
	var before = walls.export_state()
	var chair = Vector2i(Grid.interaction(Grid.find(walls.layout, "table_1")))
	expect(not walls.place_wall(chair).ok and not walls.place_wall(Vector2i(14, 2)).ok and not walls.place_wall(Vector2i(Grid.vec(walls.layout.exit))).ok and not walls.place_wall(Vector2i(3, 12)).ok and equivalent(walls.export_state(), before), "BUILD: 墙体不能堵座位、出入口或重叠放置，锁区不可建造")
	var first_pass = walls.place_wall(Vector2i(1, 12))
	expect(first_pass.ok and not walls.place_wall(Vector2i(1, 13)).ok, "BUILD: 新墙不能封住餐厅仅剩的通路")
	var restored = Sim.new()
	var loaded = restored.restore_state(JSON.parse_string(JSON.stringify(walls.export_state())))
	var id = str(first_wall.get("facility_id", ""))
	expect(loaded.ok and Grid.facilities(restored.layout, "wall").size() == 3 and Grid.blocked(restored.layout, Vector2i(3, 12)) and restored.move_facility(id, Vector2i(3, 13)).ok and restored.store_facility(id).ok and not Grid.blocked(restored.layout, Vector2i(3, 13)), "BUILD: 自建墙体随布局读档，可移动及收起")
	expect(restored.start_day().ok and not restored.place_wall(Vector2i(6, 12)).ok and not restored.split_facility("table_1").ok, "BUILD: 营业中锁定拆桌与建墙")

func verify_wall_rows() -> void:
	var sim = Sim.new()
	var horizontal = Grid.wall_line(Vector2i(6, 14), Vector2i(3, 12), 0)
	expect(horizontal == [Vector2i(3,14), Vector2i(4,14), Vector2i(5,14), Vector2i(6,14)], "WALL: 反向拖动仍生成连续的横排")
	var vertical = Grid.wall_line(Vector2i(3, 12), Vector2i(5, 14), 1)
	var row = sim.place_wall_row(vertical, 1)
	expect(row.ok and int(row.count) == 3 and Grid.facilities(sim.layout, "wall").all(func(f): return Grid.rotation(f) == 1) and sim.gold == 600, "WALL: 一次放下一整排竖墙并保存朝向")
	var rotation = sim.rotate_facility(str(row.get("facility_id", "")))
	expect(rotation.ok and Grid.rotation(Grid.find(sim.layout, row.facility_id)) == 2, "WALL: 已铺下的单格墙体也可旋转")
	var untouched = sim.export_state()
	var blocked = sim.place_wall_row(Grid.wall_line(Vector2i(1,12), Vector2i(1,13), 1), 1)
	expect(not blocked.ok and equivalent(sim.export_state(), untouched), "WALL: 整排封路时全部撤销，首格也不会落下")

func settle_festival_fixture(sim, full_stars: bool = true) -> void:
	sim.start_day()
	sim.arrival_plan = [{"id":1,"type":"normal","tick":1}]
	sim.arrival_cursor = 1
	sim.stats.arrived = 1
	sim.stats.admitted = 1
	sim.stats.completed = 1
	sim.stats.completed_before_midnight = 1
	sim.stats.funnel.S = 1
	if not full_stars: sim.stats.wait_penalty_raw = 1
	sim._close_day()

func verify_major_events() -> void:
	var sim = Sim.new()
	var schedule = [[6,8,"food_festival"], [11,12,"thug_visit"], [13,13,"group_booking"], [15,15,"food_inspection"], [16,21,"bad_weather"], [24,25,"food_review"]]
	var valid_schedule = true
	for row in schedule:
		for date in range(int(row[0]) - 1, int(row[1]) + 2):
			var matching = sim.major_events_for(date).filter(func(event): return event.id == row[2])
			if (not matching.is_empty()) != (date >= int(row[0]) and date <= int(row[1])): valid_schedule = false
	expect(valid_schedule, "EVENT: 六次重大事件按指定晚上预告、次日开始，恶劣天气覆盖第 21 天")
	sim.day = 5
	expect(not sim.confirm_major_event("food_festival").ok, "EVENT: 公告日期前不可领资源")
	sim.day = 6
	sim.gold = 10000
	var expected_grant = int(sim.chapter.events.food_festival.notice.grant.reputation)
	var expected_reward = int(sim.chapter.events.food_festival.notice.goal.reward.reputation)
	var grant = sim.confirm_major_event("food_festival")
	expect(grant.ok and grant.grant.reputation == expected_grant and sim.reputation == expected_grant, "EVENT: 确认美食节公告即时领配置声望")
	var reloaded = Sim.new()
	var persisted = reloaded.restore_state(JSON.parse_string(JSON.stringify(sim.export_state())))
	var again = reloaded.confirm_major_event("food_festival")
	expect(persisted.ok and again.ok and again.grant.is_empty() and reloaded.reputation == expected_grant, "EVENT: 领取状态随存档恢复，重复确认无额外奖励")
	settle_festival_fixture(reloaded)
	expect(reloaded.last_report.major_event_goals[0].passed == 1 and reloaded.reputation == expected_grant, "EVENT: 挑战逐天记录，首日不提前发奖")
	reloaded.continue_night()
	settle_festival_fixture(reloaded)
	reloaded.continue_night()
	var missed = Sim.new()
	missed.restore_state(reloaded.export_state())
	# Keep the other two days perfect while making this route miss day 8.
	settle_festival_fixture(missed, false)
	expect(missed.last_report.major_event_goals[0].finished and not missed.last_report.major_event_goals[0].success and missed.reputation == expected_grant, "EVENT: 连续三天有一天少于三星就不发挑战奖励")
	settle_festival_fixture(reloaded)
	reloaded._close_day()
	expect(reloaded.last_report.major_event_goals[0].success and reloaded.last_report.reputation_after == expected_grant + expected_reward and reloaded.reputation == expected_grant + expected_reward, "EVENT: 第三天结算只发一次 挑战声望")
	var festival = Sim.new()
	festival.day = 6
	festival.chapter.demand_curve[1].rare = 1
	festival.start_day()
	var festival_events = festival.events_for()
	var base_counts = festival._regular_counts(festival_events.filter(func(item): return item.id != "food_festival"))
	var planned = festival._regular_counts(festival_events)
	var traffic = festival.chapter.events.food_festival.traffic
	var growth_ok = true
	for key in planned:
		var base = int(base_counts[key])
		if base > 0 and int(planned[key]) != base + maxi(1, roundi(base * float(traffic[key]))): growth_ok = false
	expect(growth_ok and planned.rare == 2 and festival.arrival_plan.size() == planned.normal + planned.rare + 2 * planned["2"] + 4 * planned["4"], "EVENT: 美食节按配置增加四类客流，小增幅仍增加一位或一组")
	var booking = Sim.new()
	booking.day = 13
	booking.start_day()
	var booking_events = booking.events_for()
	var base_groups = booking._regular_counts(booking_events.filter(func(item): return item.id != "group_booking"))
	var appointments = booking._regular_counts(booking_events)
	var late = booking.arrival_plan.filter(func(visit): return int(visit.tick) >= 1600 and int(visit.tick) < 2000)
	var two = int(base_groups["2"])
	var four = int(base_groups["4"])
	expect(appointments["2"] == two + maxi(1, roundi(two * .50)) and appointments["4"] == four + maxi(1, roundi(four * 1.50)) and absi(late.size() - roundi(booking.arrival_plan.size() * .55)) <= 3, "EVENT: 团餐增加双人组和四人组，55% 客流集中晚市")
	var inspection = food_fixture()
	inspection.day = 24
	inspection.modifiers = inspection.effective_modifiers()
	prepare_plate(inspection)
	inspection._checkout(inspection.customers[1])
	var enhanced = Rules.payment(24, 1.0, float(inspection.chapter.events.food_review.payment_pct), 1.0, 0)
	expect(inspection.stats.income == enhanced and enhanced > 24 and inspection.stats.quality_penalty_raw == 2, "EVENT: 品鉴同时提高结账单价和实际品质要求")

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var data = Catalog.load_all()
	expect(data.errors.is_empty(),"CONFIG: 内容配置有效")
	verify_shop_tiers()
	verify_faster_dining()
	verify_night_layout()
	verify_group_dining()
	verify_guest_mix()
	verify_build_tools()
	verify_wall_rows()
	verify_major_events()
	var invalid_speed = Catalog.load_all()
	invalid_speed.chapter.fast_forward_multiplier = 0
	expect(not Catalog.validate(invalid_speed).is_empty(),"CONFIG: 拒绝零倍率快进造成时间不推进")
	var invalid_upgrade = Catalog.load_all()
	invalid_upgrade.chapter.upgrade_rules.queue_capacity.step = 0
	expect(not Catalog.validate(invalid_upgrade).is_empty(),"CONFIG: 拒绝队列升级步长为零")
	var missing_capacity = Catalog.load_all()
	missing_capacity.chapter.initial_attributes.erase("queue_capacity")
	expect(not Catalog.validate(missing_capacity).is_empty(),"CONFIG: 拒绝缺少必要队列容量")
	var invalid_peak = Catalog.load_all()
	invalid_peak.chapter.events.lunch_rush.arrival_peak.end_minute = 1290
	expect(not Catalog.validate(invalid_peak).is_empty(), "CONFIG: 拒绝接客窗口以外的集中到店时段")
	var invalid_target = Catalog.load_all()
	invalid_target.chapter.completion_star_targets[0].percent = 101
	expect(not Catalog.validate(invalid_target).is_empty(), "CONFIG: 拒绝超过 100% 的完餐目标")
	expect(Grid.errors(data.chapter.initial_layout).is_empty(),"LAYOUT: 初始通路有效")
	expect(data.chapter.initial_layout.width==32 and data.chapter.initial_layout.height==22 and data.chapter.land_plots.size()==7,"LAND: 32×22 内提供七块顺序地块")
	var locked_layout = Sim.new()
	expect(Grid.structural_blocked(locked_layout.layout,Vector2i(14,2)) and Grid.structural_blocked(locked_layout.layout,Vector2i(25,8)) and not Grid.structural_blocked(locked_layout.layout,Vector2i(12,8)),"LAND: 未解锁厨房/客桌阻断寻路，基础区仍通行")
	expect(not locked_layout.move_facility("cashier",Vector2i(14,2)).ok and Vector2i(Grid.vec(Grid.find(locked_layout.layout,"cashier").pos))==Vector2i(2,10),"LAND: 锁区禁止摆放且失败不改变设施")
	locked_layout.stars = 20
	expect(not locked_layout.unlock_land_plot("east_dining").ok and not locked_layout.unlock_land_plot("kitchen_extension").ok,"LAND: 解锁必须遵守顺序与开放天数")
	locked_layout.day = 3
	expect(locked_layout.unlock_land_plot("purchase_annex").ok and locked_layout.purchase_unlocked(), "LAND: 首块开放采购处")
	locked_layout.day = 5
	expect(locked_layout.unlock_land_plot("trophy_gallery").ok and "bronze_clock" in locked_layout.owned_relics and Grid.facilities(locked_layout.layout, "trophy").size() == 1, "LAND: 奖杯地块赠送可立即生效的独有遗物")
	locked_layout.day = 7
	expect(locked_layout.unlock_land_plot("decor_studio").ok and locked_layout.decoration_shop_unlocked(), "LAND: 工坊开放装饰商店")
	locked_layout.day = 10
	expect(locked_layout.unlock_land_plot("kitchen_extension").ok and locked_layout.attributes.chefs == 3 and Grid.facilities(locked_layout.layout, "stove").size() == 3, "LAND: 厨房解锁同时赠送厨师及可用灶台")
	expect(locked_layout.upgrade_cost("chefs") == int(locked_layout.chapter.upgrade_rules.chefs.first_cost) and int(locked_layout.upgrade_purchases.chefs) == 0, "LAND: 免费厨师不计入付费升级次数")
	for id in ["south_dining", "garden_dining", "east_dining"]:
		locked_layout.day = int(locked_layout.next_land_plot().unlock_day)
		expect(locked_layout.unlock_land_plot(id).ok and locked_layout.opening_errors().is_empty(), "LAND: 客席扩建后通路保持畅通 " + id)
	expect(locked_layout.attributes.tables == 18 and locked_layout.upgrade_cost("tables") == int(locked_layout.chapter.upgrade_rules.tables.first_cost) and locked_layout.upgrade_gold_cost("tables") == int(locked_layout.chapter.upgrade_rules.tables.first_gold), "LAND: 地块赠送的十张餐桌不抬高升级价格")
	var restored_lots = Sim.new()
	expect(restored_lots.restore_state(locked_layout.export_state()).ok and equivalent(restored_lots.export_state(),locked_layout.export_state()),"LAND: 地块顺序、赠送资产及付费次数完整存档")
	var bad_lot_save = locked_layout.export_state()
	bad_lot_save.layout.unlocked_plots.reverse()
	expect(not Sim.new().restore_state(bad_lot_save).ok,"LAND: 拒绝存档内颠倒的地块解锁顺序")
	expect(Grid.structural_blocked(data.chapter.initial_layout,Vector2i(11,6)) and Grid.reachable(data.chapter.initial_layout,Grid.vec(data.chapter.initial_layout.entrance),Grid.interaction(Grid.find(data.chapter.initial_layout,"table_5"))),"WALL: 实体分割墙改变寻路，但不封死餐桌")
	var bad_gate = Catalog.load_all()
	bad_gate.chapter.upgrade_unlocks.waiters.purchase_caps[0].max_purchases = -1
	expect(not Catalog.validate(bad_gate).is_empty(),"GATE: 配置拒绝负升级上限")
	var budget = Sim.new()
	var table_gold = budget.upgrade_gold_cost("tables")
	var table_rep = budget.upgrade_cost("tables")
	budget.gold = table_gold - 1
	budget.reputation = table_rep
	var before_upgrade = budget.export_state()
	expect(not budget.upgrade("tables").ok and budget.export_state() == before_upgrade, "UPGRADE: 金币不足时不扣声望或改变布局")
	budget.gold = table_gold
	budget.reputation -= 1
	before_upgrade = budget.export_state()
	expect(not budget.upgrade("tables").ok and budget.export_state() == before_upgrade, "UPGRADE: 声望不足时不扣金币")
	budget.reputation = table_rep
	expect(budget.upgrade("tables").ok and budget.gold == 0 and budget.reputation == 0 and budget.night_spend == table_gold, "UPGRADE: 正好够两种资源时扣款并记账")
	var reopened = Sim.new()
	expect(reopened.restore_state(budget.export_state()).ok and reopened.upgrade_gold_cost("tables") == table_gold + int(budget.chapter.upgrade_rules.tables.gold_increment) and reopened.night_spend == table_gold, "UPGRADE: 存档保留下一次升级报价和已付成本")
	var gated = Sim.new()
	gated.reputation = 1000
	gated.gold = 10000
	expect(gated.upgrade("waiters").ok and gated.upgrade("waiters").ok and not gated.upgrade("waiters").ok,"GATE: 第一天服务员最多累计升级两次")
	gated.day = 4
	expect(gated.upgrade("waiters").ok,"GATE: 第四天解锁更多服务员升级")
	var locked = Sim.new()
	locked.reputation = 1000
	expect(locked.upgrade_progression().unlocked == ["tables", "waiters"] and locked.upgrade_progression().next_key == "chefs" and not locked.upgrade("chefs").ok, "GATE: 第一晚开放桌位与服务员，预告厨师")
	expect(not locked.upgrade("relic_slots").ok and locked.upgrade_gate("relic_slots").error.contains("第 5 天"),"GATE: 遗物位达到解锁日之前不可购买")
	locked.day = 3
	expect("chefs" in locked.upgrade_progression().unlocked and locked.upgrade_progression().next_key == "menu_slots", "GATE: 厨师开放后只预告下一项菜单槽")
	locked.day = 5
	expect(locked.attributes.relic_slots == 3 and int(locked.chapter.attribute_caps.relic_slots) == 6, "TROPHY: 默认三个展示位，最高六个")
	expect(locked.upgrade("relic_slots").ok and locked.attributes.relic_slots == 4, "GATE: 解锁日可以买第四个展示位")
	locked.day = 21
	locked.gold = 4000
	expect(locked.upgrade("relic_slots").ok and locked.upgrade("relic_slots").ok and locked.attributes.relic_slots == 6 and not locked.upgrade("relic_slots").ok, "TROPHY: 可升级至六个展示位")
	var unlimited = Sim.new()
	unlimited.reputation = 1000
	unlimited.chapter.upgrade_unlocks.waiters.unlock_day = 0
	unlimited.chapter.upgrade_unlocks.waiters.purchase_caps = [{"day":1,"max_purchases":0}]
	expect(unlimited.upgrade("waiters").ok and unlimited.upgrade("waiters").ok,"GATE: 配置 0 表示没有按天购买次数限制")
	var relic_run = Sim.new()
	relic_run.stars = 12
	var locked_box = relic_run.export_state()
	expect(not relic_run.draw_trophy().ok and relic_run.export_state() == locked_box, "TROPHY: 展廊开放前无法开箱且不扣款")
	relic_run.day = 5
	relic_run.reputation = 1000
	relic_run.gold = 4000
	expect(relic_run.unlock_land_plot("purchase_annex").ok and relic_run.unlock_land_plot("trophy_gallery").ok and relic_run.trophy_shop_unlocked(), "TROPHY: 开放展廊时一并开放盲盒")
	var original_mods = relic_run.effective_modifiers()
	var initial_gold = relic_run.gold
	var initial_stars = relic_run.stars
	var first_offer = relic_run.trophy_box_offer()
	var first = draw_named_trophy(relic_run, "brass_spoon")
	expect(first.ok and first.id in relic_run.owned_relics and not Grid.placed(Grid.find(relic_run.layout,first.facility_id)) and relic_run.gold == initial_gold - first_offer.gold and relic_run.stars == initial_stars, "TROPHY: 只扣金币且奖杯直接入背包")
	expect(relic_run.effective_modifiers() == original_mods and not relic_run.move_facility(first.facility_id,relic_run.trophy_shop_cell()).ok, "TROPHY: 未展示的奖杯不生效，盲盒占用独立格子")
	expect(relic_run.move_facility(first.facility_id,Vector2i(27,10)).ok, "TROPHY: 默认容量足以展示额外奖杯")
	expect(relic_run.effective_modifiers().flat_gold == original_mods.flat_gold + 1, "TROPHY: 展示后常驻效果生效")
	var second_price = relic_run.trophy_box_offer().gold
	var golden_draw = draw_named_trophy(relic_run, "golden_spoon")
	expect(golden_draw.ok and golden_draw.gold == second_price and second_price > first.gold and relic_run.trophy_box_offer().gold > second_price and relic_run.trophy_draws_total == 2, "TROPHY: 当晚金币逐箱涨价，累计计数增加")
	expect(relic_run.move_facility(golden_draw.facility_id,Vector2i(28,10)).ok and Grid.facilities(relic_run.layout, "trophy").size() == 3, "TROPHY: 到默认容量前可摆三件奖杯")
	expect(relic_run.store_facility(first.facility_id).ok and relic_run.move_facility(golden_draw.facility_id,Vector2i(27,10)).ok and relic_run.move_facility(first.facility_id,Vector2i(28,10)).ok, "TROPHY: 收起后可替换奖杯格子")
	var relic_save = relic_run.export_state()
	var reloaded = Sim.new()
	expect(reloaded.restore_state(relic_save).ok and reloaded.trophy_shop_unlocked() and equivalent(reloaded.export_state(),relic_save), "TROPHY: 当日、累计次数与随机状态可恢复")
	var third = relic_run.draw_trophy()
	var replay = reloaded.draw_trophy()
	expect(third.ok and third.id == replay.id and third.id not in [first.id, golden_draw.id, "bronze_clock"], "TROPHY: 重读生成相同的下一箱，排除已拥有和展廊赠礼")
	expect(not reloaded.move_facility(replay.facility_id, Vector2i(29, 10)).ok and reloaded.trophy_placement_cells(replay.facility_id).is_empty(), "TROPHY: 默认展位满时第四件留在背包")
	var expensive_gold = reloaded.gold
	reloaded.gold = 0
	var insufficient = reloaded.export_state()
	expect(not reloaded.draw_trophy().ok and reloaded.export_state() == insufficient, "TROPHY: 余额不足不改随机状态和背包")
	reloaded.gold = expensive_gold
	expect(reloaded.start_day().ok and reloaded.modifiers.flat_gold == original_mods.flat_gold + 2, "TROPHY: 展示效果参与实际营业")
	var during = reloaded.trophy_rng.state
	expect(not reloaded.draw_trophy().ok and reloaded.trophy_rng.state == during, "TROPHY: 营业期间无法开箱")
	var total_draws = reloaded.trophy_draws_total
	reloaded.phase = "REPORT"
	reloaded.last_report = {"result": "CONTINUE"}
	expect(reloaded.continue_night().ok and reloaded.trophy_draws_today == 0 and reloaded.trophy_draws_total == total_draws and reloaded.trophy_box_offer().gold == first_offer.gold, "TROPHY: 换天只重置当晚金币报价")
	var prior_capacity = relic_save.duplicate(true)
	prior_capacity.attributes.relic_slots = 3
	prior_capacity.upgrade_purchases.relic_slots = 2
	var adapted_capacity = Sim.new()
	expect(adapted_capacity.restore_state(prior_capacity).ok and adapted_capacity.attributes.relic_slots == 5, "TROPHY: 已购买的展位升级按三个默认展位累计")
	var moved_counters = Sim.new()
	moved_counters.day = 3
	moved_counters.stars = 1
	moved_counters.unlock_land_plot("purchase_annex")
	expect(moved_counters.move_facility("cashier",Vector2i(3,10)).ok and moved_counters.move_facility("slot",Vector2i(16,8)).ok and moved_counters.opening_errors().is_empty(), "LAYOUT: 收银台和采购处可移动")
	var moved_shop = moved_counters.export_state()
	expect(not moved_counters.move_facility("slot", Vector2i(24, 8)).ok and not moved_counters.move_facility("slot", Vector2i(0, 0)).ok and moved_counters.export_state() == moved_shop, "LAYOUT: 商店不能阻塞墙体或移入未开放地块")
	var persisted_shop = Sim.new()
	expect(persisted_shop.restore_state(moved_shop).ok and Grid.vec(Grid.find(persisted_shop.layout, "slot").pos) == Vector2(16, 8), "LAYOUT: 采购处移动后跨存档保留新位置")
	var all_stars = Sim.new()
	all_stars.start_day()
	all_stars.arrival_plan = [{"id":1,"type":"normal","tick":1}]
	all_stars.arrival_cursor = 1
	all_stars.stats.arrived = 1
	all_stars.stats.admitted = 1
	all_stars.stats.completed = 1
	all_stars.stats.completed_before_midnight = 1
	all_stars.stats.funnel.S = 1
	all_stars.tick = all_stars.day_ticks-1
	all_stars.step()
	expect(all_stars.last_report.star_goals==[true,true,true] and all_stars.stars==3,"STARS: 全入店、零扣分、午夜前全完成获得三星")
	var no_stars = Sim.new()
	no_stars.start_day()
	no_stars.arrival_plan = [{"id":1,"type":"normal","tick":1}]
	no_stars.arrival_cursor = 1
	no_stars.stats.refused = 1
	no_stars.stats.wait_penalty_raw = 1
	no_stars.tick = no_stars.midnight_ticks
	no_stars._close_day()
	expect(no_stars.last_report.star_goals==[false,false,false] and no_stars.stars==0,"STARS: 拒客、原始周期扣分及午夜未完成均不授星")
	var threshold = Sim.new()
	threshold.start_day()
	threshold.arrival_plan = threshold.arrival_plan.slice(0, 4)
	threshold.stats.arrived = 4
	threshold.stats.refused = 1
	threshold.stats.completed = 3
	threshold.stats.completed_before_midnight = 3
	threshold.tick = threshold.midnight_ticks + 5
	threshold._close_day()
	expect(threshold.last_report.star_goals == [false, true, true] and threshold.last_report.completion_required == 3, "STARS: 恰好达到完餐门槛可得第三星，日结晚于午夜不影响")
	var kitchen_delay = food_fixture()
	kitchen_delay.tick = 400
	kitchen_delay._terminal(kitchen_delay.customers[1], "F")
	kitchen_delay._close_day()
	var kitchen = kitchen_delay.last_report.diagnosis
	expect(kitchen.focus == "kitchen" and kitchen.stages.kitchen.average == 20.0 and kitchen.stages.delivery.count == 0 and kitchen.stages.kitchen.tables == ["table_1"], "REPORT: 未到出餐口的超时全计入出餐前，保留桌位定位")
	var delivery_delay = food_fixture()
	delivery_delay.orders[1].pass_tick = 100
	delivery_delay.tick = 400
	delivery_delay._terminal(delivery_delay.customers[1], "F")
	delivery_delay._close_day()
	var delivery = delivery_delay.last_report.diagnosis
	expect(delivery.focus == "delivery" and delivery.stages.kitchen.average == 5.0 and delivery.stages.delivery.average == 15.0 and delivery.stages.delivery.tables == ["table_1"], "REPORT: 到达出餐口后等候独立统计并定位到对应餐桌")
	expect(data.chapter.initial_attributes.chefs==2 and data.chapter.initial_attributes.waiters==4 and data.chapter.initial_attributes.tables==8,"LAYOUT: 扩建版初始两厨四服务员八桌")
	expect(Grid.structural_blocked(data.chapter.initial_layout,Vector2i(3,6)) and not Grid.structural_blocked(data.chapter.initial_layout,Vector2i(5,6)),"LAYOUT: 厨房隔断和通道正确")
	var broken = data.duplicate(true)
	broken.chapter.rent_schedule[3].day = 27
	expect(not Catalog.validate(broken).is_empty(),"CONFIG: 拒绝最后日缺房租")
	expect(Rules.payment(24,1.25,0.2,2,3)==75,"PRICE-01: 售价只最终取整")
	var pricing = Sim.new()
	expect(pricing.meal_price("starter_rice", 1.0, Rules.BASE_MODIFIERS, pricing.guest_defs.big_eater) == 96, "PRICE-03: 大胃袋在基础菜价下支付四倍")
	expect(pricing.meal_price("starter_rice", 2.0, Rules.BASE_MODIFIERS) == 33 and pricing.meal_price("starter_rice", .75, Rules.BASE_MODIFIERS) == 18, "PRICE: 高品质溢价放缓，低品质仍按原折扣")
	expect(Rules.payment(24,2,0,0,9,true)==0,"PRICE-02: 霸王餐最终零付款")
	expect(Rules.customer_count(36,0.8)==64,"GUEST-01: 同类人数百分比加算")
	expect(Rules.quality(1,99,data.chapter)==2,"BUFF-05: 品质上限钳制")
	expect(Rules.ticks(6/1.4,50)==86,"BUFF-04: 烹饪时长向上对齐tick")
	var night = Sim.new()
	expect(night.phase=="NIGHT" and night.day==1 and night.shop.size()==3,"FLOW-01: 首晚生成三格")
	expect(night.shop[1].id!=night.shop[2].id,"SHOP-05: 同晚Buff不重复")
	night.day = 3
	night.stars = 1
	night.unlock_land_plot("purchase_annex")
	var old = night.export_state()
	var result = night.buy_offer(0)
	expect(result.get("needs_replacement",false) and night.export_state()==old,"SHOP-01: 未选择替换不扣款")
	result = night.buy_offer(0,0)
	expect(result.ok and night.owned_recipes.size()==2 and "starter_rice" in night.owned_recipes and night.menu[0]==night.shop[0].id,"SHOP-02: 原子解锁并保留旧菜")
	var money = night.gold
	var today = night.export_state()
	expect(night.purchase_spent() and not night.buy_offer(0,0).ok and not night.buy_offer(1).ok and night.export_state() == today, "SHOP: 一次成功购买占用当晚所有商品的额度")
	var next_shop = Sim.new()
	expect(next_shop.restore_state(today).ok and next_shop.purchase_spent() and not next_shop.buy_offer(2).ok, "SHOP: 读档不会恢复已用过的额度")
	expect(run_day(next_shop) and next_shop.continue_night().ok and not next_shop.purchase_spent() and next_shop.purchase_offer_status(1).ok, "SHOP: 下一晚刷新商品并恢复采购额度")
	expect(night.change_menu(0,"starter_rice").ok and night.gold==money,"RECIPE-02: 收藏换菜免费")
	var poor = Sim.new()
	poor.day = 3
	poor.stars = 1
	poor.unlock_land_plot("purchase_annex")
	poor.gold = 0
	expect(not poor.buy_offer(1).ok and poor.buff_states.is_empty() and not poor.purchase_spent(),"ECON-07: 余额不足无副作用")
	poor.gold = 5000
	expect(poor.buy_offer(1).ok and poor.purchase_spent() and not poor.buy_offer(0, 0).ok, "SHOP: 买了营业增益后今夜无法再买菜谱")
	var growth = Sim.new()
	growth.day = 3
	growth.reputation = 1000
	var up = growth.upgrade("chefs")
	expect(up.ok and growth.attributes.chefs==3 and not growth.opening_errors().is_empty(),"UPGRADE: 新厨师配套灶台需放置")
	growth.move_facility(up.facility_id,Vector2i(9,2))
	expect(growth.opening_errors().is_empty(),"UPGRADE: 放下灶台后可开店")
	expect(not growth.move_facility("table_1",Vector2i(3,6)).ok,"LAYOUT: 墙体不可摆放家具")
	expect(not growth.move_facility("table_1",Vector2i(5,4)).ok and growth.opening_errors().is_empty(),"TASK-12: 禁止移动桌子阻挡出生点")
	var buffs = Sim.new()
	buffs.grant_buff("swift_steps",2)
	expect(run_day(buffs) and buffs.buff_states.swift_steps.remaining_days==1,"BUFF-02: 当日生效后衰减一次")
	buffs.continue_night()
	buffs.grant_buff("swift_steps",2)
	expect(buffs.buff_states.swift_steps.stack_count==2 and buffs.buff_states.swift_steps.remaining_days==3,"BUFF-01: 强度和共享天数累加")
	for i in range(3):
		run_day(buffs)
		if i<2: buffs.continue_night()
	expect(not buffs.buff_states.has("swift_steps"),"BUFF: 到期整组删除")
	var caps = Sim.new()
	for i in range(4): caps.grant_buff("great_value",2)
	expect(not caps.grant_buff("great_value",2).ok and caps.preview_quality("starter_rice")==2,"BUFF: 达层数上限拒绝授予")
	var zero_rep = food_fixture()
	zero_rep.tick = 299
	zero_rep.step()
	expect(zero_rep.reputation==0 and zero_rep.stats.wait_penalty_raw==1 and zero_rep.stats.wait_penalty_actual==0,"ECON-06: 零声望记原始扣分")
	var timeout = food_fixture()
	for i in range(1200): timeout.step()
	expect(timeout.stats.wait_penalty_raw==4 and timeout.customers[1].terminal=="F" and timeout.orders[1].status=="CANCELLED","GUEST-02: 四圈扣分后超时取消")
	var thug = food_fixture("thug")
	var thug_rules = thug.guest_defs.thug
	expect(thug.customers[1].next_penalty == Rules.ticks(15.0 * float(thug_rules.food_cycle_multiplier), thug.tick_ms) and thug_rules.unlimited_food_wait and thug_rules.food_penalty_per_cycle == 3, "GUEST-06: 地痞等餐不限次数，每轮扣三点")
	var elder = food_fixture("elder")
	expect(elder._guest_seconds(elder.customers[1],"choose")==9 and elder._guest_seconds(elder.customers[1],"eat")==24,"GUEST-05: 老头耗时为3倍")
	var served = food_fixture()
	served.tick = 299
	served.orders[1].food = 1
	served.orders[1].supply = "WITH_WAITER"
	served.foods[1] = {"id":1,"recipe":"starter_rice","quality":1.0,"location":"WAITER","location_id":"1","origin":"stove_1","bound_order":1,"reserved_by":0,"created_tick":0}
	served.stats.produced = 1
	served.staff = [{"id":1,"role":"waiter","pos":served.customers[1].pos,"path":[],"task":{"kind":"DELIVER","stage":"MOVE","order_id":1},"carry_orders":[],"carry_food":[1],"reason":"","time":{"move":0,"cook":0,"interact":0,"idle":0,"blocked":0}}]
	served.step()
	expect(served.customers[1].state=="EATING" and served.stats.wait_penalty_raw==0,"GUEST-03: 同tick上菜先于扣分")
	var checkout = food_fixture()
	prepare_plate(checkout,1.25)
	checkout.modifiers.price_pct = .2
	checkout.modifiers.flat_gold = 3
	checkout.guest_defs.normal.type_payment_multiplier = 2
	var receipts: Array = []
	checkout.payment_received.connect(func(cell, amount): receipts.append([cell, amount]))
	checkout._checkout(checkout.customers[1])
	var first_gold = checkout.gold
	checkout._checkout(checkout.customers[1])
	expect(checkout.stats.income==66 and checkout.gold==first_gold,"ECON-05: 结账金额正确且幂等")
	expect(receipts == [[checkout.customers[1].pos, 66]], "PAYMENT: 实际付款只发一次金币反馈，携带客人位置和实收金额")
	var free = food_fixture("freeloader")
	prepare_plate(free)
	free.modifiers.flat_gold = 9
	free.payment_received.connect(func(cell, amount): receipts.append([cell, amount]))
	free._checkout(free.customers[1])
	expect(free.stats.completed==1 and free.stats.income==0 and free.stats.payer_count==0,"PRICE: 霸王餐计完成而非付款")
	expect(receipts.size() == 1, "PAYMENT: 免单完成不会产生金币反馈")
	var disappoint = food_fixture()
	prepare_plate(disappoint,1.25)
	disappoint.chapter.common_guest_template.expected_quality = 1.5
	disappoint.reputation = 10
	disappoint._checkout(disappoint.customers[1])
	expect(disappoint.reputation==9 and disappoint.stats.quality_penalty_raw==2,"GUEST-08: 品质失望扣分分账")
	var close_exact = food_fixture()
	prepare_plate(close_exact)
	close_exact.customers[1].deadline = close_exact.day_ticks
	close_exact.tick = close_exact.day_ticks-1
	close_exact.step()
	expect(close_exact.phase=="DAY" and close_exact.stats.completed==1 and close_exact.stats.income==24,"FLOW-06: 第120秒吃完已结账但继续清场")
	while close_exact.phase=="DAY": close_exact.step()
	expect(close_exact.last_report.funnel.S==1,"FLOW-06b: 客人离开后才生成复盘")
	var late = food_fixture()
	prepare_plate(late)
	late.customers[1].deadline = late.day_ticks+1
	late.tick = late.day_ticks-1
	late.step()
	expect(late.phase=="DAY" and late.stats.completed==0,"FLOW-07: 第120秒不强制闭店或提前付款")
	while late.phase=="DAY": late.step()
	expect(late.last_report.completed==1 and late.last_report.funnel.C==0,"FLOW-07b: 收尾时自然用餐完成后结账")
	var event = Sim.new()
	event.day = 20
	event.start_day()
	var daily_events = event.events_for()
	var base = event._regular_counts(daily_events.filter(func(item): return item.id != "bad_weather"))
	var rain = event._regular_counts(daily_events)
	var rain_ok = rain.keys().all(func(key): return int(rain[key]) == Rules.customer_count(int(base[key]), -0.60))
	expect(rain_ok and event.arrival_plan.size() == rain.normal + rain.rare + 2 * rain["2"] + 4 * rain["4"], "EVENT-01: 恶劣天气按配置压低各类客流")
	var evening = Sim.new()
	evening.day = 8
	evening.reputation = 1000
	expect(evening.upgrade_cost("queue_capacity")==48,"QUEUE: 首次队列升级价为48声望")
	expect(evening.upgrade("queue_capacity").ok and evening.attributes.queue_capacity==224 and evening.upgrade_cost("queue_capacity")==68,"QUEUE: 初始96、单次+128且按购买次数涨价")
	var boost = Sim.new()
	boost.day = 22
	boost._refresh_shop()
	expect(boost.shop[1].id=="crowd_magnet","BUFF: 第22晚保底提供客流增益")
	boost.grant_buff("crowd_magnet",2)
	boost.start_day()
	expect(boost.arrival_plan.size()==227,"TRAFFIC: 末周146位常规客经增益加到219位，另有8位稀有客")
	var overflow = Sim.new()
	overflow.start_day()
	overflow.attributes.queue_capacity = 1
	for seat_id in overflow.seats: overflow.seats[seat_id] = -1
	overflow.arrival_plan = [{"id":1,"type":"normal","tick":1},{"id":2,"type":"blogger","tick":1}]
	overflow.arrival_cursor = 0
	overflow.step()
	expect(overflow.stats.arrived==2 and overflow.stats.admitted==1 and overflow.stats.refused==1 and overflow.stats.funnel.R==1 and overflow.customers.size()==1,"QUEUE: 满额丢弃稀有客，不创建NPC或额外扣声望")
	overflow.tick = Rules.ticks(26,overflow.tick_ms)
	overflow.step()
	expect(overflow.customers[1].state=="QUEUE" and overflow.stats.funnel.Q==0,"QUEUE: 排队超过26秒也不自然离开")
	var special = Sim.new()
	special.day = 11
	special.start_day()
	var single = special.arrival_plan.filter(func(p): return p.type == "thug")
	var second = Sim.new()
	second.day = 12
	second.start_day()
	var pair = second.arrival_plan.filter(func(p): return p.type == "thug")
	expect(single.size() == 1 and not single[0].has("party_id") and single[0].tick == Rules.ticks(48, special.tick_ms) and pair.size() == 2 and pair[0].party_size == 2 and pair[0].party_id == pair[1].party_id and pair[0].tick == Rules.ticks(86, second.tick_ms), "EVENT-02: 地痞单人与双人组分两天出现，保留各自到店时间")
	var early = Sim.new()
	early.start_day()
	early.arrival_plan = [{"id":1,"type":"normal","tick":1}]
	early.arrival_cursor = 0
	while early.phase=="DAY" and early.tick<early.day_ticks: early.step()
	expect(early.phase=="REPORT" and early.last_report.operation_ticks>=early.day_ticks and early.last_report.funnel.S==1,"FLOW-05: 全部计划客人离开后仍营业至21点")
	var midnight = food_fixture()
	prepare_plate(midnight)
	midnight.customers[1].deadline = midnight.midnight_ticks + 4
	midnight.arrival_plan.append({"id":2,"type":"normal","tick":2})
	midnight.arrival_cursor = 2
	midnight._spawn_customer(midnight.arrival_plan[1])
	midnight.tick = midnight.midnight_ticks - 1
	midnight.step()
	expect(midnight.customers[2].terminal == "C" and midnight._queue_count() == 0 and midnight.customers[1].state == "EATING" and midnight.seats.table_1 == 1 and midnight.stats.income == 0, "MIDNIGHT: 午夜仅解散排队，正在用餐的客人继续占座")
	while midnight.phase=="DAY": midnight.step()
	expect(midnight.last_report.operation_ticks > midnight.midnight_ticks + 4 and midnight.last_report.completed == 1 and midnight.last_report.completed_before_midnight == 0 and midnight.last_report.income > 0 and not midnight.last_report.star_goals[2], "MIDNIGHT: 午夜后照常结账，客人离开后结算并单计完餐闪星")
	var clock = Sim.new()
	clock.start_day()
	expect(clock.clock_text()=="09:00" and clock.midnight_ticks==clock.day_ticks * 5 / 4,"Opening time is 09:00")
	clock.tick = clock.day_ticks
	expect(clock.clock_text()=="21:00","Arrival cutoff is 21:00")
	clock.tick = clock.midnight_ticks
	expect(clock.clock_text()=="00:00","Closing cutoff is midnight")
	var paused = Sim.new()
	paused.start_day()
	paused.paused = true
	paused.step()
	expect(paused.tick==0 and paused.customers.is_empty(),"FLOW-04: 暂停冻结到店与时钟")
	expect(not paused.start_day().ok,"FLOW-02: 开店不可重复")
	var before = paused.gold
	expect(not paused.buy_offer(1).ok and paused.gold==before,"FLOW-03: 白天禁止购买")
	var rent_due = int(Sim.new().next_rent().amount)
	for cash in [rent_due, rent_due - 1]:
		var rent = food_fixture()
		rent._terminal(rent.customers[1],"F")
		rent.day=7
		rent.gold=cash
		rent.tick=rent.day_ticks
		rent._close_day()
		expect((rent.gold==0 and rent.last_report.result=="CONTINUE") if cash==rent_due else (rent.gold==cash and rent.last_report.result=="LOSE"),"ECON: 房租边界现金%d" % cash)
	var full = Sim.new()
	full.gold = 1000000
	var full_ok = true
	for i in range(28):
		if not run_day(full): full_ok=false; break
		if i<27 and not full.continue_night().ok: full_ok=false; break
	expect(full_ok and full.last_report.result=="WIN" and full.day==28 and not full.continue_night().ok,"ECON-03: 28天四笔租金及最终胜利流程（高现金夹具）")
	for chapter_id in ["street_corner", "market_lane"]:
		var week = Sim.new(Catalog.load_all(chapter_id))
		var week_ok = week.catalog.errors.is_empty()
		for day in range(1, 8):
			if not week_ok: break
			var plot = week.next_land_plot()
			if not plot.is_empty() and week.land_plot_status(plot.id).ok:
				week_ok = week.unlock_land_plot(plot.id).ok
			week_ok = week_ok and run_day(week)
			if day < 7: week_ok = week_ok and week.continue_night().ok
		expect(week_ok and week.reports.size() == 7 and week.last_report.rent_ok, "CHAPTER: %s 前七天自然现金流程可结算并缴租" % chapter_id)
		if week_ok:
			var rush = week.reports[5]
			var preview = Sim.new(Catalog.load_all(chapter_id))
			preview.day = 6
			preview.start_day()
			var counts = preview._regular_counts(preview.events_for().filter(func(item): return not item.has("arrival_peak")))
			expect(rush.planned == counts.normal + counts.rare + 2 * counts["2"] + 4 * counts["4"] and rush.completion_target == 75, "EVENT: %s 午市高峰重排到店时段" % chapter_id)
	var rush_plan = Sim.new()
	rush_plan.day = 6
	rush_plan.start_day()
	var clustered = rush_plan.arrival_plan.filter(func(visit): return int(visit.tick) >= 600 and int(visit.tick) < 1000)
	expect(clustered.size() == roundi(rush_plan.arrival_plan.size() * 0.45), "EVENT: 首个午市 12:00–14:00 命中配置比例")
	var second_chapter = Sim.new(Catalog.load_all("market_lane"))
	expect(second_chapter.chapter.id == "market_lane" and second_chapter.menu == ["batch_snacks"] and float(second_chapter.chapter.common_guest_template.eat_seconds) == 5.0, "CHAPTER: 第二章使用独立初始菜谱、节奏和标识")
	expect(not second_chapter.restore_state(Sim.new().export_state()).ok and Store.default_path("street_corner") != Store.default_path("market_lane"), "SAVE: 两个章节使用独立路径并拒绝串档")
	var deterministic_a = Sim.new()
	var deterministic_b = Sim.new()
	run_day(deterministic_a)
	run_day(deterministic_b)
	expect(deterministic_a.last_report==deterministic_b.last_report,"SAVE-03: 同种子同命令结果完全一致")
	var state = JSON.parse_string(JSON.stringify(deterministic_a.export_state()))
	var restored = Sim.new()
	expect(restored.restore_state(state).ok and restored.gold==deterministic_a.gold and equivalent(restored.last_report,deterministic_a.last_report),"SAVE-02: 完整结算恢复不二次入账")
	deterministic_a.continue_night()
	restored.continue_night()
	expect(equivalent(deterministic_a.shop,restored.shop) and deterministic_a.buff_bag==restored.buff_bag,"SHOP-03: 恢复随机状态后下一晚商品一致")
	var checkpoint = "res://.local/unit_checkpoint.json"
	var saved_error = Store.write_checkpoint(restored.export_state(),checkpoint)
	var from_disk = Sim.new()
	expect(saved_error.is_empty() and from_disk.restore_state(Store.read_checkpoint(checkpoint)).ok and equivalent(from_disk.shop,restored.shop),"SAVE: 文件检查点读写通过")
	run_day(deterministic_a)
	run_day(restored)
	expect(deterministic_a.last_report==restored.last_report,"SAVE: 经检查点恢复再营业仍完全可复现")
	var incompatible = Sim.new()
	var old_state = incompatible.export_state()
	old_state.config_version = "0.2.2"
	old_state.save_version = 1
	var previous_gold = incompatible.gold
	expect(not incompatible.restore_state(old_state).ok and incompatible.gold==previous_gold and incompatible.phase=="NIGHT","SAVE-04: 旧版存档被拒绝且当前资源不变")
	old_state.config_version = "0.3.0"
	old_state.save_version = 2
	expect(not incompatible.restore_state(old_state).ok and incompatible.gold==previous_gold and incompatible.phase=="NIGHT","SAVE-05: 新布局不覆盖0.3.0的用户存档")
	full.new_run(111)
	expect(full.stats.is_empty() and full.customers.is_empty() and full.reports.is_empty() and full.gold==600,"FLOW: 重开清除上一局统计")
	var stress_ok = true
	for i in range(12):
		var concurrent = Sim.new()
		concurrent.new_run(10000+i)
		concurrent.day = 4
		concurrent.gold = 20000
		concurrent.reputation = 20000
		concurrent.upgrade("waiters")
		concurrent.upgrade("waiters")
		var hire = concurrent.upgrade("chefs")
		concurrent.move_facility(hire.facility_id,Vector2i(9,2))
		concurrent.upgrade("menu_slots")
		concurrent.owned_recipes.append("quick_noodles")
		concurrent.change_menu(1,"quick_noodles")
		if not run_day(concurrent): stress_ok=false; break
	expect(stress_ok,"TASK: 12种子多人多菜全tick预留与物品守恒")
	var output = {"passed":passed,"failed":failed,"results":results,"notes":"v0.4只验证功能与基本不变量，不做全面平衡评估。"}
	var file = FileAccess.open("res://.local/test_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	file.close()
	print("RESULT: ",passed," passed, ",failed," failed")
	quit(1 if failed>0 else 0)
