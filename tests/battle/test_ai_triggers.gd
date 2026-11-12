extends GdUnitTestSuite
## How the battle AI prices knockout, faint, status, round-end and enter triggers. HP effects count the same for
## both styles; setup effects (stat stages, field states, energy) count half as much for the aggressive style.

const HEAL := [{"op": "heal", "fraction": 0.25}]
const STYLES := ["tactician", "aggressive"]

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB.move("twin_hit", "neutral", "physical", 50, 100, "two_enemies",
		[{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("triple", "neutral", "physical", 20, 100, "one_enemy",
		[{"op": "damage"}], {"hits": {"min": 3, "max": 3}}))
	r.add_entry("moves", FixtureDB.move("smack_ally", "neutral", "physical", 50, 100, "one_ally",
		[{"op": "damage"}]))
	for p in [
		{"id": "ko_heal", "triggers": [{"on": "knockout", "effects": HEAL}]},
		{"id": "ko_speed", "triggers": [{"on": "knockout", "effects": [{"op": "stat_stage", "stat": "spd", "stages": 1}]}]},
		{"id": "ko_when_low", "triggers": [{"on": "knockout", "when": {"hp_below": 0.5}, "effects": HEAL}]},
		{"id": "ko_half", "triggers": [{"on": "knockout", "chance": 50, "effects": HEAL}]},
		{"id": "faint_burn", "triggers": [{"on": "faint", "effects": [{"op": "damage", "power": 40}]}]},
		{"id": "faint_soak", "triggers": [{"on": "faint",
			"effects": [{"op": "apply_field_state", "side": "enemy", "state": "soaked"}]}]},
		{"id": "faint_ally", "triggers": [{"on": "faint",
			"effects": [{"op": "heal", "fraction": 0.5, "target": "all_allies"}]}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	r.add_entry("items", {"id": "ko_charm", "name": "Ko Charm", "description": "Test held item.",
		"category": "held", "price": 10,
		"held": {"use": "per_battle", "triggers": [{"on": "knockout", "effects": HEAL}]}})
	r.add_entry("moves", FixtureDB.move("ignite", "fire", "status", 0, 100, "one_enemy",
		[{"op": "apply_status", "status": "burn"}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("ignite_half", "fire", "status", 0, 100, "one_enemy",
		[{"op": "apply_status", "status": "burn", "chance": 50}], {"always_hits": true}))
	r.add_entry("field_states", {"id": "ward", "name": "Ward", "max_stacks": 3, "default_turns": 3,
		"passive": [{"op": "stat_mod", "stat": "patk", "mult": 1.2}]})
	var soak := [{"op": "apply_field_state", "side": "enemy", "state": "soaked"}]
	var ward := [{"op": "apply_field_state", "side": "own", "state": "ward"}]
	for p in [
		{"id": "taunt", "triggers": [{"on": "status", "effects": [{"op": "stat_stage", "stat": "patk", "stages": 1}]}]},
		{"id": "taunt_half", "triggers": [{"on": "status", "chance": 50,
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": 1}]}]},
		{"id": "thorn_status", "triggers": [{"on": "status", "effects": [{"op": "damage", "power": 30}]}]},
		{"id": "pure", "effects": [{"op": "status_immune"}]},
		{"id": "photo", "triggers": [{"on": "round_end", "effects": HEAL}]},
		{"id": "welcome_soak", "triggers": [{"on": "enter", "effects": soak}]},
		{"id": "welcome_soak_half", "triggers": [{"on": "enter", "chance": 50, "effects": soak}]},
		{"id": "welcome_ward", "triggers": [{"on": "enter", "effects": ward}]},
		{"id": "welcome_when", "triggers": [{"on": "enter", "when": {"hp_below": 0.5}, "effects": ward}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	r.add_entry("items", {"id": "taunt_charm", "name": "Taunt Charm", "description": "Test held item.",
		"category": "held", "price": 10,
		"held": {"triggers": [{"on": "status", "effects": [{"op": "stat_stage", "stat": "patk", "stages": 1}]}]}})
	for p in [
		{"id": "faint_snipe", "triggers": [{"on": "faint",
			"effects": [{"op": "damage", "power": 40, "target": "one_enemy"}]}]},
		{"id": "ko_buddy", "triggers": [{"on": "knockout",
			"effects": [{"op": "heal", "fraction": 0.25, "target": "one_ally"}]}]},
		{"id": "cure_on_status", "triggers": [{"on": "status", "effects": [{"op": "cure_status"}]}]},
		{"id": "punisher", "triggers": [{"on": "status",
			"effects": [{"op": "damage", "power": 30, "target": "attacker"}]}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	r.add_entry("items", {"id": "welcome_charm", "name": "Welcome Charm", "description": "Test held item.",
		"category": "held", "price": 10,
		"held": {"triggers": [{"on": "enter", "effects": [{"op": "apply_field_state", "side": "own", "state": "ward"}]}]}})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive := "", moves: Array = ["hit"], held := "") -> CreatureInstance:
	var c := FixtureDB.make(db, species, 10, moves)
	c.passive = passive
	c.held_item = held
	return c


func _me(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foe(e: BattleEngine) -> Battler:
	return e.sides[1].active()[0]


## 1v1: side 0 is a blob at `my_hp` of its max HP, side 1 a tank with `foe_hp` HP (-1: full).
func _engine(my_passive := "", foe_passive := "", my_hp := 0.5, foe_hp := 1, my_held := "") -> BattleEngine:
	var e := FixtureDB.engine(db, [_make("blob", my_passive, ["hit"], my_held)], [_make("tank", foe_passive)])
	_me(e).creature.hp = roundi(my_hp * _me(e).creature.max_hp(db))
	if foe_hp >= 0:
		_foe(e).creature.hp = foe_hp
	return e


func _score(e: BattleEngine, style: String, move := "hit") -> float:
	return BattleAI.score(e, _me(e), db.move(move), _foe(e).bid, style)


func _ref(e: BattleEngine) -> float:
	return BattleAI.best_damage(e, _me(e))


## HP the faint_burn trigger would do to side 0's blob (what the AI would be charged).
func _burn_cost(e: BattleEngine, holder: Battler) -> float:
	var eff: Dictionary = db.passive("faint_burn").triggers[0].effects[0]
	var ctx := EffectContext.new()
	ctx.engine = e
	ctx.user = holder
	ctx.source = "passive"
	ctx.attacker = _me(e)
	ctx.targets.append(_me(e))
	return minf(float(_me(e).hp()), float(BattleMath.damage(e, ctx, eff, _me(e), false).amount))


# --- knockout ---

func test_a_finishing_move_is_credited_with_the_users_knockout_trigger() -> void:
	for s: String in STYLES:
		var with := _score(_engine("ko_heal"), s)
		var without := _score(_engine(""), s)
		var max_hp := float(_me(_engine("")).creature.max_hp(db))
		assert_float(with - without).override_failure_message(s).is_equal_approx(0.25 * max_hp, 0.01)


func test_the_knockout_term_is_only_for_a_lethal_hit() -> void:
	for s: String in STYLES:
		assert_float(_score(_engine("ko_heal", "", 0.5, -1), s)).is_equal(_score(_engine("", "", 0.5, -1), s))


func test_setup_effects_scale_with_ref_and_by_style() -> void:
	var e := _engine("ko_speed")
	var step := float(BattleAI.DEBUFF_VALUE["spd"]) * _ref(e)
	var base_t := _score(_engine(""), "tactician")
	var base_a := _score(_engine(""), "aggressive")
	assert_float(_score(e, "tactician") - base_t).is_equal_approx(step, 0.001)
	assert_float(_score(e, "aggressive") - base_a).is_equal_approx(BattleAI.AGGRESSIVE_SETUP_MULT * step, 0.001)


func test_hp_effects_are_valued_equally_by_both_styles() -> void:
	var e := _engine("ko_heal")
	var plain := _engine("")
	assert_float(_score(e, "tactician") - _score(plain, "tactician")).is_equal_approx(
		_score(e, "aggressive") - _score(plain, "aggressive"), 0.001)


func test_a_failing_when_or_a_spent_item_is_worth_nothing() -> void:
	for s: String in STYLES:
		# At 60% HP a heal would be worth something, so only the failing `when` keeps it at 0.
		var base := _score(_engine("", "", 0.6), s)
		assert_float(_score(_engine("ko_when_low", "", 0.6), s)).is_equal(base)
		assert_float(_score(_engine("ko_when_low", "", 0.4), s)).is_greater(_score(_engine("", "", 0.4), s))
		var held := _engine("", "", 0.5, 1, "ko_charm")
		assert_float(_score(held, s)).is_greater(_score(_engine(""), s))
		_me(held).held_spent = true
		assert_float(_score(held, s)).is_equal(_score(_engine(""), s))


func test_chance_weights_the_trigger() -> void:
	var full := _score(_engine("ko_heal"), "tactician") - _score(_engine(""), "tactician")
	var half := _score(_engine("ko_half"), "tactician") - _score(_engine(""), "tactician")
	assert_float(half).is_equal_approx(full / 2.0, 0.001)


func test_a_heal_trigger_at_full_hp_is_worth_nothing() -> void:
	for s: String in STYLES:
		assert_float(_score(_engine("ko_heal", "", 1.0), s)).is_equal(_score(_engine("", "", 1.0), s))


# --- faint ---

func test_the_targets_faint_trigger_is_charged_to_the_killer() -> void:
	for s: String in STYLES:
		var e := _engine("", "faint_burn")
		var cost := _burn_cost(e, _foe(e))
		assert_float(cost).is_greater(0.0)
		assert_float(_score(e, s) - _score(_engine(""), s)).override_failure_message(s).is_equal_approx(-cost, 0.01)


func test_a_hostile_field_state_on_our_side_is_a_cost() -> void:
	var e := _engine("", "faint_soak")
	var step := BattleAI.NEW_STATE * _ref(e)
	assert_float(_score(e, "tactician") - _score(_engine(""), "tactician")).is_equal_approx(-step, 0.001)
	assert_float(_score(e, "aggressive") - _score(_engine(""), "aggressive")).is_equal_approx(
		-BattleAI.AGGRESSIVE_SETUP_MULT * step, 0.001)


func test_a_faint_trigger_with_its_own_target_is_charged_there() -> void:
	for s: String in STYLES:
		var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "faint_ally"), _make("tank")], 1, 2)
		var plain := FixtureDB.engine(db, [_make("blob")], [_make("tank"), _make("tank")], 1, 2)
		for engine: BattleEngine in [e, plain]:
			engine.sides[1].active()[0].creature.hp = 1
			var other: Battler = engine.sides[1].active()[1]
			other.creature.hp = other.creature.max_hp(db) / 2
		var other: Battler = e.sides[1].active()[1]
		var healed := minf(float(other.creature.max_hp(db) - other.hp()), 0.5 * other.creature.max_hp(db))
		var score_e := BattleAI.score(e, _me(e), db.move("hit"), _foe(e).bid, s)
		var score_p := BattleAI.score(plain, _me(plain), db.move("hit"), _foe(plain).bid, s)
		# The fainting holder itself is not healed; its standing ally is, and that is bad for the AI.
		assert_float(score_e - score_p).override_failure_message(s).is_equal_approx(-healed, 0.01)
		# Alone, there is nobody to heal.
		assert_float(_score(_engine("", "faint_ally"), s)).is_equal(_score(_engine(""), s))


func test_finishing_an_ally_pays_the_faint_term_only() -> void:
	var build := func(my_passive: String, ally_passive: String) -> BattleEngine:
		var e := FixtureDB.engine(db, [_make("blob", my_passive, ["smack_ally"]), _make("tank", ally_passive)],
			[_make("tank")], 2, 1)
		e.sides[0].active()[1].creature.hp = 1
		return e
	for s: String in STYLES:
		var plain: BattleEngine = build.call("", "")
		var greedy: BattleEngine = build.call("ko_heal", "")
		var burnt: BattleEngine = build.call("", "faint_burn")
		var score := func(e: BattleEngine) -> float:
			return BattleAI.score(e, _me(e), db.move("smack_ally"), e.sides[0].active()[1].bid, s)
		assert_float(score.call(greedy)).is_equal(score.call(plain))
		var cost := _burn_cost(burnt, burnt.sides[0].active()[1])
		assert_float(score.call(burnt) - score.call(plain)).is_equal_approx(-cost, 0.01)


func test_each_finished_target_pays_once() -> void:
	for s: String in STYLES:
		var e := FixtureDB.engine(db, [_make("blob", "", ["twin_hit"])],
			[_make("tank", "faint_burn"), _make("tank", "faint_burn")], 1, 2)
		var plain := FixtureDB.engine(db, [_make("blob", "", ["twin_hit"])], [_make("tank"), _make("tank")], 1, 2)
		for engine: BattleEngine in [e, plain]:
			for foe: Battler in engine.sides[1].active():
				foe.creature.hp = 1
		var cost := _burn_cost(e, e.sides[1].active()[0])
		var foes: Array[Battler] = e.sides[1].active()
		var plain_foes: Array[Battler] = plain.sides[1].active()
		var diff := BattleAI.score(e, _me(e), db.move("twin_hit"), foes[0].bid, s, -1.0, foes[1].bid) \
			- BattleAI.score(plain, _me(plain), db.move("twin_hit"), plain_foes[0].bid, s, -1.0, plain_foes[1].bid)
		assert_float(diff).override_failure_message(s).is_equal_approx(-2.0 * cost, 0.01)


func test_a_multi_hit_finisher_is_credited_once() -> void:
	var e := _engine("ko_heal")
	var plain := _engine("")
	var gain := _score(e, "tactician", "triple") - _score(plain, "tactician", "triple")
	var single := _score(e, "tactician") - _score(plain, "tactician")
	assert_float(gain).is_equal_approx(single, 0.01)


# --- invariants ---

func test_scoring_never_draws_from_the_rng() -> void:
	for pair: Array in [["ko_heal", ""], ["", "faint_burn"], ["", "faint_soak"], ["ko_speed", "faint_ally"]]:
		var e := _engine(pair[0], pair[1])
		var before_state := e.rng.state
		for s: String in STYLES:
			_score(e, s)
		assert_int(e.rng.state).is_equal(before_state)


func test_the_basic_style_scores_as_before() -> void:
	for pair: Array in [["ko_heal", ""], ["", "faint_burn"], ["", "faint_soak"]]:
		assert_float(_score(_engine(pair[0], pair[1]), "basic")).is_equal(_score(_engine(""), "basic"))


# --- status ---

## `ignite` (or `move`) from the blob against a tank holding `foe_passive`, the tank at full HP.
func _status_delta(foe_passive: String, style: String, move := "ignite") -> float:
	return _score(_engine("", foe_passive, 0.5, -1), style, move) - _score(_engine("", "", 0.5, -1), style, move)


func test_a_status_move_into_a_punishing_status_trigger_scores_lower() -> void:
	var step := float(BattleAI.DEBUFF_VALUE["patk"]) * _ref(_engine("", "", 0.5, -1))
	assert_float(_status_delta("taunt", "tactician")).is_equal_approx(-step, 0.001)
	assert_float(_status_delta("taunt", "aggressive")).is_equal_approx(-BattleAI.AGGRESSIVE_SETUP_MULT * step, 0.001)


func test_aggressive_never_seeks_a_status_for_its_trigger() -> void:
	# thorn_status hurts the foe that was statused: the tactician takes the bonus, aggressive only avoids costs.
	assert_float(_status_delta("thorn_status", "tactician")).is_greater(0.0)
	assert_float(_status_delta("thorn_status", "aggressive")).is_equal(0.0)


func test_status_term_weights_both_chances() -> void:
	var full := _status_delta("taunt", "tactician", "ignite")
	assert_float(_status_delta("taunt_half", "tactician", "ignite_half")).is_equal_approx(full / 4.0, 0.001)


func test_no_status_term_when_the_status_cannot_land() -> void:
	for s: String in STYLES:
		# The foe already has a status.
		var burnt := _engine("", "taunt", 0.5, -1)
		_foe(burnt).creature.status = "shock"
		var burnt_plain := _engine("", "", 0.5, -1)
		_foe(burnt_plain).creature.status = "shock"
		assert_float(_score(burnt, s, "ignite")).is_equal(_score(burnt_plain, s, "ignite"))
		# The foe is immune to statuses (and would otherwise be punished by its held item).
		var immune := FixtureDB.engine(db, [_make("blob")], [_make("tank", "pure", ["hit"], "taunt_charm")])
		var immune_plain := FixtureDB.engine(db, [_make("blob")], [_make("tank", "pure")])
		assert_float(_score(immune, s, "ignite")).is_equal(_score(immune_plain, s, "ignite"))


# --- round_end ---

func test_own_round_end_healing_lowers_heal_urgency() -> void:
	for s: String in STYLES:
		var with := _engine("photo", "", 0.4)
		var without := _engine("", "", 0.4)
		var max_hp := float(_me(with).creature.max_hp(db))
		assert_float(_score(without, s, "mend")).is_equal_approx(0.5 * max_hp, 0.01)
		assert_float(_score(with, s, "mend")).is_equal_approx((0.6 - 0.25) * max_hp, 0.01)


func test_a_foes_round_end_heal_lowers_a_non_lethal_hit_only() -> void:
	for s: String in STYLES:
		var plain := _engine("", "", 0.5, -1)
		var est := BattleAI.estimate_damage(plain, _me(plain), db.move("hit"), _foe(plain), 1)
		var max_hp := float(_foe(plain).creature.max_hp(db))
		assert_float(max_hp).is_greater(est + 10.0)
		var hp := roundi(est) + 10
		var photo := _engine("", "photo", 0.5, hp)
		var plain_hurt := _engine("", "", 0.5, hp)
		var heal := minf(max_hp - float(hp - roundi(est)), 0.25 * max_hp)
		var drop := _score(plain_hurt, s) - _score(photo, s)
		assert_float(drop).override_failure_message(s).is_equal_approx(minf(est, heal), 0.01)
		# A lethal hit is not helped by a heal that comes after it.
		assert_float(_score(_engine("", "photo"), s)).is_equal(_score(_engine(""), s))


# --- enter ---

## Side 0: the blob fielded with a bench creature; side 1: a tank. The passives are set after the battle
## starts, so their enter triggers have not fired (and left field states behind).
func _enter_engine(bench_passive := "", foe_passive := "") -> BattleEngine:
	var e := FixtureDB.engine(db, [_make("blob"), _make("tank")], [_make("tank")], 1, 1)
	e.sides[0].bench()[0].creature.passive = bench_passive
	_foe(e).creature.passive = foe_passive
	return e


func test_enter_value_signs_and_scale() -> void:
	var e := _enter_engine("welcome_soak", "welcome_soak")
	var ref := BattleAI.best_damage(e, _me(e))
	var ally: Battler = e.sides[0].bench()[0]
	assert_float(BattleAI.enter_value(e, _me(e), ally)).is_equal_approx(BattleAI.NEW_STATE * ref, 0.001)
	assert_float(BattleAI.enter_value(e, _me(e), _foe(e))).is_equal_approx(-BattleAI.NEW_STATE * ref, 0.001)
	assert_float(BattleAI.enter_value(e, _me(e), ally, "aggressive")).is_equal_approx(
		BattleAI.AGGRESSIVE_SETUP_MULT * BattleAI.NEW_STATE * ref, 0.001)
	var ward := _enter_engine("welcome_ward", "welcome_ward")
	var ward_ref := BattleAI.best_damage(ward, _me(ward))
	assert_float(BattleAI.enter_value(ward, _me(ward), ward.sides[0].bench()[0])).is_equal_approx(
		BattleAI.OWN_BUFF * ward_ref, 0.001)
	assert_float(BattleAI.enter_value(ward, _me(ward), _foe(ward))).is_equal_approx(-BattleAI.OWN_BUFF * ward_ref, 0.001)


func test_enter_value_is_zero_without_a_trigger_or_when_the_when_fails() -> void:
	var none := _enter_engine()
	assert_float(BattleAI.enter_value(none, _me(none), none.sides[0].bench()[0])).is_equal(0.0)
	var when := _enter_engine("welcome_when")
	var bench: Battler = when.sides[0].bench()[0]
	assert_float(BattleAI.enter_value(when, _me(when), bench)).is_equal(0.0)
	bench.creature.hp = bench.creature.max_hp(db) / 4
	assert_float(BattleAI.enter_value(when, _me(when), bench)).is_greater(0.0)


func test_enter_value_is_weighted_by_chance() -> void:
	var full := _enter_engine("welcome_soak")
	var half := _enter_engine("welcome_soak_half")
	assert_float(BattleAI.enter_value(half, _me(half), half.sides[0].bench()[0])).is_equal_approx(
		BattleAI.enter_value(full, _me(full), full.sides[0].bench()[0]) / 2.0, 0.001)


func test_restacking_a_hostile_state_on_our_side_is_a_cost() -> void:
	# The foe's real enter trigger fired at battle start, so soaked is already on our side.
	var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "welcome_soak")])
	assert_bool(e.sides[0].field.has("soaked")).is_true()
	var ref := BattleAI.best_damage(e, _me(e))
	assert_float(BattleAI.enter_value(e, _me(e), _foe(e))).is_equal_approx(-BattleAI.RESTACK * ref, 0.001)


# --- shipped content ---

func test_shipped_triggers_move_the_score() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert_array(Array(result.errors)).is_empty()
	var real: Database = result.db
	var score := func(mine: String, foe: String, style: String) -> float:
		var user := FixtureDB.make(real, "tidepup", 20, ["splash_jab"])
		user.passive = mine
		var target := FixtureDB.make(real, "pebblet", 20, ["splash_jab"])
		target.passive = foe
		var e := FixtureDB.engine(real, [user], [target])
		e.sides[1].active()[0].creature.hp = 1
		e.sides[0].active()[0].creature.energy = 0
		return BattleAI.score(e, e.sides[0].active()[0], real.move("splash_jab"), e.sides[1].active()[0].bid, style)
	for s: String in STYLES:
		var base: float = score.call("", "", s)
		assert_float(score.call("cold_snap", "", s)).override_failure_message("cold_snap " + s).is_greater(base)
		assert_float(score.call("finisher", "", s)).override_failure_message("finisher " + s).is_greater(base)
		assert_float(score.call("", "ember_trail", s)).override_failure_message("ember_trail " + s).is_less(base)


# --- review fixes ---

func test_scoring_a_trigger_with_a_chosen_target_never_draws_from_the_rng() -> void:
	# one_enemy / one_ally effects pick a random creature in the engine; the AI must not roll for it.
	# 2v2, so each random pick has two candidates (a one-candidate pick draws nothing).
	var e := FixtureDB.engine(db, [_make("blob", "ko_buddy"), _make("tank")],
		[_make("tank", "faint_snipe"), _make("tank")], 2, 2)
	var foes: Array[Battler] = e.sides[1].active()
	foes[0].creature.hp = 1
	var before_state := e.rng.state
	for s: String in STYLES:
		BattleAI.score(e, _me(e), db.move("hit"), foes[0].bid, s)
	assert_int(e.rng.state).is_equal(before_state)


func test_a_status_trigger_that_punishes_the_attacker_is_a_cost() -> void:
	for s: String in STYLES:
		var e := _engine("", "punisher", 0.5, -1)
		var eff: Dictionary = db.passive("punisher").triggers[0].effects[0]
		var ctx := EffectContext.new()
		ctx.engine = e
		ctx.user = _foe(e)
		ctx.source = "passive"
		ctx.attacker = _me(e)
		ctx.targets.append(_me(e))
		var cost := minf(float(_me(e).hp()), float(BattleMath.damage(e, ctx, eff, _me(e), false).amount))
		assert_float(cost).is_greater(0.0)
		assert_float(_status_delta("punisher", s)).override_failure_message(s).is_equal_approx(-cost, 0.01)


func test_a_cure_on_status_trigger_cancels_the_status() -> void:
	var e := _engine("", "cure_on_status", 0.5, -1)
	# The tactician's credit for the burn is offset by the cure the foe's trigger gives it at once.
	assert_float(_score(e, "tactician", "ignite")).is_equal_approx(0.0, 0.001)
	assert_float(_score(e, "aggressive", "ignite")).is_less(0.0)


func test_enter_value_reads_a_benched_creatures_held_item() -> void:
	var e := _enter_engine()
	var bench: Battler = e.sides[0].bench()[0]
	bench.creature.held_item = "welcome_charm"
	var ref := BattleAI.best_damage(e, _me(e))
	assert_float(BattleAI.enter_value(e, _me(e), bench)).is_equal_approx(BattleAI.OWN_BUFF * ref, 0.001)
