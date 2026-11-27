extends RefCounted
## Distances are metres on the rendered horizontal plane, including its Z scale.
const DEPTH := 1.2018504
var points := PackedVector2Array()
var marks := PackedFloat32Array()
var length := 0.

func _init(nodes: Array) -> void:
	for node in nodes:
		var p := Vector2(node)
		if not points.is_empty():
			var delta := (p-points[-1])*Vector2(1.,DEPTH)
			if delta.length_squared()<.00001: continue
			length+=delta.length()
		points.append(p)
		marks.append(length)

func sample(distance: float) -> Vector2:
	if points.size()==1 or distance<=0.: return points[0]
	if distance>=length: return points[-1]
	var index:=clampi(marks.bsearch(distance),1,marks.size()-1)
	return points[index-1].lerp(points[index],(distance-marks[index-1])/(marks[index]-marks[index-1]))

func distance_of(p: Vector2) -> float:
	var metric:=Vector2(1,DEPTH)
	var best:=INF
	var distance:=0.
	for i in range(1,points.size()):
		var start:=points[i-1]*metric
		var end:=points[i]*metric
		var nearest:=Geometry2D.get_closest_point_to_segment(p*metric,start,end)
		var error:=nearest.distance_squared_to(p*metric)
		if error<best:
			best=error
			distance=marks[i-1]+start.distance_to(nearest)
	return distance

func tail(distance: float) -> Array:
	var path: Array=[sample(distance)]
	for i in range(maxi(1,marks.bsearch(distance)),points.size()):path.append(points[i])
	return path
