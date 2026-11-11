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
	DataRegistry.db._tables["items"].erase("test_charm")
	DebugMenu.close()
	WorldTest.close(world)


func test_menu_opens_saves_and_closes() -> void:
	world.open_pause_menu()
	await get_tree().process_frame
	assert_object(WorldTest.find_screen(world, CodexScreen)).is_null()
	assert_bool(world.pause_menu.menu.is_choosing()).is_true()
	assert_bool(world.pause_menu.menu.labels().has("Codex")).is_true()
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
	Training.train(DataRegistry.db, c, "patk", 10)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	assert_str(world.pause_menu.menu.labels()[0]).contains("10 points spent")
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("Return 10 points from Tidepup?")
	assert_int(c.trained("patk")).is_equal(10)
	await _pick("Yes")
	assert_str(world.pause_menu.page_text()).is_equal("Tidepup's 10 points came back.")
	assert_int(Training.spent(c)).is_equal(0)
	assert_bool(GameState.current.inventory.has("reset_seed")).is_false()


func test_bag_reset_seed_no_keeps_points() -> void:
	var c := Story.give_creature("tidepup", 10)
	Training.train(DataRegistry.db, c, "patk", 4)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	await _pick("No")
	assert_int(Training.spent(c)).is_equal(4)
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
	Training.train(DataRegistry.db, c, "patk", 1)
	GameState.current.inventory["reset_seed"] = 1
	await _open_seed_target()
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("Return 1 point from Tidepup?")
	await _pick("Yes")
	assert_str(world.pause_menu.page_text()).is_equal("Tidepup's 1 point came back.")


func test_bag_held_item_points_to_the_summary() -> void:
	DataRegistry.db._tables["items"]["test_charm"] = ItemDef.from_dict({"id": "test_charm", "name": "Test Charm",
		"description": "Raises Physical Attack.", "category": "held", "price": 10, "held": {"effects": []}})
	Story.give_creature("tidepup", 5)
	GameState.current.inventory["test_charm"] = 1
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Bag")
	await _pick("Test Charm ×1")
	var text := world.pause_menu.page_text()
	assert_str(text).contains("Raises Physical Attack.")
	assert_str(text).contains("Give it from the Summary.")
	assert_str(text).not_contains("on who?")
	assert_int(int(GameState.current.inventory["test_charm"])).is_equal(1)


func test_bag_unknown_item_shows_a_page_with_back() -> void:
	Story.give_creature("tidepup", 5)
	GameState.current.inventory["ghost"] = 1
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Bag")
	await _pick("ghost ×1")
	assert_str(world.pause_menu.page_text()).contains("ghost")
	assert_str(world.pause_menu.page_text()).contains("Unknown item.")
	assert_bool(world.pause_menu.menu.labels().has("Back")).is_true()
	await _pick("Back")
	assert_int(int(GameState.current.inventory["ghost"])).is_equal(1)


## The bag list's buttons, Back last.
func _bag_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for n: Node in world.pause_menu.menu._grid.get_children():
		if n is Button and not n.is_queued_for_deletion():
			out.append(n as Button)
	return out


func _open_bag_with_three_items() -> BagSummary:
	var c := Story.give_creature("tidepup", 5)
	c.hp = 1
	GameState.current.inventory = {"salve": 2, "oran_berry": 1, "lure_cage": 4}
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Bag")
	await get_tree().process_frame
	return world.pause_menu.bag_summary()


func test_bag_summary_follows_the_focused_item() -> void:
	var s := await _open_bag_with_three_items()
	assert_bool(s.is_visible_in_tree()).is_true()
	assert_str(world.pause_menu.page_text()).is_equal("")
	var buttons := _bag_buttons()
	assert_int(buttons.size()).is_equal(4)
	var expected: Array = [["Salve", "heal", "Owned: 2", "Usable now."],
		["Oran Berry", "held", "Owned: 1", "Give it from the Summary."],
		["Lure Cage", "capture", "Owned: 4", "Used in battle."]]
	for i: int in expected.size():
		buttons[i].grab_focus()
		await get_tree().process_frame
		assert_str(s.title_text()).is_equal(expected[i][0])
		assert_str(s.icon_category()).is_equal(expected[i][1])
		assert_str(s.body_text()).contains(expected[i][2])
		assert_bool(s.body_text().ends_with("\n" + expected[i][3])).override_failure_message(
			"use line of %s: %s" % [expected[i][0], s.body_text()]).is_true()
	buttons[3].grab_focus()  # Back
	await get_tree().process_frame
	assert_str(s.title_text()).is_equal("")
	assert_str(s.body_text()).is_equal("Pick an item.")
	buttons[1].grab_focus()
	await get_tree().process_frame
	assert_str(s.title_text()).is_equal("Oran Berry")


func test_closing_the_bag_hides_the_summary() -> void:
	var s := await _open_bag_with_three_items()
	_bag_buttons()[0].grab_focus()
	await get_tree().process_frame
	await _pick("Back")
	await get_tree().process_frame
	assert_bool(world.pause_menu.menu.labels().has("Party")).is_true()
	assert_bool(s.is_visible_in_tree()).is_false()
	world.pause_menu.menu.pick_label("Save")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("Saved.")
	assert_bool(s.is_visible_in_tree()).is_false()


func test_bag_summary_gives_way_to_use_on_who_and_comes_back() -> void:
	var s := await _open_bag_with_three_items()
	await _pick("Salve ×2")
	await get_tree().process_frame
	assert_bool(s.is_visible_in_tree()).is_false()
	assert_str(world.pause_menu.page_text()).contains("Use the Salve on who?")
	assert_str(world.pause_menu.menu.labels()[0]).contains("Tidepup")
	await _pick("Back")
	await get_tree().process_frame
	assert_bool(s.is_visible_in_tree()).is_true()
	assert_str(s.title_text()).is_equal("Salve")
	await _pick("Salve ×2")
	world.pause_menu.menu.pick_label("Tidepup")
	await get_tree().process_frame
	assert_str(world.pause_menu.page_text()).is_equal("Tidepup recovered.")
	assert_bool(s.is_visible_in_tree()).is_false()
	assert_int(int(GameState.current.inventory["salve"])).is_equal(1)


func test_bag_summary_can_not_use_message_replaces_it() -> void:
	var s := await _open_bag_with_three_items()
	await _pick("Lure Cage ×4")
	await get_tree().process_frame
	assert_bool(s.is_visible_in_tree()).is_false()
	assert_str(world.pause_menu.page_text()).contains("Lure Cage")
	assert_str(world.pause_menu.page_text()).not_contains("on who?")


func test_empty_bag_says_so() -> void:
	GameState.current.inventory = {}
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Bag")
	await get_tree().process_frame
	var s := world.pause_menu.bag_summary()
	assert_str(s.body_text()).is_equal("Your bag is empty.")
	_bag_buttons()[0].grab_focus()
	await get_tree().process_frame
	assert_str(s.body_text()).is_equal("Your bag is empty.")


func _hovered_connections() -> int:
	return world.pause_menu.menu.get_signal_connection_list("hovered").size()


func test_paged_bag_page_buttons_and_page_two() -> void:
	Story.give_creature("tidepup", 5)
	var ids: Array = ["salve", "tonic", "lure_cage", "tide_net", "snare_vine", "reset_seed", "tide_charm",
		"oran_berry", "rough_bark", "scout_lens", "guard_banner", "ghost"]
	var inv: Dictionary = {}
	for id: String in ids:
		inv[id] = 1
	GameState.current.inventory = inv
	assert_int(ids.size() + 1).is_greater(SideMenu.MENU_ROWS)
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Bag")
	await get_tree().process_frame
	var s := world.pause_menu.bag_summary()
	assert_int(world.pause_menu.menu.page_count()).is_equal(2)
	var buttons := _bag_buttons()
	var prev: Button = buttons[buttons.size() - 2]
	var next: Button = buttons[buttons.size() - 1]
	assert_str(prev.text).is_equal(CommandMenu.PREV_PAGE)
	assert_str(next.text).starts_with(CommandMenu.NEXT_PAGE)
	buttons[0].grab_focus()
	await get_tree().process_frame
	assert_str(s.title_text()).is_equal("Salve")
	next.grab_focus()
	await get_tree().process_frame
	assert_str(s.title_text()).is_equal("")
	assert_str(s.body_text()).is_equal("Pick an item.")
	buttons[0].grab_focus()
	await get_tree().process_frame
	prev.grab_focus()
	await get_tree().process_frame
	assert_str(s.body_text()).is_equal("Pick an item.")
	next.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var page2 := _bag_buttons()
	var per: int = SideMenu.MENU_ROWS - 2
	assert_str(page2[0].text).is_equal("%s ×1" % DataRegistry.db.item(ids[per]).name)
	assert_str(s.body_text()).is_equal("Pick an item.")  # focus stays on the Next page button
	for i: int in ids.size() - per:
		page2[i].grab_focus()
		await get_tree().process_frame
		var it := DataRegistry.db.item(ids[per + i])
		assert_str(s.title_text()).is_equal(it.name if it != null else ids[per + i])
	page2[ids.size() - per].grab_focus()  # Back, on page 2
	await get_tree().process_frame
	assert_str(s.body_text()).is_equal("Pick an item.")


func test_reopening_the_bag_starts_fresh_with_one_connection() -> void:
	var s := await _open_bag_with_three_items()
	assert_int(_hovered_connections()).is_equal(1)
	_bag_buttons()[1].grab_focus()
	await get_tree().process_frame
	assert_str(s.title_text()).is_equal("Oran Berry")
	await _pick("Back")
	await get_tree().process_frame
	assert_int(_hovered_connections()).is_equal(0)
	assert_bool(s.is_visible_in_tree()).is_false()
	for round: int in 2:
		await _pick("Bag")
		assert_int(_hovered_connections()).is_equal(1)
		assert_bool(s.is_visible_in_tree()).is_true()
		# Shown fresh before anything is focused, then the first item once focus lands.
		assert_str(s.title_text()).is_not_equal("Oran Berry")
		await get_tree().process_frame
		await get_tree().process_frame
		assert_str(s.title_text()).is_equal("Salve")
		assert_str(s.body_text()).not_contains("Give it from the Summary.")
		await _pick("Back")
		await get_tree().process_frame
		assert_int(_hovered_connections()).is_equal(0)


func test_codex_row_opens_the_codex_and_back_returns() -> void:
	world.open_pause_menu()
	await get_tree().process_frame
	await _pick("Codex")
	await get_tree().process_frame
	var s := WorldTest.find_screen(world, CodexScreen) as CodexScreen
	assert_object(s).is_not_null()
	assert_bool(s.menu.pick_label("Back")).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(world.pause_menu.is_open()).is_true()
