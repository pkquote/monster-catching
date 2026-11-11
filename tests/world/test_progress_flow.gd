extends GdUnitTestSuite
## The after-battle step: Learn Move and Grow screens, run before the autosave.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("progress_flow")


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	WorldTest.close(world)


## A level-14 Tidepup with Tide Beam learned but unequipped (so it is offered).
func _offered_pup() -> ProgressEntry:
	var c := Story.give_creature("tidepup", 14)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	return Progression.progress_entry(DataRegistry.db, c, 13, "")


## A level-16 Tidepup, ready to grow into Torrentusk.
func _grow_pup() -> ProgressEntry:
	var c := Story.give_creature("tidepup", 16)
	return Progression.progress_entry(DataRegistry.db, c, 15, "")


func _screen(cls: Script) -> Node:
	return WorldTest.find_screen(world, cls)


## Waits for a screen of `cls` to be choosing, then picks `label`.
func _answer(cls: Script, label: String) -> void:
	for i in 200:
		var s := _screen(cls)
		if s != null and s.menu.is_choosing():
			await get_tree().process_frame  # let the menu's deferred focus land first
			assert_bool(s.menu.pick_label(label)).is_true()
			await get_tree().process_frame
			return
		await get_tree().process_frame
	fail("no %s screen offering %s" % [cls.get_global_name(), label])


func _run_after(summary: BattleSummary, done: Array) -> void:
	done.append(await world.battles.after_battle(summary, true))


func _wait(done: Array) -> void:
	for i in 200:
		if not done.is_empty():
			return
		await get_tree().process_frame


func test_learn_move_replace() -> void:
	var entry := _offered_pup()
	var c: CreatureInstance = entry.creature
	assert_array(entry.offered_moves).is_equal(["tide_beam"])
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer(LearnMoveScreen, "Replace Tackle")
	await _wait(done)
	assert_array(done).is_equal([true])
	assert_array(Array(c.moves)).is_equal(["tide_beam", "splash_jab", "drench", "riptide"])
	assert_bool(c.move_pool.has("tackle")).is_true()
	assert_object(_screen(LearnMoveScreen)).is_null()
	assert_bool(world.is_locked()).is_false()


func test_learn_move_keep() -> void:
	var entry := _offered_pup()
	var c: CreatureInstance = entry.creature
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer(LearnMoveScreen, "Keep it for later")
	await _wait(done)
	assert_array(Array(c.moves)).is_equal(["tackle", "splash_jab", "drench", "riptide"])
	assert_bool(c.move_pool.has("tide_beam")).is_true()


func test_learn_move_copy() -> void:
	var entry := _offered_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	for i in 50:
		await get_tree().process_frame
	var s := _screen(LearnMoveScreen) as LearnMoveScreen
	assert_str(s.title_text()).is_equal("Tidepup wants to learn Tide Beam")
	assert_array(Array(s.menu.labels())).is_equal(["Replace Tackle", "Replace Splash Jab",
		"Replace Drench", "Replace Riptide", "Keep it for later"])
	await _answer(LearnMoveScreen, "Keep it for later")
	await _wait(done)


func test_grow_now_changes_species() -> void:
	var entry := _grow_pup()
	var c: CreatureInstance = entry.creature
	assert_bool(entry.growth_due).is_true()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	for i in 50:
		await get_tree().process_frame
	var g := _screen(GrowScreen) as GrowScreen
	assert_str(g.page_text()).is_equal("Tidepup is ready to grow! It will become Torrentusk.")
	await _answer(GrowScreen, "Grow now")
	assert_str(c.species).is_equal("torrentusk")
	assert_str(g.page_text()).is_equal("Tidepup grew into Torrentusk!")
	await _answer(GrowScreen, "OK")
	await _answer(LearnMoveScreen, "Keep it for later")  # Quake Stomp has no free slot
	await _wait(done)
	assert_array(done).is_equal([true])
	assert_bool(c.move_pool.has("quake_stomp")).is_true()
	assert_bool(c.moves.has("quake_stomp")).is_false()


func test_grow_names_dominant_affinity() -> void:
	var entry := _grow_pup()
	var c: CreatureInstance = entry.creature
	c.affinity["catalyst"] = 100
	assert_str(Progression.growth_target(DataRegistry.db, c)).is_equal("mistcoil")
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	for i in 50:
		await get_tree().process_frame
	var g := _screen(GrowScreen) as GrowScreen
	assert_str(g.page_text()).is_equal(
		"Tidepup is ready to grow! Its Catalyst side is strongest: it will become Mistcoil.")
	await _answer(GrowScreen, "Not yet")
	await _wait(done)


func test_grow_not_yet_keeps_ready() -> void:
	var entry := _grow_pup()
	var c: CreatureInstance = entry.creature
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer(GrowScreen, "Not yet")
	await _wait(done)
	assert_str(c.species).is_equal("tidepup")
	assert_str(Progression.growth_target(DataRegistry.db, c)).is_equal("torrentusk")


func test_not_yet_reoffered_only_after_level_gain() -> void:
	var entry := _grow_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer(GrowScreen, "Not yet")
	await _wait(done)
	var again: Array = []
	_run_after(BattleSummary.of("won", []), again)
	await get_tree().process_frame
	assert_array(again).is_equal([true])
	assert_object(_screen(GrowScreen)).is_null()


func test_grow_screen_skips_when_not_due() -> void:
	var c := Story.give_creature("tidepup", 5)
	var grew := await GrowScreen.run(world, c)
	assert_bool(grew).is_false()
	assert_object(_screen(GrowScreen)).is_null()


func test_autosave_after_choices() -> void:
	var entry := _offered_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer(LearnMoveScreen, "Replace Tackle")
	await _wait(done)
	var r := GameState.store.read(GameState.current_path)
	assert_bool(r.ok).is_true()
	assert_array(Array(r.save.party[0].moves)).is_equal(["tide_beam", "splash_jab", "drench", "riptide"])


func test_loss_with_levels_runs_after_respawn() -> void:
	var entry := _offered_pup()
	var c: CreatureInstance = entry.creature
	c.hp = 0
	var done: Array = []
	_run_after(BattleSummary.of("lost", [entry]), done)
	for i in 300:
		var s := _screen(LearnMoveScreen)
		if s != null and s.menu.is_choosing():
			break
		world.dialogue_box.press_accept()
		await get_tree().process_frame
	assert_str(world.map.map_id()).is_equal(Overworld.new_game_map())
	assert_bool(done.is_empty()).is_true()
	await _answer(LearnMoveScreen, "Replace Tackle")
	await _wait(done)
	assert_array(done).is_equal([false])
	var r := GameState.store.read(GameState.current_path)
	assert_array(Array(r.save.party[0].moves)).is_equal(["tide_beam", "splash_jab", "drench", "riptide"])


func test_progress_blocks_debug_menu() -> void:
	var entry := _offered_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	for i in 20:
		await get_tree().process_frame
	assert_bool(world.blocks_debug_menu()).is_true()
	await _answer(LearnMoveScreen, "Keep it for later")
	await _wait(done)
	assert_bool(world.blocks_debug_menu()).is_false()


## The info panel (new move, its description, four current moves) must not run
## under the menu, and the menu must stay on the 640x360 screen.
func test_learn_move_screen_fits_the_screen() -> void:
	var entry := _offered_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer_wait(LearnMoveScreen)
	var s := _screen(LearnMoveScreen) as LearnMoveScreen
	await get_tree().process_frame
	ScreenFit.check(self, s)
	s.menu.pick_label("Keep it for later")
	await _wait(done)


func _answer_wait(cls: Script) -> void:
	for i in 200:
		var s := _screen(cls)
		if s != null and s.menu.is_choosing():
			return
		await get_tree().process_frame
	fail("no %s screen choosing" % cls.get_global_name())


## A Tidepup with Tidal Heart whose Striker track just reached the threshold.
func _unlocked_pup(level: int) -> CreatureInstance:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", level)
	c.passive = "tidal_heart"
	c.affinity["striker"] = db.balance.growth_affinity_threshold
	assert_str(Passives.try_unlock(db, c, "striker")).is_equal("finisher")
	return c


func test_unlock_screen_switch_and_keep() -> void:
	var c := _unlocked_pup(10)
	var done: Array = []
	var run := func() -> void: done.append(await PassiveUnlockScreen.run(world, c))
	run.call()
	await _answer_wait(PassiveUnlockScreen)
	var s := _screen(PassiveUnlockScreen) as PassiveUnlockScreen
	assert_str(s.title_text()).is_equal("Tidepup awakened Finisher!")
	assert_str(s.page_text()).contains("Tidal Heart")
	assert_str(s.page_text()).contains("Water moves hit 20% harder.")
	assert_str(s.page_text()).contains("Finisher")
	assert_str(s.page_text()).contains("Scrap hits 50% harder.")
	assert_array(Array(s.menu.labels())).is_equal(["Switch to it", "Keep current"])
	await get_tree().process_frame
	ScreenFit.check(self, s)
	await _answer(PassiveUnlockScreen, "Keep current")
	await _wait(done)
	assert_array(done).is_equal([false])
	assert_str(Passives.active_id(c)).is_equal("tidal_heart")
	done.clear()
	run.call()
	await _answer(PassiveUnlockScreen, "Switch to it")
	await _wait(done)
	assert_array(done).is_equal([true])
	assert_str(Passives.active_id(c)).is_equal("finisher")
	assert_object(_screen(PassiveUnlockScreen)).is_null()


func test_unlock_screen_cancel_keeps_current() -> void:
	var c := _unlocked_pup(10)
	var done: Array = []
	var run := func() -> void: done.append(await PassiveUnlockScreen.run(world, c))
	run.call()
	await _answer_wait(PassiveUnlockScreen)
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	await get_tree().process_frame
	world.get_viewport().push_input(ev)
	await _wait(done)
	assert_array(done).is_equal([false])
	assert_str(c.active_passive).is_equal("rolled")


func test_unlock_runs_after_learn_move_before_grow() -> void:
	var c := _unlocked_pup(16)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	var entry := Progression.progress_entry(DataRegistry.db, c, 13, "")
	assert_array(entry.offered_moves).is_equal(["tide_beam"])
	assert_bool(entry.growth_due).is_true()
	assert_str(entry.unlocked_passive).is_equal("finisher")
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer_wait(LearnMoveScreen)
	assert_object(_screen(PassiveUnlockScreen)).is_null()
	await _answer(LearnMoveScreen, "Keep it for later")
	await _answer_wait(PassiveUnlockScreen)
	assert_object(_screen(GrowScreen)).is_null()
	await _answer(PassiveUnlockScreen, "Keep current")
	await _answer(GrowScreen, "Not yet")
	await _wait(done)
	assert_array(done).is_equal([true])


## Review Focus 5: a track crossing the threshold in a battle with no level-up still
## brings up the screen, and the choice reaches the autosave.
func test_unlock_screen_for_entry_without_level_gain() -> void:
	var c := _unlocked_pup(10)
	var entry := Progression.progress_entry(DataRegistry.db, c, 10, "")
	assert_object(entry).is_not_null()
	assert_array(entry.offered_moves).is_empty()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	await _answer(PassiveUnlockScreen, "Switch to it")
	await _wait(done)
	assert_array(done).is_equal([true])
	assert_str(c.active_passive).is_equal("affinity")
	var r := GameState.store.read(GameState.current_path)
	assert_str(r.save.party[0].active_passive).is_equal("affinity")
	assert_str(r.save.party[0].affinity_passive).is_equal("finisher")


func test_growing_marks_the_new_species_caught_and_counts() -> void:
	var entry := _grow_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	for i in 50:
		await get_tree().process_frame
	assert_str(Codex.status(GameState.current, "torrentusk")).is_equal("unseen")
	await _answer(GrowScreen, "Grow now")
	await _answer(GrowScreen, "OK")
	await _answer(LearnMoveScreen, "Keep it for later")
	await _wait(done)
	assert_str(Codex.status(GameState.current, "torrentusk")).is_equal("caught")
	assert_int(Counters.value(GameState.current, "creatures_evolved")).is_equal(1)


func test_declining_growth_changes_nothing() -> void:
	var entry := _grow_pup()
	var done: Array = []
	_run_after(BattleSummary.of("won", [entry]), done)
	for i in 50:
		await get_tree().process_frame
	await _answer(GrowScreen, "Not yet")
	await _wait(done)
	assert_str(Codex.status(GameState.current, "torrentusk")).is_equal("unseen")
	assert_int(Counters.value(GameState.current, "creatures_evolved")).is_equal(0)


func test_record_growth_tolerates_no_loaded_game() -> void:
	GrowScreen.record_growth(null, "torrentusk")
	var rng := RandomNumberGenerator.new()
	var s := SaveGame.new_game("Ana", 1000, rng)
	GrowScreen.record_growth(s, "torrentusk")
	assert_str(Codex.status(s, "torrentusk")).is_equal("caught")
	assert_int(Counters.value(s, "creatures_evolved")).is_equal(1)
