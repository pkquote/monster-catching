extends SceneTree
## Starts a new species line: writes data/creatures/<name>_line.json with valid placeholders to replace.
##
##   godot --headless --path . --script res://tools/new_species_line.gd -- --name=wisp --types=fire --stages=3
##
## --types is a comma list of one or two type ids (default neutral); --stages is 1 to 3 (default 3).
## Stage ids are <name>_1..<name>_3: rename them and fill in the real stats, moves and description.
## Refuses to overwrite an existing file, and writes nothing when the result would not validate. Reloads the data afterwards and prints any problems.

const OUT_DIR := "res://data/creatures"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var name := ""
	var types: Array = ["neutral"]
	var stages := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			name = a.trim_prefix("--name=")
		elif a.begins_with("--types="):
			types = []
			for t in a.trim_prefix("--types=").split(",", false):
				types.append(t.strip_edges())
		elif a.begins_with("--stages="):
			stages = int(a.trim_prefix("--stages="))
	if name == "":
		printerr("new_species_line: --name=<snake_case> is required")
		return 1
	var errs := PackedStringArray()
	var raw := DataLoader.read_raw("res://data", errs)
	if not errs.is_empty():
		for e in errs:
			printerr(e)
		printerr("new_species_line: fix the existing data first")
		return 1
	var written := SpeciesScaffold.write_line(raw, OUT_DIR, name, types, stages)
	if not written.ok:
		printerr("new_species_line: " + written.error)
		return 1
	var entries: Array = written.doc.entries
	var after := DataLoader.load_database("res://data", "res://dialogue")
	for e in after.errors:
		printerr(e)
	for w in after.warnings:
		print(w)
	print("Wrote %s: dex %d-%d, %d species" % [written.path, entries[0].dex, entries[-1].dex, entries.size()])
	return 0 if after.ok() else 1
