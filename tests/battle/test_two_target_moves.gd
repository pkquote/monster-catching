extends GdUnitTestSuite
## Moves aimed at two chosen foes (`two_enemies`): picking, replacement and the spread penalty.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB._m("twin_strike", "neutral", "physical", 50, 100, "two_enemies",
		[{"op": "damage"}]))
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _mk(species := "blob", moves: Array = ["hit"]) -> CreatureInstance:
	return FixtureDB.make(db, species, 10, moves)


## One attacker with twin_strike against `foes` tanks (all fielded unless `bench` > 0).
func _versus(foes: int, bench := 0, allies := 1, seed_value := 1) -> BattleEngine:
	var mine: Array = [_mk("blob", ["twin_strike", "hit"])]
	for i in allies - 1:
		mine.append(_mk("blob"))
	var theirs: Array = []
	for i in foes + bench:
		theirs.append(_mk("tank"))
	return FixtureDB.engine(db, mine, theirs, allies, foes, seed_value)


func _me(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foes(e: BattleEngine) -> Array:
	return e.sides[1].active()


func _used_targets(events: Array) -> Array:
	return FixtureDB.events_of(events, BattleEvents.MOVE_USED)[0].targets


func _damage_by_target(events: Array) -> Dictionary:
	var out := {}
	for ev in FixtureDB.events_of(events, BattleEvents.DAMAGE):
		out[ev.bid] = int(out.get(ev.bid, 0)) + int(ev.amount)
	return out


func _assert_two_distinct_standing_foes(e: BattleEngine, targets: Array) -> void:
	assert_array(targets).has_size(2)
	assert_bool(targets[0] != targets[1]).is_true()
	for bid in targets:
		var b := e.battler(bid)
		assert_int(b.side).is_equal(1)
		assert_bool(b.alive() and b.active).is_true()


func test_two_enemies_hits_the_chosen_pair() -> void:
	var e := _versus(3)
	var foes := _foes(e)
	var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "twin_strike", foes[0].bid, foes[2].bid)])
	var targets := _used_targets(events)
	assert_array(targets).contains_exactly_in_any_order([foes[0].bid, foes[2].bid])
	var dmg := _damage_by_target(events)
	assert_array(dmg.keys()).contains_exactly_in_any_order([foes[0].bid, foes[2].bid])
	assert_int(FixtureDB.events_of(events, BattleEvents.DAMAGE).size()).is_equal(2)
	assert_int(foes[1].hp()).is_equal(foes[1].creature.max_hp(db))


func test_duplicate_second_pick_is_replaced() -> void:
	for seed_value in range(1, 21):
		var e := _versus(3, 0, 1, seed_value)
		var foes := _foes(e)
		var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "twin_strike", foes[0].bid, foes[0].bid)])
		var targets := _used_targets(events)
		_assert_two_distinct_standing_foes(e, targets)
		assert_bool(targets.has(foes[0].bid)).is_true()
		assert_int(FixtureDB.events_of(events, BattleEvents.DAMAGE).size()).is_equal(2)


func test_missing_second_pick_is_replaced() -> void:
	for seed_value in range(1, 21):
		var e := _versus(3, 0, 1, seed_value)
		var foes := _foes(e)
		var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "twin_strike", foes[1].bid)])
		var targets := _used_targets(events)
		_assert_two_distinct_standing_foes(e, targets)
		assert_bool(targets.has(foes[1].bid)).is_true()


func test_invalid_second_pick_is_replaced() -> void:
	for seed_value in range(1, 11):
		# An ally, an unknown bid, and a benched foe.
		var e := _versus(3, 1, 2, seed_value)
		var foes := _foes(e)
		var ally: Battler = e.sides[0].active()[1]
		var bench: Battler = e.sides[1].bench()[0]
		for bad in [ally.bid, 999, bench.bid]:
			var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "twin_strike", foes[0].bid, bad)])
			var targets := _used_targets(events)
			_assert_two_distinct_standing_foes(e, targets)
			assert_bool(targets.has(foes[0].bid)).is_true()
			assert_bool(targets.has(bad)).is_false()


func test_first_pick_gone_at_execution_is_replaced() -> void:
	for seed_value in range(1, 11):
		var mine: Array = [_mk("fast"), _mk("blob", ["twin_strike"])]
		var theirs: Array = [_mk("tank"), _mk("tank"), _mk("tank")]
		var e := FixtureDB.engine(db, mine, theirs, 2, 3, seed_value)
		var foes := _foes(e)
		var striker: Battler = e.sides[0].active()[0]
		var twin: Battler = e.sides[0].active()[1]
		foes[0].creature.hp = 1
		var events := e.resolve_round([BattleAction.use_move(striker.bid, "hit", foes[0].bid),
			BattleAction.use_move(twin.bid, "twin_strike", foes[0].bid, foes[1].bid)])
		var used := FixtureDB.events_of(events, BattleEvents.MOVE_USED)
		var targets: Array = used[1].targets
		assert_bool(foes[0].alive()).is_false()
		_assert_two_distinct_standing_foes(e, targets)
		assert_bool(targets.has(foes[0].bid)).is_false()
		assert_array(targets).contains_exactly_in_any_order([foes[1].bid, foes[2].bid])


func test_fewer_than_two_foes_hits_those_present() -> void:
	var e := _versus(2)
	var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "twin_strike", -1, -1)])
	assert_array(_used_targets(events)).contains_exactly_in_any_order([_foes(e)[0].bid, _foes(e)[1].bid])

	# One foe left: hit once, no spread penalty (same seed as an identical one_enemy move).
	var one := _versus(1)
	var events_one := one.resolve_round([BattleAction.use_move(_me(one).bid, "twin_strike", -1, -1)])
	assert_array(_used_targets(events_one)).contains_exactly([_foes(one)[0].bid])
	var plain := _versus(1)
	var events_plain := plain.resolve_round([BattleAction.use_move(_me(plain).bid, "hit", _foes(plain)[0].bid)])
	assert_int(_damage_by_target(events_one).values()[0]).is_equal(_damage_by_target(events_plain).values()[0])

	# No foes at all (one benched foe keeps the battle going).
	var none := _versus(1, 1)
	_foes(none)[0].creature.hp = 0
	none.check_faints()
	assert_array(_foes(none)).is_empty()
	none.actions.execute(BattleAction.use_move(_me(none).bid, "twin_strike"))
	assert_int(FixtureDB.events_of(none._take_events(), BattleEvents.NO_TARGET).size()).is_equal(1)


func test_resolve_targets_does_not_randomise_when_disallowed() -> void:
	var e := _versus(3, 1, 2)
	var foes := _foes(e)
	var me := _me(e)
	var ally: Battler = e.sides[0].active()[1]
	var bench: Battler = e.sides[1].bench()[0]
	# Duplicate second pick: only the valid one.
	var dup := e.resolve_targets(me, "two_enemies", foes[0].bid, foes[0].bid, false)
	assert_array(dup).contains_exactly([foes[0]])
	# Invalid second pick: only the valid one.
	for bad in [ally.bid, 999, bench.bid, -1]:
		var got := e.resolve_targets(me, "two_enemies", foes[1].bid, bad, false)
		assert_array(got).contains_exactly([foes[1]])
	# Both valid and distinct: both.
	var both := e.resolve_targets(me, "two_enemies", foes[0].bid, foes[2].bid, false)
	assert_array(both).contains_exactly([foes[0], foes[2]])
	# The AI scoring call shape (second = -1, allow_random = false) must not randomise a one_enemy pick.
	assert_array(e.resolve_targets(me, "one_enemy", 999, -1, false)).is_empty()
	assert_array(e.resolve_targets(me, "one_enemy", ally.bid, -1, false)).is_empty()
	# ...but it does when allowed.
	assert_array(e.resolve_targets(me, "one_enemy", 999, -1, true)).has_size(1)


func test_second_targets_for_excludes_first_and_fainted_foes() -> void:
	var e := _versus(3)
	var foes := _foes(e)
	var second := e.second_targets_for(_me(e).bid, "twin_strike", foes[0].bid)
	assert_array(second).contains_exactly_in_any_order([foes[1].bid, foes[2].bid])
	foes[2].creature.hp = 0
	e.check_faints()
	second = e.second_targets_for(_me(e).bid, "twin_strike", foes[0].bid)
	assert_array(second).contains_exactly([foes[1].bid])


func test_targets_for_lists_first_pick_foes() -> void:
	var e := _versus(3)
	var ids: Array = _foes(e).map(func(f): return f.bid)
	assert_array(e.targets_for(_me(e).bid, "twin_strike")).contains_exactly_in_any_order(ids)


func test_second_targets_for_is_empty_for_other_targets() -> void:
	var e := _versus(3)
	var foes := _foes(e)
	assert_array(e.second_targets_for(_me(e).bid, "hit", foes[0].bid)).is_empty()
	assert_array(e.second_targets_for(_me(e).bid, "wave", foes[0].bid)).is_empty()
	assert_array(e.second_targets_for(_me(e).bid, "mend", -1)).is_empty()


func test_use_move_without_second_target_behaves_as_before() -> void:
	var e := _versus(2)
	var foes := _foes(e)
	var a := BattleAction.use_move(_me(e).bid, "hit", foes[1].bid)
	assert_int(a.second_target).is_equal(-1)
	var events := e.resolve_round([a])
	assert_array(_used_targets(events)).contains_exactly([foes[1].bid])
	assert_int(foes[0].hp()).is_equal(foes[0].creature.max_hp(db))


func _big(foes: int, seed_value: int) -> BattleEngine:
	var mine: Array = [FixtureDB.make(db, "blob", 90, ["twin_strike", "hit"])]
	var theirs: Array = []
	for i in foes:
		theirs.append(FixtureDB.make(db, "tank", 90))
	return FixtureDB.engine(db, mine, theirs, 1, foes, seed_value)


## Real execution path. `hit` has the same power, type and category as `twin_strike`, so the
## single-target estimate S is the no-spread baseline. Every hit must lie in the roll window of
## S / ROLL_AVG * 0.85: [base * ROLL_MIN / ROLL_MAX - 1, base + 1]. With S = 52 that is
## about [39.6, 48.8]. A x0.75 hit spans about [35.8, 42.2], so most rolls fall below the floor;
## no penalty spans about [47.8, 56.2], so most rolls exceed the ceiling. Either regression
## breaches the window within 20 hits over 10 seeds.
func test_spread_penalty_applies_to_a_two_target_move() -> void:
	var base_e: BattleEngine = _big(2, 1)
	var single: float = BattleAI.estimate_damage(base_e, _me(base_e), db.move("hit"), _foes(base_e)[0], 1)
	var base85: float = single / BattleMath.ROLL_AVG * db.balance.spread_mult_for(2)
	var ceiling: float = base85 + 1.0
	var floor_value: float = base85 * BattleMath.ROLL_MIN / BattleMath.ROLL_MAX - 1.0
	var hits: int = 0
	for seed_value in range(1, 11):
		var e: BattleEngine = _big(2, seed_value)
		var events: Array = e.resolve_round([BattleAction.use_move(_me(e).bid, "twin_strike")])
		var damages: Array = FixtureDB.events_of(events, BattleEvents.DAMAGE)
		assert_array(damages).has_size(2)
		for ev in damages:
			hits += 1
			assert_float(float(ev.amount)).is_between(floor_value, ceiling)
	assert_int(hits).is_equal(20)
	# A single foe takes no penalty: the baseline window of a 1v1 single-target estimate
	# (a lone foe is a different underdog ratio than 1v2, so it needs its own baseline).
	var base_one: BattleEngine = _big(1, 1)
	single = BattleAI.estimate_damage(base_one, _me(base_one), db.move("hit"), _foes(base_one)[0], 1)
	var one_ceiling: float = single / BattleMath.ROLL_AVG + 1.0
	var one_floor: float = single / BattleMath.ROLL_AVG * BattleMath.ROLL_MIN / BattleMath.ROLL_MAX - 1.0
	for seed_value in range(1, 11):
		var one: BattleEngine = _big(1, seed_value)
		var events_one: Array = one.resolve_round([BattleAction.use_move(_me(one).bid, "twin_strike")])
		var damages_one: Array = FixtureDB.events_of(events_one, BattleEvents.DAMAGE)
		assert_array(damages_one).has_size(1)
		assert_float(float(damages_one[0].amount)).is_between(one_floor, one_ceiling)


func test_ai_scoring_a_two_target_move_draws_no_random_numbers() -> void:
	var e: BattleEngine = _versus(3)
	var foes: Array = _foes(e)
	var move: MoveDef = db.move("twin_strike")
	for pick in [-1, 999, foes[0].bid]:
		var before_state: int = e.rng.state
		BattleAI.score(e, _me(e), move, pick, "basic")
		assert_int(e.rng.state).is_equal(before_state)
	# With a valid first pick only that foe is scored (no random second foe is added).
	var one_foe: float = BattleAI.score(e, _me(e), move, foes[0].bid, "basic")
	var estimate: float = BattleAI.estimate_damage(e, _me(e), move, foes[0], 1)
	assert_float(one_foe).is_equal_approx(minf(estimate, float(foes[0].hp())), 0.001)
