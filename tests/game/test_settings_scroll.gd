extends GdUnitTestSuite
## The Settings tabs scroll to follow keyboard/gamepad focus, so every Controls
## binding stays reachable on the 640x360 screen.


func _open() -> Control:
	var node: Control = auto_free(load("res://game/menus/settings_menu.tscn").instantiate())
	add_child(node)
	await get_tree().process_frame
	await get_tree().process_frame
	return node


func _scroll_of(tab: Control) -> ScrollContainer:
	return tab.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer


func _controls_tab(node: Control) -> Control:
	for i: int in node.tabs.get_tab_count():
		if node.tabs.get_tab_title(i) == "Controls":
			return node.tabs.get_tab_control(i)
	fail("no Controls tab")
	return null


func _show_controls(node: Control) -> void:
	node.tabs.current_tab = node.tabs.get_tab_idx_from_control(_controls_tab(node))


func test_every_tab_scroll_follows_focus() -> void:
	var node: Control = await _open()
	for i: int in node.tabs.get_tab_count():
		assert_bool(_scroll_of(node.tabs.get_tab_control(i)).follow_focus).is_true()
	remove_child(node)


func test_last_controls_binding_scrolls_into_view() -> void:
	var node: Control = await _open()
	_show_controls(node)
	await get_tree().process_frame
	var scroll: ScrollContainer = _scroll_of(_controls_tab(node))
	# Make sure the content overflows the viewport, whatever the tab's natural size is.
	scroll.custom_minimum_size = Vector2(0, 120)
	node.tabs.custom_minimum_size = Vector2(460, 150)
	await get_tree().process_frame
	await get_tree().process_frame
	var content: Control = scroll.get_child(0) as Control
	assert_float(content.size.y).is_greater(scroll.size.y)
	assert_int(scroll.scroll_vertical).is_equal(0)
	var last: String = GameSettings.ACTIONS[GameSettings.ACTIONS.size() - 1]
	var b: Button = node.bind_buttons[last].keyboard
	b.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_greater(0)
	var visible: Rect2 = scroll.get_global_rect()
	assert_bool(visible.encloses(b.get_global_rect().grow(-0.5))).override_failure_message(
		"button %s is outside the scroll area %s" % [b.get_global_rect(), visible]).is_true()
	remove_child(node)


func test_arrow_down_from_tab_bar_reaches_a_binding() -> void:
	var node: Control = await _open()
	_show_controls(node)
	await get_tree().process_frame
	var bar: TabBar = node.tabs.get_tab_bar()
	bar.grab_focus()
	await get_tree().process_frame
	assert_object(get_viewport().gui_get_focus_owner()).is_same(bar)
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "ui_down"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var focused: Control = get_viewport().gui_get_focus_owner()
	assert_object(focused).is_not_null()
	assert_bool(_controls_tab(node).is_ancestor_of(focused)).override_failure_message(
		"focus is on %s, not inside the Controls tab" % focused).is_true()
	remove_child(node)
