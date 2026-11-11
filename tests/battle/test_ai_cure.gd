extends GdUnitTestSuite
## How the AI scores moves with a cure_status effect.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB.move("soothe", "neutral", "status", 0, 100, "self",
		[{"op": "cure_status"}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("soothe_burn", "neutral", "status", 0, 100, "self",
		[{"op": "cure_status", "status": "burn"}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("soothe_foe", "neutral", "status", 0, 100, "one_enemy",
		[{"op": "cure_status"}], {"always_hits": true}))
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _setup() -> Array:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["soothe", "soothe_burn", "soothe_foe", "hit"])],
		[FixtureDB.make(db, "tank", 10, ["hit"])])
	return [e, e.sides[0].active()[0], e.sides[1].active()[0]]


func _score(e: BattleEngine, me: Battler, move: String, target: Battler) -> float:
	return BattleAI.score(e, me, db.move(move), target.bid, "aggressive")


func test_cure_move_scores_zero_on_a_healthy_user() -> void:
	var s := _setup()
	assert_float(_score(s[0], s[1], "soothe", s[2])).is_equal(0.0)


func test_cure_move_is_worth_the_status_when_afflicted() -> void:
	var s := _setup()
	s[1].creature.status = "burn"
	s[1].status_turns = 3
	var expected := BattleAI.status_value(s[0], s[1], "burn", BattleAI.best_damage(s[0], s[1]), 3)
	assert_float(expected).is_greater(0.0)
	assert_float(_score(s[0], s[1], "soothe", s[2])).is_equal_approx(expected, 0.001)
	assert_float(_score(s[0], s[1], "soothe_burn", s[2])).is_equal_approx(expected, 0.001)


func test_cure_is_worth_less_when_the_status_is_about_to_end() -> void:
	var s := _setup()
	s[1].creature.status = "burn"
	s[1].status_turns = 3
	var fresh := _score(s[0], s[1], "soothe", s[2])
	s[1].status_turns = 1
	var nearly_over := _score(s[0], s[1], "soothe", s[2])
	assert_float(nearly_over).is_less(fresh)
	assert_float(nearly_over).is_greater(0.0)


func test_cure_effect_with_its_own_target_scores_on_that_target() -> void:
	var s := _setup()
	s[1].creature.status = "burn"
	s[1].status_turns = 3
	var move := FixtureDB.move("strike_and_soothe", "neutral", "physical", 40, 100, "one_enemy",
		[{"op": "damage"}, {"op": "cure_status", "target": "self"}])
	var plain := FixtureDB.move("plain_strike", "neutral", "physical", 40, 100, "one_enemy", [{"op": "damage"}])
	assert_float(BattleAI.score(s[0], s[1], MoveDef.from_dict(move), s[2].bid, "aggressive")) 		.is_greater(BattleAI.score(s[0], s[1], MoveDef.from_dict(plain), s[2].bid, "aggressive"))


func test_cure_move_ignores_a_filter_mismatch() -> void:
	var s := _setup()
	s[1].creature.status = "shock"
	s[1].status_turns = 3
	assert_float(_score(s[0], s[1], "soothe_burn", s[2])).is_equal(0.0)


func test_cure_move_on_a_foe_scores_negative() -> void:
	var s := _setup()
	s[2].creature.status = "burn"
	s[2].status_turns = 3
	assert_float(_score(s[0], s[1], "soothe_foe", s[2])).is_less(0.0)
