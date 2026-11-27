extends Node3D

const CAR_COUNT := 6
const LIGHTS_BUDGET := 2
const ENAMEL = preload("res://assets/interface/enamel.png")
const OAK_NORMAL = preload("res://assets/materials/tavern-oak-normal.png")
const COATS = [Color("a46450"), Color("497b78"), Color("98533a"), Color("4e605b"), Color("637c95"), Color("ac8d58")]

var cars: Array[Node3D] = []
var lights: Array[SpotLight3D] = []
var bulb_material := StandardMaterial3D.new()
var tail_material := StandardMaterial3D.new()
var carriage := BoxMesh.new()
var cabin := BoxMesh.new()
var wheel := CylinderMesh.new()

func _ready() -> void:
	carriage.size = Vector3(.80, .30, 1.46)
	cabin.size = Vector3(.73, .29, .72)
	wheel.top_radius = .16
	wheel.bottom_radius = .16
	wheel.height = .13
	wheel.radial_segments = 10
	bulb_material.albedo_color = Color("ffdbad")
	bulb_material.emission_enabled = true
	bulb_material.emission = Color("ffba6d")
	tail_material.albedo_color = Color("a04f43")
	tail_material.emission_enabled = true
	tail_material.emission = Color("a53f23")
	var rubber = _plain(Color("292b30"), .95)
	var window = _plain(Color("30434d"), .3)
	var trim = _plain(Color("c1a271"), .45)
	var glass := BoxMesh.new()
	glass.size = Vector3(.57, .14, .02)
	var bumper := BoxMesh.new()
	bumper.size = Vector3(.75, .065, .075)
	var bulb := SphereMesh.new()
	bulb.radius = .067
	bulb.height = .134
	bulb.radial_segments = 8
	bulb.rings = 4
	for i in range(CAR_COUNT):
		var car := Node3D.new()
		car.rotation.y = PI if i % 2 == 0 else 0.0
		add_child(car)
		cars.append(car)
		var body := _plain(COATS[i], .38)
		body.albedo_texture = ENAMEL
		body.albedo_color = COATS[i] * Color(3.9, 3.2, 2.7)
		body.normal_enabled = true
		body.normal_texture = OAK_NORMAL
		body.normal_scale = .09
		body.metallic = .23
		_part(car, carriage, body, Vector3(0, .27, 0))
		_part(car, cabin, body, Vector3(0, .54, .12))
		_part(car, glass, window, Vector3(0, .55, -.251))
		_part(car, glass, window, Vector3(0, .55, .485))
		_part(car, bumper, trim, Vector3(0, .22, -.74))
		_part(car, bumper, trim, Vector3(0, .22, .74))
		for x in [-.33, .33]:
			for z in [-.48, .48]:
				var tire := _part(car, wheel, rubber, Vector3(x * 1.24, .17, z))
				tire.rotation.z = PI * .5
			_part(car, bulb, bulb_material, Vector3(x, .34, -.75))
			_part(car, bulb, tail_material, Vector3(x, .30, .742))
	for i in range(LIGHTS_BUDGET * 2):
		var beam := SpotLight3D.new()
		beam.light_color = Color("ffe4b7")
		beam.spot_range = 6.3
		beam.spot_angle = 19.0
		beam.spot_angle_attenuation = 1.05
		beam.spot_attenuation = .89
		beam.shadow_enabled = false
		beam.visible = false
		add_child(beam)
		lights.append(beam)

func update(street, depth: float, visible_tiles: Rect2, light_level: float) -> void:
	var candidates: Array[Dictionary] = []
	for i in range(cars.size()):
		var cell: Vector2 = street.vehicle_position(i)
		var car := cars[i]
		car.visible = street.bounds.grow(-1.0).has_point(cell) and visible_tiles.grow(1.4).has_point(cell)
		if not car.visible: continue
		var height := 7.0
		car.position = Vector3(cell.x, height, (cell.y + height * .5547) * depth)
		car.rotation.y = street.vehicle_heading(i)
		if light_level > .14:
			candidates.append({"car": car, "distance": cell.distance_squared_to(visible_tiles.get_center())})
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	bulb_material.emission_energy_multiplier = lerpf(.05, 1.8, light_level)
	tail_material.emission_energy_multiplier = light_level * .8
	for i in range(lights.size()):
		var beam := lights[i]
		var car_index := i >> 1
		beam.visible = car_index < candidates.size()
		if not beam.visible: continue
		var car: Node3D = candidates[car_index].car
		var offset := Vector3(-.29 if i % 2 == 0 else .29, .36, -.78)
		beam.position = car.transform * offset
		beam.rotation = Vector3(deg_to_rad(-9.5), car.rotation.y, 0.0)
		beam.light_energy = light_level * 2.4

func _part(parent: Node3D, mesh: Mesh, material: Material, point: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = point
	parent.add_child(part)
	return part

func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
