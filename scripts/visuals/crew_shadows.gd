extends Node3D
## The visual billboard turns towards the viewer; its invisible volume follows
## the real direction of travel instead. One instanced pair per silhouette.
const CONTACT=preload("res://scripts/visuals/crew_contact.gdshader")
const CAST=preload("res://scripts/visuals/crew_shadow_volume.gdshader")
const MAX_PER_SHAPE := 256
var batches := {}
var membership := {}

func _ellipsoid(vertices: PackedVector3Array,normals: PackedVector3Array,indices: PackedInt32Array,origin: Vector3,radius: Vector3) -> void:
	const SIDES := 10
	const RINGS := 5
	var base:=vertices.size()
	for j in range(RINGS+1):
		var lat:=PI*float(j)/RINGS
		for i in SIDES:
			var ang:=TAU*float(i)/SIDES
			var n:=Vector3(sin(lat)*cos(ang),cos(lat),sin(lat)*sin(ang))
			vertices.append(origin+n*radius)
			normals.append((n/radius).normalized())
	for j in RINGS:
		for i in SIDES:
			var a:=base+j*SIDES+i
			var b:=base+j*SIDES+(i+1)%SIDES
			if j>0: indices.append_array(PackedInt32Array([a,b+SIDES,b]))
			if j<RINGS-1: indices.append_array(PackedInt32Array([a,a+SIDES,b+SIDES]))

func _volume(kind: String) -> ArrayMesh:
	var v:=PackedVector3Array()
	var n:=PackedVector3Array()
	var ix:=PackedInt32Array()
	if kind=="person":
		_ellipsoid(v,n,ix,Vector3(0,.84,0),Vector3(.125,.152,.132))
		_ellipsoid(v,n,ix,Vector3(0,.54,0),Vector3(.23,.30,.145))
		for side in [-1.,1.]:
			_ellipsoid(v,n,ix,Vector3(side*.092,.18,.013),Vector3(.081,.176,.098))
	elif kind=="toad" or kind=="crab":
		_ellipsoid(v,n,ix,Vector3(0,.49,-.06),Vector3(.66,.43,.55) if kind=="toad" else Vector3(.77,.38,.62))
		_ellipsoid(v,n,ix,Vector3(0,.43,.36),Vector3(.47,.30,.31))
		for side in [-1.,1.]:
			for end in [-1.,1.]:
				_ellipsoid(v,n,ix,Vector3(side*.42,.20,end*.32),Vector3(.19,.19,.25))
	else:
		_ellipsoid(v,n,ix,Vector3(0,.50,0),Vector3(.44,.34,.58))
		_ellipsoid(v,n,ix,Vector3(0,.68,.4),Vector3(.19,.17,.48))
		for side in [-1.,1.]:
			for end in [-1.,1.]:_ellipsoid(v,n,ix,Vector3(side*.36,.22,end*.30),Vector3(.075,.22,.22))
	var arr: Array=[]
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX]=v
	arr[Mesh.ARRAY_NORMAL]=n
	arr[Mesh.ARRAY_INDEX]=ix
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
	var mat:=ShaderMaterial.new()
	mat.shader=CAST
	mat.set_shader_parameter("limbed",kind!="cart")
	mesh.surface_set_material(0,mat)
	return mesh

func _batch(mesh: Mesh,shadows_only: bool) -> MultiMesh:
	var node:=MultiMeshInstance3D.new()
	var mm:=MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.use_custom_data=shadows_only
	mm.mesh=mesh
	mm.instance_count=MAX_PER_SHAPE
	mm.visible_instance_count=0
	node.multimesh=mm
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadows_only else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return mm

func _create(kind: String) -> void:
	var patch:=QuadMesh.new()
	patch.orientation=PlaneMesh.FACE_Y
	patch.size=Vector2(.65,.46) if kind=="person" else Vector2(1.24,1.10)
	var mat:=ShaderMaterial.new()
	mat.shader=CONTACT
	patch.material=mat
	batches[kind]={"casters":_batch(_volume(kind),true),"feet":_batch(patch,false),"ids":[]}

func show_actor(id: String,kind: String,ground: Vector3,height: float,heading: Vector3,phase: float,moving: bool) -> void:
	if membership.has(id) and membership[id].kind!=kind: remove_actor(id)
	if not batches.has(kind): _create(kind)
	var batch: Dictionary=batches[kind]
	if not membership.has(id):
		if batch.ids.size()>=MAX_PER_SHAPE:return
		membership[id]={"kind":kind,"slot":batch.ids.size(),"yaw":0.}
		batch.ids.append(id)
		batch.casters.visible_instance_count=batch.ids.size()
		batch.feet.visible_instance_count=batch.ids.size()
	var actor: Dictionary=membership[id]
	if heading.length_squared()>.01:actor.yaw=atan2(heading.x,heading.z)
	var basis:=Basis(Vector3.UP,float(actor.yaw))*Basis.from_scale(Vector3.ONE*height)
	batch.casters.set_instance_transform(actor.slot,Transform3D(basis,ground))
	batch.casters.set_instance_custom_data(actor.slot,Color(phase,float(moving),0,1))
	batch.feet.set_instance_transform(actor.slot,Transform3D(basis,ground+Vector3.UP*.012))

func remove_actor(id: String) -> void:
	if not membership.has(id):return
	var item: Dictionary=membership[id]
	var group: Dictionary=batches[item.kind]
	var last: int=group.ids.size()-1
	if item.slot!=last:
		var moved: String=group.ids[last]
		group.ids[item.slot]=moved
		membership[moved].slot=item.slot
		for mesh: MultiMesh in [group.casters,group.feet]:
			mesh.set_instance_transform(item.slot,mesh.get_instance_transform(last))
		group.casters.set_instance_custom_data(item.slot,group.casters.get_instance_custom_data(last))
	group.ids.pop_back()
	membership.erase(id)
	group.casters.visible_instance_count=group.ids.size()
	group.feet.visible_instance_count=group.ids.size()
