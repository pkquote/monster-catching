extends GdUnitTestSuite
## The summary screen: the creature card on the left; an info block and a menu on the right that opens
## Moves, Train and Held item sub-lists; switching creature.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("summary_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")
	_add_item("test_charm", "Test Charm", "Raises Physical Attack a little.")
	_add_item("test_berry", "Test Berry", "A snack to hold.")


func after_test() -> void:
	for id in ["test_charm", "test_berry", "test_long"]:
		DataRegistry.db._tables["items"].erase(id)
	DataRegistry.db.creature("tidepup").growth_rates = {}
	WorldTest.close(world)


func _screen(cls: Script) -> Node:
	return WorldTest.find_screen(world, cls)


func _open(index: int = 0) -> SummaryScreen:
	SummaryScreen.run(world, GameState.current.party, index)
	await get_tree().process_frame
	return _screen(SummaryScreen) as SummaryScreen


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _pick(s: ProgressScreen, label: String) -> void:
	await get_tree().process_frame  # let the menu's deferred focus land first
	assert_bool(s.menu.pick_label(label)).override_failure_message("no enabled option '%s' in %s" % [label, s.menu.labels()]).is_true()
	await get_tree().process_frame


## Picks a top-level entry and waits for its sub-list to be showing.
func _enter(s: SummaryScreen, label: String) -> void:
	await _pick(s, label)
	await _frames(3)


## Waits for a screen of `cls` to be choosing, then picks `label`.
func _answer(cls: Script, label: String) -> void:
	for i in 200:
		var s := _screen(cls)
		if s != null and s.menu.is_choosing():
			await _pick(s, label)
			return
		await get_tree().process_frame
	fail("no %s screen offering %s" % [cls.get_global_name(), label])


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	world.get_viewport().push_input(ev)
	await get_tree().process_frame


func _assert_fits(s: SummaryScreen, allow_scroll := false) -> void:
	await get_tree().process_frame
	ScreenFit.check(self, s, allow_scroll)


func _focus_text() -> String:
	var f := world.get_viewport().gui_get_focus_owner()
	return f.text if f is Button else ""


func _enabled_buttons(s: SummaryScreen) -> Array:
	return s.menu.find_children("*", "Button", true, false).filter(func(b: Button): return not b.disabled)


## Every Label text on the screen (the page, the greyed lines under it).
func _texts(s: SummaryScreen) -> Array:
	return s.find_children("*", "Label", true, false).map(func(l: Label): return l.text)


func _radar(s: SummaryScreen) -> StatRadar:
	return s.card().find_children("*", "StatRadar", true, false)[0] as StatRadar


## The shared db has no held items yet: add a test one (the real db is restored in after_test).
func _add_item(id: String, item_name: String, description: String) -> void:
	DataRegistry.db._tables["items"][id] = ItemDef.from_dict({"id": id, "name": item_name, "description": description,
		"category": "held", "price": 10, "held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}})


## Held-item ids in the bag and on `c`: what must stay constant.
func _count(c: CreatureInstance, id: String) -> int:
	return int(GameState.current.inventory.get(id, 0)) + (1 if c.held_item == id else 0)


# --- Top level ----------------------------------------------------------------------------------

func test_top_level_entries_follow_the_creature() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	await _frames()
	var labels := s.menu.labels()
	assert_bool(labels.has("Moves...")).is_true()
	assert_bool(labels.has("Train...")).is_true()
	assert_bool(labels.has("Grow")).is_false()
	assert_bool(labels.has("Held item...")).is_false()
	assert_bool(labels.has("Previous creature")).is_false()
	assert_bool(labels.has("Next creature")).is_false()
	assert_bool(labels.has("Back")).is_true()


func test_grow_is_first_when_available() -> void:
	Story.give_creature("tidepup", 16)
	var s := await _open()
	await _frames()
	assert_str(s.menu.labels()[0]).is_equal("Grow")


func test_previous_and_next_appear_with_two_creatures() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await _frames()
	var labels := Array(s.menu.labels())
	assert_int(labels.find("Previous creature")).is_less(labels.find("Back"))
	assert_int(labels.find("Next creature")).is_less(labels.find("Back"))


func test_held_item_entry_appears_with_a_bag_item_or_a_held_one() -> void:
	var c := Story.give_creature("tidepup", 5)
	var s := await _open()
	await _frames()
	assert_bool(s.menu.labels().has("Held item...")).is_false()
	GameState.current.inventory["test_charm"] = 1
	s.show_mode("top")
	await _frames()
	assert_bool(s.menu.labels().has("Held item...")).is_true()
	GameState.current.inventory.erase("test_charm")
	c.held_item = "test_berry"
	s.show_mode("top")
	await _frames()
	assert_bool(s.menu.labels().has("Held item...")).is_true()


func test_title_shows_name_level_and_position() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	assert_str(s.title_text()).is_equal("Tidepup  Lv 5")
	Story.give_creature("emberkit", 5)
	s.close()
	s = await _open()
	assert_str(s.title_text()).is_equal("Tidepup  Lv 5  (1 / 2)")


func test_card_shows_the_creature_and_follows_the_switch() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 7)
	var s := await _open()
	await _frames()
	assert_str(s.card().header_text()).is_equal("Tidepup  Lv 5")
	await _pick(s, "Next creature")
	await _frames()
	assert_str(s.title_text()).contains("Emberkit")
	assert_str(s.card().header_text()).is_equal("Emberkit  Lv 7")
	await _pick(s, "Previous creature")
	await _frames()
	assert_str(s.card().header_text()).is_equal("Tidepup  Lv 5")
	assert_bool(s.menu.pick_label("Back")).is_true()
	await get_tree().process_frame
	assert_object(_screen(SummaryScreen)).is_null()


func test_info_block_lines() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 10)
	var s := await _open()
	assert_str(s.page_text()).contains("XP to next level: %d" % (Stats.xp_for_level(11) - c.xp))
	assert_str(s.page_text()).contains("Bond: 0")
	assert_str(s.page_text()).contains("Passive: ")
	assert_str(s.page_text()).contains("Held item: none")
	c.level = db.balance.level_cap
	s.show_mode("top")
	await _frames()
	assert_str(s.page_text()).contains("Max level")


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


func _pup_with_passives(unlocked: bool) -> CreatureInstance:
	var c := Story.give_creature("tidepup", 10)
	c.passive = "tidal_heart"
	if unlocked:
		c.affinity_passive = "finisher"
	return c


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
	BoxStorage.add(save, c)
	var bare := CreatureInstance.create(DataRegistry.db, "emberkit", 5)
	bare.passive = ""
	BoxStorage.add(save, bare)
	SummaryScreen.run(world, BoxStorage.all_creatures(save), 0, save)
	await get_tree().process_frame
	var s := _screen(SummaryScreen) as SummaryScreen
	await get_tree().process_frame
	assert_str(s.page_text()).contains("Passive: Finisher — ")
	assert_bool(s.menu.labels().has("Use no_such_passive")).is_false()
	await _pick(s, "Next creature")
	assert_str(s.page_text()).contains("Passive: none")
	s.close()


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


# --- Switching creature ---------------------------------------------------------------------------

func test_left_right_switch_creature_from_any_focus() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await _frames()
	await _press("ui_right")
	assert_str(s.title_text()).contains("Emberkit")
	await _press("ui_left")
	assert_str(s.title_text()).contains("Tidepup")
	await _frames()
	var buttons: Array = _enabled_buttons(s)
	buttons[buttons.size() - 1].grab_focus()
	await _press("ui_right")
	assert_str(s.title_text()).contains("Emberkit")


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


func test_one_creature_left_right_do_nothing() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	await _frames()
	await _press("ui_right")
	await _press("ui_left")
	assert_str(s.title_text()).is_equal("Tidepup  Lv 5")


func test_left_right_ignored_in_a_sub_list() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await _enter(s, "Train...")
	await _press("ui_right")
	await _press("next_creature")
	assert_str(s.title_text()).contains("Tidepup")
	assert_str(s.mode).is_equal("train")


func test_left_right_ignored_while_a_prompt_is_open() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 14)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	Story.give_creature("emberkit", 5)
	var spare := ""
	for m in c.move_pool:
		if not c.moves.has(m):
			spare = m
			break
	var s := await _open()
	await _enter(s, "Moves...")
	await _pick(s, db.move(spare).name)
	for i in 50:
		var lm := _screen(LearnMoveScreen) as LearnMoveScreen
		if lm != null and lm.menu.is_choosing():
			break
		await get_tree().process_frame
	await _press("ui_right")
	assert_str(s.title_text()).contains("Tidepup")
	await _answer(LearnMoveScreen, "Cancel")


# --- Moves -----------------------------------------------------------------------------------

func test_moves_list_shows_equipped_and_empty_slots() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 1)
	assert_int(c.moves.size()).is_less(4)
	var s := await _open()
	await _enter(s, "Moves...")
	assert_str(s.mode).is_equal("moves")
	assert_str(s.page_text()).contains("Equipped:")
	assert_str(s.page_text()).contains(LearnMoveScreen.move_line(db, c.moves[0]))
	assert_str(s.page_text()).contains("- empty -")


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
	await _enter(s, "Moves...")
	await _pick(s, db.move(spare).name)
	await _answer(LearnMoveScreen, "Replace " + db.move("tackle").name)
	assert_bool(c.moves.has(spare)).is_true()
	assert_bool(c.moves.has("tackle")).is_false()
	assert_bool(c.move_pool.has("tackle")).is_true()


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
	await _enter(s, "Moves...")
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


func test_moves_list_with_a_full_pool_fits() -> void:
	var c := Story.give_creature("tidepup", 14)
	for m in DataRegistry.db.ids("moves"):
		if c.move_pool.size() >= 10:
			break
		if not c.move_pool.has(m):
			c.move_pool.append(m)
	var s := await _open()
	await _enter(s, "Moves...")
	await _assert_fits(s, true)


# --- Train -----------------------------------------------------------------------------------

func test_train_plus_one_updates_points_and_card() -> void:
	var c := Story.give_creature("tidepup", 10)
	var s := await _open()
	await _enter(s, "Train...")
	assert_str(s.page_text()).contains("Points to spend: 9")
	var radar_before := _radar(s)
	await _pick(s, "+1 Physical Attack")
	await _frames()
	assert_int(c.trained("patk")).is_equal(1)
	assert_str(s.page_text()).contains("Points to spend: 8")
	var radar_after := _radar(s)
	assert_bool(radar_after != radar_before).override_failure_message("the card was not rebuilt").is_true()
	assert_int(StatRadar.axes(DataRegistry.db, radar_after.creature)[0].value).is_equal(c.stat(DataRegistry.db, "patk"))


func test_train_refused_at_cap_shows_reason() -> void:
	var c := Story.give_creature("tidepup", 40)
	c.training["patk"] = 30
	var s := await _open()
	await _enter(s, "Train...")
	await _pick(s, "+1 Physical Attack")
	assert_int(c.trained("patk")).is_equal(30)
	assert_str(s.page_text()).contains("Physical Attack is at the 30-point limit.")


func test_train_refused_with_no_points() -> void:
	var c := Story.give_creature("tidepup", 1)
	var s := await _open()
	await _enter(s, "Train...")
	await _pick(s, "+1 Physical Attack")
	assert_int(c.trained("patk")).is_equal(0)
	assert_str(s.page_text()).contains("No points left to spend.")


func test_focus_stays_on_the_picked_row_after_training() -> void:
	Story.give_creature("tidepup", 10)
	var s := await _open()
	await _enter(s, "Train...")
	await _pick(s, "+1 Physical Defense")
	await _frames()
	assert_str(_focus_text()).starts_with("+1 Physical Defense")
	assert_bool(s.page_text().contains("Points to spend: 8")).is_true()


func test_down_and_up_reach_every_option_in_the_train_list() -> void:
	Story.give_creature("tidepup", 10)
	var s := await _open()
	await _enter(s, "Train...")
	var want: Array = _enabled_buttons(s).map(func(b: Button): return b.text)
	assert_int(want.size()).is_greater(8)
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


func test_reset_seed_from_summary() -> void:
	var c := Story.give_creature("tidepup", 10)
	Training.train(DataRegistry.db, c, "patk", 3)
	GameState.current.inventory["reset_seed"] = 1
	var s := await _open()
	await _enter(s, "Train...")
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
	await _enter(s, "Train...")
	await _pick(s, "Use a Reset Seed")
	await _pick(s, "No")
	assert_int(c.trained("patk")).is_equal(3)
	assert_int(GameState.current.inventory.reset_seed).is_equal(1)


func test_reset_seed_refund_of_one_point_is_singular() -> void:
	var c := Story.give_creature("tidepup", 10)
	Training.train(DataRegistry.db, c, "patk", 1)
	GameState.current.inventory["reset_seed"] = 1
	var s := await _open()
	await _enter(s, "Train...")
	await _pick(s, "Use a Reset Seed")
	assert_str(s.page_text()).is_equal("Return 1 point from Tidepup?")
	await _pick(s, "Yes")
	assert_str(s.page_text()).contains("1 training point came back.")


func test_summary_reads_the_bag_of_the_save_it_is_given() -> void:
	var other := SaveGame.new_game("Bo", 0, RandomNumberGenerator.new())
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 10)
	other.party.append(c)
	other.inventory["reset_seed"] = 4
	SummaryScreen.run(world, other.party, 0, other)
	await get_tree().process_frame
	var s := _screen(SummaryScreen) as SummaryScreen
	await _enter(s, "Train...")
	assert_bool(s.menu.labels().has("Use a Reset Seed (you have 4)")).is_true()
	s.close()


# --- Held item ---------------------------------------------------------------------------------

func test_held_list_by_state() -> void:
	var c := Story.give_creature("tidepup", 10)
	GameState.current.inventory["test_charm"] = 1
	var s := await _open()
	await _enter(s, "Held item...")
	assert_str(s.page_text()).contains("Held item: none")
	assert_bool(s.menu.labels().has("Give held item")).is_true()
	assert_bool(s.menu.labels().has("Swap held item")).is_false()
	assert_bool(s.menu.labels().has("Take back")).is_false()
	c.held_item = "test_berry"  # holding one, and the bag has another
	s.show_mode("held")
	await _frames()
	assert_bool(s.menu.labels().has("Give held item")).is_false()
	assert_bool(s.menu.labels().has("Swap held item")).is_true()
	assert_bool(s.menu.labels().has("Take back")).is_true()
	GameState.current.inventory.erase("test_charm")  # nothing to swap with: only Take back
	s.show_mode("held")
	await _frames()
	assert_bool(s.menu.labels().has("Swap held item")).is_false()
	assert_bool(s.menu.labels().has("Take back")).is_true()


func test_summary_shows_the_held_item_line() -> void:
	var c := Story.give_creature("tidepup", 10)
	var s := await _open()
	assert_str(s.page_text()).contains("Held item: none")
	c.held_item = "test_charm"
	s.show_mode("top")
	await _frames()
	assert_str(s.page_text()).contains("Test Charm")
	assert_str(s.page_text()).contains("Raises Physical Attack a little.")


func test_give_from_the_summary() -> void:
	var c := Story.give_creature("tidepup", 10)
	GameState.current.inventory["test_charm"] = 2
	var s := await _open()
	await _enter(s, "Held item...")
	await _pick(s, "Give held item")
	await _pick(s, "Test Charm ×2")
	assert_str(c.held_item).is_equal("test_charm")
	assert_int(int(GameState.current.inventory["test_charm"])).is_equal(1)
	await _frames()
	assert_str(s.page_text()).contains("Test Charm")
	assert_str(s.page_text()).contains("Tidepup now holds the Test Charm.")


func test_give_back_out_changes_nothing() -> void:
	var c := Story.give_creature("tidepup", 10)
	GameState.current.inventory["test_charm"] = 1
	var s := await _open()
	await _enter(s, "Held item...")
	await _pick(s, "Give held item")
	await _pick(s, "Back")
	assert_str(c.held_item).is_empty()
	assert_int(int(GameState.current.inventory["test_charm"])).is_equal(1)


func test_swap_and_take_back_conserve_items() -> void:
	var c := Story.give_creature("tidepup", 10)
	GameState.current.inventory["test_charm"] = 1
	GameState.current.inventory["test_berry"] = 1
	var s := await _open()
	await _enter(s, "Held item...")
	await _pick(s, "Give held item")
	await _pick(s, "Test Charm ×1")
	assert_str(c.held_item).is_equal("test_charm")
	await _frames()
	await _pick(s, "Swap held item")
	await _pick(s, "Test Berry ×1")
	assert_str(c.held_item).is_equal("test_berry")
	assert_int(_count(c, "test_charm")).is_equal(1)
	assert_int(_count(c, "test_berry")).is_equal(1)
	assert_int(int(GameState.current.inventory["test_charm"])).is_equal(1)
	assert_bool(GameState.current.inventory.has("test_berry")).is_false()
	await _frames()
	await _pick(s, "Take back")
	assert_str(c.held_item).is_empty()
	assert_int(int(GameState.current.inventory["test_charm"])).is_equal(1)
	assert_int(int(GameState.current.inventory["test_berry"])).is_equal(1)
	await _frames()
	assert_str(s.page_text()).contains("Held item: none")
	assert_str(s.page_text()).contains("Took back the Test Berry.")


func test_unknown_held_id_shows_a_fallback() -> void:
	var c := Story.give_creature("tidepup", 10)
	c.held_item = "ghost"
	var s := await _open()
	assert_str(s.page_text()).contains("Held item: unknown item: ghost")
	await _assert_fits(s)
	await _enter(s, "Held item...")
	await _pick(s, "Take back")
	assert_str(c.held_item).is_empty()
	assert_int(int(GameState.current.inventory.get("ghost", 0))).is_equal(1)


func test_held_item_works_for_a_fainted_creature() -> void:
	var c := Story.give_creature("tidepup", 10)
	c.hp = 0
	GameState.current.inventory["test_charm"] = 1
	var s := await _open()
	await _enter(s, "Held item...")
	await _pick(s, "Give held item")
	await _pick(s, "Test Charm ×1")
	assert_str(c.held_item).is_equal("test_charm")


# --- Sub-list navigation and fit ----------------------------------------------------------------

func test_back_from_a_sub_list_returns_to_top_with_the_entry_focused() -> void:
	Story.give_creature("tidepup", 10)
	GameState.current.inventory["test_charm"] = 1
	var s := await _open()
	await _frames()
	for entry in ["Moves...", "Train...", "Held item..."]:
		await _enter(s, entry)
		assert_str(s.mode).is_not_equal("top")
		await _pick(s, "Back")
		await _frames()
		assert_str(s.mode).is_equal("top")
		assert_str(_focus_text()).is_equal(entry)


func test_back_in_the_top_level_closes_the_screen() -> void:
	Story.give_creature("tidepup", 10)
	var s := await _open()
	await _frames()
	assert_bool(s.menu.pick_label("Back")).is_true()
	await _frames()
	assert_object(_screen(SummaryScreen)).is_null()


func test_every_mode_fits_the_screen() -> void:
	Story.give_creature("tidepup", 14)
	Story.give_creature("emberkit", 5)
	GameState.current.inventory["test_charm"] = 1
	var s := await _open()
	await _frames()
	await _assert_fits(s)
	for m in ["moves", "train", "held"]:
		s.show_mode(m)
		await _frames()
		await _assert_fits(s, true)  # the Train list is long enough to scroll a little


func test_top_level_fits_with_every_stat_trained_and_a_long_held_item() -> void:
	var c := Story.give_creature("tidepup", 99)
	for key in DataSchemas.TRAINABLE_STATS:
		c.training[key] = 30
	_add_item("test_long", "The Extraordinarily Long Named Held Item",
		"Does a great many wonderful things for its holder, including a long sentence about all of them.")
	c.held_item = "test_long"
	c.nickname = "Sir Reginald Bartholomew Torrentusk the Magnificent Third"
	GameState.current.inventory["test_charm"] = 1
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await _frames()
	await _assert_fits(s, true)  # nine entries and long lines: scrolling is allowed
	for m in ["train", "held", "moves"]:
		s.show_mode(m)
		await _frames()
		await _assert_fits(s, true)
