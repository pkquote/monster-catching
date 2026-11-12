extends GdUnitTestSuite
## The shipped multi-hit moves: loaded cleanly, taught at the stated levels, tuned in range.

## id -> [type, category, power, cost, accuracy, hits_min, hits_max, teacher, level]
const MOVES := {
	"twin_splash": ["water", "special", 28, 5, 100, 2, 2, "tidepup", 15],
	"needle_flurry": ["ice", "physical", 20, 5, 95, 3, 3, "frostling", 10],
	"spark_volley": ["electric", "special", 16, 6, 100, 2, 5, "voltmoth", 15],
}

var db: Database


func before() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert_array(Array(result.errors)).is_empty()
	assert_array(Array(result.warnings)).is_empty()
	db = result.db


func test_shipped_multi_hit_moves() -> void:
	for id: String in MOVES:
		var want: Array = MOVES[id]
		assert_bool(db.has("moves", id)).override_failure_message(id).is_true()
		var m := db.move(id)
		assert_str(m.target).is_equal("one_enemy")
		assert_str(m.type).is_equal(want[0])
		assert_str(m.category).is_equal(want[1])
		assert_int(m.power).is_equal(want[2])
		assert_int(m.cost).is_equal(want[3])
		assert_int(m.accuracy).is_equal(want[4])
		assert_int(m.hits_min).is_equal(want[5])
		assert_int(m.hits_max).is_equal(want[6])
		var taught := db.creature(want[7]).learnset.filter(func(l: Dictionary) -> bool: return l.move == id)
		assert_int(taught.size()).override_failure_message("%s teacher" % id).is_equal(1)
		assert_int(taught[0].level).is_equal(want[8])


func test_exactly_these_moves_are_multi_hit() -> void:
	var found := []
	for id in db.ids("moves"):
		if db.move(id).is_multi_hit():
			found.append(id)
	assert_array(found).contains_exactly_in_any_order(MOVES.keys())


func test_each_move_beats_a_single_target_move_of_its_cost_on_average() -> void:
	for id: String in MOVES:
		var m := db.move(id)
		var expected := m.power * m.mean_hits()
		assert_float(expected).override_failure_message("%s expects %s" % [id, expected]).is_between(55.0, 62.0)


func test_the_compendium_lists_the_hit_counts() -> void:
	var text := CompendiumBuilder.build(db)
	assert_str(text).contains("Hits 2 times")
	assert_str(text).contains("Hits 3 times")
	assert_str(text).contains("Hits 2-5 times")


func test_players_see_the_hit_count_in_move_lists() -> void:
	# The Learn Move / Summary line and the battle's move menu carry it, so a x2 move is not read as weak.
	assert_str(LearnMoveScreen.move_line(db, "twin_splash")).contains("Power 28 x2")
	assert_str(LearnMoveScreen.move_line(db, "spark_volley")).contains("Power 16 x2-5")
	assert_str(LearnMoveScreen.move_line(db, "tide_beam")).not_contains(" x")
	assert_str(BattleText.move_label(db, db.move("needle_flurry"), 5)).contains("P20 x3")
	assert_str(BattleText.move_label(db, db.move("splash_jab"), 2)).is_equal("Splash Jab · Water P40 · 2 EN")
