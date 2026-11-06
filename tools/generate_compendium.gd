extends SceneTree
## Generates documentation/compendium.md, a readable reference of all game content,
## straight from the JSON data so it never drifts out of date.
##   godot --headless --path . --script res://tools/generate_compendium.gd
## Exits 1 if the content fails validation. The text itself comes from CompendiumBuilder.

const OUT_PATH := "res://documentation/compendium.md"


func _init() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	if not result.ok():
		for e in result.errors:
			printerr(e)
		printerr("Content is invalid; compendium not generated.")
		quit(1)
		return
	var text: String = CompendiumBuilder.build(result.db)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("Cannot write %s (error %d)." % [OUT_PATH, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("Wrote %s (%d lines)" % [OUT_PATH, text.count("\n")])
	quit(0)
