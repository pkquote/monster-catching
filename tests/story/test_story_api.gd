extends GdUnitTestSuite
## The Story autoload: bag, money, creatures and flags on the current game.

var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("story_api", false)


func before_test() -> void:
	GameState.start_new_game("Ana")


func after() -> void:
	WorldTest.end_suite(_suite)


func test_items_and_money() -> void:
	Story.give_item("salve", 2)
	assert_bool(Story.has_item("salve", 2)).is_true()
	assert_bool(Story.take_item("salve", 3)).is_false()
	assert_int(GameState.current.inventory.salve).is_equal(2)
	assert_bool(Story.take_item("salve", 2)).is_true()
	assert_bool(GameState.current.inventory.has("salve")).is_false()
	Story.give_money(300)
	assert_bool(Story.take_money(500)).is_false()
	assert_bool(Story.take_money(100)).is_true()
	assert_int(Story.money()).is_equal(200)


func test_flags_counters_done() -> void:
	Story.set_flag("met_mum")
	Story.add_count("talks", 2)
	Story.mark_done("x/Y")
	assert_bool(Story.flag("met_mum")).is_true()
	assert_int(Story.count("talks")).is_equal(2)
	assert_bool(Story.is_done("x/Y")).is_true()


func test_give_creature_party_then_storage() -> void:
	var c := Story.give_creature("emberkit", 5, true)
	assert_int(c.level).is_equal(5)
	assert_int(c.bond).is_equal(DataRegistry.db.balance.bond_cfg.starter)
	assert_int(Story.party_size()).is_equal(1)
	for i in DataRegistry.db.balance.party_size - 1:
		Story.give_creature("sprigling", 3)
	Story.give_creature("pebblet", 3)
	assert_int(Story.party_size()).is_equal(DataRegistry.db.balance.party_size)
	assert_int(BoxStorage.count(GameState.current)).is_equal(1)
