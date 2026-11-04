extends GdUnitTestSuite
## Story.start_minigame: opens over the paused map, returns the result, unlocks.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("minigame", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self)


func after_test() -> void:
	WorldTest.close(world)


func test_minigame_result_comes_back() -> void:
	var r := await Story.start_minigame_scene("res://tests/fixtures/stub_minigame.tscn", {"score": 9})
	assert_dict(r).is_equal({"won": true, "score": 9})
	assert_dict(Story.last_minigame()).is_equal({"won": true, "score": 9})
	assert_bool(world.is_locked()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_quick_draw_is_in_the_data() -> void:
	var m := DataRegistry.db.minigame("quick_draw")
	assert_object(m).is_not_null()
	assert_bool(ResourceLoader.exists(m.scene)).is_true()


func test_unknown_minigame_returns_a_loss() -> void:
	var r := await Story.start_minigame("no_such_game")
	assert_bool(r.won).is_false()
	assert_bool(world.is_locked()).is_false()
