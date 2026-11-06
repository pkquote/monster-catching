extends Node
## Loads all game content once at boot and exposes the Database to scenes.
## Core systems never use this autoload; scenes pass `DataRegistry.db` in.

const DATA_ROOT := "res://data"
const DIALOGUE_ROOT := "res://dialogue"
## Debug-only test content pack; absent in release builds and fresh clones.
const PACK_ROOT: String = "res://data_testpack"

var db: Database
var errors: PackedStringArray = []


func _ready() -> void:
	var packs: Array = []
	if OS.is_debug_build() and DirAccess.dir_exists_absolute(PACK_ROOT):
		packs.append(PACK_ROOT)
	var result := load_with_fallback(DATA_ROOT, DIALOGUE_ROOT, packs)
	db = result.db
	errors = result.errors
	for e in errors:
		Log.error(Log.DATA, e)
	if not errors.is_empty():
		Log.error(Log.DATA, "Content errors; run tools/validate_data.gd for details", {"count": errors.size()})
		if OS.is_debug_build():
			assert(false, "Content failed validation; see errors above.")


## Loads `data_root` plus `packs`. If that fails and there are packs, the errors are logged
## (Log.DATA, error level) and `data_root` is loaded alone, so a broken test pack can't stop a
## debug session. If `data_root` alone fails too, that result (with its errors) is returned.
static func load_with_fallback(data_root: String, dialogue_root: String, packs: Array) -> DataLoader.LoadResult:
	var result: DataLoader.LoadResult = DataLoader.load_database(data_root, dialogue_root, packs)
	if result.ok() or packs.is_empty():
		return result
	for e: String in result.errors:
		Log.error(Log.DATA, "With test pack: " + e)
	Log.error(Log.DATA, "Content plus test pack failed validation; loading data without the pack",
		{"count": result.errors.size(), "packs": packs})
	return DataLoader.load_database(data_root, dialogue_root)


func is_ready() -> bool:
	return db != null
