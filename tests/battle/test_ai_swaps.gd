extends GdUnitTestSuite
## How the tactician AI values swapping an active creature for a benched one (swap_score and threat), and how it
## chooses between a swap and its moves. Species: blob is flat, tank has HP 250, puncher hits hard, wimp hits soft.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	var learn := [{"level": 1, "move": "hit"}]
	r.add_entry("creatures", FixtureDB._c("puncher", ["neutral"], FixtureDB.stats({"patk": 150}), learn))
	r.add_entry("creatures", FixtureDB._c("wimp", ["neutral"], FixtureDB.stats({"patk": 20}), learn))
	# brute and wall hit equally hard, wall takes almost nothing: a bench creature that makes a doomed lead worth swapping.
	r.add_entry("creatures", FixtureDB._c("brute", ["neutral"], FixtureDB.stats({"patk": 255}), learn))
	r.add_entry("creatures", FixtureDB._c("wall", ["neutral"], FixtureDB.stats({"patk": 255, "pdef": 250, "sdef": 250}), learn))
	r.add_entry("creatures", FixtureDB._c("feeble", ["neutral"], FixtureDB.stats({"patk": 1}), learn))
	r.add_entry("creatures", FixtureDB._c("glass", ["neutral"], FixtureDB.stats({"pdef": 20, "sdef": 20}), learn))
	r.add_entry("field_states", {"id": "ward", "name": "Ward", "max_stacks": 3, "default_turns": 3,
		"passive": [{"op": "stat_mod", "stat": "patk", "mult": 1.2}]})
	r.add_entry("passives", {"id": "welcome_ward", "name": "Welcome Ward", "description": "Test passive.",
		"triggers": [{"on": "enter", "effects": [{"op": "apply_field_state", "side": "own", "state": "ward"}]}]})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String) -> CreatureInstance:
	return FixtureDB.make(db, species, 10, ["hit"])


## 1v1 with one benched creature on side 0.
func _engine(lead: String, bench: String, foe: String) -> BattleEngine:
	return FixtureDB.engine(db, [_make(lead), _make(bench)], [_make(foe)])


func _lead(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _bench(e: BattleEngine) -> Battler:
	return e.sides[0].bench()[0]


func _score(e: BattleEngine, style := "tactician") -> float:
	return BattleAI.swap_score(e, _lead(e), _bench(e), style, BattleAI.best_damage(e, _lead(e)))


func test_damage_avoided_when_lead_is_doomed() -> void:
	var e := _engine("blob", "tank", "blob")
	_lead(e).creature.hp = 1
	var d_lead := BattleAI.threat(e, _lead(e))
	var d_bench := BattleAI.threat(e, _bench(e))
	assert_bool(d_lead >= 1.0).is_true()
	assert_bool(d_bench < float(_bench(e).hp())).is_true()
	assert_float(_score(e)).is_equal_approx(1.0 - d_bench + BattleAI.ko_bonus(BattleAI.best_damage(e, _lead(e))), 0.001)


func test_no_damage_avoided_when_lead_is_healthy() -> void:
	# Same species: nothing to gain, nothing to lose.
	var e := _engine("blob", "blob", "blob")
	assert_float(_score(e)).is_equal_approx(0.0, 0.001)
	# A bench creature that takes more damage (lower defences) is worse by exactly the extra damage, with no knockout
	# bonus (the lead is not doomed): the avoided-damage term is threat(lead) - threat(bench) while both survive.
	var e2 := _engine("blob", "glass", "blob")
	var t_lead := BattleAI.threat(e2, _lead(e2))
	var t_bench := BattleAI.threat(e2, _bench(e2))
	assert_bool(t_lead < float(_lead(e2).hp()) and t_bench < float(_bench(e2).hp())).is_true()
	assert_bool(t_bench > t_lead).is_true()
	assert_float(_score(e2)).is_equal_approx(t_lead - t_bench, 0.001)


func test_doomed_bench_gains_nothing() -> void:
	var e := _engine("blob", "blob", "blob")
	_lead(e).creature.hp = 1
	_bench(e).creature.hp = 1
	assert_float(_score(e)).is_equal_approx(0.0, 0.001)


func test_offence_prefers_the_harder_hitter() -> void:
	var e := _engine("wimp", "puncher", "tank")
	var gain := BattleAI.best_damage(e, _bench(e)) - BattleAI.best_damage(e, _lead(e))
	assert_bool(gain > 0.0).is_true()
	assert_float(_score(e)).is_equal_approx(gain, 0.001)
	var e2 := _engine("puncher", "wimp", "tank")
	assert_bool(_score(e2) < 0.0).is_true()


func test_entry_term_matches_enter_value() -> void:
	var e := _engine("blob", "blob", "blob")
	var base := _score(e)
	_bench(e).creature.passive = "welcome_ward"
	var with_entry := _score(e)
	var value := BattleAI.enter_value(e, _lead(e), _bench(e))
	assert_bool(value > 0.0).is_true()
	assert_float(with_entry - base).is_equal_approx(value, 0.001)


func test_escape_counts_stages() -> void:
	var e := _engine("blob", "blob", "blob")
	var ref := BattleAI.best_damage(e, _lead(e))
	var base := _score(e)
	var unit: float = BattleAI.DEBUFF_VALUE.spd * ref
	_lead(e).stages.spd = -2
	assert_float(_score(e) - base).is_equal_approx(unit * 2.0, 0.001)
	_lead(e).stages.spd = 2
	assert_float(_score(e) - base).is_equal_approx(-unit * 2.0, 0.001)


func test_escape_counts_a_skip_status() -> void:
	var e := _engine("blob", "blob", "blob")
	var ref := BattleAI.best_damage(e, _lead(e))
	var base := _score(e)
	_lead(e).creature.status = "shock"  # skip_chance 100
	_lead(e).status_turns = 2
	assert_float(_score(e) - base).is_equal_approx(ref * float(mini(2, BattleAI.STATUS_HORIZON)), 0.001)
	_lead(e).creature.status = "burn"  # damage over time only
	assert_float(_score(e) - base).is_equal_approx(0.0, 0.001)


func test_swap_score_draws_no_rng() -> void:
	var e := FixtureDB.engine(db, [_make("blob"), _make("blob"), _make("blob")], [_make("tank"), _make("puncher")], 2, 2)
	var before_state := e.rng.state
	for b in e.sides[0].active():
		for c in e.sides[0].bench():
			BattleAI.swap_score(e, b, c, "tactician", BattleAI.best_damage(e, b))
	assert_int(e.rng.state).is_equal(before_state)


func test_threat_uses_each_foes_best_move() -> void:
	var e := FixtureDB.engine(db, [_make("blob"), _make("blob")], [_make("blob"), _make("puncher")], 1, 2)
	var lead := _lead(e)
	var expected := 0.0
	for foe in e.sides[1].active():
		expected += BattleAI.estimate_damage(e, foe, db.move("hit"), lead, 1)
	assert_float(BattleAI.threat(e, lead)).is_equal_approx(expected, 0.001)


## Best score among the lead's non-swap options (moves and targets, as `choose` builds them).
func _best_move(e: BattleEngine, b: Battler) -> float:
	var best := -INF
	var ref := BattleAI.best_damage(e, b)
	for mid in e.usable_moves(b.bid):
		for t in e.targets_for(b.bid, mid):
			best = maxf(best, BattleAI.score(e, b, e.db.move(mid), t, "tactician", ref))
	return best


func _kind(e: BattleEngine, b: Battler, style := "tactician") -> String:
	return BattleAI.choose(e, b.bid, style).kind


func test_doomed_tactician_swaps() -> void:
	var e := _engine("brute", "wall", "blob")
	_lead(e).creature.hp = 1
	var a := BattleAI.choose(e, _lead(e).bid, "tactician")
	assert_str(a.kind).is_equal("swap")
	assert_int(a.swap_in).is_equal(_bench(e).bid)


func test_healthy_tactician_does_not_swap() -> void:
	var e := _engine("blob", "blob", "blob")
	assert_str(_kind(e, _lead(e))).is_equal("move")


func test_swap_is_chosen_exactly_when_it_clears_the_margin() -> void:
	var in_zone := false
	var swapped := 0
	var stayed := 0
	for foe in ["blob", "puncher", "wimp", "tank"]:
		for bench in ["tank", "blob", "puncher", "wimp"]:
			for lead_hp in [1, 2, 3, 4, 5, 6, 8, 10, 14, 20, 40, 1000]:
				var e := _engine("blob", bench, foe)
				_lead(e).creature.hp = mini(lead_hp, _lead(e).creature.max_hp(db))
				var ref := BattleAI.best_damage(e, _lead(e))
				var gap := _score(e) - _best_move(e, _lead(e))
				var want_swap := gap > BattleAI.SWAP_MARGIN * ref
				assert_bool(_kind(e, _lead(e)) == "swap").is_equal(want_swap)
				if want_swap:
					swapped += 1
				else:
					stayed += 1
				if gap > 0.0 and not want_swap:
					in_zone = true
	assert_int(swapped).is_greater(0)
	assert_int(stayed).is_greater(0)
	assert_bool(in_zone).is_true()


## A doomed lead with two moves and a healthy bench: the situation where the tactician swaps.
func _doomed_two_move_engine() -> BattleEngine:
	var e: BattleEngine = FixtureDB.engine(db, [FixtureDB.make(db, "brute", 10, ["hit", "quick_jab"]), _make("wall")],
		[_make("blob")])
	_lead(e).creature.hp = 1
	return e


func test_aggressive_never_swaps_and_plays_its_best_move() -> void:
	var e := _doomed_two_move_engine()
	assert_str(_kind(e, _lead(e), "tactician")).is_equal("swap")  # the same fixture does swap for the tactician
	var a := BattleAI.choose(e, _lead(e).bid, "aggressive")
	assert_str(a.kind).is_equal("move")
	var ref := BattleAI.best_damage(e, _lead(e))
	for mid in e.usable_moves(_lead(e).bid):
		for t in e.targets_for(_lead(e).bid, mid):
			assert_bool(BattleAI.score(e, _lead(e), db.move(mid), t, "aggressive", ref)
				<= BattleAI.score(e, _lead(e), db.move(a.move), a.target, "aggressive", ref) + 0.0001).is_true()


func test_basic_never_swaps_and_draws_exactly_one_pick() -> void:
	var e := _doomed_two_move_engine()
	var expected := RandomNumberGenerator.new()
	expected.seed = e.rng.seed
	expected.state = e.rng.state
	assert_str(_kind(e, _lead(e), "basic")).is_not_equal("swap")
	# One random pick among the two moves (a swap option would change the pool size, and a draw for scoring would
	# change the count): the generator is exactly where one randi_range(0, 1) leaves it.
	expected.randi_range(0, 1)
	assert_int(e.rng.state).is_equal(expected.state)


func test_two_doomed_actives_claim_distinct_bench() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_make("brute"), _make("brute"), _make("wall")],
		[_make("feeble"), _make("feeble")], 2, 2)
	for b in e.sides[0].active():
		b.creature.hp = 1
	e.sides[0].ai = "tactician"
	var actions := BattleAI.choose_all(e, 0)
	var swaps := actions.filter(func(a: BattleAction) -> bool: return a.kind == "swap")
	assert_int(swaps.size()).is_equal(1)
	assert_int(swaps[0].swap_in).is_equal(e.sides[0].bench()[0].bid)
	assert_int(actions.size()).is_equal(2)


func test_two_doomed_actives_two_bench() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_make("brute"), _make("brute"), _make("wall"), _make("wall")],
		[_make("feeble"), _make("feeble")], 2, 2)
	for b in e.sides[0].active():
		b.creature.hp = 1
	e.sides[0].ai = "tactician"
	var swaps := BattleAI.choose_all(e, 0).filter(func(a: BattleAction) -> bool: return a.kind == "swap")
	assert_int(swaps.size()).is_equal(2)
	assert_bool(swaps[0].swap_in != swaps[1].swap_in).is_true()


func test_swapper_takes_no_further_actions() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_make("brute"), _make("brute"), _make("wall")],
		[_make("feeble"), _make("feeble")], 2, 2)
	e.sides[0].underdog = {"bonus_actions": 1}
	var doomed: Battler = e.sides[0].active()[0]
	var healthy: Battler = e.sides[0].active()[1]
	doomed.creature.hp = 1
	e.sides[0].ai = "tactician"
	var actions := BattleAI.choose_all(e, 0)
	assert_int(actions.filter(func(a: BattleAction) -> bool: return a.actor == doomed.bid).size()).is_equal(1)
	assert_int(actions.filter(func(a: BattleAction) -> bool: return a.actor == healthy.bid).size()).is_equal(2)


func test_fresh_swap_in_does_not_swap_back() -> void:
	var e := _engine("wall", "brute", "blob")
	var old_lead := _lead(e)
	var newcomer := _bench(e)
	e.resolve_round([BattleAction.swap(old_lead.bid, newcomer.bid)])
	assert_bool(newcomer.acted).is_false()
	newcomer.creature.hp = 1
	old_lead.creature.hp = old_lead.creature.max_hp(db)
	assert_str(_kind(e, newcomer)).is_equal("move")
	newcomer.acted = true
	assert_str(_kind(e, newcomer)).is_equal("swap")


func test_no_bench_changes_nothing() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_make("blob")], [_make("puncher")])
	_lead(e).creature.hp = 1
	assert_str(_kind(e, _lead(e))).is_equal("move")


func test_incoming_skip_status_costs_the_swap() -> void:
	# A status freezes on the bench, so bringing a shocked creature back in costs the turns it will lose.
	var e := _engine("blob", "blob", "blob")
	var ref := BattleAI.best_damage(e, _lead(e))
	var base := _score(e)
	_bench(e).creature.status = "shock"  # skip_chance 100
	_bench(e).status_turns = 2
	assert_float(_score(e) - base).is_equal_approx(-ref * float(mini(2, BattleAI.STATUS_HORIZON)), 0.001)
	_bench(e).creature.status = "burn"  # damage over time only
	assert_float(_score(e) - base).is_equal_approx(0.0, 0.001)
