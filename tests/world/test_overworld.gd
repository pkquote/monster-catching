extends GdUnitTestSuite
## The overworld screen: map changes through doors, arrival tiles, locking, camera.

const DT := 1.0 / 60.0

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("overworld", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "", "", WorldTest.NO_GAME)


func after_test() -> void:
	WorldTest.close(world)


## Walks for `seconds`, stopping early if a door changes the map (real input is
## locked during the change, so a held direction can't carry through it).
func _walk(dir: Vector2, seconds: float) -> void:
	var start := world.map
	for i in roundi(seconds / DT):
		world.player.step(dir, false, DT)
		if world.map != start:
			break
	await get_tree().process_frame


func test_starts_on_test_map_without_a_game() -> void:
	assert_str(world.map.map_id()).is_equal("test_a")
	assert_object(world.player.feet_tile()).is_equal(world.map.spawn("start").tile())


func test_door_changes_map() -> void:
	var changed: Array = []
	world.map_changed.connect(func(m): changed.append(m.map_id()))
	world.player.place(GameMap.centre_of(Vector2i(4, 4)), Vector2i.DOWN)
	await _walk(Vector2.DOWN, 0.4)
	assert_array(changed).is_equal(["test_b"])
	assert_str(world.map.map_id()).is_equal("test_b")
	assert_object(world.player.feet_tile()).is_equal(world.map.spawn("from_a").tile())
	assert_bool(world.player.get_parent() == world.map.entities()).is_true()


func test_arrival_tile_never_fires() -> void:
	await world.change_map("test_b", "from_a")  # from_a sits on test_b's door tile
	var changed: Array = []
	world.map_changed.connect(func(m): changed.append(m.map_id()))
	await _walk(Vector2.DOWN, 0.2)  # pushes against the map edge, still on the door tile
	assert_array(changed).is_empty()
	await _walk(Vector2.UP, 0.3)
	await _walk(Vector2.DOWN, 0.4)
	assert_array(changed).is_equal(["test_a"])


func test_map_edge_blocks() -> void:
	await world.change_map("test_b", "from_a")
	await _walk(Vector2.DOWN, 1.0)
	assert_bool(world.map.bounds().has_point(world.player.feet_tile())).is_true()


func test_lock_freezes_player() -> void:
	world.lock(Overworld.LOCK_MENU)
	assert_bool(world.is_locked()).is_true()
	assert_bool(world.player.locked).is_true()
	world.lock(Overworld.LOCK_DIALOGUE)
	world.unlock(Overworld.LOCK_MENU)
	assert_bool(world.is_locked()).is_true()
	world.unlock(Overworld.LOCK_DIALOGUE)
	assert_bool(world.player.locked).is_false()


func test_camera_centres_small_maps() -> void:
	var b := world.map.bounds()
	await get_tree().process_frame
	assert_object(world.camera.position).is_equal(Vector2(b.get_center()) * GameMap.TILE)


# --- Resuming (Task 6) ---------------------------------------------------------

func _with_game() -> void:
	world.free()
	GameState.store = SaveStore.new("user://test_overworld_saves")
	GameState.start_new_game("Ana")


func _rebuild() -> void:
	world = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame


func test_resume_restores_exact_position() -> void:
	_with_game()
	GameState.current.position = {"map": "test_b", "x": 123.0, "y": 77.0, "facing": "left"}
	await _rebuild()
	assert_str(world.map.map_id()).is_equal("test_b")
	assert_object(world.player.position).is_equal(Vector2(123, 77))
	assert_object(world.player.facing).is_equal(Vector2i.LEFT)
	world.player.place(Vector2(150, 90), Vector2i.UP)
	GameState.autosave()
	var r := GameState.store.read(GameState.current_path)
	assert_dict(r.save.position).is_equal({"map": "test_b", "x": 150.0, "y": 90.0, "facing": "up"})
	GameState.close_game()


func test_missing_map_falls_back() -> void:
	_with_game()
	GameState.current.position = {"map": "deleted_map", "x": 10.0, "y": 10.0, "facing": "down"}
	await _rebuild()
	assert_str(world.map.map_id()).is_equal(Overworld.new_game_map())
	GameState.close_game()


func test_resume_inside_trigger_does_not_fire() -> void:
	_with_game()
	GameState.current.position = {"map": "test_a", "x": 144.0, "y": 176.0, "facing": "down"}  # on Door1
	await _rebuild()
	assert_str(world.map.map_id()).is_equal("test_a")
	await _walk(Vector2.UP, 0.3)
	await _walk(Vector2.DOWN, 0.4)
	assert_str(world.map.map_id()).is_equal("test_b")
	GameState.close_game()


func test_map_change_autosaves_and_sets_location() -> void:
	_with_game()
	await _rebuild()
	var shown: Array = []
	world.banner.shown.connect(func(t): shown.append(t))
	await world.change_map("test_b", "middle")
	assert_str(GameState.current.location).is_equal("Test Field")
	assert_bool(GameState.store.list().any(func(e): return e.kind == SaveGame.KIND_AUTO)).is_true()
	await world.change_map("test_b", "from_a")  # same place name: no banner again
	assert_array(shown).is_equal(["Test Field"])
	GameState.close_game()


func test_every_lock_name_is_a_known_constant() -> void:
	for name in Overworld.LOCKS:
		world.lock(name)
		assert_bool(world.is_locked()).is_true()
		world.unlock(name)
	assert_bool(world.is_locked()).is_false()
	assert_str(Overworld.LOCK_MENU).is_equal("menu")


func test_an_unknown_lock_name_is_logged_as_an_error() -> void:
	var got: Array = []
	var state := Log.save_state()
	var sink := func(r: Dictionary) -> void: got.append(r)
	Log.add_sink(sink)
	world.lock("menuu")
	world.unlock("menuu")
	Log.restore_state(state)
	var errors := got.filter(func(r): return r.level == Log.Level.ERROR and r.category == Log.WORLD)
	assert_int(errors.size()).is_equal(2)
