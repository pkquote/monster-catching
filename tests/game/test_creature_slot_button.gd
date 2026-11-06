extends GdUnitTestSuite
## The focusable creature slot used by the Box and Party screens.

var db: Database


func before() -> void:
	db = DataRegistry.db


func _button(c: CreatureInstance = null, size := 36) -> CreatureSlotButton:
	var b: CreatureSlotButton = auto_free(CreatureSlotButton.new())
	b.configure(db, c, size)
	return b


func test_an_empty_slot_has_no_creature_and_no_sprite() -> void:
	var b := _button(null)
	assert_object(b.creature()).is_null()
	assert_bool(_has_sprite(b)).is_false()
	assert_str(b.badge_text()).is_empty()


func test_a_creature_slot_embeds_a_sprite_slot() -> void:
	var c := CreatureInstance.create(db, "tidepup", 5)
	var b := _button(c)
	assert_that(b.creature()).is_same(c)
	assert_bool(_has_sprite(b)).is_true()


func _has_sprite(b: Node) -> bool:
	for child in b.get_children():
		if child is CreatureSpriteSlot:
			return true
	return false


func test_marked_and_carried_toggle() -> void:
	var b := _button(CreatureInstance.create(db, "tidepup", 5))
	assert_bool(b.is_marked()).is_false()
	b.set_marked(true)
	assert_bool(b.is_marked()).is_true()
	b.set_marked(false)
	assert_bool(b.is_marked()).is_false()
	b.set_carried(true)
	assert_bool(b.is_carried()).is_true()
	b.set_carried(false)
	assert_bool(b.is_carried()).is_false()


func test_badge_text_for_none_status_and_fainted() -> void:
	var c := CreatureInstance.create(db, "tidepup", 5)
	var b := _button(c)
	assert_str(b.badge_text()).is_empty()
	var burn := db.ids("statuses")[0] as String
	c.status = burn
	b.configure(db, c)
	assert_str(b.badge_text()).is_equal(db.status(burn).name.substr(0, 1).to_upper())
	c.hp = 0
	b.configure(db, c)
	assert_str(b.badge_text()).is_equal("F")


func test_count_badge_is_hidden_below_two() -> void:
	var b := _button(CreatureInstance.create(db, "tidepup", 5))
	b.set_count_badge(1)
	assert_str(b.count_text()).is_empty()
	b.set_count_badge(3)
	assert_str(b.count_text()).is_equal("x3")
	b.set_count_badge(0)
	assert_str(b.count_text()).is_empty()


func test_minimum_size_follows_the_requested_size() -> void:
	assert_vector(_button(null, 36).custom_minimum_size).is_equal(Vector2(36, 36))
	assert_vector(_button(null, 28).custom_minimum_size).is_equal(Vector2(28, 28))


func test_a_long_named_creature_draws_without_error() -> void:
	var c := CreatureInstance.create(db, "tidepup", 5)
	c.nickname = "An extremely long nickname that goes on and on"
	var b := _button(c)
	add_child(b)
	await get_tree().process_frame
	b.set_marked(true)
	b.set_carried(true)
	b.set_count_badge(12)
	await get_tree().process_frame
	remove_child(b)
	assert_vector(b.custom_minimum_size).is_equal(Vector2(36, 36))


func test_focus_emits_focus_entered() -> void:
	var b := _button(CreatureInstance.create(db, "tidepup", 5))
	add_child(b)
	var hits := [0]
	b.focus_entered.connect(func(): hits[0] += 1)
	b.grab_focus()
	await get_tree().process_frame
	remove_child(b)
	assert_int(hits[0]).is_equal(1)
