extends SceneTree

const Sim = preload("res://scripts/core/simulation.gd")
const Rules = preload("res://scripts/core/rules.gd")
var errors := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	var sim = Sim.new()
	check(not sim.call_current(), "技能限营业使用")
	check(sim.start_day().ok, "第一天可以营业")
	sim.paused = true
	check(not sim.call_current(), "暂停禁用急送")
	sim.paused = false
	check(sim.call_current() and not sim.call_current(), "一次施放只开启一个区域")
	var finish: int = sim.current_until
	var ready: int = sim.current_ready
	check(finish == Rules.ticks(8.0, sim.tick_ms), "水流持续 8 秒")
	check(ready == Rules.ticks(28.0, sim.tick_ms), "急送冷却 28 秒")
	var saw_flare := false
	var saw_haste := false
	var limit: int = sim.midnight_ticks * 4
	while sim.phase == "DAY" and sim.tick < limit:
		sim.step()
		if sim.tick == ready:
			check(sim.call_current(), "冷却边界允许再次施放")
		elif sim.tick > ready and sim.tick >= sim.current_ready:
			sim.call_current()
		for s in sim.staff:
			if int(s.get("haste_until", 0)) > sim.tick: saw_haste = true
			if s.task.get("flare", false):
				saw_flare = true
				check(int(s.finished_pots) % 3 == 2, "第三锅触发旺火")
				var base: float = sim.recipes[s.task.recipe].cook_seconds / (1.0 + sim.modifiers.cook + sim.fixture_bonus(s.task.stove_id, "stove_speed"))
				check(s.task.done_tick - s.task.started_tick == Rules.ticks(base * 0.5, sim.tick_ms), "旺火耗时减半")
		if not sim.invariant_errors().is_empty():
			check(false, "食物和订单不变约束")
			break
	check(saw_flare and saw_haste and sim.phase == "REPORT", "完整营业触发两种技能并进入日结")
	print("CANYON_SERVICE errors=", errors)
	quit(1 if errors else 0)
