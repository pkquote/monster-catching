extends SceneTree
## Compiles every .dialogue file with Dialogue Manager and prints errors.
##   godot --headless --path . --script res://tools/check_dialogue.gd
## Exits 0 when all files compile, 1 otherwise.

const ROOT := "res://dialogue"


func _init() -> void:
	var failed := 0
	for path in _files(ROOT):
		var result: DMCompilerResult = DMCompiler.compile_string(FileAccess.get_file_as_string(path), path)
		for e in result.errors:
			printerr("%s:%d:%d: %s" % [path, e.line_number + 1, e.column_number, DMConstants.get_error_message(e.error)])
			failed += 1
	if failed == 0:
		print("Dialogue OK")
	quit(1 if failed > 0 else 0)


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
