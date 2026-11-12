extends GdUnitTestSuite
## Per-stat growth tiers: balance tier table and creature growth_rates.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func test_growth_percent_is_exact() -> void:
	var b := BalanceDef.from_dict(FixtureDB.balance())
	b.growth_tiers = {"slow": 0.8, "steady": 1.0, "fast": 1.2, "odd": 1.1}
	assert_int(b.growth_percent("slow")).is_equal(80)
	assert_int(b.growth_percent("steady")).is_equal(100)
	assert_int(b.growth_percent("fast")).is_equal(120)
	assert_int(b.growth_percent("odd")).is_equal(110)


func test_growth_tier_defaults_to_steady() -> void:
	var d := {"id": "pup", "name": "Pup", "types": ["water"], "base_stats": FixtureDB.FLAT.duplicate(),
		"catch_rate": 0.5, "xp_yield": 50, "learnset": [{"level": 1, "move": "splash"}],
		"passives": ["steady"], "growth_rates": {"spd": "fast"}}
	var c := CreatureDef.from_dict(d)
	assert_str(c.growth_tier("spd")).is_equal("fast")
	assert_str(c.growth_tier("patk")).is_equal("steady")


func test_balance_loads_tiers() -> void:
	assert_int(db.balance.growth_budget).is_equal(2)
	assert_int(db.balance.growth_percent("fast")).is_equal(120)


func test_steady_matches_the_old_formulas() -> void:
	for b in [1, 37, 50, 100, 255]:
		for l in [1, 2, 17, 50, 99]:
			assert_int(Stats.stat_at(b, l, 100)).is_equal((2 * b * l) / 100 + 5)
			assert_int(Stats.hp_at(b, l, 100)).is_equal((2 * b * l) / 100 + l + 10)
			assert_int(Stats.energy_at(b, l, 20, 100)).is_equal((2 * b * l) / 100 + 20)


func test_tier_table_at_level_99() -> void:
	assert_int(Stats.stat_at(50, 99, 80)).is_equal(84)
	assert_int(Stats.stat_at(50, 99, 100)).is_equal(104)
	assert_int(Stats.stat_at(50, 99, 120)).is_equal(123)
	assert_int(Stats.stat_at(100, 99, 80)).is_equal(163)
	assert_int(Stats.stat_at(100, 99, 120)).is_equal(242)
	assert_int(Stats.hp_at(50, 99, 120)).is_equal(2 * 50 * 120 * 99 / 10000 + 99 + 10)
	assert_int(Stats.energy_at(50, 99, 20, 120)).is_equal(118 + 20)


func test_grown_uses_the_species_tier() -> void:
	var def := db.creature("blob")
	var saved = def.growth_rates
	def.growth_rates = {"patk": "fast", "hp": "slow", "stamina": "fast"}
	var c := CreatureInstance.create(db, "blob", 50)
	var flat := int(db.balance.energy_cfg.base)
	assert_int(c.grown(db, "patk")).is_equal(Stats.stat_at(50, 50, 120))
	assert_int(c.grown(db, "hp")).is_equal(Stats.hp_at(50, 50, 80))
	assert_int(c.grown(db, "stamina")).is_equal(Stats.energy_at(50, 50, flat, 120))
	assert_int(c.grown(db, "pdef")).is_equal(Stats.stat_at(50, 50, 100))
	c.training = {"patk": 3, "hp": 2, "stamina": 4}
	assert_int(c.stat(db, "patk")).is_equal(c.grown(db, "patk") + 3)
	assert_int(c.max_hp(db)).is_equal(c.grown(db, "hp") + 2 * int(db.balance.training_cfg.hp_per_point))
	assert_int(c.max_energy(db)).is_equal(c.grown(db, "stamina") + 4)
	def.growth_rates = saved


func test_every_shipped_creature_grows_by_its_tier() -> void:
	var real := DataLoader.load_database("res://data", "res://dialogue").db
	var flat := int(real.balance.energy_cfg.base)
	for id in real.ids("creatures"):
		var def := real.creature(id)
		var base: Dictionary = def.base_stats
		for l in [1, 10, 50, 99]:
			var c := CreatureInstance.create(real, id, l)
			for s in DataSchemas.BASE_STATS:
				var pct := roundi(float(real.balance.growth_tiers[def.growth_tier(s)]) * 100.0)
				var scaled: int = (2 * int(base[s]) * pct * l) / 10000
				var expected: int
				if s == "hp":
					expected = scaled + l + 10
				elif s == "stamina":
					expected = scaled + flat
				else:
					expected = scaled + 5
				assert_int(c.grown(real, s)).override_failure_message("%s Lv %d %s" % [id, l, s]).is_equal(expected)


func test_clamp_pulls_hp_and_energy_down_after_a_tier_shrinks_stats() -> void:
	var def := db.creature("blob")
	var saved = def.growth_rates
	var c := CreatureInstance.create(db, "blob", 50)
	var old_hp := c.hp
	var old_energy := c.energy
	def.growth_rates = {"hp": "slow", "stamina": "slow"}
	assert_int(c.max_hp(db)).is_less(old_hp)
	assert_int(c.max_energy(db)).is_less(old_energy)
	c.clamp_to_cap(db)
	assert_int(c.hp).is_equal(c.max_hp(db))
	assert_int(c.energy).is_equal(c.max_energy(db))
	def.growth_rates = saved
