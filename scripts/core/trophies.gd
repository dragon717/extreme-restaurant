extends RefCounted

const NAMES = ["绿色", "蓝色", "紫色", "橙色", "彩色"]
const COLORS = ["83cf9b", "7ebcf4", "c4a0f9", "ffc377", "f2b9d8"]
const PRISM = ["f9adbb", "f9c38b", "f9e6a5", "a5e4c3", "92d6f4", "bcaff5"]
const ART = ["clock", "cup", "gem", "spoon", "crown", "bell", "hourglass", "boot", "feather", "fan", "book", "pen", "tray", "cart", "pot", "shelf", "coin", "lantern", "ribbon"]
const EFFECTS = {
	"speed": ["服务员移动速度", "percent", 1.0],
	"cook": ["烹饪速率", "percent", 1.0],
	"quality_bonus": ["所有菜品品质", "points", 1.0],
	"flat_gold": ["每位付费客人额外金币", "count", 20],
	"reputation": ["每位完餐客人额外声望", "count", 20],
	"patience": ["客人等餐耐心", "percent", 1.0],
	"eat_time_reduction": ["客人用餐时间", "reduction", .75],
	"chef_speed": ["厨师移动速度", "percent", 1.0],
	"guest_speed": ["客人移动速度", "percent", 1.0],
	"order_patience": ["客人等点单的耐心", "percent", 1.0],
	"choose_reduction": ["客人选菜时间", "reduction", .75],
	"service_reduction": ["服务员点单和交单用时", "reduction", .75],
	"waiter_orders": ["服务员一次可交单数", "count", 5],
	"waiter_food": ["服务员一次可取餐数", "count", 5],
	"chef_carry": ["厨师一次可搬运份数", "count", 10],
	"stove_space": ["每座灶台备餐位", "count", 12],
	"pass_space": ["出餐口餐位", "count", 24],
	"price_pct": ["菜品结账收入", "percent", .50],
	"normal_arrivals": ["普通客到店人数", "percent", .50],
	"rare_extra": ["每天到店的稀有客人", "count", 10],
	"cook_yield": ["烹饪额外份数", "batch", 8],
	"cook_quality_roll": ["烹饪额外品质", "quality_roll", 1.0]
}

static func grade_name(grade: int) -> String:
	return NAMES[clampi(grade, 1, NAMES.size()) - 1]

static func grade_color(grade: int) -> Color:
	return Color(COLORS[clampi(grade, 1, COLORS.size()) - 1])

static func description(item: Dictionary) -> String:
	var effect = EFFECTS[item.effect_type]
	var value = float(item.effect_value)
	match str(effect[1]):
		"count": return "%s +%d" % [effect[0], int(value)]
		"percent": return "%s +%d%%" % [effect[0], roundi(value * 100.0)]
		"reduction": return "%s缩短 %d%%" % [effect[0], roundi(value * 100.0)]
		"points": return "%s +%d 个百分点" % [effect[0], roundi(value * 100.0)]
		"batch": return "每锅有 %d%% 概率产出至少 %d 份" % [roundi(float(item.chance) * 100.0), int(value)]
		"quality_roll": return "每锅有 %d%% 概率额外提高 %d 个百分点品质" % [roundi(float(item.chance) * 100.0), roundi(value * 100.0)]
	return ""

static func price(config: Dictionary, today: int) -> int:
	@warning_ignore("integer_division")
	var growth = today * (today - 1) / 2
	return int(config.base_gold) + today * int(config.daily_step_gold) + growth * int(config.daily_growth_gold)

static func _at(curve: Array, value: int, grade_index: int) -> float:
	for index in range(1, curve.size()):
		var b = curve[index]
		if value <= int(b.at):
			var a = curve[index - 1]
			var fraction = clampf(float(value - int(a.at)) / float(int(b.at) - int(a.at)), 0.0, 1.0)
			return lerpf(a.weights[grade_index], b.weights[grade_index], fraction)
	return float(curve.back().weights[grade_index])

static func odds(config: Dictionary, day: int, total: int, pools: Array) -> PackedFloat64Array:
	var weights := PackedFloat64Array()
	for index in NAMES.size():
		var weight = 0.0 if pools[index].is_empty() else maxf(0.0, _at(config.day_weights, day, index) + _at(config.draw_bonus, total, index))
		weights.append(weight)
	var sum_weight = 0.0
	for weight in weights: sum_weight += weight
	if sum_weight <= 0.0:
		for index in NAMES.size():
			if pools[index].is_empty(): continue
			weights[index] = 1.0
			sum_weight += 1.0
	if sum_weight > 0.0:
		for index in NAMES.size(): weights[index] = weights[index] * 100.0 / sum_weight
	return weights

static func sample(pools: Array, weights: PackedFloat64Array, rng: RandomNumberGenerator) -> String:
	var roll = rng.randf() * 100.0
	var fallback = -1
	for index in NAMES.size():
		if weights[index] <= 0.0: continue
		fallback = index
		roll -= weights[index]
		if roll < 0.0: break
	if fallback < 0: return ""
	var tier = pools[fallback]
	return str(tier[rng.randi_range(0, tier.size() - 1)])
