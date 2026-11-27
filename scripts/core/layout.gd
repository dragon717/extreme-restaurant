extends RefCounted

const DIRECTIONS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const FACING = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]

static func vec(value) -> Vector2:
	if value is Vector2 or value is Vector2i:
		return Vector2(value)
	return Vector2(float(value[0]), float(value[1]))

static func placed(f: Dictionary) -> bool:
	return int(f.pos[0]) >= 0 and int(f.pos[1]) >= 0

static func interaction(f: Dictionary) -> Vector2:
	return vec(f.pos) + Vector2(FACING[rotation(f)])

static func table_size(f: Dictionary) -> int:
	var size = f.get("capacity", 1)
	return int(size) if size is int or size is float else 1

static func footprint(f: Dictionary) -> Rect2i:
	var extent = Vector2i.ONE
	if f.type == "table":
		match table_size(f):
			2: extent = Vector2i(2, 1) if rotation(f) % 2 == 0 else Vector2i(1, 2)
			4: extent = Vector2i(2, 2)
	elif f.type == "decoration":
		extent = Vector2i(vec(f.get("extent", [1, 1])))
		if rotation(f) % 2 != 0: extent = Vector2i(extent.y, extent.x)
	return Rect2i(Vector2i(vec(f.pos)), extent)

static func footprint_cells(f: Dictionary) -> Array:
	var area = footprint(f)
	var cells = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x): cells.append(Vector2i(x, y))
	return cells

static func table_label(size: int) -> String:
	return {1: "单人桌", 2: "双人桌", 4: "四人桌"}[size]

static func rotation(f: Dictionary) -> int:
	var facing = f.get("rotation", 0)
	return int(facing) if can_rotate(f) and (facing is int or facing is float) else 0

static func can_rotate(f: Dictionary) -> bool:
	return f.get("type", "") in ["table", "stove", "wall", "decoration"]

static func wall_line(from: Vector2i, to: Vector2i, turns: int) -> Array:
	var cells = []
	if turns % 2 == 0:
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1): cells.append(Vector2i(x, from.y))
	else:
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1): cells.append(Vector2i(from.x, y))
	return cells

static func can_split(f: Dictionary) -> bool:
	return f.get("type", "") == "table" and table_size(f) in [2, 4]

static func can_store(f: Dictionary) -> bool:
	return f.get("type", "") in ["table", "stove", "trophy", "wall", "decoration"]

static func interaction_cells(f: Dictionary) -> Array:
	if f.type in ["wall", "decoration"]: return []
	if f.type == "table" and table_size(f) > 1:
		var area = footprint(f)
		var tiles = footprint_cells(f)
		var front = FACING[rotation(f)]
		var directions = [front, -front] if table_size(f) == 4 else [front]
		var seats = []
		for direction in directions:
			for tile in tiles:
				if not area.has_point(tile + direction): seats.append(tile + direction)
		return seats
	if f.type not in ["order", "pass"]:
		return [Vector2i(interaction(f))]
	var center = Vector2i(vec(f.pos))
	var cells = []
	for direction in DIRECTIONS:
		cells.append(center + direction)
	return cells

static func interaction_accessible(f: Dictionary, region: Dictionary) -> bool:
	if f.type in ["wall", "decoration"]: return true
	if f.type == "table":
		return interaction_cells(f).all(func(cell): return region.has(cell))
	for cell in interaction_cells(f):
		if region.has(cell): return true
	return false

static func facilities(layout: Dictionary, kind: String) -> Array:
	var found = []
	for f in layout.facilities:
		if f.type == kind and placed(f):
			found.append(f)
	return found

static func find(layout: Dictionary, id: String) -> Dictionary:
	for f in layout.facilities:
		if f.id == id:
			return f
	return {}

static func facility_at(layout: Dictionary, cell: Vector2i) -> Dictionary:
	for f in layout.facilities:
		if placed(f) and footprint(f).has_point(cell): return f
	return {}

static func plot_at(layout: Dictionary, cell: Vector2i) -> Dictionary:
	for plot in layout.get("plots", []):
		var b = plot.bounds
		if cell.x >= int(b.left) and cell.x <= int(b.right) and cell.y >= int(b.top) and cell.y <= int(b.bottom):
			return plot
	return {}

static func locked_plot_at(layout: Dictionary, cell: Vector2i) -> Dictionary:
	var plot = plot_at(layout, cell)
	return plot if not plot.is_empty() and str(plot.id) not in layout.get("unlocked_plots",[]) else {}

# Buildable floor occupies the interior of the simulation grid. The outer ring
# remains a navigation boundary; the visible eaves follow the occupied rooms.
static func has_room(layout: Dictionary, cell: Vector2i) -> bool:
	var interior := Rect2i(1, 1, int(layout.width) - 2, int(layout.height) - 2)
	return interior.has_point(cell) and locked_plot_at(layout, cell).is_empty()

static func occupied_bounds(layout: Dictionary) -> Rect2i:
	var result := Rect2i()
	for y in range(1, int(layout.height) - 1):
		for x in range(1, int(layout.width) - 1):
			var cell := Vector2i(x, y)
			if has_room(layout, cell):
				var tile := Rect2i(cell, Vector2i.ONE)
				result = result.merge(tile) if result.has_area() else tile
	return result

static func kitchen_bounds(layout: Dictionary) -> Dictionary:
	@warning_ignore("integer_division")
	var bounds = layout.get("kitchen_bounds", {"left":1, "top":1, "right":int(layout.width)/2, "bottom":5}).duplicate()
	if "kitchen_extension" in layout.get("unlocked_plots", []):
		for plot in layout.plots:
			if plot.id == "kitchen_extension":
				bounds.right = plot.bounds.right
				break
	return bounds

static func structural_blocked(layout: Dictionary, cell: Vector2i) -> bool:
	var width = int(layout.width)
	var height = int(layout.height)
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height: return true
	if cell == Vector2i(vec(layout.entrance)) or cell == Vector2i(vec(layout.exit)): return false
	if cell.x == 0 or cell.x == width - 1 or cell.y == 0 or cell.y == height - 1: return true
	for wall in layout.get("wall_cells", []):
		if Vector2i(vec(wall)) == cell: return true
	return not locked_plot_at(layout,cell).is_empty()

static func blocked(layout: Dictionary, cell: Vector2i) -> bool:
	return structural_blocked(layout, cell) or not facility_at(layout, cell).is_empty()

static func path(layout: Dictionary, origin: Vector2, destination: Vector2, solid: Dictionary = {}) -> Array:
	return _route(layout, origin, [Vector2i(destination.round())], solid).get("path", [])

static func approach(layout: Dictionary, origin: Vector2, facility: Dictionary) -> Dictionary:
	return approach_cells(layout, origin, interaction_cells(facility))

static func approach_cells(layout: Dictionary, origin: Vector2, targets: Array, solid: Dictionary = {}) -> Dictionary:
	var route = _route(layout, origin, targets, solid)
	if not route.is_empty() and not origin.is_equal_approx(origin.round()):
		route.path.push_front(origin.round())
	return route

static func _route(layout: Dictionary, origin: Vector2, targets: Array, solid: Dictionary) -> Dictionary:
	var start = Vector2i(origin.round())
	var area = Rect2i(0, 0, int(layout.width), int(layout.height))
	if not area.has_point(start): return {}
	var obstacles = solid if not solid.is_empty() else solid_cells(layout)
	if obstacles.has(start): return {}
	var destinations = {}
	for cell in targets:
		if area.has_point(cell) and not obstacles.has(cell): destinations[cell] = true
	if destinations.is_empty(): return {}
	if destinations.has(start): return {"target": Vector2(start), "path": []}
	var queue = [start]
	var parents = {start: start}
	var index = 0
	while index < queue.size():
		var current = queue[index]
		index += 1
		for direction in DIRECTIONS:
			var next = current + direction
			if not area.has_point(next) or parents.has(next) or obstacles.has(next):
				continue
			parents[next] = current
			if destinations.has(next):
				var result = []
				var cursor = next
				while cursor != start:
					result.push_front(Vector2(cursor))
					cursor = parents[cursor]
				return {"target": Vector2(next), "path": result}
			queue.append(next)
	return {}

static func reachable(layout: Dictionary, origin: Vector2, destination: Vector2) -> bool:
	if blocked(layout, Vector2i(destination.round())) or blocked(layout, Vector2i(origin.round())):
		return false
	return origin.round() == destination.round() or not path(layout, origin, destination).is_empty()

static func solid_cells(layout: Dictionary) -> Dictionary:
	var solid = {}
	for y in range(int(layout.height)):
		for x in range(int(layout.width)):
			var cell = Vector2i(x,y)
			if structural_blocked(layout,cell): solid[cell] = true
	for f in layout.facilities:
		if placed(f):
			for cell in footprint_cells(f): solid[cell] = true
	return solid

static func walkable_region(layout: Dictionary, obstacles: Dictionary = {}) -> Dictionary:
	var solid = obstacles if not obstacles.is_empty() else solid_cells(layout)
	var entrance = Vector2i(vec(layout.entrance))
	if solid.has(entrance): return {}
	var queue = [entrance]
	var visited = {entrance:true}
	var index = 0
	while index < queue.size():
		var cell = queue[index]
		index += 1
		for direction in DIRECTIONS:
			var next = cell + direction
			if next.x < 0 or next.y < 0 or next.x >= int(layout.width) or next.y >= int(layout.height): continue
			if visited.has(next) or solid.has(next): continue
			visited[next] = true
			queue.append(next)
	return visited

static func staff_positions(layout: Dictionary, attributes: Dictionary, region: Dictionary = {}) -> Dictionary:
	var result = {"chef": [], "waiter": []}
	var taken = {Vector2i(vec(layout.entrance)): true, Vector2i(vec(layout.exit)): true}
	var needs_defaults = false
	for role in result:
		var count = int(attributes[role + "s"])
		var configured = layout.get(role + "_starts", [])
		result[role].resize(count)
		for index in range(count):
			if index < configured.size():
				var cell = Vector2i(vec(configured[index]))
				if not taken.has(cell):
					result[role][index] = cell
					taken[cell] = true
					continue
			needs_defaults = true
		for index in range(count, configured.size()):
			taken[Vector2i(vec(configured[index]))] = true
	if not needs_defaults: return result
	var open = walkable_region(layout) if region.is_empty() else region
	for role in result:
		if not result[role].has(null): continue
		var spawn = Vector2i(vec(layout[role + "_spawn"]))
		var cells = open.keys()
		cells.sort_custom(func(a, b):
			var da = (a - spawn).length_squared()
			var db = (b - spawn).length_squared()
			return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x)
		)
		var cursor = 0
		for index in range(result[role].size()):
			if result[role][index] != null: continue
			while cursor < cells.size() and taken.has(cells[cursor]): cursor += 1
			var cell = cells[cursor] if cursor < cells.size() else spawn
			result[role][index] = cell
			taken[cell] = true
	return result

static func errors(layout: Dictionary, obstacles: Dictionary = {}) -> Array:
	var result = []
	var cells = {}
	var chair_sizes = {}
	var ids = {}
	var accessible = walkable_region(layout, obstacles)
	for f in layout.facilities:
		if ids.has(f.id): result.append(TranslationServer.translate("设施 ID 重复"))
		ids[f.id] = true
		var capacity = f.get("capacity", 1)
		if f.type == "table" and (not (capacity is int or capacity is float) or float(capacity) != floorf(float(capacity)) or int(capacity) not in [1, 2, 4]):
			result.append(TranslationServer.translate(str(f.name)) + TranslationServer.translate(" 的座位数无效"))
			continue
		var facing = f.get("rotation", 0)
		if can_rotate(f) and (not (facing is int or facing is float) or float(facing) != floorf(float(facing)) or float(facing) < 0 or float(facing) >= FACING.size()):
			result.append(TranslationServer.translate(str(f.name)) + TranslationServer.translate(" 的朝向无效"))
			continue
		if not placed(f): continue
		for cell in footprint_cells(f):
			if cells.has(cell): result.append(TranslationServer.translate(str(f.name)) + TranslationServer.translate(" 与其他设施重叠"))
			cells[cell] = true
			if structural_blocked(layout,cell): result.append(TranslationServer.translate(str(f.name)) + TranslationServer.translate(" 放在不可用的墙体或边界"))
		if not interaction_accessible(f, accessible): result.append(TranslationServer.translate(str(f.name)) + TranslationServer.translate(" 的交互位置不可达"))
		if f.type == "table":
			for cell in interaction_cells(f):
				var prior_size = int(chair_sizes.get(cell, 0))
				if prior_size > 0 and (prior_size > 1 or int(capacity) > 1): result.append(TranslationServer.translate(str(f.name)) + TranslationServer.translate(" 的座位与其他餐桌重叠"))
				chair_sizes[cell] = maxi(prior_size, int(capacity))
	for key in ["waiter_spawn","chef_spawn","exit"]:
		if not accessible.has(Vector2i(vec(layout[key]))): result.append(TranslationServer.translate("出生点 / 出口被阻挡：") + key)
	var starts = {Vector2i(vec(layout.entrance)): true, Vector2i(vec(layout.exit)): true}
	for key in ["waiter_starts","chef_starts"]:
		for position in layout.get(key,[]):
			var cell = Vector2i(vec(position))
			if not accessible.has(cell): result.append(TranslationServer.translate("员工初始站位被阻挡：") + key)
			if starts.has(cell): result.append(TranslationServer.translate("员工初始站位重叠或占用出入口"))
			starts[cell] = true
	return result
