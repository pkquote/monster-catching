extends GdUnitTestSuite
## Placeholder item icon: size, per-category colour, initial.

const CATEGORIES: Array = ["capture", "heal", "battle", "key", "training", "held"]


func test_configure_sets_minimum_size() -> void:
	var slot: ItemIconSlot = auto_free(ItemIconSlot.new())
	slot.configure("heal", 32)
	assert_vector(slot.custom_minimum_size).is_equal(Vector2(32, 32))
	assert_str(slot.category).is_equal("heal")
	assert_int(slot.icon_size).is_equal(32)


func test_default_size_is_48() -> void:
	var slot: ItemIconSlot = auto_free(ItemIconSlot.new())
	slot.configure("key")
	assert_vector(slot.custom_minimum_size).is_equal(Vector2(48, 48))


func test_every_item_category_has_a_distinct_colour() -> void:
	var schema_values: Array = DataSchemas.ENTRY["items"]["category"]["values"]
	assert_array(schema_values).contains_exactly_in_any_order(CATEGORIES)
	var seen: Array = []
	for cat: String in schema_values:
		assert_bool(ItemIconSlot.CATEGORY_COLORS.has(cat)).override_failure_message("no colour for " + cat).is_true()
		var col: Color = ItemIconSlot.CATEGORY_COLORS[cat]
		assert_bool(seen.has(col)).override_failure_message("duplicate colour for " + cat).is_false()
		seen.append(col)
	assert_bool(ItemIconSlot.CATEGORY_COLORS.has("unknown")).is_true()
	assert_bool(seen.has(ItemIconSlot.CATEGORY_COLORS["unknown"])).is_false()


func test_colours_are_readable_on_panel() -> void:
	for cat: String in ItemIconSlot.CATEGORY_COLORS:
		var col: Color = ItemIconSlot.CATEGORY_COLORS[cat]
		assert_bool(absf(col.get_luminance() - UIKit.PANEL.get_luminance()) > 0.1) \
			.override_failure_message(cat + " too close to the panel").is_true()


func test_unknown_category_uses_fallback() -> void:
	var slot: ItemIconSlot = auto_free(ItemIconSlot.new())
	slot.configure("nonsense")
	assert_object(slot.fill_color()).is_equal(ItemIconSlot.CATEGORY_COLORS["unknown"])
	slot.configure("heal")
	assert_object(slot.fill_color()).is_equal(ItemIconSlot.CATEGORY_COLORS["heal"])


func test_initial_for() -> void:
	assert_str(ItemIconSlot.initial_for("heal")).is_equal("H")
	assert_str(ItemIconSlot.initial_for("capture")).is_equal("C")
	assert_str(ItemIconSlot.initial_for("")).is_equal("?")
	assert_str(ItemIconSlot.initial_for("nonsense")).is_equal("N")
