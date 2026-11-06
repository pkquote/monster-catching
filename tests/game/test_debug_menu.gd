extends GdUnitTestSuite
## The F1 debug overlay: opens over any screen, pauses the game, and its party
## tools act on the current playthrough. Saves go to a throwaway folder.

var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("debug_menu", false)


func after() -> void:
	DebugMenu.close()
	WorldTest.end_suite(_suite)


func _labels() -> Dictionary:
	var out := {}
	var stack: Array = [DebugMenu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			out[n.text] = n
		stack.append_array(n.get_children())
	return out


func test_without_a_game_only_explains() -> void:
	GameState.close_game()
	DebugMenu.open()
	assert_bool(get_tree().paused).is_true()
	var buttons := _labels()
	assert_bool(buttons.has("Get test party")).is_false()
	assert_bool(buttons.has("Close")).is_true()
	DebugMenu.close()
	assert_bool(get_tree().paused).is_false()


func test_test_party_unlocks_battles() -> void:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	var world := await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	DebugMenu.open()
	var buttons := _labels()
	assert_bool(buttons["Wild battle (Route 1)"].disabled).is_true()
	assert_bool(buttons["Custom battle..."].disabled).is_false()  # builds its own teams
	buttons["Get test party"].pressed.emit()
	await get_tree().process_frame
	assert_int(GameState.current.party.size()).is_equal(BattleLauncher.TEST_PARTY.size())
	buttons = _labels()
	assert_bool(buttons["Get test party"].disabled).is_true()
	for b in ["Wild battle (Route 1)", "Scout Ana (1v1)", "Rival (2v2)", "Custom battle..."]:
		assert_bool(buttons[b].disabled).override_failure_message(b).is_false()
	buttons["Custom battle..."].pressed.emit()
	await get_tree().process_frame
	assert_bool(_labels().has("Start")).is_true()
	DebugMenu.close()
	assert_bool(DebugMenu.is_open()).is_false()
	WorldTest.close(world)


# --- M4 progression tools ------------------------------------------------------------

func _open_world_with(c: CreatureInstance) -> Overworld:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	GameState.current.party.append(c)
	var world := await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	return world


func test_give_xp_to_16_runs_progress() -> void:
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 15)
	var world := await _open_world_with(c)
	DebugMenu.open()
	_labels()["Give XP..."].pressed.emit()
	await get_tree().process_frame
	_labels()["To level 16"].pressed.emit()
	for i in 10:
		await get_tree().process_frame
	assert_int(c.level).is_equal(16)
	assert_bool(DebugMenu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	var grow: Node = null
	for n in world.get_children():
		if n is GrowScreen:
			grow = n
	assert_object(grow).is_not_null()
	assert_bool(world.is_locked()).is_true()
	DebugMenu.close()
	WorldTest.close(world)


func test_set_affinity_steers_growth() -> void:
	var db := DataRegistry.db
	var c := CreatureInstance.create(db, "tidepup", 15)
	var world := await _open_world_with(c)
	DebugMenu.open()
	_labels()["Set Affinity..."].pressed.emit()
	await get_tree().process_frame
	_labels()[db.affinity("catalyst").name].pressed.emit()
	await get_tree().process_frame
	assert_int(c.affinity["catalyst"]).is_equal(db.balance.growth_affinity_threshold + 10)
	_labels()["Give XP..."].pressed.emit()
	await get_tree().process_frame
	_labels()["To level 16"].pressed.emit()
	for i in 10:
		await get_tree().process_frame
	assert_str(Progression.growth_target(db, c)).is_equal("mistcoil")
	DebugMenu.close()
	WorldTest.close(world)


## The page's drop-downs in tree order: creature, then (on the passive page) passive and slot.
func _options() -> Array[Node]:
	return DebugMenu.find_children("*", "OptionButton", true, false)


func _status_text() -> String:
	return DebugMenu._status.text


func test_set_affinity_unlocks_passive() -> void:
	var db := DataRegistry.db
	var c := CreatureInstance.create(db, "tidepup", 9)
	var world := await _open_world_with(c)
	DebugMenu.open()
	_labels()["Set Affinity..."].pressed.emit()
	await get_tree().process_frame
	_labels()[db.affinity("warden").name].pressed.emit()
	await get_tree().process_frame
	assert_str(c.affinity_passive).is_equal("guardian_aura")
	assert_str(_status_text()).contains(db.passive("guardian_aura").name)
	# Already unlocked: a second track leaves the slot alone.
	_labels()["Set Affinity..."].pressed.emit()
	await get_tree().process_frame
	_labels()[db.affinity("striker").name].pressed.emit()
	await get_tree().process_frame
	assert_str(c.affinity_passive).is_equal("guardian_aura")
	DebugMenu.close()
	WorldTest.close(world)


## Opens the Set passive page and applies `passive_id` ("" = none) to `slot`.
func _apply_passive(passive_id: String, slot: int, make_active: bool) -> void:
	_labels()["Set passive..."].pressed.emit()
	await get_tree().process_frame
	var ids := DebugPassivePage.save_safe_passives(DataRegistry.db)
	var opts := _options()
	opts[1].selected = ids.size() if passive_id == "" else ids.find(passive_id)
	opts[2].selected = slot
	(_labels()["Make active"] as CheckBox).button_pressed = make_active
	_labels()["Apply"].pressed.emit()
	await get_tree().process_frame


func test_set_passive_page_sets_slot_and_active() -> void:
	var db := DataRegistry.db
	var c := CreatureInstance.create(db, "tidepup", 9)
	var world := await _open_world_with(c)
	DebugMenu.open()
	await _apply_passive("sturdy", 1, true)
	assert_str(c.affinity_passive).is_equal("sturdy")
	assert_str(c.active_passive).is_equal(Passives.SLOT_AFFINITY)
	assert_str(Passives.active_id(c)).is_equal("sturdy")
	assert_str(_status_text()).contains(db.passive("sturdy").name)
	await _apply_passive("kindling", 0, false)
	assert_str(c.passive).is_equal("kindling")
	assert_str(c.active_passive).is_equal(Passives.SLOT_AFFINITY)
	var r := GameState.store.read(GameState.current_path)
	assert_bool(r.ok).is_true()
	assert_str(r.save.party[0].passive).is_equal("kindling")
	assert_str(r.save.party[0].affinity_passive).is_equal("sturdy")
	DebugMenu.close()
	WorldTest.close(world)


func test_set_passive_page_never_offers_test_pack_passives() -> void:
	# The page writes to the real party and autosaves, so tp_ passives (loaded in debug
	# builds when data_testpack/ exists) must not be offered; every other passive is.
	# test_testpack_safety.gd checks the filter against a database that has pack passives.
	var db: Database = DataRegistry.db
	var safe: PackedStringArray = DebugPassivePage.save_safe_passives(db)
	for id: String in db.ids("passives"):
		assert_bool(safe.has(id)).override_failure_message(id).is_equal(not Database.is_test_content(id))
	var c: CreatureInstance = CreatureInstance.create(db, "tidepup", 9)
	var world: Overworld = await _open_world_with(c)
	DebugMenu.open()
	_labels()["Set passive..."].pressed.emit()
	await get_tree().process_frame
	var passive_opt: OptionButton = _options()[1]
	assert_int(passive_opt.item_count).is_equal(safe.size() + 1)
	for i: int in passive_opt.item_count - 1:
		assert_str(passive_opt.get_item_text(i)).is_equal(db.passive(safe[i]).name)
	DebugMenu.close()
	WorldTest.close(world)


func test_set_passive_page_refuses_to_activate_an_empty_slot() -> void:
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 9)
	var world := await _open_world_with(c)
	DebugMenu.open()
	await _apply_passive("", 1, true)
	assert_str(c.affinity_passive).is_empty()
	assert_str(c.active_passive).is_equal(Passives.SLOT_ROLLED)
	assert_str(_status_text()).contains("empty")
	assert_bool(DebugMenu.is_open()).is_true()
	DebugMenu.close()
	WorldTest.close(world)


## Any id may go in the Affinity slot; it counts as the unlock and survives growth.
func test_debug_affinity_passive_keeps_progress_working() -> void:
	var db := DataRegistry.db
	var c := CreatureInstance.create(db, "tidepup", 15)
	var world := await _open_world_with(c)
	DebugMenu.open()
	await _apply_passive("sturdy", 1, true)
	_labels()["Set Affinity..."].pressed.emit()
	await get_tree().process_frame
	_labels()[db.affinity("catalyst").name].pressed.emit()
	await get_tree().process_frame
	assert_str(c.affinity_passive).is_equal("sturdy")
	var before := c.level
	Progression.award_xp(db, c, Stats.xp_for_level(16) - c.xp)
	var entry := Progression.progress_entry(db, c, before, "sturdy")
	assert_object(entry).is_not_null()
	assert_str(entry.unlocked_passive).is_empty()
	Progression.apply_growth(db, c, Progression.growth_target(db, c))
	assert_str(c.species).is_equal("mistcoil")
	assert_str(c.affinity_passive).is_equal("sturdy")
	assert_str(Passives.active_id(c)).is_equal("sturdy")
	DebugMenu.close()
	WorldTest.close(world)


func test_fill_box_adds_12() -> void:
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 9)
	var world := await _open_world_with(c)
	DebugMenu.open()
	_labels()["Fill box"].pressed.emit()
	await get_tree().process_frame
	var box := GameState.current.storage
	assert_int(box.size()).is_equal(12)
	for b: CreatureInstance in box:
		assert_int(b.level).is_equal(9)
	DebugMenu.close()
	WorldTest.close(world)


func test_give_xp_choices_are_autosaved() -> void:
	var c := CreatureInstance.create(DataRegistry.db, "tidepup", 15)
	var world := await _open_world_with(c)
	DebugMenu.open()
	_labels()["Give XP..."].pressed.emit()
	await get_tree().process_frame
	_labels()["To level 16"].pressed.emit()
	# Answer whatever the progress screens ask until the world is unlocked again.
	for i in 400:
		await get_tree().process_frame
		for n in world.get_children():
			if (n is GrowScreen or n is LearnMoveScreen) and n.menu.is_choosing():
				for label in ["Grow now", "OK", "Keep it for later"]:
					if n.menu.pick_label(label):
						break
		if i > 5 and not world.is_locked():
			break
	await get_tree().process_frame
	assert_str(c.species).is_equal("torrentusk")
	var r := GameState.store.read(GameState.current_path)
	assert_bool(r.ok).is_true()
	assert_str(r.save.party[0].species).is_equal("torrentusk")
	WorldTest.close(world)


func test_progress_tools_disabled_without_a_party() -> void:
	DebugMenu.close()
	await get_tree().process_frame
	assert_str(GameState.start_new_game("Ana")).is_empty()
	var world := await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	DebugMenu.open()
	var buttons := _labels()
	for b in ["Give XP...", "Set Affinity...", "Set passive..."]:
		assert_bool(buttons[b].disabled).override_failure_message(b).is_true()
	assert_bool(buttons["Fill box"].disabled).is_false()
	DebugMenu.close()
	WorldTest.close(world)


func test_progress_tools_disabled_without_a_world() -> void:
	DebugMenu.close()
	await get_tree().process_frame
	assert_str(GameState.start_new_game("Ana")).is_empty()
	GameState.current.party.append(CreatureInstance.create(DataRegistry.db, "tidepup", 9))
	DebugMenu.open()
	var buttons := _labels()
	for b in ["Give XP...", "Set Affinity...", "Fill box"]:
		assert_bool(buttons[b].disabled).override_failure_message(b).is_true()


func test_progress_tools_disabled_while_world_is_locked() -> void:
	var world := await _open_world_with(CreatureInstance.create(DataRegistry.db, "tidepup", 9))
	world.lock(Overworld.LOCK_MENU)
	DebugMenu.open()
	var buttons := _labels()
	for b in ["Give XP...", "Set Affinity...", "Fill box"]:
		assert_bool(buttons[b].disabled).override_failure_message(b).is_true()
	DebugMenu.close()
	WorldTest.close(world)


## The main page lists every tool and the status line: its panel must stay on the 640x360 screen.
func test_main_page_fits_the_screen() -> void:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	BattleLauncher.grant_test_party(DataRegistry.db, GameState.current)
	DebugMenu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = DebugMenu._root.get_child(1).get_child(0)
	var rect := panel.get_global_rect()
	assert_float(rect.position.y).is_greater_equal(0.0)
	assert_float(rect.end.y).is_less_equal(360.0)
	DebugMenu.close()


# --- Logs page --------------------------------------------------------------------

const TEST_LOG_CFG := "user://test_debug_logging.cfg"


func _open_logs() -> void:
	DebugMenu.open()
	_labels()["Logs..."].pressed.emit()
	await get_tree().process_frame


func test_logs_page_lists_recent_records() -> void:
	var state := Log.save_state()
	Log.set_level(Log.UI, Log.Level.INFO)
	Log.info(Log.UI, "viewer probe line")
	await _open_logs()
	assert_bool("\n".join(DebugMenu.log_lines()).contains("viewer probe line")).is_true()
	DebugMenu.close()
	Log.restore_state(state)


func test_logs_page_filters_by_level_and_category() -> void:
	var state := Log.save_state()
	Log.set_level(Log.UI, Log.Level.INFO)
	Log.set_level(Log.SAVE, Log.Level.INFO)
	Log.info(Log.UI, "filter probe ui")
	Log.warn(Log.SAVE, "filter probe save")
	await _open_logs()
	DebugMenu.set_log_filter(Log.Level.WARN, "")
	var text := "\n".join(DebugMenu.log_lines())
	assert_bool(text.contains("filter probe save")).is_true()
	assert_bool(text.contains("filter probe ui")).is_false()
	DebugMenu.set_log_filter(Log.Level.TRACE, Log.UI)
	text = "\n".join(DebugMenu.log_lines())
	assert_bool(text.contains("filter probe ui")).is_true()
	assert_bool(text.contains("filter probe save")).is_false()
	DebugMenu.close()
	Log.restore_state(state)


func test_logs_page_changes_and_saves_levels() -> void:
	var state := Log.save_state()
	var old_path: String = Logging.config_path
	Logging.config_path = TEST_LOG_CFG
	await _open_logs()
	DebugMenu.set_category_level(Log.BATTLE, Log.Level.TRACE)
	assert_int(Log.level_of(Log.BATTLE)).is_equal(Log.Level.TRACE)
	_labels()["Save levels"].pressed.emit()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TEST_LOG_CFG)).is_equal(OK)
	assert_str(str(cfg.get_value("levels", "battle"))).is_equal("TRACE")
	DebugMenu.close()
	Logging.config_path = old_path
	Log.restore_state(state)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LOG_CFG))


func test_logs_page_fits_the_screen() -> void:
	await _open_logs()
	await get_tree().process_frame
	var panel: Control = DebugMenu._scroll.get_parent()
	assert_float(panel.position.y + panel.size.y).is_less_equal(360.0)
	DebugMenu.close()


func test_logs_page_keyboard_never_gets_stuck_in_the_log_text() -> void:
	for i in 30:  # a real log is long: Down would walk the caret line by line
		Log.warn(Log.UI, "keyboard probe %d" % i)
	await _open_logs()
	await get_tree().process_frame
	var view: Control = DebugMenu._log_view
	view.grab_focus()
	await get_tree().process_frame
	for i in 6:  # a real key press: it is also the TextEdit's caret-down shortcut
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = KEY_DOWN
			ev.physical_keycode = KEY_DOWN
			ev.pressed = pressed
			get_viewport().push_input(ev)
		await get_tree().process_frame
	assert_object(get_viewport().gui_get_focus_owner()).is_not_same(view)
	DebugMenu.close()


func test_battle_starts_after_the_count_even_if_the_menu_was_closed() -> void:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	BattleLauncher.grant_test_party(DataRegistry.db, GameState.current)
	var world := await WorldTest.open(self, "test_b", "middle", WorldTest.KEEP_GAME)
	DebugMenu.open()
	_labels()["Rival (2v2)"].pressed.emit()
	await get_tree().process_frame
	DebugMenu.close()  # F1 while the "how many?" prompt is up
	await get_tree().process_frame
	var prompt: FieldCountPrompt = null
	for n in DebugMenu.get_children():
		if n is FieldCountPrompt:
			prompt = n
	assert_object(prompt).is_not_null()
	var menu: CommandMenu = prompt.find_children("*", "CommandMenu", true, false)[0]
	assert_bool(menu.pick_label("2 creatures")).is_true()
	for i in 10:
		await get_tree().process_frame
	assert_bool(world.battles.in_battle()).is_true()
	WorldTest.close(world)
