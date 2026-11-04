extends GdUnitTestSuite
## The pause menu, and menus refusing to open over conversations.

const TALK := "res://tests/fixtures/test_talk.dialogue"

var world: Overworld
var _old_store: SaveStore


func before() -> void:
	_old_store = GameState.store
	GameState.store = SaveStore.new("user://test_pause_saves")


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
	DebugMenu.close()
	world.free()
	Overworld.instant = false
	GameState.close_game()


func test_menu_opens_saves_and_closes() -> void:
	world.open_pause_menu()
	await get_tree().process_frame
	assert_bool(world.pause_menu.is_open()).is_true()
	assert_bool(world.is_locked()).is_true()
	var before := GameState.store.list().size()
	world.pause_menu.menu.pick_label("Save")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(GameState.store.list().size()).is_equal(before + 1)
	world.pause_menu.menu.pick_label("Close")
	await get_tree().process_frame
	assert_bool(world.pause_menu.is_open()).is_false()
	assert_bool(world.is_locked()).is_false()


func test_menu_does_nothing_while_locked() -> void:
	world.lock("dialogue")
	world.open_pause_menu()
	await get_tree().process_frame
	assert_bool(world.pause_menu.is_open()).is_false()
	world.unlock("dialogue")


func test_party_page_lists_creatures() -> void:
	Story.give_creature("tidepup", 5)
	world.open_pause_menu()
	await get_tree().process_frame
	world.pause_menu.menu.pick_label("Party")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).contains("Tidepup")


func test_debug_menu_refuses_during_a_conversation() -> void:
	world.say(TALK, "hello")
	await get_tree().process_frame
	DebugMenu.open()
	assert_bool(DebugMenu.is_open()).is_false()


func test_no_test_battles_from_f1_over_a_menu_or_prompt() -> void:
	Story.give_creature("tidepup", 5)
	world.lock("battle")  # e.g. the wild "how many?" prompt is up
	DebugMenu.open()
	var found := false
	var stack: Array = [DebugMenu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and n.text == "Wild battle (Route 1)":
			found = true
			assert_bool(n.disabled).is_true()
		stack.append_array(n.get_children())
	assert_bool(found).is_true()
	DebugMenu.close()
	world.unlock("battle")
