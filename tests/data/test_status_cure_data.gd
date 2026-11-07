extends GdUnitTestSuite
## Shipped and test-pack content for the cure_status op.


func test_clear_tonic_is_a_priced_heal_item() -> void:
	var db: Database = DataLoader.load_database("res://data").db
	var it := db.item("clear_tonic")
	assert_object(it).is_not_null()
	assert_str(it.name).is_equal("Clear Tonic")
	assert_str(it.category).is_equal("heal")
	assert_int(it.price).is_equal(200)
	assert_str(it.target).is_equal("one_ally")
	assert_array(it.effects).is_equal([{"op": "cure_status"}])
	assert_bool(FieldItems.can_use(db, "clear_tonic")).is_true()


func test_pack_cure_content_exists() -> void:
	var db: Database = DataLoader.load_database("res://data", "", ["res://data_testpack"]).db
	var full := db.item("tp_full_restore")
	assert_bool(full.effects.any(func(e): return e.op == "cure_status")).is_true()
	assert_array(db.item("tp_antidote").effects).is_equal([{"op": "cure_status", "status": "burn"}])
	assert_array(db.item("tp_cure_all").effects).is_equal([{"op": "cure_status"}])
	assert_object(db.move("tp_purify")).is_not_null()
	assert_object(db.passive("tp_purifier")).is_not_null()
	var berry := db.item("tp_clear_berry")
	assert_str(berry.held_use).is_equal("consumed")
	assert_str(berry.held.triggers[0].on).is_equal("status")
