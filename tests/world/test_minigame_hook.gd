extends GdUnitTestSuite
## Story.start_minigame: opens over the paused map, returns the result, unlocks.

var world: Overworld
var _old_store: SaveStore


func before() -> void:
	_old_store = GameState.store
	GameState.store = SaveStore.new("user://test_minigame_saves")


func after() -> void:
	GameState.store = _old_store


func before_test() -> void:
	Overworld.instant = true
	GameState.start_new_game("Ana")
	world = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame


func after_test() -> void:
	world.free()
	Overworld.instant = false
	GameState.close_game()


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
