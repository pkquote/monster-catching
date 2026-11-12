extends GdUnitTestSuite
## Multi-hit moves' data: the `hits` field, `balance.max_hits` and the hits label.


func _raw_with(hits: Variant, target := "one_enemy") -> RawData:
	var r := FixtureDB.raw()
	var extra := {} if hits == null else {"hits": hits}
	r.add_entry("moves", FixtureDB.move("flurry", "neutral", "physical", 20, 100, target,
		[{"op": "damage"}], extra))
	return r


func _errors(r: RawData) -> String:
	return "\n".join(DataValidator.validate(r))


func _db_with(hits: Variant) -> Database:
	var r := _raw_with(hits)
	assert(DataValidator.validate(r).is_empty())
	return Database.from_raw(r)


func test_a_move_without_hits_hits_once() -> void:
	var m := FixtureDB.build().move("hit")
	assert_int(m.hits_min).is_equal(1)
	assert_int(m.hits_max).is_equal(1)
	assert_bool(m.is_multi_hit()).is_false()
	assert_float(m.mean_hits()).is_equal(1.0)


func test_hits_range_is_read() -> void:
	var m := _db_with({"min": 2, "max": 5}).move("flurry")
	assert_int(m.hits_min).is_equal(2)
	assert_int(m.hits_max).is_equal(5)
	assert_bool(m.is_multi_hit()).is_true()
	assert_float(m.mean_hits()).is_equal(3.5)


func test_a_fixed_count_is_min_equal_max() -> void:
	var r := _raw_with({"min": 3, "max": 3})
	assert_str(_errors(r)).is_empty()
	var m := Database.from_raw(r).move("flurry")
	assert_bool(m.is_multi_hit()).is_true()
	assert_float(m.mean_hits()).is_equal(3.0)


func test_validator_rejects_bad_hits() -> void:
	var cases := {
		"min_above_max": _raw_with({"min": 3, "max": 2}),
		"zero_min": _raw_with({"min": 0, "max": 2}),
		"above_balance": _raw_with({"min": 1, "max": 6}),
		"two_enemies_target": _raw_with({"min": 2, "max": 3}, "two_enemies"),
		"self_target": _raw_with({"min": 2, "max": 3}, "self"),
		"all_target": _raw_with({"min": 2, "max": 3}, "all_enemies"),
	}
	for label: String in cases:
		assert_str(_errors(cases[label])).override_failure_message(label).contains("hits")


func test_balance_max_hits_range() -> void:
	for n: int in [1, 11]:
		var r := FixtureDB.raw()
		var b := FixtureDB.balance()
		b["max_hits"] = n
		r.set_single("balance", b)
		assert_str(_errors(r)).override_failure_message("max_hits %d" % n).contains("max_hits")
	for n: int in [2, 5, 10]:
		var r := FixtureDB.raw()
		var b := FixtureDB.balance()
		b["max_hits"] = n
		r.set_single("balance", b)
		assert_str(_errors(r)).override_failure_message("max_hits %d" % n).is_empty()


func test_shipped_balance_has_max_hits_five() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert_int(result.db.balance.max_hits).is_equal(5)


func test_hits_label_wording() -> void:
	assert_str(EffectText.hits_label(FixtureDB.build().move("hit"))).is_empty()
	assert_str(EffectText.hits_label(_db_with({"min": 3, "max": 3}).move("flurry"))).is_equal("Hits 3 times")
	assert_str(EffectText.hits_label(_db_with({"min": 2, "max": 2}).move("flurry"))).is_equal("Hits 2 times")
	assert_str(EffectText.hits_label(_db_with({"min": 2, "max": 5}).move("flurry"))).is_equal("Hits 2-5 times")


func test_compendium_moves_table_shows_the_hits_label() -> void:
	var text := CompendiumBuilder.build(_db_with({"min": 2, "max": 5}))
	var row := ""
	for line in text.split("\n"):
		if line.begins_with("| **Flurry**"):
			row = line
	assert_str(row).contains("Hits 2-5 times")


func test_hits_short_wording() -> void:
	assert_str(EffectText.hits_short(FixtureDB.build().move("hit"))).is_empty()
	assert_str(EffectText.hits_short(_db_with({"min": 3, "max": 3}).move("flurry"))).is_equal("x3")
	assert_str(EffectText.hits_short(_db_with({"min": 2, "max": 5}).move("flurry"))).is_equal("x2-5")
