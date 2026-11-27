extends SceneTree

const Catalog = preload("res://scripts/core/catalog.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Decor = preload("res://scripts/core/decoration_effects.gd")
const Rules = preload("res://scripts/core/rules.gd")
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func _initialize() -> void:
	for chapter in ["street_corner", "market_lane"]:
		check(Catalog.load_all(chapter).errors.is_empty(), "章节配置有效 " + chapter)
	var sim = Sim.new()
	if not sim.catalog.errors.is_empty():
		quit(1)
		return
	check(sim.opening_errors().is_empty() and sim.layout.plots.size() == 7, "小地图可直接开店，且只开放起始区域")
	check(not sim.buy_offer(0).ok and not sim.buy_decoration("meal_bell").ok, "锁定商店无法交易")
	sim.gold = 10000
	sim.reputation = 1000
	var table = sim.upgrade("tables")
	check(table.ok and Grid.placed(Grid.find(sim.layout, table.get("facility_id", ""))) and sim.opening_errors().is_empty(), "新桌自动落入合法空位")
	sim.stars = 100
	var first_four := ["purchase_annex", "trophy_gallery", "decor_studio", "kitchen_extension"]
	check(not sim.unlock_land_plot("trophy_gallery").ok, "扩建不能跳过顺序")
	for i in range(sim.layout.plots.size()):
		var plot = sim.layout.plots[i]
		if i < first_four.size():
			check(plot.id == first_four[i], "系统扩建顺序 " + str(plot.id))
		sim.day = int(plot.unlock_day)
		var result = sim.unlock_land_plot(plot.id)
		check(result.ok and sim.opening_errors().is_empty(), "扩建时通路有效 " + str(plot.id) + " " + str(result))
	check(sim.purchase_unlocked() and sim.trophy_shop_unlocked() and sim.decoration_shop_unlocked(), "三个商店随各自地块开放")
	for id in ["slot", "trophy_shop", "decor_shop"]:
		var counter = Grid.find(sim.layout, id)
		check(Grid.interaction_accessible(counter, Grid.walkable_region(sim.layout)), "商店初始位置可达 " + id)
		var origin = Vector2i(Grid.vec(counter.pos))
		var moved = false
		for step in Grid.DIRECTIONS:
			if sim.move_facility(id, origin + step).ok:
				moved = true
				break
		check(moved and Vector2i(Grid.vec(counter.pos)) != origin and sim.opening_errors().is_empty(), "商店可移动且保持通路 " + id)
		check(not sim.store_facility(id).ok and sim.move_facility(id, origin).ok, "可移回的商店保持在场景内 " + id)
	var savings = sim.gold
	var night_spending = sim.night_spend
	var stars = sim.stars
	sim.stars = 0
	var before_purchase = sim.export_state()
	check(not sim.buy_decoration("meal_bell").ok and sim.export_state() == before_purchase, "装饰缺少闪星时不交易")
	sim.stars = stars
	var first = sim.buy_decoration("meal_bell")
	var second = sim.buy_decoration("meal_bell")
	var lantern = sim.buy_decoration("gold_lantern")
	check(first.ok and second.ok and first.facility_id != second.facility_id and sim.stored_facilities("decoration").size() == 3, "同款可重复购买并存入背包")
	check(sim.stars == stars - 3 and sim.gold == savings and sim.night_spend == night_spending, "装饰只花闪星，金币与金币支出不变")
	var placements = [
		[first.facility_id, Vector2i(4, 7)], [second.facility_id, Vector2i(3, 8)], [lantern.facility_id, Vector2i(5, 7)],
	]
	for item in placements:
		check(sim.move_facility(item[0], item[1]).ok, "装饰有合法摆位 " + str(item))
	var effects = Decor.build(sim.layout, sim.decoration_defs)
	check(is_equal_approx(float(effects.fixtures.table_1.table_eat), .18), "重叠的同款效果只取最高值")
	check(is_equal_approx(float(effects.fixtures.table_1.table_gold), .12), "同一张桌可受到不同效果")
	check(sim.store_facility(first.facility_id).ok and is_equal_approx(float(Decor.build(sim.layout, sim.decoration_defs).fixtures.table_1.table_eat), .18), "收起一件后保留另一件的效果")
	var screen = sim.buy_decoration("wish_screen")
	check(sim.move_facility(screen.facility_id, Vector2i(16, 12)).ok, "长条装饰放置")
	var object = Grid.find(sim.layout, screen.facility_id)
	var definition = sim.decoration_defs[object.decoration_id]
	var before = Decor.coverage(object, definition, sim.layout)
	check(before.has(Vector2i(16, 14)) and sim.rotate_facility(object.id).ok, "朝向影响前方覆盖")
	var after = Decor.coverage(object, definition, sim.layout)
	check(before != after and after.has(Vector2i(15, 12)) and Grid.footprint(object).size == Vector2i(2, 1), "旋转同时更新覆盖和占地")
	check(sim.move_facility(table.facility_id, Vector2i(15, 12)).ok, "将新桌搬入装饰范围")
	check(sim.move_facility("gift_table_e2", Vector2i(23, 16)).ok, "扩建餐桌合成多人桌")
	var additional = [
		["breeze_fan", Vector2i(14, 9)], ["lotus_pond", Vector2i(17, 10)],
		["peach_pavilion", Vector2i(19, 16)], ["herb_rack", Vector2i(14, 2)],
		["ceramic_station", Vector2i(16, 2)],
	]
	for item in additional:
		var purchase = sim.buy_decoration(item[0])
		check(purchase.ok and sim.move_facility(purchase.facility_id, item[1]).ok, "装饰商店的其他物件可摆放 " + item[0])
	var restored = Sim.new()
	check(restored.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))).ok, "重复装饰、朝向和位置随存档恢复")
	check(sim.start_day().ok, "新布局正式营业")
	check(is_equal_approx(sim.guest_eating_duration("normal", "table_1"), 8.0 * .82), "局部用餐时间进入真实模拟")
	check(sim.meal_price("starter_rice", 1.0, sim.modifiers, {}, "table_1") == 26, "局部金币进入真实结账")

	check(is_equal_approx(sim.fixture_bonus(table.facility_id, "table_quality"), .15) and sim.fixture_bonus(table.facility_id, "table_reputation") == 1.0, "桌边品质和声望范围分别生效")
	check(sim.fixture_bonus("gift_table_e1", "group_base_gold") == 2.0 and sim.fixture_bonus("gift_table_e3", "group_base_gold") == 0.0, "基础餐费装饰只作用于多人桌")
	var runner = {"role": "waiter", "pos": Vector2(14, 11), "path": [Vector2(14, 12)], "task": {"kind": "RETURN", "stage": "MOVE"}, "time": {"move": 0}}
	sim._advance_staff(runner)
	var expected_step = float(sim.chapter.movement.waiter_speed) * (1.0 + sim.modifiers.speed + .24) * sim.tick_ms / 1000.0
	check(is_equal_approx(runner.pos.y - 11.0, expected_step), "服务员实际在亮格内加速")
	var cook = {"task": {"kind": "COOK", "recipe": "starter_rice", "stove_id": "gift_stove_k", "order_ids": [], "batch": 2}}
	sim._arrive_task(cook)
	check(cook.task.done_tick - sim.tick == Rules.ticks(6.0 / 1.22, sim.tick_ms), "灶台实际按局部速度烹饪")
	sim._complete_action(cook)
	check(is_equal_approx(float(sim.foods[1].quality), 1.25), "烹饪品质保留到产出的餐品")

	var thug = Sim.new()
	thug.day = 11
	check(thug.start_day().ok, "地痞事件日开店")
	for date in [11, 12]:
		var visit = Sim.new()
		visit.day = date
		check(visit.start_day().ok, "地痞事件第 %d 天可开店" % date)
		var counts = visit._regular_counts(visit.events_for().filter(func(e): return e.id != "thug_visit"))
		var usual = int(counts.normal) + int(counts.rare) + 2 * int(counts["2"]) + 4 * int(counts["4"])
		var special = visit.arrival_plan.filter(func(c): return c.type == "thug")
		check(special.size() == date - 10 and visit.arrival_plan.size() - special.size() == roundi(usual * .7), "两天均减少常规客流并另安排当日地痞")
	var guest = {"type": "thug", "id": 1, "state": "FOOD", "terminal": "", "next_penalty": 1, "food_start": -10, "food_max": 2}
	var cycle = Rules.ticks(thug._guest_seconds(guest, "cycle"), thug.tick_ms)
	thug.reputation = 60
	thug.tick = cycle * 5 + 1
	thug._apply_patience(guest)
	check(guest.terminal.is_empty() and thug.reputation == 42 and int(thug.stats.wait_penalty_raw) == 18, "超出旧耐心上限仍在等，每轮扣 3")

	for input in [[0, -50], [1, 0], [2, 50]]:
		verify_inspection(input[0], input[1])
	print("EXPANSIONS RESULT: %d passed / %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func verify_inspection(levels: int, expected: int) -> void:
	var sim = Sim.new()
	sim.day = 15
	sim.gold = 20000
	sim.reputation = 300
	var table = Grid.find(sim.layout, "table_1")
	table.pos = [5, 11]
	table.capacity = 4
	sim.layout.facilities = sim.layout.facilities.filter(func(f): return f.id not in ["table_2", "table_3", "table_4"])
	for i in range(levels):
		sim.grant_buff("great_value", 2)
	check(sim.start_day().ok, "食品安全检查营业开始")
	sim.arrival_plan = sim.arrival_plan.filter(func(c): return c.type == "food_inspector")
	check(sim.arrival_plan.size() == 4 and sim.arrival_plan.all(func(c): return c.party_id == sim.arrival_plan[0].id and int(c.party_size) == 4), "四位检查员同一批到店")
	check(is_equal_approx(sim.guest_eating_duration("food_inspector"), 48.0), "检查员用餐时间为 600%")
	while sim.phase == "DAY" and sim.tick < 6000:
		sim.step()
	var result = sim.last_report.get("quality_inspection", {})
	check(sim.phase == "REPORT" and result.get("served") == 4 and result.get("assessed") == expected and result.get("change") == expected and sim.invariant_errors().is_empty(),
		"真实出餐与检查结算 " + str(expected) + " " + str(result))
