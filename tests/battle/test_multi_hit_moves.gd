extends GdUnitTestSuite
## Multi-hit moves: the hit count, per-hit effects and triggers, and faint-and-spill.

var db: Database


func _build(balance_overrides := {}) -> Database:
	var r := FixtureDB.raw()
	var dmg := [{"op": "damage"}]
	for spec: Array in [
		["triple", 20, 100, dmg, {"hits": {"min": 3, "max": 3}}],
		["quint", 20, 100, dmg, {"hits": {"min": 5, "max": 5}}],
		["flurry", 20, 100, dmg, {"hits": {"min": 2, "max": 5}}],
		["shaky", 20, 1, dmg, {"hits": {"min": 3, "max": 3}}],
		["doubled", 20, 100, [{"op": "damage"}, {"op": "damage"}], {"hits": {"min": 3, "max": 3}}],
		["jolting", 20, 100, [{"op": "damage"}, {"op": "apply_status", "status": "shock", "chance": 100}],
			{"hits": {"min": 3, "max": 3}}],
		["zapper", 20, 100, dmg, {"hits": {"min": 3, "max": 3}, "type": "electric"}],
		["cashin", 20, 100, [{"op": "bonus_if_field", "side": "target", "state": "soaked", "mult": 1.5, "consume": true},
			{"op": "damage"}], {"hits": {"min": 3, "max": 3}}],
		["single", 20, 100, dmg, {}],
		["single_one", 20, 100, dmg, {"hits": {"min": 1, "max": 1}}],
	]:
		r.add_entry("moves", FixtureDB.move(spec[0], "neutral", "physical", spec[1], spec[2], "one_enemy", spec[3], spec[4]))
	for p in [
		{"id": "pricker", "triggers": [{"on": "hit", "effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]},
		{"id": "sponge", "effects": [{"op": "absorb_type", "type": "electric", "fraction": 0.25}]},
		{"id": "thorns", "triggers": [{"on": "hit", "effects": [{"op": "damage", "power": 200, "target": "attacker"}]}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	if not balance_overrides.is_empty():
		var b := FixtureDB.balance()
		b.merge(balance_overrides, true)
		r.set_single("balance", b)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	return Database.from_raw(r)


func before() -> void:
	db = _build()


func _mk(species := "blob", moves: Array = ["hit"]) -> CreatureInstance:
	return FixtureDB.make(db, species, 10, moves)


## One attacker knowing every test move against `foes` tanks fielded plus `bench` waiting.
func _versus(foes: int, bench := 0, seed_value := 1, the_db: Database = null) -> BattleEngine:
	var d := the_db if the_db != null else db
	var mine := [FixtureDB.make(d, "blob", 10, ["triple", "quint", "flurry", "shaky", "doubled", "jolting", "single", "single_one", "zapper", "cashin", "drench"])]
	var theirs: Array = []
	for i in foes + bench:
		theirs.append(FixtureDB.make(d, "tank", 10, ["hit"]))
	return FixtureDB.engine(d, mine, theirs, 1, foes, seed_value)


func _me(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foes(e: BattleEngine) -> Array:
	return e.sides[1].active()


func _use(e: BattleEngine, move: String, target: Battler) -> Array:
	return e.resolve_round([BattleAction.use_move(_me(e).bid, move, target.bid)])


func _count(events: Array, type: String) -> int:
	return FixtureDB.events_of(events, type).size()


func _hits_landed(events: Array) -> int:
	return int(FixtureDB.events_of(events, BattleEvents.HIT_COUNT)[0].hits)


## [type, bid] of every DAMAGE and FAINT event, in order.
func _sequence(events: Array) -> Array:
	var out := []
	for ev in events:
		if ev.type == BattleEvents.DAMAGE or ev.type == BattleEvents.FAINT:
			out.append([ev.type, ev.bid])
	return out


func _index_of(events: Array, type: String) -> int:
	for i in events.size():
		if events[i].type == type:
			return i
	return -1


func test_a_fixed_count_hits_exactly_that_many_times() -> void:
	var e := _versus(1)
	var events := _use(e, "triple", _foes(e)[0])
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(3)
	assert_int(_hits_landed(events)).is_equal(3)
	assert_int(_count(events, BattleEvents.MOVE_USED)).is_equal(1)


func test_a_range_stays_within_min_and_max_and_covers_it() -> void:
	var seen := {}
	for seed_value in range(1, 61):
		var e := _versus(1, 0, seed_value)
		var events := _use(e, "flurry", _foes(e)[0])
		var n := _hits_landed(events)
		assert_int(n).is_between(2, 5)
		assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(n)
		seen[n] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([2, 3, 4, 5])


func test_a_move_without_hits_emits_no_hit_count_and_hits_once() -> void:
	var e := _versus(1)
	var events := _use(e, "single", _foes(e)[0])
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(1)
	assert_int(_count(events, BattleEvents.HIT_COUNT)).is_equal(0)


func test_an_explicit_single_hit_draws_no_extra_rng() -> void:
	var a := _versus(1, 0, 7)
	var b := _versus(1, 0, 7)
	var events_a := _use(a, "single", _foes(a)[0])
	var events_b := _use(b, "single_one", _foes(b)[0])
	assert_array(FixtureDB.events_of(events_b, BattleEvents.DAMAGE)).is_equal(FixtureDB.events_of(events_a, BattleEvents.DAMAGE))
	assert_int(_count(events_b, BattleEvents.HIT_COUNT)).is_equal(0)
	assert_int(b.rng.state).is_equal(a.rng.state)


func test_accuracy_is_rolled_once_so_a_move_lands_all_hits_or_none() -> void:
	var missed := 0
	for seed_value in range(1, 41):
		var e := _versus(1, 0, seed_value)
		var events := _use(e, "shaky", _foes(e)[0])
		if _count(events, BattleEvents.MISS) > 0:
			missed += 1
			assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(0)
			assert_int(_count(events, BattleEvents.HIT_COUNT)).is_equal(0)
		else:
			assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(3)
	assert_int(missed).is_greater(0)


func test_the_whole_effect_list_runs_per_hit() -> void:
	var e := _versus(1)
	var events := _use(e, "doubled", _foes(e)[0])
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(6)
	var e2 := _versus(1)
	var foe: Battler = _foes(e2)[0]
	var events2 := _use(e2, "jolting", foe)
	assert_str(foe.status()).is_equal("shock")
	assert_int(_count(events2, BattleEvents.STATUS_APPLIED)).is_equal(1)
	assert_int(_count(events2, BattleEvents.STATUS_FAILED)).is_equal(2)


func test_hit_triggers_fire_once_per_hit() -> void:
	var e := _versus(1)
	var foe: Battler = _foes(e)[0]
	foe.creature.passive = "pricker"
	_use(e, "triple", foe)
	assert_int(int(_me(e).stages["patk"])).is_equal(-3)


func test_resolve_endure_happens_at_most_once() -> void:
	var strict := _build({"resolve": {"resist_cap": 0.0, "endure_cap": 1.0}})
	for seed_value in range(1, 21):
		var e := _versus(1, 0, seed_value, strict)
		var foe: Battler = _foes(e)[0]
		foe.creature.hp = 1
		var events := _use(e, "triple", foe)
		assert_int(_count(events, BattleEvents.ENDURED)).is_less_equal(1)


func test_affinity_from_hits_is_earned_once_per_move() -> void:
	var one := _versus(1)
	_use(one, "single", _foes(one)[0])
	var many := _versus(1)
	var foe: Battler = _foes(many)[0]
	_use(many, "triple", foe)
	assert_dict(many.rewards.affinity_log.get(_me(many).bid, {})).is_equal(one.rewards.affinity_log.get(_me(one).bid, {}))
	assert_dict(many.rewards.affinity_log.get(foe.bid, {})).is_equal(one.rewards.affinity_log.get(_foes(one)[0].bid, {}))


func test_a_fainted_target_faints_at_once_and_the_rest_spill_in_slot_order() -> void:
	var e := _versus(3)
	var foes := _foes(e)
	foes[0].creature.hp = 1
	var events := _use(e, "triple", foes[0])
	assert_array(_sequence(events)).is_equal([
		[BattleEvents.DAMAGE, foes[0].bid], [BattleEvents.FAINT, foes[0].bid],
		[BattleEvents.DAMAGE, foes[1].bid], [BattleEvents.DAMAGE, foes[1].bid]])
	assert_int(_hits_landed(events)).is_equal(3)
	assert_int(foes[2].hp()).is_equal(foes[2].creature.max_hp(db))


func test_the_spill_wraps_around_the_slots() -> void:
	var e := _versus(3)
	var foes := _foes(e)
	foes[2].creature.hp = 1
	var events := _use(e, "triple", foes[2])
	assert_array(_sequence(events)).is_equal([
		[BattleEvents.DAMAGE, foes[2].bid], [BattleEvents.FAINT, foes[2].bid],
		[BattleEvents.DAMAGE, foes[0].bid], [BattleEvents.DAMAGE, foes[0].bid]])


func test_the_spill_skips_a_fainted_slot_and_never_reaches_the_bench() -> void:
	var e := _versus(2, 1)
	var foes := _foes(e)
	var bench: Battler = e.sides[1].bench()[0]
	foes[0].creature.hp = 1
	foes[1].creature.hp = 1
	var events := _use(e, "triple", foes[0])
	assert_array(_sequence(events)).is_equal([
		[BattleEvents.DAMAGE, foes[0].bid], [BattleEvents.FAINT, foes[0].bid],
		[BattleEvents.DAMAGE, foes[1].bid], [BattleEvents.FAINT, foes[1].bid]])
	assert_int(_hits_landed(events)).is_equal(2)
	assert_int(bench.hp()).is_equal(bench.creature.max_hp(db))
	var first := _index_of(events, BattleEvents.MOVE_USED)
	var last := _index_of(events, BattleEvents.HIT_COUNT)
	for i in range(first, last):
		assert_str(events[i].type).is_not_equal(BattleEvents.SEND_OUT)


func test_a_lone_foe_ends_the_move_early() -> void:
	var e := _versus(1, 1)
	var foe: Battler = _foes(e)[0]
	foe.creature.hp = 1
	var events := _use(e, "quint", foe)
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(1)
	assert_int(_hits_landed(events)).is_equal(1)


func test_the_hit_that_ends_the_battle_stops_the_move() -> void:
	var e := _versus(1)
	var foe: Battler = _foes(e)[0]
	foe.creature.hp = 1
	var events := _use(e, "quint", foe)
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(1)
	assert_int(_index_of(events, BattleEvents.HIT_COUNT)).is_less(_index_of(events, BattleEvents.BATTLE_END))


func test_the_attacker_fainting_mid_move_stops_it() -> void:
	var mine := [FixtureDB.make(db, "blob", 10, ["triple"]), FixtureDB.make(db, "blob", 10, ["hit"])]
	var theirs := [FixtureDB.make(db, "tank", 10, ["hit"])]
	theirs[0].passive = "thorns"
	mine[0].hp = 1
	var e := FixtureDB.engine(db, mine, theirs, 1, 1)
	var foe: Battler = _foes(e)[0]
	var attacker := _me(e)
	var events := e.resolve_round([BattleAction.use_move(attacker.bid, "triple", foe.bid)])
	var on_foe := FixtureDB.events_of(events, BattleEvents.DAMAGE).filter(func(ev): return ev.bid == foe.bid)
	assert_int(on_foe.size()).is_equal(1)
	assert_bool(attacker.alive()).is_false()
	assert_int(_hits_landed(events)).is_equal(1)


func test_next_foe_after_returns_null_without_a_standing_foe() -> void:
	var e := _versus(1)
	var foe: Battler = _foes(e)[0]
	foe.creature.hp = 0
	e.check_faints()
	assert_object(e.next_foe_after(_me(e), foe)).is_null()


func test_a_field_bonus_does_not_compound_across_hits() -> void:
	var e := _versus(1)
	var foe: Battler = _foes(e)[0]
	e.resolve_round([BattleAction.use_move(_me(e).bid, "drench")])
	var events := _use(e, "cashin", foe)
	var amounts := FixtureDB.events_of(events, BattleEvents.DAMAGE).map(func(ev): return int(ev.amount))
	assert_int(amounts.size()).is_equal(3)
	# Each hit gets the same x1.5 (the damage roll alone varies by at most 1/0.85); compounding would
	# make the second hit x1.5 the first.
	assert_float(float(amounts.max())).is_less_equal(float(amounts.min()) * 1.25)


func test_hits_against_an_immune_foe_stop_after_one_no_effect() -> void:
	var mine := [FixtureDB.make(db, "blob", 10, ["zapper"])]
	var theirs := [FixtureDB.make(db, "mole", 10, ["hit"])]
	var e := FixtureDB.engine(db, mine, theirs, 1, 1)
	var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "zapper", _foes(e)[0].bid)])
	assert_int(_count(events, BattleEvents.NO_EFFECT)).is_equal(1)
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(0)
	assert_int(_hits_landed(events)).is_equal(0)


func test_an_absorber_absorbs_every_hit_and_each_counts() -> void:
	var foe_creature := FixtureDB.make(db, "tank", 10, ["hit"])
	foe_creature.passive = "sponge"
	foe_creature.hp = foe_creature.max_hp(db) / 2
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["zapper"])], [foe_creature], 1, 1)
	var events := e.resolve_round([BattleAction.use_move(_me(e).bid, "zapper", _foes(e)[0].bid)])
	assert_int(_count(events, BattleEvents.HEAL)).is_equal(3)
	assert_int(_count(events, BattleEvents.DAMAGE)).is_equal(0)
	assert_int(_hits_landed(events)).is_equal(3)
