extends GdUnitTestSuite
## Loads the real shipped content; any validation error fails the build.


func test_shipped_content_is_valid() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert_array(Array(result.errors)).is_empty()
	assert_object(result.db).is_not_null()


func test_shipped_content_builds_typed_defs() -> void:
	var db := DataLoader.load_database("res://data", "res://dialogue").db
	var pup := db.creature("tidepup")
	assert_str(pup.name).is_equal("Tidepup")
	assert_int(pup.base_stats.hp).is_equal(50)
	assert_array(Array(pup.moves_up_to(5))).contains_exactly(["tackle", "splash_jab", "drench"])
	assert_int(pup.growth.size()).is_equal(3)

	var riptide := db.move("riptide")
	assert_int(riptide.power).is_equal(55)
	assert_str(riptide.effects[0].op).is_equal("bonus_if_field")


func test_merges_multiple_files_per_folder() -> void:
	var db := DataLoader.load_database("res://data").db
	# Moves come from three files, creatures from two.
	assert_bool(db.has("moves", "riptide")).is_true()
	assert_bool(db.has("moves", "flare_burst")).is_true()
	assert_bool(db.has("moves", "tackle")).is_true()
	assert_bool(db.has("creatures", "tidepup")).is_true()
	assert_bool(db.has("creatures", "pebblet")).is_true()


func test_type_multiplier_combines_dual_types() -> void:
	var db := DataLoader.load_database("res://data").db
	# Water vs Water/Earth: 0.5 * 2.0
	assert_float(db.type_multiplier("water", PackedStringArray(["water", "earth"]))).is_equal(1.0)
	assert_float(db.type_multiplier("electric", PackedStringArray(["earth"]))).is_equal(0.0)


func test_find_reaction_is_order_independent() -> void:
	var db := DataLoader.load_database("res://data").db
	assert_str(db.find_reaction("soaked", "charged").id).is_equal("conduction")
	assert_str(db.find_reaction("charged", "soaked").id).is_equal("conduction")
	assert_object(db.find_reaction("soaked", "overgrown")).is_null()


func test_encounter_roll_is_deterministic_with_seed() -> void:
	var enc := DataLoader.load_database("res://data").db.encounter("route_01_grass")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	for i in 20:
		assert_str(enc.roll(a).species).is_equal(enc.roll(b).species)


func test_reports_json_parse_errors_with_path() -> void:
	var dir := create_temp_dir("bad_json")
	_write(dir.path_join("types.json"), "{ \"schema\": 1, \"entries\": [ ")
	var errors := PackedStringArray()
	DataLoader.read_raw(dir, errors)
	assert_bool(errors.size() > 0).is_true()
	assert_str(" ".join(errors)).contains("types.json").contains("JSON parse error")


func test_rejects_wrong_schema_version() -> void:
	var dir := create_temp_dir("bad_schema")
	_write(dir.path_join("types.json"), "{ \"schema\": 99, \"entries\": [] }")
	var errors := PackedStringArray()
	DataLoader.read_raw(dir, errors)
	assert_str(" ".join(errors)).contains("unsupported schema")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_shipped_content_has_no_warnings() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert_array(Array(result.warnings)).is_empty()
