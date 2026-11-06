extends GdUnitTestSuite
## The battle's field-state chips carry a label under each chip with the state's effect.

const SCREEN := Rect2(0, 0, 640, 236)

var db: Database


func before() -> void:
	db = DataRegistry.db


func _view(side: int) -> FieldView:
	var f: FieldView = FieldView.new()
	f.setup(side, db)
	f.position = Vector2(8, 6)
	add_child(auto_free(f))
	return f


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _expected(state_id: String) -> String:
	return EffectText.short(db, db.field_state(state_id).passive)


func test_each_state_shows_its_own_effect() -> void:
	var f: FieldView = _view(1)
	f.applied("soaked", 1, 4)
	f.applied("scorched", 1, 3)
	f.applied("radiant", 1, 4)
	await _settle()
	assert_array(f.effect_labels()).is_equal([_expected("soaked"), _expected("scorched"), _expected("radiant")])
	for text: String in f.effect_labels():
		assert_str(text).is_not_empty()
		assert_str(text).is_not_equal("—")


func test_label_text_is_generated_from_the_data() -> void:
	var f: FieldView = _view(1)
	f.applied("soaked", 1, 4)
	await _settle()
	assert_array(f.effect_labels()).is_equal(["Electric dmg taken x1.25; Fire dmg taken x0.75"])


func test_stacks_do_not_change_the_label() -> void:
	var f: FieldView = _view(1)
	f.applied("soaked", 1, 4)
	await _settle()
	var before_text: Array = f.effect_labels()
	f.applied("soaked", 3, 4)
	await _settle()
	assert_array(f.effect_labels()).is_equal(before_text)
	assert_int(f.effect_labels().size()).is_equal(1)


func test_labels_follow_remove_and_sync() -> void:
	var f: FieldView = _view(1)
	f.applied("soaked", 1, 4)
	f.applied("charged", 2, 3)
	await _settle()
	assert_int(f.effect_labels().size()).is_equal(2)
	f.removed("soaked")
	await _settle()
	assert_array(f.effect_labels()).is_equal([_expected("charged")])
	var field: Field = Field.new()
	field.add("frosted", 1, 4, 3)
	field.add("hazed", 1, 3, 3)
	f.sync(field)
	await _settle()
	assert_array(f.effect_labels()).is_equal([_expected("frosted"), _expected("hazed")])
	f.sync(Field.new())
	await _settle()
	assert_array(f.effect_labels()).is_empty()
	assert_int(f.get_child_count()).is_equal(0)


func test_tag_and_underdog_badge_are_unchanged() -> void:
	var foe: FieldView = _view(1)
	foe.applied("soaked", 1, 4)
	foe.set_underdog(1, 2.0)
	await _settle()
	assert_str(foe.underdog_text).is_equal("UNDERDOG +1")
	var texts: Array = []
	for l: Node in foe.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_array(texts).contains(["Foe field:", "UNDERDOG +1", "Soaked · 4"])
	var mine: FieldView = _view(0)
	mine.applied("soaked", 2, 3)
	await _settle()
	var mine_texts: Array = []
	for l: Node in mine.find_children("*", "Label", true, false):
		mine_texts.append((l as Label).text)
	assert_array(mine_texts).contains(["Your field:", "Soaked ×2 · 3"])


func test_nothing_is_shown_without_states() -> void:
	var f: FieldView = _view(1)
	await _settle()
	assert_int(f.get_child_count()).is_equal(0)
	assert_array(f.effect_labels()).is_empty()


func _chip_and_label(f: FieldView) -> Array:
	# The first state column: its chip (a PanelContainer) and its effect label.
	var chip: Control = null
	var label: Control = null
	for n: Node in f.find_children("*", "PanelContainer", true, false):
		var l: Label = n.get_child(0) as Label
		if l != null and l.text.begins_with("Soaked"):
			chip = n as Control
	for n: Node in f.find_children("*", "Label", true, false):
		if (n as Label).text == _expected("soaked"):
			label = n as Control
	return [chip, label]


func test_label_is_above_the_chip_for_you_and_below_for_the_foe() -> void:
	for side: int in [0, 1]:
		var f: FieldView = _view(side)
		f.applied("soaked", 1, 4)
		await _settle()
		var pair: Array = _chip_and_label(f)
		assert_object(pair[0]).is_not_null()
		assert_object(pair[1]).is_not_null()
		var chip: Rect2 = (pair[0] as Control).get_global_rect()
		var label: Rect2 = (pair[1] as Control).get_global_rect()
		if side == 0:
			assert_float(label.end.y).is_less_equal(chip.position.y + 0.5)
		else:
			assert_float(label.position.y).is_greater_equal(chip.end.y - 0.5)
		f.queue_free()


func test_badge_and_tag_are_not_stretched_to_the_tallest_column() -> void:
	var f: FieldView = _view(1)
	f.set_underdog(1, 2.0)
	f.applied("radiant", 1, 4)
	await _settle()
	for n: Node in f.get_children():
		if n is PanelContainer or n is Label:
			assert_float((n as Control).size.y).override_failure_message(
				"%s is %s tall: stretched" % [n, (n as Control).size.y]).is_less(24.0)


func test_your_view_sits_at_the_bottom_right_of_the_stage() -> void:
	var f: FieldView = FieldView.new()
	f.setup(0, db)
	add_child(auto_free(f))
	f.anchor_bottom_right(Vector2(632, 232))
	f.set_underdog(1, 2.0)
	f.applied("radiant", 1, 4)  # the longest effect text
	await _settle()
	var rect: Rect2 = f.get_global_rect()
	assert_bool(SCREEN.encloses(rect)).override_failure_message(
		"your field view %s is outside the stage %s" % [rect, SCREEN]).is_true()
	assert_float(rect.end.x).is_equal_approx(632.0, 1.0)
	assert_float(rect.end.y).is_equal_approx(232.0, 1.0)
	# It grows upwards and leftwards when a replacement state with a different size arrives.
	f.removed("radiant")
	f.applied("soaked", 1, 4)
	await _settle()
	rect = f.get_global_rect()
	assert_float(rect.end.x).is_equal_approx(632.0, 1.0)
	assert_float(rect.end.y).is_equal_approx(232.0, 1.0)


func test_foe_view_fits_the_top_left_corner() -> void:
	var f: FieldView = _view(1)
	f.set_underdog(1, 2.0)
	f.applied("radiant", 1, 4)
	await _settle()
	var rect: Rect2 = f.get_global_rect()
	assert_bool(SCREEN.encloses(rect)).is_true()
	assert_float(rect.end.y).override_failure_message("%s reaches the creatures" % rect).is_less_equal(100.0)
	assert_float(rect.end.x).is_less_equal(470.0)


func test_a_higher_cap_still_shows_every_state() -> void:
	var f: FieldView = _view(1)
	f.applied("soaked", 1, 4)
	f.applied("scorched", 1, 3)
	await _settle()
	assert_int(f.effect_labels().size()).is_equal(2)
