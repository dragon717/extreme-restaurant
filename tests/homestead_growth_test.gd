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
	var ghost = district.projection
	var first_cell := Vector2i(18,10)
	check(ghost.visible and ghost.plot_id=="purchase_annex" and ghost.bounds==Rect2i(13,7,8,8) and not ghost.available, "开局仅预告与主屋相连的采购小厅")
	var first_visual: int = ghost.get_child(0).get_instance_id()
	check(Grid.blocked(game.sim.layout,first_cell) and not Grid.has_room(game.sim.layout,first_cell), "虚影保留未购地块的碰撞和经营范围")
	check(ghost.find_children("*","MeshInstance3D",true,false).all(func(piece): return piece.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "虚影不会向人物和地面投射实体阴影")
	check(world._preview_plot_at(first_cell)=="purchase_annex" and world._preview_plot_at(Vector2i(24,10)).is_empty(), "整块预告可点，下一顺位之后的空地不响应")
	var point: Vector2 = world.screen_point(Vector2(first_cell))
	world._primary_pointer(point,true)
	world._primary_pointer(point,false)
	check(game.modal_kind=="plot_unlock" and game.modal_layer.find_child("ConfirmLandUnlock",true,false).disabled, "直接点待开放地面可查看解锁条件")
	game._close_modal()
	world._primary_pointer(point,true)
	world._primary_pointer(point+Vector2(24,0),false)
	check(game.modal_layer==null, "从虚影上拖动不会误开扩建确认")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = true
	world._handle_touch(touch)
	var second_finger := touch.duplicate() as InputEventScreenTouch
	second_finger.index = 1
	second_finger.position += Vector2(40,0)
	world._handle_touch(second_finger)
	second_finger.pressed = false
	world._handle_touch(second_finger)
	touch.pressed = false
	world._handle_touch(touch)
	check(game.modal_layer==null and world.pressed_plot.is_empty(), "虚影上的双指操作不会触发购买入口")
	touch.pressed = true
	world._handle_touch(touch)
	touch.pressed = false
	world._handle_touch(touch)
	check(game.modal_kind=="plot_unlock","单指轻点虚影打开同一确认页")
	game._close_modal()
	world.editing = true
	world._sync_plot_buttons()
	check(ghost.visible and world.plot_buttons.purchase_annex.button.disabled, "布置期间能看到房间轮廓，设施摆放优先")
	world.editing = false
	game.sim.phase = "DAY"
	world._sync_plot_buttons()
	check(not ghost.visible and world._preview_plot_at(first_cell).is_empty(), "营业时隐藏地块提示和点击入口")
	game.sim.phase = "NIGHT"
	world._sync_plot_buttons()
	await capture("opening")
	game._unlock_land("purchase_annex")
	check(district.construction.is_empty() and district.wings.size() == 1, "条件未满足时不施工")
	game.sim.day = 3
	world._sync_plot_buttons()
	check(not ghost.available and world.plot_buttons.purchase_annex.label.text == "闪星不足", "日期达标而闪星不足时维持待建虚影")
	game.sim.stars = 1
	game._refresh_all()
	game.ui.toast_card.hide()
	world._sync_plot_buttons()
	check(ghost.available and ghost.get_child(0).get_instance_id()==first_visual and world.plot_buttons.purchase_annex.label.text=="可扩建", "满足条件原位变色且复用同一组模型")
	await capture("eligible")
	var language := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	world._sync_plot_buttons()
	check(world.plot_buttons.purchase_annex.label.text=="Expand", "英文同步提示可扩建状态")
	TranslationServer.set_locale(language)
	game.sim.day = 22
	game.sim.stars = 40
	game._refresh_all()
	var previous := room_area(game.sim)
	var checkpoint := {}
	for plot in game.sim.layout.plots.duplicate(true):
		var before: int = game.sim.stars
		var ground_point: Vector2 = world.screen_point(Vector2(first_cell))
		if plot.id == "purchase_annex":
			world._primary_pointer(ground_point,true)
			world._primary_pointer(ground_point,false)
		else:
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
		check(ghost.plot_id==game.sim.next_land_plot().get("id","") and (ghost.plot_id!=plot.id), "施工接管原地，预告顺移 " + plot.id)
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
	check(not ghost.visible and ghost.get_child_count()==0, "全开后释放虚影")
	await capture("complete")
	var restored := Sim.new()
	check(restored.restore_state(checkpoint).ok, "可恢复中途存档")
	world.sim = restored
	world._process(0)
	check(ghost.visible and ghost.plot_id=="trophy_gallery","读档从已购地块接续预告")
	check(district.wings.size() == 2 and district.construction.is_empty(), "读档直接显示已建阶段")
	var market := Sim.new(Catalog.load_all("market_lane"))
	world.sim = market
	world._process(0)
	check(district.wings.size() == 1 and room_area(market) == 168, "第二章同样从小屋开始")
	game.sim = market
	market.stars = 99
	market.day = 22
	var door_id: int = district.doorway.get_instance_id()
	var lamp_id: int = district.porch_lamps[0].get_instance_id()
	for plot in market.layout.plots:
		game._unlock_land(plot.id)
		check(district.construction.has(plot.id), "第二章启动施工 " + str(plot.id))
		if plot.id == "south_dining":
			world._process(.43)
			continue
		if plot.id == "garden_dining":
			var previous_wing: Dictionary = district.wings.south_dining
			check(not previous_wing.across and is_equal_approx(district.construction.south_dining,.43), "连续扩建沿南侧客席原接缝接着铺地")
			check(not previous_wing.roof.get_node("Soffit").is_visible_in_tree(), "新房檐底随各自屋面施工")
			var early := false
			for fixture_id in district.fixture_plots:
				if district.fixture_plots[fixture_id] in ["south_dining", "garden_dining"]:
					early = early or district.fixture_models[fixture_id].visible
			check(not early, "连续扩建重建家具后仍依各房间进度显示")
		world._process(2.)
	check(district.doorway.get_instance_id()==door_id and district.porch_lamps[0].get_instance_id()==lamp_id, "扩建时门扇与门灯常驻原位")
	check(room_area(market)==600 and district.wings.size()==8, "第二章七处扩建全部到位")
	print("GROWTH RESULT: %d passed / %d failed" % [passed,failures])
	quit(0 if failures == 0 else 1)
