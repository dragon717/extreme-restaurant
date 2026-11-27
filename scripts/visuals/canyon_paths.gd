extends "res://scripts/visuals/commercial_street.gd"
const Walk = preload("res://scripts/visuals/walking_route.gd")
const Grid = preload("res://scripts/core/layout.gd")
var inlet
var site := {}
var solids := {}
var outward := {}
const Plan = preload("res://scripts/visuals/canyon_plan.gd")

func configure(map_dimensions: Vector2i, gate := 12.0) -> void:
	dimensions = map_dimensions
	entrance_y = gate
	bounds = Plan.bounds()
	buildings.clear()
	storefronts.clear()
	warm_windows.clear()
	var nodes: Array = []
	for point in Plan.GUEST_PATH: nodes.append(Plan.from_art(point))
	var lane:=Plan.entry_lane(gate)
	nodes.append_array(lane.slice(0,lane.size()-2))
	nodes.append(Vector2(0,gate))
	outward.clear()
	inlet=Walk.new(nodes)

	lamps.clear()

func rain_paving() -> Array[Rect2]:
	return [Rect2(Plan.from_art(Vector2(432,660)), Vector2(27,14)),Rect2(Plan.from_art(Vector2(1005,373)),Vector2(15,6))]

func use_layout(layout: Dictionary) -> void:
	site=layout
	solids=Grid.solid_cells(layout)

func approach_seconds(speed: float) -> float:
	return inlet.length/maxf(.2,speed) if inlet!=null else 50.

func gate_route(progress: float, target: Vector2) -> Vector2:
	if progress>=1.: return target
	var distance: float = inlet.length*clampf(progress,0,1)
	return inlet.sample(distance)+(target-Vector2(0,entrance_y)).limit_length(.44)*smoothstep(inlet.length-1.4,inlet.length,distance)

func exit_route(progress: float,start: Vector2) -> Vector2:
	if progress<=0.: return start
	# The existing service simulation owns the final few metres of egress.
	# Walk back down the same treads at the same speed, rather than traversing
	# the entire river valley during the short building-exit simulation.
	if start.x < -.5: return inlet.sample(inlet.length+start.x-progress*4.5)
	if outward.size()>96:outward.clear()
	if not outward.has(start):
		var nodes: Array=[start]
		var lane:=Plan.entry_lane(entrance_y)
		lane.reverse()
		nodes.append_array(lane.slice(2))
		outward[start]=Walk.new(nodes)
	return outward[start].sample(4.5*clampf(progress,0,1))

func from_queue(distance: float,seat: Vector2):
	var nodes: Array=inlet.tail(distance)
	nodes.append_array(Grid.path(site,Vector2(0,entrance_y),seat,solids))
	return Walk.new(nodes)

func threshold_alpha(cell: Vector2) -> float:
	return smoothstep(.0,1.6,cell.distance_to(Plan.from_art(Plan.GUEST_PATH[0])))

func vehicle_position(index: int) -> Vector2:
	var t := fposmod(elapsed * .025 + index * .17, 2.0)
	return Plan.from_art(Plan.route(Plan.CARGO_PATH, t if t <= 1.0 else 2.0-t))

func vehicle_heading(index: int) -> float:
	var t := fposmod(elapsed * .025 + index * .17, 2.0)
	var fraction := t if t <= 1.0 else 2.0-t
	var delta := Plan.route(Plan.CARGO_PATH, minf(1, fraction+.003))-Plan.route(Plan.CARGO_PATH,maxf(0,fraction-.003))
	if t > 1: delta = -delta
	return atan2(-delta.x,-delta.y)
