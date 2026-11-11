extends GdUnitTestSuite
## The shipped achievements in data/achievements/.

const STARTER := ["first_steps", "first_victory", "tamer_trouncer", "first_catch", "field_notes", "collector",
	"first_evolution", "rising_star", "close_friends", "big_spender", "quick_on_the_draw"]

var db: Database


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "res://dialogue")
	assert_bool(result.ok()).is_true()
	db = result.db


func test_the_starter_set_is_there() -> void:
	assert_array(Array(db.ids("achievements"))).contains_exactly(STARTER)


func test_every_kind_is_used() -> void:
	var kinds := {}
	for id in db.ids("achievements"):
		kinds[db.achievement(id).criterion.kind] = true
	for kind in Criteria.kinds():
		assert_bool(kinds.has(kind)).override_failure_message("no achievement uses " + kind).is_true()


func test_exactly_one_hidden_and_it_is_the_flag_one() -> void:
	var hidden := []
	for id in db.ids("achievements"):
		if db.achievement(id).hidden:
			hidden.append(id)
	assert_array(hidden).is_equal(["quick_on_the_draw"])
	assert_str(db.achievement("quick_on_the_draw").criterion.flag).is_equal("quick_draw_won")


func test_no_test_content_is_shipped() -> void:
	for id in db.ids("achievements"):
		assert_bool(Database.is_test_content(id)).is_false()


func test_codex_targets_fit_the_species() -> void:
	var species := Codex.order(db).size()
	for id in db.ids("achievements"):
		var c: Dictionary = db.achievement(id).criterion
		if c.kind == "codex" and c.mode != "species":
			assert_int(int(c.target)).is_less_equal(species)
