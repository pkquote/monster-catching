extends GdUnitTestSuite
## ProgressScreen's optional side control: a control to the left of the info panel and the menu.


func _screen(side: Control = null) -> ProgressScreen:
	var s := ProgressScreen.new()
	if side != null:
		s.set_side(side)
	add_child(auto_free(s))
	return s


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func test_without_a_side_control_nothing_changes() -> void:
	var s := _screen()
	await _settle()
	assert_object(s.side_control()).is_null()
	var top := s.info_panel().get_global_rect()
	assert_float(top.position.x).is_equal_approx(float(ProgressScreen.MARGIN), 0.5)
	assert_float(top.end.x).is_equal_approx(640.0 - ProgressScreen.MARGIN, 0.5)


func test_side_control_sits_left_of_the_column() -> void:
	var side := ColorRect.new()
	side.custom_minimum_size = Vector2(100, 200)
	var s := _screen(side)
	await _settle()
	assert_object(s.side_control()).is_same(side)
	var rect := side.get_global_rect()
	var top := s.info_panel().get_global_rect()
	assert_float(rect.position.x).is_equal_approx(float(ProgressScreen.MARGIN), 0.5)
	assert_float(rect.position.y).is_equal_approx(float(ProgressScreen.MARGIN), 0.5)
	assert_float(rect.end.x).is_less_equal(top.position.x + 0.5)
	assert_float(top.end.x).is_equal_approx(640.0 - ProgressScreen.MARGIN, 0.5)
	assert_array(Array(ScreenFit.problems(s))).is_empty()
