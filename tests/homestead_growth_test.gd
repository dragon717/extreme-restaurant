extends SceneTree

const Sim = preload("res://scripts/core/simulation.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Catalog = preload("res://scripts/core/catalog.gd")
var failures := 0
var passed := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failures += 1
		push_error(label)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	if "--capture-growth" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("res://.local/growth-" + label + ".png")

func room_area(sim) -> int:
	var tiles := 0
	for y in range(int(sim.layout.height)):
		for x in range(int(sim.layout.width)):
			if Grid.has_room(sim.layout, Vector2i(x,y)): tiles += 1
	return tiles

func check_roof(stage,expected: int) -> void:
	var rings: Array = stage.canopy._outline()
	check(rings.size() == 1 and rings[0].size() >= 4,"实有房间的屋檐闭合成一个外圈")
	var area := 0.0
	for panel: MeshInstance3D in stage.roof_panels:
		var arrays := panel.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var a := verts[indices[i]]
			var b := verts[indices[i+1]]
			var c := verts[indices[i+2]]
			area += absf((b-a).cross(c-a).y)*.5/stage.DEPTH
	check(absf(area-expected)<.03, "大屋面在地面的正投影与已开放格数完全相符")

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Run in a graphical test window with -- --ui-test.")
		quit(1)
		return
	Store.write_checkpoint(Sim.new().export_state(), Store.default_path("street_corner", true))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.guide.skip()
	game.set_process(false)
	var world = game.world
	world.focus_restaurant()
	await process_frame
	await process_frame
	world.set_process(false)
	world._process(0.0)
	var district = world.district_3d
	check(district.wings.size() == 1 and district.wings.has("homestead"), "开局只建一间小屋")
	check(room_area(game.sim) == 168, "起始可经营面积为 12×14")
	check(world.plot_buttons.values().filter(func(m): return m.button.visible).size() == 1, "只展示下一处扩建入口")
	check_roof(district,168)
	await capture("opening")
	game._unlock_land("purchase_annex")
	check(district.construction.is_empty() and district.wings.size() == 1, "条件未满足时不施工")
	game.sim.day = 22
	game.sim.stars = 40
	var previous := room_area(game.sim)
	var checkpoint := {}
	for plot in game.sim.layout.plots.duplicate(true):
		var before: int = game.sim.stars
		game._show_plot_confirmation(plot.id)
		game.modal_layer.find_child("ConfirmLandUnlock",true,false).pressed.emit()
		check(game.sim.stars == before-int(plot.star_cost) and district.construction.has(plot.id), "确认扩建扣款一次并启动演出 " + plot.id)
		var layers: Dictionary = district.wings[plot.id]
		check(not layers.frame.visible and not layers.roof.visible, "施工先铺地 " + plot.id)
		var b = plot.bounds
		previous += (int(b.right) - int(b.left) + 1) * (int(b.bottom) - int(b.top) + 1)
		check(room_area(game.sim) == previous, "增加实际经营面积 " + plot.id)
		check_roof(district,previous)
		world._process(.67)
		check(layers.frame.visible and layers.frame.scale.y < 1 and not layers.roof.visible, "外墙和木架正在搭起 " + plot.id)
		if plot.id == "purchase_annex": await capture("building")
		world._process(1.5)
		check(layers.roof.visible and is_equal_approx(layers.frame.scale.y,1.0) and district.construction.is_empty(), "檐口和家具就位 " + plot.id)
		if plot.id == "purchase_annex":
			checkpoint = game.sim.export_state()
			await capture("first-wing")
			game._unlock_land(plot.id)
			check(game.sim.stars == before-int(plot.star_cost) and district.construction.is_empty(), "重复确认不会重复扣款或重播")
	check(district.wings.size() == 8 and previous == 600, "七次扩建覆盖全部室内面积")
	await capture("complete")
	var restored := Sim.new()
	check(restored.restore_state(checkpoint).ok, "可恢复中途存档")
	world.sim = restored
	world._process(0)
	check(district.wings.size() == 2 and district.construction.is_empty(), "读档直接显示已建阶段")
	var market := Sim.new(Catalog.load_all("market_lane"))
	world.sim = market
	world._process(0)
	check(district.wings.size() == 1 and room_area(market) == 168, "第二章同样从小屋开始")
	print("GROWTH RESULT: %d passed / %d failed" % [passed,failures])
	quit(0 if failures == 0 else 1)
