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
