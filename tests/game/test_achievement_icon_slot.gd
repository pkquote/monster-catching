extends GdUnitTestSuite
## The placeholder achievement icon: a colour and a letter per criterion kind, greyed while locked.


func _slot(kind: String, unlocked := true) -> AchievementIconSlot:
	var s: AchievementIconSlot = auto_free(AchievementIconSlot.new())
	s.configure(kind, 48, unlocked)
	return s


func test_each_kind_has_its_own_colour_and_letter() -> void:
	var colours := []
	var letters := []
	for kind in Criteria.kinds():
		colours.append(_slot(kind).fill_color())
		letters.append(_slot(kind).letter())
	assert_int(colours.size()).is_equal(4)
	for i in colours.size():
		assert_int(colours.count(colours[i])).is_equal(1)
		assert_int(letters.count(letters[i])).is_equal(1)
		assert_str(letters[i]).is_not_equal("?")


func test_an_unknown_kind_is_a_question_mark() -> void:
	assert_str(_slot("unknown").letter()).is_equal("?")
	assert_str(_slot("nonsense").letter()).is_equal("?")


func test_a_locked_icon_is_greyed() -> void:
	assert_object(_slot("counter", false).fill_color()).is_not_equal(_slot("counter", true).fill_color())
	var grey := _slot("counter", false).fill_color()
	assert_float(grey.s).is_less(_slot("counter", true).fill_color().s)
