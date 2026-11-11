extends GdUnitTestSuite
## data/locations.json is what the map scenes give (tools/build_locations.tscn writes it).

const CheckMaps := preload("res://tools/check_maps.gd")


func test_shipped_locations_match_the_map_scenes() -> void:
	var built := Locations.build(CheckMaps.describe_all())
	assert_array(built.entries).is_equal(Locations.file_entries(DataRegistry.db))
	assert_int(built.entries.size()).is_greater(0)


func test_test_maps_are_not_listed() -> void:
	for e in Locations.file_entries(DataRegistry.db):
		assert_bool(e.id.begins_with("test_")).is_false()


func test_a_changed_scene_makes_the_file_stale() -> void:
	var maps := CheckMaps.describe_all()
	maps["route_01"].default_encounter = "route_01_deep_grass"
	maps["route_01"].pieces = []
	var built := Locations.build(maps)
	assert_array(built.entries).is_not_equal(Locations.file_entries(DataRegistry.db))
