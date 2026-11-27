extends RefCounted

const Store = preload("res://scripts/core/save_store.gd")
const LIMIT := 5
const STARTERS := ["kilnkeeper", "ovenhand", "ferrier", "riverclaw", "mosskeeper"]
const PROFILES := {
	"kilnkeeper": {"name":"布兰德", "title":"复仇焰魂", "reference_skill":"烈焰风暴", "badge":"res://assets/crew/Brand-R.png", "roles":["chef"], "skill":"连灶飞火", "copy":"手动点燃附近已经备锅的灶。", "icon":"stove"},
	"ovenhand": {"name":"潘森", "title":"不屈之枪", "reference_skill":"大荒星陨", "badge":"res://assets/crew/Pantheon-R.png", "roles":["chef","waiter"], "skill":"熟锅", "copy":"在后厨加快家常饭的烹饪。", "icon":"recipe"},
	"ferrier": {"name":"希维尔", "title":"战争女神", "reference_skill":"狩猎", "badge":"res://assets/crew/Sivir-R.png", "roles":["waiter"], "skill":"河道急送", "copy":"手动开启出餐口旁的短时配送加速。", "icon":"move"},
	"riverclaw": {"name":"峡谷迅捷蟹", "title":"", "reference_skill":"", "badge":"res://assets/crew/Scuttler-icon.png", "roles":["waiter"], "skill":"顺水", "copy":"受河道急送影响时多维持片刻。", "icon":"district"},
	"mosskeeper": {"name":"魔沼蛙", "title":"", "reference_skill":"", "badge":"res://assets/crew/Gromp-icon.png", "roles":["waiter"], "skill":"熟客一眼", "copy":"为已选好菜的客人更快点单。", "icon":"crowd"},
	"hearthling": {"name":"安妮", "title":"黑暗之女", "reference_skill":"提伯斯之怒", "badge":"res://assets/crew/Annie-R.png", "roles":["chef"], "skill":"隔灶助火", "copy":"和布兰德相邻备锅时，更早准备好连灶飞火。", "icon":"stove"},
}

var unlocked: Array = []
var groups: Array = []
var file_path := ""

func _init(testing := false) -> void:
	file_path = Store.default_path("crew_profile", testing)
	var profile := Store.read_checkpoint(file_path)
	var pool = profile.get("unlocked", STARTERS)
	if pool is Array:
		for id in pool:
			if id is String and PROFILES.has(id) and id not in unlocked: unlocked.append(id)
	for id in STARTERS:
		if id not in unlocked: unlocked.append(id)
	var saved_groups = profile.get("groups", [])
	if saved_groups is Array:
		for group in saved_groups:
			if group is Dictionary and group.get("name") is String and valid(group.get("crew"), unlocked):
				groups.append({"name": str(group.name), "crew": group.crew.duplicate(true)})

static func valid(lineup: Variant, pool: Array = []) -> bool:
	if not lineup is Array or lineup.size() != LIMIT: return false
	var used := {}
	var chefs := 0
	for entry in lineup:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("role") is String:
			return false
		var id: String = entry.id
		if used.has(id) or not PROFILES.has(id) or (not pool.is_empty() and id not in pool):
			return false
		if entry.role not in PROFILES[id].roles: return false
		used[id] = true
		if entry.role == "chef": chefs += 1
	return chefs in [1, 2]

static func by_role(lineup: Array, role: String) -> Array:
	return lineup.filter(func(entry): return entry.role == role).map(func(entry): return entry.id)

func save_group(index: int, label: String, lineup: Array) -> String:
	var clean := label.strip_edges()
	if clean.is_empty() or clean.length() > 36: return tr("组名需要 1 至 36 个字符。")
	if not valid(lineup, unlocked): return tr("先选好五位并分配岗位。")
	for i in range(groups.size()):
		if i != index and groups[i].name == clean: return tr("这个组名已被使用。")
	var next := groups.duplicate(true)
	var group := {"name": clean, "crew": lineup.duplicate(true)}
	if index >= 0 and index < next.size():
		next[index] = group
	else:
		next.append(group)
	var error := Store.write_checkpoint({"unlocked": unlocked, "groups": next}, file_path)
	if error.is_empty(): groups = next
	return error
