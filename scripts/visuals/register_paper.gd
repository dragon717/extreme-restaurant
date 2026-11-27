extends MeshInstance3D
## A top-bound sheaf. Vertices used for drawing and picking come from the same
## fixed-step position solver. The ViewportTexture is the ink on the front leaf.
const PAPER = preload("res://assets/interface/register-paper.webp")
const SHADER = preload("res://scripts/visuals/register_paper.gdshader")
const COLS := 11
const ROWS := 15
const PIXELS := Vector2(640,820)
const STEP := 1./30.
const pixel_size := .00338
var texture: Texture2D
var points := PackedVector3Array()
var previous := PackedVector3Array()
var rest := PackedVector3Array()
var edges := PackedInt32Array()
var lengths := PackedFloat32Array()
var stiffness := PackedFloat32Array()
var indices := PackedInt32Array()
var uv := PackedVector2Array()
var packed_positions := PackedFloat32Array()
var pose: ImageTexture
var accumulator := 0.
var clock := 0.
var grip := -1
var grip_origin := Vector3.ZERO
var grip_target := Vector3.ZERO
var pointer_origin := Vector3.ZERO
var pointer_id := -99

func bind_page(art: Texture2D) -> void:
	texture = art
	if mesh != null:
		material_override.set_shader_parameter("ink",art)
		return
	var extent := PIXELS*pixel_size
	for row in ROWS:
		for col in COLS:
			var u := float(col)/(COLS-1)
			var v := float(row)/(ROWS-1)
			uv.append(Vector2(u,v))
			# A slight native curl in the lower fore-edge of the linen stock.
			var curl := v*v*(.052+.178*pow(u,3)+.040*cos(4.9*u))
			rest.append(Vector3((u-.5)*extent.x-.032*v*v*pow(u,4),(.5-v)*extent.y+curl*.27,curl))
			var i := row*COLS+col
			if col+1<COLS and row+1<ROWS:
				indices.append_array(PackedInt32Array([i,i+1,i+COLS,i+1,i+COLS+1,i+COLS]))
	points=rest.duplicate()
	previous=rest.duplicate()
	for row in ROWS:
		for col in COLS:
			var i := row*COLS+col
			if col+1<COLS: _edge(i,i+1,.98)
			if row+1<ROWS: _edge(i,i+COLS,.99)
			if col+1<COLS and row+1<ROWS:
				_edge(i,i+COLS+1,.78)
				_edge(i+1,i+COLS,.78)
			if col+2<COLS: _edge(i,i+2,.46)
			if row+2<ROWS: _edge(i,i+COLS*2,.49)
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX]=rest
	data[Mesh.ARRAY_TEX_UV]=uv
	data[Mesh.ARRAY_INDEX]=indices
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	mesh=surface
	custom_aabb=AABB(Vector3(-extent.x*.5-.76,-extent.y*.5-.55,-.22),Vector3(extent.x+1.52,extent.y+1.1,1.27))
	packed_positions.resize(points.size()*4)
	_upload_pose()
	var paper := ShaderMaterial.new()
	paper.shader=SHADER
	paper.set_shader_parameter("ink",art)
	paper.set_shader_parameter("fibres",PAPER)
	paper.set_shader_parameter("positions",pose)
	paper.set_shader_parameter("sheet_size",extent)
	material_override=paper
	var backing := MeshInstance3D.new()
	backing.name="SecondLeaf"
	backing.mesh=mesh
	backing.custom_aabb=custom_aabb
	var blank := paper.duplicate() as ShaderMaterial
	blank.set_shader_parameter("lower_leaf",true)
	backing.material_override=blank
	add_child(backing)

	# The load-bearing rod is behind the punched head of the sheets; the lower
	# three edges remain free. No solid plate lies underneath them.
	var rail := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius=.039
	rod.bottom_radius=.039
	rod.height=extent.x+.03
	rod.radial_segments=16
	rod.rings=1
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color=Color("98784c")
	bronze.metallic=.65
	bronze.roughness=.44
	rod.material=bronze
	rail.mesh=rod
	rail.rotation.z=PI*.5
	rail.position=Vector3(0,extent.y*.5-.015,-.035)
	add_child(rail)
	var staple := TorusMesh.new()
	staple.inner_radius=.036
	staple.outer_radius=.048
	staple.rings=20
	staple.ring_segments=8
	staple.material=bronze
	for u in [.075,.29,.5,.71,.925]:
		var loop := MeshInstance3D.new()
		loop.mesh=staple
		loop.rotation.z=PI*.5
		loop.scale=Vector3(1,1.65,1.18)
		loop.position=Vector3((float(u)-.5)*extent.x,extent.y*.5-.011,-.010)
		add_child(loop)

func _edge(a: int,b: int,strength: float) -> void:
	edges.append(a)
	edges.append(b)
	lengths.append(rest[a].distance_to(rest[b]))
	stiffness.append(strength)

func _upload_pose() -> void:
	for i in points.size():
		var v := points[i]
		packed_positions[i*4]=v.x
		packed_positions[i*4+1]=v.y
		packed_positions[i*4+2]=v.z
	var image := Image.create_from_data(COLS,ROWS,false,Image.FORMAT_RGBAF,packed_positions.to_byte_array())
	if pose == null: pose=ImageTexture.create_from_image(image)
	else: pose.update(image)

func advance(delta: float,wind: float,nearby: bool) -> void:
	if points.is_empty(): return
	accumulator+=minf(delta,.10)
	var interval := STEP if nearby or grip>=0 else .10
	if accumulator<interval: return
	# At panorama scale the register takes one relaxed step per update. Never
	# accumulate a distant/offscreen catch-up burst when the camera comes back.
	var steps := mini(3,floori(accumulator/STEP)) if nearby or grip>=0 else 1
	accumulator=fmod(accumulator,interval)
	for n in steps: _step(wind)
	_upload_pose()

func _step(wind: float) -> void:
	clock+=STEP
	var pressure := (.68+absf(wind)*.68)*(sin(clock*1.27)+.45*sin(clock*2.43+.8))
	for i in range(COLS,points.size()):
		var p := points[i]
		var free := uv[i].y
		var force := (rest[i]-p)*(15.+10.*(1.-free))
		force += Vector3(.10*pressure,-.68,pressure*(.38+uv[i].x*.67)+.24*sin(clock*2.13-uv[i].y*3.6))*free
		points[i]=p+(p-previous[i])*.949 + force*(STEP*STEP)
		previous[i]=p
	for iteration in 3:
		if grip>=0: points[grip]=grip_target
		for edge in lengths.size():
			var a := edges[edge*2]
			var b := edges[edge*2+1]
			var wa := int(a>=COLS and a!=grip)
			var wb := int(b>=COLS and b!=grip)
			if wa+wb==0: continue
			var segment := points[b]-points[a]
			var distance := segment.length()
			if distance<.0001: continue
			var correction := segment*(stiffness[edge]*(distance-lengths[edge])/(distance*(wa+wb)))
			points[a]+=correction*wa
			points[b]-=correction*wb
		for i in range(COLS,points.size()):
			# Contact with the next sheet is independent of the camera.
			var lower_z := points[i].z*.18-.043
			if points[i].z<lower_z: points[i].z=lower_z
	if grip>=0: points[grip]=grip_target

func point_for_pixel(pixel: Vector2) -> Vector3:
	var scaled := (pixel/PIXELS).clamp(Vector2.ZERO,Vector2.ONE)*Vector2(COLS-1,ROWS-1)
	var col := mini(COLS-2,floori(scaled.x))
	var row := mini(ROWS-2,floori(scaled.y))
	var fraction := scaled-Vector2(col,row)
	var i := row*COLS+col
	if fraction.x+fraction.y<=1.:
		return points[i]+(points[i+1]-points[i])*fraction.x+(points[i+COLS]-points[i])*fraction.y
	return points[i+COLS+1]+(points[i+COLS]-points[i+COLS+1])*(1.-fraction.x)+(points[i+1]-points[i+COLS+1])*(1.-fraction.y)

func pixel_at_ray(origin: Vector3,direction: Vector3) -> Vector2:
	if points.is_empty() or custom_aabb.intersects_ray(origin,direction) == null: return Vector2(-1,-1)
	var nearest := INF
	var pixel := Vector2(-1,-1)
	for j in range(0,indices.size(),3):
		var a := indices[j]
		var b := indices[j+1]
		var c := indices[j+2]
		var hit = Geometry3D.ray_intersects_triangle(origin,direction,points[a],points[b],points[c])
		if hit == null: continue
		var distance := origin.distance_squared_to(hit)
		if distance>=nearest: continue
		nearest=distance
		var weights := Geometry3D.get_triangle_barycentric_coords(hit,points[a],points[b],points[c])
		pixel=(uv[a]*weights.x+uv[b]*weights.y+uv[c]*weights.z)*PIXELS
	return pixel

func can_grip(pixel: Vector2) -> bool:
	return Rect2(Vector2.ZERO,PIXELS).has_point(pixel) and pixel.y>PIXELS.y*.32 and (pixel.x<38. or pixel.x>PIXELS.x-38. or pixel.y>PIXELS.y-38.)

func _particle(pixel: Vector2) -> int:
	var scaled := pixel/PIXELS * Vector2(COLS-1,ROWS-1)
	return clampi(roundi(scaled.y),1,ROWS-1)*COLS+clampi(roundi(scaled.x),0,COLS-1)

func grasp(pixel: Vector2,id: int) -> void:
	grip=_particle(pixel)
	grip_origin=points[grip]
	grip_target=grip_origin
	pointer_origin=point_for_pixel(pixel)
	pointer_id=id

func drag_ray(origin: Vector3,direction: Vector3) -> void:
	if grip<0 or absf(direction.z)<.001: return
	var at := origin+direction*((pointer_origin.z-origin.z)/direction.z)
	var delta := (at-pointer_origin).limit_length(.64)
	grip_target=grip_origin+Vector3(delta.x*.83,delta.y*.84,.04+.84*delta.length())

func release_grip() -> void:
	if grip>=0: previous[grip]=points[grip]
	grip=-1
	pointer_id=-99

func press_ink(pixel: Vector2) -> void:
	if points.is_empty() or grip>=0: return
	var i := _particle(pixel)
	previous[i].z+=.025

func riffle() -> void:
	if points.is_empty() or grip>=0: return
	# A short impulse at the fore-edge propagates through the constraint mesh.
	for i in range(COLS,points.size()):
		previous[i].z -= .053*pow(uv[i].x*uv[i].y,3)
