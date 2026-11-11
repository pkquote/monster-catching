extends GdUnitTestSuite
## The pure evaluator over the shipped achievements.

var db: Database
var save: SaveGame


func before() -> void:
	db = DataLoader.load_database("res://data").db


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)
	save.party.clear()
	save.storage.fill(null)


func after_test() -> void:
	db._tables["achievements"].erase("tp_ach")


func test_listed_is_in_file_order_and_leaves_out_test_content() -> void:
	var def := AchievementDef.from_dict({"id": "tp_ach", "name": "T", "description": "t",
		"criterion": {"kind": "flag", "flag": "x"}})
	db._tables["achievements"]["tp_ach"] = def
	var listed := Achievements.listed(db)
	assert_str(listed[0]).is_equal("first_steps")
	assert_bool(listed.has("tp_ach")).is_false()
	assert_int(listed.size()).is_equal(db.count("achievements") - 1)


func test_evaluate_takes_only_the_achievements_watching_the_keys() -> void:
	save.story.counters["steps"] = 500
	save.story.counters["battles_won"] = 1  # also met, but not watching the pushed key
	var met := Achievements.evaluate(db, save, PackedStringArray(["counter:steps"]))
	assert_array(Array(met)).is_equal(["first_steps"])


func test_empty_keys_and_all_check_everything() -> void:
	save.story.counters["steps"] = 500
	save.story.counters["battles_won"] = 1
	assert_array(Array(Achievements.evaluate(db, save, PackedStringArray()))).contains_exactly_in_any_order(
		["first_steps", "first_victory"])
	assert_array(Array(Achievements.evaluate(db, save, PackedStringArray([AchievementWatch.ALL])))) \
		.contains_exactly_in_any_order(["first_steps", "first_victory"])


func test_an_unlocked_id_is_never_returned_again() -> void:
	save.story.counters["steps"] = 500
	Achievements.unlock(save, "first_steps", 1234)
	assert_bool(Achievements.is_unlocked(save, "first_steps")).is_true()
	assert_array(Array(Achievements.evaluate(db, save, PackedStringArray([AchievementWatch.ALL])))).is_empty()


func test_unlock_count_counts_listed_ids_only() -> void:
	Achievements.unlock(save, "first_steps", 1)
	Achievements.unlock(save, "removed_achievement", 1)  # the data no longer has it
	db._tables["achievements"]["tp_ach"] = AchievementDef.from_dict({"id": "tp_ach", "name": "T",
		"description": "t", "criterion": {"kind": "flag", "flag": "x"}})
	Achievements.unlock(save, "tp_ach", 1)
	assert_int(Achievements.unlock_count(db, save)).is_equal(1)


func test_unlock_and_reset() -> void:
	Achievements.unlock(save, "first_steps", 10)
	Achievements.unlock(save, "first_catch", 20)
	assert_int(int(save.achievements.first_steps)).is_equal(10)
	Achievements.reset(save, "first_steps")
	assert_bool(Achievements.is_unlocked(save, "first_steps")).is_false()
	assert_bool(Achievements.is_unlocked(save, "first_catch")).is_true()
	Achievements.reset(save)
	assert_dict(save.achievements).is_empty()


func test_progress_and_is_met() -> void:
	save.story.counters["steps"] = 120
	assert_dict(Achievements.progress(db, save, "first_steps")).is_equal({"current": 120, "target": 500})
	assert_bool(Achievements.is_met(db, save, "first_steps")).is_false()
	save.story.counters["steps"] = 500
	assert_bool(Achievements.is_met(db, save, "first_steps")).is_true()


func test_watch_index() -> void:
	var index := Achievements.watch_index(db)
	assert_array(Array(index["counter:steps"])).is_equal(["first_steps"])
	assert_array(Array(index["codex"])).contains_exactly_in_any_order(["field_notes", "collector"])
	assert_array(Array(index["flag:quick_draw_won"])).is_equal(["quick_on_the_draw"])
	assert_bool(Array(index["creature"]).has("rising_star")).is_true()
	assert_bool(Array(index["counter:creatures_evolved"]).has("first_evolution")).is_true()
