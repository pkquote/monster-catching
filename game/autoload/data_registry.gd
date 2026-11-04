extends Node
## Loads all game content once at boot and exposes the Database to scenes.
## Core systems never use this autoload; scenes pass `DataRegistry.db` in.

const DATA_ROOT := "res://data"
const DIALOGUE_ROOT := "res://dialogue"

var db: Database
var errors: PackedStringArray = []


func _ready() -> void:
	var result := DataLoader.load_database(DATA_ROOT, DIALOGUE_ROOT)
	db = result.db
	errors = result.errors
	for e in errors:
		Log.error(Log.DATA, e)
	if not errors.is_empty():
		Log.error(Log.DATA, "Content errors; run tools/validate_data.gd for details", {"count": errors.size()})
		if OS.is_debug_build():
			assert(false, "Content failed validation; see errors above.")


func is_ready() -> bool:
	return db != null
