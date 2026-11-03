extends GdUnitTestSuite
## Settings defaults, validation and bindings.


func test_defaults_round_trip() -> void:
	var s := GameSettings.new()
	var back := GameSettings.from_dict(s.to_dict())
	assert_dict(back.to_dict()).is_equal(s.to_dict())


func test_invalid_values_fall_back_to_defaults() -> void:
	var s := GameSettings.from_dict({
		"audio": {"master": 5.0, "music": "loud", "sfx": -1},
		"display": {"window_scale": 7, "fullscreen": "yes"},
		"gameplay": {"text_speed": "warp", "battle_speed": 3},
	})
	assert_float(s.master_volume).is_equal(1.0)  # clamped
	assert_float(s.music_volume).is_equal(0.8)  # default
	assert_float(s.sfx_volume).is_equal(0.0)  # clamped
	assert_int(s.window_scale).is_equal(2)
	assert_bool(s.fullscreen).is_false()
	assert_str(s.text_speed).is_equal("normal")
	assert_int(s.battle_speed).is_equal(1)


func test_garbage_input_gives_defaults() -> void:
	var s := GameSettings.from_dict({"audio": 3, "controls": "nope"})
	assert_dict(s.to_dict()).is_equal(GameSettings.new().to_dict())


func test_every_action_has_keyboard_and_gamepad_defaults() -> void:
	var b := GameSettings.default_bindings()
	for action in GameSettings.ACTIONS:
		assert_bool(b[action].keyboard.is_empty()).is_false()
		assert_bool(b[action].gamepad.is_empty()).is_false()
		assert_bool(GameSettings.ACTION_LABELS.has(action)).is_true()


func test_rebind_replaces_primary_binding_only() -> void:
	var s := GameSettings.new()
	var second: Dictionary = s.bindings.accept.keyboard[1]
	s.rebind("accept", "keyboard", {"type": "key", "keycode": KEY_SPACE})
	assert_int(s.bindings.accept.keyboard[0].keycode).is_equal(KEY_SPACE)
	assert_dict(s.bindings.accept.keyboard[1]).is_equal(second)


func test_saved_bindings_load_back() -> void:
	var s := GameSettings.new()
	s.rebind("menu", "gamepad", {"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "value": -1})
	var back := GameSettings.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_int(back.bindings.menu.gamepad[0].axis).is_equal(JOY_AXIS_RIGHT_Y)
	assert_int(back.bindings.menu.gamepad[0].value).is_equal(-1)


func test_invalid_bindings_are_ignored() -> void:
	var d := GameSettings.new().to_dict()
	d.controls.cancel.keyboard = [{"type": "key", "keycode": -4}]
	var s := GameSettings.from_dict(d)
	assert_dict(s.bindings.cancel).is_equal(GameSettings.default_bindings().cancel)


func test_reset_bindings() -> void:
	var s := GameSettings.new()
	s.rebind("accept", "keyboard", {"type": "key", "keycode": KEY_SPACE})
	s.reset_bindings()
	assert_dict(s.bindings).is_equal(GameSettings.default_bindings())
