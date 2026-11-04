extends GdUnitTestSuite
## The WorldTest helper that overworld suites use for their setup and cleanup.

const NAME := "world_helper_probe"


func test_suite_state_swaps_and_restores_saves_and_text_speed() -> void:
	var store_before := GameState.store
	var speed_before: String = Settings.data.text_speed
	var state := WorldTest.begin_suite(NAME)
	assert_object(GameState.store).is_not_same(store_before)
	assert_str(GameState.store.root).is_equal("user://test_%s_saves" % NAME)
	assert_str(Settings.data.text_speed).is_equal("instant")
	GameState.start_new_game("Ana")
	GameState.save_manual()
	GameState.close_game()
	assert_bool(DirAccess.dir_exists_absolute(GameState.store.root)).is_true()
	WorldTest.end_suite(state)
	assert_object(GameState.store).is_same(store_before)
	assert_str(Settings.data.text_speed).is_equal(speed_before)
	assert_bool(DirAccess.dir_exists_absolute("user://test_%s_saves" % NAME)).is_false()  # cleaned up


func test_open_and_close_a_world() -> void:
	var state := WorldTest.begin_suite(NAME)
	var world := await WorldTest.open(self, "test_b", "middle")
	assert_bool(Overworld.instant).is_true()
	assert_bool(GameState.has_game()).is_true()
	assert_str(world.map.map_id()).is_equal("test_b")
	assert_object(Overworld.active).is_same(world)
	WorldTest.close(world)
	assert_bool(Overworld.instant).is_false()
	assert_bool(GameState.has_game()).is_false()
	assert_object(Overworld.active).is_null()
	WorldTest.end_suite(state)


func test_open_without_a_game() -> void:
	var state := WorldTest.begin_suite(NAME)
	var world := await WorldTest.open(self, "", "", WorldTest.NO_GAME)
	assert_bool(GameState.has_game()).is_false()
	assert_str(world.map.map_id()).is_equal(Overworld.DEBUG_MAP)
	WorldTest.close(world)
	WorldTest.end_suite(state)


func test_find_screen_and_finish_talk() -> void:
	var state := WorldTest.begin_suite(NAME)
	var world := await WorldTest.open(self, "test_a", "start")
	world.say_lines([{"speaker": "", "text": "one"}, {"speaker": "", "text": "two"}])
	await get_tree().process_frame
	assert_bool(world.is_talking()).is_true()
	await WorldTest.finish_talk(world)
	assert_bool(world.is_talking()).is_false()
	StorageScreen.run(world)
	await get_tree().process_frame
	assert_bool(WorldTest.find_screen(world, StorageScreen) is StorageScreen).is_true()
	assert_object(WorldTest.find_screen(world, PartyScreen)).is_null()
	WorldTest.find_screen(world, StorageScreen).close()
	WorldTest.close(world)
	WorldTest.end_suite(state)
