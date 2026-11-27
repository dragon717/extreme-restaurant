extends SubViewportContainer
## The simulation uses 2D tile coordinates. This viewport renders those same
## coordinates as a roofless 3D set. Its fixed camera keeps the ground projection
## aligned with the game board, including its existing hit areas and actor feet.

const RegisterPaper = preload("res://scripts/visuals/register_paper.gd")
const Grid = preload("res://scripts/core/layout.gd")
const Seasons = preload("res://scripts/core/seasons.gd")
const Lighting = preload("res://scripts/visuals/restaurant_lighting.gd")
const Geography = preload("res://scenes/canyon/geography.tscn")
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
const X_RAY = preload("res://scripts/visuals/crew_occlusion.gdshader")
const Traffic = preload("res://scripts/visuals/district_traffic.gd")
const GroundEffects = preload("res://scripts/visuals/seasonal_ground.gd")
const WeatherField = preload("res://scripts/visuals/district_weather.gd")
const MEADOW_ALBEDO = preload("res://assets/materials/canyon-meadow.png")
const STONE_ALBEDO = preload("res://assets/materials/inn-stone.jpg")
const STONE_NORMAL = preload("res://assets/materials/inn-stone-normal.png")
const OAK_ALBEDO = preload("res://assets/materials/inn-oak.jpg")
const OAK_NORMAL = preload("res://assets/materials/inn-oak-normal.png")
const PORTRAIT_NORMALS = {
	"res://assets/canyon/chef.webp": preload("res://assets/materials/chef-normal.png"),
	"res://assets/canyon/courier.webp": preload("res://assets/materials/courier-normal.png"),
}
const STRAIGHT_WALL = preload("res://assets/tavern/straight_wall.glb")
const STRAIGHT_SILL = preload("res://assets/tavern/straight_sill.glb")
const HEARTH_BAY = preload("res://assets/tavern/hearth_bay.glb")
const WINDOW_BAY = preload("res://assets/tavern/window_bay.glb")
const VERANDA = preload("res://assets/tavern/river_veranda.glb")
const Canopy = preload("res://scripts/visuals/tavern_canopy.gd")
var canopy := Canopy.new()
var facade_profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/architecture/eaves.json"))
const GATE_COURT = preload("res://assets/tavern/gate_court.glb")
const BAY_LAYERS := {"Foundation":"floor", "Structure":"frame"}
var roof_panels: Array[MeshInstance3D] = []
const STOVE = preload("res://assets/tavern/hearth_stove.glb")
const DINING_TABLE = preload("res://assets/tavern/round_table.glb")
const RISE := 72.0
const SETBACK := 48.0
const DEPTH := 1.2018504 # Length of the viewing vector divided by its rise.
const STONE := Color("716b60")
const TIMBER := Color("573627")
const BRASS := Color("bb8750")

var view := SubViewport.new()
var camera := Camera3D.new()
var current_decal := Sprite3D.new()
var board: RegisterPaper
var board_stand: MeshInstance3D
var door_camera := 0.
var register_wind := 0.
var doorway: Node3D
var left_hinge: Node3D
var right_hinge: Node3D
var door_open := 0.0
var entrance_glass: StandardMaterial3D
var porch_sky: SpotLight3D
var soffits := Node3D.new()
var light := DirectionalLight3D.new()
var environment := Environment.new()
var district := Geography.instantiate()
var xray_materials := {}
var house_bounds := Rect2()
var exterior_amount := 0.0
var season := -1
var season_tween: Tween
var garden := preload("res://scenes/canyon/gate_garden.tscn").instantiate()
var season_weights := Vector3.ZERO
var rooms := Node3D.new()
var fixtures := Node3D.new()
var portraits := Node3D.new()
var traffic := Traffic.new()
var seasonal_ground := GroundEffects.new()
var walkers: Array[Node2D] = []
var promenade := PackedFloat32Array([.24,.60])
var procession_cells := PackedVector2Array()
var walkway_time := 0.0
var weather_field := WeatherField.new()
var actor_planes: Dictionary = {}
var actor_materials: Dictionary = {}
var site_layout := {}
var ground_view := Rect2()
var map_size := Vector2.ZERO
var lanterns: Array[OmniLight3D] = []
var fixture_models := {}
var materials := {}
var wings: Dictionary = {}
var construction: Dictionary = {}
var fixture_plots: Dictionary = {}
const BUILD_SECONDS := 1.55
var room_signature := 0
var room_structure: Array = []
var fixture_structure := ""
var fixture_signature := 0
var district_signature := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	stretch = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view.msaa_3d = Viewport.MSAA_2X
	add_child(view)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .10
	camera.far = 400.0
	view.add_child(camera)
	camera.current = true
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	view.add_child(world_environment)
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 125.0
	light.shadow_bias = .07
	view.add_child(light)
	light.rotation_degrees = Vector3(-48, -37, 0)
	for group in [district, rooms, fixtures, portraits, traffic, weather_field]:
		view.add_child(group)
	view.add_child(GATE_COURT.instantiate())
	view.add_child(garden)
	view.add_child(soffits)
	current_decal.name = "RiverCurrent"
	current_decal.texture = preload("res://assets/canyon/current.webp")
	current_decal.hframes = 4
	current_decal.axis = Vector3.AXIS_Y
	current_decal.pixel_size = 1.7/128.
	current_decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	current_decal.transparent = true
	current_decal.hide()
	view.add_child(current_decal)
	soffits.hide()
	view.add_child(seasonal_ground)
	for i in range(2):
		var traveler := preload("res://scripts/visuals/actor_view.gd").new()
		traveler.name="RoadTraveler%d"%i
		view.add_child(traveler)
		traveler.hide()
		traveler.set_visual("minion_melee")
		traveler.present("walk")
		walkers.append(traveler)


func frame(board_origin: Vector2, pixels_per_tile: float) -> void:
	if size.is_zero_approx() or pixels_per_tile <= 0.0: return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .1
	camera.far = 400.
	door_camera = 0.
	ground_view = Rect2(-board_origin / pixels_per_tile, size / pixels_per_tile)
	var center := ground_view.get_center()
	var target := Vector3(center.x, 0, center.y * DEPTH)
	camera.position = target + Vector3(0, RISE, SETBACK)
	camera.look_at(target)
	camera.size = size.y / pixels_per_tile

# Call after frame(). Varying the field of view and distance together
# preserves the apparent scale at the orthographic end of the approach.
func frame_door(amount: float, crossing := 0.) -> void:
	if amount <= .0001 or not is_instance_valid(doorway): return
	var origin := camera.position - Vector3(0,RISE,SETBACK)
	var start_direction := Vector3(0,RISE,SETBACK).normalized()
	var eye_direction := Vector3(-1.,.085,.53).normalized()
	var right := Vector3.UP.cross(eye_direction).normalized()
	var door_focus := doorway.position + Vector3(.25+crossing*1.35,1.53,-.05) - right*(1.18*(1.-crossing))
	var focus := origin.lerp(door_focus,amount)
	var direction := start_direction.slerp(eye_direction,amount)
	var porch_span := maxf(4.65,7.35*size.y/maxf(size.x,1.))
	var span := exp(lerpf(log(maxf(1.,camera.size)),log(porch_span-crossing*1.3),amount))
	var tangent := maxf(.012,amount*tan(deg_to_rad(39.)*.5))
	var distance := span/(2.*tangent)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.far = distance+360.
	camera.near = maxf(.055,distance-270.)
	camera.fov = rad_to_deg(2.*atan(tangent))
	camera.position = focus+direction*distance
	camera.look_at(focus)
	door_camera = amount

func frame_procession(amount: float) -> void:
	if not is_instance_valid(doorway):return
	# A three-quarter view keeps the queue, the stair treads and the clear
	# doorway in one shot. The same camera returns to the threshold afterward.
	var target:=doorway.position+Vector3(-1.35,1.20,1.46)
	var eye:=target+Vector3(-4.15,2.80,7.0)
	var desired:=Transform3D(Basis.looking_at(target-eye,Vector3.UP),eye)
	camera.transform=camera.transform.interpolate_with(desired,amount)
	camera.fov=lerpf(camera.fov,53.,amount)

func install_register(art: Texture2D) -> void:
	if not is_instance_valid(board):
		board = RegisterPaper.new()
		board.name = "BoundRegister"
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		view.add_child(board)
		board_stand = MeshInstance3D.new()
		var timber := BoxMesh.new()
		timber.size = Vector3(.12,3.05,.13)
		timber.material = _material("wood")
		board_stand.mesh = timber
		view.add_child(board_stand)
	board.bind_page(art)
	_place_register()

func _place_register() -> void:
	if not is_instance_valid(board) or not is_instance_valid(doorway): return
	var out := Vector3(-1,0,.53).normalized()
	var right := Vector3.UP.cross(out).normalized()
	board.position = doorway.position+Vector3.UP*1.69 - right*2.57 + out*1.48
	board.rotation = Vector3(-.065,atan2(out.x,out.z)-.065,0.)
	board_stand.position = board.to_global(Vector3(0,-.19,-.135))
	board_stand.rotation = board.rotation

func register_pixel(screen: Vector2) -> Vector2:
	if not is_instance_valid(board): return Vector2(-1,-1)
	var origin := board.to_local(camera.project_ray_origin(screen))
	var ray := board.global_basis.inverse()*camera.project_ray_normal(screen)
	return board.pixel_at_ray(origin,ray)

func drag_register(screen: Vector2) -> void:
	var origin := board.to_local(camera.project_ray_origin(screen))
	var ray := board.global_basis.inverse()*camera.project_ray_normal(screen)
	board.drag_ray(origin,ray)

func hit_door(point: Vector2) -> bool:
	if not is_instance_valid(doorway): return false
	var outline := PackedVector2Array()
	for local in [Vector3(-1.12,0,0),Vector3(1.12,0,0),Vector3(1.12,3.,0),Vector3(-1.12,3.,0)]:
		outline.append(camera.unproject_position(doorway.to_global(local)))
	return Geometry2D.is_point_in_polygon(point,outline)

# Both moving fanlight halves and the porch lanterns use the same painted
# glass. A stage owns the emission strength for its own hour and weather.
func _bind_entrance_glass(model: Node3D) -> void:
	for mesh_node: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh_node.mesh.get_surface_count():
			var original := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or original.resource_name != "Gate_glass": continue
			if entrance_glass == null: entrance_glass = original.duplicate() as StandardMaterial3D
			mesh_node.set_surface_override_material(surface,entrance_glass)

func open_door(amount: float) -> void:
	door_open = clampf(amount,0.,1.)
	if not is_instance_valid(left_hinge): return
	left_hinge.rotation.y = deg_to_rad(100.)*door_open
	right_hinge.rotation.y = -deg_to_rad(96.)*door_open

func sync_atmosphere(street, weather, hour: float, migration: bool, frozen: bool) -> void:
	register_wind = weather.wind
	var light_level := maxf(Lighting.lamplight(hour), float(weather.cloud_cover) * .70)
	traffic.update(street, DEPTH, ground_view, light_level)
	weather_field.update(ground_view, DEPTH, weather, migration and hour >= 17.0, Plan.landmark("wood_bridge") + Vector2(4,8), frozen)
	_material("stone").roughness = lerpf(.91, .43, clampf(float(weather.rain) * 1.2, 0, 1))
	light_at(hour, weather.cloud_cover, weather.flash, weather.lamp_voltage)

func set_day(day: int) -> void:
	var current := Seasons.at_day(day)
	if current == season: return
	var first := season < 0
	season = current
	if season_tween != null: season_tween.kill()
	var target := Seasons.weights(current)
	if first: _tint_season(target)
	else:
		season_tween = create_tween().set_trans(Tween.TRANS_SINE)
		season_tween.tween_method(_tint_season,season_weights,target,1.8)
	weather_field.set_season(current)
	seasonal_ground.set_season(current)

func advance_outdoors(delta: float, frozen: bool) -> void:
	if is_instance_valid(board): board.advance(delta,register_wind,door_camera>.06)
	seasonal_ground.advance(delta,frozen,camera.basis)
	if not frozen: walkway_time += delta
	for i in range(walkers.size()):
		var speed := .066 if i==0 else .014
		var next := fposmod(promenade[i]+(0. if frozen else delta*speed),2.)
		var p := _promenade_position(i,next)
		var clear := true
		for member in procession_cells:
			if ((member-p)*Vector2(1,DEPTH)).length_squared()<1.25:
				clear=false
				break
		if clear: promenade[i]=next
		else: p=_promenade_position(i,promenade[i])
		var actor=walkers[i]
		actor.present("walk" if clear and not frozen else "idle")
		sync_actor(str(actor.name),actor,p,false)
		if not frozen: seasonal_ground.observe(str(actor.name),p,ground_view)

func _promenade_position(index: int,cycle: float) -> Vector2:
	var t:=cycle if cycle<1. else 2.-cycle
	return Plan.route(GroundEffects.COURT_PATH,t) if index==0 else Plan.from_art(Plan.route(Plan.GUEST_PATH,t*.62))

func _tint_season(weights: Vector3) -> void:
	season_weights = weights
	district.season_colors(weights)
	for paint in [canopy.coverage,canopy.rim_paint]: paint.set_shader_parameter("season_weights",weights)
	var color := Color.WHITE.lerp(Color("def1c7"),weights.x*.40)
	color = color.lerp(Color("f1bf82"),weights.y*.72)
	color = color.lerp(Color("cadaef"),weights.z*.75)
	for item: Sprite3D in garden.get_children(): item.modulate = color

func light_at(hour: float, overcast: float, flash: float, voltage: float) -> void:
	var night := Lighting.lamplight(hour)
	district.set_dusk(night)
	light.light_color = Lighting.sample(hour, Lighting.KEY).lerp(Color("c7d4e3"), overcast * .60)
	light.light_energy = lerpf(1.00, .26, night) * (1.0 - overcast * .50) + flash * .60
	environment.background_color = Color("9a9f8e").lerp(Color("26364a"), night)
	environment.ambient_light_color = Color("dfd9b9").lerp(Color("829cc7"), night)
	environment.ambient_light_energy = lerpf(.68, .54, night) + flash * .22
	for lamp in lanterns:
		var level := smoothstep(.98, BUILD_SECONDS, float(construction.get(lamp.get_meta("wing_id", ""), BUILD_SECONDS)))
		lamp.light_energy = (.10 + maxf(night, overcast * .65) * .65) * voltage * level * float(lamp.get_meta("flame_gain",1.0))
	if entrance_glass != null:
		entrance_glass.emission_energy_multiplier = (.11 + maxf(night,overcast*.65)*.51)*voltage
	if is_instance_valid(porch_sky):
		porch_sky.light_color = environment.ambient_light_color.lerp(Color("c1d6e0"),.55)
		porch_sky.light_energy = .22 + .23*night + flash*.21

func sync_layout(layout: Dictionary, street, hide_fixture: String) -> void:
	site_layout = layout
	var signature := hash([layout.get("unlocked_plots",[]),layout.width,layout.height,layout.get("kitchen_bounds"),layout.get("wall_cells"),layout.get("plots"),layout.entrance,layout.exit])
	if room_signature != signature:
		room_signature = signature
		# A checkpoint can reorder dictionary keys and decode whole numbers as
		# floats. Compare the architectural dimensions before rebuilding the set.
		var structure := [int(layout.width),int(layout.height),Vector2i(Grid.vec(layout.entrance)),Vector2i(Grid.vec(layout.exit)),layout.get("unlocked_plots",[]).duplicate()]
		var bounds: Array = [Grid.kitchen_bounds(layout)]
		for plot in layout.get("plots",[]):
			structure.append(str(plot.id))
			bounds.append(plot.bounds)
		for rect in bounds:
			structure.append(Rect2i(int(rect.left),int(rect.top),int(rect.right)-int(rect.left)+1,int(rect.bottom)-int(rect.top)+1))
		for cell in layout.get("wall_cells",[]): structure.append(Vector2i(Grid.vec(cell)))
		if structure != room_structure:
			room_structure = structure
			_build_rooms(layout)
	signature = hash(layout.facilities)
	if fixture_signature != signature:
		fixture_signature = signature
		var key := JSON.stringify(layout.facilities)
		if key != fixture_structure:
			fixture_structure = key
			_build_fixtures(layout)
	for id in fixture_models:
		fixture_models[id].visible = id != hide_fixture

func show_exterior(amount: float, _unlocked: int) -> void:
	if is_equal_approx(exterior_amount, amount): return
	exterior_amount = amount
	soffits.visible = amount > .001
	canopy.set_cover(amount)
	for panel in roof_panels: panel.visible = amount > .001

func _clear(parent: Node3D) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _material(kind := "plain") -> StandardMaterial3D:
	if materials.has(kind): return materials[kind]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = .87
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		"meadow":
			material.albedo_texture = MEADOW_ALBEDO
			material.uv1_scale = Vector3(.43,.43,1)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"glow": material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"stone", "wood":
			var stone := kind == "stone"
			material.albedo_texture = STONE_ALBEDO if stone else OAK_ALBEDO
			material.albedo_color = Color(1.22, 1.19, 1.12) if stone else Color(1.20, 1.13, 1.06)
			material.normal_enabled = true
			material.normal_texture = STONE_NORMAL if stone else OAK_NORMAL
			material.normal_scale = .61 if stone else .39
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	materials[kind] = material
	return material

func sync_actor(id: String, actor: Node2D, cell: Vector2, hero_inside: bool) -> void:
	var indoors := not site_layout.is_empty() and Grid.has_room(site_layout,Vector2i(cell.round()))
	if id.begins_with("g_"):
		if not indoors:
			seasonal_ground.observe(id,cell,ground_view)
		else: seasonal_ground.forget(id)
	var sprite: AnimatedSprite2D = actor.sprite
	if not actor.uses_world_sprite:
		actor.uses_world_sprite = true
		sprite.hide()
		actor.queue_redraw()
	var plane: Sprite3D = actor_planes.get(id)
	var gate_y := float(site_layout.get("entrance",[0,12])[1])
	var ground := Plan.foot_point(cell,gate_y,indoors)
	var in_view := camera.is_position_in_frustum(ground+Vector3.UP*.57) if door_camera>.01 else ground_view.grow(2).has_point(cell)
	if actor.modulate.a<=.08 or not in_view:
		if plane != null: plane.hide()
		return
	var cycle := .67 if str(actor.visual_key).begins_with("minion_") or actor.visual_key in ["normal","chef","waiter"] else .94
	if actor.visual_key=="riverclaw": cycle=.61
	if actor.visual_key=="minion_siege": cycle=.46
	var walking: bool=actor.gait.orient(actor,ground,camera,cycle)
	var frame := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if frame == null: return
	if plane == null:
		plane = Sprite3D.new()
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		plane.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		portraits.add_child(plane)
		actor_planes[id] = plane
	if plane.texture != frame:
		plane.texture = frame
		var sheet: Texture2D = frame.atlas if frame is AtlasTexture else frame
		plane.material_override = _actor_material(sheet)
	plane.show()
	plane.modulate = actor.modulate
	plane.flip_h = sprite.flip_h
	var art_factor: float = actor.sprite_base_scale * actor.art_scale
	plane.pixel_size = art_factor / 48.0
	var sole: Vector2 = frame.get_meta("sole",Vector2(.5,.5-actor.sprite_base_offset.y/(art_factor*frame.get_height())))
	plane.offset=Vector2(0,(sole.y-.5)*frame.get_height())
	var breath := 1.
	if sprite.animation == &"idle":
		breath += .015*sin(walkway_time*2.65+float(id.hash()%24))
	var to_camera := Vector3(camera.basis.z.x,0,camera.basis.z.z).normalized()
	plane.basis=Basis(Vector3.UP,atan2(to_camera.x,to_camera.z))*Basis.from_scale(Vector3(1,breath*1.27,1))
	plane.position=ground
	if walking:
		var sheet: Texture2D = frame.atlas if frame is AtlasTexture else frame
		var skin := plane.material_override as StandardMaterial3D
		actor.gait.draw(plane,frame,sheet,skin.normal_texture,sole,cycle,actor.visual_key=="minion_siege",hero_inside,gate_y,indoors)
	else: actor.gait.idle(plane)
	var outline := plane.get_node_or_null("ThroughWall") as Sprite3D
	if hero_inside and not walking:
		if outline == null:
			outline = Sprite3D.new()
			outline.name = "ThroughWall"
			outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plane.add_child(outline)
		if outline.texture != frame:
			outline.texture = frame
			var art: Texture2D = frame.atlas if frame is AtlasTexture else frame
			outline.material_override = _xray_material(art)
		outline.pixel_size = plane.pixel_size
		outline.offset = plane.offset
		outline.flip_h = plane.flip_h
		outline.show()
	elif outline != null:
		outline.hide()

func remove_actor(id: String) -> void:
	seasonal_ground.forget(id)
	var plane: Sprite3D = actor_planes.get(id)
	if plane == null: return
	plane.queue_free()
	actor_planes.erase(id)

func _xray_material(sheet: Texture2D) -> ShaderMaterial:
	if not xray_materials.has(sheet):
		var mat := ShaderMaterial.new()
		mat.shader = X_RAY
		mat.set_shader_parameter("character", sheet)
		xray_materials[sheet] = mat
	return xray_materials[sheet]

func _actor_material(sheet: Texture2D) -> StandardMaterial3D:
	if actor_materials.has(sheet): return actor_materials[sheet]
	var material := StandardMaterial3D.new()
	material.albedo_texture = sheet
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = .23
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .84
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var baked: Texture2D = PORTRAIT_NORMALS.get(sheet.resource_path)
	if baked == null and sheet.resource_path.begins_with("res://assets/crew/"):
		baked = load(sheet.resource_path.get_basename() + "-normal.png")
	if baked == null:
		var frame_source := sheet.get_image()
		if frame_source != null and not frame_source.is_empty():
			if frame_source.is_compressed(): frame_source.decompress()
			frame_source.bump_map_to_normal_map(.65)
			baked = ImageTexture.create_from_image(frame_source)
	if baked != null:
		material.normal_enabled = true
		material.normal_texture = baked
		material.normal_scale = .66
	actor_materials[sheet] = material
	return material

func _build_rooms(layout: Dictionary) -> void:
	_clear(rooms)
	wings.clear()
	roof_panels.clear()
	canopy.begin()
	lanterns.clear()
	var kitchen := Grid.kitchen_bounds(layout)
	var geometry_by_room := {}
	var boundaries := {}
	var footprints := {}
	for y in range(1, int(layout.height) - 1):
		for x in range(1, int(layout.width) - 1):
			var cell := Vector2i(x, y)
			var center := Vector2(cell) + Vector2.ONE * .5
			if not Grid.has_room(layout, cell): continue
			var plot := Grid.plot_at(layout, cell)
			var id := str(plot.get("id", "homestead"))
			if not geometry_by_room.has(id):
				geometry_by_room[id] = {"floor":Geometry.new(), "tile":Geometry.new(), "frame":Geometry.new(), "roof":Geometry.new()}
			var square := Rect2i(cell, Vector2i.ONE)
			footprints[id] = square if not footprints.has(id) else footprints[id].merge(square)
			var parts: Dictionary = geometry_by_room[id]
			var floor_mesh: Geometry = parts.floor
			if y <= int(kitchen.bottom):
				var jade := Color("809d96") if x >= int(kitchen.left) and x <= int(kitchen.right) else Color("9d9a79")
				for row in range(2):
					for column in range(2):
						var tile := Rect2(Vector2(cell) + Vector2(column, row) * .5 + Vector2.ONE * .014, Vector2.ONE * .472)
						parts.tile.slab(tile, .022, .07, jade.lightened(float((x * 3 + y + row + column) % 4) * .035))
			else:
				for plank in range(3):
					var wood := Color("986749").lerp(Color("c99362"), float((x * 3 + y * 5 + plank * 7) % 11) / 11)
					floor_mesh.slab(Rect2(x+.009, y+plank/3.0+.01, .982, .312), .022, .07, wood)
			if Grid.structural_blocked(layout, cell):
				parts.frame.block(center, .32, Vector3(.98, .62, .58), STONE)
				parts.roof.block(center, .65, Vector3(1.0, .10, .65), TIMBER)
			for side in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + side
				if Grid.has_room(layout, neighbor): continue
				if neighbor == Vector2i(Grid.vec(layout.entrance)) or neighbor == Vector2i(Grid.vec(layout.exit)):
					# The guests pass underneath this continuous piece of the west eave.
					canopy.add_run(id,PackedVector2Array([Vector2(x,y+1),Vector2(x,y)]))
					continue
				var horizontal: bool = side.y != 0
				var line := (y if horizontal else x) + (1 if side == Vector2i.RIGHT or side == Vector2i.DOWN else 0)
				var key := Vector3i(side.x, side.y, line)
				if not boundaries.has(id): boundaries[id] = {}
				if not boundaries[id].has(key): boundaries[id][key] = []
				boundaries[id][key].append(x if horizontal else y)
	for id in geometry_by_room:
		var wing := Node3D.new()
		wing.name = id
		rooms.add_child(wing)
		var parts: Dictionary = geometry_by_room[id]
		var layers := {}
		for key in ["floor", "frame", "roof"]:
			var layer := Node3D.new()
			layer.name = key
			wing.add_child(layer)
			parts[key].finish(layer, _material("wood" if key == "floor" else "stone" if key == "frame" else "plain"))
			if key == "floor": parts.tile.finish(layer, _material("stone"))
			layers[key] = layer
		var location: Dictionary = {}
		for plot in layout.get("plots", []):
			if str(plot.id) == id:
				location = plot.bounds
				break
		var left := int(location.get("left", 1))
		var top := int(location.get("top", 1))
		var right := int(location.get("right", left))
		var bottom := int(location.get("bottom", top))
		var west := Grid.has_room(layout, Vector2i(left - 1, floori((top + bottom) * .5)))
		var east := Grid.has_room(layout, Vector2i(right + 1, floori((top + bottom) * .5)))
		var north := Grid.has_room(layout, Vector2i(floori((left + right) * .5), top - 1))
		_build_bays(id,layers, boundaries.get(id, {}))
		layers.anchor = Vector2(left if west else right + 1, top if north else bottom + 1)
		layers.across = west or east
		wings[id] = layers
	weather_field.shelter_rooms(footprints,DEPTH)
	roof_panels = canopy.build(wings, footprints, _material("wood"))
	canopy.set_cover(exterior_amount)
	for panel in roof_panels: panel.visible = exterior_amount > .001
	house_bounds = Rect2(Grid.occupied_bounds(layout)).grow_individual(2.8,5.,2.4,1.8)
	_clear(soffits)
	var boards := Geometry.new()
	var beams := Geometry.new()
	for footprint: Rect2i in footprints.values():
		var area := Rect2(footprint)
		boards.slab(area,3.96,.07,Color("b99774"))
		for x in range(footprint.position.x+1,footprint.end.x,3):
			beams.slab(Rect2(x,area.position.y,.16,area.size.y),3.82,.19,Color("715242"))
	boards.finish(soffits,canopy.ridge_material)
	beams.finish(soffits,canopy.ridge_material)
	soffits.visible = exterior_amount > .001
	var entrance := Grid.vec(layout.entrance)
	doorway = preload("res://assets/tavern/hinged_door.glb").instantiate() as Node3D
	doorway.position = Vector3(.855,.02,(entrance.y+1.)*DEPTH)
	doorway.rotation.y = -PI*.5
	rooms.add_child(doorway)
	_bind_entrance_glass(doorway)
	_place_register()
	left_hinge = doorway.find_child("LeftHinge",true,false)
	right_hinge = doorway.find_child("RightHinge",true,false)
	open_door(door_open)
	var vestibule_lamp := OmniLight3D.new()
	vestibule_lamp.position = doorway.position+Vector3(3.2,2.35,-.6)
	vestibule_lamp.light_color = Color("ffd295")
	vestibule_lamp.light_energy = 1.4
	vestibule_lamp.omni_range = 8.
	rooms.add_child(vestibule_lamp)
	var chimney_model := preload("res://assets/tavern/stone_chimney.glb").instantiate() as Node3D
	chimney_model.position = Vector3(2.72,0,1.83*DEPTH)
	rooms.add_child(chimney_model)
	var porch := preload("res://assets/tavern/entrance_porch.glb").instantiate() as Node3D
	porch.rotation.y = float(Plan.porch.yaw)
	porch.position = Vector3(Plan.porch.porch_x,0,(entrance.y+float(Plan.porch.porch_gate_offset))*DEPTH)
	rooms.add_child(porch)
	_bind_entrance_glass(porch)
	# Broad, unshadowed sky bounce from the open side of the porch. The small
	# radius and cut-off keep the cool return local to the frame and brass.
	porch_sky = SpotLight3D.new()
	porch_sky.name = "PorchSkyBounce"
	porch_sky.position = doorway.position + Vector3(-3.8,3.55,1.55)
	porch_sky.spot_range = 5.9
	porch_sky.spot_angle = 39.
	porch_sky.spot_attenuation = .83
	porch_sky.light_specular = .77
	rooms.add_child(porch_sky)
	porch_sky.look_at(doorway.global_position+Vector3(0,1.55,0))
	for side in [-1.25,1.25]:
		var lantern := OmniLight3D.new()
		lantern.position = Vector3(side,2.1,1.8)
		lantern.light_color = Color("ffd39a") if side < 0 else Color("ffdaac")
		lantern.omni_range = 3.85 if side < 0 else 3.25
		lantern.omni_attenuation = .82
		lantern.light_specular = .96
		lantern.set_meta("flame_gain",1.18 if side < 0 else .72)
		lantern.set_meta("wing_id","homestead")
		porch.add_child(lantern)
		lanterns.append(lantern)
	for point in [entrance + Vector2(.68, -.43), Vector2(7.2, 4.5), Vector2(8.4, 12.5), Vector2(14.9, 10.3), Vector2(18.3, 12.7)]:
		if point.x > 1.0 and not Grid.has_room(layout, Vector2i(point)): continue
		var lamp := OmniLight3D.new()
		lamp.set_meta("wing_id", str(Grid.plot_at(layout, Vector2i(point)).get("id", "")))
		lamp.position = Vector3(point.x, 2.1, point.y * DEPTH)
		lamp.light_color = Color("ffc484")
		lamp.omni_range = 7.6
		lamp.omni_attenuation = .80
		rooms.add_child(lamp)
		var glass := MeshInstance3D.new()
		var shade := CylinderMesh.new()
		shade.top_radius = .077
		shade.bottom_radius = .095
		shade.height = .175
		shade.radial_segments = 8
		shade.rings = 1
		var amber := StandardMaterial3D.new()
		amber.albedo_color = Color("e8b777")
		amber.emission_enabled = true
		amber.emission = Color("fcca86")
		amber.emission_energy_multiplier = .6
		shade.material = amber
		glass.mesh = shade
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(glass)
		var chain := Geometry.new()
		chain.block(point,3.01,Vector3(.034,1.65,.034),Color("5f4b39"))
		chain.finish(rooms,_material())
		lanterns.append(lamp)
	# Restores and restarts can remove a wing while its reveal is in progress.
	for id in construction.keys():
		if not wings.has(id): construction.erase(id)
		else: _pose_construction(id, construction[id])

# Only exposed cell edges produce façades. A shared wall vanishes when the
# adjacent plot opens. Runs terminate at doorways and ownership boundaries.
func _build_bays(id: String, layers: Dictionary, edges: Dictionary) -> void:
	for key: Vector3i in edges:
		var cells: Array = edges[key]
		cells.sort()
		var start: int = cells[0]
		var last := start
		for n in range(1, cells.size() + 1):
			if n < cells.size() and cells[n] == last + 1:
				last += 1
				continue
			var length := last + 1 - start
			var sections := 2 if length > 8 else 1
			for i in range(sections):
				var split := 7 if length >= 11 else ceili(length*.58)
				var begin := start if i == 0 else start + split
				var end := start + length if i == sections - 1 else start + split
				_attach_bay(id,layers, key, begin, end)
			if n < cells.size():
				start = int(cells[n])
				last = start

func _attach_bay(id: String,layers: Dictionary, edge: Vector3i, begin: int, end: int) -> void:
	var horizontal := edge.y != 0
	var middle := (begin + end) * .5
	var center := Vector2(middle, edge.z) if horizontal else Vector2(edge.z, middle)
	var source := STRAIGHT_SILL
	if edge.y < 0:
		source = HEARTH_BAY if begin == 1 else STRAIGHT_WALL
	elif edge.x < 0 and end <= 12:
		source = WINDOW_BAY if begin == 1 else STRAIGHT_WALL
	elif edge.x > 0:
		source = WINDOW_BAY if begin == 1 and end <= 7 else STRAIGHT_WALL
	elif edge.y > 0 and begin == 1:
		source = VERANDA
	var rotation_y := atan2(-float(edge.x), -float(edge.y))
	var module := source.instantiate() as Node3D
	var span := float(end - begin)
	var depth_scale := minf(1.0, span / 3.0)
	if edge.x > 0 and begin >= 7: depth_scale *= .76
	var key := source.resource_path.get_file().get_basename()
	var line := PackedVector2Array()
	var along := Vector2(-edge.y,edge.x)
	var outward := Vector2(edge.x,edge.y)
	for p in facade_profiles[key].line:
		line.append(center + along * (float(p[0])*span/6.) + outward*float(p[1])*depth_scale)
	canopy.add_run(id,line)
	for layer_name in BAY_LAYERS:
		var piece := module.find_child(layer_name, true, false) as Node3D
		if piece == null: continue
		var target: Node3D = layers[BAY_LAYERS[layer_name]]
		var authored := piece.transform
		piece.owner = null
		piece.get_parent().remove_child(piece)
		target.add_child(piece)
		# Incorporate DEPTH after rotation so every join lands on the same grid edge.
		var basis := Basis(Vector3.UP, rotation_y) * Basis.from_scale(Vector3(span / 6.0, 1, depth_scale))
		basis = Basis.from_scale(Vector3(1,1,DEPTH)) * basis
		piece.transform = Transform3D(basis, Vector3(center.x,0,center.y * DEPTH)) * authored
	module.free()

func start_construction(id: String) -> void:
	if not wings.has(id): return
	construction[id] = 0.0
	_pose_construction(id, 0.0)
	_set_new_furniture(id, 0.0)

func finish_construction() -> void:
	advance_construction(BUILD_SECONDS)

func advance_construction(delta: float) -> void:
	for id in construction.keys():
		var elapsed := minf(BUILD_SECONDS, float(construction[id]) + delta)
		construction[id] = elapsed
		_pose_construction(id, elapsed)
		_set_new_furniture(id, elapsed)
		if elapsed >= BUILD_SECONDS: construction.erase(id)

func _pose_construction(id: String, elapsed: float) -> void:
	var parts: Dictionary = wings[id]
	var anchor: Vector2 = parts.anchor
	var across: bool = parts.across
	var floor_ratio := smoothstep(0.0, .64, elapsed)
	var ratio := maxf(.001, floor_ratio)
	parts.floor.scale = Vector3(ratio if across else 1.0, 1.0, 1.0 if across else ratio)
	parts.floor.position = Vector3(anchor.x * (1.0-ratio), 0, 0) if across else Vector3(0, 0, anchor.y * DEPTH * (1.0-ratio))
	parts.frame.visible = elapsed > .27
	parts.frame.scale.y = maxf(.001, smoothstep(.27, 1.10, elapsed))
	parts.roof.visible = elapsed > .98
	parts.roof.position.y = (1.0 - smoothstep(.98, 1.47, elapsed)) * .8
	parts.roof.scale.y = maxf(.001, smoothstep(.98, 1.36, elapsed))

func furniture_revealed(fixture_id: String) -> bool:
	var wing_id: String = fixture_plots.get(fixture_id, "")
	return float(construction.get(wing_id, BUILD_SECONDS)) >= 1.1

func _set_new_furniture(id: String, elapsed: float) -> void:
	var ratio := maxf(.001, smoothstep(1.1, BUILD_SECONDS, elapsed))
	for fixture in fixture_plots:
		if fixture_plots[fixture] == id:
			fixture_models[fixture].scale.y = ratio

func _build_fixtures(layout: Dictionary) -> void:
	_clear(fixtures)
	fixture_models.clear()
	fixture_plots.clear()
	for f in layout.facilities:
		if not Grid.placed(f): continue
		var model := Node3D.new()
		fixtures.add_child(model)
		fixture_models[f.id] = model
		fixture_plots[f.id] = str(Grid.plot_at(layout, Vector2i(Grid.vec(f.pos))).get("id", ""))
		var area: Rect2i = Grid.footprint(f)
		var center := Vector2(area.position) + Vector2(area.size) * .5
		model.position = Vector3(center.x, 0, center.y * DEPTH)
		if area.size == Vector2i.ONE:
			model.rotate_y(-Grid.rotation(f) * PI * .5)
		var mesh := Geometry.new()
		var glow := Geometry.new()
		match f.type:
			"table":
				var table := DINING_TABLE.instantiate() as Node3D
				table.scale = Vector3(area.size.x * .97, 1.05, area.size.y * DEPTH * .97)
				model.add_child(table)
				for x in range(area.size.x):
					for z in range(area.size.y):
						var point := Vector2(x,z) - Vector2(area.size - Vector2i.ONE) * .5
						if z > 0 and z < area.size.y - 1: continue
						var direction := -1 if z == 0 and area.size.y > 1 else 1
						var chair := point + Vector2(0, direction * .46)
						mesh.block(chair, .24, Vector3(.35,.10,.25), TIMBER)
						mesh.block(chair + Vector2(0,direction*.12), .39, Vector3(.35,.30,.065), TIMBER)
			"stove":
				model.add_child(STOVE.instantiate())
			"wall":
				mesh.block(Vector2.ZERO, .36, Vector3(.94, .70, .22), TIMBER)
				mesh.block(Vector2.ZERO, .73, Vector3(.98, .095, .28), BRASS.darkened(.31))
			"trophy":
				mesh.block(Vector2.ZERO, .23, Vector3(.56, .42, .56), STONE)
				mesh.block(Vector2.ZERO, .58, Vector3(.27, .35, .28), BRASS)
				glow.block(Vector2.ZERO, .77, Vector3(.28, .06, .24), Color("d9ae6f"))
			"decoration":
				mesh.block(Vector2.ZERO, .15, Vector3(area.size.x * .74, .26, area.size.y * .66), TIMBER)
				_tree(mesh, Vector2.ZERO, .42)
			_:
				mesh.block(Vector2.ZERO, .28, Vector3(.86, .53, .73), TIMBER)
				mesh.block(Vector2.ZERO, .59, Vector3(.92, .12, .80), Color("baa176"))
				mesh.block(Vector2(.18, -.11), .68, Vector3(.30, .11, .28), Color("5f746c"))
		mesh.finish(model, _material("wood" if f.type in ["table", "wall", "slot", "cashier", "decor_shop"] else "plain"))
		glow.finish(model, _material("glow"))

func _tree(mesh: Geometry, point: Vector2, scale_factor: float) -> void:
	mesh.block(point, scale_factor * .50, Vector3(.14, scale_factor, .16), TIMBER)
	for i in range(4):
		var shift := Vector2.from_angle(i * TAU / 4.0) * scale_factor * .18
		mesh.crown(point + shift, scale_factor * (.67 + i * .03), scale_factor * .43, Color("426a53").lightened(float(i) * .063))

class Geometry:
	var surface := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	func slab(area: Rect2, height: float, thickness: float, color: Color) -> void:
		block(area.get_center(), height, Vector3(area.size.x, thickness, area.size.y), color)

	func block(at: Vector2, height: float, extent: Vector3, color: Color) -> void:
		var lo := Vector3(at.x - extent.x * .5, height - extent.y * .5, (at.y - extent.z * .5) * DEPTH)
		var hi := Vector3(at.x + extent.x * .5, height + extent.y * .5, (at.y + extent.z * .5) * DEPTH)
		var a := Vector3(lo.x, lo.y, lo.z)
		var b := Vector3(hi.x, lo.y, lo.z)
		var c := Vector3(hi.x, lo.y, hi.z)
		var d := Vector3(lo.x, lo.y, hi.z)
		var e := Vector3(lo.x, hi.y, lo.z)
		var f := Vector3(hi.x, hi.y, lo.z)
		var g := Vector3(hi.x, hi.y, hi.z)
		var h := Vector3(lo.x, hi.y, hi.z)
		_quad(e, f, g, h, Vector3.UP, color)
		_quad(a, d, c, b, Vector3.DOWN, color)
		_quad(a, b, f, e, Vector3.FORWARD, color.darkened(.08))
		_quad(b, c, g, f, Vector3.RIGHT, color.darkened(.10))
		_quad(c, d, h, g, Vector3.BACK, color.darkened(.04))
		_quad(d, a, e, h, Vector3.LEFT, color)

	func roof(area: Rect2, base: float, rise: float, color: Color) -> void:
		var a := Vector3(area.position.x, base, area.position.y * DEPTH)
		var b := Vector3(area.end.x, base, area.position.y * DEPTH)
		var c := Vector3(area.end.x, base, area.end.y * DEPTH)
		var d := Vector3(area.position.x, base, area.end.y * DEPTH)
		var r := Vector3(a.x, base + rise, area.get_center().y * DEPTH)
		var s := Vector3(b.x, base + rise, r.z)
		_quad(a, b, s, r, Vector3(0, area.size.y * DEPTH * .5, -rise).normalized(), color.lightened(.09))
		_quad(r, s, c, d, Vector3(0, area.size.y * DEPTH * .5, rise).normalized(), color)
		_tri(d, a, r, Vector3.LEFT, color.darkened(.21))
		_tri(b, c, s, Vector3.RIGHT, color.darkened(.27))
		for n in range(1, 7):
			var edge := float(n) / 7.0
			var front := lerpf(area.position.y, area.get_center().y, edge)
			var back := lerpf(area.end.y, area.get_center().y, edge)
			for z in [front, back]:
				block(Vector2(area.get_center().x, z), base + rise * edge, Vector3(area.size.x, .035, .032), color.lightened(.15))

	func crown(at: Vector2, height: float, radius: float, color: Color) -> void:
		for i in range(6):
			var a2 := at + Vector2.from_angle(i * TAU / 6.0) * radius
			var b2 := at + Vector2.from_angle((i + 1) * TAU / 6.0) * radius
			var a := Vector3(a2.x, height, a2.y * DEPTH)
			var b := Vector3(b2.x, height, b2.y * DEPTH)
			var top := Vector3(at.x, height + radius * 1.4, at.y * DEPTH)
			var bottom := Vector3(at.x, height - radius * .62, at.y * DEPTH)
			_tri(a, top, b, (b - a).cross(top - a).normalized(), color.lightened(float(i % 3) * .08))
			_tri(b, bottom, a, (a - b).cross(bottom - b).normalized(), color.darkened(.15))

	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
		_tri(a, b, c, normal, color)
		_tri(a, c, d, normal, color)

	func _tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
		var axis := Vector3.FORWARD if absf(normal.x) > .75 else Vector3.RIGHT
		var tangent := (axis - normal * axis.dot(normal)).normalized()
		var bitangent := normal.cross(tangent)
		for p in [a, b, c]:
			surface.set_normal(normal)
			surface.set_tangent(Plane(tangent.x, tangent.y, tangent.z, 1.0))
			surface.set_uv(Vector2(p.dot(tangent), p.dot(bitangent)) * .29)
			surface.set_color(color)
			surface.add_vertex(p)
			count += 1

	func finish(parent: Node3D, material: Material) -> void:
		if count == 0: return
		var node := MeshInstance3D.new()
		node.mesh = surface.commit()
		node.material_override = material
		parent.add_child(node)
