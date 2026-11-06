extends GdUnitTestSuite
## Placeholder creature sprite: colours from the types, initial, size.


func test_body_color_is_the_first_types_colour() -> void:
	assert_object(CreatureSpriteSlot.body_color(PackedStringArray(["water"]))).is_equal(TypeColors.type_color("water"))
	assert_object(CreatureSpriteSlot.body_color(PackedStringArray(["fire", "water"]))).is_equal(TypeColors.type_color("fire"))


func test_no_types_falls_back_to_grey() -> void:
	assert_object(CreatureSpriteSlot.body_color(PackedStringArray())).is_equal(Color("9aa0ae"))


func test_ring_color_only_for_two_types() -> void:
	assert_float(CreatureSpriteSlot.ring_color(PackedStringArray(["water"])).a).is_equal(0.0)
	assert_float(CreatureSpriteSlot.ring_color(PackedStringArray()).a).is_equal(0.0)
	assert_object(CreatureSpriteSlot.ring_color(PackedStringArray(["water", "earth"]))).is_equal(TypeColors.type_color("earth"))


func test_initial_for() -> void:
	assert_str(CreatureSpriteSlot.initial_for("Tidepup")).is_equal("T")
	assert_str(CreatureSpriteSlot.initial_for("")).is_equal("?")


func test_configure_sets_the_minimum_size() -> void:
	var slot: CreatureSpriteSlot = auto_free(CreatureSpriteSlot.new())
	slot.configure(DataRegistry.db, "tidepup", 48)
	assert_vector(slot.custom_minimum_size).is_equal(Vector2(48, 48))


func test_draws_for_a_real_species_without_error() -> void:
	var slot: CreatureSpriteSlot = CreatureSpriteSlot.new()
	add_child(auto_free(slot))
	slot.configure(DataRegistry.db, "torrentusk", 56)
	await get_tree().process_frame
	assert_object(slot).is_not_null()
