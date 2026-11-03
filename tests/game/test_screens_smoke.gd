extends GdUnitTestSuite
## Every front-end screen loads and builds without script errors, and the
## Settings autoload round-trips bindings through real InputEvents.

const SCREENS := [
	"res://game/boot/splash.tscn",
	"res://game/menus/title_menu.tscn",
	"res://game/menus/new_game.tscn",
	"res://game/menus/load_menu.tscn",
	"res://game/menus/settings_menu.tscn",
]


func test_screens_build() -> void:
	for path in SCREENS:
		var scene: PackedScene = load(path)
		assert_object(scene).is_not_null()
		var node: Control = auto_free(scene.instantiate())
		add_child(node)
		await get_tree().process_frame
		assert_int(node.get_child_count()).is_greater(0)
		node.set_process_input(false)
		remove_child(node)


func test_new_game_requires_a_name() -> void:
	var node: Control = auto_free(load("res://game/menus/new_game.tscn").instantiate())
	add_child(node)
	await get_tree().process_frame
	assert_bool(node.start_button.disabled).is_true()
	node.name_edit.text = "   "
	node._refresh()
	assert_bool(node.start_button.disabled).is_true()
	node.name_edit.text = "  Ana "
	node._refresh()
	assert_bool(node.start_button.disabled).is_false()
	assert_str(node.clean_name()).is_equal("Ana")
	remove_child(node)


func test_settings_screen_has_four_tabs_and_all_bindings() -> void:
	var node: Control = auto_free(load("res://game/menus/settings_menu.tscn").instantiate())
	add_child(node)
	await get_tree().process_frame
	assert_int(node.tabs.get_tab_count()).is_equal(4)
	for action in GameSettings.ACTIONS:
		assert_str(node.bind_buttons[action].keyboard.text).is_not_equal("—")
	remove_child(node)


func test_bindings_convert_to_events_and_back() -> void:
	for action in GameSettings.ACTIONS:
		for device in ["keyboard", "gamepad"]:
			for b in GameSettings.default_bindings()[action][device]:
				var ev := Settings.binding_to_event(b)
				if ev is InputEventKey or ev is InputEventJoypadButton:
					ev.pressed = true
				assert_dict(Settings.event_to_binding(ev)).is_equal(b)
				assert_str(Settings.describe(b)).is_not_empty()


func test_controls_are_applied_to_the_input_map() -> void:
	Settings.apply_controls()
	for action in GameSettings.ACTIONS:
		assert_bool(InputMap.has_action(action)).is_true()
	# Menus follow game bindings.
	assert_int(InputMap.action_get_events("ui_accept").size()).is_equal(InputMap.action_get_events("accept").size())
