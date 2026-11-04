extends GdUnitTestSuite
## Every map in res://game/maps loads, has a spawn and a painted area; Route 1
## has the content the M3 spec lists.


func _maps() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(GameMap.MAPS_DIR):
		if f.ends_with(".tscn") and not f.begins_with("_"):
			out.append(f.get_basename())
	return out


func test_every_map_loads_and_spawns_exist() -> void:
	assert_int(_maps().size()).is_greater_equal(7)
	for id in _maps():
		var m: GameMap = load(GameMap.path_of(id)).instantiate()
		assert_bool(m.pieces().any(func(p): return p is Spawn)).override_failure_message(id).is_true()
		assert_bool(m.bounds().size.x > 0 and m.bounds().size.y > 0).override_failure_message(id).is_true()
		m.free()


func test_route_01_content() -> void:
	var m: GameMap = load(GameMap.path_of("route_01")).instantiate()
	var kinds := {}
	for p in m.pieces():
		var k: String = p.get_script().get_global_name()
		kinds[k] = int(kinds.get(k, 0)) + 1
	assert_int(kinds.get("Tamer", 0)).is_equal(2)
	assert_int(kinds.get("ItemPickup", 0)).is_equal(2)
	assert_int(kinds.get("HiddenItem", 0)).is_equal(1)
	assert_int(kinds.get("EncounterArea", 0)).is_equal(1)
	assert_int(kinds.get("MinigameSpot", 0)).is_equal(1)
	assert_int(kinds.get("Sign", 0)).is_greater_equal(1)
	assert_str(m.default_encounter).is_equal("route_01_grass")
	m.free()
