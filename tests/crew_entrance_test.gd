extends "res://tests/door_entry_test.gd"
const Minions=preload("res://scripts/core/minion_staff.gd")
const Plan=preload("res://scripts/visuals/canyon_plan.gd")
const Grid=preload("res://scripts/core/layout.gd")
func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--ui-test" in OS.get_cmdline_user_args():
		quit(1)
		return
	var sim:=Sim.new()
	Store.write_checkpoint(sim.export_state(),Store.default_path("street_corner",true))
	Store.write_checkpoint({"mode":"off","seen":{}},Store.default_path("tutorial_progress",true))
	var title=load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await visit(title)
	await click_page(title,"NewRun")
	var draft=title.crew_layer.find_child("OpeningDraft",true,false)
	for id in Roster.STARTERS:
		draft.cards[id].pick.pressed.emit()
		draft.get_node("%Pick").pressed.emit()
	draft.get_node("%HelperButton").pressed.emit()
	draft.helper_controls.kind.select(2)
	draft.helper_controls.kind.item_selected.emit(2)
	check(draft.helper_staff.waiter==["siege"],"选定炮车小兵补前厅")
	draft.get_node("%Confirm").pressed.emit()
	var hub=title.get_node("Menu/CanyonHub")
	var stage=hub.model
	var porch=stage.rooms.find_child("Entrance_porch_frame",true,false) as MeshInstance3D
	check(porch!=null,"入场使用实际门廊的表面")
	if porch!=null:
		var faces: PackedVector3Array=porch.mesh.get_faces()
		for depth: float in [2.70,2.33,1.98,.95]:
			var start:=Vector3(0.,1.2,depth)
			var y:=-INF
			for index in range(0,faces.size(),3):
				var hit=Geometry3D.ray_intersects_triangle(start,Vector3.DOWN,faces[index],faces[index+1],faces[index+2])
				if hit!=null:y=maxf(y,porch.to_global(hit).y)
			var anchor:=Plan.foot_point(Plan.porch_cell(0,depth))
			check(absf(anchor.y-y)<.019,"鞋底高度吻合实际踏面 "+str(depth))
	check(hub.march.members.size()==6 and hub.preview_staff.values().filter(func(w):return w.visual_key=="minion_siege").size()==1,"五名所选角色和真实补位兵各一次入场")
	var seen:={}
	var clear:=true
	var separation:=INF
	var ankles:=0
	var backs:=0
	var old_step:={}
	var pinned:={}
	var stable:=true
	var orientation:={}
	var raised_early:=false
	for i in range(1100):
		await process_frame
		if not hub.marching:break
		var group: Array=hub.march.members
		var entered:=0
		for j in group.size():
			var m: Dictionary=group[j]
			var w=hub.preview_staff[m.id]
			var actor: Sprite3D=stage.actor_planes[m.id]
			var p:=actor.global_position
			if m.distance>=hub.march.door_distance:entered+=1
			if p.x>.60 and p.x<1.12:
				seen[m.id]=true
				clear=clear and absf(p.z-stage.doorway.position.z)<.85 and hub.aperture>.94
			if m.moving and w.gait.mesh_node!=null and w.gait.mesh_node.visible:
				if w.sprite.animation==&"walk_away":backs+=1
				var shift: Vector3=w.gait.paint.get_shader_parameter("planted_shift")
				var frame=w.sprite.sprite_frames.get_frame_texture(w.sprite.animation,w.sprite.frame)
				var sole: Vector2=frame.get_meta("sole",Vector2(.5,.95))
				var sx:=1.-sole.x if actor.flip_h else sole.x
				var physical:=actor.to_global(Vector3((sx-.5)*frame.get_width()*actor.pixel_size,0,0)+shift)
				if w.visual_key!="minion_siege" and physical.distance_to(w.gait.planted)<.002:ankles+=1
				if w.visual_key!="minion_siege" and old_step.get(m.id,-1)==w.gait.step and pinned.has(m.id) and orientation.get(m.id,"")==str(w.sprite.animation)+str(actor.flip_h):
					stable=stable and Vector3(pinned[m.id]).distance_to(w.gait.planted)<.002
				orientation[m.id]=str(w.sprite.animation)+str(actor.flip_h)
				old_step[m.id]=w.gait.step
				pinned[m.id]=w.gait.planted
			for k in range(j):
				separation=minf(separation,((Vector2(m.cell)-Vector2(group[k].cell))*Vector2(1,Plan.DEPTH)).length())
			if m.distance>hub.march.door_distance+1.2:
				clear=clear and not Grid.blocked(stage.site_layout,Vector2i(Vector2(m.cell).round()))
		if hub.reveal_started and entered!=6:raised_early=true
		if i==72:
			title.get_node("Menu/ArrivalControls/Rate").pressed.emit()
			check(hub.march.rate==3.,"右下角三倍速生效")
	check(title.game!=null and seen.size()==6 and clear,"所有人均走过打开的门洞，后续路线避开实体设施")
	check(separation>.74 and not raised_early,"队员保持间距，最后一人进门后才抬镜")
	check(stable and ankles>35 and backs>12,"实际绘制背面步态，支撑脚锚定到地面")
	# Changing from a side to a rear drawing can establish a fresh support
	# even within an otherwise unchanged phase; stationary contacts are
	# geometrically checked above on the exact material used by the viewport.
	if title.game!=null:
		var g=title.game
		check(g.sim.helper_staff.waiter==["siege"] and g.sim.day==1,"抵达后保存本局兵种，不多次建档")
		var stored=Store.read_checkpoint(g.save_path)
		var copy:=Sim.new()
		check(copy.restore_state(stored).ok and copy.helper_at("waiter",3)=="siege","炮车排班读档一致")
		g.guide.skip()
		g._open_day()
		var helpers=g.sim.staff.filter(func(s):return s.crew_id=="")
		check(helpers.size()==1 and helpers[0].minion=="siege","正式开店以同一个炮车兵送餐")
	title.queue_free()
	await create_timer(.6).timeout
	print("ARRIVAL ",checks-failures,"/",checks,"  min separation ",separation,"m grounded samples ",ankles," rear samples ",backs)
	quit(1 if failures else 0)
