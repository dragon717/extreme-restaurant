extends Node3D

const Seasons = preload("res://scripts/core/seasons.gd")
const RainArt = preload("res://scripts/visuals/weather_streak.gdshader")
const Ember = preload("res://assets/interface/lantern-ember.png")
const MAX_DROPS := 390
var drift := CPUParticles3D.new()
var drift_mat := StandardMaterial3D.new()
var season := -1
var rain := CPUParticles3D.new()
var motes := CPUParticles3D.new()
var rain_material := ShaderMaterial.new()

func _ready() -> void:
	drift.amount = 45
	drift.emitting = false
	drift.local_coords = false
	drift.lifetime = 4.
	drift.fixed_fps = 24
	drift.preprocess = 1.
	drift.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drift.emission_box_extents = Vector3(2.6,1.2,8)
	drift.position = Vector3(-4.2,3.2,12.)
	drift.direction = Vector3(.33,-1,.06)
	drift.initial_velocity_min = .54
	drift.initial_velocity_max = 1.0
	drift.scale_amount_min = .43
	drift.scale_amount_max = .78
	drift.spread = 24
	drift.gravity = Vector3(.08,-.24,.02)
	drift.angular_velocity_min = -70.
	drift.angular_velocity_max = 65.
	drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drift_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drift_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	drift_mat.distance_fade_min_distance = .6
	drift_mat.distance_fade_max_distance = 2.3
	drift_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drift_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	var seed_mesh := SphereMesh.new()
	seed_mesh.radius = .046
	seed_mesh.height = .025
	seed_mesh.radial_segments = 5
	seed_mesh.rings = 1
	seed_mesh.material = drift_mat
	drift.mesh = seed_mesh
	add_child(drift)
	rain.amount = MAX_DROPS
	rain.emitting = false
	rain.lifetime = .70
	rain.fixed_fps = 30
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(13, 1.7, 10)
	rain.initial_velocity_min = 19.0
	rain.initial_velocity_max = 27.0
	rain.gravity = Vector3(0, -14.0, 0)
	rain.spread = 1.9
	rain.particle_flag_align_y = true
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streak := BoxMesh.new()
	streak.size = Vector3(.016, .47, .016)
	rain_material.shader = RainArt
	streak.material = rain_material
	rain.mesh = streak
	add_child(rain)
	motes.amount = 48
	motes.emitting = false
	motes.lifetime = 5.2
	motes.preprocess = 2.1
	motes.fixed_fps = 24
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(1.0, .28, 8.2)
	motes.direction = Vector3(.08, .08, .98)
	motes.gravity = Vector3(.025, .012, 0)
	motes.initial_velocity_min = .14
	motes.initial_velocity_max = .54
	motes.scale_amount_min = .30
	motes.scale_amount_max = .71
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wisp := QuadMesh.new()
	wisp.size = Vector2(.28, .28)
	var glimmer := StandardMaterial3D.new()
	glimmer.albedo_texture = Ember
	glimmer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glimmer.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glimmer.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glimmer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glimmer.vertex_color_use_as_albedo = true
	wisp.material = glimmer
	motes.mesh = wisp
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0, .16, .75, 1])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, .77, .42, .75), Color(1, .60, .27, .52), Color(1, .58, .28, 0)])
	motes.color_ramp = fade
	add_child(motes)

func shelter_rooms(footprints: Dictionary,depth: float) -> void:
	var rooms := PackedVector4Array()
	for rect: Rect2i in footprints.values():
		rooms.append(Vector4(rect.position.x,rect.position.y*depth,rect.end.x,rect.end.y*depth))
	rain_material.set_shader_parameter("room_count",mini(8,rooms.size()))
	rooms.resize(8)
	rain_material.set_shader_parameter("sheltered",rooms)

func set_season(index: int) -> void:
	season = index
	drift_mat.albedo_color = Seasons.COLORS[index]
	drift.amount = [20,0,34,45][index] if index != 1 else 1
	drift.scale_amount_max = .55 if index == 3 else .85
	drift.gravity = Vector3(.05,-.34 if index == 3 else -.18,.03)
	drift.emitting = index != 1

func update(visible_tiles: Rect2, depth: float, weather, migration: bool, canal: Vector2, frozen: bool) -> void:
	var center := visible_tiles.get_center()
	drift.speed_scale = 0.0 if frozen else 1.0
	drift.emitting = season >= 0 and season != 1 and visible_tiles.intersects(Rect2(-8,0,7,22))
	rain.position = Vector3(center.x, 12.5, center.y * depth - 1.8)
	var size := visible_tiles.size
	rain.emission_box_extents = Vector3(size.x * .59, 2.6, size.y * depth * .58)
	rain.direction = Vector3(float(weather.wind) * .18, -1.0, .02).normalized()
	rain.speed_scale = 0.0 if frozen else 1.0
	rain_material.set_shader_parameter("intensity", clampf(weather.rain * .84, 0, .68))
	rain.emitting = weather.rain > .045
	motes.position = Vector3(canal.x, .55, canal.y * depth)
	motes.speed_scale = 0.0 if frozen else 1.0
	motes.emitting = migration and visible_tiles.grow(3).intersects(Rect2(canal - Vector2(3, 9), Vector2(6, 18)))
