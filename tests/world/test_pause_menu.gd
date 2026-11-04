extends GdUnitTestSuite
## The pause menu, and menus refusing to open over conversations.

const TALK := "res://tests/fixtures/test_talk.dialogue"

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("pause", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_a", "start")


func after_test() -> void:
	DebugMenu.close()
	WorldTest.close(world)


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
	world.lock(Overworld.LOCK_DIALOGUE)
	world.open_pause_menu()
	await get_tree().process_frame
	assert_bool(world.pause_menu.is_open()).is_false()
	world.unlock(Overworld.LOCK_DIALOGUE)


func test_party_page_lists_creatures() -> void:
	Story.give_creature("tidepup", 5)
	world.open_pause_menu()
	await get_tree().process_frame
	world.pause_menu.menu.pick_label("Party")
	await get_tree().process_frame
	var found := false
	for n in world.get_children():
		if n is PartyScreen:
			found = true
			assert_str(n.menu.labels()[0]).contains("Tidepup")
	assert_bool(found).is_true()


func test_debug_menu_refuses_during_a_conversation() -> void:
	world.say(TALK, "hello")
	await get_tree().process_frame
	DebugMenu.open()
	assert_bool(DebugMenu.is_open()).is_false()


func test_no_test_battles_from_f1_over_a_menu_or_prompt() -> void:
	Story.give_creature("tidepup", 5)
	world.lock(Overworld.LOCK_BATTLE)  # e.g. the wild "how many?" prompt is up
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
	world.unlock(Overworld.LOCK_BATTLE)


## Waits until the pause menu is offering `label`, then picks it.
func _pick(label: String) -> void:
	for i in 200:
		if world.pause_menu.menu.is_choosing() and world.pause_menu.menu.labels().has(label):
			world.pause_menu.menu.pick_label(label)
			await get_tree().process_frame
			return
		await get_tree().process_frame
	fail("pause menu never offered %s" % label)


## Opens the bag and picks the Reset Seed and the first creature.
func _open_seed_target() -> void:
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Bag")
	await _pick("Reset Seed ×1")
	await get_tree().process_frame


func test_bag_reset_seed_confirms_and_refunds() -> void:
	var c := Story.give_creature("tidepup", 20)
	Progression.train(DataRegistry.db, c, "patk", 10)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	assert_str(world.pause_menu.menu.labels()[0]).contains("10 points spent")
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("Return 10 points from Tidepup?")
	assert_int(c.trained("patk")).is_equal(10)
	await _pick("Yes")
	assert_str(world.pause_menu.page_text()).is_equal("Tidepup's 10 points came back.")
	assert_int(Progression.training_points_spent(c)).is_equal(0)
	assert_bool(GameState.current.inventory.has("reset_seed")).is_false()


func test_bag_reset_seed_no_keeps_points() -> void:
	var c := Story.give_creature("tidepup", 10)
	Progression.train(DataRegistry.db, c, "patk", 4)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	await _pick("No")
	assert_int(Progression.training_points_spent(c)).is_equal(4)
	assert_int(GameState.current.inventory.reset_seed).is_equal(1)


func test_bag_reset_seed_nothing_to_refund() -> void:
	Story.give_creature("tidepup", 10)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("It has no points to return.")
	assert_int(GameState.current.inventory.reset_seed).is_equal(1)


func test_bag_reset_seed_one_point_is_singular() -> void:
	var c := Story.give_creature("tidepup", 10)
	Progression.train(DataRegistry.db, c, "patk", 1)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("Return 1 point from Tidepup?")
	await _pick("Yes")
	assert_str(world.pause_menu.page_text()).is_equal("Tidepup's 1 point came back.")
