extends GdUnitTestSuite
## GameMap tile helpers, spawns, solidity and piece lookup on the test maps.


func _map(id: String) -> GameMap:
	var m: GameMap = load("res://game/maps/%s.tscn" % id).instantiate()
	add_child(m)
	return m


func test_tile_math() -> void:
	assert_object(GameMap.tile_of(Vector2(47, 70))).is_equal(Vector2i(1, 2))
	assert_object(GameMap.centre_of(Vector2i(1, 2))).is_equal(Vector2(48, 80))
	assert_object(GameMap.tile_of(Vector2(-1, 5))).is_equal(Vector2i(-1, 0))


func test_map_basics() -> void:
	var m := _map("test_a")
	assert_str(m.map_id()).is_equal("test_a")
	assert_object(m.spawn("start")).is_not_null()
	assert_object(m.spawn("nope")).is_null()
	assert_bool(m.is_solid(Vector2i(0, 0))).is_true()   # wall corner
	assert_bool(m.is_solid(Vector2i(2, 2))).is_false()  # floor
	assert_object(m.bounds()).is_equal(Rect2i(0, 0, 8, 6))
	var door := m.piece_at(Vector2i(4, 5))
	assert_object(door).is_instanceof(Door)
	assert_str((door as Door).target_map).is_equal("test_b")
	assert_str(door.save_key()).is_equal("test_a/Door1")
	assert_object(m.spawn("start").tile()).is_equal(Vector2i(2, 2))
	m.free()


func test_encounter_tiles() -> void:
	var m := _map("test_b")
	assert_bool(m.is_encounter_tile(Vector2i(2, 2))).is_true()   # tall grass patch
	assert_bool(m.is_encounter_tile(Vector2i(5, 2))).is_false()
	m.free()
