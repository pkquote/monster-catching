extends GdUnitTestSuite
## Every tracked change pushes its watch key, and only when something actually changed.

var db: Database
var save: SaveGame


func before() -> void:
	db = FixtureDB.build()


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)
	AchievementWatch.clear()


func after_test() -> void:
	AchievementWatch.clear()


func _keys() -> Array:
	return Array(AchievementWatch.drain())


func test_counter_add_pushes_its_key() -> void:
	Counters.add(save, "steps")
	assert_array(_keys()).is_equal(["counter:steps"])


func test_a_refused_counter_pushes_nothing() -> void:
	Counters.add(save, "bogus")
	assert_array(_keys()).is_empty()


func test_codex_marks_push_only_on_change() -> void:
	Codex.mark_seen(save, "blob")
	assert_array(_keys()).is_equal(["codex"])
	Codex.mark_seen(save, "blob")
	assert_array(_keys()).is_empty()
	Codex.mark_caught(save, "blob")
	assert_array(_keys()).is_equal(["codex"])
	Codex.mark_caught(save, "blob")
	assert_array(_keys()).is_empty()


func test_story_flags_push_only_on_change() -> void:
	save.story.set_flag("f")
	assert_array(_keys()).is_equal(["flag:f"])
	save.story.set_flag("f")
	assert_array(_keys()).is_empty()
	save.story.set_flag("f", false)
	assert_array(_keys()).is_equal(["flag:f"])
	save.story.set_flag("f", false)
	assert_array(_keys()).is_empty()


func test_bond_change_pushes_creature_only_when_bond_moves() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	Bond.change(db, c, "battle_won")
	assert_array(_keys()).is_equal(["creature"])
	Bond.change(db, c, "no_such_happening")  # delta 0
	assert_array(_keys()).is_empty()
	c.bond = int(db.balance.bond_cfg.max)
	Bond.change(db, c, "battle_won")  # clamped: nothing changed
	assert_array(_keys()).is_empty()


func test_award_xp_pushes_creature_on_a_level_up_only() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	Progression.award_xp(db, c, 1)
	assert_array(_keys()).is_empty()
	Progression.award_xp(db, c, Stats.xp_for_level(6) - c.xp)
	assert_array(_keys()).is_equal(["creature"])


func test_add_to_party_pushes_creature_and_codex() -> void:
	BattleLauncher.add_to_party(db, save, FixtureDB.make(db, "blob", 5))
	assert_array(_keys()).contains_exactly_in_any_order(["creature", "codex"])


func test_record_growth_pushes_creature_codex_and_the_evolved_counter() -> void:
	GrowScreen.record_growth(save, "fish")
	assert_array(_keys()).contains_exactly_in_any_order(["creature", "codex", "counter:creatures_evolved"])
