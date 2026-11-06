extends GdUnitTestSuite
## The party_size schema ceiling and how party-adding code reads it.


func _raw_with_party_size(n: int) -> RawData:
	var r: RawData = FixtureDB.raw()
	var b: Dictionary = FixtureDB.balance()
	b["party_size"] = n
	r.set_single("balance", b)
	return r


func _db_with_party_size(n: int) -> Database:
	return FixtureDB.build({"party_size": n})


func _save_with(db: Database, count: int) -> SaveGame:
	var s: SaveGame = SaveGame.new()
	for i: int in count:
		s.party.append(FixtureDB.make(db, "blob", 10, ["hit"]))
	return s


func test_max_party_size_constant_is_twelve() -> void:
	assert_int(BalanceDef.MAX_PARTY_SIZE).is_equal(12)


func test_accepts_1_through_12() -> void:
	for n: int in [1, 6, 12]:
		var errors: Array = DataValidator.validate(_raw_with_party_size(n))
		assert_array(errors).is_empty()


func test_rejects_0_and_13() -> void:
	for n: int in [0, 13]:
		var errors: Array = DataValidator.validate(_raw_with_party_size(n))
		assert_array(errors).is_not_empty()
		assert_bool(errors.any(func(e: Variant) -> bool: return str(e).contains("party_size"))).is_true()


func test_team_add_respects_changed_size() -> void:
	var db: Database = _db_with_party_size(8)
	var s: SaveGame = _save_with(db, 7)
	assert_bool(BattleLauncher.add_to_party(db, s, FixtureDB.make(db, "fish", 3))).is_true()
	assert_int(s.party.size()).is_equal(8)
	assert_bool(BattleLauncher.add_to_party(db, s, FixtureDB.make(db, "fish", 3))).is_false()
	assert_int(s.party.size()).is_equal(8)
	assert_int(s.storage.size()).is_equal(1)


func test_oversized_party_in_save_is_kept() -> void:
	var db: Database = _db_with_party_size(3)
	var s: SaveGame = _save_with(db, 5)
	assert_bool(BattleLauncher.add_to_party(db, s, FixtureDB.make(db, "fish", 3))).is_false()
	assert_int(s.party.size()).is_equal(5)
	assert_int(s.storage.size()).is_equal(1)


func test_shipped_balance_allows_one_field_state() -> void:
	var db: Database = DataLoader.load_database("res://data").db
	assert_int(db.balance.max_field_states).is_equal(1)
