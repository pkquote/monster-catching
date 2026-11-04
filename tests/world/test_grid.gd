extends GdUnitTestSuite
## Tamer sight lines on the tile grid.


func _walls(tiles: Array) -> Callable:
	return func(t: Vector2i) -> bool: return tiles.has(t)


func test_sight_stops_before_a_wall() -> void:
	var seen := Grid.sight_tiles(Vector2i(0, 0), Vector2i.RIGHT, 4, _walls([Vector2i(3, 0)]))
	assert_array(seen).is_equal([Vector2i(1, 0), Vector2i(2, 0)])


func test_sight_in_all_four_facings() -> void:
	var open := _walls([])
	assert_array(Grid.sight_tiles(Vector2i(5, 5), Vector2i.UP, 2, open)).is_equal([Vector2i(5, 4), Vector2i(5, 3)])
	assert_array(Grid.sight_tiles(Vector2i(5, 5), Vector2i.DOWN, 2, open)).is_equal([Vector2i(5, 6), Vector2i(5, 7)])
	assert_array(Grid.sight_tiles(Vector2i(5, 5), Vector2i.LEFT, 2, open)).is_equal([Vector2i(4, 5), Vector2i(3, 5)])
	assert_array(Grid.sight_tiles(Vector2i(5, 5), Vector2i.RIGHT, 2, open)).is_equal([Vector2i(6, 5), Vector2i(7, 5)])


func test_zero_length_sees_nothing() -> void:
	assert_array(Grid.sight_tiles(Vector2i(0, 0), Vector2i.RIGHT, 0, _walls([]))).is_empty()
