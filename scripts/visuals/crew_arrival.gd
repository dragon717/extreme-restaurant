extends RefCounted
## The real on-duty cast walks the porch centre line and the normal four-neighbour
## floor graph. Paths share a source; deeper stations depart first so a stopped
## employee cannot seal the aisle for someone following.
const Plan=preload("res://scripts/visuals/canyon_plan.gd")
const Grid=preload("res://scripts/core/layout.gd")
const Route=preload("res://scripts/visuals/walking_route.gd")
const PACE := 2.25
const SPACING := 1.24
var members := []
var rate := 1.
var delay := .62
var complete := false
var door_distance := 0.
var cleared_door := false

func _init(layout: Dictionary,stations: Dictionary) -> void:
	var gate_y:=float(layout.entrance[1])
	var lane:=Plan.entry_lane(gate_y)
	var throat:=Vector2(lane[-1])
	var solid:=Grid.solid_cells(layout)
	for id in stations:
		var goal:=Vector2(stations[id])
		var interior:=Grid.path(layout,throat,goal,solid)
		assert(not interior.is_empty() or goal==throat,"入场站位必须可达")
		var full:=Route.new(lane+interior)
		members.append({"id":id,"path":full,"goal":goal,"distance":0.,"cell":lane[0],"moving":false})
	members.sort_custom(func(a,b): return a.path.length>b.path.length if not is_equal_approx(a.path.length,b.path.length) else a.id<b.id)
	var common:=Route.new(lane)
	door_distance=common.marks[common.marks.size()-2]+.22
	var lead:=maxf(0.,common.length-4.5)
	for i in members.size():
		var m: Dictionary=members[i]
		m.distance=maxf(0.,lead-i*SPACING)
		m.cell=m.path.sample(m.distance)

func advance(delta: float) -> void:
	if complete:return
	var time:=delta*rate
	if delay>0.:
		var held:=minf(delay,time)
		delay-=held
		time-=held
	# Limit physical moves even through accelerated or skipped render frames.
	while time>.00001 and not complete:
		var dt:=minf(1./30.,time)
		time-=dt
		var settled:=0
		for i in members.size():
			var m: Dictionary=members[i]
			if m.distance>=m.path.length-.0001:
				m.moving=false
				settled+=1
				continue
			var travel:=minf(m.path.length,float(m.distance)+PACE*dt)
			var next: Vector2=m.path.sample(travel)
			var blocked:=false
			for other in members:
				if other.id==m.id:continue
				var distance:=((next-Vector2(other.cell))*Vector2(1,Plan.DEPTH)).length_squared()
				if distance<.76*.76 and distance<((Vector2(m.cell)-Vector2(other.cell))*Vector2(1,Plan.DEPTH)).length_squared():
					blocked=true
					break
			m.moving=not blocked
			if not blocked:
				m.distance=travel
				m.cell=next
		complete=settled==members.size()
		if not cleared_door: cleared_door=members.all(func(m):return m.distance>=door_distance)

func finish() -> void:
	for m in members:
		m.distance=m.path.length
		m.cell=m.goal
		m.moving=false
	complete=true
	cleared_door=true
