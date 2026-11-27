extends RefCounted
## Index each helper within its actual post. Specialty staff are separate and
## never inherit a minion modifier or count twice for a bond.
const KINDS := ["melee","caster","siege"]
const NAMES := {"melee":"近战小兵","caster":"法师小兵","siege":"炮车兵"}
const TRAITS := {
	"chef":{"melee":"前往灶位时移速提高 6%。","caster":"烹饪用时减少 4%。","siege":"将成菜搬往出餐口时移速提高 8%。"},
	"waiter":{"melee":"前往客桌接单时移速提高 6%。","caster":"桌边点单用时减少 10%。","siege":"端菜送往客桌时移速提高 8%。"}
}

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for role in value:
		if role not in ["chef","waiter"] or not value[role] is Array: return false
		if value[role].size()>(12 if role=="chef" else 18): return false
		for kind in value[role]:
			if kind not in KINDS: return false
	return true

static func at(slots: Dictionary, role: String, helper_index: int) -> String:
	var assigned: Array = slots.get(role,[])
	return str(assigned[helper_index]) if helper_index>=0 and helper_index<assigned.size() else "melee"

static func set_slot(slots: Dictionary,role: String,index: int,kind: String) -> void:
	if not slots.has(role): slots[role]=[]
	while slots[role].size()<=index: slots[role].append("melee")
	slots[role][index]=kind

static func movement(kind: String,role: String,job: String) -> float:
	if kind=="melee" and ((role=="chef" and job=="COOK") or (role=="waiter" and job=="ORDER")): return 1.06
	if kind=="siege" and ((role=="chef" and job=="TRANSFER") or (role=="waiter" and job=="DELIVER")): return 1.08
	return 1.

static func duration(kind: String,role: String,job: String) -> float:
	if kind=="caster":
		if role=="chef" and job=="COOK": return .96
		if role=="waiter" and job=="ORDER": return .90
	return 1.
