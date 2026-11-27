extends RefCounted

static func default_path(chapter_id := "street_corner", testing := false) -> String:
	# Development writes stay inside the workspace. Exported builds use platform storage.
	var directory = "res://.local/checkpoints" if OS.has_feature("editor") else "user://checkpoints"
	if testing: directory = "res://.local/test_checkpoints"
	return directory.path_join(chapter_id + ".json")

# Legacy per-chapter checkpoints remain selectable alongside independent new runs.
static func chapter_slots(id: String, testing: bool) -> Array:
	var legacy := default_path(id,testing)
	var dir := DirAccess.open(legacy.get_base_dir())
	if dir == null: return []
	var found := {}
	for filename in dir.get_files():
		var name := String(filename).trim_suffix(".bak")
		if name == id+".json" or (name.begins_with(id+"__") and name.ends_with(".json")):
			found[legacy.get_base_dir().path_join(name)] = true
	var slots := []
	for slot: String in found:
		var data := read_checkpoint(slot)
		var active := slot if FileAccess.file_exists(slot) else slot+".bak"
		var prefix := slot.get_file().get_slice("__",1).get_slice("_",0) if slot != legacy else "1"
		slots.append({"number":int(prefix) if prefix.is_valid_int() else 0,"path":slot,"day":int(data.get("day",1)), "valid":not data.is_empty(),
			"phase":str(data.get("phase","")), "modified":FileAccess.get_modified_time(active)})
	slots.sort_custom(func(a,b): return a.modified > b.modified if a.modified != b.modified else a.path > b.path)
	return slots

static func new_slot(id: String, testing: bool) -> String:
	var legacy := default_path(id,testing)
	if not FileAccess.file_exists(legacy) and not FileAccess.file_exists(legacy+".bak"): return legacy
	var number := 2
	for run in chapter_slots(id,testing): number = maxi(number,int(run.number)+1)
	var stem := legacy.get_basename()+"__%04d_" % number
	var key := Crypto.new().generate_random_bytes(8).hex_encode()
	var next := stem+key+".json"
	while FileAccess.file_exists(next) or FileAccess.file_exists(next+".bak"):
		next = stem+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	return next

static func write_checkpoint(data: Dictionary, path: String = "") -> String:
	if path.is_empty():
		path = default_path()
	var absolute = ProjectSettings.globalize_path(path)
	var error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return TranslationServer.translate("无法创建存档目录（%s）") % error
	var temporary = absolute + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return TranslationServer.translate("无法写入存档（%s）") % FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(absolute):
		var backup = absolute + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		error = DirAccess.rename_absolute(absolute, backup)
		if error != OK:
			return TranslationServer.translate("无法备份旧存档（%s）") % error
	error = DirAccess.rename_absolute(temporary, absolute)
	return "" if error == OK else TranslationServer.translate("无法提交存档（%s）") % error

static func read_checkpoint(path: String = "") -> Dictionary:
	if path.is_empty():
		path = default_path()
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var json = JSON.new()
		if json.parse(FileAccess.get_file_as_string(candidate)) == OK and json.data is Dictionary:
			return json.data
	return {}
