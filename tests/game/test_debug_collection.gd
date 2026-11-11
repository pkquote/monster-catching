extends GdUnitTestSuite
## The F1 Collection page: the actions it offers act on the real tracking and the real service.

var save: SaveGame
var _emitted: Array = []
var _listener := func(id: String) -> void: _emitted.append(id)


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	save = SaveGame.new_game("Ana", 1000, rng)
	GameState.current = save
	AchievementService.flush()
	AchievementWatch.clear()
	_emitted = []
	AchievementService.unlocked.connect(_listener)


func after_test() -> void:
	AchievementService.unlocked.disconnect(_listener)
	GameState.current = null
	AchievementService.flush()
	AchievementWatch.clear()


func _page() -> DebugCollectionPage:
	var p := DebugCollectionPage.new()
	p.menu = DebugMenu
	return p


func test_mark_species_caught_and_seen() -> void:
	var p := _page()
	p.mark_species("tidepup", true)
	assert_bool(Codex.caught(save, "tidepup")).is_true()
	assert_array(Array(AchievementWatch.drain())).contains("codex")
	p.mark_species("emberkit", false)
	assert_str(Codex.status(save, "emberkit")).is_equal("seen")


func test_add_counter_moves_it_and_pushes_its_key() -> void:
	_page().add_counter("steps", 10)
	assert_int(Counters.value(save, "steps")).is_equal(10)
	assert_array(Array(AchievementWatch.drain())).contains("counter:steps")


func test_unlock_goes_through_the_service() -> void:
	assert_bool(_page().unlock("first_catch")).is_true()
	assert_bool(Achievements.is_unlocked(save, "first_catch")).is_true()
	assert_array(_emitted).is_equal(["first_catch"])


func test_reset_one_pushes_the_full_pass_and_reset_all_clears() -> void:
	var p := _page()
	p.unlock("first_catch")
	p.unlock("first_victory")
	p.reset("first_catch")
	assert_bool(Achievements.is_unlocked(save, "first_catch")).is_false()
	assert_bool(Achievements.is_unlocked(save, "first_victory")).is_true()
	assert_array(Array(AchievementWatch.drain())).contains(AchievementWatch.ALL)
	p.reset_all()
	assert_dict(save.achievements).is_empty()


func test_the_page_builds_its_controls() -> void:
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(box)
	var p := _page()
	p.build(box)
	assert_str(p.title()).is_equal("Collection")
	assert_int(box.find_children("*", "Button", true, false).size()).is_greater_equal(6)
