extends GdUnitTestSuite
## The F1 UI gallery page: a throwaway creature in a CreatureCard; no game needed, no save touched.

var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("debug_ui_gallery", false)


func after() -> void:
	DebugMenu.close()
	WorldTest.end_suite(_suite)


func _open() -> DebugUiGalleryPage:
	DebugMenu.open()
	var page := DebugUiGalleryPage.new()
	DebugMenu.show_page(page)
	return page


func test_make_creature_applies_level_and_training() -> void:
	var c := DebugUiGalleryPage.make_creature(DataRegistry.db, "tidepup", 50, 10, "Pup", "oran_berry")
	assert_int(c.level).is_equal(50)
	assert_int(c.trained("patk")).is_equal(10)
	assert_int(c.trained("hp")).is_equal(10)
	assert_str(c.nickname).is_equal("Pup")
	assert_str(c.held_item).is_equal("oran_berry")
	assert_int(c.hp).is_equal(c.max_hp(DataRegistry.db))
	assert_int(c.energy).is_equal(c.max_energy(DataRegistry.db))


func test_gallery_opens_without_a_game() -> void:
	GameState.close_game()
	var page := _open()
	await get_tree().process_frame
	assert_object(page.card).is_not_null()
	assert_bool(page.card.is_inside_tree()).is_true()
	assert_str(page.card.header_text()).contains("Lv 20")


func test_changing_the_level_changes_the_card() -> void:
	var page := _open()
	await get_tree().process_frame
	page.level_spin.value = 5
	assert_str(page.card.header_text()).ends_with("Lv 5")
	var radars: Array = page.card.find_children("*", "StatRadar", true, false)
	var small: float = (StatRadar.axes(DataRegistry.db, DebugUiGalleryPage.make_creature(
		DataRegistry.db, "tidepup", 5, 0))[0] as Dictionary).fraction
	page.level_spin.value = 99
	assert_str(page.card.header_text()).ends_with("Lv 99")
	assert_array(radars).is_not_empty()
	var big: float = (StatRadar.axes(DataRegistry.db, DebugUiGalleryPage.make_creature(
		DataRegistry.db, "tidepup", 99, 0))[0] as Dictionary).fraction
	assert_float(big).is_greater(small)


func test_nickname_and_held_item_show_on_the_card() -> void:
	var page := _open()
	await get_tree().process_frame
	page.nickname_edit.text = "Bubbles"
	page.nickname_edit.text_changed.emit("Bubbles")
	assert_str(page.card.header_text()).starts_with("Bubbles")
	page.item_pick.select(1)
	page.item_pick.item_selected.emit(1)
	assert_str(page.card.held_text()).is_not_equal("Held: none")


func test_gallery_does_not_touch_the_save() -> void:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	var before_save: Dictionary = GameState.current.to_dict().duplicate(true)
	var page := _open()
	await get_tree().process_frame
	page.level_spin.value = 60
	page.species_pick.select(1)
	page.species_pick.item_selected.emit(1)
	assert_bool(GameState.current.to_dict() == before_save).is_true()
