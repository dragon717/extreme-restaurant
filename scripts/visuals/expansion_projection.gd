extends Node3D
## The next wing occupies its real ground coordinates. Its ghost only owns
## render nodes, so it cannot become walkable, shelter rain or cast a shadow.

const GHOST = preload("res://scripts/visuals/expansion_projection.gdshader")
const OAK = preload("res://assets/materials/inn-oak.jpg")
var plot_id := ""
var bounds := Rect2i()
var available := false
var highlighted := false
var paints: Dictionary = {}
var ground_material: ShaderMaterial

func configure(id: String, area: Rect2i, depth: float) -> void:
	clear()
	plot_id = id
	bounds = area
	var footprint := PlaneMesh.new()
	footprint.size = Vector2(area.size) * Vector2(1., depth)
	ground_material = ShaderMaterial.new()
	ground_material.shader = GHOST
	ground_material.render_priority = -2
	ground_material.set_shader_parameter("footprint", true)
	ground_material.set_shader_parameter("span", footprint.size)
	ground_material.set_shader_parameter("surface_paint", OAK)
	footprint.material = ground_material
	var ground := MeshInstance3D.new()
	ground.mesh = footprint
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var center := Vector2(area.position) + Vector2(area.size) * .5
	ground.position = Vector3(center.x, .055, center.y * depth)
	add_child(ground)
	show()

func coat_walls() -> void:
	for piece: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if piece.mesh is PlaneMesh: continue
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index in piece.mesh.get_surface_count():
			var source := piece.get_active_material(index) as BaseMaterial3D
			var texture: Texture2D = source.albedo_texture if source else null
			if not paints.has(texture):
				var material := ShaderMaterial.new()
				material.shader = GHOST
				material.render_priority = -1
				material.set_shader_parameter("surface_paint", texture)
				paints[texture] = material
			piece.set_surface_override_material(index, paints[texture])

func set_appearance(ready_to_build: bool, focused: bool, refresh: bool) -> void:
	if not refresh and available == ready_to_build and highlighted == focused: return
	available = ready_to_build
	highlighted = focused
	var tint := Color("ffd48a") if available else Color("9ed8d9")
	var materials := paints.values()
	materials.append(ground_material)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("accent", tint)
		material.set_shader_parameter("available", available)
		material.set_shader_parameter("highlighted", highlighted)

func clear() -> void:
	hide()
	plot_id = ""
	bounds = Rect2i()
	paints.clear()
	ground_material = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
