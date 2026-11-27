extends SceneTree

const Crew = preload("res://scripts/core/crew_roster.gd")
const Sim = preload("res://scripts/core/simulation.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Store = preload("res://scripts/core/save_store.gd")

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _lineup(oven_role: String) -> Array:
	return [{"id":"kilnkeeper","role":"chef"}, {"id":"ovenhand","role":oven_role}, {"id":"ferrier","role":"waiter"}, {"id":"riverclaw","role":"waiter"}, {"id":"mosskeeper","role":"waiter"}]

func _run() -> void:
	for role in ["chef", "waiter"]:
		var sim := Sim.new()
		var lineup := _lineup(role)
		check(Crew.valid(lineup) and sim.set_crew(lineup), "Valid opening lineup " + role)
		var checkpoint := sim.export_state()
		check(sim.start_day().ok, "Roster starts service")
		check(sim.staff.size() == 6 and sim.staff.filter(func(worker): return not str(worker.crew_id).is_empty()).size() == 5, "Five specialty staff and one helper")
		check(sim.staff.any(func(worker): return worker.crew_id == "ovenhand" and worker.role == role), "Flexible staff assigned once to chosen role")
		check(sim.call_current(), "River Rush remains manual")
		var restored := Sim.new()
		check(restored.restore_state(checkpoint).ok and restored.crew_lineup == lineup, "Crew survives checkpoint reload")
		checkpoint.erase("crew_lineup")
		check(restored.restore_state(checkpoint).ok and restored.crew_lineup.is_empty(), "Legacy checkpoints remain compatible")
	var duplicate := _lineup("chef")
	duplicate[1] = duplicate[0].duplicate()
	check(not Crew.valid(duplicate), "Duplicate crew member rejected")
	var incompatible := _lineup("chef")
	incompatible[0].role = "waiter"
	check(not Crew.valid(incompatible), "Unsupported role rejected")

	var profile := Crew.new(true)
	profile.groups.clear()
	profile.file_path = "user://crew-roster-probe-%d.json" % Time.get_ticks_usec()
	check(profile.save_group(-1,"Bend",_lineup("chef")).is_empty(), "Save a named group")
	check(profile.save_group(0,"East Bank",_lineup("waiter")).is_empty(), "Rename and replace a saved group")
	var stored := Store.read_checkpoint(profile.file_path)
	check(stored.groups.size() == 1 and stored.groups[0].name == "East Bank" and stored.groups[0].crew[1].role == "waiter", "Group writes are durable")
	var profile_path := ProjectSettings.globalize_path(profile.file_path)
	for candidate in [profile_path, profile_path + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(candidate)

	var service := Sim.new()
	service.set_crew(_lineup("chef"))
	service.start_day()
	check(not service.call_linked_fire() and service.linked_fire_ready == 0, "Empty prep consumes no skill")
	var cooks: Array = service.staff.filter(func(worker): return worker.role == "chef")
	var burners := Grid.facilities(service.layout, "stove")
	cooks[0].pos = Grid.vec(burners[0].pos)
	for i in range(2):
		var cook: Dictionary = cooks[i]
		var burner: Dictionary = burners[i]
		var id := 100 + i
		service.orders[id] = {"id":id, "status":"ACTIVE", "supply":"COOKING", "supply_owner":cook.id, "recipe":"starter_rice", "submitted_tick":0}
		service.stoves[burner.id].owner = cook.id
		service.stoves[burner.id].output_reserved = int(service.recipes.starter_rice.batch_yield)
		cook.task = {"kind":"COOK", "stage":"MOVE", "stove_id":burner.id, "recipe":"starter_rice", "order_ids":[id]}
		service._arrive_task(cook)
	service.tick = 7
	check(service.linked_fire_targets().size() == 2, "Two nearby prepared stoves are eligible")
	var before: Array = cooks.map(func(cook): return cook.task.done_tick)
	check(service.call_linked_fire() and service.linked_fire_stoves.size() == 2, "Manual fire uses the two available stoves")
	for i in range(2):
		check(cooks[i].task.stage == "ACTION" and cooks[i].task.done_tick < before[i] and cooks[i].task.order_ids == [100+i], "Ignition preserves the reserved order")
	check(not service.call_linked_fire(), "Cooldown prevents a duplicate cast")
	for cook in cooks: service._complete_action(cook)
	check(service.stats.produced == int(service.recipes.starter_rice.batch_yield) * 2, "Each pot produces its normal batch once")
	check(service.orders[100].food != service.orders[101].food and service.orders[100].supply == "IN_TRANSIT" and service.orders[101].supply == "IN_TRANSIT", "Orders receive distinct food and resume normal handoff")
	print("CREW RESULT: %d passed / %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
