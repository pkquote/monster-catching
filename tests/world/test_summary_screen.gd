extends GdUnitTestSuite
## The summary screen: stats, moves and training tabs, and switching creature.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("summary_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	WorldTest.close(world)


func _screen(cls: Script) -> Node:
	return WorldTest.find_screen(world, cls)


func _open(index: int = 0) -> SummaryScreen:
	SummaryScreen.run(world, GameState.current.party, index)
	await get_tree().process_frame
	return _screen(SummaryScreen) as SummaryScreen


func _pick(s: ProgressScreen, label: String) -> void:
	await get_tree().process_frame  # let the menu's deferred focus land first
	assert_bool(s.menu.pick_label(label)).is_true()
	await get_tree().process_frame


## Waits for a screen of `cls` to be choosing, then picks `label`.
func _answer(cls: Script, label: String) -> void:
	for i in 200:
		var s := _screen(cls)
		if s != null and s.menu.is_choosing():
			await _pick(s, label)
			return
		await get_tree().process_frame
	fail("no %s screen offering %s" % [cls.get_global_name(), label])


func test_train_plus_one() -> void:
	var c := Story.give_creature("tidepup", 10)
	var s := await _open()
	s.show_tab("training")
	await get_tree().process_frame
	assert_str(s.page_text()).contains("Points to spend: 9")
	await _pick(s, "+1 Physical Attack")
	assert_int(c.trained("patk")).is_equal(1)
	assert_str(s.page_text()).contains("Points to spend: 8")


func test_train_refused_at_cap_shows_reason() -> void:
	var c := Story.give_creature("tidepup", 40)
	c.training["patk"] = 30
	var s := await _open()
	s.show_tab("training")
	await get_tree().process_frame
	await _pick(s, "+1 Physical Attack")
	assert_int(c.trained("patk")).is_equal(30)
	assert_str(s.page_text()).contains("Physical Attack is at the 30-point limit.")


func test_reset_seed_from_summary() -> void:
	var c := Story.give_creature("tidepup", 10)
	Training.train(DataRegistry.db, c, "patk", 3)
	GameState.current.inventory["reset_seed"] = 1
	var s := await _open()
	s.show_tab("training")
	await get_tree().process_frame
	assert_bool(s.menu.labels().has("Use a Reset Seed (you have 1)")).is_true()
	await _pick(s, "Use a Reset Seed")
	assert_str(s.page_text()).is_equal("Return 3 points from Tidepup?")  # asks first, like the Bag
	assert_int(c.trained("patk")).is_equal(3)
	await _pick(s, "Yes")
	assert_int(c.trained("patk")).is_equal(0)
	assert_bool(GameState.current.inventory.has("reset_seed")).is_false()
	assert_str(s.page_text()).contains("Points to spend: 9")
	assert_str(s.page_text()).contains("3 training points came back.")
	await get_tree().process_frame  # the page re-lays out for a frame before the menu is back
	assert_bool(s.menu.pick_label("Use a Reset Seed")).is_false()  # none left: disabled


func test_reset_seed_from_summary_no_keeps_points() -> void:
	var c := Story.give_creature("tidepup", 10)
	Training.train(DataRegistry.db, c, "patk", 3)
	GameState.current.inventory["reset_seed"] = 1
	var s := await _open()
	s.show_tab("training")
	await get_tree().process_frame
	await _pick(s, "Use a Reset Seed")
	await _pick(s, "No")
	assert_int(c.trained("patk")).is_equal(3)
	assert_int(GameState.current.inventory.reset_seed).is_equal(1)


func test_reset_seed_refund_of_one_point_is_singular() -> void:
	var c := Story.give_creature("tidepup", 10)
	Training.train(DataRegistry.db, c, "patk", 1)
	GameState.current.inventory["reset_seed"] = 1
	var s := await _open()
	s.show_tab("training")
	await get_tree().process_frame
	await _pick(s, "Use a Reset Seed")
	assert_str(s.page_text()).is_equal("Return 1 point from Tidepup?")
	await _pick(s, "Yes")
	assert_str(s.page_text()).contains("1 training point came back.")


func test_swap_pool_move_into_slot() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 14)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	var spare := ""
	for m in c.move_pool:
		if not c.moves.has(m):
			spare = m
			break
	assert_str(spare).is_not_empty()
	var s := await _open()
	s.show_tab("moves")
	await get_tree().process_frame
	await _pick(s, db.move(spare).name)
	await _answer(LearnMoveScreen, "Replace " + db.move("tackle").name)
	assert_bool(c.moves.has(spare)).is_true()
	assert_bool(c.moves.has("tackle")).is_false()
	assert_bool(c.move_pool.has("tackle")).is_true()


func test_grow_from_summary() -> void:
	var c := Story.give_creature("tidepup", 16)
	var s := await _open()
	await _pick(s, "Grow")
	await _answer(GrowScreen, "Grow now")
	await _answer(GrowScreen, "OK")
	assert_str(c.species).is_equal("torrentusk")
	for i in 5:
		if _screen(LearnMoveScreen) != null:
			await _answer(LearnMoveScreen, "Keep it for later")
		await get_tree().process_frame
	assert_bool(s.menu.labels().has("Grow")).is_false()


func test_tabs_and_creature_switch() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	assert_str(s.tab).is_equal("stats")
	assert_str(s.title_text()).contains("Tidepup")
	assert_str(s.page_text()).contains("Bond")
	s.next_tab()
	assert_str(s.tab).is_equal("moves")
	s.next_tab()
	assert_str(s.tab).is_equal("training")
	s.next_tab()
	assert_str(s.tab).is_equal("stats")
	s.next_tab(-1)
	assert_str(s.tab).is_equal("training")
	for i in 3:
		await get_tree().process_frame  # a switch made mid-layout takes a second render
	await _pick(s, "Next creature")
	assert_str(s.title_text()).contains("Emberkit")
	assert_str(s.tab).is_equal("training")  # the tab stays
	await _pick(s, "Previous creature")
	assert_str(s.title_text()).contains("Tidepup")
	assert_bool(s.menu.pick_label("Back")).is_true()
	await get_tree().process_frame
	assert_object(_screen(SummaryScreen)).is_null()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	world.get_viewport().push_input(ev)
	await get_tree().process_frame


func test_left_right_switch_tab_on_first_press_from_any_column() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	s.show_tab("training")  # two columns of options
	await get_tree().process_frame
	await _press("ui_right")
	assert_str(s.tab).is_equal("stats")  # training -> wraps to stats
	s.show_tab("training")
	await get_tree().process_frame
	# Focus the right-hand column, then press Left.
	var buttons: Array = s.menu.get_children().filter(func(n): return n is GridContainer)[0].get_children()
	buttons[1].grab_focus()
	await _press("ui_left")
	assert_str(s.tab).is_equal("moves")
	await _press("ui_right")
	assert_str(s.tab).is_equal("training")


func test_shoulder_actions_switch_creature() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await _press("next_creature")
	assert_str(s.title_text()).contains("Emberkit")
	await _press("prev_creature")
	assert_str(s.title_text()).contains("Tidepup")
	assert_bool(InputMap.has_action("next_creature")).is_true()
	var pads := InputMap.action_get_events("next_creature").filter(func(e): return e is InputEventJoypadButton)
	assert_int(pads.size()).is_equal(1)
	assert_int((pads[0] as InputEventJoypadButton).button_index).is_equal(JOY_BUTTON_RIGHT_SHOULDER)


func _assert_fits(s: SummaryScreen) -> void:
	await get_tree().process_frame
	ScreenFit.check(self, s)


func test_every_tab_fits_the_screen() -> void:
	Story.give_creature("tidepup", 14)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	for t in SummaryScreen.TABS:
		s.show_tab(t)
		await get_tree().process_frame
		await _assert_fits(s)


func test_moves_tab_with_a_full_pool_fits() -> void:
	var c := Story.give_creature("tidepup", 14)
	for m in DataRegistry.db.ids("moves"):
		if c.move_pool.size() >= 10:
			break
		if not c.move_pool.has(m):
			c.move_pool.append(m)
	var s := await _open()
	s.show_tab("moves")
	await get_tree().process_frame
	await _assert_fits(s)


func test_moves_tab_shows_empty_slots() -> void:
	var c := Story.give_creature("tidepup", 1)
	assert_int(c.moves.size()).is_less(4)
	var s := await _open()
	s.show_tab("moves")
	await get_tree().process_frame
	assert_str(s.page_text()).contains("- empty -")


## The very first page (Stats) is laid out before its text has been wrapped: the menu
## must still land under the info panel, not off the bottom of the screen.
func test_first_page_fits_the_screen() -> void:
	Story.give_creature("tidepup", 14)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _assert_fits(s)


func _focus_text() -> String:
	var f := world.get_viewport().gui_get_focus_owner()
	return f.text if f is Button else ""


func _enabled_buttons(s: SummaryScreen) -> Array:
	return s.menu.find_children("*", "Button", true, false).filter(func(b: Button): return not b.disabled)


## Both columns of the Training grid must be reachable with Up/Down alone.
func test_down_and_up_reach_every_option_on_the_training_tab() -> void:
	Story.give_creature("tidepup", 10)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	s.show_tab("training")
	for i in 3:
		await get_tree().process_frame
	var want: Array = _enabled_buttons(s).map(func(b: Button): return b.text)
	assert_int(want.size()).is_greater(10)
	var seen: Array = [_focus_text()]
	for i in want.size() + 1:
		await _press("ui_down")
		seen.append(_focus_text())
	for text in want:
		assert_bool(seen.has(text)).override_failure_message("Down never reached: " + text).is_true()
	var back: Array = [_focus_text()]
	for i in want.size() + 1:
		await _press("ui_up")
		back.append(_focus_text())
	for text in want:
		assert_bool(back.has(text)).override_failure_message("Up never reached: " + text).is_true()


func test_down_visits_options_in_reading_order() -> void:
	Story.give_creature("tidepup", 10)
	var s := await _open()
	s.show_tab("training")
	for i in 3:
		await get_tree().process_frame
	var order: Array = _enabled_buttons(s).map(func(b: Button): return b.text)
	for i in 5:
		assert_str(_focus_text()).is_equal(order[i])
		await _press("ui_down")


func test_focus_stays_on_the_picked_option_after_training() -> void:
	Story.give_creature("tidepup", 10)
	var s := await _open()
	s.show_tab("training")
	await get_tree().process_frame
	await _pick(s, "+1 Physical Defense")
	for i in 3:
		await get_tree().process_frame
	assert_str(_focus_text()).starts_with("+1 Physical Defense")
	assert_bool(s.page_text().contains("Points to spend: 8")).is_true()


## A tab change during the layout frame must not leave the previous tab's options up.
func test_tab_changed_during_layout_frame_is_rendered() -> void:
	Story.give_creature("tidepup", 10)
	SummaryScreen.run(world, GameState.current.party, 0)
	var s := _screen(SummaryScreen) as SummaryScreen
	s.show_tab("training")  # lands before the first layout frame is over
	for i in 4:
		await get_tree().process_frame
	assert_bool(s.menu.labels().has("+1 Physical Attack")).is_true()


func test_equipping_a_pool_move_is_not_worded_as_learning() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 14)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	var spare := ""
	for m in c.move_pool:
		if not c.moves.has(m):
			spare = m
			break
	var s := await _open()
	s.show_tab("moves")
	await get_tree().process_frame
	await _pick(s, db.move(spare).name)
	var lm: LearnMoveScreen = null
	for i in 50:
		lm = _screen(LearnMoveScreen) as LearnMoveScreen
		if lm != null and lm.menu.is_choosing():
			break
		await get_tree().process_frame
	assert_str(lm.title_text()).is_equal("Equip %s on Tidepup?" % db.move(spare).name)
	assert_bool(lm.menu.labels().has("Cancel")).is_true()
	assert_bool(lm.menu.labels().has("Keep it for later")).is_false()
	await _pick(lm, "Cancel")


func test_summary_reads_the_bag_of_the_save_it_is_given() -> void:
	var other := SaveGame.new_game("Bo", 0, RandomNumberGenerator.new())
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 10)
	other.party.append(c)
	other.inventory["reset_seed"] = 4
	SummaryScreen.run(world, other.party, 0, other)
	await get_tree().process_frame
	var s := _screen(SummaryScreen) as SummaryScreen
	s.show_tab("training")
	await get_tree().process_frame
	assert_bool(s.menu.labels().has("Use a Reset Seed (you have 4)")).is_true()
	s.close()


## Every Label text on the screen (the page, the greyed lines under it).
func _texts(s: SummaryScreen) -> Array:
	return s.find_children("*", "Label", true, false).map(func(l: Label): return l.text)


func _pup_with_passives(unlocked: bool) -> CreatureInstance:
	var c := Story.give_creature("tidepup", 10)
	c.passive = "tidal_heart"
	if unlocked:
		c.affinity_passive = "finisher"
	return c


func test_summary_shows_passives_and_switches() -> void:
	var c := _pup_with_passives(true)
	var s := await _open()
	await get_tree().process_frame
	assert_str(s.page_text()).contains("Passive: Tidal Heart — Water moves hit 20% harder.")
	assert_bool(_texts(s).has("Finisher (not active)")).is_true()
	await _assert_fits(s)
	await _pick(s, "Use Finisher")
	assert_str(c.active_passive).is_equal("affinity")
	assert_str(s.page_text()).contains("Passive: Finisher — ")
	assert_bool(_texts(s).has("Tidal Heart (not active)")).is_true()
	assert_bool(s.menu.labels().has("Use Tidal Heart")).is_true()
	# The switch is made on the save's own creature, so the next autosave carries it.
	GameState.autosave()
	var r := GameState.store.read(GameState.current_path)
	assert_str(r.save.party[0].active_passive).is_equal("affinity")
	await _pick(s, "Use Tidal Heart")
	assert_str(c.active_passive).is_equal("rolled")


func test_summary_locked_hint() -> void:
	_pup_with_passives(false)
	var s := await _open()
	await get_tree().process_frame
	assert_str(s.page_text()).contains("Passive: Tidal Heart — ")
	var hint := "Affinity passive: unlocks when a track reaches %d" % DataRegistry.db.balance.growth_affinity_threshold
	assert_bool(_texts(s).has(hint)).is_true()
	for label in s.menu.labels():
		assert_bool(label.begins_with("Use ")).is_false()


## A creature in storage (not in the party), or one whose passives are missing or
## unknown, can be shown without errors.
func test_summary_of_a_stored_creature_with_odd_passives() -> void:
	var save := GameState.current
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 10)
	c.passive = "no_such_passive"
	c.affinity_passive = "finisher"
	c.active_passive = "affinity"
	save.storage.append(c)
	var bare := CreatureInstance.create(DataRegistry.db, "emberkit", 5)
	bare.passive = ""
	save.storage.append(bare)
	SummaryScreen.run(world, save.storage, 0, save)
	await get_tree().process_frame
	var s := _screen(SummaryScreen) as SummaryScreen
	await get_tree().process_frame
	assert_str(s.page_text()).contains("Passive: Finisher — ")
	assert_bool(s.menu.labels().has("Use no_such_passive")).is_false()
	await _pick(s, "Next creature")
	assert_str(s.page_text()).contains("Passive: none")
	s.close()


func test_stats_tab_splits_growth_from_training() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 10)
	Training.train(db, c, "patk", 3)
	var s := await _open()
	var text := s.page_text()
	var grown := c.grown(db, "patk")
	assert_str(text).contains("Physical Attack %d (%d+3)" % [grown + 3, grown])
	# Untrained stats show the plain total.
	assert_str(text).contains("Speed %d" % c.stat(db, "spd"))
	assert_str(text).not_contains("Speed %d (" % c.stat(db, "spd"))


func test_stats_tab_fits_with_every_stat_trained() -> void:
	var c := Story.give_creature("tidepup", 99)
	for key in DataSchemas.TRAINABLE_STATS:
		c.training[key] = 30
	var s := await _open()
	ScreenFit.check(self, s)
