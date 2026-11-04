extends Node
## Checks every map in res://game/maps/ (doors, spawns, ids, dialogue titles,
## grid alignment...; see core/world/map_rules.gd). Prints errors and warnings.
##
##   godot --headless --path . res://tools/check_maps.tscn
##
## Exits 0 when there are no errors (warnings are allowed), 1 otherwise. Runs as a
## scene so piece scripts (which use autoloads) load with their settings.

const DIALOGUE_DIRS := ["res://dialogue", "res://tests/fixtures"]


func _ready() -> void:
	var loaded := DataLoader.load_database("res://data")
	if not loaded.ok():
		printerr("Data failed to load; run tools/validate_data.gd first.")
		get_tree().quit(1)
		return
	var maps := {}
	for f in DirAccess.get_files_at(GameMap.MAPS_DIR):
		if f.ends_with(".tscn") and not f.begins_with("_"):
			maps[f.get_basename()] = describe(load(GameMap.MAPS_DIR.path_join(f)).instantiate())
	var r := MapRules.check(maps, loaded.db, dialogue_titles())
	for w in r.warnings:
		print("warning: ", w)
	for e in r.errors:
		printerr(e)
	if r.errors.is_empty():
		print("Maps OK (%d maps)" % maps.size())
	get_tree().quit(1 if not r.errors.is_empty() else 0)


## A map scene as MapRules wants it. Frees the instance.
static func describe(map: GameMap) -> Dictionary:
	var out := {"spawns": [], "default_encounter": map.default_encounter, "pieces": []}
	for p in map.pieces():
		if p is Spawn:
			out.spawns.append((p as Spawn).id)
		var props := {}
		for prop in p.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
				props[prop.name] = p.get(prop.name)
		out.pieces.append({"key": p.save_key(), "type": p.get_script().get_global_name(), "props": props,
			"pos": p.position})
	map.free()
	return out


static func dialogue_titles() -> Dictionary:
	var out := {}
	for dir in DIALOGUE_DIRS:
		for path in _files(dir):
			var res: DMCompilerResult = DMCompiler.compile_string(FileAccess.get_file_as_string(path), path)
			out[path] = res.cues.keys()
	return out


static func _files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".dialogue"):
			out.append(dir_path.path_join(f))
	return out
