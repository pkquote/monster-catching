extends SceneTree
## Compiles every .dialogue file with Dialogue Manager and prints errors.
##   godot --headless --path . --script res://tools/check_dialogue.gd
## Exits 0 when all files compile, 1 otherwise.

const ROOT := "res://dialogue"


## Ids passed to these calls must exist in the data: call -> data category.
const ID_CALLS := {"give_item": "items", "take_item": "items", "has_item": "items",
	"start_battle": "tamers", "give_creature": "creatures", "start_minigame": "minigames"}


func _init() -> void:
	var failed := 0
	var db := DataLoader.load_database("res://data").db
	var id_call := RegEx.create_from_string(r'Story\.(\w+)\(\s*"([^"]*)"')
	var any_call := RegEx.create_from_string(r'\b(Story|Cutscene)\.(\w+)\s*\(')
	var known := {"Story": _funcs("res://game/autoload/story.gd"), "Cutscene": _funcs("res://game/autoload/cutscene.gd")}
	for path in _files(ROOT):
		var text := FileAccess.get_file_as_string(path)
		var result: DMCompilerResult = DMCompiler.compile_string(text, path)
		for e in result.errors:
			printerr("%s:%d:%d: %s" % [path, e.line_number + 1, e.column_number, DMConstants.get_error_message(e.error)])
			failed += 1
		var lines := text.split("\n")
		for i in lines.size():
			for m in any_call.search_all(lines[i]):
				if not known[m.get_string(1)].has(m.get_string(2)):
					printerr("%s:%d: %s.%s() doesn't exist" % [path, i + 1, m.get_string(1), m.get_string(2)])
					failed += 1
			for m in id_call.search_all(lines[i]):
				var cat: String = ID_CALLS.get(m.get_string(1), "")
				if cat != "" and DataSchemas.CATEGORIES.has(cat) and db != null and not db.has(cat, m.get_string(2)):
					printerr("%s:%d: %s(\"%s\"): no such id in %s" % [path, i + 1, m.get_string(1), m.get_string(2), cat])
					failed += 1
	if failed == 0:
		print("Dialogue OK")
	quit(1 if failed > 0 else 0)


## Public function names in an autoload script, read as text (it can't be compiled
## from a --script tool because it uses other autoloads).
func _funcs(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string(r'(?m)^func ([a-z]\w*)\(')
	for m in re.search_all(FileAccess.get_file_as_string(path)):
		out.append(m.get_string(1))
	return out


func _files(dir_path: String) -> PackedStringArray:
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
