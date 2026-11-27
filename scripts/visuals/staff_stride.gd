extends RefCounted
## Shared locomotion for scenery walkers, guests, on-duty staff and the entry cast.
const Plan=preload("res://scripts/visuals/canyon_plan.gd")
const Surface := preload("res://scripts/visuals/planted_stride.gdshader")
static var card: ArrayMesh
var last := Vector3.INF
var heading := Vector3.ZERO
var travelled := 0.
var step := -1
var planted := Vector3.ZERO
var last_view := ""
var last_flip := false
var mesh_node: MeshInstance3D
var paint: ShaderMaterial
var sheet_ref: Texture2D
var silhouette: MeshInstance3D
var tint: ShaderMaterial

static func _card() -> ArrayMesh:
	if card != null: return card
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var faces := PackedInt32Array()
	for row in 13:
		for col in 13:
			var uv := Vector2(col,row)/12.
			verts.append(Vector3(uv.x-.5,.5-uv.y,0))
			uvs.append(uv)
			normals.append(Vector3.BACK)
			tangents.append_array(PackedFloat32Array([1.,0.,0.,1.]))
			if row<12 and col<12:
				var i := row*13+col
				faces.append_array(PackedInt32Array([i,i+1,i+13,i+1,i+14,i+13]))
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX]=verts
	data[Mesh.ARRAY_TEX_UV]=uvs
	data[Mesh.ARRAY_NORMAL]=normals
	data[Mesh.ARRAY_TANGENT]=tangents
	data[Mesh.ARRAY_INDEX]=faces
	card=ArrayMesh.new()
	card.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	return card

func reset() -> void:
	last=Vector3.INF
	heading=Vector3.ZERO
	travelled=0.
	step=-1

func orient(actor,ground: Vector3,camera: Camera3D,cycle: float) -> bool:
	var delta:=ground-last if last.is_finite() else Vector3.ZERO
	last=ground
	delta.y=0
	var walking: bool=actor.current_action in ["walk","carry"]
	if not walking:
		step=-1
		return false
	if delta.length()>3.5:
		step=-1
		delta=Vector3.ZERO
	elif delta.length_squared()>.0000001:
		var next:=delta.normalized()
		if heading.dot(next)<.3: step=-1
		heading=next
		travelled+=delta.length()
	var toward:=Vector3(camera.basis.z.x,0,camera.basis.z.z).normalized()
	var depth:=heading.dot(toward)
	var across:=heading.dot(camera.basis.x)
	var clip: StringName=&"walk_away" if depth<-.48 else (&"walk" if depth>.48 else &"walk_side")
	var sprite: AnimatedSprite2D=actor.sprite
	if not sprite.sprite_frames.has_animation(clip): clip=&"walk"
	if not sprite.sprite_frames.has_animation(clip): return false
	if absf(across)>.055: sprite.flip_h=(across<0.)!=actor.faces_left
	if clip!=last_view or sprite.flip_h!=last_flip:
		step=-1
		last_view=clip
		last_flip=sprite.flip_h
	sprite.pause()
	sprite.animation=clip
	var count:=sprite.sprite_frames.get_frame_count(clip)
	var phase:=fposmod(travelled/maxf(.01,cycle),1.)
	sprite.set_frame_and_progress(mini(count-1,floori(phase*count)),0.)
	return true

func draw(plane: Sprite3D,frame: Texture2D,sheet: Texture2D,normal: Texture2D,sole: Vector2,cycle: float,rolling: bool,through_wall: bool,gate_y: float,indoors: bool) -> void:
	if not is_instance_valid(mesh_node) or mesh_node.get_parent()!=plane:
		mesh_node=MeshInstance3D.new()
		mesh_node.name="GroundedStride"
		mesh_node.mesh=_card()
		mesh_node.custom_aabb=AABB(Vector3(-1.8,-.65,-.9),Vector3(3.6,3.9,1.8))
		paint=ShaderMaterial.new()
		paint.shader=Surface
		mesh_node.material_override=paint
		plane.add_child(mesh_node)
		sheet_ref=null
		silhouette=null
		tint=null
	if sheet_ref!=sheet:
		sheet_ref=sheet
		paint.set_shader_parameter("paint",sheet)
		paint.set_shader_parameter("relief",normal)
	var rect: Rect2=frame.region if frame is AtlasTexture else Rect2(Vector2.ZERO,frame.get_size())
	var size:=sheet.get_size()
	var extent:=frame.get_size()*plane.pixel_size
	var sx:=1.-sole.x if plane.flip_h else sole.x
	var foot:=plane.to_global(Vector3((sx-.5)*extent.x,0,0))
	var next_step:=floori(travelled/maxf(.01,cycle)*2.)
	if step!=next_step:
		step=next_step
		planted=foot
		planted.y=Plan.foot_point(Plan.from_world(foot.x,foot.z),gate_y,indoors).y
	var shift:=plane.global_basis.inverse()*(planted-foot)
	if through_wall and not is_instance_valid(silhouette):
		silhouette=MeshInstance3D.new()
		silhouette.mesh=mesh_node.mesh
		silhouette.custom_aabb=mesh_node.custom_aabb
		silhouette.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tint=ShaderMaterial.new()
		tint.shader=preload("res://scripts/visuals/stride_occlusion.gdshader")
		silhouette.material_override=tint
		mesh_node.add_child(silhouette)
	if is_instance_valid(silhouette):
		silhouette.visible=through_wall
		if through_wall:tint.set_shader_parameter("paint",sheet)
	var materials: Array=[paint,tint] if through_wall else [paint]
	for surface: ShaderMaterial in materials:
		surface.set_shader_parameter("region",Vector4(rect.position.x/size.x,rect.position.y/size.y,rect.size.x/size.x,rect.size.y/size.y))
		surface.set_shader_parameter("opacity",plane.modulate.a)
		surface.set_shader_parameter("extent",extent)
		surface.set_shader_parameter("sole",sole)
		surface.set_shader_parameter("flipped",plane.flip_h)
		surface.set_shader_parameter("planted_shift",Vector3.ZERO if rolling else shift)
	plane.layers=0
	mesh_node.show()

func idle(plane: Sprite3D) -> void:
	plane.layers=1
	var stride:=plane.get_node_or_null("GroundedStride") as MeshInstance3D
	if stride!=null: stride.hide()
