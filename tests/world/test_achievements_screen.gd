extends GdUnitTestSuite
## The Achievements list: rows by state, the header, the preview, the hidden rule, the screen fit.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("achievements_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	DataRegistry.db._tables["achievements"].erase("tp_long")
	WorldTest.close(world)


func _open() -> AchievementsScreen:
	AchievementsScreen.run(world)
	await get_tree().process_frame
	return WorldTest.find_screen(world, AchievementsScreen) as AchievementsScreen


func _db() -> Database:
	return DataRegistry.db


func test_row_labels_by_state() -> void:
	var save := GameState.current
	assert_str(AchievementsScreen.row_label(_db(), save, "first_steps")).is_equal("First Steps 0 / 500")
	AchievementService.unlock("first_catch")
	assert_str(AchievementsScreen.row_label(_db(), save, "first_catch")).is_equal("First Catch ✓")


func test_a_hidden_locked_row_is_unknown_until_it_is_unlocked() -> void:
	var save := GameState.current
	assert_str(AchievementsScreen.row_label(_db(), save, "quick_on_the_draw")).is_equal("???")
	AchievementService.unlock("quick_on_the_draw")
	assert_str(AchievementsScreen.row_label(_db(), save, "quick_on_the_draw")).is_equal("Quick on the Draw ✓")


func test_the_list_is_in_file_order_and_ends_with_back() -> void:
	var s := await _open()
	var labels := s.menu.labels()
	var listed := Achievements.listed(_db())
	assert_int(labels.size()).is_equal(listed.size() + 1)
	assert_str(labels[0]).starts_with("First Steps")
	assert_str(labels[labels.size() - 1]).is_equal("Back")


func test_the_header_counts_listed_achievements_only() -> void:
	var n := Achievements.listed(_db()).size()
	assert_str(AchievementsScreen.header_text(_db(), GameState.current)).is_equal("Unlocked 0 / %d" % n)
	_db()._tables["achievements"]["tp_long"] = AchievementDef.from_dict({"id": "tp_long", "name": "T",
		"description": "t", "criterion": {"kind": "flag", "flag": "x"}})
	AchievementService.unlock("tp_long")  # test content: not counted
	AchievementService.unlock("first_catch")
	assert_str(AchievementsScreen.header_text(_db(), GameState.current)).is_equal("Unlocked 1 / %d" % n)
	var s := await _open()
	assert_int(s.menu.labels().size()).is_equal(n + 1)


func test_hover_shows_progress_for_a_locked_row_and_the_date_for_an_unlocked_one() -> void:
	AchievementService.unlock("first_catch")
	var s := await _open()
	s.menu.hovered.emit("first_steps")
	assert_str(s.preview().name_text()).is_equal("First Steps")
	assert_str(s.preview().description_text()).is_equal("Walk 500 steps.")
	assert_str(s.preview().status_text()).is_equal("Progress 0 / 500")
	s.menu.hovered.emit("first_catch")
	assert_str(s.preview().status_text()).starts_with("Unlocked 20")
	assert_bool(s.preview().is_masked()).is_false()


func test_a_hidden_locked_row_leaks_nothing_in_the_preview() -> void:
	var s := await _open()
	s.menu.hovered.emit("quick_on_the_draw")
	var def := _db().achievement("quick_on_the_draw")
	assert_bool(s.preview().is_masked()).is_true()
	assert_str(s.preview().name_text()).is_equal("???")
	for text in [s.preview().name_text(), s.preview().description_text(), s.preview().status_text()]:
		assert_str(text).not_contains(def.name)
		assert_str(text).not_contains(def.description)
		assert_str(text).not_contains("quick_draw_won")
		assert_str(text).not_contains("0 / 1")
	AchievementService.unlock("quick_on_the_draw")
	s.menu.hovered.emit("quick_on_the_draw")
	assert_bool(s.preview().is_masked()).is_false()
	assert_str(s.preview().name_text()).is_equal(def.name)


func test_back_closes_the_screen() -> void:
	var s := await _open()
	assert_bool(s.menu.pick_label("Back")).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(s) and s.is_inside_tree()).is_false()


func test_the_screen_fits_with_a_very_long_name_and_description() -> void:
	_db()._tables["achievements"]["tp_long"] = AchievementDef.from_dict({"id": "tp_long",
		"name": "An extraordinarily long achievement name that keeps going ".repeat(3),
		"description": "A deliberately wordy description that goes on and on. ".repeat(10),
		"criterion": {"kind": "flag", "flag": "x"}})
	var s := await _open()
	s.menu.hovered.emit("tp_long")
	assert_array(Array(ScreenFit.problems(s))).is_empty()
	assert_int(s.preview().description_text().length()).is_less_equal(AchievementPreview.DESCRIPTION_MAX)
