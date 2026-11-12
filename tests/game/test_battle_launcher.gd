extends GdUnitTestSuite
## Building battles from a save and writing results back.

var real: Database
var db: Database
var rng := RandomNumberGenerator.new()


func before() -> void:
	real = DataLoader.load_database("res://data").db
	db = FixtureDB.build()


func _save() -> SaveGame:
	rng.seed = 3
	return SaveGame.new_game("Ana", 1000, rng)


func test_test_party_is_granted_once() -> void:
	var s := _save()
	assert_bool(BattleLauncher.grant_test_party(real, s)).is_true()
	assert_int(s.party.size()).is_equal(BattleLauncher.TEST_PARTY.size())
	assert_int(s.party[0].bond).is_equal(real.balance.bond_cfg.starter)
	assert_int(s.inventory.lure_cage).is_equal(5)
	assert_bool(BattleLauncher.grant_test_party(real, s)).is_false()
	assert_int(s.party.size()).is_equal(BattleLauncher.TEST_PARTY.size())


func test_max_fieldable_counts_healthy_creatures() -> void:
	var s := _save()
	BattleLauncher.grant_test_party(real, s)
	assert_int(BattleLauncher.max_fieldable(s, 2)).is_equal(2)
	s.party[0].hp = 0
	s.party[1].hp = 0
	assert_int(BattleLauncher.max_fieldable(s, 2)).is_equal(1)


func test_wild_pack_respects_the_table() -> void:
	var enc := real.encounter("route_01_grass")
	for i in 20:
		var pack := BattleLauncher.roll_wild_pack(real, "route_01_grass", rng)
		assert_int(pack.size()).is_between(enc.pack_min, enc.pack_max)
		for c: CreatureInstance in pack:
			assert_bool(enc.table.any(func(row): return row.species == c.species)).is_true()


func test_tamer_setup_uses_format_and_bag() -> void:
	var s := _save()
	BattleLauncher.grant_test_party(real, s)
	var setup := BattleLauncher.tamer_setup(real, s, "rival_01", 1)
	assert_int(setup.sides[0].field_count).is_equal(1)
	assert_int(setup.sides[1].max_active).is_equal(2)
	assert_int(setup.sides[0].items.salve).is_equal(3)


func test_results_write_back_items_catches_and_money() -> void:
	var s := _save()
	s.party = [FixtureDB.make(db, "blob", 10, ["hit"])]
	s.inventory = {"master_cage": 1, "potion": 2}
	var setup := BattleLauncher.wild_setup(db, s, [FixtureDB.make(db, "fish", 3)], 1)
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), setup)
	e.start()
	e.resolve_round([BattleAction.use_item(e.sides[0].active()[0].bid, "master_cage", e.sides[1].active()[0].bid)])
	var summary := BattleLauncher.apply_results(db, s, e)
	assert_str(summary.outcome).is_equal("captured")
	assert_array(summary.captured).contains_exactly(["Fish"])
	assert_int(s.party.size()).is_equal(2)
	assert_bool(s.inventory.has("master_cage")).is_false()
	assert_int(s.inventory.potion).is_equal(2)


func test_results_push_the_creature_key_after_the_battle_copies_are_written_back() -> void:
	var s := _save()
	s.party = [FixtureDB.make(db, "blob", 10, ["hit"])]
	var setup := BattleLauncher.wild_setup(db, s, [FixtureDB.make(db, "fish", 3)], 1)
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), setup)
	e.start()
	e.sides[0].battlers[0].creature.level = 20  # levelled up inside the battle, on its copy
	AchievementWatch.clear()
	BattleLauncher.apply_results(db, s, e)
	assert_int(s.party[0].level).is_equal(20)
	assert_array(Array(AchievementWatch.drain())).contains("creature")
	AchievementWatch.clear()


func test_fill_box_pushes_the_creature_key() -> void:
	var s := _save()
	AchievementWatch.clear()
	BattleLauncher.fill_box(real, s, 3, 9, RandomNumberGenerator.new())
	assert_array(Array(AchievementWatch.drain())).contains("creature")


func test_full_party_sends_catches_to_storage() -> void:
	var s := _save()
	for i in db.balance.party_size:
		s.party.append(FixtureDB.make(db, "blob", 10, ["hit"]))
	s.inventory = {"master_cage": 1}
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), BattleLauncher.wild_setup(db, s, [FixtureDB.make(db, "fish", 3)], 1))
	e.start()
	e.resolve_round([BattleAction.use_item(e.sides[0].active()[0].bid, "master_cage", e.sides[1].active()[0].bid)])
	var summary := BattleLauncher.apply_results(db, s, e)
	assert_int(summary.to_storage).is_equal(1)
	assert_int(BoxStorage.count(s)).is_equal(1)


func test_loss_no_longer_heals() -> void:
	var s := _save()
	s.party = [FixtureDB.make(db, "blob", 2, ["hit"])]
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), BattleLauncher.wild_setup(db, s, [FixtureDB.make(db, "tank", 40, ["hit"])], 1))
	e.start()
	while not e.is_over():
		e.resolve_round([BattleAction.pass_turn(e.sides[0].active()[0].bid)] if not e.sides[0].active().is_empty() else [])
	var summary := BattleLauncher.apply_results(db, s, e)
	assert_str(summary.outcome).is_equal("lost")
	assert_int(s.party[0].hp).is_equal(0)  # the overworld applies the defeat rules (Defeat)


func test_party_level_is_the_average() -> void:
	var s := _save()
	assert_int(BattleLauncher.party_level(s)).is_equal(1)
	BattleLauncher.grant_test_party(real, s)
	assert_int(BattleLauncher.party_level(s)).is_equal(8)


func _levelling_engine(s: SaveGame, moves: Array, xp_gain: int) -> BattleEngine:
	var lead := FixtureDB.make(real, "tidepup", 8, moves)
	lead.xp = Stats.xp_for_level(9) - 1
	s.party = [lead, FixtureDB.make(real, "emberkit", 8)]
	var e := BattleEngine.new(real, RandomNumberGenerator.new(), BattleLauncher.wild_setup(real, s, [FixtureDB.make(real, "tidepup", 2)], 1))
	e.start()
	if xp_gain > 0:
		Progression.award_xp(real, e.sides[0].battlers[0].creature, xp_gain)
	return e


func test_results_report_levelled_creatures() -> void:
	var s := _save()
	var e := _levelling_engine(s, ["tackle", "splash_jab", "drench", "taunting_howl"], 1)
	var summary := BattleLauncher.apply_results(real, s, e)
	assert_int(summary.progress.size()).is_equal(1)
	assert_object(summary.progress[0].creature).is_same(s.party[0])
	assert_int(s.party[0].level).is_equal(9)
	assert_array(summary.progress[0].offered_moves).contains_exactly(["riptide"])


func test_results_progress_empty_without_levels() -> void:
	var s := _save()
	var e := _levelling_engine(s, ["tackle", "splash_jab", "drench", "taunting_howl"], 0)
	var summary := BattleLauncher.apply_results(real, s, e)
	assert_array(summary.progress).is_empty()


func test_battle_reports_unlock_without_level_gain() -> void:
	var s := _save()
	var lead := FixtureDB.make(real, "tidepup", 8, ["tackle"])
	lead.affinity["striker"] = real.balance.growth_affinity_threshold - 1
	s.party = [lead]
	var e := BattleEngine.new(real, RandomNumberGenerator.new(), BattleLauncher.wild_setup(real, s, [FixtureDB.make(real, "tidepup", 2)], 1))
	e.start()
	e.rewards.award(e.sides[0].battlers[0], "hit_dealt")
	var summary := BattleLauncher.apply_results(real, s, e)
	assert_int(summary.progress.size()).is_equal(1)
	assert_object(summary.progress[0].creature).is_same(s.party[0])
	assert_str(summary.progress[0].unlocked_passive).is_equal("finisher")
	assert_int(s.party[0].level).is_equal(8)
	assert_bool(summary.progress[0].growth_due).is_false()


func test_no_entry_without_level_or_unlock() -> void:
	var s := _save()
	s.party = [FixtureDB.make(real, "tidepup", 8, ["tackle"])]
	var e := BattleEngine.new(real, RandomNumberGenerator.new(), BattleLauncher.wild_setup(real, s, [FixtureDB.make(real, "tidepup", 2)], 1))
	e.start()
	e.rewards.award(e.sides[0].battlers[0], "hit_dealt")
	assert_array(BattleLauncher.apply_results(real, s, e).progress).is_empty()


func test_setups_carry_the_lead_field_multipliers() -> void:
	var s := _save()
	var lead := FixtureDB.make(real, "sprigling", 8)
	lead.passive = "photosynth"  # Bond gains x1.25
	var frost := FixtureDB.make(real, "frostling", 8)
	frost.passive = "cold_snap"  # XP x1.1, but not the lead
	s.party = [lead, frost]
	var setups := [
		BattleLauncher.wild_setup(real, s, [FixtureDB.make(real, "tidepup", 2)], 1),
		BattleLauncher.tamer_setup(real, s, "rival_01", 1),
	]
	for setup: BattleSetup in setups:
		assert_float(setup.bond_gain).is_equal_approx(1.25, 0.0001)
		assert_float(setup.xp_mult).is_equal(1.0)
	s.party = [frost, lead]
	var w := BattleLauncher.wild_setup(real, s, [FixtureDB.make(real, "tidepup", 2)], 1)
	assert_float(w.xp_mult).is_equal_approx(1.1, 0.0001)
	assert_float(w.bond_gain).is_equal(1.0)


func test_setup_defaults_are_neutral() -> void:
	var setup := BattleSetup.new()
	assert_float(setup.xp_mult).is_equal(1.0)
	assert_float(setup.bond_gain).is_equal(1.0)

func _specs(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(CreatureSpec.natural(real, "tidepup", 6, rng))
	return out


func test_exhibition_setup_formats() -> void:
	# [mine team, mine field, foe team, foe field, expected mine field, expected foe field]
	for f: Array in [[3, 1, 3, 1, 1, 1], [3, 2, 3, 2, 2, 2], [4, 2, 5, 3, 2, 3], [6, 3, 6, 3, 3, 3], [1, 1, 6, 3, 1, 3]]:
		var setup: BattleSetup = BattleLauncher.exhibition_setup(real, _specs(f[0]), f[1], _specs(f[2]), f[3], false, {}, rng)
		assert_bool(setup.exhibition).is_true()
		assert_int(setup.sides[0].field_count).is_equal(f[4])
		assert_int(setup.sides[0].party.size()).is_equal(f[0])
		assert_int(setup.sides[1].field_count).is_equal(f[5])
		assert_int(setup.sides[1].party.size()).is_equal(f[2])


func test_exhibition_setup_tamer_and_wild_ai() -> void:
	var tamer: BattleSetup = BattleLauncher.exhibition_setup(real, _specs(2), 2, _specs(2), 2, false, {}, rng)
	assert_str(tamer.sides[1].ai).is_equal("tactician")
	assert_str(tamer.foe_name).is_equal("Sparring Partner")
	assert_bool(tamer.is_wild).is_false()
	assert_bool(tamer.sides[1].auto_replace).is_true()
	var wild: BattleSetup = BattleLauncher.exhibition_setup(real, _specs(2), 2, _specs(5), 5, true, {"lure_cage": 2}, rng)
	assert_str(wild.sides[1].ai).is_equal("basic")
	assert_bool(wild.is_wild).is_true()
	assert_bool(wild.sides[1].is_wild).is_true()
	assert_int(wild.sides[1].party.size()).is_equal(BattleLauncher.MAX_SIDE)
	assert_int(wild.sides[1].field_count).is_equal(BattleLauncher.MAX_SIDE)
	assert_int(wild.sides[0].items.lure_cage).is_equal(2)
	assert_bool(wild.exhibition).is_true()
	assert_bool(BattleSetup.new().exhibition).is_false()


func test_exhibition_setup_clamps_field_counts() -> void:
	var setup: BattleSetup = BattleLauncher.exhibition_setup(real, _specs(2), 9, _specs(4), 0, false, {}, rng)
	assert_int(setup.sides[0].field_count).is_equal(2)
	assert_int(setup.sides[1].field_count).is_equal(1)


# --- Codex and counters (M7a) ---

## Plays the player's first creature attacking the first standing foe until the battle ends.
func _fight(e: BattleEngine, move := "hit") -> void:
	var guard := 60
	while not e.is_over() and guard > 0:
		guard -= 1
		var me := e.sides[0].active()
		var foes := e.sides[1].active()
		if me.is_empty() or foes.is_empty():
			e.resolve_round([])
			continue
		e.resolve_round([BattleAction.use_move(me[0].bid, move, foes[0].bid)])


func _wild_engine(s: SaveGame, foe_species: String, foe_level: int, bag := {}) -> BattleEngine:
	s.party = [FixtureDB.make(db, "blob", 30, ["hit"])]
	s.inventory = bag
	var e := BattleEngine.new(db, RandomNumberGenerator.new(),
		BattleLauncher.wild_setup(db, s, [FixtureDB.make(db, foe_species, foe_level)], 1))
	e.start()
	return e


func test_wild_win_marks_foe_seen_and_counts() -> void:
	var s := _save()
	var e := _wild_engine(s, "fish", 1)
	_fight(e)
	BattleLauncher.apply_results(db, s, e)
	assert_str(Codex.status(s, "fish")).is_equal("seen")
	assert_int(Counters.value(s, "battles_fought")).is_equal(1)
	assert_int(Counters.value(s, "battles_won")).is_equal(1)
	assert_int(Counters.value(s, "tamers_defeated")).is_equal(0)
	assert_int(Counters.value(s, "money_earned")).is_equal(0)


func test_capture_marks_caught_and_counts() -> void:
	var s := _save()
	var e := _wild_engine(s, "fish", 3, {"master_cage": 1})
	e.resolve_round([BattleAction.use_item(e.sides[0].active()[0].bid, "master_cage", e.sides[1].active()[0].bid)])
	BattleLauncher.apply_results(db, s, e)
	assert_str(Codex.status(s, "fish")).is_equal("caught")
	assert_int(Counters.value(s, "creatures_caught")).is_equal(1)
	assert_int(Counters.value(s, "battles_won")).is_equal(1)
	assert_int(Counters.value(s, "items_used")).is_equal(1)


func test_tamer_win_counts_tamer_and_money() -> void:
	var s := _save()
	s.party = [FixtureDB.make(db, "blob", 30, ["hit"])]
	var e := BattleEngine.new(db, RandomNumberGenerator.new(), BattleLauncher.tamer_setup(db, s, "t1", 1))
	e.start()
	_fight(e)
	BattleLauncher.apply_results(db, s, e)
	assert_int(Counters.value(s, "tamers_defeated")).is_equal(1)
	assert_int(Counters.value(s, "money_earned")).is_equal(1)
	assert_int(Counters.value(s, "battles_won")).is_equal(1)
	assert_str(Codex.status(s, "blob")).is_equal("seen")
	assert_str(Codex.status(s, "fish")).is_equal("seen")


func test_loss_counts_fought_and_never_sees_a_bench_foe() -> void:
	var raw := FixtureDB.raw()
	raw.add_entry("tamers", {"id": "t_bench", "name": "Bench", "max_active": 1, "ai": "aggressive",
		"reward_money": 1, "party": [{"species": "tank", "level": 40}, {"species": "fish", "level": 5}]})
	var tdb := Database.from_raw(raw)
	var s := _save()
	s.party = [FixtureDB.make(tdb, "blob", 2, ["hit"])]
	var e := BattleEngine.new(tdb, RandomNumberGenerator.new(), BattleLauncher.tamer_setup(tdb, s, "t_bench", 1))
	e.start()
	_fight(e)
	var summary := BattleLauncher.apply_results(tdb, s, e)
	assert_str(summary.outcome).is_equal("lost")
	assert_str(Codex.status(s, "tank")).is_equal("seen")
	assert_str(Codex.status(s, "fish")).is_equal("unseen")
	assert_int(Counters.value(s, "battles_fought")).is_equal(1)
	assert_int(Counters.value(s, "battles_won")).is_equal(0)
	assert_int(Counters.value(s, "tamers_defeated")).is_equal(0)


func test_flee_marks_the_fielded_foe_but_is_not_fought_or_won() -> void:
	var s := _save()
	var e := _wild_engine(s, "fish", 3, {"potion": 3})
	var me := e.sides[0].active()[0]
	e.resolve_round([BattleAction.use_item(me.bid, "potion", me.bid)])
	e.resolve_round([BattleAction.use_item(me.bid, "potion", me.bid)])
	e.resolve_round([BattleAction.flee(me.bid)])
	var summary := BattleLauncher.apply_results(db, s, e)
	assert_str(summary.outcome).is_equal("fled")
	assert_str(Codex.status(s, "fish")).is_equal("seen")
	assert_int(Counters.value(s, "battles_fought")).is_equal(0)
	assert_int(Counters.value(s, "battles_won")).is_equal(0)
	assert_int(Counters.value(s, "items_used")).is_equal(2)

