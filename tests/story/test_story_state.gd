extends GdUnitTestSuite
## StoryState: flags, counters, one-time keys, last heal spot, round trip.


func test_story_round_trip() -> void:
	var s := StoryState.new()
	s.set_flag("got_starter")
	s.add_count("talked_mum", 3)
	s.mark_done("route_01/Potion1")
	s.last_heal = {"map": "town_01_center", "spawn": "heal"}
	var back := StoryState.from_dict(s.to_dict())
	assert_bool(back.flag("got_starter")).is_true()
	assert_bool(back.flag("never_set")).is_false()
	assert_int(back.count("talked_mum")).is_equal(3)
	assert_int(back.count("never")).is_equal(0)
	assert_bool(back.is_done("route_01/Potion1")).is_true()
	assert_bool(back.is_done("route_01/Potion2")).is_false()
	assert_dict(back.last_heal).is_equal({"map": "town_01_center", "spawn": "heal"})


func test_clearing_a_flag() -> void:
	var s := StoryState.new()
	s.set_flag("x")
	s.set_flag("x", false)
	assert_bool(s.flag("x")).is_false()


func test_missing_keys_default() -> void:
	var s := StoryState.from_dict({})
	assert_dict(s.flags).is_empty()
	assert_dict(s.counters).is_empty()
	assert_dict(s.done).is_empty()
	assert_dict(s.last_heal).is_empty()
