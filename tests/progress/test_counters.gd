extends GdUnitTestSuite
## Lifetime counters kept in the story store.

var save: SaveGame


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)


func test_built_in_ids_are_the_eight() -> void:
	assert_array(Array(Counters.BUILT_IN)).contains_exactly_in_any_order(["battles_fought", "battles_won",
		"tamers_defeated", "creatures_caught", "creatures_evolved", "items_used", "money_earned", "steps"])


func test_add_and_value() -> void:
	assert_int(Counters.value(save, "steps")).is_equal(0)
	assert_bool(Counters.add(save, "steps")).is_true()
	assert_int(Counters.value(save, "steps")).is_equal(1)
	assert_bool(Counters.add(save, "steps", 3)).is_true()
	assert_int(Counters.value(save, "steps")).is_equal(4)


func test_unknown_id_is_rejected() -> void:
	assert_bool(Counters.add(save, "bogus")).is_false()
	assert_bool(save.story.counters.has("bogus")).is_false()


func test_counters_share_the_story_store() -> void:
	Counters.add(save, "battles_won")
	assert_int(save.story.count("battles_won")).is_equal(1)
