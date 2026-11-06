extends GdUnitTestSuite
## AI choices and effect-op registry coverage.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB._m("twin_strike", "neutral", "physical", 50, 100, "two_enemies",
		[{"op": "damage"}]))
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func test_every_schema_op_has_a_handler() -> void:
	var schema_ops := Array(DataSchemas.EFFECT_OPS.keys())
	var handled := Array(EffectOps.known_ops())
	schema_ops.sort()
	handled.sort()
	assert_array(handled).is_equal(schema_ops)


func test_aggressive_picks_super_effective_move() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "fish", 10, ["hit", "splash"])], [FixtureDB.make(db, "flame")])
	var a := BattleAI.choose(e, e.sides[0].active()[0].bid, "aggressive")
	assert_str(a.move).is_equal("splash")


func test_aggressive_prefers_knockout_target() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["hit"])],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "blob")], 1, 2)
	var weak: Battler = e.sides[1].active()[1]
	weak.creature.hp = 2
	var a := BattleAI.choose(e, e.sides[0].active()[0].bid, "aggressive")
	assert_int(a.target).is_equal(weak.bid)


func test_tactician_sets_up_reaction() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "sparky", 10, ["hit", "charge_up"])], [FixtureDB.make(db, "tank")])
	e.apply_field_state(1, "soaked", 2, 3, null, false)
	var a := BattleAI.choose(e, e.sides[0].active()[0].bid, "tactician")
	assert_str(a.move).is_equal("charge_up")


func test_tactician_avoids_reaction_on_own_side() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "sparky", 10, ["hit", "charge_up"])], [FixtureDB.make(db, "tank")])
	e.apply_field_state(0, "soaked", 2, 3, null, false)
	var me: Battler = e.sides[0].active()[0]
	# charge_up targets the enemy side, so own-side soaked is irrelevant; it should still score.
	assert_float(BattleAI.score(e, me, db.move("charge_up"), -1, "tactician")).is_greater(0.0)


func test_aggressive_ignores_setup_moves() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "sparky", 10, ["hit", "charge_up"])], [FixtureDB.make(db, "tank")])
	e.apply_field_state(1, "soaked", 2, 3, null, false)
	var a := BattleAI.choose(e, e.sides[0].active()[0].bid, "aggressive")
	assert_str(a.move).is_equal("hit")


func test_heals_when_low() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["hit", "mend"])], [FixtureDB.make(db, "tank")])
	var me: Battler = e.sides[0].active()[0]
	me.creature.hp = 3
	assert_str(BattleAI.choose(e, me.bid, "aggressive").move).is_equal("mend")


func test_status_value_reflects_what_the_status_does() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob")], [FixtureDB.make(db, "tank")])
	var foe: Battler = e.sides[1].active()[0]
	var ref := 10.0
	# Shock (100% skip for 2 rounds) beats Burn (12.5%/round), which beats Chill (speed only).
	assert_float(BattleAI.status_value(e, foe, "shock", ref)).is_greater(BattleAI.status_value(e, foe, "chill", ref))
	assert_float(BattleAI.status_value(e, foe, "burn", ref)).is_greater(BattleAI.status_value(e, foe, "chill", ref))


func test_damaging_reaction_outvalues_debuff_reaction() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "sparky", 10, ["zap"])],
		[FixtureDB.make(db, "tank"), FixtureDB.make(db, "tank")], 1, 2)
	var me: Battler = e.sides[0].active()[0]
	var conduction := BattleAI.reaction_value(e, me, db.reaction("conduction"), 1, 2, 10.0)
	var steam := BattleAI.reaction_value(e, me, db.reaction("steam"), 1, 2, 10.0)
	assert_float(conduction).is_greater(steam)


func test_state_benefit_sign() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob")], [FixtureDB.make(db, "tank")])
	assert_float(BattleAI.state_benefit(e, "soaked")).is_less(0.0)  # electric weakness
	assert_float(BattleAI.state_benefit(e, "overgrown")).is_less(0.0)  # slowed
	assert_float(BattleAI.state_benefit(e, "charged")).is_equal(0.0)


# --- overwriting a state (cap 1) --------------------------------------------------

## A cap-1 database with two helpful states (warded, blessed) and moves that set a state.
func _overwrite_engine() -> BattleEngine:
	var r := FixtureDB.raw()
	var b := FixtureDB.balance()
	b["max_field_states"] = 1
	r.set_single("balance", b)
	r.add_entry("field_states", {"id": "warded", "name": "Warded", "max_stacks": 3, "default_turns": 3,
		"passive": [{"op": "stat_mod", "stat": "sdef", "mult": 1.2}]})
	r.add_entry("field_states", {"id": "blessed", "name": "Blessed", "max_stacks": 3, "default_turns": 3,
		"passive": [{"op": "stat_mod", "stat": "patk", "mult": 1.2}]})
	r.add_entry("moves", FixtureDB._m("ward", "neutral", "status", 0, 100, "own_side",
		[{"op": "apply_field_state", "side": "own", "state": "warded"}], {"always_hits": true}))
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:
" + "
".join(errors))
	var d := Database.from_raw(r)
	return FixtureDB.engine(d, [FixtureDB.make(d, "blob", 10, ["hit", "ward", "grow"])], [FixtureDB.make(d, "tank")])


func _setup_score(e: BattleEngine, move: String) -> float:
	var me: Battler = e.sides[0].active()[0]
	return BattleAI.score(e, me, e.db.move(move), -1, "tactician", 10.0)


func test_tactician_avoids_overwriting_its_own_buff() -> void:
	var empty := _setup_score(_overwrite_engine(), "ward")
	var e := _overwrite_engine()
	e.apply_field_state(0, "blessed", 1, 3, null, false)
	assert_float(_setup_score(e, "ward")).is_less(empty)


func test_tactician_likes_overwriting_its_own_harmful_state() -> void:
	var empty := _setup_score(_overwrite_engine(), "ward")
	var e := _overwrite_engine()
	e.apply_field_state(0, "soaked", 1, 3, null, false)
	assert_float(_setup_score(e, "ward")).is_greater(empty)


func test_tactician_likes_overwriting_an_enemy_buff() -> void:
	var empty := _setup_score(_overwrite_engine(), "grow")
	var e := _overwrite_engine()
	e.apply_field_state(1, "blessed", 1, 3, null, false)
	assert_float(_setup_score(e, "grow")).is_greater(empty)


func test_tactician_avoids_overwriting_an_enemy_debuff() -> void:
	var empty := _setup_score(_overwrite_engine(), "grow")
	var e := _overwrite_engine()
	e.apply_field_state(1, "soaked", 1, 3, null, false)
	assert_float(_setup_score(e, "grow")).is_less(empty)


func test_basic_returns_a_known_move() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 8)], [FixtureDB.make(db, "tank")])
	var me: Battler = e.sides[0].active()[0]
	for i in 10:
		assert_bool(me.creature.moves.has(BattleAI.choose(e, me.bid, "basic").move)).is_true()


# --- two_enemies moves ---------------------------------------------------------

func _twin_engine(foes: int, seed_value := 1) -> BattleEngine:
	var theirs: Array = []
	for i in foes:
		theirs.append(FixtureDB.make(db, "tank", 10, ["hit"]))
	return FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["twin_strike"])], theirs, 1, foes, seed_value)


func _pair(a: BattleAction) -> Array:
	var out := [a.target, a.second_target]
	out.sort()
	return out


func test_ai_picks_the_best_pair() -> void:
	var e := _twin_engine(3)
	var me: Battler = e.sides[0].active()[0]
	var foes: Array = e.sides[1].active()
	# Foe 0 is healthy; foes 1 and 2 are low enough to be knocked out together.
	foes[1].creature.hp = 1
	foes[2].creature.hp = 2
	var a := BattleAI.choose(e, me.bid, "aggressive")
	assert_str(a.move).is_equal("twin_strike")
	assert_array(_pair(a)).is_equal([foes[1].bid, foes[2].bid])


func test_ai_prefers_a_pair_with_a_knockout() -> void:
	for weak_index in 3:
		var e := _twin_engine(3)
		var me: Battler = e.sides[0].active()[0]
		var foes: Array = e.sides[1].active()
		foes[weak_index].creature.hp = 1
		var a := BattleAI.choose(e, me.bid, "aggressive")
		assert_int(a.second_target).is_not_equal(-1)
		assert_bool([a.target, a.second_target].has(foes[weak_index].bid)).is_true()


func test_basic_ai_picks_two_distinct_legal_targets() -> void:
	for s in range(1, 9):
		var e := _twin_engine(3, s)
		var me: Battler = e.sides[0].active()[0]
		var legal: Array = e.sides[1].active().map(func(f: Battler) -> int: return f.bid)
		for i in 5:
			var a := BattleAI.choose(e, me.bid, "basic")
			if a.move != "twin_strike":
				continue
			assert_bool(a.target != a.second_target).is_true()
			assert_bool(legal.has(a.target) and legal.has(a.second_target)).is_true()


func test_two_foe_case_needs_no_choice() -> void:
	var two := _twin_engine(2)
	var me: Battler = two.sides[0].active()[0]
	var foe_bids: Array = two.sides[1].active().map(func(f: Battler) -> int: return f.bid)
	foe_bids.sort()
	for style in ["aggressive", "basic"]:
		var a := BattleAI.choose(two, me.bid, style)
		if a.move == "twin_strike":
			assert_array(_pair(a)).is_equal(foe_bids)
	var one := _twin_engine(1)
	var a1 := BattleAI.choose(one, one.sides[0].active()[0].bid, "aggressive")
	assert_str(a1.move).is_equal("twin_strike")
	assert_int(a1.target).is_equal(one.sides[1].active()[0].bid)
	assert_int(a1.second_target).is_equal(-1)


func test_score_of_a_pair_includes_the_spread_value() -> void:
	var e := _twin_engine(2)
	var me: Battler = e.sides[0].active()[0]
	var foes: Array = e.sides[1].active()
	var m := db.move("twin_strike")
	var chance := minf(1.0, BattleMath.hit_chance(e, me, m) / 100.0)
	var expected := 0.0
	for f: Battler in foes:
		expected += minf(BattleAI.estimate_damage(e, me, m, f, 2), float(f.hp()))
	expected *= chance
	var pair := BattleAI.score(e, me, m, foes[0].bid, "aggressive", -1.0, foes[1].bid)
	assert_float(pair).is_equal_approx(expected, 0.001)
	# Two foes hit for the spread multiplier beat one foe hit at full power, but not two full hits.
	var single := BattleAI.score(e, me, m, foes[0].bid, "aggressive")
	assert_float(pair).is_greater(single)
