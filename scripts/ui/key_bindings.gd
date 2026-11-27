extends RefCounted

const Store = preload("res://scripts/core/save_store.gd")

const ACTIONS = {
	"rotate": ["旋转设施", KEY_R], "split": ["拆分餐桌", KEY_X], "store": ["收起设施", KEY_BACKSPACE],
	"build": ["建造背包", KEY_B], "menu": ["菜谱", KEY_M], "upgrades": ["招聘与改造", KEY_U],
	"trophy_bag": ["奖杯背包", KEY_T], "trophy_shop": ["奖杯商店", KEY_Y], "purchase": ["采购", KEY_P],
	"open": ["开店", KEY_E], "pause": ["暂停 / 继续", KEY_SPACE], "fast": ["切换倍速", KEY_V], "focus": ["复位视野", KEY_F],
}
const RESERVED = [KEY_NONE, KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META,
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]

var bindings: Dictionary = {}
var save_path: String

func _init(path: String) -> void:
	save_path = path
	bindings = _defaults()
	var saved = Store.read_checkpoint(save_path) if not save_path.is_empty() else {}
	var loaded = {}
	for action in ACTIONS:
		var key = saved.get(action, bindings[action])
		if not (key is int or key is float) or float(key) != floorf(float(key)) or not _assignable(int(key)) or int(key) in loaded.values(): return
		loaded[action] = int(key)
	bindings = loaded

func _defaults() -> Dictionary:
	var result = {}
	for action in ACTIONS: result[action] = ACTIONS[action][1]
	return result

func _assignable(key: int) -> bool:
	return key > 0 and key not in RESERVED and not OS.get_keycode_string(key).is_empty()

func action_for(key: int) -> String:
	return str(bindings.find_key(key)) if key in bindings.values() else ""

func text(action: String) -> String:
	var key = int(bindings[action])
	if key == KEY_SPACE: return tr("空格")
	if key == KEY_BACKSPACE: return "Backspace"
	return OS.get_keycode_string(key)

func bind(action: String, key: int) -> String:
	if not ACTIONS.has(action): return tr("找不到这项操作")
	if not _assignable(key): return tr("此键用于镜头、返回或界面导航，请选其他键。")
	var used = action_for(key)
	if not used.is_empty() and used != action: return tr("这个键已用于「%s」。") % tr(ACTIONS[used][0])
	var updated = bindings.duplicate()
	updated[action] = key
	return _commit(updated)

func reset() -> String:
	return _commit(_defaults())

func _commit(updated: Dictionary) -> String:
	var error = Store.write_checkpoint(updated, save_path) if not save_path.is_empty() else ""
	if error.is_empty(): bindings = updated
	return error
