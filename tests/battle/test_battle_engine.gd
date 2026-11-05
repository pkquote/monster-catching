extends GdUnitTestSuite
## Turn flow, damage, statuses, swaps, faints, XP and determinism.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func _duel(a: String, b: String, moves_a: Array = [], moves_b: Array = [], seed_value := 1) -> BattleEngine:
	return FixtureDB.engine(db, [FixtureDB.make(db, a, 10, moves_a)], [FixtureDB.make(db, b, 10, moves_b)],
		-1, -1, seed_value)


func _bid(e: BattleEngine, side: int, slot := 0) -> int:
	return e.sides[side].active()[slot].bid


func test_start_sends_out_fielded_creatures() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob"), FixtureDB.make(db, "fish"), FixtureDB.make(db, "mole")],
		[FixtureDB.make(db, "blob"), FixtureDB.make(db, "fish")], 2, 2)
	assert_array(e.sides[0].active()).has_size(2)
	assert_array(e.sides[0].bench()).has_size(1)
	assert_array(e.sides[1].active()).has_size(2)


func test_faster_creature_acts_first() -> void:
	var e := _duel("slow", "fast")
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "hit", _bid(e, 1)),
		BattleAction.use_move(_bid(e, 1), "hit", _bid(e, 0))])
	assert_int(FixtureDB.events_of(events, "move_used")[0].bid).is_equal(_bid(e, 1))


func test_priority_beats_speed() -> void:
	var e := _duel("slow", "fast", ["quick_jab"])
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "quick_jab", _bid(e, 1)),
		BattleAction.use_move(_bid(e, 1), "hit", _bid(e, 0))])
	assert_int(FixtureDB.events_of(events, "move_used")[0].bid).is_equal(_bid(e, 0))


func test_type_advantage_and_stab() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "fish")], [FixtureDB.make(db, "flame"), FixtureDB.make(db, "tank")], 2, 2)
	var me := e.battler(_bid(e, 0))
	var vs_fire := BattleAI.estimate_damage(e, me, db.move("splash"), e.battler(_bid(e, 1, 0)), 1)
	var vs_neutral := BattleAI.estimate_damage(e, me, db.move("splash"), e.battler(_bid(e, 1, 1)), 1)
	assert_float(vs_fire).is_greater(vs_neutral * 1.6)


func test_immunity_reports_no_effect() -> void:
	var e := _duel("sparky", "mole")
	var hp := e.battler(_bid(e, 1)).hp()
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "zap", _bid(e, 1))])
	assert_array(FixtureDB.events_of(events, "no_effect")).has_size(1)
	assert_int(e.battler(_bid(e, 1)).hp()).is_equal(hp)


func test_low_accuracy_move_misses() -> void:
	var e := _duel("blob", "tank", ["wild_swing"])
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "wild_swing", _bid(e, 1))])
	assert_array(FixtureDB.events_of(events, "miss")).has_size(1)
	assert_array(FixtureDB.events_of(events, "damage")).is_empty()


func test_quake_hits_everyone_but_user() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "mole", 10, ["quake"]), FixtureDB.make(db, "tank")],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 2, 2)
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "quake")])
	var hit := FixtureDB.events_of(events, "damage").map(func(ev): return ev.bid)
	assert_array(hit).has_size(3)
	assert_bool(hit.has(_bid(e, 0))).is_false()


func test_retargets_when_chosen_target_is_gone() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["hit"])], [FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 1, 2)
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "hit", 999)])
	assert_array(FixtureDB.events_of(events, "damage")).has_size(1)


func test_burn_damages_each_round_then_ends() -> void:
	var e := _duel("blob", "tank", ["burn_touch", "mend"])
	var foe := e.battler(_bid(e, 1))
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "burn_touch", foe.bid)])
	assert_str(foe.status()).is_equal("burn")
	var dmg := FixtureDB.events_of(events, "damage")
	assert_int(dmg[0].amount).is_equal(foe.creature.max_hp(db) / 8)
	events = e.resolve_round([BattleAction.pass_turn(_bid(e, 0))])
	assert_array(FixtureDB.events_of(events, "status_ended")).has_size(1)
	assert_str(foe.status()).is_equal("")


func test_only_one_status_at_a_time() -> void:
	var e := _duel("blob", "tank", ["burn_touch", "jolt"])
	var foe := _bid(e, 1)
	e.resolve_round([BattleAction.use_move(_bid(e, 0), "burn_touch", foe)])
	var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "jolt", foe)])
	var failed := FixtureDB.events_of(events, "status_failed")
	assert_array(failed).has_size(1)
	assert_str(failed[0].has).is_equal("burn")


func test_shock_skips_actions() -> void:
	var e := _duel("fast", "tank", ["jolt"])
	var foe := _bid(e, 1)
	e.resolve_round([BattleAction.use_move(_bid(e, 0), "jolt", foe)])
	var events := e.resolve_round([BattleAction.use_move(foe, "hit", _bid(e, 0))])
	assert_array(FixtureDB.events_of(events, "action_skipped")).has_size(1)


func test_stat_stage_and_trickster_credit() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["growl"])],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 1, 2)
	e.resolve_round([BattleAction.use_move(_bid(e, 0), "growl")])
	for b in e.sides[1].active():
		assert_int(b.stages.patk).is_equal(-1)
	assert_int(e.battler(_bid(e, 0)).creature.affinity.trickster).is_equal(2)


func test_heal_and_warden_credit() -> void:
	var e := _duel("blob", "tank", ["mend"])
	var me := e.battler(_bid(e, 0))
	me.creature.hp = 5
	e.resolve_round([BattleAction.use_move(me.bid, "mend")])
	assert_int(me.hp()).is_equal(5 + me.creature.max_hp(db) / 2)
	assert_int(me.creature.affinity.warden).is_equal(2)


func test_swap_brings_in_bench_and_resets_stages() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob"), FixtureDB.make(db, "fish")], [FixtureDB.make(db, "tank")])
	var first := e.battler(_bid(e, 0))
	first.stages.patk = 2
	var bench_bid: int = e.sides[0].bench()[0].bid
	var events := e.resolve_round([BattleAction.swap(first.bid, bench_bid)])
	assert_int(_bid(e, 0)).is_equal(bench_bid)
	assert_int(first.stages.patk).is_equal(0)
	assert_array(FixtureDB.events_of(events, "swap_out")).has_size(1)


func test_player_faint_asks_for_replacement() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 2), FixtureDB.make(db, "fish", 10)],
		[FixtureDB.make(db, "tank", 30)])
	e.battler(_bid(e, 0)).creature.hp = 1
	var events := e.resolve_round([BattleAction.pass_turn(_bid(e, 0)),
		BattleAction.use_move(_bid(e, 1), "hit", _bid(e, 0))])
	assert_array(FixtureDB.events_of(events, "faint")).has_size(1)
	assert_array(FixtureDB.events_of(events, "replacement_needed")).has_size(1)
	assert_int(e.pending_replacements(0)).is_equal(1)
	e.replace(0, e.sides[0].bench()[0].bid)
	assert_str(e.sides[0].active()[0].creature.species).is_equal("fish")


func test_auto_replace_side_refills_itself() -> void:
	var setup := BattleSetup.new()
	setup.add_side([FixtureDB.make(db, "tank", 30)], 1)
	setup.add_side([FixtureDB.make(db, "blob", 2), FixtureDB.make(db, "fish", 2)], 1, 1, {}, "", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var e := BattleEngine.new(db, rng, setup)
	e.start()
	e.battler(_bid(e, 1)).creature.hp = 1
	e.resolve_round([BattleAction.use_move(_bid(e, 0), "hit", _bid(e, 1))])
	assert_str(e.sides[1].active()[0].creature.species).is_equal("fish")


func test_knockout_awards_xp_and_striker() -> void:
	var e := _duel("blob", "blob", ["hit"])
	var me := e.battler(_bid(e, 0))
	var xp_before := me.creature.xp
	e.battler(_bid(e, 1)).creature.hp = 1
	var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", _bid(e, 1))])
	assert_array(FixtureDB.events_of(events, "xp_gain")).has_size(1)
	assert_int(me.creature.xp).is_greater(xp_before)
	assert_int(me.creature.affinity.striker).is_equal(1 + 3)
	assert_bool(e.is_over()).is_true()
	assert_int(e.result().winner).is_equal(0)


func test_battle_works_on_copies_until_commit() -> void:
	var mine := FixtureDB.make(db, "blob")
	var foe := FixtureDB.make(db, "tank", 10, ["hit"])
	var e := FixtureDB.engine(db, [mine], [foe])
	e.resolve_round([BattleAction.pass_turn(_bid(e, 0)), BattleAction.use_move(_bid(e, 1), "hit", _bid(e, 0))])
	assert_int(e.battler(_bid(e, 0)).hp()).is_less(mine.max_hp(db))
	assert_int(mine.hp).is_equal(mine.max_hp(db))
	assert_int(foe.energy).is_equal(foe.max_energy(db))
	e.commit(0)
	assert_int(mine.hp).is_equal(e.battler(_bid(e, 0)).hp())
	assert_int(foe.energy).is_equal(foe.max_energy(db))  # side 1 was not committed


func test_same_seed_same_battle() -> void:
	var logs := []
	for run in 2:
		var setup := BattleSetup.new()
		setup.add_side([FixtureDB.make(db, "blob", 8), FixtureDB.make(db, "fish", 8)], 2, 2, {}, "tactician")
		setup.add_side([FixtureDB.make(db, "sparky", 8), FixtureDB.make(db, "mole", 8)], 2, 2, {}, "aggressive")
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var e := BattleEngine.new(db, rng, setup)
		var events := e.start()
		while not e.is_over():
			events.append_array(e.resolve_round([]))
		logs.append(JSON.stringify(events))
	assert_str(logs[0]).is_equal(logs[1])


func test_ai_battles_always_finish() -> void:
	for s in 20:
		var setup := BattleSetup.new()
		setup.add_side([FixtureDB.make(db, "blob", 6), FixtureDB.make(db, "fish", 6), FixtureDB.make(db, "sparky", 6)], 3, 3, {}, "basic")
		setup.add_side([FixtureDB.make(db, "mole", 6), FixtureDB.make(db, "flame", 6)], 3, 2, {}, "tactician")
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var e := BattleEngine.new(db, rng, setup)
		e.start()
		while not e.is_over():
			e.resolve_round([])
		assert_bool(e.round_number <= db.balance.round_limit).is_true()


func _tanks(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(FixtureDB.make(db, "tank", 90))
	return out


func test_spread_mult_for_counts() -> void:
	assert_float(db.balance.spread_mult_for(0)).is_equal(1.0)
	assert_float(db.balance.spread_mult_for(1)).is_equal(1.0)
	assert_float(db.balance.spread_mult_for(2)).is_equal_approx(0.85, 0.0001)
	for count in [3, 4, 5]:
		assert_float(db.balance.spread_mult_for(count)).is_equal_approx(0.75, 0.0001)


func test_damage_uses_the_count_table() -> void:
	var e := FixtureDB.engine(db, _tanks(1), _tanks(1))
	var me := e.battler(_bid(e, 0))
	var foe := e.battler(_bid(e, 1))
	var one := BattleAI.estimate_damage(e, me, db.move("hit"), foe, 1)
	var two := BattleAI.estimate_damage(e, me, db.move("hit"), foe, 2)
	var three := BattleAI.estimate_damage(e, me, db.move("hit"), foe, 3)
	assert_float(two).is_equal_approx(one * 0.85, 1.0)
	assert_float(three).is_equal_approx(one * 0.75, 1.0)
	assert_float(two).is_greater(three)


func test_all_enemies_against_two_foes_takes_the_two_target_value() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "fish", 90, ["wave"])], _tanks(2), 1, 2)
	var me := e.battler(_bid(e, 0))
	var single := BattleAI.estimate_damage(e, me, db.move("wave"), e.battler(_bid(e, 1)), 1)
	assert_float(BattleAI.best_damage(e, me)).is_equal(BattleAI.estimate_damage(e, me, db.move("wave"), e.battler(_bid(e, 1)), 2))
	assert_float(BattleAI.best_damage(e, me)).is_equal_approx(single * 0.85, 2.0)


func test_all_enemies_against_three_foes_is_unchanged() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "fish", 90, ["wave"])], _tanks(3), 1, 3)
	var me := e.battler(_bid(e, 0))
	var single := BattleAI.estimate_damage(e, me, db.move("wave"), e.battler(_bid(e, 1)), 1)
	assert_float(BattleAI.best_damage(e, me)).is_equal(BattleAI.estimate_damage(e, me, db.move("wave"), e.battler(_bid(e, 1)), 3))
	assert_float(BattleAI.best_damage(e, me)).is_equal_approx(single * 0.75, 2.0)


func test_all_in_a_3v3_takes_the_three_target_value() -> void:
	# Quake hits five creatures at the three-target value: every hit lies in the roll window of base75.
	var base_party: Array = [FixtureDB.make(db, "mole", 90, ["quake"]), FixtureDB.make(db, "tank", 90), FixtureDB.make(db, "tank", 90)]
	var base_engine := FixtureDB.engine(db, base_party, _tanks(3), 3, 3)
	var single := BattleAI.estimate_damage(base_engine, base_engine.battler(_bid(base_engine, 0)), db.move("quake"),
		base_engine.battler(_bid(base_engine, 1)), 1)
	var base75: float = single / BattleMath.ROLL_AVG * 0.75
	var ceiling: float = base75 + 1.0
	var floor_value: float = base75 * BattleMath.ROLL_MIN / BattleMath.ROLL_MAX - 1.0
	for seed_value in range(1, 11):
		var party0: Array = [FixtureDB.make(db, "mole", 90, ["quake"]), FixtureDB.make(db, "tank", 90), FixtureDB.make(db, "tank", 90)]
		var e := FixtureDB.engine(db, party0, _tanks(3), 3, 3, seed_value)
		var events := e.resolve_round([BattleAction.use_move(_bid(e, 0), "quake")])
		var amounts := FixtureDB.events_of(events, "damage")
		assert_array(amounts).has_size(5)
		for ev in amounts:
			assert_float(float(ev.amount)).is_between(floor_value, ceiling)
