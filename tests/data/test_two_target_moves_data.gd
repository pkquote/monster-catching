extends GdUnitTestSuite
## The shipped `two_enemies` moves: loaded cleanly, taught by a species, tuned in range.


func test_shipped_two_target_moves() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert_array(Array(result.errors)).is_empty()
	assert_array(Array(result.warnings)).is_empty()
	var db: Database = result.db
	var found := 0
	for id in db.ids("moves"):
		var move := db.move(id)
		if move.target != "two_enemies":
			continue
		found += 1
		var learners := 0
		for cid in db.ids("creatures"):
			for entry in db.creature(cid).learnset:
				if entry.move == id:
					learners += 1
		assert_int(learners).override_failure_message("%s has no teacher" % id).is_greater(0)
		assert_int(move.power).is_between(38, 48)
		assert_int(move.cost).is_between(4, 5)
		assert_int(move.accuracy).is_equal(100)
	assert_int(found).is_greater_equal(3)
