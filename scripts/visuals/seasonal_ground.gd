extends Node3D
## Ground marks live in map coordinates. Only nearby leaves are queried at each
## footfall. The GPU batches, footprint slots and spray pool never grow during play.
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
const DEPTH := 1.2018504
const LEAVES := 384
const PRINTS := 160
const PUFFS := 64
const FLECKS := 88
const BUCKET := 2.
const STRIDE := .61
const COURT_PATH := [Vector2(-4.25,18.9),Vector2(-4.56,17.6),Vector2(-4.74,16.),Vector2(-4.49,14.6),Vector2(-4.15,12.4),Vector2(-4.77,10.2),Vector2(-5.02,8.6)]
var season := -1
var leaves := PackedVector2Array()
var size_of := PackedFloat32Array()
var twist := PackedFloat32Array()
var batches: Array[MultiMeshInstance3D] = []
var bins := {}
var flying := {}
var walkers := {}
var impressions := {}
var spray := [{},{}]
var cursors := [0,0,0]
var time := 0.
var pending_time := 0.
var step_budget := 0
var random := RandomNumberGenerator.new()
var steps := 0
var displaced := 0

func _ready() -> void:
	for spec in [["oak",LEAVES/2],["maple",LEAVES/2],["boot",PRINTS],["powder",PUFFS],["snow-grain",FLECKS]]:
		var instance := MultiMeshInstance3D.new()
		var mesh := QuadMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/seasons/%s.webp" % spec[0])
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.material = material
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		instance.multimesh.use_colors = true
		instance.multimesh.mesh = mesh
		instance.multimesh.instance_count = int(spec[1])
		instance.multimesh.visible_instance_count = 0
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		batches.append(instance)

func _hide_slot(batch: int, slot: int) -> void:
	batches[batch].multimesh.set_instance_transform(slot,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.00001),Vector3(0,-100,0)))

func set_season(next: int) -> void:
	if next == season: return
	season = next
	random.seed = 817221
	flying.clear()
	walkers.clear()
	impressions.clear()
	spray = [{},{}]
	cursors = [0,0,0]
	pending_time = 0
	for batch in batches:
		batch.multimesh.visible_instance_count = 0
		batch.hide()
	if next == 2:
		_scatter()
		for i in range(2):
			batches[i].multimesh.visible_instance_count = LEAVES/2
			batches[i].show()
	if next == 3:
		for i in range(2,5): batches[i].show()

func _bin(p: Vector2) -> Vector2i:
	return Vector2i((p/BUCKET).floor())

func _index_leaf(i: int) -> void:
	var key := _bin(leaves[i])
	if not bins.has(key): bins[key] = []
	bins[key].append(i)

func _scatter() -> void:
	leaves.resize(LEAVES)
	size_of.resize(LEAVES)
	twist.resize(LEAVES)
	bins.clear()
	for i in range(LEAVES):
		var p: Vector2
		if i < 140:
			p = Plan.route(COURT_PATH,random.randf()) + Vector2.from_angle(random.randf()*TAU)*random.randf_range(.04,1.34)
		else:
			var progress := random.randf()
			p = Plan.from_art(Plan.route(Plan.GUEST_PATH,progress))
			if i % 3 == 0: p += Vector2(0,random.randf_range(-3,3))
			else: p += Vector2.from_angle(random.randf()*TAU)*random.randf_range(.15,1.6)
		leaves[i] = p
		size_of[i] = random.randf_range(.17,.43)
		twist[i] = random.randf()*TAU
		_index_leaf(i)
		_leaf_pose(i,0,0)

func _ground(p: Vector2) -> Vector3:
	return Plan.foot_point(p)+Vector3.UP*.012

func _flat(angle: float) -> Basis:
	return Basis(Vector3.UP,angle)*Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)

func _leaf_pose(i: int, lift: float, tilt: float) -> void:
	var b := _flat(twist[i])*Basis(Vector3.RIGHT,tilt)
	var position := _ground(leaves[i])+Vector3.UP*(lift+.009*(i%4))
	var mesh := batches[i%2].multimesh
	mesh.set_instance_transform(i>>1,Transform3D(b.scaled(Vector3.ONE*size_of[i]),position))
	mesh.set_instance_color(i>>1,Color.WHITE)

func forget(id: String) -> void:
	walkers.erase(id)

func observe(id: String, p: Vector2, visible_area: Rect2) -> void:
	if season < 2: return
	if not visible_area.grow(3.).has_point(p):
		forget(id)
		return
	if not walkers.has(id):
		walkers[id] = {"last":p,"stride":0.,"left":false}
		return
	var walker: Dictionary = walkers[id]
	var previous: Vector2 = walker.last
	var dist := previous.distance_to(p)
	if dist < .001: return
	walker.last = p
	if dist > 5.5:
		walker.stride = 0.
		return
	var direction := (p-previous)/dist
	var at := STRIDE-float(walker.stride)
	while at <= dist and step_budget < 14:
		walker.left = not walker.left
		var foot := previous + direction*at + direction.orthogonal()*(.092 if walker.left else -.092)
		if season == 2: _kick(foot,direction)
		else: _snow_step(foot,direction,walker.left)
		steps += 1
		step_budget += 1
		at += STRIDE
	walker.stride = fposmod(float(walker.stride)+dist,STRIDE)

func _kick(p: Vector2,direction: Vector2) -> void:
	if flying.size() >= 48: return
	var key := _bin(p)
	var kicked := 0
	for z in range(-1,2):
		for x in range(-1,2):
			var bucket: Array = bins.get(key+Vector2i(x,z),[])
			for n in range(bucket.size()-1,-1,-1):
				var i: int = bucket[n]
				var away := leaves[i]-p
				if away.length_squared() > .72: continue
				bucket.remove_at(n)
				var sideways := direction.orthogonal() * (1 if away.dot(direction.orthogonal()) >= 0 else -1)
				flying[i] = {"v":(sideways*.82 + direction*.18)*random.randf_range(1.5,3.1),"lift":.012,"up":random.randf_range(.75,1.65),"spin":random.randf_range(-5.,5.)}
				kicked += 1
				displaced += 1
				if kicked >= 4 or flying.size() >= 48: return

func _next(batch: int) -> int:
	var mesh := batches[batch].multimesh
	var slot: int = cursors[batch-2]
	cursors[batch-2] = (slot+1)%mesh.instance_count
	if batch > 2: _hide_slot(batch,slot)
	mesh.visible_instance_count = maxi(mesh.visible_instance_count,slot+1)
	return slot

func _snow_step(p: Vector2,direction: Vector2,left: bool) -> void:
	var slot := _next(2)
	var foot := _flat(-atan2(direction.y,direction.x)-PI*.5)
	var xf := Transform3D(foot*Basis.from_scale(Vector3(-.24 if left else .24,.46,1)),_ground(p)+Vector3.UP*.017)
	batches[2].multimesh.set_instance_transform(slot,xf)
	batches[2].multimesh.set_instance_color(slot,Color(1,1,1,.88))
	impressions[slot] = time+19.
	var ground := _ground(p)
	for kind in range(2):
		for i in range(2 if kind else 1):
			var index := _next(kind+3)
			var side := direction.orthogonal()*(1. if left else -1.)
			var jitter := -direction*.53 + side*random.randf_range(.22,1.)
			var velocity := Vector3(jitter.x,random.randf_range(.8,1.5),jitter.y)*(.85 if kind else .62)
			var life := .62 if kind else .48
			spray[kind][index] = {"p":ground+Vector3.UP*.03,"v":velocity,"age":0.,"life":life,"scale":random.randf_range(.075,.14) if kind else .35,"twist":random.randf()*PI}

func advance(dt: float,frozen: bool,camera_basis: Basis) -> void:
	step_budget = 0
	if frozen or season < 2: return
	pending_time += dt
	if pending_time < 1./30.: return
	dt = minf(pending_time,.1)
	pending_time = 0.
	time += dt
	for i in flying.keys():
		var leaf: Dictionary = flying[i]
		leaves[i] += Vector2(leaf.v)*dt
		leaf.v = Vector2(leaf.v)*exp(-3.2*dt)
		leaf.up -= 4.5*dt
		leaf.lift += leaf.up*dt
		twist[i] += leaf.spin*dt
		if leaf.lift <= 0:
			flying.erase(i)
			_index_leaf(i)
			_leaf_pose(i,0,0)
		else: _leaf_pose(i,leaf.lift,sin(leaf.lift*5.)*.53)
	for i in impressions.keys():
		var left := float(impressions[i])-time
		if left <= 0:
			_hide_slot(2,i)
			impressions.erase(i)
		elif left < 3.: batches[2].multimesh.set_instance_color(i,Color(1,1,1,.88*left/3.))
	for kind in range(2):
		for i in spray[kind].keys():
			var cloud: Dictionary = spray[kind][i]
			cloud.age += dt
			if cloud.age >= cloud.life:
				_hide_slot(kind+3,i)
				spray[kind].erase(i)
				continue
			cloud.v.y -= (2.7 if kind else .42)*dt
			cloud.p += cloud.v*dt
			var progress := float(cloud.age)/float(cloud.life)
			var radius := float(cloud.scale)*(1.+progress*(.35 if kind else 1.65))
			var face := camera_basis*Basis(Vector3.BACK,float(cloud.twist))
			batches[kind+3].multimesh.set_instance_transform(i,Transform3D(face.scaled(Vector3.ONE*radius),cloud.p))
			batches[kind+3].multimesh.set_instance_color(i,Color(1,1,1,(1.-progress)*(.89 if kind else .61)))
