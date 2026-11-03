class_name RawData
extends RefCounted
## Untyped JSON content as read from disk, before validation.
## Tests build these directly to exercise the validator without files.

## category -> Array of { "entry": Dictionary, "file": String }
var entries: Dictionary = {}
## category -> { "data": Dictionary, "file": String } (for "single" categories)
var singles: Dictionary = {}
## path -> file text, for dialogue reference checks
var dialogue_files: Dictionary = {}


func add_entry(category: String, entry: Dictionary, file: String = "<memory>") -> void:
	if not entries.has(category):
		entries[category] = []
	entries[category].append({"entry": entry, "file": file})


func set_single(category: String, data: Dictionary, file: String = "<memory>") -> void:
	singles[category] = {"data": data, "file": file}


func get_entries(category: String) -> Array:
	return entries.get(category, [])


func ids(category: String) -> Dictionary:
	var out := {}
	for rec in get_entries(category):
		var id = rec.entry.get("id")
		if id is String:
			out[id] = true
	return out
