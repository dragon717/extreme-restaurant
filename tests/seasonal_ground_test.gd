extends SceneTree
const Sim = preload("res://scripts/core/simulation.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Calendar = preload("res://scripts/core/seasons.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func percentile(values: Array, fraction: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return float(ordered[clampi(ceili(fraction*ordered.size())-1,0,ordered.size()-1)])

func stress(stage, with_steps: bool, business = null) -> Dictionary:
	var effect = stage.seasonal_ground
	var timing := []
	var frames := []
	var last := Time.get_ticks_usec()
	for frame in range(140):
		if business != null:
			if frame % 2 == 0: business.sim.step()
			business.world._process(1./60.)
			if frame % 9 == 0: business._update_hud()
		var started := Time.get_ticks_usec()
		if with_steps:
			effect.advance(1./60.,false,stage.camera.basis)
			for guest in range(32):
				var t := fposmod(float(frame)*.004+guest*.019,1.)
				var p: Vector2 = effect.Plan.route(effect.COURT_PATH,t)
				effect.observe("load_%d"%guest,p+Vector2(guest%3*.17,0),stage.ground_view)
		if frame >= 20: timing.append((Time.get_ticks_usec()-started)/1000.)
		await process_frame
		var now := Time.get_ticks_usec()
		if frame >= 20: frames.append((now-last)/1000.)
		last = now
	return {"step_p95_ms":percentile(timing,.95),"frame_p95_ms":percentile(frames,.95),"frame_p50_ms":percentile(frames,.5)}

func snap(label: String) -> void:
	for n in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	if "--capture-season" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("res://.local/season-"+label+".png")

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	var sim := Sim.new()
	sim.day = 15
	Store.write_checkpoint(sim.export_state(),Store.default_path("street_corner",true))
	Store.write_checkpoint({"mode":"off","seen":{}},Store.default_path("tutorial_progress",true))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.guide.skip()
	game.set_process(false)
	var world = game.world
	world.set_process(false)
	world.set_roof_view(false)
	world.zoom = 1.65
	world._process(.1)
	var gate := Vector2(-2.6,13.1)
	world.camera_pan += world.size*Vector2(.46,.54)-world.screen_point(gate)
	world._process(.1)
	var stage = world.district_3d
	var effect = stage.seasonal_ground
	for day in [1,7,8,14,15,21,22,28]:
		game.sim.day = day
		game._refresh_all()
		world._process(.033)
		check(stage.season == Calendar.at_day(day) and game.soundtrack.season == stage.season and effect.season == stage.season and game.ui.hub.get_node("Service/Season").text==Calendar.NAMES[stage.season],"音乐、地面和界面按第 %d 天一致换季"%day)
	game.sim.day = 15
	game._refresh_all()
	world._process(.1)
	var first: PackedVector2Array = effect.leaves.duplicate()
	var sample: Vector2 = effect.leaves[0]
	effect.observe("test",sample-Vector2(.72,0),stage.ground_view)
	effect.observe("test",sample,stage.ground_view)
	for n in range(55): world._process(1./30.)
	check(effect.displaced>0 and effect.leaves!=first,"脚步拨开真实地面落叶，静止后位置保留")
	var total := 0
	for bucket in effect.bins.values(): total += bucket.size()
	check(total+effect.flying.size()==effect.LEAVES,"落叶落回地面，不增殖且空间索引一致")
	if stage.season_tween != null: stage.season_tween.custom_step(2.0)
	await snap("autumn")
	game.sim.day=22
	game._refresh_all()
	world._process(.1)
	for n in range(65): world._process(1./30.)
	check(not effect.impressions.is_empty() and effect.displaced>0 and effect.flying.is_empty(),"换季清除秋叶，真实行人沿当前路线踩出雪印")
	var stamp: int = effect.steps
	var held := float(effect.time)
	for n in range(20): stage.advance_outdoors(1./60.,true)
	check(effect.steps==stamp and is_equal_approx(effect.time,held),"暂停冻结脚印、踢雪和行人的动作")
	var p: Vector2 = effect.COURT_PATH[3]
	effect.observe("boot",p-Vector2(.7,0),stage.ground_view)
	effect.observe("boot",p,stage.ground_view)
	effect.advance(1./30.,false,stage.camera.basis)
	check(not effect.spray[0].is_empty() and not effect.spray[1].is_empty(),"踏雪同时留下压痕、贴地雪雾和扬起的冰粒")
	if stage.season_tween != null: stage.season_tween.custom_step(2.0)
	await snap("winter")
	var baseline := await stress(stage,false)
	var winter := await stress(stage,true)
	check(effect.impressions.size()<=effect.PRINTS and effect.spray[0].size()<=effect.PUFFS and effect.spray[1].size()<=effect.FLECKS,"高客流仅复用预分配的三层雪地效果")
	stage.set_day(15)
	var autumn := await stress(stage,true)
	check(effect.flying.size()<=48 and effect.batches.size()==5,"秋叶并发与所有实例批次均有上限")
	game.sim.stars = 99
	game.sim.day = 22
	for plot in game.sim.layout.plots:
		check(game.sim.unlock_land_plot(plot.id).ok,"实测扩建地块 "+str(plot.id))
	game._refresh_all()
	world._process(.1)
	game._open_day()
	check(game.sim.phase == "DAY","营业压力场景实际开店")
	for id in range(700,732): game.sim._spawn_customer({"id":id,"type":"normal"})
	for n in range(32): game.sim.step()
	var full_service := await stress(stage,true,game)
	print("FULL SERVICE / 8 building sections / 32 additional guests / ",full_service)
	print("SEASON GROUND ",checks-failures,"/",checks," / 32 walkers / ",root.size," / baseline=",baseline," winter=",winter," autumn=",autumn)
	game.queue_free()
	await create_timer(.6).timeout
	quit(1 if failures else 0)
