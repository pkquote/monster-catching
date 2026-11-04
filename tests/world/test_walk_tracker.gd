extends GdUnitTestSuite
## Walking restores 1 energy per creature every few tiles.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func test_energy_every_n_tiles_for_healthy_creatures() -> void:
	var a := FixtureDB.make(db, "blob", 10)
	var b := FixtureDB.make(db, "blob", 10)
	var full := FixtureDB.make(db, "blob", 10)
	a.energy = 0
	b.energy = 0
	b.hp = 0
	var w := WalkTracker.new(db.balance)
	var n: int = db.balance.overworld_cfg.walk_energy_tiles
	for i in n - 1:
		assert_bool(w.on_tile(db, [a, b, full])).is_false()
	assert_int(a.energy).is_equal(0)
	assert_bool(w.on_tile(db, [a, b, full])).is_true()
	assert_int(a.energy).is_equal(1)
	assert_int(b.energy).is_equal(0)  # fainted creatures don't recover
	assert_int(full.energy).is_equal(full.max_energy(db))
