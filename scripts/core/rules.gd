extends RefCounted

const BASE_MODIFIERS = {
	"speed": 0.0, "cook": 0.0, "patience": 0.0, "quality": 0, "reputation": 0,
	"flat_gold": 0, "price_pct": 0.0, "normal_arrivals": 0.0, "eat_time_reduction": 0.0
}
const MAX_EAT_TIME_REDUCTION := 0.75

static func ticks(seconds: float, tick_ms: int) -> int:
	return maxi(1, int(ceil(seconds * 1000.0 / float(tick_ms) - 0.0000001)))

static func quality(base: float, levels: int, chapter: Dictionary, bonus := 0.0) -> float:
	var q = chapter.quality_rules
	return clampf(base + float(q.step) * levels + bonus, float(q.minimum), float(q.maximum))

static func payment(base: int, q: float, percent: float, multiplier: float, flat: int, override_zero: bool = false) -> int:
	if override_zero:
		return 0
	# Convert UI multipliers to fixed-point basis points; round only once.
	var quality_bp = int(round(q * 10000.0))
	var price_bp = int(round((1.0 + percent) * 10000.0))
	var guest_bp = int(round(multiplier * 10000.0))
	var numerator = base * quality_bp * price_bp * guest_bp
	@warning_ignore("integer_division")
	return maxi(0, int(numerator / 1000000000000) + flat)

static func customer_count(base: int, percent: float, flat: int = 0) -> int:
	var bp = int(round((1.0 + percent) * 10000.0))
	@warning_ignore("integer_division")
	return maxi(0, int(base * bp / 10000) + flat)

static func modifier(buff_states: Dictionary, definitions: Dictionary) -> Dictionary:
	var total = BASE_MODIFIERS.duplicate()
	for id in buff_states:
		var definition = definitions[id]
		var key = definition.effect_type
		total[key] += definition.effect_per_stack * buff_states[id].stack_count
	return total
