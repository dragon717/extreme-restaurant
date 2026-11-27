extends SceneTree

const Shadows = preload("res://scripts/visuals/crew_shadows.gd")
const FRAMES = preload("res://assets/crew/Pantheon.tres")
var checks := 0
var failures := 0
var view := SubViewport.new()
var scene := Node3D.new()

func check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(reason)

func capture() -> Image:
	for i in 3: await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func changed(a: Image, b: Image, mask: Rect2i, threshold: float) -> int:
	var pixels := 0
	for y in range(mask.position.y, mask.end.y):
		for x in range(mask.position.x, mask.end.x):
			if absf(a.get_pixel(x,y).get_luminance()-b.get_pixel(x,y).get_luminance()) > threshold:
				pixels += 1
	return pixels

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	view.size = Vector2i(384, 320)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(scene)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.12,.12,.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .24
	view.find_world_3d().environment = environment
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 2.4, 6.)
	camera.look_at(Vector3(0,.78,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(12,12)
	floor_mesh.mesh = floor_plane
	scene.add_child(floor_mesh)
	var card := Sprite3D.new()
	var frame: AtlasTexture = FRAMES.get_frame_texture(&"idle",0)
	card.texture = frame
	card.pixel_size = .016
	card.offset = Vector2(0, (frame.get_meta("sole").y-.5) * frame.get_height())
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://scripts/visuals/crew_surface.gdshader")
	paint.set_shader_parameter("paint",frame.atlas)
	paint.set_shader_parameter("relief",preload("res://assets/crew/Pantheon-normal.png"))
	paint.set_shader_parameter("armour",.72)
	card.material_override = paint
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(card)
	var shadows := Shadows.new()
	scene.add_child(shadows)
	shadows.show_actor("pantheon","person",Vector3.ZERO,1.65,Vector3.LEFT,0.,false)
	var sun := DirectionalLight3D.new()
	scene.add_child(sun)
	sun.position = Vector3(-3,4,3)
	sun.look_at(Vector3.ZERO)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 18
	var lit := await capture()
	shadows.batches.person.casters.visible_instance_count = 0
	var unshadowed := await capture()
	var shadow_pixels := changed(lit, unshadowed, Rect2i(70,145,275,150),.045)
	check(shadow_pixels>100,"固定脚点体积向地面投影")
	shadows.batches.person.casters.visible_instance_count = 1
	sun.visible = false
	var ambient := await capture()
	var sun_pixels := changed(lit,ambient,Rect2i(157,54,72,105),.035)
	check(sun_pixels>100,"同一张立绘接受主光和环境光")
	floor_mesh.hide()
	var lamp := OmniLight3D.new()
	scene.add_child(lamp)
	lamp.omni_range = 4.8
	lamp.light_energy = 2.6
	lamp.position = Vector3(-1,.95,1.35)
	var left := await capture()
	lamp.position.x = 1.
	var right := await capture()
	var normal_pixels := changed(left,right,Rect2i(129,40,126,167),.035)
	check(normal_pixels>180,"点光换侧时法线起伏改变角色表面的明暗")
	var proxy: MultiMesh = shadows.batches.person.casters
	var previous := proxy.get_instance_transform(0)
	camera.position.x += 1.6
	camera.look_at(Vector3(0,.78,0))
	card.rotation.y = atan2(camera.basis.z.x,camera.basis.z.z)
	shadows.show_actor("pantheon","person",Vector3.ZERO,1.65,Vector3.LEFT,0.,false)
	check(proxy.get_instance_transform(0).is_equal_approx(previous),"镜头换侧时角色投影仍保持世界朝向")
	shadows.show_actor("minion","person",Vector3(1,0,0),.8,Vector3.FORWARD,.25,true)
	shadows.remove_actor("pantheon")
	check(proxy.visible_instance_count==1 and proxy.get_instance_transform(0).origin.is_equal_approx(Vector3.RIGHT),"回收批次槽后移动的角色仍在原脚点")
	print("CREW LIGHTING ",checks-failures,"/",checks," · shadow pixels ",shadow_pixels," · sun ",sun_pixels," · side light ",normal_pixels)
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)
