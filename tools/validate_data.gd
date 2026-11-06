extends SceneTree
## Headless content validator.
##   godot --headless --path . --script res://tools/validate_data.gd
## Validates data/ alone ("Data OK"), then data/ plus the debug test pack ("Data+pack OK") when
## res://data_testpack holds any content. Exits 0 when all content is valid, 1 otherwise.

const PACK_ROOT: String = "res://data_testpack"


func _init() -> void:
	var failed: bool = not _check("Data OK", [])
	if DataLoader.pack_has_entries(PACK_ROOT):
		failed = not _check("Data+pack OK", [PACK_ROOT]) or failed
	quit(1 if failed else 0)


func _check(label: String, packs: Array) -> bool:
	var result := DataLoader.load_database("res://data", "res://dialogue", packs)
	if result.ok():
		for w in result.warnings:
			print(w)
		var db := result.db
		print("%s: %d creatures, %d moves, %d items, %d tamers, %d encounters, %d field states, %d reactions, %d passives" % [
			label, db.count("creatures"), db.count("moves"), db.count("items"), db.count("tamers"),
			db.count("encounters"), db.count("field_states"), db.count("reactions"), db.count("passives")])
		return true
	for e in result.errors:
		printerr(e)
	printerr("Data validation failed (%s): %d error(s)" % [label, result.errors.size()])
	return false
