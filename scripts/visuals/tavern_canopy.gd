extends RefCounted
## All rooms use the same hip surface. The joinery follows the authored bay
## profiles outside the grid and spans doorways without putting posts in them.
const DEPTH := 1.2018504
const PLATE := 4.15
const FASCIA := .19
const SURFACE = preload("res://scripts/visuals/tavern_roof.gdshader")
const TILES = preload("res://assets/materials/house-roof.jpg")
const NORMAL = preload("res://assets/materials/inn-shingles-normal.png")
var large_hall := false
var elevations := {}
var window_material: ShaderMaterial
var gable_material: ShaderMaterial
var rear_materials := {}
var ridge_material: ShaderMaterial
var runs := {}
var heights := {}
var height_edges: Array[PackedVector2Array] = []
var coverage := ShaderMaterial.new()
var rim_paint: ShaderMaterial

func _init() -> void:
	coverage.shader = SURFACE
	coverage.set_shader_parameter("grain",TILES)
	coverage.set_shader_parameter("relief",NORMAL)
	coverage.set_shader_parameter("pigment",Color("f5ddbd"))
	coverage.set_shader_parameter("is_roof",true)
	coverage.set_shader_parameter("surface_roughness",.87)
	rim_paint = coverage.duplicate()
	window_material = _paint(preload("res://assets/materials/house-window.jpg"))
	gable_material = _paint(preload("res://assets/materials/inn-plaster.jpg"))
	ridge_material = _paint(preload("res://assets/materials/inn-oak.jpg"))
	window_material.set_shader_parameter("leadlight",true)
	rear_materials = {"rear_windows":window_material.duplicate(),"rear_gable":gable_material.duplicate(),"rear_timbers":ridge_material.duplicate()}

func _paint(art: Texture2D) -> ShaderMaterial:
	var mat := coverage.duplicate() as ShaderMaterial
	mat.set_shader_parameter("is_roof",false)
	mat.set_shader_parameter("pigment",Color.WHITE)
	mat.set_shader_parameter("grain",art)
	mat.set_shader_parameter("relief",null)
	return mat

func set_cover(amount: float) -> void:
	for mat in [coverage,window_material,gable_material,ridge_material]:
		mat.set_shader_parameter("coverage",amount)

func _ridge_z(x: float) -> float:
	return (6.65 if large_hall else 6.0) - (x-6.)*.24

func _porch_x(z: float) -> float:
	return (9.8 if large_hall else 7.35)+(z-11.)*.15


func begin() -> void:
	runs.clear()
	heights.clear()
	height_edges.clear()

func add_run(owner: String, path: PackedVector2Array) -> void:
	var start := Vector2i(path[0].round())
	runs[start] = {"owner":owner,"path":path}
	height_edges.append(PackedVector2Array([path[0],path[-1]]))

func _height(p: Vector2) -> float:
	if heights.has(p): return heights[p]
	var dist := INF
	for edge in height_edges:
		var nearest := Geometry2D.get_closest_point_to_segment(p,edge[0],edge[1])
		dist = minf(dist,nearest.distance_to(p))
	var main_end := 21. if large_hall else 13.
	var along := clampf((p.x-1.)/(main_end-1.),0,1)
	var end_fall := smoothstep(-.8,1.,p.x)*(1.-smoothstep(main_end,main_end+3.,p.x))
	var curve := pow(maxf(0.,1.-absf(p.y-_ridge_z(p.x))/(7.7 if large_hall else 6.25)),1.4)
	var main := ((6.5 if large_hall else 5.35)+.73*pow(absf(2.*along-1.),3.))*curve*end_fall
	var porch := (4.5 if large_hall else 3.9)*pow(maxf(0.,1.-absf(p.x-_porch_x(p.y))/4.35),1.37)
	porch *= smoothstep(6.5,11.7,p.y)*(1.-smoothstep(15.,18.,p.y))
	var height := PLATE + maxf(maxf(main,porch),.33*dist+.010*dist*dist)
	heights[p] = height
	return height

func _world(p: Vector2,h: float) -> Vector3:
	return Vector3(p.x,h,p.y*DEPTH)

func _vertex(surface: SurfaceTool, p: Vector3, normal: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.set_normal(normal)
	surface.add_vertex(p)

func _tri(s: SurfaceTool, a: Vector3,b: Vector3,c: Vector3, colored := false) -> void:
	var n := (c-a).cross(b-a)
	if n.length_squared() < .000001: return
	n = n.normalized()
	for p in [a,b,c]:
		var uv := Vector2(p.x*.22,p.z*.22)
		if colored:
			uv = Vector2((p.x+p.z)*.37,p.y*.76)
			s.set_color(Color("a08262"))
		_vertex(s,p,n,uv)

func _quad(s: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3, colored := false) -> void:
	_tri(s,a,b,c,colored)
	_tri(s,a,c,d,colored)

func _surface() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	s.set_color(Color.WHITE)
	return s

func _mesh(s: SurfaceTool, parent: Node3D, label: String, material: Material) -> MeshInstance3D:
	s.index()
	s.generate_tangents()
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = s.commit()
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

# Each point stores its inner seat on the grid and the actual wall crown.
# Endpoints of consecutive wall modules coincide exactly, including concave joints.
func _panel(s: SurfaceTool, bottom_a: Vector3,bottom_b: Vector3,top_a: Vector3,top_b: Vector3,u0: float,u1: float) -> void:
	var normal := (top_a-bottom_a).cross(bottom_b-bottom_a).normalized()
	var positions := [bottom_a,bottom_b,top_b,bottom_a,top_b,top_a]
	var uvs := [Vector2(u0,1),Vector2(u1,1),Vector2(u1,0),Vector2(u0,1),Vector2(u1,0),Vector2(u0,0)]
	for i in range(6): _vertex(s,positions[i],normal,uvs[i])

func _beam(s: SurfaceTool,a: Vector3,b: Vector3,width: float) -> void:
	var axis := (b-a).normalized()
	if axis.is_zero_approx(): return
	var across := axis.cross(Vector3.UP if absf(axis.y)<.95 else Vector3.RIGHT).normalized()*width*.5
	var side := axis.cross(across).normalized()*width*.5
	var offsets := [across+side,across-side,-across-side,-across+side]
	for i in range(4):
		var l: Vector3 = offsets[i]
		var r: Vector3 = offsets[(i+1)%4]
		_quad(s,a+l,a+r,b+r,b+l)

func _outline() -> Array:
	var line := []
	var seen := {}
	for start in runs:
		if seen.has(start): continue
		var cursor: Vector2i = start
		var ring := []
		while runs.has(cursor) and not seen.has(cursor):
			seen[cursor] = true
			var run: Dictionary = runs[cursor]
			var path: PackedVector2Array = run.path
			for j in range(path.size()-1):
				var start_p := path[j]
				var end_p := path[j+1]
				var axis := (path[-1]-path[0]).normalized()
				var d0 := (start_p-path[0]).dot(axis)
				var d1 := (end_p-path[0]).dot(axis)
				var distances: Array[float] = [d0]
				for split in range(floori(d0)+1,ceili(d1)):
					if split < d1-.00001: distances.append(float(split))
				for dist in distances:
					var ratio := (dist-d0)/maxf(.00001,d1-d0)
					ring.append({"p":start_p.lerp(end_p,ratio),"base":path[0]+axis*dist,"axis":axis,"owner":run.owner})

			cursor = Vector2i(path[-1].round())
		if ring.size() >= 3:
			assert(cursor == start, "屋檐边界必须闭合")
			line.append(ring)
	return line

func build(wings: Dictionary, plots: Dictionary, wood: Material) -> Array[MeshInstance3D]:
	var panels: Array[MeshInstance3D] = []
	large_hall = plots.has("kitchen_extension")
	for mat in [coverage,rim_paint]: mat.set_shader_parameter("mature",large_hall)
	elevations.clear()
	var covers := {}
	var aprons := {}
	var edges := {}
	for id in wings:
		var skin := _surface()
		var fascia := _surface()
		covers[id] = skin
		edges[id] = fascia
		aprons[id] = _surface()
		elevations[id] = {"windows":_surface(),"gable":_surface(),"timbers":_surface(),"rear_windows":_surface(),"rear_gable":_surface(),"rear_timbers":_surface(),"visible":{}}
		var rect: Rect2i = plots[id]
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var p := Vector2(x,y)
				var a := _world(p,_height(p))
				var b := _world(p+Vector2.RIGHT,_height(p+Vector2.RIGHT))
				var c := _world(p+Vector2.ONE,_height(p+Vector2.ONE))
				var d := _world(p+Vector2.DOWN,_height(p+Vector2.DOWN))
				var mid := p+Vector2(.5,.5)
				var crown := _world(mid,_height(mid))
				_tri(skin,a,b,crown)
				_tri(skin,b,c,crown)
				_tri(skin,c,d,crown)
				_tri(skin,d,a,crown)
	var has_eave := {}
	for ring in _outline():
		var tips := PackedVector3Array()
		for i in range(ring.size()):
			var p: Vector2 = ring[i].p
			var prev := (p-Vector2(ring[posmod(i-1,ring.size())].p)).normalized()
			var next := (Vector2(ring[(i+1)%ring.size()].p)-p).normalized()
			var outward := (prev.orthogonal()+next.orthogonal()).normalized()
			var reach := .44 / maxf(.42,outward.dot(next.orthogonal()))
			var lip := p+outward*reach
			tips.append(_world(lip,_height(ring[i].base)-.16-.13*p.distance_to(ring[i].base)))
		for i in range(ring.size()):
			var j: int = (i+1)%ring.size()
			var a := _world(ring[i].base,_height(ring[i].base))
			var b := _world(ring[j].base,_height(ring[j].base))
			var lip_a := tips[i]
			var lip_b := tips[j]
			var id: String = ring[i].owner
			# The apron covers the full distance from the straight roof to the polygonal bays.
			_quad(aprons[id],b,a,lip_a,lip_b)
			_quad(edges[id],lip_a,lip_b,lip_b-Vector3.UP*FASCIA,lip_a-Vector3.UP*FASCIA,true)
			var wall_a := _world(ring[i].p,.05)
			var wall_b := _world(ring[j].p,.05)
			var top_a := Vector3(wall_a.x,PLATE-.2,wall_a.z)
			var top_b := Vector3(wall_b.x,PLATE-.2,wall_b.z)
			var axis: Vector2 = ring[i].axis
			var outward := Vector3(axis.y,0,-axis.x)*.145
			wall_a += outward
			wall_b += outward
			top_a += outward
			top_b += outward
			var seat_a: Vector2 = ring[i].base
			var seat_b: Vector2 = ring[j].base
			var gate := is_equal_approx(seat_a.x,1.) and is_equal_approx(seat_b.x,1.) and (seat_a.y+seat_b.y)*.5 >= 12. and (seat_a.y+seat_b.y)*.5 < 14.
			var u0 := (seat_a.x+seat_a.y)*.38
			var u1 := (seat_b.x+seat_b.y)*.38
			var skin: Dictionary = elevations[id]
			var rear := axis.x > .5
			var kind := "rear_windows" if rear else "windows"
			var gable := "rear_gable" if rear else "gable"
			var beam := "rear_timbers" if rear else "timbers"
			if not gate:
				_panel(skin[kind],wall_a,wall_b,top_a,top_b,u0,u1)
				skin.visible[kind] = true
			var cap_a := Vector3(top_a.x,lip_a.y-.11,top_a.z)
			var cap_b := Vector3(top_b.x,lip_b.y-.11,top_b.z)
			if maxf(cap_a.y,cap_b.y)>PLATE+.02:
				_panel(skin[gable],top_a,top_b,cap_a,cap_b,u0,u1)
				skin.visible[gable] = true
				if absf(roundf(seat_a.x+seat_a.y)-(seat_a.x+seat_a.y))<.01:
					_beam(skin[beam],top_a+outward*.4,cap_b+outward*.4,.115)
					_beam(skin[beam],top_a+outward*.4,cap_a+outward*.4,.105)
					skin.visible[beam] = true
			if not gate and posmod(roundi(seat_a.x+seat_a.y),3)==0 and seat_a.distance_to(seat_a.round()) < .01:
				_beam(edges[id],wall_a,cap_a,.14)

			has_eave[id] = true
	# Ridge timbers, bowed tips and the cross-gable meet the same sampled roof.
	var truss: Dictionary = elevations.homestead
	var last_x := 21 if large_hall else 13
	for x in range(1,last_x):
		var left := Vector2(x,_ridge_z(x))
		var right := Vector2(x+1,_ridge_z(x+1.))
		_beam(truss.timbers,_world(left,_height(left)+.02),_world(right,_height(right)+.02),.20)
	for z in range(11,15):
		var lo := Vector2(_porch_x(z),z)
		var hi := Vector2(_porch_x(z+1.),z+1)
		_beam(truss.timbers,_world(lo,_height(lo)+.05),_world(hi,_height(hi)+.05),.16)
	truss.visible.timbers = true
	for id in wings:
		for part in elevations[id].visible:
			var paint: ShaderMaterial = rear_materials.get(part)
			if paint == null: paint = {"windows":window_material,"gable":gable_material,"timbers":ridge_material}[part]
			_mesh(elevations[id][part],wings[id].roof,part,paint)
		panels.append(_mesh(covers[id],wings[id].roof,"JoinedRoof",coverage))
		if has_eave.has(id):
			_mesh(aprons[id],wings[id].roof,"EaveTiles",rim_paint)
			_mesh(edges[id],wings[id].roof,"Fascia",wood)
	elevations.clear()
	return panels
