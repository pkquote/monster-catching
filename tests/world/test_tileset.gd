extends GdUnitTestSuite
## The generated placeholder tileset: collision on solid tiles, encounter data on tall grass.

const TILESET := "res://game/maps/tiles/placeholder_tileset.tres"


func _data(ts: TileSet, coord: Vector2i) -> TileData:
	var src := ts.get_source(TileIds.SOURCE) as TileSetAtlasSource
	return src.get_tile_data(coord, 0)


func test_tileset_has_collision_and_encounter_data() -> void:
	assert_bool(ResourceLoader.exists(TILESET)).is_true()
	var ts: TileSet = load(TILESET)
	assert_int(ts.get_custom_data_layer_by_name("encounter")).is_greater_equal(0)
	var src := ts.get_source(TileIds.SOURCE) as TileSetAtlasSource
	assert_object(src.texture_region_size).is_equal(Vector2i(32, 32))
	assert_bool(_data(ts, TileIds.TALL_GRASS).get_custom_data("encounter")).is_true()
	assert_bool(_data(ts, TileIds.GRASS).get_custom_data("encounter")).is_false()
	for coord in TileIds.SOLID:
		assert_int(_data(ts, coord).get_collision_polygons_count(0)).override_failure_message(str(coord)).is_equal(1)
	assert_int(_data(ts, TileIds.GRASS).get_collision_polygons_count(0)).is_equal(0)
	assert_int(_data(ts, TileIds.TALL_GRASS).get_collision_polygons_count(0)).is_equal(0)
