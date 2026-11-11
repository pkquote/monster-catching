extends GdUnitTestSuite
## The static set of changed keys the achievement service drains once per frame.


func before_test() -> void:
	AchievementWatch.clear()


func after_test() -> void:
	AchievementWatch.clear()


func test_push_then_drain_returns_the_keys_and_empties() -> void:
	AchievementWatch.push("codex")
	AchievementWatch.push("creature")
	assert_bool(AchievementWatch.is_empty()).is_false()
	var keys := AchievementWatch.drain()
	assert_array(Array(keys)).contains_exactly_in_any_order(["codex", "creature"])
	assert_bool(AchievementWatch.is_empty()).is_true()


func test_pushing_the_same_key_twice_keeps_one() -> void:
	AchievementWatch.push("codex")
	AchievementWatch.push("codex")
	assert_int(AchievementWatch.drain().size()).is_equal(1)


func test_key_helpers() -> void:
	assert_str(AchievementWatch.counter_key("steps")).is_equal("counter:steps")
	assert_str(AchievementWatch.flag_key("a")).is_equal("flag:a")
	assert_str(AchievementWatch.ALL).is_equal("*")
