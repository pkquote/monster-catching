extends GdUnitTestSuite
## Catching, items, fleeing, and tamer battle setup.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func _wild(items: Dictionary = {"cage": 3, "net": 3, "master_cage": 1, "potion": 2}, seed_value := 1) -> BattleEngine:
	return FixtureDB.engine(db, [FixtureDB.make(db, "fish"), FixtureDB.make(db, "blob")],
		[FixtureDB.make(db, "blob", 5)], -1, -1, seed_value, true, items)


func _me(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _wild_one(e: BattleEngine) -> Battler:
	return e.sides[1].active()[0]


func test_catch_chance_formula() -> void:
	var e := _wild()
	var t := _wild_one(e)
	# Full HP: 0.5 base * 1.0 * (1 - 0.8) = 0.1
	assert_float(BattleMath.capture_chance(e, t, {"mult": 1.0})).is_equal_approx(0.1, 0.0001)
	t.creature.hp = 0 + 1
	var low := BattleMath.capture_chance(e, t, {"mult": 1.0})
	assert_float(low).is_greater(0.45)


func test_status_raises_catch_chance() -> void:
	var e := _wild()
	var t := _wild_one(e)
	var plain := BattleMath.capture_chance(e, t, {"mult": 1.0})
	t.creature.status = "burn"
	assert_float(BattleMath.capture_chance(e, t, {"mult": 1.0})).is_equal_approx(plain * 1.5, 0.0001)


func test_field_bonus_only_on_matching_state() -> void:
	var e := _wild()
	var t := _wild_one(e)
	var net: Dictionary = db.item("net").effects[0]
	var dry := BattleMath.capture_chance(e, t, net)
	e.apply_field_state(1, "soaked", 1, 3, null, false)
	assert_float(BattleMath.capture_chance(e, t, net)).is_equal_approx(dry * 3.0, 0.0001)
	# The bonus checks the target's side, not the thrower's.
	var e2 := _wild()
	e2.apply_field_state(0, "soaked", 1, 3, null, false)
	assert_float(BattleMath.capture_chance(e2, _wild_one(e2), net)).is_equal_approx(dry, 0.0001)


func test_successful_capture_ends_battle_with_creature() -> void:
	var e := _wild()
	var t := _wild_one(e)
	var events := e.resolve_round([BattleAction.use_item(_me(e).bid, "master_cage", t.bid)])
	assert_array(FixtureDB.events_of(events, "captured")).has_size(1)
	assert_bool(e.is_over()).is_true()
	var res := e.result()
	assert_int(res.winner).is_equal(0)
	assert_array(res.captured).has_size(1)
	assert_object(res.captured[0]).is_same(t.creature)
	assert_int(e.sides[0].items.master_cage).is_equal(0)


func test_cannot_use_missing_item() -> void:
	var e := _wild({})
	var events := e.resolve_round([BattleAction.use_item(_me(e).bid, "cage", _wild_one(e).bid)])
	assert_str(FixtureDB.events_of(events, "action_invalid")[0].reason).is_equal("no_item")


func test_capture_items_rejected_in_tamer_battle() -> void:
	var setup := BattleSetup.vs_tamer(db, [FixtureDB.make(db, "fish", 10), FixtureDB.make(db, "blob", 10)], "t1", -1, {"cage": 1})
	var rng := RandomNumberGenerator.new()
	var e := BattleEngine.new(db, rng, setup)
	e.start()
	var events := e.resolve_round([BattleAction.use_item(_me(e).bid, "cage", _wild_one(e).bid)])
	assert_str(FixtureDB.events_of(events, "action_invalid")[0].reason).is_equal("not_wild")
	assert_int(e.sides[0].items.cage).is_equal(1)


func test_training_items_hidden_and_refused_in_battle() -> void:
	var e := _wild({"seed": 1, "potion": 1})
	var events := e.resolve_round([BattleAction.use_item(_me(e).bid, "seed", _me(e).bid)])
	assert_str(FixtureDB.events_of(events, "action_invalid")[0].reason).is_equal("field_only")
	assert_int(e.sides[0].items.seed).is_equal(1)
	assert_array(FixtureDB.events_of(events, "item_used")).is_empty()


func test_potion_heals_benched_ally() -> void:
	var e := _wild()
	var benched: Battler = e.sides[0].bench()[0]
	benched.creature.hp = 1
	e.resolve_round([BattleAction.use_item(_me(e).bid, "potion", benched.bid)])
	assert_int(benched.hp()).is_equal(1 + roundi(benched.creature.max_hp(db) * 0.5))


func test_items_act_before_moves() -> void:
	var e := _wild()
	var events := e.resolve_round([BattleAction.use_item(_me(e).bid, "potion", _me(e).bid),
		BattleAction.use_move(_wild_one(e).bid, "hit", _me(e).bid)])
	assert_str(events[1].type).is_equal("item_used")


func test_flee_from_wild_battle() -> void:
	var e := _wild()
	e.resolve_round([BattleAction.flee(_me(e).bid)])
	assert_bool(e.is_over()).is_true()
	assert_str(e.result().reason).is_equal("fled")


func test_cannot_flee_tamer_battle() -> void:
	var setup := BattleSetup.vs_tamer(db, [FixtureDB.make(db, "fish", 10)], "t1")
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), setup)
	e.start()
	var events := e.resolve_round([BattleAction.flee(_me(e).bid)])
	assert_str(FixtureDB.events_of(events, "action_invalid")[0].reason).is_equal("cannot_flee")
	assert_bool(e.is_over()).is_false()


func test_tamer_format_and_fewer_fielded_creatures() -> void:
	var party := [FixtureDB.make(db, "fish", 10), FixtureDB.make(db, "blob", 10)]
	var setup := BattleSetup.vs_tamer(db, party, "t1", 1)
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), setup)
	e.start()
	assert_array(e.sides[1].active()).has_size(2)
	assert_array(e.sides[0].active()).has_size(1)
	assert_int(e.sides[0].underdog.bonus_actions).is_equal(1)


func test_tamer_xp_is_boosted() -> void:
	var b := db.balance
	assert_int(Stats.xp_reward(b, 50, 10, true, 0.0)).is_equal(int(Stats.xp_reward(b, 50, 10, false, 0.0) * 1.5))


func test_held_items_refused_as_bag_items() -> void:
	var raw := FixtureDB.raw()
	raw.add_entry("items", {"id": "charm", "name": "Charm", "category": "held", "price": 10,
		"held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}})
	var held_db := Database.from_raw(raw)
	var e := FixtureDB.engine(held_db, [FixtureDB.make(held_db, "fish")], [FixtureDB.make(held_db, "blob", 5)],
		-1, -1, 1, true, {"charm": 1, "potion": 1})
	var events := e.resolve_round([BattleAction.use_item(_me(e).bid, "charm", _me(e).bid)])
	assert_str(FixtureDB.events_of(events, "action_invalid")[0].reason).is_equal("held_item")
	assert_int(e.sides[0].items.charm).is_equal(1)
	assert_array(FixtureDB.events_of(events, "item_used")).is_empty()
