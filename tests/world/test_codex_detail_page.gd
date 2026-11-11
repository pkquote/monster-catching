extends GdUnitTestSuite
## The Codex detail page on the overworld: what it shows, what it refuses, how it fits.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("codex_detail_page", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	var db: Database = DataRegistry.db
	db._tables["creatures"].erase("tp_long")
	for i in 8:
		db._tables["locations"].erase("tp_m%d" % i)
	var table: Array = db.encounter("route_01_grass").table
	table = table.filter(func(r: Dictionary) -> bool: return r.species != "tp_long")
	db.encounter("route_01_grass").table = table
	WorldTest.close(world)


func _open_page(species: String) -> CodexDetailPage:
	CodexDetailPage.run(world, species)
	await get_tree().process_frame
	return WorldTest.find_screen(world, CodexDetailPage) as CodexDetailPage


func _close(s: CodexDetailPage) -> void:
	s.menu.pick_label("Back")
	await get_tree().process_frame
	await get_tree().process_frame


func test_page_shows_sprite_types_description_and_back() -> void:
	Codex.mark_seen(GameState.current, "tidepup")
	var s := await _open_page("tidepup")
	var def: CreatureDef = DataRegistry.db.creature("tidepup")
	assert_str(s.title_text()).is_equal(" / ".join(Array(def.types).map(func(t: String) -> String:
		return DataRegistry.db.type_def(t).name)))
	assert_str(s.page_text()).contains(def.description)
	assert_str(s.preview().name_text()).is_equal("#001 " + def.name)
	assert_bool(s.preview().is_silhouette()).is_false()
	assert_array(Array(s.menu.labels())).is_equal(["Back"])
	await _close(s)


func test_unseen_species_opens_nothing() -> void:
	var s := await _open_page("tidepup")
	assert_object(s).is_null()


func test_every_shipped_page_fits_the_screen() -> void:
	for id in DataRegistry.db.ids("creatures"):
		Codex.mark_seen(GameState.current, id)
	for id in DataRegistry.db.ids("creatures"):
		var s := await _open_page(id)
		assert_object(s).is_not_null()
		assert_array(Array(ScreenFit.problems(s))).override_failure_message(id).is_empty()
		await _close(s)


func test_a_long_description_and_many_locations_still_fit() -> void:
	var db: Database = DataRegistry.db
	var base: CreatureDef = db.creature("tidepup")
	var d := {"id": "tp_long", "name": "Longwinded", "types": ["water"], "base_stats": base.base_stats,
		"catch_rate": 0.5, "xp_yield": 10, "learnset": [{"level": 1, "move": "tackle"}], "passives": ["undertow"],
		"description": "A deliberately wordy test description that goes on and on. ".repeat(8)}
	db._tables["creatures"]["tp_long"] = CreatureDef.from_dict(d)
	db.encounter("route_01_grass").table.append({"species": "tp_long", "weight": 1, "min_level": 2, "max_level": 9})
	for i in 8:
		db._tables["locations"]["tp_m%d" % i] = LocationDef.from_dict({"id": "tp_m%d" % i, "name": "Map %d" % i,
			"areas": ["route_01_grass"]})
	Codex.mark_seen(GameState.current, "tp_long")
	var s := await _open_page("tp_long")
	assert_object(s).is_not_null()
	assert_array(Array(ScreenFit.problems(s))).is_empty()
	assert_str(s.page_text()).contains("more places")
	await _close(s)


func test_back_returns_to_the_list_on_the_same_row() -> void:
	Codex.mark_seen(GameState.current, "torrentusk")
	CodexScreen.run(world)
	await get_tree().process_frame
	var list := WorldTest.find_screen(world, CodexScreen) as CodexScreen
	assert_bool(list.menu.pick_label("#002")).is_true()
	await get_tree().process_frame
	var page := WorldTest.find_screen(world, CodexDetailPage) as CodexDetailPage
	assert_object(page).is_not_null()
	assert_bool(list.visible).is_false()  # the list is hidden behind the page, not shown through it
	await _close(page)
	assert_bool(list.visible).is_true()
	assert_object(WorldTest.find_screen(world, CodexDetailPage)).is_null()
	assert_bool(list.is_inside_tree()).is_true()
	assert_str(list.preview().name_text()).is_equal("#002 " + DataRegistry.db.creature("torrentusk").name)
	assert_bool(list.menu.is_choosing()).is_true()
