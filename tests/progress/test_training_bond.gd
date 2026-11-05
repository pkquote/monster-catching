extends GdUnitTestSuite
## Training points, energy pool, and Bond rules outside battle.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func test_energy_pool_formula() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	# 2*50*10/100 + 20
	assert_int(c.max_energy(db)).is_equal(30)
	assert_int(c.energy).is_equal(30)


func test_level_up_adds_energy_gain() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	c.energy = 10
	var gain := Stats.energy_at(50, 11, 20) - Stats.energy_at(50, 10, 20)
	Progression.award_xp(db, c, Stats.xp_for_level(11) - c.xp)
	assert_int(c.energy).is_equal(10 + gain)


func test_training_points_accumulate_per_level() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	assert_int(Training.available(db, c)).is_equal(9)


func test_training_raises_stats() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	var sdef := c.stat(db, "sdef")
	assert_str(Training.train(db, c, "sdef", 5)).is_equal("")
	assert_int(c.stat(db, "sdef")).is_equal(sdef + 5)
	assert_int(Training.available(db, c)).is_equal(4)


func test_hp_training_counts_double_and_heals_the_gain() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	var max_hp := c.max_hp(db)
	c.hp = 10
	Training.train(db, c, "hp", 3)
	assert_int(c.max_hp(db)).is_equal(max_hp + 6)
	assert_int(c.hp).is_equal(16)


func test_stamina_training_grows_energy_pool() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	Training.train(db, c, "stamina", 4)
	assert_int(c.max_energy(db)).is_equal(34)


func test_training_limits() -> void:
	var c := FixtureDB.make(db, "blob", 50)  # 49 points
	assert_str(Training.train(db, c, "luck", 1)).is_equal("not_trainable")
	assert_str(Training.train(db, c, "patk", 0)).is_equal("bad_amount")
	assert_str(Training.train(db, c, "patk", 31)).is_equal("stat_capped")
	assert_str(Training.train(db, c, "patk", 30)).is_equal("")
	assert_str(Training.train(db, c, "patk", 1)).is_equal("stat_capped")
	assert_str(Training.train(db, c, "pdef", 20)).is_equal("not_enough_points")


func test_bond_is_clamped() -> void:
	var c := FixtureDB.make(db, "blob")
	c.bond = 99
	assert_int(Bond.change(db, c, "battle_won")).is_equal(1)
	assert_int(c.bond).is_equal(100)
	c.bond = -98
	Bond.change(db, c, "fainted")
	assert_int(c.bond).is_equal(-100)


func test_bond_effect_curves() -> void:
	var c := FixtureDB.make(db, "blob")
	c.bond = -50
	assert_float(Bond.disobey_chance(db, c)).is_equal_approx(0.2, 0.0001)
	assert_float(Bond.performance(db, c)).is_equal_approx(0.9, 0.0001)
	assert_float(Bond.lash_out_chance(db, c)).is_equal_approx(0.05, 0.0001)
	c.bond = -49
	assert_float(Bond.lash_out_chance(db, c)).is_equal(0.0)
	c.bond = 100
	assert_float(Bond.xp_mult(db, c)).is_equal_approx(1.1, 0.0001)
	assert_float(Bond.disobey_chance(db, c)).is_equal(0.0)


func test_starter_and_rest() -> void:
	var c := FixtureDB.make(db, "blob")
	Bond.make_starter(db, c)
	assert_int(c.bond).is_equal(20)
	c.hp = 1
	c.energy = 0
	c.status = "burn"
	Bond.rest(db, c)
	assert_int(c.hp).is_equal(c.max_hp(db))
	assert_int(c.energy).is_equal(c.max_energy(db))
	assert_str(c.status).is_equal("")
	assert_int(c.bond).is_equal(22)


func test_new_fields_round_trip() -> void:
	var c := FixtureDB.make(db, "blob", 12)
	c.bond = -30
	c.energy = 7
	Training.train(db, c, "spd", 3)
	var copy := CreatureInstance.from_dict(c.to_dict())
	assert_int(copy.bond).is_equal(-30)
	assert_int(copy.energy).is_equal(7)
	assert_int(copy.trained("spd")).is_equal(3)


func test_grown_stats_exclude_training_and_add_up_to_the_totals() -> void:
	var c := FixtureDB.make(db, "blob", 20)
	var untrained := {}
	for key in ["hp", "stamina", "patk", "pdef", "satk", "sdef", "spd", "resolve", "luck"]:
		untrained[key] = c.max_hp(db) if key == "hp" else c.max_energy(db) if key == "stamina" else c.stat(db, key)
	Training.train(db, c, "hp", 3)
	Training.train(db, c, "stamina", 2)
	Training.train(db, c, "patk", 4)
	var base: int = db.creature("blob").base_stats.patk
	assert_int(c.grown(db, "patk")).is_equal(Stats.stat_at(base, 20))
	assert_int(c.grown(db, "hp")).is_equal(untrained.hp)
	assert_int(c.grown(db, "stamina")).is_equal(untrained.stamina)
	assert_int(c.max_hp(db)).is_equal(c.grown(db, "hp") + 3 * int(db.balance.training_cfg.hp_per_point))
	assert_int(c.max_energy(db)).is_equal(c.grown(db, "stamina") + 2)
	assert_int(c.stat(db, "patk")).is_equal(c.grown(db, "patk") + 4)
	for key in untrained:
		assert_int(c.grown(db, key)).is_equal(untrained[key])


func test_level_cap_is_99() -> void:
	assert_int(db.balance.level_cap).is_equal(99)
	assert_int(CreatureInstance.create(db, "blob", 150).level).is_equal(99)


func test_clamp_to_cap_pulls_an_over_level_creature_down() -> void:
	var c := FixtureDB.make(db, "blob", 50)
	c.level = 100
	c.hp = 9999
	c.clamp_to_cap(db)
	assert_int(c.level).is_equal(99)
	assert_int(c.hp).is_equal(c.max_hp(db))
	var fine := FixtureDB.make(db, "blob", 30)
	fine.clamp_to_cap(db)
	assert_int(fine.level).is_equal(30)
