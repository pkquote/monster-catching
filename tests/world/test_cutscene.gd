extends GdUnitTestSuite
## Cutscene commands: moving and turning actors, locking, typos don't hang.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("cutscene", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_a", "start")


func after_test() -> void:
	WorldTest.close(world)


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


func test_script_that_forgets_unlock_gives_control_back() -> void:
	var old_speed: String = Settings.data.text_speed
	Settings.data.text_speed = "instant"
	world.say("res://tests/fixtures/test_talk.dialogue", "forgets_unlock")
	for i in 100:
		if not world.is_talking():
			break
		world.dialogue_box.press_accept()
		await get_tree().process_frame
	Settings.data.text_speed = old_speed
	assert_bool(world.is_talking()).is_false()
	assert_bool(world.is_locked()).is_false()


func test_fading_to_where_the_screen_already_is_does_not_wait() -> void:
	Overworld.instant = false
	await Cutscene.fade_out()
	var start := Engine.get_process_frames()
	await Cutscene.fade_out()
	await world.fade(1.0)
	var waited := Engine.get_process_frames() - start
	await Cutscene.fade_in()
	Overworld.instant = true
	assert_int(waited).is_equal(0)


func test_camera_pan_and_back() -> void:
	await Cutscene.pan_camera("start")
	assert_bool(world.camera_focus != null).is_true()
	await Cutscene.camera_back()
	assert_bool(world.camera_focus == null).is_true()
