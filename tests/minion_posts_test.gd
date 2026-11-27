extends SceneTree
const Sim=preload("res://scripts/core/simulation.gd")
const Rules=preload("res://scripts/core/rules.gd")
const Crew=preload("res://scripts/core/crew_roster.gd")
var passed:=0
var failed:=0
func check(ok: bool,what: String) -> void:
	if ok:passed+=1
	else:
		failed+=1
		push_error(what)
func _initialize():run.call_deferred()
func run():
	var s:=Sim.new()
	var team: Array=[]
	for id in Crew.STARTERS:team.append({"id":id,"role":Crew.PROFILES[id].roles[0]})
	s.set_crew(team)
	s.helper_staff={"chef":["caster"],"waiter":["siege"]}
	var saved:=s.export_state()
	var copy:=Sim.new()
	check(copy.restore_state(saved).ok and copy.helper_at("waiter",3)=="siege","新档记录每个补位兵")
	saved.erase("helper_staff")
	check(copy.restore_state(saved).ok and copy.helper_at("waiter",3)=="melee","旧档默认近战小兵")
	saved.helper_staff={"waiter":["invalid"]}
	check(not copy.restore_state(saved).ok,"非法兵种不会进入模拟")
	s.start_day()
	check(s.staff.size()==6 and s.staff.filter(func(w):return w.minion=="siege").size()==1 and s.staff.filter(func(w):return w.crew_id!="" and w.minion!="").is_empty(),"五位特色员工加一小兵，英雄不叠加小兵专长")
	var cook: Dictionary=s.staff.filter(func(w):return w.role=="chef")[0].duplicate(true)
	var waiter: Dictionary=s.staff.filter(func(w):return w.role=="waiter")[0].duplicate(true)
	s.orders[804]={"status":"ACTIVE"}
	s.customers[803]={"state":"READY","terminal":"","reserved_by":waiter.id}
	for cell in [[cook,"melee","COOK",1.06],[cook,"siege","TRANSFER",1.08],[waiter,"melee","ORDER",1.06],[waiter,"siege","DELIVER",1.08],[waiter,"caster","DELIVER",1.],[cook,"melee","TRANSFER",1.]]:
		var w: Dictionary=cell[0]
		w.pos=Vector2(3.,3.)
		w.path=[w.pos+Vector2.RIGHT*4.]
		w.minion=cell[1]
		w.crew_id=""
		w.task={"stage":"MOVE","kind":cell[2],"customer_id":803,"order_id":804}
		var base:=float(s.chapter.movement.chef_speed if w.role=="chef" else s.chapter.movement.waiter_speed)
		s._advance_staff(w)
		check(is_equal_approx(w.pos.x-3.,base*float(cell[3])*s.tick_ms/1000.),"实际移动 "+w.role+" "+str(cell[1])+" "+str(cell[2]))
	cook.crew_id=""
	cook.minion="caster"
	cook.finished_pots=0
	cook.task={"kind":"COOK","recipe":"starter_rice","stove_id":"stove_1"}
	s._arrive_task(cook)
	var seconds: float=float(s.recipes.starter_rice.cook_seconds)/(1.+s.modifiers.cook+s.fixture_bonus("stove_1","stove_speed"))
	check(cook.task.done_tick-s.tick==Rules.ticks(seconds*.96,s.tick_ms),"法师在后厨实际缩短锅时")
	waiter.minion="caster"
	waiter.task={"kind":"ORDER","customer_id":803}
	s._arrive_task(waiter)
	check(waiter.task.done_tick-s.tick==Rules.ticks(s.chapter.movement.interaction_seconds*.90,s.tick_ms),"法师在前厅实际缩短点单时间")
	print("MINION POSTS ",passed," passed / ",failed," failed")
	quit(1 if failed else 0)
