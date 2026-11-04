extends GdUnitTestSuite
## Cutscene commands: moving and turning actors, locking, typos don't hang.

var world: Overworld
var _old_store: SaveStore


func before() -> void:
	_old_store = GameState.store
	GameState.store = SaveStore.new("user://test_cutscene_saves")


func after() -> void:
	GameState.store = _old_store


func before_test() -> void:
	Overworld.instant = true
	GameState.start_new_game("Ana")
	world = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await world.change_map("test_a", "start")


func after_test() -> void:
	world.free()
	Overworld.instant = false
	GameState.close_game()


func _guide() -> Npc:
	return world.map.entities().get_node("Guide") as Npc


func test_move_actor_to_spawn_and_tile() -> void:
	await Cutscene.move("guide", "start")
	assert_object(_guide().tile()).is_equal(world.map.spawn("start").tile())
	await Cutscene.move("player", "5,3")
	assert_object(world.player.feet_tile()).is_equal(Vector2i(5, 3))


func test_face_another_actor_and_direction() -> void:
	world.player.place(GameMap.centre_of(Vector2i(6, 3)), Vector2i.DOWN)
	await Cutscene.face("player", "guide")
	assert_object(world.player.facing).is_equal(Vector2i.UP)
	await Cutscene.face("guide", "left")
	assert_object(_guide().facing).is_equal(Vector2i.LEFT)


func test_unknown_actor_or_spot_returns() -> void:
	await Cutscene.move("nobody", "start")
	await Cutscene.move("guide", "no_such_spawn")
	assert_object(_guide().tile()).is_equal(Vector2i(6, 1))


func test_lock_round_trip() -> void:
	await Cutscene.lock_player()
	assert_bool(world.is_locked()).is_true()
	await Cutscene.unlock_player()
	assert_bool(world.is_locked()).is_false()


func test_camera_pan_and_back() -> void:
	await Cutscene.pan_camera("start")
	assert_bool(world.camera_focus != null).is_true()
	await Cutscene.camera_back()
	assert_bool(world.camera_focus == null).is_true()
