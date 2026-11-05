class_name DataLoader
extends RefCounted
## Reads JSON content from disk into RawData, validates it, builds a Database.
##
## Usage:
##   var result := DataLoader.load_database("res://data", "res://dialogue")
##   if result.ok(): use result.db  else: print result.errors


class LoadResult:
	extends RefCounted
	var db: Database
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty() and db != null


static func load_database(data_root: String, dialogue_root: String = "") -> LoadResult:
	var result := LoadResult.new()
	var raw := read_raw(data_root, result.errors)
	if not dialogue_root.is_empty():
		_read_dialogue(dialogue_root, raw)
	# Parse errors make validation output noisy; stop early.
	if not result.errors.is_empty():
		return result
	result.errors.append_array(DataValidator.validate(raw))
	result.warnings = DataValidator.warnings(raw)
	if result.errors.is_empty():
		result.db = Database.from_raw(raw)
	return result


## Reads every category under `root`. Parse/shape errors go into `errors`.
static func read_raw(root: String, errors: PackedStringArray) -> RawData:
	var raw := RawData.new()
	for cat in DataSchemas.CATEGORIES:
		match DataSchemas.CATEGORIES[cat]:
			"folder":
				var dir_path := root.path_join(cat)
				if not DirAccess.dir_exists_absolute(dir_path):
					errors.append("%s: missing content folder" % dir_path)
					continue
				for file in _json_files(dir_path):
					_read_entries_file(file, cat, raw, errors)
			"file":
				_read_entries_file(root.path_join(cat + ".json"), cat, raw, errors)
			"single":
				var path := root.path_join(cat + ".json")
				var doc = _read_doc(path, errors)
				if doc == null:
					continue
				if not doc.get("data") is Dictionary:
					errors.append("%s: expected top-level \"data\" object" % path)
					continue
				raw.set_single(cat, doc.data, path)
	return raw


static func _read_entries_file(path: String, cat: String, raw: RawData, errors: PackedStringArray) -> void:
	var doc = _read_doc(path, errors)
	if doc == null:
		return
	if not doc.get("entries") is Array:
		errors.append("%s: expected top-level \"entries\" array" % path)
		return
	for i in doc.entries.size():
		var entry = doc.entries[i]
		if not entry is Dictionary:
			errors.append("%s: entries[%d] is not an object" % [path, i])
			continue
		raw.add_entry(cat, entry, path)


## Returns the parsed top-level Dictionary, or null after recording an error.
static func _read_doc(path: String, errors: PackedStringArray) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: JSON parse error: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	var doc = json.data
	if not doc is Dictionary:
		errors.append("%s: top level must be an object" % path)
		return null
	if doc.get("schema") != float(DataSchemas.SCHEMA_VERSION):
		errors.append("%s: unsupported schema %s (expected %d)" % [path, doc.get("schema"), DataSchemas.SCHEMA_VERSION])
		return null
	return doc


static func _read_dialogue(root: String, raw: RawData) -> void:
	for path in _files_recursive(root, ".dialogue"):
		raw.dialogue_files[path] = FileAccess.get_file_as_string(path)


static func _json_files(dir_path: String) -> PackedStringArray:
	return _files_recursive(dir_path, ".json")


## Sorted for deterministic load order (stable error output, stable ids).
static func _files_recursive(dir_path: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files_recursive(dir_path.path_join(sub), ext))
	for f in dir.get_files():
		if f.ends_with(ext):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
