extends SceneTree
## Headless content validator.
##   godot --headless --path . --script res://tools/validate_data.gd
## Exits 0 when all content is valid, 1 otherwise.


func _init() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	if result.ok():
		var db := result.db
		print("Data OK: %d creatures, %d moves, %d items, %d tamers, %d encounters, %d field states, %d reactions" % [
			db.count("creatures"), db.count("moves"), db.count("items"), db.count("tamers"),
			db.count("encounters"), db.count("field_states"), db.count("reactions")])
		quit(0)
	else:
		for e in result.errors:
			printerr(e)
		printerr("Data validation failed: %d error(s)" % result.errors.size())
		quit(1)
