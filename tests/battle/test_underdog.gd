extends GdUnitTestSuite
## Underdog compensation for the outnumbered side.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func test_even_fight_has_no_underdog() -> void:
	var u := Underdog.compute(db.balance, 2, 2)
	assert_int(u.bonus_actions).is_equal(0)
	assert_float(u.stat_bonus).is_equal(0.0)


func test_one_vs_two() -> void:
	var u := Underdog.compute(db.balance, 1, 2)
	assert_int(u.bonus_actions).is_equal(1)
	assert_float(u.stat_bonus).is_equal_approx(0.15, 0.0001)
	assert_float(u.spread_reduction).is_equal_approx(0.2, 0.0001)
	assert_float(u.xp_bonus).is_equal_approx(0.5, 0.0001)


func test_one_vs_three_caps_bonuses() -> void:
	var u := Underdog.compute(db.balance, 1, 3)
	assert_int(u.bonus_actions).is_equal(2)
	assert_float(u.stat_bonus).is_equal_approx(0.3, 0.0001)
	assert_float(u.spread_reduction).is_equal_approx(0.4, 0.0001)
	assert_float(u.xp_bonus).is_equal_approx(1.0, 0.0001)


func test_two_vs_three_gets_stats_but_no_extra_actions() -> void:
	var u := Underdog.compute(db.balance, 2, 3)
	assert_int(u.bonus_actions).is_equal(0)
	assert_float(u.stat_bonus).is_equal_approx(0.075, 0.0001)


func test_bonus_action_rate_scales_extra_actions() -> void:
	var gentle := FixtureDB.build({"underdog": {"bonus_actions_per_ratio": 0.5, "spread_reduction_per_ratio": 0.2,
		"spread_reduction_cap": 0.5, "stat_bonus_per_ratio": 0.15, "stat_bonus_cap": 0.15, "xp_bonus_per_ratio": 0.5}})
	assert_int(Underdog.compute(gentle.balance, 1, 2).bonus_actions).is_equal(0)
	assert_int(Underdog.compute(gentle.balance, 1, 3).bonus_actions).is_equal(1)
	assert_float(Underdog.compute(gentle.balance, 1, 3).stat_bonus).is_equal_approx(0.15, 0.0001)


func test_the_larger_side_gets_nothing() -> void:
	assert_int(Underdog.compute(db.balance, 3, 1).bonus_actions).is_equal(0)


func test_engine_gives_underdog_extra_action_slots() -> void:
	var solo := [FixtureDB.make(db, "tank")]
	var pack := [FixtureDB.make(db, "blob"), FixtureDB.make(db, "blob"), FixtureDB.make(db, "blob")]
	var e := FixtureDB.engine(db, solo, pack, 1, 3)
	var needed := e.actions_needed(0)
	assert_array(needed).has_size(3)
	assert_int(needed[0]).is_equal(needed[2])
	assert_array(e.actions_needed(1)).has_size(3)


func test_underdog_acts_multiple_times_in_a_round() -> void:
	var solo := [FixtureDB.make(db, "tank")]
	var pack := [FixtureDB.make(db, "blob"), FixtureDB.make(db, "blob"), FixtureDB.make(db, "blob")]
	var e := FixtureDB.engine(db, solo, pack, 1, 3)
	var me: int = e.actions_needed(0)[0]
	var foe: int = e.sides[1].active()[0].bid
	var events := e.resolve_round([BattleAction.use_move(me, "hit", foe),
		BattleAction.use_move(me, "hit", foe), BattleAction.use_move(me, "hit", foe)])
	var mine := FixtureDB.events_of(events, "move_used").filter(func(ev): return ev.bid == me)
	assert_array(mine).has_size(3)


func test_extra_actions_beyond_allowance_are_rejected() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob")], [FixtureDB.make(db, "blob")])
	var me := e.sides[0].active()[0].bid
	var events := e.resolve_round([BattleAction.pass_turn(me), BattleAction.pass_turn(me)])
	assert_array(FixtureDB.events_of(events, "action_invalid")).has_size(1)


func test_underdog_stat_bonus_raises_damage() -> void:
	var even := FixtureDB.engine(db, [FixtureDB.make(db, "tank")], [FixtureDB.make(db, "tank")])
	var outnumbered := FixtureDB.engine(db, [FixtureDB.make(db, "tank")],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 1, 3)
	var a := BattleAI.estimate_damage(even, even.sides[0].active()[0], db.move("hit"), even.sides[1].active()[0], false)
	var b := BattleAI.estimate_damage(outnumbered, outnumbered.sides[0].active()[0], db.move("hit"),
		outnumbered.sides[1].active()[0], false)
	assert_float(b).is_greater(a)


func test_underdog_takes_less_spread_damage() -> void:
	var even := FixtureDB.engine(db, [FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 2, 2)
	var under := FixtureDB.engine(db, [FixtureDB.make(db, "tank")],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 1, 2)
	# Enemy side 1 uses a spread move on side 0.
	var wave := db.move("wave")
	var to_even := BattleAI.estimate_damage(even, even.sides[1].active()[0], wave, even.sides[0].active()[0], true)
	var to_under := BattleAI.estimate_damage(under, under.sides[1].active()[0], wave, under.sides[0].active()[0], true)
	# Underdog also gets +Def, so damage drops for two reasons.
	assert_float(to_under).is_less(to_even)
