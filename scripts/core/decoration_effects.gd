extends RefCounted

const Grid = preload("res://scripts/core/layout.gd")
const TARGETS = {
	"waiter_speed": "", "table_eat": "table", "table_quality": "table",
	"table_reputation": "table", "table_gold": "table", "group_base_gold": "table",
	"stove_speed": "stove", "stove_quality": "stove",
}

static func description(definition: Dictionary) -> String:
	var amount = roundi(float(definition.value) * 100)
	match str(definition.effect):
		"waiter_speed": return TranslationServer.translate("范围内服务员移速 +%d%%") % amount
		"table_eat": return TranslationServer.translate("十字相邻餐桌用餐时间缩短 %d%%") % amount
		"table_quality": return TranslationServer.translate("范围内餐桌用餐品质 +%d%%") % amount
		"table_reputation": return TranslationServer.translate("范围内餐桌每位完餐客人 +%d 声望") % int(definition.value)
		"table_gold": return TranslationServer.translate("范围内餐桌结账金币 +%d%%") % amount
		"group_base_gold": return TranslationServer.translate("范围内多人桌每位客人基础餐费 +%d 金币") % int(definition.value)
		"stove_speed": return TranslationServer.translate("相邻灶台烹饪速度 +%d%%") % amount
		"stove_quality": return TranslationServer.translate("相邻灶台出品品质 +%d%%") % amount
	return ""

static func coverage(fixture: Dictionary, definition: Dictionary, layout: Dictionary) -> Dictionary:
	var footprint = Grid.footprint(fixture)
	var result := {}
	var distance = int(definition.reach)
	match str(definition.shape):
		"cross":
			for direction in Grid.DIRECTIONS:
				for n in range(1, distance + 1):
					result[footprint.position + direction * n] = true
		"forward":
			var facing = Grid.FACING[Grid.rotation(fixture)]
			var sideways = Vector2i(facing.y, -facing.x)
			var start: Vector2i = footprint.position
			if facing.x > 0: start.x = footprint.end.x - 1
			if facing.y > 0: start.y = footprint.end.y - 1
			if sideways.x < 0: start.x = footprint.end.x - 1
			if sideways.y < 0: start.y = footprint.end.y - 1
			var width = int(definition.width)
			@warning_ignore("integer_division")
			var offset = (width - 1) / 2
			for n in range(1, distance + 1):
				for edge in range(width):
					result[start + facing * n + sideways * (edge - offset)] = true
		"ring":
			var area = footprint.grow(distance)
			for y in range(area.position.y, area.end.y):
				for x in range(area.position.x, area.end.x):
					var cell = Vector2i(x, y)
					if not footprint.has_point(cell):
						result[cell] = true
	for cell in result.keys():
		if Grid.structural_blocked(layout, cell):
			result.erase(cell)
	return result

static func affects(fixture: Dictionary, definition: Dictionary, cells: Dictionary) -> bool:
	if fixture.type != TARGETS[definition.effect]:
		return false
	if definition.effect == "group_base_gold" and Grid.table_size(fixture) == 1:
		return false
	return Grid.footprint_cells(fixture).any(func(cell): return cells.has(cell))

static func build(layout: Dictionary, definitions: Dictionary) -> Dictionary:
	var result := {"waiter_cells": {}, "fixtures": {}}
	var tables = Grid.facilities(layout, "table")
	var stoves = Grid.facilities(layout, "stove")
	for fixture in Grid.facilities(layout, "decoration"):
		var definition = definitions[fixture.decoration_id]
		var cells = coverage(fixture, definition, layout)
		var effect = str(definition.effect)
		var value = float(definition.value)
		if effect == "waiter_speed":
			for cell in cells:
				result.waiter_cells[cell] = maxf(result.waiter_cells.get(cell, 0.0), value)
			continue
		for target in (tables if TARGETS[effect] == "table" else stoves):
			if affects(target, definition, cells):
				var modifiers = result.fixtures.get_or_add(target.id, {})
				modifiers[effect] = maxf(modifiers.get(effect, 0.0), value)
	return result
