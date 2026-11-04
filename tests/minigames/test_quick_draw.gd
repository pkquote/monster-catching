extends GdUnitTestSuite
## Quick Draw: press Accept right after the "!" appears. 3 of 5 rounds wins.


func _game() -> QuickDraw:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return QuickDraw.new(rng, 0.45, 5)


func test_round_outcomes() -> void:
	var q := _game()
	assert_str(q.press(-0.1)).is_equal("early")
	assert_str(q.press(0.3)).is_equal("win")
	assert_str(q.press(0.5)).is_equal("slow")
	assert_int(q.wins).is_equal(1)
	assert_int(q.round).is_equal(3)


func test_three_of_five_wins() -> void:
	var q := _game()
	for t in [0.2, 0.2, 0.9, 0.2, -1.0]:
		assert_bool(q.is_over()).is_false()
		q.press(t)
	assert_bool(q.is_over()).is_true()
	assert_dict(q.result()).is_equal({"won": true, "score": 3})


func test_two_of_five_loses() -> void:
	var q := _game()
	for t in [0.2, 0.2, 0.9, 0.9, 0.9]:
		q.press(t)
	assert_bool(q.result().won).is_false()


func test_delays_are_one_to_three_seconds() -> void:
	var q := _game()
	for i in 50:
		assert_float(q.next_delay()).is_between(1.0, 3.0)


func test_presses_after_the_end_are_ignored() -> void:
	var q := _game()
	for i in 5:
		q.press(0.1)
	assert_str(q.press(0.1)).is_equal("over")
	assert_int(q.wins).is_equal(5)
