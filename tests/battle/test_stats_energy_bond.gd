extends GdUnitTestSuite
## Physical/Special split, energy and Rest, Resolve, Endure and Bond in battle.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func _duel(a: String, b: String, moves_a: Array = [], seed_value := 1, use_db: Database = null) -> BattleEngine:
	var d := use_db if use_db != null else db
	return FixtureDB.engine(d, [FixtureDB.make(d, a, 10, moves_a)], [FixtureDB.make(d, b, 10, ["hit"])],
		-1, -1, seed_value)


func _me(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foe(e: BattleEngine) -> Battler:
	return e.sides[1].active()[0]


func _act(e: BattleEngine, move: String) -> Array:
	return e.resolve_round([BattleAction.use_move(_me(e).bid, move, _foe(e).bid)])


# --- Physical / Special ---

func test_special_moves_use_special_defense() -> void:
	var e := _duel("blob", "shell", ["hit", "blast"])
	var physical := BattleAI.estimate_damage(e, _me(e), db.move("hit"), _foe(e), 1)
	var special := BattleAI.estimate_damage(e, _me(e), db.move("blast"), _foe(e), 1)
	assert_float(special).is_greater(physical * 3.0)


func test_stat_pair_by_category() -> void:
	var ctx := EffectContext.new()
	ctx.move = db.move("hit")
	assert_array(BattleMath.stat_pair(ctx)).is_equal(["patk", "pdef"])
	ctx.move = db.move("blast")
	assert_array(BattleMath.stat_pair(ctx)).is_equal(["satk", "sdef"])


# --- Energy ---

func test_moves_spend_energy() -> void:
	var e := _duel("blob", "tank", ["hit"])
	var before := _me(e).energy()
	var events := _act(e, "hit")
	assert_int(_me(e).energy()).is_equal(before - 2)
	assert_int(FixtureDB.events_of(events, "energy")[0].change).is_equal(-2)


func test_cannot_use_move_without_energy() -> void:
	var e := _duel("blob", "tank", ["big_hit"])
	var events := _act(e, "big_hit")  # costs 25 of 30
	events = _act(e, "big_hit")
	assert_str(FixtureDB.events_of(events, "action_invalid")[0].reason).is_equal("no_energy")


func test_scrap_is_always_available() -> void:
	var e := _duel("blob", "tank", ["hit"])
	_me(e).creature.energy = 0
	assert_array(Array(e.usable_moves(_me(e).bid))).is_equal(["scrap"])
	var events := _act(e, "scrap")
	assert_array(FixtureDB.events_of(events, "damage")).has_size(1)


func test_rest_restores_a_quarter() -> void:
	var e := _duel("blob", "tank", ["hit"])
	var me := _me(e)
	me.creature.energy = 0
	e.resolve_round([BattleAction.rest(me.bid)])
	assert_int(me.energy()).is_equal(roundi(me.creature.max_energy(db) * 0.25))


func test_energy_persists_on_the_instance() -> void:
	var mine := FixtureDB.make(db, "blob", 10, ["hit"])
	var e := FixtureDB.engine(db, [mine], [FixtureDB.make(db, "tank")])
	e.resolve_round([BattleAction.use_move(_me(e).bid, "hit", _foe(e).bid)])
	assert_int(_me(e).energy()).is_equal(mine.max_energy(db) - 2)
	e.commit(0)
	assert_int(mine.energy).is_equal(mine.max_energy(db) - 2)


func test_tonic_restores_energy() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob")], [FixtureDB.make(db, "tank")], -1, -1, 1, false, {"tonic": 1})
	var me := _me(e)
	me.creature.energy = 0
	e.resolve_round([BattleAction.use_item(me.bid, "tonic", me.bid)])
	assert_int(me.energy()).is_equal(roundi(me.creature.max_energy(db) * 0.5))


func test_drained_ai_still_acts() -> void:
	var e := _duel("blob", "tank", ["big_hit"])
	var me := _me(e)
	me.creature.energy = 1
	for style in ["basic", "aggressive", "tactician"]:
		var a := BattleAI.choose(e, me.bid, style)
		assert_bool(a.kind == "rest" or a.move == "scrap").is_true()


# --- Resolve ---

func test_resolve_chance_formula() -> void:
	# Average Resolve at the attacker's level (stat 15 at Lv 10) resists cap/2.
	assert_float(Stats.resolve_chance(15.0, 10, 0.3)).is_equal_approx(0.15, 0.0001)
	assert_float(Stats.resolve_chance(500.0, 10, 0.3)).is_less(0.3)


func test_high_resolve_resists_more() -> void:
	var rdb := FixtureDB.build({"resolve": {"resist_cap": 0.9, "endure_cap": 0.0}})
	var counts := {}
	for target in ["meek", "stoic"]:
		var resisted := 0
		for s in 60:
			var e := _duel("blob", target, ["burn_touch"], s, rdb)
			if not FixtureDB.events_of(_act(e, "burn_touch"), "resisted").is_empty():
				resisted += 1
		counts[target] = resisted
	assert_int(counts.stoic).is_greater(counts.meek + 15)


func test_resolve_blocks_stat_drops_from_foes() -> void:
	var rdb := FixtureDB.build({"resolve": {"resist_cap": 1.0, "endure_cap": 0.0}})
	var resisted := 0
	for s in 30:
		var e := _duel("blob", "stoic", ["growl"], s, rdb)
		resisted += FixtureDB.events_of(_act(e, "growl"), "resisted").size()
	assert_int(resisted).is_greater(10)


func test_endure_leaves_one_hp_once() -> void:
	var rdb := FixtureDB.build({"resolve": {"resist_cap": 0.0, "endure_cap": 1.0}})
	var found := false
	for s in 30:
		var e := _duel("blob", "stoic", ["big_hit"], s, rdb)
		var foe := _foe(e)
		foe.creature.hp = 5
		var events := _act(e, "big_hit")
		if not FixtureDB.events_of(events, "endured").is_empty():
			assert_int(foe.hp()).is_equal(1)
			assert_bool(foe.endured).is_true()
			found = true
			break
	assert_bool(found).is_true()


# --- Bond ---

func test_negative_bond_weakens_damage_and_accuracy() -> void:
	var e := _duel("blob", "tank", ["hit"])
	var me := _me(e)
	var normal := BattleAI.estimate_damage(e, me, db.move("hit"), _foe(e), 1)
	me.creature.bond = -100
	var sulking := BattleAI.estimate_damage(e, me, db.move("hit"), _foe(e), 1)
	assert_float(sulking).is_less(normal * 0.85)
	assert_float(BattleMath.effective_stat(e, me, "acc")).is_equal_approx(0.8, 0.0001)


func test_negative_bond_disobeys_sometimes() -> void:
	var disobeyed := 0
	for s in 80:
		var e := _duel("blob", "tank", ["hit", "mend"], s)
		_me(e).creature.bond = -100
		disobeyed += FixtureDB.events_of(_act(e, "hit"), "disobeyed").size()
	# 40% expected
	assert_int(disobeyed).is_between(18, 50)


func test_very_negative_bond_can_lash_out() -> void:
	var lashed := 0
	for s in 200:
		var e := _duel("blob", "tank", ["hit"], s)
		_me(e).creature.bond = -100
		lashed += FixtureDB.events_of(_act(e, "hit"), "lashed_out").size()
	assert_int(lashed).is_greater(0)


func test_positive_bond_never_misbehaves() -> void:
	for s in 40:
		var e := _duel("blob", "tank", ["hit"], s)
		_me(e).creature.bond = 100
		var events := _act(e, "hit")
		assert_array(FixtureDB.events_of(events, "disobeyed")).is_empty()
		assert_array(FixtureDB.events_of(events, "lashed_out")).is_empty()


func test_win_and_knockout_raise_bond() -> void:
	var e := _duel("blob", "blob", ["hit"])
	var me := _me(e)
	_foe(e).creature.hp = 1
	_act(e, "hit")
	assert_int(me.creature.bond).is_equal(1 + 2)


func test_fainting_lowers_bond() -> void:
	var mine := FixtureDB.make(db, "blob", 10, ["hit"])
	var e := FixtureDB.engine(db, [mine], [FixtureDB.make(db, "tank", 30, ["hit"])])
	var me := _me(e)
	me.creature.hp = 1
	e.resolve_round([BattleAction.pass_turn(me.bid), BattleAction.use_move(_foe(e).bid, "hit", me.bid)])
	# Sent out at full HP and only passed, so no overwork: just -4 for fainting.
	assert_int(me.creature.bond).is_equal(-4)
	assert_int(mine.bond).is_equal(0)


func test_overwork_lowers_bond_once_per_battle() -> void:
	var mine := FixtureDB.make(db, "blob", 10, ["hit"])
	mine.hp = 2
	var e := FixtureDB.engine(db, [mine], [FixtureDB.make(db, "tank")])
	assert_int(_me(e).creature.bond).is_equal(-2)
	_act(e, "hit")
	assert_int(_me(e).creature.bond).is_equal(-2)


func test_item_healing_raises_bond() -> void:
	var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob")], [FixtureDB.make(db, "tank")], -1, -1, 1, false, {"potion": 1})
	var me := _me(e)
	me.creature.hp -= 5
	e.resolve_round([BattleAction.use_item(me.bid, "potion", me.bid)])
	assert_int(me.creature.bond).is_equal(1)


# --- Overworld field multipliers carried by the setup ---

## One knockout of a level-10 blob; returns the player's battler after it.
func _ko_with(xp_mult: float, bond_gain: float, start_xp := -1) -> Battler:
	var e := _duel("blob", "blob", ["hit"])
	e.setup.xp_mult = xp_mult
	e.setup.bond_gain = bond_gain
	var me := _me(e)
	if start_xp >= 0:
		me.creature.xp = start_xp
	_foe(e).creature.hp = 1
	_act(e, "hit")
	return me


func test_xp_mult_from_lead() -> void:
	var base := _ko_with(1.0, 1.0)
	var gained := base.creature.xp - Stats.xp_for_level(10)
	assert_int(gained).is_greater(0)
	var tripled := _ko_with(3.0, 1.0)
	var amount := Stats.xp_reward(db.balance, 50, 10, true, 0.0)  # FixtureDB.engine is not wild
	assert_int(gained).is_equal(maxi(1, int(amount)))
	assert_int(tripled.creature.xp - Stats.xp_for_level(10)).is_equal(int(amount * 3.0))
	# Level-ups follow from the scaled XP: just short of 11 at 1x, past it at 3x.
	var start := Stats.xp_for_level(11) - gained - 1
	assert_int(_ko_with(1.0, 1.0, start).creature.level).is_equal(10)
	assert_int(_ko_with(3.0, 1.0, start).creature.level).is_equal(11)


func test_bond_gain_only_scales_gains() -> void:
	# Knockout +1 and win +2: x1.25 gives 1 (1.25 rounded) and 3 (2.5 rounded).
	assert_int(_ko_with(1.0, 1.25).creature.bond).is_equal(1 + 3)
	# A scaled positive gain is at least 1.
	assert_int(_ko_with(1.0, 0.01).creature.bond).is_equal(1 + 1)
	# Losses are never scaled.
	var mine := FixtureDB.make(db, "blob", 10, ["hit"])
	var e := FixtureDB.engine(db, [mine], [FixtureDB.make(db, "tank", 30, ["hit"])])
	e.setup.bond_gain = 3.0
	var me := _me(e)
	me.creature.hp = 1
	e.resolve_round([BattleAction.pass_turn(me.bid), BattleAction.use_move(_foe(e).bid, "hit", me.bid)])
	assert_int(me.creature.bond).is_equal(-4)


func test_the_foes_bond_is_not_scaled_by_the_players_bond_gain() -> void:
	# setup.bond_gain is the player's lead passive; the foe side earns Bond at 1x whatever it is.
	var gained := []
	for gain in [1.0, 3.0]:
		var e := FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["hit"])], [FixtureDB.make(db, "tank", 30, ["hit"])])
		e.setup.bond_gain = gain
		var me := _me(e)
		me.creature.hp = 1
		var bond_before := _foe(e).creature.bond
		e.resolve_round([BattleAction.pass_turn(me.bid), BattleAction.use_move(_foe(e).bid, "hit", me.bid)])
		gained.append(_foe(e).creature.bond - bond_before)
	assert_int(gained[0]).is_greater(0)  # the foe does earn Bond for the knockout
	assert_int(gained[1]).is_equal(gained[0])


func test_knocking_out_your_own_ally_earns_no_knockout_credit() -> void:
	# `quake` hits everyone, so it can finish a 1 HP ally. Only a blow from the other side sets last_hit_by, so the
	# ally's fall credits nobody: no knockout Bond and no knockout Affinity (the hit on the foe still counts once).
	var a := FixtureDB.make(db, "blob", 10, ["quake"])
	var b := FixtureDB.make(db, "blob", 10, ["hit"])
	var e: BattleEngine = FixtureDB.engine(db, [a, b], [FixtureDB.make(db, "tank", 10, ["hit"])], 2, 1)
	var me: Battler = e.sides[0].active()[0]
	var ally: Battler = e.sides[0].active()[1]
	ally.creature.hp = 1
	var bond_before := me.creature.bond
	e.resolve_round([BattleAction.use_move(me.bid, "quake", -1), BattleAction.pass_turn(ally.bid)])
	assert_bool(ally.fainted).is_true()
	assert_int(ally.last_hit_by).is_equal(-1)
	assert_int(me.creature.bond - bond_before).is_equal(0)
	assert_int(int(e.rewards.affinity_log.get(me.bid, {}).get("striker", 0))).is_equal(1)  # one hit_dealt, on the foe
