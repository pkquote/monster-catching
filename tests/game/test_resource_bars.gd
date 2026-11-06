extends GdUnitTestSuite
## HP and Stamina bars: fill, colours, labels.


func test_fill_fraction_at_zero_half_full_and_over() -> void:
	assert_float(ResourceBars.fill_fraction(0, 40)).is_equal(0.0)
	assert_float(ResourceBars.fill_fraction(20, 40)).is_equal(0.5)
	assert_float(ResourceBars.fill_fraction(40, 40)).is_equal(1.0)
	assert_float(ResourceBars.fill_fraction(99, 40)).is_equal(1.0)
	assert_float(ResourceBars.fill_fraction(-5, 40)).is_equal(0.0)


func test_fill_fraction_with_zero_maximum_is_zero() -> void:
	assert_float(ResourceBars.fill_fraction(0, 0)).is_equal(0.0)
	assert_float(ResourceBars.fill_fraction(5, 0)).is_equal(0.0)


func test_hp_colour_thresholds() -> void:
	assert_object(ResourceBars.hp_color(0.6)).is_equal(Color("6cc96a"))
	assert_object(ResourceBars.hp_color(0.3)).is_equal(Color("e8c04a"))
	assert_object(ResourceBars.hp_color(0.1)).is_equal(Color("e2675c"))


func test_label_text() -> void:
	assert_str(ResourceBars.label(12, 30)).is_equal("12 / 30")


func test_creature_view_uses_the_same_colour() -> void:
	for ratio: float in [0.9, 0.4, 0.05]:
		assert_object(CreatureView._hp_color(ratio)).is_equal(ResourceBars.hp_color(ratio))


func test_draws_at_zero_and_full_without_error() -> void:
	var b: ResourceBars = ResourceBars.new()
	add_child(auto_free(b))
	b.configure(0, 0, 0, 0)
	await get_tree().process_frame
	b.configure(30, 30, 25, 25)
	await get_tree().process_frame
	b.configure(0, 30, 0, 25)
	await get_tree().process_frame
	assert_float(b.custom_minimum_size.x).is_equal(180.0)
