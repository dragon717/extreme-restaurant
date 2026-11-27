extends RefCounted
## Fixed-camera projection shared by the imported architectural set, signs, guest paths and camera.
const DEPTH := 1.2018504
static var porch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/architecture/entrance_walk.json"))
static var paving: Array[PackedVector2Array] = []
const PIXELS := 6.8
const MAP_ORIGIN := Vector2(511,479)
const ART_SIZE := Vector2(1585,992)
const LANDMARKS := {
	"tavern":Vector2(558,582), "freight":Vector2(328,257), "supply":Vector2(1040,377),
	"workshop":Vector2(1264,275), "gallery":Vector2(1400,420), "dock":Vector2(1420,777),
	"wood_bridge":Vector2(916,634), "stone_bridge":Vector2(807,183)
}
const GUEST_PATH := [Vector2(1280,580),Vector2(1170,575),Vector2(1132,603),Vector2(1090,651),Vector2(996,629),Vector2(937,628),Vector2(885,634),Vector2(826,649),Vector2(773,674),Vector2(725,694),Vector2(678,716),Vector2(623,679),Vector2(552,658),Vector2(512,646)]
const CARGO_PATH := [Vector2(225,286),Vector2(336,257),Vector2(455,238),Vector2(559,218),Vector2(658,214)]
const LABELS := {"tavern":"峡谷餐厅","freight":"货运驿站","supply":"采购处","workshop":"装饰工坊","gallery":"奖杯展廊","dock":"下游河埠"}

static func from_art(point: Vector2) -> Vector2:
	return (point - MAP_ORIGIN) / PIXELS - Vector2(.5,.5)

static func landmark(id: String) -> Vector2:
	return from_art(LANDMARKS[id])

static func bounds() -> Rect2:
	return Rect2(-MAP_ORIGIN / PIXELS, ART_SIZE / PIXELS)

static func route(points: Array, progress: float) -> Vector2:
	var length := 0.0
	for i in range(1, points.size()): length += points[i-1].distance_to(points[i])
	var left := clampf(progress,0,1)*length
	for i in range(1, points.size()):
		var distance: float = points[i-1].distance_to(points[i])
		if left <= distance: return points[i-1].move_toward(points[i], left)
		left -= distance
	return points[-1]

static func walk_height(cell: Vector2) -> float:
	var p:=MAP_ORIGIN+(cell+Vector2(.5,.5))*PIXELS
	# Same cross-sections as the arched mesh in tools/build_canyon.py.
	const XS := [678.,725.,773.,826.,885.,937.,994.,1041.,1092.]
	const YS := [716.,694.,674.,649.,634.,628.,629.,637.,653.]
	if p.x<XS[0] or p.x>XS[-1]:return 0.
	for i in range(1,XS.size()):
		if p.x>XS[i]:continue
		var blend: float=(p.x-XS[i-1])/(XS[i]-XS[i-1])
		if absf(p.y-lerpf(YS[i-1],YS[i],blend))>16.5:return 0.
		return .35+3.1*lerpf(sin(PI*(i-1)/8.),sin(PI*i/8.),blend)
	return 0.

static func from_world(x: float,z: float) -> Vector2:
	return Vector2(x-.5,z/DEPTH-.5)

static func porch_cell(local_x: float,out: float,gate_y := 12.) -> Vector2:
	var offset := Vector2(local_x,out).rotated(-float(porch.yaw))
	return from_world(float(porch.porch_x)+offset.x,(gate_y+float(porch.porch_gate_offset))*DEPTH+offset.y)

static func porch_height(cell: Vector2,gate_y := 12.) -> float:
	var offset := Vector2(cell.x+.5-float(porch.porch_x),(cell.y+.5-gate_y-float(porch.porch_gate_offset))*DEPTH)
	var local := offset.rotated(float(porch.yaw))
	var height := -INF
	for step in porch.treads:
		var nose := float(step[0])
		var half := float(step[1])*.5
		# Account for the clipped outside corners of the actual tread stones.
		var cut := maxf(0.,.23-(nose-local.y))
		if local.y >= float(porch.back)-.02 and local.y <= nose+.025 and absf(local.x) <= half-cut:
			height=maxf(height,float(step[2]))
	return height

static func foot_point(cell: Vector2,gate_y := 12., indoors := false) -> Vector3:
	var z := (cell.y+.5)*DEPTH
	var stair := porch_height(cell,gate_y) if cell.x>-3.5 and cell.x<2.8 and absf(cell.y-gate_y)<4. else -INF
	if is_finite(stair): return Vector3(cell.x+.5,stair+.008,z)
	if indoors or (cell.x>=.25 and absf(cell.y-gate_y-.5)<.95):
		return Vector3(cell.x+.5,.076,z)
	var bridge := walk_height(cell)
	if bridge>0.: return Vector3(cell.x+.5,bridge+.012,(cell.y+.5+bridge*.5547)*DEPTH)
	var x:=cell.x+.5
	if x>=-4.4 and x<=0. and z>=12. and z<=21.:
		if paving.is_empty():
			for outline in porch.path_stones:
				var polygon:=PackedVector2Array()
				for vertex in outline:polygon.append(Vector2(vertex[0],vertex[1]))
				paving.append(polygon)
		for polygon in paving:
			if Geometry2D.is_point_in_polygon(Vector2(x,z),polygon):
				return Vector3(x,float(porch.stone_height)+.008,z)
	return Vector3(x,-.472,z)

static func entry_lane(gate_y := 12.) -> Array:
	var shift := (gate_y-12.)*DEPTH
	return [from_world(.05,28.6+shift),from_world(-.36,25.65+shift),from_world(-2.75,22.7+shift),
		from_world(-3.38,21.36+shift),from_world(-3.16,20.08+shift),porch_cell(0,3.20,gate_y),
		porch_cell(0,2.70,gate_y),porch_cell(0,1.66,gate_y),porch_cell(0,.58,gate_y),
		from_world(.855,(gate_y+1.)*DEPTH),Vector2(1.,gate_y)]
