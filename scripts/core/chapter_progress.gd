extends RefCounted

const Store = preload("res://scripts/core/save_store.gd")

static func path(testing := false) -> String:
	return Store.default_path("chapter_progress", testing)

static func _has_victory(checkpoint: Dictionary, id: String) -> bool:
	if id.is_empty() or checkpoint.get("chapter_id", "") != id or checkpoint.get("phase", "") != "REPORT":
		return false
	var report = checkpoint.get("last_report", {})
	return report is Dictionary and report.get("result", "") == "WIN" and report.get("rent_ok", false)

static func completed(options: Array, testing := false) -> Array:
	var saved = Store.read_checkpoint(path(testing)).get("completed", [])
	var wins: Array = saved.duplicate() if saved is Array else []
	for option in options:
		var id = str(option.id)
		if id in wins: continue
		for slot in Store.chapter_slots(id,testing):
			if slot.phase == "REPORT" and _has_victory(Store.read_checkpoint(slot.path),id):
				wins.append(id)
				break
	return wins

static func record_win(checkpoint: Dictionary, testing := false) -> String:
	var id = str(checkpoint.get("chapter_id", ""))
	if not _has_victory(checkpoint, id): return ""
	var saved = Store.read_checkpoint(path(testing)).get("completed", [])
	var wins: Array = saved if saved is Array else []
	if id in wins: return ""
	wins.append(id)
	return Store.write_checkpoint({"completed": wins}, path(testing))
