extends GdUnitTestSuite
## The service: drains watch keys once per frame, checks only what watches them, unlocks once.

var save: SaveGame
var _emitted: Array = []
var _listener := func(id: String) -> void: _emitted.append(id)


func before_test() -> void:
	_emitted = []
	AchievementWatch.clear()
	save = _new_save()
	GameState.current = save
	AchievementService.flush()  # the load pass for this game
	AchievementService.unlocked.connect(_listener)


func after_test() -> void:
	AchievementService.unlocked.disconnect(_listener)
	GameState.current = null
	AchievementService.flush()
	AchievementWatch.clear()


func _new_save() -> SaveGame:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var s := SaveGame.new_game("Ana", 1000, rng)
	s.party.clear()
	s.storage.fill(null)
	return s


func test_a_counter_bump_unlocks_and_emits_once() -> void:
	Counters.add(save, "battles_won")
	var got := AchievementService.flush()
	assert_array(Array(got)).is_equal(["first_victory"])
	assert_bool(save.achievements.has("first_victory")).is_true()
	assert_int(int(save.achievements.first_victory)).is_greater(0)
	assert_array(_emitted).is_equal(["first_victory"])


func test_pushing_again_never_emits_again() -> void:
	Counters.add(save, "battles_won")
	AchievementService.flush()
	Counters.add(save, "battles_won")
	AchievementWatch.push(AchievementWatch.ALL)
	AchievementService.flush()
	assert_array(_emitted).is_equal(["first_victory"])


func test_many_keys_in_one_frame_still_emit_once() -> void:
	Counters.add(save, "steps", 600)
	AchievementWatch.push("counter:steps")
	AchievementWatch.push("counter:steps")
	AchievementWatch.push(AchievementWatch.ALL)
	AchievementService.flush()
	assert_array(_emitted).is_equal(["first_steps"])


func test_an_idle_frame_checks_nothing() -> void:
	var before := AchievementService.checks
	AchievementService.flush()
	assert_int(AchievementService.checks).is_equal(before)


func test_one_step_checks_only_what_watches_steps() -> void:
	var before := AchievementService.checks
	Counters.add(save, "steps")
	AchievementService.flush()
	assert_int(AchievementService.checks).is_equal(before + 1)  # first_steps, not the other ten
	assert_array(_emitted).is_empty()


func test_an_unlocked_achievement_is_not_checked_again() -> void:
	Counters.add(save, "steps", 500)
	AchievementService.flush()
	var before := AchievementService.checks
	Counters.add(save, "steps")
	AchievementService.flush()
	assert_int(AchievementService.checks).is_equal(before)


func test_the_load_pass_catches_up_an_old_save() -> void:
	var old := _new_save()
	old.story.counters["battles_won"] = 5  # earned before achievements existed: nothing was pushed
	GameState.current = old
	AchievementService.flush()
	assert_bool(old.achievements.has("first_victory")).is_true()
	assert_array(_emitted).is_equal(["first_victory"])


func test_with_no_game_keys_are_dropped_quietly() -> void:
	GameState.current = null
	Counters.add(save, "battles_won")
	assert_array(Array(AchievementService.flush())).is_empty()
	assert_bool(AchievementWatch.is_empty()).is_true()
	assert_bool(AchievementService.unlock("first_victory")).is_false()


func test_unlock_twice_and_unknown_id() -> void:
	assert_bool(AchievementService.unlock("first_catch")).is_true()
	assert_bool(AchievementService.unlock("first_catch")).is_false()
	assert_bool(AchievementService.unlock("no_such_achievement")).is_false()
	assert_array(_emitted).is_equal(["first_catch"])


func test_a_reset_achievement_is_earned_once_more() -> void:
	Counters.add(save, "battles_won")
	AchievementService.flush()
	Achievements.reset(save, "first_victory")
	AchievementWatch.push(AchievementWatch.ALL)
	AchievementService.flush()
	assert_array(_emitted).is_equal(["first_victory", "first_victory"])
	assert_bool(save.achievements.has("first_victory")).is_true()
