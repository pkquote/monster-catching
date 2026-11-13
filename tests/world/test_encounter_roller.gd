extends GdUnitTestSuite
## Wild encounter rolls per grass tile: rate, grace tiles, no table, no fighters.

var db: Database
var rng := RandomNumberGenerator.new()


func before() -> void:
	db = FixtureDB.build()


func before_test() -> void:
	rng.seed = 99


func test_rate_over_many_rolls() -> void:
	var r := EncounterRoller.new(db.balance, rng)
	var hits := 0
	for i in 10000:
		if r.on_grass_tile("route_01_grass", true):
			hits += 1
	assert_float(hits / 10000.0).is_equal_approx(0.10, 0.015)


func test_no_table_never_rolls() -> void:
	var r := EncounterRoller.new(db.balance, rng)
	for i in 500:
		assert_bool(r.on_grass_tile("", true)).is_false()


func test_no_healthy_creatures_never_rolls() -> void:
	var r := EncounterRoller.new(db.balance, rng)
	for i in 500:
		assert_bool(r.on_grass_tile("route_01_grass", false)).is_false()


func test_grace_tiles_after_a_battle() -> void:
	var always := FixtureDB.build({"overworld": {"walk_speed": 4.0, "run_speed": 7.0, "encounter_rate": 1.0,
		"encounter_grace_tiles": 4, "walk_energy_tiles": 8, "defeat_money_fraction": 0.1, "sell_fraction": 0.5}})
	var r := EncounterRoller.new(always.balance, rng)
	r.start_grace()
	for i in 4:
		assert_bool(r.on_grass_tile("route_01_grass", true)).is_false()
	assert_bool(r.on_grass_tile("route_01_grass", true)).is_true()


func test_encounter_rate_mult() -> void:
	var always := FixtureDB.build({"overworld": {"walk_speed": 4.0, "run_speed": 7.0, "encounter_rate": 1.0,
		"encounter_grace_tiles": 4, "walk_energy_tiles": 8, "defeat_money_fraction": 0.1, "sell_fraction": 0.5}})
	var r := EncounterRoller.new(always.balance, rng)
	for i in 200:
		assert_bool(r.on_grass_tile("route_01_grass", true, 0.0)).is_false()
	assert_bool(r.on_grass_tile("route_01_grass", true, 1.0)).is_true()
	var hits := 0
	for i in 10000:
		if r.on_grass_tile("route_01_grass", true, 0.5):
			hits += 1
	assert_float(hits / 10000.0).is_equal_approx(0.5, 0.03)


func test_a_zero_rate_mult_still_draws_one_number_per_tile() -> void:
	# A creature that suppresses encounters must not change what the generator does afterwards: every tile rolls once.
	var always := FixtureDB.build({"overworld": {"walk_speed": 4.0, "run_speed": 7.0, "encounter_rate": 1.0,
		"encounter_grace_tiles": 4, "walk_energy_tiles": 8, "defeat_money_fraction": 0.1, "sell_fraction": 0.5}})
	var r := EncounterRoller.new(always.balance, rng)
	var expected := RandomNumberGenerator.new()
	expected.seed = rng.seed
	expected.state = rng.state
	for i in 5:
		assert_bool(r.on_grass_tile("route_01_grass", true, 0.0)).is_false()
		expected.randf()
	assert_int(rng.state).is_equal(expected.state)
