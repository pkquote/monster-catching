extends GdUnitTestSuite
## Stats, XP, levelling, Affinity and growth.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func test_stat_formulas() -> void:
	assert_int(Stats.hp_at(50, 10)).is_equal(30)
	assert_int(Stats.stat_at(50, 10)).is_equal(15)
	assert_int(Stats.hp_at(50, 1)).is_equal(12)


func test_xp_curve() -> void:
	assert_int(Stats.xp_for_level(1)).is_equal(0)
	assert_int(Stats.xp_for_level(2)).is_equal(8)
	assert_int(Stats.xp_for_level(10)).is_equal(1000)


func test_stage_multipliers() -> void:
	assert_float(Stats.stage_mult("patk", 0)).is_equal(1.0)
	assert_float(Stats.stage_mult("patk", 2)).is_equal(2.0)
	assert_float(Stats.stage_mult("patk", -2)).is_equal(0.5)
	assert_float(Stats.stage_mult("acc", -1)).is_equal_approx(0.75, 0.001)


func test_create_takes_latest_moves_up_to_cap() -> void:
	var c := FixtureDB.make(db, "blob", 8)
	# Learnset by Lv 8: hit, growl, mend, quick_jab, wave -> keep the last 4.
	assert_array(Array(c.moves)).contains_exactly(["growl", "mend", "quick_jab", "wave"])
	assert_int(c.hp).is_equal(c.max_hp(db))
	assert_int(c.xp).is_equal(Stats.xp_for_level(8))


func test_award_xp_levels_up_and_learns_moves() -> void:
	var c := FixtureDB.make(db, "blob", 2)  # knows: hit
	var events := Progression.award_xp(db, c, Stats.xp_for_level(5) - c.xp, 7)
	assert_int(c.level).is_equal(5)
	assert_array(FixtureDB.events_of(events, "level_up")).has_size(3)
	assert_array(Array(c.moves)).contains_exactly(["hit", "growl", "mend"])
	assert_int(FixtureDB.events_of(events, "move_learned")[0].bid).is_equal(7)


func test_full_moveset_offers_instead_of_learning() -> void:
	var c := FixtureDB.make(db, "blob", 5, ["hit", "growl", "mend", "splash"])
	var events := Progression.award_xp(db, c, Stats.xp_for_level(6) - c.xp)
	assert_array(FixtureDB.events_of(events, "move_offered")).has_size(1)
	assert_bool(c.moves.has("quick_jab")).is_false()


func test_level_up_keeps_damage_taken() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	c.hp -= 5
	var missing := c.max_hp(db) - c.hp
	Progression.award_xp(db, c, Stats.xp_for_level(6) - c.xp)
	assert_int(c.max_hp(db) - c.hp).is_equal(missing)


func test_affinity_awards_and_dominant() -> void:
	var c := FixtureDB.make(db, "blob", 3)
	assert_str(Progression.dominant_affinity(db, c)).is_equal("")
	Progression.award_affinity(db, c, "reaction_triggered")  # catalyst +4
	Progression.award_affinity(db, c, "hit_dealt", 3)  # striker +3
	assert_int(c.affinity.catalyst).is_equal(4)
	assert_int(c.affinity.striker).is_equal(3)
	assert_str(Progression.dominant_affinity(db, c)).is_equal("catalyst")


func test_growth_not_due_before_level() -> void:
	var c := FixtureDB.make(db, "blob", 4)
	c.affinity.striker = 50
	assert_str(Progression.growth_target(db, c)).is_equal("")


func test_growth_follows_dominant_affinity() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	c.affinity.striker = 12
	assert_str(Progression.growth_target(db, c)).is_equal("fish")
	c.affinity.catalyst = 20
	assert_str(Progression.growth_target(db, c)).is_equal("sparky")


func test_growth_falls_back_to_default_below_threshold() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	c.affinity.striker = 9  # threshold is 10
	assert_str(Progression.growth_target(db, c)).is_equal("mole")


func test_growth_with_unmatched_affinity_uses_default() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	c.affinity.warden = 50  # no warden branch
	assert_str(Progression.growth_target(db, c)).is_equal("mole")


func test_apply_growth_keeps_hp_ratio_and_moves() -> void:
	var c := FixtureDB.make(db, "blob", 5)
	c.hp = c.max_hp(db) / 2
	var ev := Progression.apply_growth(db, c, "fish")
	assert_str(c.species).is_equal("fish")
	assert_str(ev.from).is_equal("blob")
	assert_array(Array(c.moves)).contains(["hit"])
	assert_int(c.hp).is_between(c.max_hp(db) / 2 - 1, c.max_hp(db) / 2 + 1)


func test_instance_round_trips_through_dict() -> void:
	var c := FixtureDB.make(db, "blob", 6)
	c.nickname = "Bob"
	c.status = "burn"
	c.affinity.warden = 7
	var copy := CreatureInstance.from_dict(c.to_dict())
	assert_dict(copy.to_dict()).is_equal(c.to_dict())
