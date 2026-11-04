extends GdUnitTestSuite
## The shared ProgressScreen layout: info panel on top, menu below it, and a menu
## too long for the screen scrolls instead of running off the bottom.

var screen: ProgressScreen


func before_test() -> void:
	screen = ProgressScreen.new()
	add_child(screen)
	await get_tree().process_frame


func after_test() -> void:
	screen.free()


func _options(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"label": "Option %d" % i, "value": i})
	return out


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func test_short_menu_sits_under_the_info_panel() -> void:
	screen._body.text = "A short line."
	screen.menu.choose("", _options(2), true, 1)
	await _settle()
	assert_array(Array(ScreenFit.problems(screen))).is_empty()
	var panel := screen.menu_panel().get_global_rect()
	assert_float(panel.size.y).is_less(120.0)  # only as tall as its two options
	assert_float(panel.position.y - screen.info_panel().get_global_rect().end.y).is_less_equal(8.0)


func test_long_text_pushes_the_menu_down_without_overlap() -> void:
	var lines := PackedStringArray()
	for i in 6:
		lines.append("A long wrapped description line number %d that goes on for a while to wrap." % i)
	screen._body.text = "\n".join(lines)
	screen.menu.button_width = ProgressScreen.HALF_WIDTH
	screen.menu.choose("", _options(4), true, 2)
	await _settle()
	assert_array(Array(ScreenFit.problems(screen))).is_empty()


func test_a_menu_taller_than_the_screen_scrolls() -> void:
	screen.menu.choose("", _options(30), true, 1)
	await _settle()
	assert_array(Array(ScreenFit.problems(screen))).is_empty()
	var scroll := screen.menu_area() as ScrollContainer
	assert_float(scroll.get_v_scroll_bar().max_value).is_greater(scroll.size.y)


func test_focus_on_a_far_option_scrolls_it_into_view() -> void:
	screen.menu.choose("", _options(30), true, 1)
	await _settle()
	var last: Button = null
	for b in screen.menu.find_children("*", "Button", true, false):
		if (b as Button).text == "Option 29":
			last = b
	last.grab_focus()
	await _settle()
	var area := screen.menu_area().get_global_rect()
	assert_bool(area.encloses(last.get_global_rect().grow(-1.0))).is_true()
