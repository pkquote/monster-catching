extends GdUnitTestSuite
## CommandMenu paging (max_rows): when a list pages, the page entries, focus, wrapping,
## Cancel, and the value a pick on a later page returns.

var menu: CommandMenu
var got: Array = []


func before_test() -> void:
	got = []
	menu = CommandMenu.new()
	add_child(menu)
	menu.picked.connect(func(v: Variant) -> void: got.append(v))


func after_test() -> void:
	menu.queue_free()
	await get_tree().process_frame


func _options(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append({"label": "Opt%02d" % i, "value": i})
	return out


## Starts choose() without awaiting it, then lets the deferred focus land.
func _open(options: Array, columns: int, allow_cancel: bool = true) -> void:
	menu.choose("Pick", options, allow_cancel, columns)
	await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _turn(label: String) -> void:
	assert_bool(menu.pick_label(label)).is_true()
	await _settle()


func _option_labels() -> Array:
	return Array(menu.labels()).filter(func(l: String) -> bool: return l.begins_with("Opt"))


func _focused_text() -> String:
	var f: Control = get_viewport().gui_get_focus_owner()
	return (f as Button).text if f is Button else ""


func test_exactly_max_rows_times_columns_does_not_page() -> void:
	menu.max_rows = 3
	await _open(_options(9), 3)
	assert_int(menu.page_count()).is_equal(1)
	assert_int(menu.labels().size()).is_equal(9)
	assert_bool(Array(menu.labels()).has(CommandMenu.PREV_PAGE)).is_false()


func test_one_more_pages_into_two_non_empty_pages() -> void:
	menu.max_rows = 3
	await _open(_options(10), 3)
	assert_int(menu.page_count()).is_equal(2)
	assert_array(_option_labels()).has_size(7)
	assert_array(Array(menu.labels()).slice(7)).is_equal([CommandMenu.PREV_PAGE, "Next page · 1/2"])
	await _turn(CommandMenu.NEXT_PAGE)
	assert_array(_option_labels()).is_equal(["Opt07", "Opt08", "Opt09"])
	assert_array(Array(menu.labels()).slice(3)).is_equal([CommandMenu.PREV_PAGE, "Next page · 2/2"])


func test_default_max_rows_never_pages() -> void:
	assert_int(menu.max_rows).is_equal(0)
	await _open(_options(40), 3)
	assert_int(menu.page_count()).is_equal(1)
	assert_int(menu.labels().size()).is_equal(40)


func test_previous_and_next_wrap() -> void:
	menu.max_rows = 3
	await _open(_options(20), 3)  # 7 per page: 3 pages
	assert_int(menu.page_count()).is_equal(3)
	await _turn(CommandMenu.PREV_PAGE)  # page 1 -> 3
	assert_array(_option_labels()).is_equal(["Opt14", "Opt15", "Opt16", "Opt17", "Opt18", "Opt19"])
	assert_str(_focused_text()).is_equal(CommandMenu.PREV_PAGE)  # focus stays on the page button
	await _turn(CommandMenu.NEXT_PAGE)  # page 3 -> 1
	assert_str(_option_labels()[0]).is_equal("Opt00")
	assert_str(_focused_text()).starts_with(CommandMenu.NEXT_PAGE)
	assert_array(got).is_empty()  # turning pages picks nothing


func test_pick_on_page_two_returns_its_value() -> void:
	menu.max_rows = 3
	await _open(_options(10), 3)
	await _turn(CommandMenu.NEXT_PAGE)
	assert_bool(menu.pick_label("Opt08")).is_true()
	assert_array(got).is_equal([8])
	assert_bool(menu.is_choosing()).is_false()


func test_disabled_entries_and_a_fully_disabled_page() -> void:
	var options: Array = _options(7)
	menu.max_rows = 2  # 2 rows x 3 columns: 4 options per page, 2 pages
	for i: int in [1, 4, 5, 6]:
		options[i]["disabled"] = true
	await _open(options, 3)
	assert_int(menu.page_count()).is_equal(2)
	assert_bool(menu.pick_label("Opt01")).is_false()  # disabled entry shown but not pickable
	assert_str(_focused_text()).is_equal("Opt00")
	await _turn(CommandMenu.NEXT_PAGE)
	assert_array(_option_labels()).is_equal(["Opt04", "Opt05", "Opt06"])
	assert_str(_focused_text()).starts_with(CommandMenu.NEXT_PAGE)  # page 2 is all disabled
	# A disabled `focus` option doesn't pick the opening page.
	menu.interrupt(null)
	var later: Array = _options(7)
	for i: int in [4, 5, 6]:
		later[i]["disabled"] = true
	later[4]["focus"] = true
	await _open(later, 3)
	assert_str(_option_labels()[0]).is_equal("Opt00")
	# A narrow menu (1 column, 1 row) still pages, one option per page; a page whose
	# only option is disabled focuses Next page.
	menu.interrupt(null)
	menu.max_rows = 1
	var narrow: Array = _options(3)
	narrow[0]["disabled"] = true
	await _open(narrow, 1)  # 1 row: a single option per page
	assert_int(menu.page_count()).is_equal(3)
	assert_array(_option_labels()).is_equal(["Opt00"])
	assert_str(_focused_text()).starts_with(CommandMenu.NEXT_PAGE)


func test_focus_option_on_a_later_page_opens_that_page() -> void:
	menu.max_rows = 3
	var options: Array = _options(16)
	options[12]["focus"] = true
	await _open(options, 3)
	assert_str(Array(menu.labels()).back()).is_equal("Next page · 2/3")
	assert_str(_focused_text()).is_equal("Opt12")
	assert_bool(menu.pick_label("Opt12")).is_true()
	assert_array(got).is_equal([12])


func test_cancel_key_works_on_page_two() -> void:
	menu.max_rows = 3
	await _open(_options(10), 3, true)
	await _turn(CommandMenu.NEXT_PAGE)
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)
	await _settle()
	assert_array(got).is_equal([null])
	assert_bool(menu.is_choosing()).is_false()


func test_cancel_key_ignored_when_not_allowed() -> void:
	menu.max_rows = 3
	await _open(_options(10), 3, false)
	await _turn(CommandMenu.NEXT_PAGE)
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)
	await _settle()
	assert_array(got).is_empty()
	assert_bool(menu.is_choosing()).is_true()
