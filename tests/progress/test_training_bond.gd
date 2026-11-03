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
	assert_int(Progression.training_points_available(db, c)).is_equal(9)


func test_training_raises_stats() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	var sdef := c.stat(db, "sdef")
	assert_str(Progression.train(db, c, "sdef", 5)).is_equal("")
	assert_int(c.stat(db, "sdef")).is_equal(sdef + 5)
	assert_int(Progression.training_points_available(db, c)).is_equal(4)


func test_hp_training_counts_double_and_heals_the_gain() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	var max_hp := c.max_hp(db)
	c.hp = 10
	Progression.train(db, c, "hp", 3)
	assert_int(c.max_hp(db)).is_equal(max_hp + 6)
	assert_int(c.hp).is_equal(16)


func test_stamina_training_grows_energy_pool() -> void:
	var c := FixtureDB.make(db, "blob", 10)
	Progression.train(db, c, "stamina", 4)
	assert_int(c.max_energy(db)).is_equal(34)


func test_training_limits() -> void:
	var c := FixtureDB.make(db, "blob", 50)  # 49 points
	assert_str(Progression.train(db, c, "luck", 1)).is_equal("not_trainable")
	assert_str(Progression.train(db, c, "patk", 0)).is_equal("bad_amount")
	assert_str(Progression.train(db, c, "patk", 31)).is_equal("stat_capped")
	assert_str(Progression.train(db, c, "patk", 30)).is_equal("")
	assert_str(Progression.train(db, c, "patk", 1)).is_equal("stat_capped")
	assert_str(Progression.train(db, c, "pdef", 20)).is_equal("not_enough_points")


func test_bond_is_clamped() -> void:
	var c := FixtureDB.make(db, "blob")
	c.bond = 99
	assert_int(Progression.change_bond(db, c, "battle_won")).is_equal(1)
	assert_int(c.bond).is_equal(100)
	c.bond = -98
	Progression.change_bond(db, c, "fainted")
	assert_int(c.bond).is_equal(-100)


func test_bond_effect_curves() -> void:
	var c := FixtureDB.make(db, "blob")
	c.bond = -50
	assert_float(Progression.disobey_chance(db, c)).is_equal_approx(0.2, 0.0001)
	assert_float(Progression.bond_performance(db, c)).is_equal_approx(0.9, 0.0001)
	assert_float(Progression.lash_out_chance(db, c)).is_equal_approx(0.05, 0.0001)
	c.bond = -49
	assert_float(Progression.lash_out_chance(db, c)).is_equal(0.0)
	c.bond = 100
	assert_float(Progression.bond_xp_mult(db, c)).is_equal_approx(1.1, 0.0001)
	assert_float(Progression.disobey_chance(db, c)).is_equal(0.0)


func test_starter_and_rest() -> void:
	var c := FixtureDB.make(db, "blob")
	Progression.make_starter(db, c)
	assert_int(c.bond).is_equal(20)
	c.hp = 1
	c.energy = 0
	c.status = "burn"
	Progression.rest(db, c)
	assert_int(c.hp).is_equal(c.max_hp(db))
	assert_int(c.energy).is_equal(c.max_energy(db))
	assert_str(c.status).is_equal("")
	assert_int(c.bond).is_equal(22)


func test_new_fields_round_trip() -> void:
	var c := FixtureDB.make(db, "blob", 12)
	c.bond = -30
	c.energy = 7
	Progression.train(db, c, "spd", 3)
	var copy := CreatureInstance.from_dict(c.to_dict())
	assert_int(copy.bond).is_equal(-30)
	assert_int(copy.energy).is_equal(7)
	assert_int(copy.trained("spd")).is_equal(3)
