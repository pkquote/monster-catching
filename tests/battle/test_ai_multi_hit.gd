extends GdUnitTestSuite
## The battle AI scores a multi-hit move by its expected number of hits.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	var dmg := [{"op": "damage"}]
	for spec: Array in [
		["single", dmg, {}],
		["triple", dmg, {"hits": {"min": 3, "max": 3}}],
		["flurry", dmg, {"hits": {"min": 2, "max": 5}}],
	]:
		r.add_entry("moves", FixtureDB.move(spec[0], "neutral", "physical", 20, 100, "one_enemy", spec[1], spec[2]))
	var thorns := {"id": "thorns", "name": "Thorns", "description": "Test passive.",
		"triggers": [{"on": "hit", "effects": [{"op": "damage", "power": 200, "target": "attacker"}]}]}
	r.add_entry("passives", thorns)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _engine(foe_passive := "") -> BattleEngine:
	var foe := FixtureDB.make(db, "tank", 10, ["hit"])
	foe.passive = foe_passive
	return FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["single", "triple", "flurry"])], [foe], 1, 1)


func _user(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foe(e: BattleEngine) -> Battler:
	return e.sides[1].active()[0]


func _estimate(e: BattleEngine, move: String) -> float:
	return BattleAI.estimate_damage(e, _user(e), db.move(move), _foe(e), 1)


func _score(e: BattleEngine, move: String, style := "aggressive") -> float:
	return BattleAI.score(e, _user(e), db.move(move), _foe(e).bid, style)


func test_estimate_is_per_hit_damage_times_the_mean_hit_count() -> void:
	var e := _engine()
	var per_hit := _estimate(e, "single")
	assert_float(_estimate(e, "flurry")).is_equal_approx(per_hit * 3.5, 0.001)
	assert_float(_estimate(e, "triple")).is_equal_approx(per_hit * 3.0, 0.001)


func test_a_single_hit_move_estimates_as_before() -> void:
	var e := _engine()
	var ctx := EffectContext.new()
	ctx.engine = e
	ctx.user = _user(e)
	ctx.source = "move"
	ctx.move = db.move("single")
	ctx.targets.append(_foe(e))
	var direct: int = BattleMath.damage(e, ctx, {"op": "damage"}, _foe(e), false).amount
	assert_float(_estimate(e, "single")).is_equal(float(direct))


func test_the_ai_prefers_a_multi_hit_move_to_an_equal_single_hit_one() -> void:
	var e := _engine()
	assert_float(_score(e, "triple")).is_greater(_score(e, "single"))
	var action := BattleAI.choose(e, _user(e).bid, "aggressive")
	assert_str(action.move).is_not_equal("single")


func test_retaliation_counts_per_expected_hit() -> void:
	var calm := _engine()
	var spiky := _engine("thorns")
	var single_drop := _score(calm, "single", "tactician") - _score(spiky, "single", "tactician")
	var triple_drop := _score(calm, "triple", "tactician") - _score(spiky, "triple", "tactician")
	assert_float(single_drop).is_greater(0.0)
	assert_float(triple_drop).is_greater(single_drop * 2.5)
