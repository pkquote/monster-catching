extends GdUnitTestSuite
## The conversation box: runs a Dialogue Manager title to the end, applies
## mutations, types text at the Text speed setting, refuses to stack.

const TALK := "res://tests/fixtures/test_talk.dialogue"

var world: Overworld
var _old_speed := ""
var _old_store: SaveStore


func before() -> void:
	_old_speed = Settings.data.text_speed
	_old_store = GameState.store
	GameState.store = SaveStore.new("user://test_dialogue_saves")


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
	Settings.data.text_speed = _old_speed
	GameState.close_game()


## Presses Accept (or picks the first response) until the conversation ends.
func _drive(done: Array) -> void:
	for i in 200:
		if not done.is_empty():
			return
		var box := world.dialogue_box
		if box.menu.is_choosing():
			box.menu.pick_label(box.menu.labels()[0])
		else:
			box.press_accept()
		await get_tree().process_frame


func test_runs_to_end_and_mutations_apply() -> void:
	Settings.data.text_speed = "instant"
	var done: Array = []
	var run := func():
		await world.say(TALK, "hello")
		done.append(true)
	run.call()
	assert_bool(world.is_locked()).is_true()
	await _drive(done)
	assert_bool(done.is_empty()).is_false()
	assert_bool(Story.flag("talked")).is_true()
	assert_bool(world.is_locked()).is_false()


func test_accept_completes_line_first() -> void:
	Settings.data.text_speed = "slow"
	world.say(TALK, "sets_flag")
	await get_tree().process_frame
	await get_tree().process_frame
	var box := world.dialogue_box
	assert_bool(box.is_typing()).is_true()
	box.press_accept()
	assert_bool(box.is_typing()).is_false()
	assert_str(box.shown_text()).is_equal("Flag set.")
	assert_bool(box.visible_now()).is_true()  # still on the line until the next Accept
	box.press_accept()
	for i in 10:
		await get_tree().process_frame
	assert_bool(box.visible_now()).is_false()


func test_second_say_is_refused() -> void:
	Settings.data.text_speed = "instant"
	var done: Array = []
	var first := func():
		await world.say(TALK, "hello")
		done.append("first")
	first.call()
	await world.say(TALK, "sets_flag")  # returns at once: a conversation is already running
	assert_bool(Story.flag("talked")).is_false()
	await _drive(done)
	assert_array(done).is_equal(["first"])


func test_lines_without_a_file() -> void:
	Settings.data.text_speed = "instant"
	var done: Array = []
	var run := func():
		await world.say_lines([{"speaker": "", "text": "Found a Salve!"}])
		done.append(true)
	run.call()
	await get_tree().process_frame
	assert_str(world.dialogue_box.shown_text()).is_equal("Found a Salve!")
	await _drive(done)
	assert_bool(done.is_empty()).is_false()
