extends Control
## Temporary boot screen for M0: shows what content loaded.

@onready var _label: Label = $Label


func _ready() -> void:
	if not DataRegistry.is_ready():
		_label.text = "Content errors:\n" + "\n".join(DataRegistry.errors)
		return
	var db := DataRegistry.db
	_label.text = "Monster Catching Game (M0)\n\n%d creatures · %d moves · %d items\n%d field states · %d reactions" % [
		db.count("creatures"), db.count("moves"), db.count("items"),
		db.count("field_states"), db.count("reactions")]
