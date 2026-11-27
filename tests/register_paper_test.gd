extends "res://tests/door_entry_test.gd"
## Native viewport input drives the same free margin and ink as the player.
func send_pointer(at: Vector2, touch: bool, motion: bool, pressed: bool) -> void:
	var event: InputEvent
	if touch:
		event=InputEventScreenDrag.new() if motion else InputEventScreenTouch.new()
		event.index=2
	else:
		event=InputEventMouseMotion.new() if motion else InputEventMouseButton.new()
		event.global_position=at
		if not motion: event.button_index=MOUSE_BUTTON_LEFT
	if not motion: event.pressed=pressed
	event.position=at
	root.push_input(event,true)

func project(d,uv: Vector2) -> Vector2:
	return d.camera.unproject_position(d.board.to_global(d.board.point_for_pixel(uv)))

func exercise(title,touch: bool) -> void:
	var d=title.get_node("Menu/CanyonHub").model
	var paper=d.board
	var pixel:=Vector2(621,785)
	var at:=project(d,pixel)
	send_pointer(at,touch,false,true)
	check(paper.grip>=0,"空白纸角接受拖动")
	if paper.grip<0: return
	var corner: int=paper.grip
	var target:=at+Vector2(-105,-76)
	for i in range(16):
		send_pointer(at.lerp(target,(i+1)/16.),touch,true,true)
		await process_frame
	await create_timer(.11).timeout
	var lifted: float=paper.points[corner].distance_to(paper.rest[corner])
	check(lifted>.21,"抓住页角能掀起纸面")
	check(paper.points[0]==paper.rest[0] and paper.points[paper.COLS-1]==paper.rest[paper.COLS-1],"装订边保持固定")
	var button_px: Vector2=title.start_button.get_global_rect().get_center()
	check(d.register_pixel(project(d,button_px)).distance_to(button_px)<1.1,"变形后的文字仍按同一三角面命中")
	if not touch: await snap("curl")
	send_pointer(target,touch,false,false)
	check(paper.grip<0 and title.crew_layer==null and title.game==null,"释放纸角不会误触新局或读档")
	await create_timer(1.85).timeout
	check(paper.points[corner].distance_to(paper.rest[corner])<lifted*.7,"放手后柔性纸面回弹并衰减")

func run() -> void:
	if not "--ui-test" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		quit(1)
		return
	var saved:=Sim.new()
	saved.day=4
	Store.write_checkpoint(saved.export_state(),Store.default_path("street_corner",true))
	var title=load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await visit(title)
	check(title.register.get_node("%ServicePage").visible and not title.register.get_node("%ChapterPage").visible and not title.register.get_node("%Options").visible,"营业页仅展示当前局")
	check(title.register.get_node("%CoverName").text==title.tr(str(title.chapter_buttons[title.selected_chapter].option.name)) and title.register.get_node("%SlotText").text.contains("4"),"章名与进度各占独立主信息行")
	check(title.register.get_node("%CoverName").get_theme_font_size("font_size")>title.register.get_node("%CoverSummary").get_theme_font_size("font_size") and title.register.get_node("%SlotText").get_theme_font_size("font_size")>title.register.get_node("%SlotCaption").get_theme_font_size("font_size"),"章次、简介、档号使用次级字号")
	await exercise(title,false)
	await exercise(title,true)
	await click_page(title,"ChaptersTab")
	check(title.register.get_node("%ChapterPage").visible and not title.register.get_node("%ServicePage").visible,"章节页只展示章节列表")
	await snap("chapters")
	title.chapter_buttons.street_corner.button.pressed.emit()
	check(title.register.get_node("%ServicePage").visible,"选择章节回到营业页")
	await click_page(title,"More")
	check(title.register.get_node("%Options").visible and not title.register.get_node("%NewRun").is_visible_in_tree(),"设置另页逐行操作")
	await snap("settings")
	await click_page(title,"ServiceTab")
	await snap("ledger")
	title.queue_free()
	await create_timer(.6).timeout
	print("REGISTER PAPER %d passed / %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
