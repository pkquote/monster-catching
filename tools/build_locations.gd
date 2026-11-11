extends Node
## Writes data/locations.json from the map scenes: each map's default encounter table and every
## encounter area's (see Locations.build). Run it after changing a map's encounters;
## tools/check_maps.gd fails while the file is out of date.
##
##   godot --headless --path . res://tools/build_locations.tscn
##
## Runs as a scene so piece scripts (which use autoloads) load with their settings.

const CheckMaps := preload("res://tools/check_maps.gd")
const OUT := "res://data/locations.json"


func _ready() -> void:
	var doc := Locations.build(CheckMaps.describe_all())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		printerr("Can't write ", OUT)
		get_tree().quit(1)
		return
	f.store_string(to_json(doc))
	f.close()
	print("Wrote ", OUT)
	get_tree().quit(0)


## The file text: one entry per line, like the other data files.
static func to_json(doc: Dictionary) -> String:
	var lines := PackedStringArray()
	for e: Dictionary in doc.entries:
		lines.append("\t" + JSON.stringify(e))
	return '{\n  "schema": %d,\n  "entries": [\n%s\n  ]\n}\n' % [doc.schema, ",\n".join(lines)]
