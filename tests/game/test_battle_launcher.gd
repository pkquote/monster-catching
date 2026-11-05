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
	assert_int(s.storage.size()).is_equal(1)


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


func test_custom_setup_builds_any_format() -> void:
	var s := _save()
	BattleLauncher.grant_test_party(real, s)
	for f in [[1, 3], [3, 1], [2, 3], [3, 3]]:
		var setup := BattleLauncher.custom_setup(real, s, f[0], f[1], 12, true, rng)
		assert_int(setup.sides[0].field_count).is_equal(f[0])
		assert_int(setup.sides[0].max_active).is_equal(f[0])
		assert_int(setup.sides[1].party.size()).is_equal(f[1])
		assert_int(setup.sides[1].field_count).is_equal(f[1])
		assert_bool(setup.is_wild).is_true()
		for c: CreatureInstance in setup.sides[1].party:
			assert_int(c.level).is_equal(12)


func test_custom_setup_caps_by_healthy_and_tamer_mode() -> void:
	var s := _save()
	BattleLauncher.grant_test_party(real, s)
	s.party[0].hp = 0
	var setup := BattleLauncher.custom_setup(real, s, 3, 2, 5, false, rng)
	assert_int(setup.sides[0].field_count).is_equal(2)
	assert_bool(setup.is_wild).is_false()
	assert_str(setup.sides[1].ai).is_equal("tactician")
	assert_str(setup.foe_name).is_equal("Sparring Partner")
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
		BattleLauncher.custom_setup(real, s, 1, 1, 5, true, rng),
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
