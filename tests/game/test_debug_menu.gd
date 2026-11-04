extends GdUnitTestSuite
## The F1 debug overlay: opens over any screen, pauses the game, and its party
## tools act on the current playthrough. Saves go to a throwaway folder.

const SAVES := "user://test_debug_menu_saves"

var _old_store: SaveStore


func before() -> void:
	_old_store = GameState.store
	GameState.store = SaveStore.new(SAVES)


func after() -> void:
	DebugMenu.close()
	GameState.close_game()
	GameState.store = _old_store
	var d := DirAccess.open(SAVES)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(SAVES.path_join(f))
		DirAccess.remove_absolute(SAVES)


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
	Overworld.instant = true
	var world: Overworld = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	DebugMenu.open()
	var buttons := _labels()
	assert_bool(buttons["Custom battle..."].disabled).is_true()
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
	world.free()
	Overworld.instant = false


# --- M4 progression tools ------------------------------------------------------------

func _open_world_with(c: CreatureInstance) -> Overworld:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	GameState.current.party.append(c)
	Overworld.instant = true
	var world: Overworld = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
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
	world.free()
	Overworld.instant = false


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
	world.free()
	Overworld.instant = false


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
	world.free()
	Overworld.instant = false


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
	world.free()
	Overworld.instant = false


func test_progress_tools_disabled_without_a_party() -> void:
	DebugMenu.close()
	await get_tree().process_frame
	assert_str(GameState.start_new_game("Ana")).is_empty()
	Overworld.instant = true
	var world: Overworld = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	DebugMenu.open()
	var buttons := _labels()
	for b in ["Give XP...", "Set Affinity..."]:
		assert_bool(buttons[b].disabled).override_failure_message(b).is_true()
	assert_bool(buttons["Fill box"].disabled).is_false()
	DebugMenu.close()
	world.free()
	Overworld.instant = false


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
	world.lock("menu")
	DebugMenu.open()
	var buttons := _labels()
	for b in ["Give XP...", "Set Affinity...", "Fill box"]:
		assert_bool(buttons[b].disabled).override_failure_message(b).is_true()
	DebugMenu.close()
	world.free()
	Overworld.instant = false


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
