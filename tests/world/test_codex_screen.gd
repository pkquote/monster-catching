extends GdUnitTestSuite
## The Codex list: rows by status, the header, the hover preview, the unseen rule, the screen fit.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("codex_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	DataRegistry.db._tables["creatures"].erase("undexed_test")
	WorldTest.close(world)


func _open() -> CodexScreen:
	CodexScreen.run(world)
	await get_tree().process_frame
	return WorldTest.find_screen(world, CodexScreen) as CodexScreen


func _name(id: String) -> String:
	return DataRegistry.db.creature(id).name


func test_row_labels_by_status() -> void:
	Codex.mark_caught(GameState.current, "tidepup")
	Codex.mark_seen(GameState.current, "torrentusk")
	var s := await _open()
	var labels := s.menu.labels()
	assert_str(labels[0]).is_equal("#001 %s ●" % _name("tidepup"))
	assert_str(labels[1]).is_equal("#002 %s ○" % _name("torrentusk"))
	assert_str(labels[2]).is_equal("#003 ???")
	assert_str(labels[labels.size() - 1]).is_equal("Back")


func test_header_counts() -> void:
	Codex.mark_caught(GameState.current, "tidepup")
	Codex.mark_seen(GameState.current, "torrentusk")
	var s := await _open()
	var n := Codex.order(DataRegistry.db).size()
	assert_str(s.page_text()).is_equal("Seen 2 / %d · Caught 1 / %d" % [n, n])


func test_header_counts_only_species_in_the_list() -> void:
	var test_id := ""
	for id in DataRegistry.db.ids("creatures"):
		if Database.is_test_content(id):
			test_id = id
			break
	assert_str(test_id).is_not_empty()
	Codex.mark_seen(GameState.current, test_id)  # debug content: not in the Codex
	Codex.mark_seen(GameState.current, "removed_species")  # no longer in the data
	Codex.mark_caught(GameState.current, "tidepup")
	var n := Codex.order(DataRegistry.db).size()
	assert_str(CodexScreen.header_text(DataRegistry.db, GameState.current)).is_equal("Seen 1 / %d · Caught 1 / %d" % [n, n])


func test_all_rows_are_unknown_on_a_fresh_game() -> void:
	var s := await _open()
	var labels := s.menu.labels()
	assert_str(s.page_text()).starts_with("Seen 0 / ")
	for i in labels.size() - 1:
		assert_bool(labels[i].ends_with("???")).is_true()
		for id in DataRegistry.db.ids("creatures"):
			assert_str(labels[i]).not_contains(_name(id))


func test_unseen_row_does_nothing() -> void:
	var s := await _open()
	assert_bool(s.menu.pick_label("#001")).is_true()
	await get_tree().process_frame
	assert_bool(s.menu.is_choosing()).is_true()
	var screens := world.get_children().filter(func(n: Node) -> bool: return n is ProgressScreen)
	assert_int(screens.size()).is_equal(1)


func test_hover_updates_the_preview() -> void:
	Codex.mark_caught(GameState.current, "tidepup")
	var s := await _open()
	s.menu.hovered.emit("tidepup")
	assert_str(s.preview().name_text()).is_equal("#001 " + _name("tidepup"))
	s.menu.hovered.emit("torrentusk")
	assert_str(s.preview().name_text()).is_equal("#002 ???")


func test_list_fits_the_screen_with_every_species_seen() -> void:
	for id in DataRegistry.db.ids("creatures"):
		Codex.mark_seen(GameState.current, id)
	var s := await _open()
	assert_array(Array(ScreenFit.problems(s))).is_empty()


func test_species_without_dex_sort_last() -> void:
	var base: CreatureDef = DataRegistry.db.creature("tidepup")
	var d := {"id": "undexed_test", "name": "Undexed", "types": ["water"], "base_stats": base.base_stats,
		"catch_rate": 0.5, "xp_yield": 10, "learnset": [{"level": 1, "move": "tackle"}], "passives": ["undertow"]}
	DataRegistry.db._tables["creatures"]["undexed_test"] = CreatureDef.from_dict(d)
	Codex.mark_seen(GameState.current, "undexed_test")
	var s := await _open()
	var labels := s.menu.labels()
	var idx := Array(labels).find("#--- Undexed ○")
	assert_int(idx).is_greater_equal(0)
	for i in labels.size() - 1:  # every numbered row (not Back) comes before it
		if not labels[i].begins_with("#---"):
			assert_int(i).is_less(idx)


func test_test_pack_creatures_are_not_listed() -> void:
	var s := await _open()
	var listed := Codex.order(DataRegistry.db).size() + 1  # and Back
	assert_int(s.menu.labels().size()).is_equal(listed)
	for id in DataRegistry.db.ids("creatures"):
		if Database.is_test_content(id):
			assert_bool(Codex.order(DataRegistry.db).has(id)).is_false()


func test_back_closes_the_screen() -> void:
	var s := await _open()
	assert_bool(s.menu.pick_label("Back")).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(s) and s.is_inside_tree()).is_false()


func test_closing_the_list_straight_away_is_safe() -> void:
	var s := await _open()
	s.close()  # inside the frames the scroll reset is still waiting
	for i in 6:
		await get_tree().process_frame
	assert_bool(is_instance_valid(s) and s.is_inside_tree()).is_false()


func test_the_list_opens_at_the_top() -> void:
	var s := await _open()
	for i in 8:  # well past the frames the screen waits before it resets the scroll
		await get_tree().process_frame
	assert_int((s.menu_area() as ScrollContainer).scroll_vertical).is_equal(0)
	var first := s.menu.get_child(1).get_child(0) as Button  # the grid's first row
	assert_bool(s.menu_area().get_global_rect().encloses(first.get_global_rect().grow(-1.0))).is_true()
