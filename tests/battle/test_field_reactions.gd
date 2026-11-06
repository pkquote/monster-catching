extends GdUnitTestSuite
## Field states per side, passives, and reactions.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func _duel(a: String = "blob", b: String = "tank", moves_a: Array = [], moves_b: Array = []) -> BattleEngine:
	return FixtureDB.engine(db, [FixtureDB.make(db, a, 10, moves_a)], [FixtureDB.make(db, b, 10, moves_b)])


func _me(e: BattleEngine) -> int:
	return e.sides[0].active()[0].bid


func _foe(e: BattleEngine) -> int:
	return e.sides[1].active()[0].bid


func _use(e: BattleEngine, move: String, target := -1) -> Array:
	return e.resolve_round([BattleAction.use_move(_me(e), move, target if target != -1 else _foe(e))])


# --- Field container ---

func test_field_stacks_cap_and_refresh() -> void:
	var f := Field.new()
	assert_int(f.add("soaked", 1, 3, 3)).is_equal(1)
	assert_int(f.add("soaked", 5, 2, 3)).is_equal(3)
	assert_int(f.states[0].turns).is_equal(3)


func test_field_tick_expires() -> void:
	var f := Field.new()
	f.add("soaked", 1, 1, 3)
	f.add("charged", 1, 2, 3)
	assert_array(Array(f.tick())).contains_exactly(["soaked"])
	assert_array(Array(f.ids())).contains_exactly(["charged"])


# --- Applying states ---

func test_side_move_applies_to_enemy_side_only() -> void:
	var e := _duel("blob", "tank", ["drench"])
	var events := _use(e, "drench")
	assert_bool(e.sides[1].field.has("soaked")).is_true()
	assert_bool(e.sides[0].field.has("soaked")).is_false()
	assert_array(FixtureDB.events_of(events, "field_applied")).has_size(1)


func test_reapplying_adds_stacks() -> void:
	var e := _duel("blob", "tank", ["drench"])
	_use(e, "drench")
	_use(e, "drench")
	assert_int(e.sides[1].field.stacks("soaked")).is_equal(2)


func test_states_expire_at_end_of_round() -> void:
	var e := _duel("blob", "tank", ["grow", "hit"])  # overgrown lasts 2 rounds
	_use(e, "grow")
	assert_bool(e.sides[1].field.has("overgrown")).is_true()
	var events := _use(e, "hit")
	assert_bool(e.sides[1].field.has("overgrown")).is_false()
	assert_str(FixtureDB.events_of(events, "field_removed")[0].reason).is_equal("expired")


func test_fourth_state_pushes_out_oldest() -> void:
	var e := _duel("blob", "tank", ["drench", "scorch", "grow", "frost"])
	e.apply_field_state(1, "soaked", 1, 9, null, false)
	e.apply_field_state(1, "charged", 1, 9, null, false)
	e.apply_field_state(1, "frosted", 1, 9, null, false)
	e.apply_field_state(1, "overgrown", 1, 9, null, false)
	assert_array(Array(e.sides[1].field.ids())).contains_exactly(["charged", "frosted", "overgrown"])
	assert_str(FixtureDB.events_of(e.drain_events(), "field_removed")[0].reason).is_equal("replaced")


func _duel_cap(cap: int) -> BattleEngine:
	var capped := FixtureDB.build({"max_field_states": cap})
	return FixtureDB.engine(capped, [FixtureDB.make(capped, "blob")], [FixtureDB.make(capped, "tank")])


func _apply_to(e: BattleEngine, state: String, stacks := 1) -> Array:
	e.drain_events()
	e.apply_field_state(1, state, stacks, 3, null)
	return FixtureDB.events_of(e.drain_events(), "field_removed")


func test_new_state_replaces_the_old_one_at_cap_one() -> void:
	var e := _duel_cap(1)
	_apply_to(e, "soaked")
	var removed := _apply_to(e, "overgrown")
	assert_array(Array(e.sides[1].field.ids())).contains_exactly(["overgrown"])
	assert_array(removed).has_size(1)
	assert_str(removed[0].state).is_equal("soaked")
	assert_str(removed[0].reason).is_equal("replaced")


func test_first_state_at_cap_one_replaces_nothing() -> void:
	var e := _duel_cap(1)
	assert_array(_apply_to(e, "soaked")).is_empty()


func test_same_state_restacks_at_cap_one() -> void:
	var e := _duel_cap(1)
	_apply_to(e, "soaked")
	assert_array(_apply_to(e, "soaked")).is_empty()
	assert_int(e.sides[1].field.stacks("soaked")).is_equal(2)


func test_reaction_keeping_existing_state_at_cap_one() -> void:
	var e := _duel_cap(1)
	_apply_to(e, "soaked")
	_apply_to(e, "charged")  # conduction consumes the incoming charged
	assert_array(Array(e.sides[1].field.ids())).contains_exactly(["soaked"])


func test_reaction_consuming_both_empties_the_side_at_cap_one() -> void:
	var e := _duel_cap(1)
	_apply_to(e, "scorched")
	_apply_to(e, "frosted")  # steam
	assert_int(e.sides[1].field.size()).is_equal(0)


func test_cap_two_still_holds_two_states() -> void:
	var e := _duel_cap(2)
	_apply_to(e, "soaked")
	_apply_to(e, "overgrown")
	assert_array(Array(e.sides[1].field.ids())).contains_exactly(["soaked", "overgrown"])


func test_passive_incoming_type_mod_boosts_damage() -> void:
	var e := _duel("sparky", "tank", ["zap", "drench"])
	var me := e.battler(_me(e))
	var foe := e.battler(_foe(e))
	var before := BattleAI.estimate_damage(e, me, db.move("zap"), foe, 1)
	e.apply_field_state(1, "soaked", 1, 3, null, false)
	var after := BattleAI.estimate_damage(e, me, db.move("zap"), foe, 1)
	assert_float(after).is_greater(before)


func test_passive_stat_mod_slows_side() -> void:
	var e := _duel()
	var foe := e.battler(_foe(e))
	var before := BattleMath.effective_stat(e, foe, "spd")
	e.apply_field_state(1, "overgrown", 1, 3, null, false)
	assert_float(BattleMath.effective_stat(e, foe, "spd")).is_equal_approx(before * 0.5, 0.001)


func test_cash_in_move_consumes_state_for_bonus() -> void:
	var e := _duel("fish", "tank", ["riptide", "drench"])
	var me := e.battler(_me(e))
	var foe := e.battler(_foe(e))
	var plain := BattleAI.estimate_damage(e, me, db.move("riptide"), foe, 1)
	e.apply_field_state(1, "soaked", 1, 3, null, false)
	var boosted := BattleAI.estimate_damage(e, me, db.move("riptide"), foe, 1)
	assert_float(boosted).is_greater(plain * 1.8)
	var events := _use(e, "riptide")
	assert_bool(e.sides[1].field.has("soaked")).is_false()
	assert_str(FixtureDB.events_of(events, "field_removed")[0].reason).is_equal("cashed_in")


func test_clearing_own_side() -> void:
	var e := _duel("blob", "tank", ["sweep"])
	e.apply_field_state(0, "soaked", 1, 3, null, false)
	e.apply_field_state(0, "charged", 1, 3, null, false)
	_use(e, "sweep")
	assert_int(e.sides[0].field.size()).is_equal(0)


# --- Reactions ---

func test_conduction_consumes_charged_keeps_soaked_and_hits_that_side() -> void:
	var e := _duel("sparky", "tank", ["charge_up", "drench"])
	_use(e, "drench")
	var foe := e.battler(_foe(e))
	var hp_before := foe.hp()
	var events := _use(e, "charge_up")
	var reactions := FixtureDB.events_of(events, "reaction")
	assert_array(reactions).has_size(1)
	assert_str(reactions[0].reaction).is_equal("conduction")
	assert_int(reactions[0].side).is_equal(1)
	assert_bool(e.sides[1].field.has("charged")).is_false()
	assert_bool(e.sides[1].field.has("soaked")).is_true()
	assert_int(foe.hp()).is_less(hp_before)
	assert_int(e.battler(_me(e)).hp()).is_equal(e.battler(_me(e)).creature.max_hp(db))


func test_reaction_power_scales_with_stacks() -> void:
	var one := _duel("sparky", "tank")
	one.apply_field_state(1, "soaked", 1, 3, null, false)
	var ev1 := FixtureDB.events_of(_apply(one, 1, "charged", 1), "damage")
	var three := _duel("sparky", "tank")
	three.apply_field_state(1, "soaked", 1, 3, null, false)
	var ev3 := FixtureDB.events_of(_apply(three, 1, "charged", 3), "damage")
	assert_int(ev3[0].amount).is_greater(ev1[0].amount)


func test_incoming_lands_when_not_consumed() -> void:
	# Wildfire consumes overgrown; incoming scorched stays.
	var e := _duel()
	e.apply_field_state(1, "overgrown", 1, 3, null, false)
	_apply(e, 1, "scorched", 1)
	assert_array(Array(e.sides[1].field.ids())).contains_exactly(["scorched"])
	assert_str(e.battler(_foe(e)).status()).is_equal("burn")


func test_steam_hits_both_sides_and_consumes_both() -> void:
	var e := _duel()
	e.apply_field_state(1, "frosted", 1, 3, null, false)
	_apply(e, 1, "scorched", 1)
	assert_int(e.sides[1].field.size()).is_equal(0)
	assert_int(e.battler(_me(e)).stages.acc).is_equal(-1)
	assert_int(e.battler(_foe(e)).stages.acc).is_equal(-1)


func test_reaction_credits_catalyst() -> void:
	var e := _duel("sparky", "tank", ["charge_up", "drench"])
	_use(e, "drench")
	_use(e, "charge_up")
	var me := e.battler(_me(e))
	# 2 (drench applied) + 4 (reaction)
	assert_int(me.creature.affinity.catalyst).is_equal(6)


func _apply(e: BattleEngine, side: int, state: String, stacks: int) -> Array:
	e.drain_events()
	e.apply_field_state(side, state, stacks, 0, e.battler(_me(e)))
	return e.drain_events()
