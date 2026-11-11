extends GdUnitTestSuite
## Unlock times in the save: round trip, the schema 7 -> 8 migration, tolerance of junk.


func _save() -> SaveGame:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	return SaveGame.new_game("Ana", 1000, rng)


func test_round_trip() -> void:
	var s := _save()
	s.achievements = {"first_steps": 1700000000, "first_catch": 1700000100}
	var back := SaveGame.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_dict(back.achievements).is_equal({"first_steps": 1700000000, "first_catch": 1700000100})


func test_schema_is_eight_and_v7_migrates_with_an_empty_record() -> void:
	assert_int(SaveGame.SCHEMA).is_equal(8)
	var d := _save().to_dict()
	d.erase("achievements")
	d["schema"] = 7
	var out: Dictionary = SaveStore._v7_to_v8(d)
	assert_int(out.schema).is_equal(8)
	assert_dict(out.achievements).is_empty()
	assert_dict(SaveGame.from_dict(out).achievements).is_empty()


func test_junk_values_load_without_error() -> void:
	var d := _save().to_dict()
	d["achievements"] = {"ok": 5, "text": "soon", "nothing": null, "list": [1], "float": 7.0}
	var s := SaveGame.from_dict(d)
	assert_dict(s.achievements).is_equal({"ok": 5, "float": 7})
	d["achievements"] = "not a dictionary"
	assert_dict(SaveGame.from_dict(d).achievements).is_empty()
