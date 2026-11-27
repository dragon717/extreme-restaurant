extends Node3D
const Surface = preload("res://scripts/visuals/canyon_surface.gdshader")
var paints := {}
var dusk_level := -1.
func _ready() -> void:
	for landmark in get_children():
		var materials := {}
		for piece: MeshInstance3D in landmark.find_children("*","MeshInstance3D",true,false):
			var original := piece.get_active_material(0) as StandardMaterial3D
			if original == null: continue
			if not materials.has(original):
				var painted := ShaderMaterial.new()
				painted.shader = Surface
				painted.set_shader_parameter("painted", original.albedo_texture)
				painted.set_shader_parameter("relief", original.normal_texture)
				painted.set_shader_parameter("orm", original.roughness_texture if original.roughness_texture != null else original.metallic_texture)
				painted.set_shader_parameter("ground_detail",preload("res://assets/materials/canyon-meadow.png"))
				painted.set_shader_parameter("landscape", landmark.name == &"valley")
				materials[original] = painted
			piece.material_override = materials[original]
			if landmark.name==&"valley": piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		paints[str(landmark.name)] = materials.values()

func season_colors(weights: Vector3) -> void:
	for set_of_paints in paints.values():
		for material in set_of_paints: material.set_shader_parameter("season_weights",weights)

func set_dusk(night: float) -> void:
	if absf(dusk_level-night) < .015: return
	dusk_level = night
	for set_of_paints in paints.values():
		for material in set_of_paints: material.set_shader_parameter("dusk",night)
