extends GdUnitTestSuite
## BattleSummary and ProgressEntry: the typed results a battle hands to the overworld.


func test_of_builds_a_summary() -> void:
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 5)
	var entry := ProgressEntry.new(c, ["riptide"], true)
	var s := BattleSummary.of(BattleSummary.WON, [entry], "scout_ana")
	assert_str(s.outcome).is_equal("won")
	assert_str(s.tamer_id).is_equal("scout_ana")
	assert_int(s.progress.size()).is_equal(1)
	assert_object(s.progress[0].creature).is_same(c)
	assert_array(s.progress[0].offered_moves).is_equal(["riptide"])
	assert_bool(s.progress[0].growth_due).is_true()
	assert_int(s.money).is_equal(0)
	assert_array(s.captured).is_empty()


func test_is_win() -> void:
	assert_bool(BattleSummary.of(BattleSummary.WON).is_win()).is_true()
	assert_bool(BattleSummary.of(BattleSummary.CAPTURED).is_win()).is_true()
	for outcome in [BattleSummary.LOST, BattleSummary.FLED, BattleSummary.DRAW]:
		assert_bool(BattleSummary.of(outcome).is_win()).is_false()


func test_progress_entry_is_null_without_a_level_gain() -> void:
	var db := DataRegistry.db
	var c := CreatureInstance.create(db, "tidepup", 15)
	assert_object(Progression.progress_entry(db, c, 15)).is_null()
	Progression.award_xp(db, c, Stats.xp_for_level(16) - c.xp)
	var e := Progression.progress_entry(db, c, 15)
	assert_bool(e is ProgressEntry).is_true()
