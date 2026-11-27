extends RefCounted

signal service_bell(midnight: bool)
signal guest_moment(id: int, moment: StringName)
signal payment_received(cell: Vector2, amount: int)

const Catalog = preload("res://scripts/core/catalog.gd")
const Grid = preload("res://scripts/core/layout.gd")
const ServiceRoutes = preload("res://scripts/core/service_routes.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Trophies = preload("res://scripts/core/trophies.gd")
const Decor = preload("res://scripts/core/decoration_effects.gd")
const ReportStats = preload("res://scripts/core/report_stats.gd")
const Crew = preload("res://scripts/core/crew_roster.gd")
const UPGRADE_ORDER = ["tables", "waiters", "chefs", "menu_slots", "relic_slots", "queue_capacity"]
const PARTY_SIZES = [1, 2, 4]

var catalog: Dictionary
var chapter: Dictionary
var recipes: Dictionary
var buff_defs: Dictionary
var guest_defs: Dictionary
var relic_defs: Dictionary
var decoration_defs: Dictionary
var local_effects := {"waiter_cells": {}, "fixtures": {}}
var stars = 0
var owned_relics: Array = []
var trophy_rng = RandomNumberGenerator.new()
var legacy_trophies: Array = []
var trophy_draws_total := 0
var trophy_draws_today := 0
var last_trophy_id := ""
var trophy_yield_rng: RandomNumberGenerator
var trophy_quality_rng: RandomNumberGenerator
var phase = "NIGHT"
var day = 1
var seed_value = 123456
var gold = 600
var reputation = 0
var total_reputation = 0
var attributes: Dictionary = {}
var upgrade_purchases: Dictionary = {}
var owned_recipes: Array = []
var menu: Array = []
var layout: Dictionary = {}
var buff_states: Dictionary = {}
var shop: Array = []
var buff_bag: Array = []
var shop_rng = RandomNumberGenerator.new()
var reports: Array = []
var last_report: Dictionary = {}
var major_event_claims: Array = []
var major_event_views: Array = []
var night_spend = 0
var tick = 0
var paused = false
var day_ticks = 2400
var midnight_ticks = 3000
var tick_ms = 50
var current_until := 0
var current_ready := 0
var current_cell := Vector2.ZERO
const Minions = preload("res://scripts/core/minion_staff.gd")
var helper_staff := {}
var crew_lineup: Array = []
var linked_fire_ready := 0
var linked_fire_until := 0
var linked_fire_origin := Vector2.ZERO
var linked_fire_stoves: Array = []
const LINKED_FIRE_RANGE := 4.5
const LINKED_FIRE_PREP_SECONDS := 1.65
const LINKED_FIRE_COOLDOWN := 26.0

func set_crew(lineup: Array) -> bool:
	if not Crew.valid(lineup): return false
	crew_lineup = lineup.duplicate(true)
	revision += 1
	return true

func helper_at(role: String,slot: int) -> String:
	var index := slot-Crew.by_role(crew_lineup,role).size()
	return Minions.at(helper_staff,role,index) if index>=0 else ""

func staff_skin(role: String,slot: int) -> String:
	var id := crew_at(role,slot)
	return id if not id.is_empty() else "minion_"+helper_at(role,slot)

func crew_at(role: String, slot: int) -> String:
	var members := Crew.by_role(crew_lineup, role)
	return str(members[slot]) if slot >= 0 and slot < members.size() else ""

func crew_on_duty(id: String, role: String) -> bool:
	return crew_lineup.any(func(entry): return entry.id == id and entry.role == role)

func linked_fire_targets() -> Array:
	if phase != "DAY" or not crew_on_duty("kilnkeeper", "chef"): return []
	var lead = staff.filter(func(member): return member.get("crew_id", "") == "kilnkeeper")
	if lead.is_empty(): return []
	var origin: Vector2 = lead[0].pos
	var targets: Array = []
	for chef in staff:
		var pot: Dictionary = chef.task
		if pot.get("kind") != "COOK" or pot.stage != "PREP": continue
		var stove := Grid.find(layout, str(pot.stove_id))
		if stove.is_empty(): continue
		var distance := Grid.vec(stove.pos).distance_to(origin)
		if distance > LINKED_FIRE_RANGE or tick < int(pot.prep_ready_tick): continue
		if not pot.order_ids.any(func(id): return _order_active(int(id)) and orders[int(id)].supply == "COOKING" and int(orders[int(id)].supply_owner) == int(chef.id)): continue
		targets.append({"chef": chef, "stove": stove, "distance": distance})
	targets.sort_custom(func(a, b): return a.distance < b.distance)
	return targets.slice(0, 3)

func call_linked_fire() -> bool:
	if phase != "DAY" or paused or tick < linked_fire_ready: return false
	var targets := linked_fire_targets()
	if targets.is_empty(): return false
	var lead = staff.filter(func(member): return member.get("crew_id", "") == "kilnkeeper")[0]
	linked_fire_origin = lead.pos
	linked_fire_stoves.clear()
	for target in targets:
		var pot: Dictionary = target.chef.task
		pot.stage = "ACTION"
		pot.linked = true
		var remaining := maxi(1, int(pot.done_tick) - tick)
		pot.started_tick = tick
		pot.done_tick = tick + maxi(1, roundi(remaining * .55))
		linked_fire_stoves.append(Grid.vec(target.stove.pos))
	linked_fire_ready = tick + Rules.ticks(LINKED_FIRE_COOLDOWN, tick_ms)
	linked_fire_until = tick + Rules.ticks(.80, tick_ms)
	return true

func call_current() -> bool:
	if phase != "DAY" or paused or tick < current_ready: return false
	if not crew_lineup.is_empty() and not crew_on_duty("ferrier", "waiter"): return false
	current_cell = Grid.vec(Grid.find(layout, "pass").pos)
	current_until = tick + Rules.ticks(8.0, tick_ms)
	current_ready = tick + Rules.ticks(28.0, tick_ms)
	return true

var modifiers: Dictionary = {}
var qualities: Dictionary = {}
var arrival_plan: Array = []
var arrival_cursor = 0
var guest_queues: Dictionary = {}
var queue_heads: Dictionary = {}
var queued_people = 0
var parties: Dictionary = {}
var customers: Dictionary = {}
var active_customers: Dictionary = {}
var orders: Dictionary = {}
var foods: Dictionary = {}
var staff: Array = []
var seats: Dictionary = {}
var seat_cells: Dictionary = {}
var tables_by_size: Dictionary = {}
var table_slots: Dictionary = {}
var navigation: Dictionary = {}
var service_routes = ServiceRoutes.new()
var idle_walk_rng: RandomNumberGenerator
var idle_walk_aisles := {}
var idle_walk_stops := {}
var stoves: Dictionary = {}
var stats: Dictionary = {}
var next_order_id = 1
var next_food_id = 1
var waiter_order_limit := 1
var waiter_food_limit := 1
var chef_carry_limit := 1
var stove_capacity := 0
var pass_capacity := 0
var guest_walk_speed := 2.0
var chef_walk_speed := 2.5
var revision = 0

func _init(data: Dictionary = {}) -> void:
	catalog = Catalog.load_all() if data.is_empty() else data
	if not catalog.errors.is_empty(): return
	chapter = catalog.chapter
	recipes = catalog.recipes
	buff_defs = catalog.buffs
	guest_defs = catalog.guests
	relic_defs = catalog.relics
	decoration_defs = catalog.decorations
	tick_ms = int(chapter.simulation_tick_ms)
	day_ticks = Rules.ticks(float(chapter.day_duration_seconds), tick_ms)
	midnight_ticks = day_ticks + Rules.ticks(float(chapter.day_duration_seconds) / 4.0, tick_ms)
	new_run()

func new_run(new_seed: int = 123456) -> void:
	seed_value = new_seed
	day = 1
	phase = "NIGHT"
	gold = int(chapter.initial_gold)
	reputation = int(chapter.initial_reputation)
	total_reputation = 0
	stars = 0
	owned_relics = []
	legacy_trophies = []
	trophy_draws_total = 0
	trophy_draws_today = 0
	last_trophy_id = ""
	attributes = chapter.initial_attributes.duplicate(true)
	for key in attributes: attributes[key] = int(attributes[key])
	upgrade_purchases = {}
	for key in attributes: upgrade_purchases[key] = 0
	owned_recipes = chapter.initial_menu.duplicate()
	menu = owned_recipes.duplicate()
	layout = chapter.initial_layout.duplicate(true)
	layout.plots = chapter.land_plots.duplicate(true)
	layout.unlocked_plots = []
	buff_states = {}
	buff_bag = []
	reports = []
	last_report = {}
	major_event_claims = []
	major_event_views = []
	night_spend = 0
	tick = 0
	customers.clear()
	active_customers.clear()
	orders.clear()
	foods.clear()
	staff.clear()
	seats.clear()
	stoves.clear()
	stats.clear()
	arrival_plan = []
	arrival_cursor = 0
	_reset_seating()
	modifiers = {}
	qualities = {}
	shop_rng.seed = abs(hash("%d/shop" % seed_value))
	trophy_rng.seed = abs(hash("%d/trophy" % seed_value))
	_refresh_shop()
	revision += 1

func _rng(domain: String) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = abs(hash("%d/%d/%s" % [seed_value, day, domain]))
	return rng

func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var value = array[i]
		array[i] = array[j]
		array[j] = value

func events_for(for_day: int = -1) -> Array:
	if for_day < 0:
		for_day = day
	var result = []
	for entry in chapter.calendar:
		var first = int(entry.day)
		var last = first + int(entry.get("duration_days", 1)) - 1
		if for_day >= first and for_day <= last:
			var event = chapter.events[entry.event].duplicate(true)
			event.id = entry.event
			event.from_day = first
			event.to_day = last
			result.append(event)
	return result

func weather_for(for_day := -1) -> Dictionary:
	var date = int(day) if for_day < 0 else int(for_day)
	var weather = chapter.weather
	var id = str(weather.default)
	for entry in weather.calendar:
		var first = int(entry.day)
		if date >= first and date < first + int(entry.get("duration_days", 1)):
			id = str(entry.weather)
	for entry in chapter.calendar:
		var first = int(entry.day)
		if date < first or date >= first + int(entry.get("duration_days", 1)): continue
		var event = chapter.events[entry.event]
		if event.has("weather"): id = str(event.weather)
	return {"id": id, "preset": weather.presets[id]}

func staff_member(id: int) -> Dictionary:
	return staff[id - 1] if id > 0 and id <= staff.size() else {}

func major_events_for(for_day: int = -1) -> Array:
	return events_for(for_day).filter(func(event): return event.has("notice"))

func confirm_major_event(id: String) -> Dictionary:
	if phase != "NIGHT": return {"ok":false,"error":tr("请在夜晚确认重大事件")}
	for event in major_events_for():
		if event.id != id: continue
		if id in major_event_claims: return {"ok":true,"grant":{}}
		var grant = event.notice.get("grant", {})
		_credit_event(grant)
		major_event_claims.append(id)
		revision += 1
		return {"ok":true,"grant":grant}
	return {"ok":false,"error":tr("这个重大事件已结束或尚未开始")}

func _credit_event(grant: Dictionary) -> void:
	gold += int(grant.get("gold", 0))
	var award = int(grant.get("reputation", 0))
	reputation += award
	total_reputation += award

func event_challenge(event: Dictionary, current: Dictionary = {}) -> Dictionary:
	var goal = event.notice.get("goal", {})
	if goal.is_empty(): return {}
	var earned = {}
	for report in reports: earned[int(report.day)] = int(report.stars_earned)
	if not current.is_empty(): earned[int(current.day)] = int(current.stars_earned)
	var days = []
	var passed = 0
	var required = int(goal.daily_stars)
	for date in range(int(event.from_day), int(event.to_day) + 1):
		var value = int(earned.get(date, -1))
		days.append({"day":date,"stars":value})
		if value >= required: passed += 1
	var finished = earned.has(int(event.to_day))
	return {"name":event.name,"days":days,"passed":passed,"required":required,"finished":finished,"success":finished and passed == days.size(),"reward":goal.reward}

func next_rent() -> Dictionary:
	for rent in chapter.rent_schedule:
		if int(rent.day) >= day and not (phase == "REPORT" and int(rent.day) == day):
			return rent
	return {}

func _reserved_plot_gifts(key: String) -> int:
	var reserved = 0
	for plot in chapter.land_plots:
		if plot.id in layout.unlocked_plots: continue
		if key == "chefs": reserved += int(plot.grant_chefs)
		elif key == "tables":
			for f in plot.fixtures:
				if f.type == "table": reserved += Grid.table_size(f)
	return reserved

func next_land_plot() -> Dictionary:
	var index = layout.unlocked_plots.size()
	return chapter.land_plots[index] if index < chapter.land_plots.size() else {}

func land_plot_status(id: String) -> Dictionary:
	if phase != "NIGHT": return {"ok":false,"error":tr("只能在夜晚解锁地块")}
	for plot in chapter.land_plots:
		if str(plot.id)!=id: continue
		if id in layout.unlocked_plots: return {"ok":false,"error":tr("该地块已经解锁")}
		if str(next_land_plot().get("id",""))!=id: return {"ok":false,"error":tr("需按顺序先解锁前面的地块")}
		if day < int(plot.unlock_day): return {"ok":false,"error":tr("第 %d 天解锁") % int(plot.unlock_day)}
		if stars < int(plot.star_cost): return {"ok":false,"error":tr("闪星不足，还差 %d") % (int(plot.star_cost)-stars)}
		return {"ok":true,"error":""}
	return {"ok":false,"error":tr("地块不存在")}

func unlock_land_plot(id: String) -> Dictionary:
	var status = land_plot_status(id)
	if not status.ok: return status
	var plot = next_land_plot()
	var updated = layout.duplicate(true)
	updated.unlocked_plots.append(id)
	var added_tables = 0
	var awarded = []
	for fixture in plot.fixtures:
		updated.facilities.append(fixture.duplicate(true))
		if fixture.type == "table": added_tables += Grid.table_size(fixture)
		if fixture.type == "trophy": awarded.append(str(fixture.relic_id))
	if int(attributes.chefs)+int(plot.grant_chefs)>int(chapter.attribute_caps.chefs) or int(attributes.tables)+added_tables>int(chapter.attribute_caps.tables):
		return {"ok":false,"error":tr("赠送家具超过本章容量，请检查配置")}
	if Grid.facilities(updated,"trophy").size()>int(attributes.relic_slots): return {"ok":false,"error":tr("奖杯展示位不足")}
	var route_errors = Grid.errors(updated)
	if not route_errors.is_empty(): return {"ok":false,"error":tr("地块通路冲突：")+str(route_errors[0])}
	stars -= int(plot.star_cost)
	layout = updated
	attributes.chefs += int(plot.grant_chefs)
	attributes.tables += added_tables
	for relic_id in awarded:
		if relic_id not in owned_relics: owned_relics.append(relic_id)
	revision += 1
	return {"ok":true,"plot":id}

func upgrade_gate(key: String) -> Dictionary:
	var gate = chapter.upgrade_unlocks[key]
	var unlock = int(gate.unlock_day)
	if unlock > 0 and day < unlock:
		return {"ok":false,"error":tr("第 %d 天解锁") % unlock}
	var cap = 0
	var next_day = 0
	for entry in gate.purchase_caps:
		if day >= int(entry.day): cap = int(entry.max_purchases)
		elif next_day == 0: next_day = int(entry.day)
	var purchased = int(upgrade_purchases.get(key,0))
	if int(attributes[key]) >= int(chapter.attribute_caps[key]) - _reserved_plot_gifts(key):
		return {"ok":false,"error":tr("预留地块赠送容量，请先解锁场地")}
	if cap > 0 and purchased >= cap:
		return {"ok":false,"error":tr("本阶段已达上限") + (tr(" · 第 %d 天开放更多") % next_day if next_day > 0 else "")}
	return {"ok":true,"error":""}

func upgrade_progression() -> Dictionary:
	var visible = []
	var next_key = ""
	var next_day = int(chapter.chapter_days) + 1
	for key in UPGRADE_ORDER:
		var unlock = int(chapter.upgrade_unlocks[key].unlock_day)
		if unlock <= day: visible.append(key)
		elif unlock < next_day:
			next_key = key
			next_day = unlock
	return {"unlocked": visible, "next_key": next_key, "next_day": next_day}

func upgrade_cost(key: String) -> int:
	var rule = chapter.upgrade_rules[key]
	var level = int(upgrade_purchases.get(key,0))
	return int(rule.first_cost + level * int(rule.increment))

func upgrade_gold_cost(key: String) -> int:
	var rule = chapter.upgrade_rules[key]
	return int(rule.first_gold) + int(upgrade_purchases.get(key, 0)) * int(rule.gold_increment)

func upgrade_status(key: String) -> Dictionary:
	if phase != "NIGHT" or not attributes.has(key):
		return {"ok": false, "error": tr("仅能在夜晚扩容")}
	if attributes[key] >= chapter.attribute_caps[key]:
		return {"ok": false, "error": tr("已达到本章上限")}
	var gate = upgrade_gate(key)
	if not gate.ok: return gate
	var missing: Array[String] = []
	var rep_cost = upgrade_cost(key)
	var gold_cost = upgrade_gold_cost(key)
	if reputation < rep_cost: missing.append(tr("%d 声望") % (rep_cost - reputation))
	if gold < gold_cost: missing.append(tr("%d 金币") % (gold_cost - gold))
	if not missing.is_empty(): return {"ok": false, "error": tr("还差 ") + tr("和").join(missing)}
	return {"ok": true, "error": ""}

func upgrade(key: String) -> Dictionary:
	var status = upgrade_status(key)
	if not status.ok: return status
	var gold_cost = upgrade_gold_cost(key)
	gold -= gold_cost
	reputation -= upgrade_cost(key)
	night_spend += gold_cost
	var new_cap = int(chapter.attribute_caps[key]) - _reserved_plot_gifts(key)
	attributes[key] = mini(new_cap, int(attributes[key]) + int(chapter.upgrade_rules[key].get("step", 1)))
	upgrade_purchases[key] = int(upgrade_purchases.get(key, 0)) + 1
	var facility_id = ""
	if key == "tables" or key == "chefs":
		var kind = "table" if key == "tables" else "stove"
		facility_id = "%s_%d" % [kind, attributes[key]]
		var fixture = {"id": facility_id, "type": kind, "name": ("餐桌 " if kind == "table" else "灶台 ") + str(attributes[key]), "pos": [-1, -1]}
		layout.facilities.append(fixture)
		if kind == "table": _auto_place_table(fixture)
	revision += 1
	return {"ok": true, "facility_id": facility_id}

func _auto_place_table(fixture: Dictionary) -> void:
	var region = Grid.walkable_region(layout)
	var candidates = region.keys()
	var entrance = Vector2i(Grid.vec(layout.entrance))
	candidates.sort_custom(func(a, b):
		var da = (a - entrance).length_squared()
		var db = (b - entrance).length_squared()
		return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x)
	)
	for cell in candidates:
		if cell == entrance or cell == Vector2i(Grid.vec(layout.exit)): continue
		if _place_fixture(layout, fixture, cell): return

func purchase_unlocked() -> bool:
	return "purchase_annex" in layout.get("unlocked_plots", [])

func decoration_shop_unlocked() -> bool:
	return "decor_studio" in layout.get("unlocked_plots", [])

func buy_decoration(id: String) -> Dictionary:
	if phase != "NIGHT" or not decoration_shop_unlocked():
		return {"ok": false, "error": tr("装饰商店尚未开放")}
	if not decoration_defs.has(id):
		return {"ok": false, "error": tr("该装饰不存在")}
	var definition = decoration_defs[id]
	var price = int(definition.star_cost)
	if stars < price:
		return {"ok": false, "error": tr("闪星不足，还差 %d") % (price - stars)}
	var facility_id = _next_fixture_id(layout, "decoration")
	layout.facilities.append({
		"id": facility_id, "type": "decoration", "name": definition.name,
		"decoration_id": id, "extent": definition.extent.duplicate(),
		"pos": [-1, -1], "rotation": 0,
	})
	stars -= price
	revision += 1
	return {"ok": true, "facility_id": facility_id}

func decoration_can_place(preview: Dictionary) -> bool:
	var board = layout.duplicate()
	board.facilities = layout.facilities.duplicate()
	for index in range(board.facilities.size()):
		if board.facilities[index].id == preview.id:
			board.facilities[index] = preview
			return Grid.errors(board).is_empty()
	return false

func move_facility(id: String, cell: Vector2i, decoration_turns := -1) -> Dictionary:
	if phase != "NIGHT":
		return {"ok": false, "error": tr("营业中不能移动设施")}
	var target = Grid.find(layout, id)
	if target.is_empty():
		return {"ok": false, "error": tr("未找到设施")}
	if not Grid.locked_plot_at(layout,cell).is_empty(): return {"ok":false,"error":tr("该地块尚未解锁")}
	if Grid.structural_blocked(layout,cell):
		return {"ok": false, "error": tr("不能放在墙体或地图边界")}
	if target.type == "trophy":
		var zone = chapter.trophy_zone
		if cell.x < int(zone.left) or cell.x > int(zone.right) or cell.y < int(zone.top) or cell.y > int(zone.bottom):
			return {"ok":false,"error":tr("奖杯仅能放在展廊展示区")}
		if not Grid.placed(target) and Grid.facilities(layout,"trophy").size() >= int(attributes.relic_slots):
			return {"ok":false,"error":tr("奖杯展示位已满，请升级容量或收起奖杯")}
	var occupant = Grid.facility_at(layout, cell)
	if not occupant.is_empty() and occupant.id != id:
		if target.type == "table" and occupant.type == "table": return _merge_tables(target, occupant)
		return {"ok": false, "error": tr("这个格子已有设施")}
	var prior_turns = Grid.rotation(target)
	if target.type == "decoration" and decoration_turns >= 0: target.rotation = posmod(decoration_turns, 4)
	if not _place_fixture(layout, target, cell):
		if target.type == "decoration": target.rotation = prior_turns
		return {"ok":false,"error":tr("此处没有足够空间，或会阻断通路和设施交互")}
	revision += 1
	return {"ok": true}

func _merge_tables(source: Dictionary, target: Dictionary) -> Dictionary:
	var result = preview_table_merge(source, target)
	if not result.ok: return result
	layout = result.layout
	result.erase("layout")
	revision += 1
	return result

func trophy_placement_cells(id: String) -> Dictionary:
	if phase != "NIGHT" or not trophy_shop_unlocked(): return {}
	var fixture = Grid.find(layout, id)
	if fixture.get("type") != "trophy": return {}
	if not Grid.placed(fixture) and Grid.facilities(layout, "trophy").size() >= int(attributes.relic_slots):
		return {}
	var preview = layout.duplicate(true)
	var target = Grid.find(preview, id)
	var original = target.pos
	var zone = chapter.trophy_zone
	var cells := {}
	for y in range(int(zone.top), int(zone.bottom) + 1):
		for x in range(int(zone.left), int(zone.right) + 1):
			var cell = Vector2i(x, y)
			if Grid.structural_blocked(preview, cell): continue
			var occupant = Grid.facility_at(preview, cell)
			if not occupant.is_empty() and occupant.id != id: continue
			if _place_fixture(preview, target, cell): cells[cell] = true
			target.pos = original
	return cells

# The guide can highlight a pair that works on the current layout without moving anything.
func preview_table_merge(source: Dictionary, target: Dictionary) -> Dictionary:
	var size = Grid.table_size(source)
	if size == 4 or size != Grid.table_size(target):
		return {"ok":false,"error":tr("两张单人桌或两张双人桌才能合成")}
	var updated = layout.duplicate(true)
	updated.facilities.erase(Grid.find(updated, str(source.id)))
	var merged = Grid.find(updated, str(target.id))
	merged.capacity = size * 2
	merged.name = Grid.table_label(merged.capacity)
	if not _place_fixture(updated, merged, Vector2i(Grid.vec(merged.pos))):
		return {"ok":false,"error":tr("空间不足，放不下%s。请留出桌面和座位的通路。") % merged.name}
	return {"ok":true,"facility_id":str(merged.id),"merged_size":int(merged.capacity),"layout":updated}

func split_facility(id: String) -> Dictionary:
	if phase != "NIGHT": return {"ok":false,"error":tr("仅能在夜晚拆分餐桌")}
	var table = Grid.find(layout, id)
	if not Grid.can_split(table): return {"ok":false,"error":tr("请选择双人桌或四人桌")}
	var updated = layout.duplicate(true)
	var first = Grid.find(updated, id)
	var size = Grid.table_size(first)
	var half = size >> 1
	var second = first.duplicate(true)
	second.id = _next_fixture_id(updated, "split_table")
	for piece in [first, second]:
		piece.capacity = half
		piece.name = Grid.table_label(half)
	if Grid.placed(table):
		var cell = Vector2i(Grid.vec(table.pos))
		var turns = Grid.rotation(table)
		if size == 2:
			cell += Vector2i.RIGHT if turns % 2 == 0 else Vector2i.DOWN
		else:
			cell += Vector2i.DOWN if turns % 2 == 0 else Vector2i.RIGHT
			# Keep both sets of seats facing out of the original table footprint.
			var opposite = (turns + 2) % Grid.FACING.size()
			if Grid.FACING[turns] in [Vector2i.DOWN, Vector2i.RIGHT]: first.rotation = opposite
			else: second.rotation = opposite
		second.pos = [cell.x, cell.y]
	updated.facilities.append(second)
	if not Grid.errors(updated).is_empty(): return {"ok":false,"error":tr("拆分后的桌位无法通行")}
	layout = updated
	revision += 1
	return {"ok":true,"facility_id":id,"second_id":str(second.id),"size":half}

func _next_fixture_id(board: Dictionary, prefix: String) -> String:
	var counter = "next_%s_id" % prefix
	var serial = maxi(1, int(board.get(counter, 1)))
	var id = "%s_%d" % [prefix, serial]
	while not Grid.find(board, id).is_empty():
		serial += 1
		id = "%s_%d" % [prefix, serial]
	board[counter] = serial + 1
	return id

func wall_placement_status(cell: Vector2i) -> Dictionary:
	return wall_row_status([cell])

func wall_row_status(cells: Array) -> Dictionary:
	if phase != "NIGHT": return {"ok":false,"error":tr("仅能在夜晚建造墙体")}
	if cells.is_empty(): return {"ok":false,"error":tr("请在餐厅内选定墙体位置")}
	var interior = Rect2i(1, 1, int(layout.width) - 2, int(layout.height) - 2)
	var obstacles = Grid.solid_cells(layout)
	for cell in cells:
		if not cell is Vector2i or not interior.has_point(cell): return {"ok":false,"error":tr("墙体需要放在室内空格")}
		if not Grid.locked_plot_at(layout, cell).is_empty(): return {"ok":false,"error":tr("该地块尚未解锁")}
		if obstacles.has(cell): return {"ok":false,"error":tr("墙体需要放在室内空格")}
		obstacles[cell] = true
	if not Grid.errors(layout, obstacles).is_empty(): return {"ok":false,"error":tr("墙体会阻断通路、座位或员工站位")}
	return {"ok":true}

func place_wall(cell: Vector2i) -> Dictionary:
	return place_wall_row([cell])

func place_wall_row(cells: Array, turns: int = 0) -> Dictionary:
	var status = wall_row_status(cells)
	if not status.ok: return status
	var ids = []
	for cell in cells:
		var id = _next_fixture_id(layout, "wall")
		layout.facilities.append({"id":id,"type":"wall","name":"木纹隔墙","pos":[cell.x, cell.y],"rotation":posmod(turns, 4)})
		ids.append(id)
	revision += 1
	return {"ok":true,"facility_id":ids[0],"count":ids.size()}

func stored_facilities(kind: String = "") -> Array:
	return layout.facilities.filter(func(f):
		return f.type in ["table", "stove", "trophy", "decoration"] and not Grid.placed(f) and (kind.is_empty() or f.type == kind)
	)

func _place_fixture(board: Dictionary, fixture: Dictionary, cell: Vector2i, rotate_only: bool = false) -> bool:
	var previous = fixture.pos
	var previous_rotation = fixture.get("rotation")
	var start = Grid.rotation(fixture)
	var count = Grid.FACING.size() if Grid.can_rotate(fixture) and (fixture.type != "decoration" or rotate_only) else 1
	fixture.pos = [cell.x, cell.y]
	for turn in range(1 if rotate_only else 0, count):
		if turn > 0: fixture.rotation = (start + turn) % count
		if Grid.errors(board).is_empty(): return true
	fixture.pos = previous
	if previous_rotation == null: fixture.erase("rotation")
	else: fixture.rotation = previous_rotation
	return false

func rotate_facility(id: String) -> Dictionary:
	if phase != "NIGHT": return {"ok":false,"error":tr("仅能在夜晚旋转设施")}
	var facility = Grid.find(layout, id)
	if not Grid.can_rotate(facility): return {"ok":false,"error":tr("这件设施不可旋转")}
	if Grid.placed(facility):
		if not _place_fixture(layout, facility, Vector2i(Grid.vec(facility.pos)), true):
			return {"ok":false,"error":tr("其他朝向没有足够空间或无法通行")}
	else:
		facility.rotation = (Grid.rotation(facility) + 1) % Grid.FACING.size()
	revision += 1
	return {"ok":true}

func move_staff(role: String, index: int, cell: Vector2i) -> Dictionary:
	if phase != "NIGHT": return {"ok":false,"error":tr("仅能在夜晚调整员工站位")}
	if role not in ["chef", "waiter"] or index < 0 or index >= int(attributes[role + "s"]):
		return {"ok":false,"error":tr("未找到员工")}
	var region = Grid.walkable_region(layout)
	if not region.has(cell) or cell in [Vector2i(Grid.vec(layout.entrance)), Vector2i(Grid.vec(layout.exit))]:
		return {"ok":false,"error":tr("请选择可通行的室内空格")}
	var positions = Grid.staff_positions(layout, attributes, region)
	for other_role in positions:
		var other_index = positions[other_role].find(cell)
		if other_index >= 0 and (other_role != role or other_index != index):
			return {"ok":false,"error":tr("这个格子已有员工")}
	var previous = positions[role][index]
	if previous == cell: return {"ok":true}
	positions[role][index] = cell
	for staff_role in positions:
		var key = staff_role + "_starts"
		var starts = positions[staff_role].map(func(position): return [position.x, position.y])
		var configured = layout.get(key, [])
		for future_index in range(starts.size(), configured.size()):
			var reserved = Vector2i(Grid.vec(configured[future_index]))
			starts.append([previous.x, previous.y] if reserved == cell else configured[future_index])
		layout[key] = starts
	revision += 1
	return {"ok":true}

func store_facility(id: String) -> Dictionary:
	var target = Grid.find(layout, id)
	if phase != "NIGHT" or not Grid.can_store(target):
		return {"ok": false, "error": tr("仅能在夜晚收起餐桌、灶台、奖杯或自建墙体")}
	if target.type == "wall": layout.facilities.erase(target)
	else: target.pos = [-1, -1]
	revision += 1
	return {"ok": true}

func opening_errors() -> Array:
	var errors = Grid.errors(layout)
	if menu.is_empty() or menu.size() > int(attributes.menu_slots):
		errors.append(tr("至少上架一道菜，且不能超出菜单容量"))
	if Grid.facilities(layout, "table").is_empty():
		errors.append(tr("至少放置一张餐桌"))
	if Grid.facilities(layout, "stove").size() < int(attributes.chefs):
		errors.append(tr("每位厨师需要一个已放置的灶台"))
	if Grid.facilities(layout,"trophy").size() > int(attributes.relic_slots):
		errors.append(tr("展示的奖杯超过当前遗物上限"))
	for relic in Grid.facilities(layout,"trophy"):
		var cell = Vector2i(Grid.vec(relic.pos))
		var zone = chapter.trophy_zone
		if cell.x < int(zone.left) or cell.x > int(zone.right) or cell.y < int(zone.top) or cell.y > int(zone.bottom):
			errors.append(tr("奖杯超出右上展示区"))
	if Grid.facilities(layout, "pass").size() != 1 or Grid.facilities(layout, "order").size() != 1:
		errors.append(tr("需要一个订单口与一个出餐口"))
	return errors

func change_menu(slot: int, recipe_id: String) -> Dictionary:
	if phase != "NIGHT" or recipe_id not in owned_recipes:
		return {"ok": false, "error": tr("仅可在夜晚更换已拥有菜谱")}
	if recipe_id in menu:
		return {"ok": false, "error": tr("这道菜已上架")}
	if slot < 0 or slot > menu.size() or slot >= int(attributes.menu_slots):
		return {"ok": false, "error": tr("无可用菜单槽位")}
	if slot == menu.size():
		menu.append(recipe_id)
	else:
		menu[slot] = recipe_id
	revision += 1
	return {"ok": true}

func remove_menu(slot: int) -> Dictionary:
	if phase != "NIGHT" or menu.size() <= 1 or slot < 0 or slot >= menu.size():
		return {"ok": false, "error": tr("至少保留一道上架菜")}
	menu.remove_at(slot)
	revision += 1
	return {"ok": true}

func _refresh_shop() -> void:
	shop.clear()
	var available_recipes = []
	for id in recipes:
		var r = recipes[id]
		if id not in owned_recipes and day >= int(r.offer_from_day) and day <= int(r.offer_until_day):
			available_recipes.append(id)
	if available_recipes.is_empty():
		shop.append({"type": "empty", "id": "", "price": 0, "bought": false})
	else:
		var id = available_recipes[shop_rng.randi_range(0, available_recipes.size() - 1)]
		shop.append({"type": "recipe", "id": id, "price": int(recipes[id].unlock_cost), "bought": false})
	var selected = []
	for index in range(2):
		var id = ""
		var guaranteed = false
		for offer_day in chapter.get("guaranteed_traffic_offer_days", []):
			if int(offer_day) == day: guaranteed = true
		if index == 0 and guaranteed and int(buff_states.get("crowd_magnet", {}).get("stack_count", 0)) < int(buff_defs.crowd_magnet.max_stacks):
			id = "crowd_magnet"
			buff_bag.erase(id)
		else:
			id = _draw_buff(selected)
		if id.is_empty():
			shop.append({"type": "empty_buff", "id": "", "price": 0, "bought": false})
		else:
			selected.append(id)
			var layers = int(buff_states.get(id, {}).get("stack_count", 0))
			var price = int(ceil(buff_defs[id].base_cost * (1.0 + buff_defs[id].stack_cost_growth * layers)))
			shop.append({"type": "buff", "id": id, "price": price, "bought": false})

func _draw_buff(excluded: Array) -> String:
	var eligible = []
	for id in buff_defs:
		if buff_defs[id].offer_enabled and id not in excluded and int(buff_states.get(id, {}).get("stack_count", 0)) < int(buff_defs[id].max_stacks):
			eligible.append(id)
	var tier = _weighted_shop_items(eligible, buff_defs, "level", _shop_weights(chapter.buff_shop_weights), shop_rng)
	if tier.is_empty(): return ""
	var bag_index = _first_in_buff_bag(tier)
	if bag_index < 0:
		_shuffle(tier, shop_rng)
		bag_index = buff_bag.size()
		buff_bag.append_array(tier)
	return str(buff_bag.pop_at(bag_index))

func _first_in_buff_bag(eligible: Array) -> int:
	for i in range(buff_bag.size()):
		if buff_bag[i] in eligible: return i
	return -1

func _shop_weights(stages: Array) -> Dictionary:
	var weights = stages[0].weights
	for stage in stages:
		if day < int(stage.from_day): break
		weights = stage.weights
	return weights

func _weighted_shop_items(candidates: Array, definitions: Dictionary, field: String, weights: Dictionary, rng: RandomNumberGenerator) -> Array:
	var groups = {}
	var total = 0
	for id in candidates:
		var level = str(int(definitions[id][field]))
		var weight = int(weights.get(level, 0))
		if weight <= 0: continue
		if not groups.has(level):
			groups[level] = []
			total += weight
		groups[level].append(id)
	if total == 0: return []
	var roll = rng.randi_range(1, total)
	for level in groups:
		roll -= int(weights[level])
		if roll <= 0: return groups[level]
	return []

func purchase_spent() -> bool:
	return shop.any(func(offer): return bool(offer.bought))

func purchase_offer_status(index: int) -> Dictionary:
	if not purchase_unlocked():
		return {"ok": false, "error": tr("先解锁采购小厅")}
	if phase != "NIGHT" or index < 0 or index >= shop.size():
		return {"ok": false, "error": tr("仅在夜晚购买")}
	var offer = shop[index]
	if offer.type in ["empty", "empty_buff"]:
		return {"ok": false, "error": "暂无商品"}
	if purchase_spent():
		return {"ok": false, "error": "今日已采购，明晚有新货"}
	if gold < int(offer.price):
		return {"ok": false, "error": "金币不足，还差 %d" % (int(offer.price) - gold)}
	if offer.type == "recipe" and offer.id in owned_recipes:
		return {"ok": false, "error": "已拥有该菜谱"}
	if offer.type == "buff" and int(buff_states.get(offer.id, {}).get("stack_count", 0)) >= int(buff_defs[offer.id].max_stacks):
		return {"ok": false, "error": "该增益已达层数上限"}
	return {"ok": true}

func buy_offer(index: int, replacement: int = -1) -> Dictionary:
	var status = purchase_offer_status(index)
	if not status.ok: return status
	var offer = shop[index]
	if offer.type == "recipe":
		if menu.size() >= int(attributes.menu_slots) and replacement < 0:
			return {"ok": false, "needs_replacement": true, "error": tr("选择要替换的菜品，确认后才扣款")}
		if replacement >= menu.size():
			return {"ok": false, "error": tr("替换槽位无效")}
		gold -= int(offer.price)
		owned_recipes.append(offer.id)
		if menu.size() < int(attributes.menu_slots):
			menu.append(offer.id)
		else:
			menu[replacement] = offer.id
	else:
		var result = grant_buff(offer.id, int(buff_defs[offer.id].duration_days))
		if not result.ok:
			return result
		gold -= int(offer.price)
	offer.bought = true
	night_spend += int(offer.price)
	revision += 1
	return {"ok": true}

func grant_buff(id: String, days: int) -> Dictionary:
	if not buff_defs.has(id) or days < 1 or phase != "NIGHT":
		return {"ok": false, "error": tr("Buff 授予参数 / 阶段无效")}
	var old = buff_states.get(id, {"stack_count": 0, "remaining_days": 0})
	if int(old.stack_count) >= int(buff_defs[id].max_stacks):
		return {"ok": false, "error": tr("该 Buff 已达层数上限")}
	buff_states[id] = {"stack_count": int(old.stack_count) + 1, "remaining_days": int(old.remaining_days) + days}
	return {"ok": true}

func displayed_trophy_effects() -> Dictionary:
	var best = {}
	for fixture in Grid.facilities(layout, "trophy"):
		var item = relic_defs[str(fixture.relic_id)]
		var effect = str(item.effect_type)
		if not best.has(effect) or int(item.rarity) > int(best[effect].rarity):
			best[effect] = item
	return best

func effective_modifiers() -> Dictionary:
	var total = Rules.modifier(buff_states, buff_defs)
	var displayed = displayed_trophy_effects()
	for effect in displayed:
		var item = displayed[effect]
		if item.has("chance"):
			total[effect] = {"chance": float(item.chance), "value": float(item.effect_value)}
		else:
			total[effect] = total.get(effect, 0) + item.effect_value
	total.quality_expectation_add = 0.0
	for event in major_events_for():
		total.price_pct += float(event.get("payment_pct", 0))
		total.quality_expectation_add += float(event.get("quality_expectation_add", 0))
	return total

func preview_quality(recipe_id: String) -> float:
	var m = effective_modifiers()
	return Rules.quality(float(recipes[recipe_id].base_quality_multiplier), int(m.quality), chapter, float(m.get("quality_bonus", 0.0)))

func fixture_bonus(id: String, effect: String) -> float:
	return float(local_effects.fixtures.get(id, {}).get(effect, 0.0))

func _decorated_quality(quality: float, bonus: float) -> float:
	return clampf(quality * (1.0 + bonus), chapter.quality_rules.minimum, chapter.quality_rules.maximum)

func meal_price(recipe_id: String, quality: float, pricing: Dictionary, guest: Dictionary = {}, table := "") -> int:
	var price_quality = quality
	if quality > 1.0:
		price_quality = 1.0 + (quality - 1.0) * float(chapter.quality_rules.price_bonus_scale)
	var multiplier = float(chapter.common_guest_template.payment_multiplier) * float(guest.get("type_payment_multiplier", 1.0))
	var base = int(recipes[recipe_id].base_value) + int(fixture_bonus(table, "group_base_gold"))
	var price_pct = float(pricing.price_pct) + fixture_bonus(table, "table_gold")
	return Rules.payment(base, price_quality, price_pct, multiplier, int(pricing.flat_gold), guest.get("payment_override", "") == "ZERO")

func start_day() -> Dictionary:
	if phase != "NIGHT":
		return {"ok": false, "error": tr("已经开店")}
	var errors = opening_errors()
	if not errors.is_empty():
		return {"ok": false, "error": "\n".join(errors)}
	phase = "DAY"
	current_until = 0
	current_ready = 0
	linked_fire_ready = 0
	linked_fire_until = 0
	linked_fire_stoves.clear()
	paused = false
	tick = 0
	customers = {}
	active_customers = {}
	orders = {}
	foods = {}
	staff = []
	stoves = {}
	arrival_cursor = 0
	_reset_seating()
	next_food_id = 1
	next_order_id = 1
	modifiers = effective_modifiers()
	waiter_order_limit = 1 + int(modifiers.get("waiter_orders", 0))
	waiter_food_limit = 1 + int(modifiers.get("waiter_food", 0))
	chef_carry_limit = int(chapter.movement.chef_carry_capacity) + int(modifiers.get("chef_carry", 0))
	stove_capacity = int(chapter.movement.stove_capacity) + int(modifiers.get("stove_space", 0))
	pass_capacity = int(chapter.movement.pass_capacity) + int(modifiers.get("pass_space", 0))
	guest_walk_speed = float(chapter.movement.guest_speed) * (1.0 + float(modifiers.get("guest_speed", 0.0)))
	chef_walk_speed = float(chapter.movement.chef_speed) * (1.0 + float(modifiers.get("chef_speed", 0.0)))
	trophy_yield_rng = _rng("trophy_yield") if modifiers.has("cook_yield") else null
	trophy_quality_rng = _rng("trophy_quality") if modifiers.has("cook_quality_roll") else null
	local_effects = Decor.build(layout, decoration_defs)
	qualities = {}
	for id in menu:
		qualities[id] = Rules.quality(float(recipes[id].base_quality_multiplier), int(modifiers.quality), chapter, float(modifiers.get("quality_bonus", 0.0)))
	stats = {"arrived": 0, "admitted": 0, "refused": 0, "refused_types": {}, "peak_queue": 0, "queue_waits": [], "completed": 0, "payer_count": 0, "income": 0, "income_recipes": {}, "income_guests": {}, "guest_checkout_counts": {}, "rep_base": 0, "rep_buff": 0, "wait_penalty_raw": 0, "wait_penalty_actual": 0, "quality_penalty_raw": 0, "quality_penalty_actual": 0, "funnel": {"R": 0, "Q": 0, "O": 0, "F": 0, "C": 0, "S": 0}, "closing_stages": {}, "produced": 0, "consumed": 0, "discarded": 0, "discard_reasons": {}, "food_waits": [], "order_waits": [], "seat_ticks": 0, "stove_ticks": 0, "night_spend": night_spend}
	stats.reputation_at_opening = reputation
	stats.completed_before_midnight = 0
	stats.refused_no_table = 0
	for event in major_events_for():
		if event.has("quality_inspection") and int(event.from_day) + int(event.special_visits[0].day_offset) == day:
			stats.quality_inspection = {"expected": int(event.special_visits[0].size), "served": 0, "quality_sum": 0.0}
			break
	navigation = Grid.solid_cells(layout)
	service_routes.prepare(layout, navigation)
	for f in Grid.facilities(layout, "table"):
		var cells = Grid.interaction_cells(f)
		var slots = []
		for index in range(cells.size()):
			var key = str(f.id) if cells.size() == 1 else "%s#%d" % [f.id, index + 1]
			seats[key] = 0
			seat_cells[key] = cells[index]
			slots.append(key)
		table_slots[f.id] = slots
		tables_by_size[cells.size()].append(f.id)
	for f in Grid.facilities(layout, "stove"):
		stoves[f.id] = {"owner": 0, "output_reserved": 0}
	_prepare_idle_walks()
	var positions = Grid.staff_positions(layout, attributes)
	for role in positions:
		var members := Crew.by_role(crew_lineup, role)
		for slot in range(positions[role].size()):
			var cell = positions[role][slot]
			var crew_id := str(members[slot]) if slot < members.size() else ""
			staff.append({"id": staff.size() + 1, "role": role, "crew_id": crew_id, "minion":helper_at(role,slot), "pos": Vector2(cell), "task": {}, "path": [], "carry_orders": [], "carry_food": [], "reason": "暂无任务", "time": {"move": 0, "cook": 0, "interact": 0, "idle": 0, "blocked": 0}})
			if role == "waiter":
				staff.back().idle_walk_after = _idle_walk_delay(2.6, 5.8)
	_build_arrivals()
	revision += 1
	return {"ok": true}

func _plot_gift_relics() -> Dictionary:
	var gifts = {}
	for plot in chapter.land_plots:
		for fixture in plot.fixtures:
			if fixture.type == "trophy": gifts[str(fixture.relic_id)] = true
	return gifts

func trophy_box_offer() -> Dictionary:
	var available: Array = [[], [], [], [], []]
	var gifts = _plot_gift_relics()
	var remaining = 0
	var already_owned = {}
	for id in owned_relics: already_owned[id] = true
	for id in relic_defs:
		if already_owned.has(id) or gifts.has(id): continue
		available[int(relic_defs[id].rarity) - 1].append(id)
		remaining += 1
	var config = chapter.trophy_box
	return {"gold": Trophies.price(config, trophy_draws_today), "remaining": remaining, "pools": available,
		"odds": Trophies.odds(config, day, trophy_draws_total, available)}

func trophy_shop_unlocked() -> bool:
	return "trophy_gallery" in layout.get("unlocked_plots", [])

func trophy_shop_cell() -> Vector2i:
	var fixture = Grid.find(layout, "trophy_shop")
	return Vector2i(Grid.vec(fixture.pos)) if not fixture.is_empty() else Vector2i(-1, -1)

func _add_trophy(id: String) -> void:
	owned_relics.append(id)
	layout.facilities.append({"id": "trophy_" + id, "type": "trophy", "relic_id": id, "name": relic_defs[id].name, "pos": [-1, -1]})

func draw_trophy() -> Dictionary:
	if phase != "NIGHT": return {"ok": false, "error": "夜晚才能打开盲盒"}
	if not trophy_shop_unlocked(): return {"ok": false, "error": "请先解锁奖杯展廊"}
	var offer = trophy_box_offer()
	if int(offer.remaining) == 0: return {"ok": false, "error": "盲盒奖杯已经集齐"}
	var cost = int(offer.gold)
	if gold < cost: return {"ok": false, "error": "金币不足，还差 %d" % (cost - gold)}
	var id = Trophies.sample(offer.pools, offer.odds, trophy_rng)
	_add_trophy(id)
	gold -= cost
	night_spend += cost
	trophy_draws_total += 1
	trophy_draws_today += 1
	last_trophy_id = id
	revision += 1
	return {"ok": true, "id": id, "facility_id": "trophy_" + id, "gold": cost}

func _weighted_guest(rarity: String, rng: RandomNumberGenerator) -> String:
	var sum_weights = 0
	for g in guest_defs.values():
		if g.rarity == rarity:
			sum_weights += int(g.pool_weight)
	var roll = rng.randi_range(1, maxi(1, sum_weights))
	for g in guest_defs.values():
		if g.rarity == rarity:
			roll -= int(g.pool_weight)
			if roll <= 0:
				return g.id
	return "normal"

func _clear_guest_queues() -> void:
	guest_queues = {1: [], 2: [], 4: []}
	queue_heads = {1: 0, 2: 0, 4: 0}
	queued_people = 0

func _reset_seating() -> void:
	_clear_guest_queues()
	parties.clear()
	seats.clear()
	seat_cells.clear()
	table_slots.clear()
	tables_by_size = {1: [], 2: [], 4: []}
	navigation.clear()

func _regular_visits(counts: Dictionary, rng: RandomNumberGenerator) -> Array:
	var visits = []
	for size in [2, 4]:
		for i in range(int(counts[str(size)])):
			var members = []
			for j in range(size): members.append(_weighted_guest("normal", rng))
			visits.append(members)
	for i in range(int(counts.normal)): visits.append([_weighted_guest("normal", rng)])
	for i in range(int(counts.rare)): visits.append([_weighted_guest("rare", rng)])
	_shuffle(visits, rng)
	return visits

func _regular_counts(events: Array) -> Dictionary:
	var normal_pct = 0.0
	var rare_pct = 0.0
	var normal_flat = 0
	var rare_flat = int(modifiers.get("rare_extra", 0))
	for event in events:
		normal_pct += float(event.get("normal_pct", 0.0))
		rare_pct += float(event.get("rare_pct", 0.0))
		normal_flat += int(event.get("normal_flat", 0))
		rare_flat += int(event.get("rare_flat", 0))
	var demand = chapter.base_customer_counts
	for tier in chapter.get("demand_curve", []):
		if day >= int(tier.from_day): demand = tier
	normal_pct += float(modifiers.normal_arrivals)
	var normal = Rules.customer_count(int(demand.normal), normal_pct, normal_flat)
	var counts = {"normal":normal, "rare":Rules.customer_count(int(demand.rare), rare_pct, rare_flat), "2":0, "4":0}
	for group in chapter.guest_groups:
		if day < int(group.from_day): continue
		var size = int(group.size)
		var count = mini(floori(float(counts.normal) / size), roundi(normal * float(group.share) / size))
		counts[str(size)] = count
		counts.normal -= count * size
	for event in events:
		for category in event.get("traffic", {}):
			var base = int(counts[category])
			var change = float(event.traffic[category])
			if base > 0 and change > 0:
				counts[category] = base + maxi(1, roundi(base * change))
			else:
				counts[category] = Rules.customer_count(base, change)
		if event.has("regular_traffic_multiplier"):
			var multiplier = float(event.regular_traffic_multiplier)
			var target = roundi((int(counts.normal) + int(counts.rare) + 2 * int(counts["2"]) + 4 * int(counts["4"])) * multiplier)
			for category in ["rare", "2", "4"]:
				counts[category] = roundi(int(counts[category]) * multiplier)
			counts.normal = maxi(0, target - int(counts.rare) - 2 * int(counts["2"]) - 4 * int(counts["4"]))
	return counts

func _build_arrivals() -> void:
	var events = events_for()
	var counts = _regular_counts(events)
	var visits = _regular_visits(counts, _rng("customer_types"))
	var people = int(counts.normal) + int(counts.rare) + int(counts["2"]) * 2 + int(counts["4"]) * 4
	arrival_plan = []
	var timing = _rng("arrival_times")
	var cutoff = int(floor(day_ticks * chapter.arrival_cutoff_ratio))
	var windows = [[1, cutoff, people]]
	for event in events:
		if not event.has("arrival_peak"): continue
		var peak = event.arrival_peak
		var peak_start = clampi(ceili((float(peak.start_minute) - 540) * day_ticks / 720.0), 1, cutoff - 1)
		var peak_end = clampi(ceili((float(peak.end_minute) - 540) * day_ticks / 720.0), peak_start + 1, cutoff)
		var peak_count = roundi(people * float(peak.share))
		var before_length = peak_start - 1
		var outside_length = before_length + cutoff - peak_end
		if outside_length <= 0: break
		var before_count = roundi(float(people - peak_count) * before_length / outside_length)
		windows = [[1, peak_start, before_count], [peak_start, peak_end, peak_count], [peak_end, cutoff, people - peak_count - before_count]]
		break
	for index in range(windows.size()):
		var window = windows[index]
		var scheduled = []
		var remaining = int(window[2])
		if index == windows.size() - 1:
			scheduled = visits
		else:
			while remaining > 0 and not visits.is_empty():
				var next = visits.find_custom(func(visit): return visit.size() <= remaining)
				if next < 0: break
				var visit = visits.pop_at(next)
				scheduled.append(visit)
				remaining -= visit.size()
		var window_size = int(window[1]) - int(window[0])
		for visit_index in range(scheduled.size()):
			var arrival_tick = int(window[0]) + mini(window_size - 1, floori((visit_index + timing.randf()) / scheduled.size() * window_size))
			var members = scheduled[visit_index]
			var leader = arrival_plan.size() + 1
			for type in members:
				var plan = {"id": arrival_plan.size() + 1, "type": type, "tick": arrival_tick}
				if members.size() > 1:
					plan.party_id = leader
					plan.party_size = members.size()
				arrival_plan.append(plan)
	for event in events:
		if not event.has("special_guest"): continue
		for visit in event.special_visits:
			if day == int(event.from_day) + int(visit.day_offset):
				_add_special_visit(str(event.special_guest), int(visit.size), float(visit.spawn_seconds))
	arrival_plan.sort_custom(func(a, b): return a.tick < b.tick or (a.tick == b.tick and a.id < b.id))

func _add_special_visit(guest_type: String, size: int, seconds: float) -> void:
	var arrival_tick = Rules.ticks(seconds, tick_ms)
	var leader = arrival_plan.size() + 1
	for member in range(size):
		var plan = {"id": leader + member, "type": guest_type, "tick": arrival_tick}
		if size > 1:
			plan.party_id = leader
			plan.party_size = size
		arrival_plan.append(plan)

# One real simulation tick represents an equal share of the 09:00?21:00 shift.
func clock_minutes() -> int:
	if phase == "NIGHT": return 9 * 60
	if phase == "REPORT": return 24 * 60
	return mini(24 * 60, 9 * 60 + int(floor(float(tick) * 12.0 * 60.0 / float(day_ticks))))

func clock_text() -> String:
	var minutes = clock_minutes()
	return "%02d:%02d" % [int(minutes / 60) % 24, minutes % 60]

func step() -> void:
	if phase != "DAY" or paused:
		return
	tick += 1
	if tick == day_ticks or tick == midnight_ticks:
		service_bell.emit(tick == midnight_ticks)
	if tick == midnight_ticks:
		_disperse_queue()
	var gone = []
	for c in active_customers.values():
		if c.state == "QUEUE": continue
		_advance_customer(c)
		if c.state == "GONE": gone.append(c.id)
	for id in gone: active_customers.erase(id)
	for s in staff:
		_advance_staff(s)
	for c in active_customers.values():
		if c.state == "READY" or c.state == "FOOD": _apply_patience(c)
	if tick < midnight_ticks: _assign_seats()
	while arrival_cursor < arrival_plan.size() and int(arrival_plan[arrival_cursor].tick) <= tick:
		var plan = arrival_plan[arrival_cursor]
		var size = int(plan.get("party_size", 1))
		if size == 1: _spawn_customer(plan)
		else: _spawn_party(arrival_plan.slice(arrival_cursor, arrival_cursor + size))
		arrival_cursor += size
		if tick < midnight_ticks: _assign_seats()
	for seat_id in seats:
		if seats[seat_id] != 0:
			stats.seat_ticks += 1
	for stove in stoves.values():
		if stove.owner != 0:
			var stove_staff = staff[int(stove.owner) - 1]
			if not stove_staff.task.is_empty() and stove_staff.task.kind == "COOK" and stove_staff.task.stage == "ACTION":
				stats.stove_ticks += 1
	for s in staff:
		if s.task.is_empty():
			_dispatch_staff(s)
	if tick >= day_ticks and arrival_cursor == arrival_plan.size() and _all_customers_gone():
		_close_day()

func _queue_count() -> int:
	return queued_people

func queue_spot(c: Dictionary, index: int, party_places: Dictionary) -> Vector2:
	var place = Vector2(-.65 - floori(index / 14.0) * .55, float(layout.entrance[1]) - (index % 14) * .48)
	var party = int(c.get("party_id", 0))
	if party == 0: return place
	if not party_places.has(party): party_places[party] = place
	return party_places[party] + party_offset(c)

func _disperse_queue() -> void:
	var party_places = {}
	var index = 0
	for c in active_customers.values():
		if c.state != "QUEUE": continue
		c.pos = queue_spot(c, index, party_places)
		_terminal(c, "C")
		index += 1
	_clear_guest_queues()

func _all_customers_gone() -> bool:
	return active_customers.is_empty()

func _spawn_customer(plan: Dictionary) -> void:
	_spawn_party([plan])

func _spawn_party(plans: Array) -> void:
	var size = plans.size()
	var leader = int(plans[0].id)
	var no_table = size > 1 and tables_by_size[size].is_empty()
	stats.arrived += size
	if no_table or _queue_count() + size > int(attributes.queue_capacity):
		stats.refused += size
		stats.funnel.R += size
		for index in range(size):
			var plan = plans[index]
			stats.refused_types[plan.type] = int(stats.refused_types.get(plan.type, 0)) + 1
			if not no_table: continue
			var c = _create_guest(plan, size, leader, index)
			c.terminal = "R"
			c.state = "APPROACHING"
			c.pos += Vector2(-3.35, 0) + party_offset(c)
			c.path = [c.pos + Vector2(2.6, 0)]
		if no_table: stats.refused_no_table += size
		return
	var members = []
	for index in range(size):
		var c = _create_guest(plans[index], size, leader, index)
		members.append(c.id)
	if size > 1:
		parties[leader] = {"members": members, "remaining": size, "at_exit": 0, "ready_tick": tick + Rules.ticks(1.2, tick_ms)}
	guest_queues[size].append(leader)
	queued_people += size
	stats.admitted += size
	guest_moment.emit(leader, &"arrival")
	stats.peak_queue = maxi(int(stats.peak_queue), _queue_count())

func _create_guest(plan: Dictionary, size: int, leader: int, index: int) -> Dictionary:
	var id = int(plan.id)
	var c = {"id": id, "type": plan.type, "state": "QUEUE", "state_tick": tick, "arrival_tick": tick, "pos": Grid.vec(layout.entrance), "path": [], "seat": "", "seat_key": "", "recipe": "", "order": 0, "reserved_by": 0, "deadline": 0, "food_start": 0, "next_penalty": 0, "food_max": 0, "served_quality": 1.0, "payment_committed": false, "terminal": "", "ready_tick": 0, "party_id": leader if size > 1 else 0, "party_size": size, "party_index": index}
	customers[id] = c
	active_customers[id] = c
	return c

func party_offset(c: Dictionary) -> Vector2:
	var index = int(c.get("party_index", 0))
	return Vector2(-floori(float(index) / 2.0) * .43, (-.25 if index % 2 == 0 else .25)) if int(c.get("party_size", 1)) > 1 else Vector2.ZERO

func _move(entity: Dictionary, speed: float) -> bool:
	if not entity.path.is_empty():
		entity.previous_pos = entity.pos
		entity.position_tick = tick
		entity.turns_this_tick = []
	var budget = speed * float(tick_ms) / 1000.0
	while not entity.path.is_empty() and budget > 0:
		var target = entity.path[0]
		var distance = entity.pos.distance_to(target)
		if distance <= budget + 0.00001:
			entity.pos = target
			entity.path.pop_front()
			budget -= distance
			if not entity.path.is_empty() and budget>.00001: entity.turns_this_tick.append(target)
		else:
			entity.pos = entity.pos.move_toward(target, budget)
			budget = 0
	return entity.path.is_empty()

func _guest_seconds(c: Dictionary, field: String) -> float:
	var g = guest_defs[c.type]
	var common = chapter.common_guest_template
	match field:
		"choose": return float(common.choose_seconds) * float(g.get("choose_time_multiplier", 1.0)) * (1.0 - float(modifiers.get("choose_reduction", 0.0)))
		"eat": return guest_eating_duration(str(c.type), str(c.seat))
		"order": return float(g.get("order_patience_override", common.order_patience_seconds)) * (1.0 + float(modifiers.get("order_patience", 0.0)))
		"cycle": return float(common.food_penalty_cycle_seconds) * float(g.get("food_cycle_multiplier", 1.0)) * (1.0 + modifiers.patience)
		"food_max": return float(common.food_max_wait_seconds) * float(g.get("food_max_multiplier", 1.0)) * (1.0 + modifiers.patience)
	return 1.0

func guest_eating_duration(type_id: String, table := "") -> float:
	var base = float(chapter.common_guest_template.eat_seconds) * float(guest_defs[type_id].get("eat_time_multiplier", 1.0))
	var active = effective_modifiers() if phase == "NIGHT" else modifiers
	var reduction = clampf(float(active.get("eat_time_reduction", 0.0)) + fixture_bonus(table, "table_eat"), 0.0, Rules.MAX_EAT_TIME_REDUCTION)
	return base * (1.0 - reduction)

func _advance_customer(c: Dictionary) -> void:
	if c.state == "APPROACHING":
		if _move(c, guest_walk_speed):
			c.state = "REFUSING"
			c.deadline = tick + Rules.ticks(2.3, tick_ms)
			if int(c.party_index) == 0: guest_moment.emit(c.id, &"no_table")
	elif c.state == "REFUSING" and tick >= int(c.deadline):
		_exit_street(c)
	elif c.state == "SEATING":
		if _move(c, guest_walk_speed):
			c.state = "CHOOSING"
			c.state_tick = tick
			c.deadline = tick + Rules.ticks(_guest_seconds(c, "choose"), tick_ms)
	elif c.state == "CHOOSING" and tick >= int(c.deadline):
		var rng = _rng("dish_%d" % c.id)
		c.recipe = menu[rng.randi_range(0, menu.size() - 1)]
		c.state = "READY"
		c.state_tick = tick
		c.ready_tick = tick
		c.deadline = tick + Rules.ticks(_guest_seconds(c, "order"), tick_ms)
	elif c.state == "EATING" and tick >= int(c.deadline):
		_checkout(c)
	elif c.state == "LEAVING" and int(c.state_tick) < tick:
		if _move(c, guest_walk_speed):
			var party = parties.get(int(c.get("party_id", 0)), {})
			if party.is_empty():
				_exit_street(c)
			else:
				c.state = "AT_EXIT"
				party.at_exit += 1
				if int(party.at_exit) == party.members.size():
					for id in party.members: _exit_street(customers[id])
					parties.erase(int(c.party_id))
	elif c.state == "EXITING" and int(c.state_tick) < tick:
		if _move(c, guest_walk_speed):
			c.state = "GONE"

func _exit_street(c: Dictionary, from_door: bool = false) -> void:
	if not from_door and c.terminal != "R": c.pos = Grid.vec(layout.exit) + party_offset(c)
	c.state = "EXITING"
	c.previous_pos = c.pos
	c.state_tick = tick
	c.path = [c.pos + Vector2(-4.5, 0)]

func _apply_patience(c: Dictionary) -> void:
	if not c.terminal.is_empty():
		return
	if c.state == "READY" and tick >= int(c.deadline):
		_terminal(c, "O")
	elif c.state == "FOOD":
		var cycle = Rules.ticks(_guest_seconds(c, "cycle"), tick_ms)
		if tick == int(c.next_penalty) and int(c.next_penalty) == int(c.food_start) + cycle:
			guest_moment.emit(c.id, &"impatient")
		var guest = guest_defs[c.type]
		var penalty = int(guest.get("food_penalty_per_cycle", 1))
		while tick >= int(c.next_penalty):
			stats.wait_penalty_raw += penalty
			var deducted = mini(reputation, penalty)
			reputation -= deducted
			stats.wait_penalty_actual += deducted
			c.next_penalty += cycle
		if not bool(guest.get("unlimited_food_wait", false)) and tick >= int(c.food_max):
			_terminal(c, "F")

func _assign_seats() -> void:
	for size in PARTY_SIZES:
		var queue = guest_queues[size]
		var head = int(queue_heads[size])
		if head == queue.size(): continue
		var free = []
		for table in tables_by_size[size]:
			if seats[table_slots[table][0]] == 0: free.append(table)
		while head < queue.size():
			var leader = int(queue[head])
			if customers[leader].state == "QUEUE":
				var party = parties.get(leader, {})
				if tick < int(party.get("ready_tick", 0)) or free.is_empty(): break
				var rng = _rng("seat_%d" % leader)
				var table = free.pop_at(rng.randi_range(0, free.size() - 1))
				_seat_party(party.get("members", [leader]), table)
			head += 1
			queued_people -= size
		if head == queue.size():
			queue.clear()
			head = 0
		queue_heads[size] = head

func _seat_party(members: Array, table: String) -> void:
	var slots = table_slots[table]
	for index in range(members.size()):
		var c = customers[members[index]]
		var slot = slots[index]
		seats[slot] = c.id
		c.seat = table
		c.seat_key = slot
		c.state = "SEATING"
		c.state_tick = tick
		c.path = service_routes.path(c.pos, seat_cells[slot])
		stats.queue_waits.append({"seconds": (tick - int(c.arrival_tick)) * tick_ms / 1000.0, "success": true})

func _seat_key(c: Dictionary) -> String:
	var slot = str(c.get("seat_key", ""))
	return str(c.seat) if slot.is_empty() else slot

func _seat_cell(c: Dictionary) -> Vector2i:
	return seat_cells[_seat_key(c)]

func _order_active(id: int) -> bool:
	return orders.has(id) and orders[id].status == "ACTIVE"

func _active_foods(location: String, location_id: String = "") -> Array:
	var result = []
	for f in foods.values():
		if f.location == location and (location_id.is_empty() or str(f.location_id) == location_id):
			result.append(f)
	result.sort_custom(func(a, b): return a.id < b.id)
	return result

func _pending_orders(recipe_id: String = "") -> Array:
	var result = []
	for o in orders.values():
		if o.status == "ACTIVE" and int(o.submitted_tick) >= 0 and o.supply == "NONE" and (recipe_id.is_empty() or o.recipe == recipe_id):
			result.append(o)
	result.sort_custom(func(a, b): return a.submitted_tick < b.submitted_tick or (a.submitted_tick == b.submitted_tick and a.id < b.id))
	return result

func _pass_free(occupied := -1) -> int:
	var reserved = 0
	for o in orders.values():
		if o.status == "ACTIVE" and o.supply in ["COOKING", "IN_TRANSIT"]:
			reserved += 1
	var count = _active_foods("PASS").size() if occupied < 0 else occupied
	return maxi(0, pass_capacity - count - reserved)

func _set_task(s: Dictionary, kind: String, facility: Dictionary, extra: Dictionary = {}, guest: Dictionary = {}) -> void:
	var cells = Grid.interaction_cells(facility) if guest.is_empty() else [_seat_cell(guest)]
	var route = service_routes.approach(s.pos, cells)
	s.task = {"kind": kind, "stage": "MOVE", "target": route.get("target", Vector2(cells[0])), "done_tick": 0}
	s.task.merge(extra)
	s.path = route.get("path", [])
	s.reason = ""
	if s.role == "waiter": s.idle_walk_after = tick + _idle_walk_delay(2.6, 5.8)

func _finish_task(s: Dictionary) -> void:
	s.task = {}
	s.path = []

func _abort_task(s: Dictionary) -> void:
	var task = s.task
	if task.get("kind", "") == "ORDER" and customers.has(int(task.get("customer_id", 0))):
		var c = customers[int(task.customer_id)]
		if int(c.reserved_by) == int(s.id):
			c.reserved_by = 0
	for food_id in task.get("food_ids", []):
		if not foods.has(int(food_id)): continue
		var f = foods[int(food_id)]
		if int(f.reserved_by) != int(s.id): continue
		f.reserved_by = 0
		if not _order_active(int(f.bound_order)): continue
		var o = orders[int(f.bound_order)]
		if task.kind == "COLLECT" and f.location == "SHELF":
			o.supply = "NONE"
			o.supply_owner = 0
			o.food = 0
			f.bound_order = 0
		elif task.kind == "PICKUP" and int(o.delivery_owner) == int(s.id):
			o.delivery_owner = 0
	var order_id = int(task.get("order_id", 0))
	if _order_active(order_id) and int(orders[order_id].delivery_owner) == int(s.id):
		orders[order_id].delivery_owner = 0

	_finish_task(s)

func _task_valid(s: Dictionary) -> bool:
	var t = s.task
	match str(t.kind):
		"ORDER":
			return customers.has(int(t.customer_id)) and customers[int(t.customer_id)].terminal.is_empty() and customers[int(t.customer_id)].state in ["READY", "TAKING"] and int(customers[int(t.customer_id)].reserved_by) == int(s.id)
		"SUBMIT":
			return not s.carry_orders.is_empty()
		"PICKUP":
			for id in t.food_ids:
				if _can_pickup(foods[int(id)], int(s.id)): return true
			return false
		"DELIVER":
			return _order_active(int(t.order_id))
		"COLLECT":
			for id in t.food_ids:
				if foods.has(int(id)) and _order_active(int(foods[int(id)].bound_order)):
					return true
			return false
	return true

func _advance_staff(s: Dictionary) -> void:
	if s.task.is_empty():
		s.time["blocked" if s.reason.begins_with("等待") else "idle"] += 1
		return
	if not _task_valid(s):
		_abort_task(s)
		return
	var t = s.task
	if t.stage == "MOVE":
		s.time.move += 1
		var speed = chef_walk_speed
		if s.role == "waiter":
			var local_speed = float(local_effects.waiter_cells.get(Vector2i(s.pos.round()), 0.0))
			speed = float(chapter.movement.waiter_speed) * (1.0 + modifiers.speed + local_speed)
			if tick < current_until and Vector2(s.pos).distance_squared_to(current_cell) <= 4.0:
				var linger := 4.0 if s.get("crew_id") == "riverclaw" and crew_on_duty("ferrier", "waiter") else 3.0
				s.haste_until = tick + Rules.ticks(linger, tick_ms)
			if tick < int(s.get("haste_until", 0)):
				speed *= 1.5
		speed *= Minions.movement(str(s.get("minion","")),s.role,t.kind)
		if _move(s, speed):
			_arrive_task(s)
	elif t.stage == "PREP":
		s.time.cook += 1
		if tick >= int(t.prep_until): t.stage = "ACTION"
	else:
		s.time["cook" if t.kind == "COOK" else "interact"] += 1
		if tick >= int(t.done_tick):
			_complete_action(s)

func staff_action_seconds(task: Dictionary) -> float:
	if task.kind == "COOK":
		return float(recipes[task.recipe].cook_seconds) / (1.0 + modifiers.cook + fixture_bonus(str(task.stove_id), "stove_speed"))
	return float(chapter.movement.interaction_seconds) * (1.0 - float(modifiers.get("service_reduction", 0.0)))

func _can_pickup(food: Dictionary, waiter_id: int) -> bool:
	return food.location == "PASS" and int(food.reserved_by) == waiter_id and _order_active(int(food.bound_order))

func _arrive_task(s: Dictionary) -> void:
	var t = s.task
	if t.kind in ["ORDER", "SUBMIT", "COOK"]:
		if t.kind == "ORDER":
			customers[int(t.customer_id)].state = "TAKING"
		t.stage = "ACTION"
		var seconds = staff_action_seconds(t)
		if t.kind == "ORDER" and s.get("crew_id") == "mosskeeper": seconds *= .84
		if t.kind == "COOK":
			t.flare = int(s.get("finished_pots", 0)) % 3 == 2
			if t.flare: seconds *= 0.5
			if s.get("crew_id") == "ovenhand" and t.recipe == "starter_rice": seconds *= .88
		seconds *= Minions.duration(str(s.get("minion","")),str(s.get("role","")),t.kind)
		t.started_tick = tick
		t.done_tick = tick + Rules.ticks(seconds, tick_ms)
		if t.kind == "COOK" and crew_on_duty("kilnkeeper", "chef"):
			var preparation := mini(maxi(0, int(t.done_tick) - tick - 1), Rules.ticks(LINKED_FIRE_PREP_SECONDS, tick_ms))
			if preparation > 0:
				t.stage = "PREP"
				t.prep_until = tick + preparation
				t.prep_ready_tick = tick + mini(preparation - 1, Rules.ticks(.28, tick_ms))
				if s.get("crew_id") == "hearthling":
					for member in staff:
						if member.get("crew_id") == "kilnkeeper" and Vector2(member.pos).distance_to(s.pos) <= 2.0:
							t.prep_ready_tick = tick
							break
		return
	if t.kind == "COLLECT":
		for id in t.food_ids:
			var f = foods[int(id)]
			if f.location == "SHELF" and int(f.reserved_by) == int(s.id) and _order_active(int(f.bound_order)):
				f.location = "CHEF"
				f.location_id = str(s.id)
				f.reserved_by = 0
				s.carry_food.append(f.id)
	elif t.kind == "TRANSFER":
		for id in t.food_ids:
			var f = foods[int(id)]
			if f.location == "CHEF" and _order_active(int(f.bound_order)):
				f.location = "PASS"
				f.location_id = "pass"
				var o = orders[int(f.bound_order)]
				o.supply = "AT_PASS"
				o.pass_tick = tick
				o.supply_owner = 0
				s.carry_food.erase(id)
	elif t.kind == "PICKUP":
		for id in t.food_ids:
			var f = foods[int(id)]
			if not _can_pickup(f, int(s.id)): continue
			f.location = "WAITER"
			f.location_id = str(s.id)
			f.reserved_by = 0
			orders[int(f.bound_order)].supply = "WITH_WAITER"
			s.carry_food.append(f.id)
	elif t.kind == "DELIVER":
		var o = orders[int(t.order_id)]
		var c = customers[int(o.customer)]
		var f = foods[int(o.food)]
		if c.state == "FOOD" and f.location == "WAITER":
			f.location = "PLATE"
			f.location_id = str(c.id)
			o.supply = "SERVED"
			o.delivery_owner = 0
			o.served_tick = tick
			c.state = "EATING"
			guest_moment.emit(c.id, &"eating")
			c.state_tick = tick
			c.served_quality = _decorated_quality(float(f.quality), fixture_bonus(str(c.seat), "table_quality"))
			if c.type == "food_inspector" and stats.has("quality_inspection"):
				stats.quality_inspection.served += 1
				stats.quality_inspection.quality_sum += c.served_quality
			c.deadline = tick + Rules.ticks(_guest_seconds(c, "eat"), tick_ms)
			_record_food_wait(c, true)
			s.carry_food.erase(f.id)
	elif t.kind == "RETURN":
		for id in t.food_ids:
			var f = foods[int(id)]
			f.bound_order = 0
			f.reserved_by = 0
			if s.role == "chef":
				if _active_foods("SHELF", str(f.origin)).size() + int(stoves[str(f.origin)].output_reserved) < stove_capacity:
					f.location = "SHELF"
					f.location_id = str(f.origin)
				else:
					_discard_food(f, "返还容量不足")
			else:
				if _pass_free() > 0:
					f.location = "PASS"
					f.location_id = "pass"
				else:
					_discard_food(f, "返还容量不足")
			s.carry_food.erase(id)
	_finish_task(s)

func _complete_action(s: Dictionary) -> void:
	var t = s.task
	if t.kind == "ORDER":
		var c = customers[int(t.customer_id)]
		var id = next_order_id
		next_order_id += 1
		orders[id] = {"id": id, "customer": c.id, "seat": c.seat, "recipe": c.recipe, "created_tick": tick, "submitted_tick": -1, "served_tick": -1, "status": "ACTIVE", "supply": "NONE", "supply_owner": 0, "delivery_owner": 0, "food": 0}
		c.order = id
		c.state = "FOOD"
		guest_moment.emit(c.id, &"waiting")
		c.state_tick = tick
		c.reserved_by = 0
		c.food_start = tick
		c.next_penalty = tick + Rules.ticks(_guest_seconds(c, "cycle"), tick_ms)
		c.food_max = tick + Rules.ticks(_guest_seconds(c, "food_max"), tick_ms)
		s.carry_orders.append(id)
		stats.order_waits.append({"seconds": (tick - int(c.ready_tick)) * tick_ms / 1000.0, "success": true, "table": c.seat})
	elif t.kind == "SUBMIT":
		for id in s.carry_orders:
			if _order_active(int(id)): orders[int(id)].submitted_tick = tick
		s.carry_orders.clear()
	elif t.kind == "COOK":
		s.finished_pots = int(s.get("finished_pots", 0)) + 1
		var batch = int(t.get("batch",recipes[t.recipe].batch_yield))
		var produced = []
		var base_quality = float(qualities[t.recipe])
		if trophy_quality_rng != null and trophy_quality_rng.randf() < float(modifiers.cook_quality_roll.chance):
			base_quality += float(modifiers.cook_quality_roll.value)
		var quality = _decorated_quality(base_quality, fixture_bonus(str(t.stove_id), "stove_quality"))
		for i in range(batch):
			var id = next_food_id
			next_food_id += 1
			foods[id] = {"id": id, "recipe": t.recipe, "quality": quality, "location": "SHELF", "location_id": t.stove_id, "origin": t.stove_id, "bound_order": 0, "reserved_by": 0, "created_tick": tick}
			produced.append(id)
			stats.produced += 1
		stoves[t.stove_id].owner = 0
		stoves[t.stove_id].output_reserved = 0
		var index = 0
		for order_id in t.order_ids:
			if not _order_active(int(order_id)):
				continue
			var o = orders[int(order_id)]
			if o.supply != "COOKING" or int(o.supply_owner) != int(s.id):
				continue
			var f = foods[int(produced[index])]
			index += 1
			f.bound_order = o.id
			f.location = "CHEF"
			f.location_id = str(s.id)
			o.food = f.id
			o.supply = "IN_TRANSIT"
			s.carry_food.append(f.id)
	_finish_task(s)

func _dispatch_staff(s: Dictionary) -> void:
	if s.role == "waiter":
		_dispatch_waiter(s)
	else:
		_dispatch_chef(s)

func _dispatch_waiter(s: Dictionary) -> void:
	if not s.carry_food.is_empty():
		var nearest = {}
		var shortest = 0
		for food_id in s.carry_food:
			var f = foods[int(food_id)]
			if not _order_active(int(f.bound_order)): continue
			var order = orders[int(f.bound_order)]
			var guest = customers[int(order.customer)]
			var distance = service_routes.distance(s.pos, _seat_cell(guest))
			if nearest.is_empty() or distance < shortest:
				nearest = order
				shortest = distance
		if nearest.is_empty():
			_set_task(s, "RETURN", Grid.find(layout, "pass"), {"food_ids": s.carry_food.duplicate()})
		else:
			_set_task(s, "DELIVER", Grid.find(layout, nearest.seat), {"order_id": nearest.id}, customers[int(nearest.customer)])
		return
	if not s.carry_orders.is_empty():
		if s.carry_orders.size() < waiter_order_limit and _assign_waiter_order(s): return
		_set_task(s, "SUBMIT", Grid.find(layout, "order"))
		return
	if _assign_waiter_pickup(s) or _assign_waiter_order(s): return
	s.reason = "暂无待点单 / 可配送食品"
	_advance_idle_walk(s)

func _assign_waiter_pickup(s: Dictionary) -> bool:
	var selected = []
	for o in orders.values():
		if o.status != "ACTIVE" or o.supply != "AT_PASS" or int(o.delivery_owner) != 0: continue
		var index = 0
		while index < selected.size():
			var current = selected[index]
			if o.created_tick < current.created_tick or (o.created_tick == current.created_tick and o.id < current.id): break
			index += 1
		if index >= waiter_food_limit: continue
		selected.insert(index, o)
		if selected.size() > waiter_food_limit: selected.pop_back()
	if selected.is_empty(): return false
	var ids = []
	for o in selected:
		var f = foods[int(o.food)]
		o.delivery_owner = s.id
		f.reserved_by = s.id
		ids.append(f.id)
	_set_task(s, "PICKUP", Grid.find(layout, "pass"), {"food_ids": ids})
	return true

func _assign_waiter_order(s: Dictionary) -> bool:
	var nearest = {}
	var shortest = 0
	for occupied in seats.values():
		var id = int(occupied)
		if id <= 0: continue
		var c = customers[id]
		if c.state != "READY" or int(c.reserved_by) != 0 or not c.terminal.is_empty(): continue
		var distance = service_routes.distance(s.pos, _seat_cell(c))
		if nearest.is_empty() or distance < shortest or (distance == shortest and (c.ready_tick < nearest.ready_tick or (c.ready_tick == nearest.ready_tick and c.id < nearest.id))):
			nearest = c
			shortest = distance
	if not nearest.is_empty():
		nearest.reserved_by = s.id
		_set_task(s, "ORDER", Grid.find(layout, nearest.seat), {"customer_id": nearest.id}, nearest)
		return true
	return false

func _prepare_idle_walks() -> void:
	idle_walk_rng = _rng("idle_walk")
	idle_walk_aisles = Grid.walkable_region(layout, navigation)
	idle_walk_aisles.erase(Vector2i(Grid.vec(layout.entrance)))
	idle_walk_aisles.erase(Vector2i(Grid.vec(layout.exit)))
	var kitchen = Grid.kitchen_bounds(layout)
	for cell in idle_walk_aisles.keys():
		if cell.x >= kitchen.left and cell.x <= kitchen.right and cell.y >= kitchen.top and cell.y <= kitchen.bottom:
			idle_walk_aisles.erase(cell)
	idle_walk_stops = idle_walk_aisles.duplicate()
	for cell in seat_cells.values(): idle_walk_stops.erase(cell)
	for facility in layout.facilities:
		if Grid.placed(facility) and facility.type in ["order", "pass", "stove"]:
			for cell in Grid.interaction_cells(facility): idle_walk_stops.erase(cell)

func _idle_walk_delay(low: float, high: float) -> int:
	return Rules.ticks(idle_walk_rng.randf_range(low, high), tick_ms)

func _advance_idle_walk(s: Dictionary) -> void:
	if tick >= day_ticks:
		s.path.clear()
		return
	if s.path.is_empty():
		if idle_walk_rng == null or tick < int(s.get("idle_walk_after", 0)): return
		s.idle_walk_after = tick + _idle_walk_delay(4.8, 9.5)
		var start = Vector2i(s.pos.round())
		var cell = start
		var path: Array = []
		var visited = {start: true}
		var stop_index = 0
		for step in range(idle_walk_rng.randi_range(2, 4)):
			var options: Array[Vector2i] = []
			for direction in Grid.DIRECTIONS:
				var next = cell + direction
				if idle_walk_aisles.has(next) and not visited.has(next): options.append(next)
			if options.is_empty(): break
			cell = options[idle_walk_rng.randi_range(0, options.size() - 1)]
			visited[cell] = true
			path.append(Vector2(cell))
			if idle_walk_stops.has(cell): stop_index = path.size()
		if stop_index == 0: return
		s.path = path.slice(0, stop_index)
		if not s.pos.is_equal_approx(Vector2(start)): s.path.push_front(Vector2(start))
	s.reason = "在餐厅走动"
	if _move(s, 1.35):
		s.idle_walk_after = tick + _idle_walk_delay(4.8, 9.5)
		s.reason = "暂无待点单 / 可配送食品"

func _dispatch_chef(s: Dictionary) -> void:
	if not s.carry_food.is_empty():
		var valid = []
		for id in s.carry_food:
			if _order_active(int(foods[int(id)].bound_order)):
				valid.append(id)
		if not valid.is_empty():
			_set_task(s, "TRANSFER", Grid.find(layout, "pass"), {"food_ids": valid})
		else:
			var origin = str(foods[int(s.carry_food[0])].origin)
			var returned = []
			for id in s.carry_food:
				if str(foods[int(id)].origin) == origin:
					returned.append(id)
			_set_task(s, "RETURN", Grid.find(layout, origin), {"food_ids": returned})
		return
	var pending = _pending_orders()
	if pending.is_empty():
		s.reason = "暂无已提交的未供应订单"
		return
	# Allocate existing pass leftovers before creating any production responsibility.
	var pass_stock = _active_foods("PASS")
	for o in pending:
		for f in pass_stock:
			if f.recipe == o.recipe and int(f.bound_order) == 0 and int(f.reserved_by) == 0:
				f.bound_order = o.id
				o.food = f.id
				o.supply = "AT_PASS"
				o.pass_tick = tick
				break
	pending = pending.filter(func(o): return o.supply == "NONE")
	if pending.is_empty():
		s.reason = "暂无已提交的未供应订单"
		return
	var pass_free = _pass_free(pass_stock.size())
	if pass_free <= 0:
		s.reason = "等待出餐口空间"
		return
	var shelves = _active_foods("SHELF")
	var available_stoves = []
	for f in Grid.facilities(layout, "stove"):
		if int(stoves[f.id].owner) == 0:
			available_stoves.append(f)
	available_stoves.sort_custom(func(a, b): return service_routes.distance(s.pos, Vector2i(Grid.interaction(a))) < service_routes.distance(s.pos, Vector2i(Grid.interaction(b))))
	var checked_recipes = {}
	for first in pending:
		if checked_recipes.has(first.recipe): continue
		checked_recipes[first.recipe] = true
		var same = pending.filter(func(o): return o.recipe == first.recipe)
		var stock = []
		for f in shelves:
			if f.recipe == first.recipe and int(f.bound_order) == 0 and int(f.reserved_by) == 0:
				stock.append(f)
		if not stock.is_empty():
			var source = str(stock[0].location_id)
			stock = stock.filter(func(f): return str(f.location_id) == source)
			var count = mini(mini(stock.size(), same.size()), mini(pass_free, chef_carry_limit))
			var ids = []
			for i in range(count):
				var f = stock[i]
				var o = same[i]
				f.bound_order = o.id
				f.reserved_by = s.id
				o.food = f.id
				o.supply = "IN_TRANSIT"
				o.supply_owner = s.id
				ids.append(f.id)
			_set_task(s, "COLLECT", Grid.find(layout, source), {"food_ids": ids})
			return
		var base_batch = int(recipes[first.recipe].batch_yield)
		for stove in available_stoves:
			var old_food = shelves.filter(func(f): return str(f.location_id) == stove.id)
			var free = stove_capacity - old_food.size()
			var disposable = old_food.filter(func(f): return int(f.reserved_by) == 0 and int(f.bound_order) == 0)
			var room = free + disposable.size()
			if room < base_batch: continue
			var batch = base_batch
			if trophy_yield_rng != null and trophy_yield_rng.randf() < float(modifiers.cook_yield.chance):
				batch = mini(room, maxi(batch, int(modifiers.cook_yield.value)))
			while free < batch:
				_discard_food(disposable.pop_front(), "库存整理")
				free += 1
			var count = mini(mini(batch, same.size()), mini(pass_free, chef_carry_limit))
			var ids = []
			for i in range(count):
				var o = same[i]
				o.supply = "COOKING"
				o.supply_owner = s.id
				ids.append(o.id)
			stoves[stove.id].owner = s.id
			stoves[stove.id].output_reserved = batch
			_set_task(s, "COOK", stove, {"recipe": first.recipe, "stove_id": stove.id, "order_ids": ids, "batch": batch})
			return
	s.reason = "等待灶台 / 厨房库存空间"

func _discard_food(f: Dictionary, reason: String) -> void:
	if f.location in ["DISCARDED", "CONSUMED"]:
		return
	f.location = "DISCARDED"
	f.location_id = ""
	f.bound_order = 0
	f.reserved_by = 0
	stats.discarded += 1
	stats.discard_reasons[reason] = int(stats.discard_reasons.get(reason, 0)) + 1

func _cancel_order(order_id: int) -> void:
	if not _order_active(order_id):
		return
	var o = orders[order_id]
	o.status = "CANCELLED"
	o.supply = "CANCELLED"
	o.supply_owner = 0
	o.delivery_owner = 0
	for f in foods.values():
		if int(f.bound_order) != order_id:
			continue
		f.bound_order = 0
		f.reserved_by = 0
		if f.location in ["PASS", "PLATE"]:
			_discard_food(f, "客人离席")
	for s in staff:
		s.carry_orders.erase(order_id)

func _checkout(c: Dictionary) -> void:
	if c.payment_committed or not c.terminal.is_empty():
		return
	var guest = guest_defs[c.type]
	var payment = meal_price(c.recipe, float(c.served_quality), modifiers, guest, str(c.seat))
	gold += payment
	stats.income += payment
	stats.income_recipes[c.recipe] = int(stats.income_recipes.get(c.recipe, 0)) + payment
	stats.income_guests[c.type] = int(stats.income_guests.get(c.type, 0)) + payment
	stats.guest_checkout_counts[c.type] = int(stats.guest_checkout_counts.get(c.type,0)) + 1
	if payment > 0:
		stats.payer_count += 1
	var expectation = float(guest.get("quality_expectation_override", chapter.common_guest_template.expected_quality)) + float(modifiers.get("quality_expectation_add", 0.0))
	var gap = maxi(0, int(ceil((expectation - float(c.served_quality)) / float(chapter.quality_rules.step) - 0.0000001)))
	var quality_loss = gap * int(chapter.quality_rules.disappointment_penalty_per_step)
	var base_rep = int(guest.base_reputation)
	var extra_rep = int(modifiers.reputation) + int(fixture_bonus(str(c.seat), "table_reputation"))
	reputation += base_rep + extra_rep
	total_reputation += base_rep + extra_rep
	var actual_loss = mini(reputation, quality_loss)
	reputation -= actual_loss
	stats.rep_base += base_rep
	stats.rep_buff += extra_rep
	stats.quality_penalty_raw += quality_loss
	stats.quality_penalty_actual += actual_loss
	c.payment_committed = true
	stats.completed += 1
	if tick < midnight_ticks: stats.completed_before_midnight += 1
	var o = orders[int(c.order)]
	o.status = "COMPLETE"
	var food = foods[int(o.food)]
	food.location = "CONSUMED"
	food.location_id = ""
	food.bound_order = 0
	stats.consumed += 1
	_terminal(c, "S")
	if payment > 0:
		payment_received.emit(c.pos, payment)
	guest_moment.emit(c.id, &"after_meal")

func _record_food_wait(c: Dictionary, success: bool) -> void:
	var pass_tick = int(orders.get(int(c.order), {}).get("pass_tick", -1))
	var before_pass = (tick if pass_tick < 0 else pass_tick) - int(c.food_start)
	var sample = {
		"seconds": (tick - int(c.food_start)) * tick_ms / 1000.0,
		"before_pass": before_pass * tick_ms / 1000.0,
		"success": success,
		"table": c.seat
	}
	if pass_tick >= 0:
		sample.after_pass = (tick - pass_tick) * tick_ms / 1000.0
	stats.food_waits.append(sample)

func _terminal(c: Dictionary, reason: String) -> void:
	if not c.terminal.is_empty():
		return
	if reason == "C":
		stats.closing_stages[c.state] = int(stats.closing_stages.get(c.state, 0)) + 1
		if c.state == "QUEUE":
			stats.queue_waits.append({"seconds": (tick - int(c.arrival_tick)) * tick_ms / 1000.0, "success": false})
	if c.state in ["READY", "TAKING"]:
		stats.order_waits.append({"seconds": (tick - int(c.ready_tick)) * tick_ms / 1000.0, "success": false, "table": c.seat})
	if c.state == "FOOD":
		_record_food_wait(c, false)
	c.terminal = reason
	stats.funnel[reason] += 1
	c.reserved_by = 0
	if reason != "S" and int(c.order) != 0:
		_cancel_order(int(c.order))
	var party = parties.get(int(c.get("party_id", 0)), {})
	if party.is_empty():
		_start_leaving(c)
	else:
		c.state = "STAYING"
		party.remaining -= 1
		if int(party.remaining) == 0:
			for id in party.members: _start_leaving(customers[id])
			if c.state == "EXITING": parties.erase(int(c.party_id))

func _start_leaving(c: Dictionary) -> void:
	if c.pos.x < 0:
		_exit_street(c, true)
		return
	var slot = _seat_key(c)
	if int(seats.get(slot, 0)) == int(c.id): seats[slot] = 0
	c.state = "LEAVING"
	c.state_tick = tick
	c.path = service_routes.path(c.pos, Vector2i(Grid.vec(layout.exit)))

func _settle_quality_inspection() -> void:
	if not stats.has("quality_inspection"): return
	var result = stats.quality_inspection
	for event in major_events_for():
		if not event.has("quality_inspection"): continue
		var rules = event.quality_inspection
		result.quality = float(result.quality_sum) / maxi(1, int(result.expected))
		var amount = roundi((float(result.quality) - float(rules.neutral_quality)) * 100.0 * int(rules.reputation_per_percentage_point))
		result.assessed = clampi(amount, -int(rules.limit), int(rules.limit))
		var before = reputation
		if int(result.assessed) > 0:
			_credit_event({"reputation": int(result.assessed)})
		else:
			reputation = maxi(0, reputation + int(result.assessed))
		result.change = reputation - before
		return

func _close_day() -> void:
	if phase != "DAY":
		return
	for c in customers.values():
		if c.terminal.is_empty():
			_terminal(c, "C")
	for f in foods.values():
		_discard_food(f, "闭店清空")
	for s in staff:
		s.task = {}
		s.path = []
		s.carry_food = []
		s.carry_orders.clear()
	for stove in stoves.values():
		stove.owner = 0
		stove.output_reserved = 0
	for id in buff_states.keys():
		buff_states[id].remaining_days = int(buff_states[id].remaining_days) - 1
		if buff_states[id].remaining_days <= 0:
			buff_states.erase(id)
	stats.day = day
	stats.planned = arrival_plan.size()
	_award_service_stars()
	stats.major_event_goals = []
	_settle_quality_inspection()
	for event in major_events_for():
		var progress = event_challenge(event, stats)
		if progress.is_empty(): continue
		if progress.success and day == int(event.to_day): _credit_event(progress.reward)
		stats.major_event_goals.append(progress)
	var rent_amount = 0
	var rent_ok = true
	for rent in chapter.rent_schedule:
		if int(rent.day) == day:
			rent_amount = int(rent.amount)
			rent_ok = gold >= rent_amount
			if rent_ok:
				gold -= rent_amount
	var result = "CONTINUE"
	if not rent_ok:
		result = "LOSE"
	elif day == int(chapter.chapter_days):
		result = "WIN"
	stats.operation_ticks = tick
	stats.overtime_ticks = maxi(0, tick - day_ticks)
	stats.seed = seed_value
	stats.config_version = chapter.config_version
	stats.result = result
	stats.rent_amount = rent_amount
	stats.rent_ok = rent_ok
	stats.gold_after = gold
	stats.reputation_after = reputation
	stats.reputation_change = reputation - int(stats.get("reputation_at_opening", reputation))
	stats.events = events_for()
	stats.seat_utilization = float(stats.seat_ticks) / maxi(1, seats.size() * tick)
	stats.stove_utilization = float(stats.stove_ticks) / maxi(1, stoves.size() * tick)
	stats.staff_times = staff.map(func(s): return {"id": s.id, "role": s.role, "time": s.time.duplicate()})
	stats.merge(ReportStats.summarize(stats, chapter.ui_thresholds), true)
	last_report = stats.duplicate(true)
	reports.append(last_report.duplicate(true))
	phase = "REPORT"
	paused = false
	revision += 1

func _award_service_stars() -> void:
	var completion_target = 0
	for target in chapter.completion_star_targets:
		if day < int(target.from_day): break
		completion_target = int(target.percent)
	var required_completions = ceili(float(stats.planned) * completion_target / 100.0)
	stats.completion_target = completion_target
	stats.completion_required = required_completions
	stats.star_goals = [int(stats.refused)==0, int(stats.wait_penalty_raw)==0 and int(stats.funnel.F)==0, int(stats.planned)>0 and int(stats.completed_before_midnight)>=required_completions]
	stats.stars_earned = stats.star_goals.count(true)
	stars += int(stats.stars_earned)
	stats.stars_after = stars

func continue_night() -> Dictionary:
	if phase != "REPORT" or last_report.get("result", "") != "CONTINUE":
		return {"ok": false, "error": tr("本章已经结束或尚未结算")}
	day += 1
	phase = "NIGHT"
	night_spend = 0
	tick = 0
	customers.clear()
	active_customers.clear()
	orders.clear()
	foods.clear()
	staff.clear()
	stoves.clear()
	_reset_seating()
	stats.clear()
	_refresh_shop()
	trophy_draws_today = 0
	revision += 1
	return {"ok": true}

func live_metrics() -> Dictionary:
	var result = {"queue": 0, "ready": 0, "food": 0, "eating": 0, "arrived": int(stats.get("arrived", 0)), "completed": int(stats.get("completed", 0)), "pending": 0, "at_pass": _active_foods("PASS").size(), "income": int(stats.get("income", 0))}
	for c in customers.values():
		if not c.terminal.is_empty():
			continue
		match c.state:
			"QUEUE": result.queue += 1
			"READY", "TAKING": result.ready += 1
			"FOOD": result.food += 1
			"EATING": result.eating += 1
	for o in orders.values():
		if o.status == "ACTIVE" and int(o.submitted_tick) >= 0 and o.supply not in ["SERVED", "WITH_WAITER"]:
			result.pending += 1
	return result

func invariant_errors() -> Array:
	var errors = []
	if gold < 0 or reputation < 0:
		errors.append(tr("资源为负"))
	var physical = 0
	var consumed = 0
	var discarded = 0
	for f in foods.values():
		if f.location == "CONSUMED": consumed += 1
		elif f.location == "DISCARDED": discarded += 1
		else: physical += 1
		if int(f.bound_order) != 0 and not _order_active(int(f.bound_order)):
			errors.append(tr("食品绑定了无效订单"))
	if not stats.is_empty() and int(stats.produced) != physical + consumed + discarded:
		errors.append(tr("食品不守恒"))
	if _active_foods("PASS").size() > pass_capacity:
		errors.append(tr("出餐口溢出"))
	for id in stoves:
		if _active_foods("SHELF", id).size() + int(stoves[id].output_reserved) > stove_capacity:
			errors.append(tr("厨房容量溢出"))
	var bound = {}
	for f in foods.values():
		if int(f.bound_order) != 0:
			if bound.has(int(f.bound_order)):
				errors.append(tr("订单重复食品绑定"))
			bound[int(f.bound_order)] = true
	for id in seats:
		var occupier = customers.get(int(seats[id]), {})
		if int(seats[id]) != 0 and (occupier.is_empty() or (not occupier.terminal.is_empty() and occupier.state != "STAYING")):
			errors.append(tr("座位预留未释放"))
	if phase == "REPORT":
		var count = 0
		for value in stats.funnel.values(): count += int(value)
		if count != int(stats.arrived) or int(stats.arrived) != int(stats.get("planned",arrival_plan.size())):
			errors.append(tr("客人漏斗不守恒"))
		if physical != 0:
			errors.append(tr("闭店后存在食品"))
	return errors

func export_state() -> Dictionary:
	# DAY is intentionally saved only as its already-committed pre-opening checkpoint.
	return {"save_version": chapter.save_version, "config_version": chapter.config_version, "chapter_id": chapter.id, "phase": phase, "day": day, "seed": seed_value, "gold": gold, "reputation": reputation, "total_reputation": total_reputation, "stars": stars, "owned_relics": owned_relics.duplicate(), "trophy_draws_total": trophy_draws_total, "trophy_draws_today": trophy_draws_today, "last_trophy_id": last_trophy_id, "trophy_rng_state": str(trophy_rng.state), "attributes": attributes.duplicate(true), "upgrade_purchases": upgrade_purchases.duplicate(true), "owned_recipes": owned_recipes.duplicate(), "menu": menu.duplicate(), "layout": layout.duplicate(true), "buff_states": buff_states.duplicate(true), "shop": shop.duplicate(true), "buff_bag": buff_bag.duplicate(), "shop_rng_state": str(shop_rng.state), "night_spend": night_spend, "reports": reports.duplicate(true), "last_report": last_report.duplicate(true), "major_event_claims": major_event_claims.duplicate(), "major_event_views": major_event_views.duplicate(), "crew_lineup":crew_lineup.duplicate(true), "helper_staff":helper_staff.duplicate(true), "legacy_trophies":legacy_trophies.duplicate()}

# A 0.8 gallery purchase is retained as an owned exhibit. It was paid for in
# stars, so it does not raise the first gold box price or the draw-based odds.
func _upgrade_gallery_v7(old: Dictionary) -> Dictionary:
	var upgraded := old.duplicate(true)
	var owned = upgraded.get("owned_relics")
	var layout_data = upgraded.get("layout")
	var old_offers = upgraded.get("trophy_shop")
	if not owned is Array or not layout_data is Dictionary or not old_offers is Array or old_offers.size()!=3:
		return {}
	for offer in old_offers:
		if not offer is Dictionary or not offer.has_all(["id","price","bought"]): return {}
		if not str(offer.id).is_empty() and not relic_defs.has(offer.id): return {}
	if not layout_data.get("plots") is Array or not layout_data.get("facilities") is Array: return {}
	var facilities: Array = layout_data.facilities.duplicate()
	for plot in layout_data.plots:
		if not plot is Dictionary or not plot.get("fixtures") is Array: return {}
		facilities.append_array(plot.fixtures)
	for f in facilities:
		if not f is Dictionary: return {}
		if f.get("id")=="trophy_shop" and f.get("type")=="trophy_shop" and f.get("name")=="奖杯商店":
			f.name = "奖杯盲盒"
	var gifts := _plot_gift_relics()
	upgraded.legacy_trophies = owned.filter(func(id):return not gifts.has(id))
	upgraded.trophy_draws_total=0
	upgraded.trophy_draws_today=0
	upgraded.last_trophy_id=""
	upgraded.erase("trophy_shop")
	upgraded.erase("trophy_refreshes")
	upgraded.save_version=chapter.save_version
	upgraded.config_version=chapter.config_version
	return upgraded

func restore_state(saved: Dictionary) -> Dictionary:
	if saved.get("config_version","")=="0.8.0" and saved.get("save_version",-1)==7 and saved.get("chapter_id","")==chapter.id:
		saved = _upgrade_gallery_v7(saved)
		if saved.is_empty(): return {"ok":false,"error":tr("旧奖杯记录无效")}
	if saved.get("config_version", "") != str(chapter.config_version) or int(saved.get("save_version", -1)) != int(chapter.save_version) or saved.get("chapter_id", "") != chapter.id:
		return {"ok": false, "error": tr("存档版本不兼容，请重新开始本章")}
	if saved.get("phase", "") not in ["NIGHT", "REPORT"] or int(saved.get("day", 0)) < 1 or int(saved.get("day", 0)) > int(chapter.chapter_days):
		return {"ok": false, "error": "存档阶段无效"}
	for key in ["seed", "gold", "reputation", "attributes", "upgrade_purchases", "owned_recipes", "menu", "layout", "buff_states", "shop", "reports", "last_report", "shop_rng_state", "stars", "owned_relics", "trophy_draws_total", "trophy_draws_today", "last_trophy_id", "trophy_rng_state"]:
		if not saved.has(key):
			return {"ok": false, "error": tr("存档缺少字段：") + key}
	for key in ["attributes","upgrade_purchases","layout","buff_states","last_report"]:
		if not saved[key] is Dictionary: return {"ok":false,"error":tr("存档对象类型无效：")+key}
	for key in ["owned_recipes","menu","shop","reports","owned_relics"]:
		if not saved[key] is Array: return {"ok":false,"error":tr("存档列表类型无效：")+key}
	var saved_helpers = saved.get("helper_staff",{})
	if not Minions.valid(saved_helpers): return {"ok":false,"error":tr("小兵排班无效")}
	var saved_crew = saved.get("crew_lineup", [])
	if not saved_crew is Array or (not saved_crew.is_empty() and not Crew.valid(saved_crew)):
		return {"ok":false,"error":tr("存档阵容无效")}
	var claims = saved.get("major_event_claims", [])
	if not claims is Array: return {"ok":false,"error":tr("重大事件领取记录格式错误")}
	var views = saved.get("major_event_views", [])
	if not views is Array or views.any(func(id): return not id is String or not chapter.events.get(id, {}).has("notice")):
		return {"ok": false, "error": tr("重大事件查看记录无效")}
	var unique_claims = {}
	for id in claims:
		if not id is String or unique_claims.has(id) or not chapter.events.get(id, {}).has("notice"):
			return {"ok":false,"error":tr("重大事件领取记录无效")}
		unique_claims[id] = true
	for key in ["width","height","entrance","exit","waiter_spawn","chef_spawn","facilities","plots","unlocked_plots"]:
		if not saved.layout.has(key): return {"ok":false,"error":tr("存档布局缺字段：")+key}
	if saved.layout.plots != chapter.land_plots or not saved.layout.unlocked_plots is Array or saved.layout.unlocked_plots.size() > chapter.land_plots.size():
		return {"ok":false,"error":tr("存档地块配置无效")}
	for i in range(saved.layout.unlocked_plots.size()):
		if str(saved.layout.unlocked_plots[i])!=str(chapter.land_plots[i].id):
			return {"ok":false,"error":tr("存档地块解锁顺序无效")}
	for key in chapter.initial_attributes:
		if not saved.upgrade_purchases.has(key) or int(saved.upgrade_purchases[key])<0:
			return {"ok":false,"error":tr("存档升级次数无效")}
	if not saved.layout.facilities is Array:
		return {"ok": false, "error": tr("存档设施列表无效")}
	for f in saved.layout.facilities:
		if not f is Dictionary or not f.has_all(["id", "type", "name", "pos"]):
			return {"ok": false, "error": tr("存档设施无效")}
		if f.type == "decoration":
			var def = decoration_defs.get(f.get("decoration_id", ""), {})
			if def.is_empty() or f.get("extent", []) != def.extent or "decor_studio" not in saved.layout.unlocked_plots:
				return {"ok": false, "error": tr("存档装饰无效")}
	if not Grid.errors(saved.layout).is_empty(): return {"ok":false,"error":tr("存档地块或设施位置无效")}
	for offer in saved.shop:
		if not offer is Dictionary or not offer.has_all(["type","id","price","bought"]): return {"ok":false,"error":tr("存档商品结构无效")}
		if int(offer.price)<0 or offer.type not in ["recipe","buff","empty","empty_buff"]: return {"ok":false,"error":tr("存档商品价格 / 类型无效")}
		if (offer.type=="recipe" and not recipes.has(offer.id)) or (offer.type=="buff" and not buff_defs.has(offer.id)):
			return {"ok":false,"error":"存档商品引用无效"}
	if int(saved.stars) < 0 or not saved.trophy_rng_state is String or not str(saved.trophy_rng_state).is_valid_int():
		return {"ok": false, "error": "存档闪星或盲盒随机状态无效"}
	var unique_relics = {}
	var gifts = _plot_gift_relics()
	var collected = 0
	for id in saved.owned_relics:
		if not relic_defs.has(id) or unique_relics.has(id): return {"ok":false,"error":tr("存档奖杯重复或不存在")}
		unique_relics[id] = true
		if not gifts.has(id): collected += 1
	for key in ["trophy_draws_total", "trophy_draws_today"]:
		var count = saved[key]
		if not (count is int or count is float) or not is_finite(float(count)) or count < 0 or count > collected or floorf(float(count)) != float(count):
			return {"ok": false, "error": "存档盲盒次数无效"}
	var inherited = saved.get("legacy_trophies",[])
	if not inherited is Array: return {"ok":false,"error":tr("旧奖杯记录无效")}
	var seen_inherited: Dictionary = {}
	for id in inherited:
		if not unique_relics.has(id) or gifts.has(id) or seen_inherited.has(id):
			return {"ok":false,"error":tr("旧奖杯记录无效")}
		seen_inherited[id]=true
	var drawn: int = collected-inherited.size()
	var last = saved.last_trophy_id
	if int(saved.trophy_draws_total) != drawn or int(saved.trophy_draws_today) > drawn or not last is String or (drawn == 0 and not last.is_empty()) or (drawn > 0 and (not unique_relics.has(last) or gifts.has(last) or seen_inherited.has(last))):
		return {"ok": false, "error": "存档盲盒记录与背包不一致"}
	if collected > 0 and "trophy_gallery" not in saved.layout.unlocked_plots:
		return {"ok": false, "error": "存档盲盒未解锁"}
	var placed_relics = 0
	var entity_ids = {}
	for f in saved.layout.facilities:
		if f.get("type","") != "trophy": continue
		if not unique_relics.has(f.get("relic_id","")) or str(f.get("id","")) != "trophy_"+str(f.get("relic_id","")):
			return {"ok":false,"error":tr("奖杯实体与背包不一致")}
		if entity_ids.has(f.relic_id): return {"ok":false,"error":tr("奖杯实体重复")}
		entity_ids[f.relic_id] = true
		if Grid.placed(f):
			placed_relics += 1
			var cell = Vector2i(Grid.vec(f.pos))
			var zone = chapter.trophy_zone
			if cell.x < int(zone.left) or cell.x > int(zone.right) or cell.y < int(zone.top) or cell.y > int(zone.bottom): return {"ok":false,"error":tr("奖杯位置超出展示区")}
	if entity_ids.size()!=unique_relics.size(): return {"ok":false,"error":tr("奖杯背包缺少实体")}
	if placed_relics > int(saved.attributes.get("relic_slots",0)):
		return {"ok":false,"error":tr("奖杯超过当前展示上限")}
	if saved.phase=="REPORT":
		for key in ["result","income","completed","planned","arrived","funnel","seat_utilization","stove_utilization","queue_wait_summary","food_wait_summary","order_wait_summary","staff_times","income_guests","produced","consumed","discarded","tips","diagnosis","income_recipes","rep_base","rep_buff","wait_penalty_raw","wait_penalty_actual","quality_penalty_raw","quality_penalty_actual","night_spend","payer_count","rent_amount","rent_ok","completion_target","completion_required","star_goals","stars_earned","stars_after"]:
			if not saved.last_report.has(key): return {"ok":false,"error":tr("存档报告缺字段：")+key}
	if saved.phase=="REPORT" and (not saved.last_report.get("star_goals",[]) is Array or saved.last_report.star_goals.size()!=3 or int(saved.last_report.get("stars_after",-1))!=int(saved.stars)):
		return {"ok":false,"error":tr("存档三星记录无效")}
	if saved.phase=="REPORT" and saved.last_report.get("result","") not in ["CONTINUE","WIN","LOSE"]:
		return {"ok":false,"error":tr("存档报告结果无效")}
	if int(saved.gold) < 0 or int(saved.reputation) < 0 or saved.menu.is_empty() or saved.shop.size() != 3:
		return {"ok": false, "error": tr("存档资源 / 菜单无效")}
	if saved.menu.size()>int(saved.attributes.get("menu_slots",0)):
		return {"ok":false,"error":tr("存档菜单超过容量")}
	for id in saved.owned_recipes:
		if not recipes.has(id): return {"ok": false, "error": tr("存档菜谱无效")}
	for id in saved.menu:
		if id not in saved.owned_recipes: return {"ok": false, "error": tr("存档菜单未解锁")}
	for key in chapter.initial_attributes:
		if not saved.attributes.has(key) or int(saved.attributes[key]) < 1 or int(saved.attributes[key]) > int(chapter.attribute_caps[key]):
			return {"ok": false, "error": tr("存档容量无效")}
	for id in saved.buff_states:
		if not saved.buff_states[id] is Dictionary or not saved.buff_states[id].has_all(["stack_count","remaining_days"]):
			return {"ok":false,"error":tr("存档Buff结构无效")}
		if not buff_defs.has(id) or int(saved.buff_states[id].stack_count) < 1 or int(saved.buff_states[id].stack_count) > int(buff_defs[id].max_stacks) or int(saved.buff_states[id].remaining_days) < 1:
			return {"ok": false, "error": tr("存档 Buff 无效")}
	if saved.layout.get("facilities", []).is_empty():
		return {"ok": false, "error": tr("存档布局为空")}
	phase = saved.phase
	day = int(saved.day)
	seed_value = int(saved.seed)
	gold = int(saved.gold)
	reputation = int(saved.reputation)
	total_reputation = int(saved.get("total_reputation", 0))
	stars = int(saved.stars)
	owned_relics = saved.owned_relics.duplicate()
	legacy_trophies = inherited.duplicate()
	trophy_draws_total = int(saved.trophy_draws_total)
	trophy_draws_today = int(saved.trophy_draws_today)
	last_trophy_id = str(saved.last_trophy_id)
	attributes = saved.attributes.duplicate(true)
	for key in attributes: attributes[key] = int(attributes[key])
	upgrade_purchases = saved.upgrade_purchases.duplicate(true)
	for key in upgrade_purchases: upgrade_purchases[key] = int(upgrade_purchases[key])
	attributes.relic_slots = mini(int(chapter.attribute_caps.relic_slots), int(chapter.initial_attributes.relic_slots) + int(upgrade_purchases.relic_slots) * int(chapter.upgrade_rules.relic_slots.get("step", 1)))
	owned_recipes = saved.owned_recipes.duplicate()
	menu = saved.menu.duplicate()
	layout = saved.layout.duplicate(true)
	buff_states = saved.buff_states.duplicate(true)
	for id in buff_states:
		buff_states[id].stack_count = int(buff_states[id].stack_count)
		buff_states[id].remaining_days = int(buff_states[id].remaining_days)
	shop = saved.shop.duplicate(true)
	for offer in shop: offer.price = int(offer.price)
	buff_bag = saved.get("buff_bag", []).duplicate()
	shop_rng.seed = abs(hash("%d/shop" % seed_value))
	shop_rng.state = int(saved.shop_rng_state)
	trophy_rng.seed = abs(hash("%d/trophy" % seed_value))
	trophy_rng.state = int(saved.trophy_rng_state)
	night_spend = int(saved.get("night_spend", 0))
	reports = saved.reports.duplicate(true)
	last_report = saved.last_report.duplicate(true)
	major_event_claims = claims.duplicate()
	major_event_views = views.duplicate()
	crew_lineup = saved_crew.duplicate(true)
	helper_staff = saved_helpers.duplicate(true)
	stats = last_report.duplicate(true) if phase == "REPORT" else {}
	_reset_seating()
	tick = day_ticks if phase == "REPORT" else 0
	customers = {}
	active_customers = {}
	orders = {}
	foods = {}
	staff = []
	stoves = {}
	revision += 1
	return {"ok": true}
