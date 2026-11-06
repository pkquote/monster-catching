extends GdUnitTestSuite
## The box screen: the party column, the box grid, the hover card, box switching and (below) picking up,
## placing and marking creatures.

const VIEW := Rect2(0, 0, 640, 360)

var world: Overworld
var db: Database
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("storage_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	db = DataRegistry.db
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	WorldTest.close(world)


func _screen() -> StorageScreen:
	return WorldTest.find_screen(world, StorageScreen) as StorageScreen


func _mon(name := "", species := "tidepup", level := 5) -> CreatureInstance:
	var c := CreatureInstance.create(db, species, level)
	c.nickname = name
	return c


## A scratch save: `party_n` party members named P1.., and box creatures given as {slot: name}.
func _save(party_n: int, box: Dictionary = {}) -> SaveGame:
	var s := SaveGame.new_game("Bo", 0, RandomNumberGenerator.new())
	for i in party_n:
		s.party.append(_mon("P%d" % (i + 1)))
	for slot in box:
		s.storage[slot] = _mon(box[slot])
	return s


func _open(save: SaveGame) -> StorageScreen:
	StorageScreen.run(world, save, db)
	await get_tree().process_frame
	await get_tree().process_frame
	return _screen()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _focus(b: Control) -> void:
	b.grab_focus()
	await get_tree().process_frame


# --- Layout and browsing ---------------------------------------------------------------

func test_the_party_column_shows_every_member_and_the_empty_slots() -> void:
	var s := await _open(_save(4))
	var buttons := s.party_buttons()
	assert_int(buttons.size()).is_equal(db.balance.party_size)
	var filled := buttons.filter(func(b: CreatureSlotButton): return b.creature() != null)
	assert_int(filled.size()).is_equal(4)
	s.close()


func test_a_party_of_twelve_gets_twelve_slots() -> void:
	var s := await _open(_save(12))
	assert_int(s.party_buttons().size()).is_equal(12)
	assert_bool(s.party_buttons().all(func(b: CreatureSlotButton): return b.creature() != null)).is_true()
	s.close()


func test_the_grid_shows_the_current_boxes_thirty_slots() -> void:
	var s := await _open(_save(1, {0: "A", 7: "B", 30: "C"}))
	var cells := s.box_buttons()
	assert_int(cells.size()).is_equal(30)
	assert_str(cells[0].creature().nickname).is_equal("A")
	assert_str(cells[7].creature().nickname).is_equal("B")
	assert_object(cells[1].creature()).is_null()
	assert_int(cells.filter(func(b: CreatureSlotButton): return b.creature() != null).size()).is_equal(2)
	s.step_box(1)
	await get_tree().process_frame
	assert_str(s.box_buttons()[0].creature().nickname).is_equal("C")
	s.close()


func test_box_switching_wraps_and_clamps_and_updates_the_header() -> void:
	var s := await _open(_save(1))
	assert_str(s.header_text()).is_equal("Box 1 / 8")
	s.step_box(1)
	assert_str(s.header_text()).is_equal("Box 2 / 8")
	s.step_box(-2)
	assert_str(s.header_text()).is_equal("Box 8 / 8")
	s.step_box(1)
	assert_int(s.box).is_equal(0)
	s.show_box(99)
	assert_int(s.box).is_equal(7)
	s.show_box(-4)
	assert_int(s.box).is_equal(0)
	s.show_box(2)
	assert_str(s.header_text()).is_equal("Box 3 / 8")
	s.close()


func test_focusing_a_slot_shows_that_creature_on_the_card() -> void:
	var s := await _open(_save(3, {2: "Boxed"}))
	await _focus(s.party_buttons()[1])
	assert_str(s.card().header_text()).contains("P2")
	await _focus(s.box_buttons()[2])
	assert_str(s.card().header_text()).contains("Boxed")
	await _focus(s.box_buttons()[3])
	assert_str(s.card().header_text()).is_equal("Empty")
	await _focus(s.party_buttons()[5])
	assert_str(s.card().header_text()).is_equal("Empty")
	s.close()


func test_focus_reaches_every_slot_with_the_arrows() -> void:
	var s := await _open(_save(6, {0: "A"}))
	var seen := {}
	var queue: Array = [s.party_buttons()[0]]
	while not queue.is_empty():
		var c: Control = queue.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			var n := c.find_valid_focus_neighbor(side)
			if n != null:
				queue.append(n)
	for b in s.party_buttons() + s.box_buttons():
		assert_bool(seen.has(b)).override_failure_message("unreachable slot").is_true()
	# From the party column the right arrow gets into the grid, and the grid leads back.
	var right_party: Control = s.party_buttons()[5]
	assert_bool(s.box_buttons().has(right_party.find_valid_focus_neighbor(SIDE_RIGHT))).is_true()
	var left_cell: Control = s.box_buttons()[0]
	assert_bool(s.party_buttons().has(left_cell.find_valid_focus_neighbor(SIDE_LEFT))).is_true()
	s.close()


func test_the_shoulder_actions_switch_box() -> void:
	var s := await _open(_save(1))
	await _press("next_creature")
	assert_int(s.box).is_equal(1)
	await _press("prev_creature")
	await _press("prev_creature")
	assert_int(s.box).is_equal(7)
	s.close()


func test_cancel_closes_the_screen() -> void:
	var s := await _open(_save(1))
	await _press("ui_cancel")
	await get_tree().process_frame
	assert_object(_screen()).is_null()


func test_focused_location_names_party_and_box_slots() -> void:
	var s := await _open(_save(3))
	await _focus(s.party_buttons()[2])
	assert_dict(s.focused_location()).is_equal({"party": 2})
	s.show_box(1)
	await _focus(s.box_buttons()[4])
	assert_dict(s.focused_location()).is_equal({"box": 34})
	s.close()


func _rects_fit(s: StorageScreen) -> void:
	for b: Control in s.party_buttons() + s.box_buttons():
		assert_bool(VIEW.encloses(b.get_global_rect().grow(-0.5))).override_failure_message(
			"slot %s off screen" % b.get_global_rect()).is_true()
	assert_bool(VIEW.encloses(s.card().get_global_rect().grow(-0.5))).override_failure_message(
		"card %s off screen" % s.card().get_global_rect()).is_true()


func test_a_full_party_and_full_boxes_with_long_names_fit_the_screen() -> void:
	var save := _save(12)
	for i in save.party.size():
		save.party[i].nickname = "A very long nickname number %d that keeps going" % i
	for i in save.storage.size():
		save.storage[i] = _mon("Another extremely long box nickname %d" % i)
	var s := await _open(save)
	_rects_fit(s)
	await _focus(s.box_buttons()[12])
	_rects_fit(s)
	s.step_box(3)
	await get_tree().process_frame
	await _focus(s.box_buttons()[29])
	_rects_fit(s)
	s.close()


# --- Where the screen is reached from ----------------------------------------------------

func _place_box(tile: Vector2i) -> StorageBox:
	var box: StorageBox = load("res://game/overworld/pieces/storage_box.tscn").instantiate()
	world.map.entities().add_child(box)
	box.position = GameMap.centre_of(tile)
	return box


func test_storage_box_works_in_unsafe_zone() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	_place_box(Vector2i(2, 2))
	world.player.place(GameMap.centre_of(Vector2i(2, 3)), Vector2i.UP)
	assert_bool(world.is_safe_here()).is_false()
	world.interact()
	await get_tree().process_frame
	assert_object(_screen()).is_not_null()
	assert_bool(world.is_locked()).is_true()


func test_screens_work_on_the_save_they_are_given() -> void:
	var other := _save(2)
	var global_before := BoxStorage.count(GameState.current)
	var s := await _open(other)
	await _focus(s.party_buttons()[1])
	assert_str(s.card().header_text()).contains("P2")
	s.close()
	assert_int(BoxStorage.count(GameState.current)).is_equal(global_before)


# --- Picking up, placing and marking ----------------------------------------------------

func _total(save: SaveGame) -> int:
	return save.party.size() + BoxStorage.count(save)


func _at(s: StorageScreen, loc: Dictionary) -> void:
	if loc.has("party"):
		await _focus(s.party_buttons()[loc.party])
	else:
		s.show_box(BoxStorage.box_of(loc.box))
		await _focus(s.box_buttons()[BoxStorage.index_in_box(loc.box)])


func test_pick_up_and_place_on_an_empty_box_slot() -> void:
	var save := _save(2)
	var s := await _open(save)
	var a: CreatureInstance = save.party[1]
	await _at(s, {"party": 1})
	s.accept()
	assert_array(s.held()).is_equal([{"party": 1}])
	assert_bool(s.party_buttons()[1].is_carried()).is_true()
	assert_str(s.help_text()).contains("Back: put down")
	await _at(s, {"box": 4})
	s.accept()
	assert_that(save.storage[4]).is_same(a)
	assert_int(save.party.size()).is_equal(1)
	assert_array(s.held()).is_empty()
	assert_that(s.box_buttons()[4].creature()).is_same(a)
	assert_int(_total(save)).is_equal(2)
	s.close()


func test_placing_on_an_occupied_slot_swaps() -> void:
	var save := _save(2, {3: "Boxed"})
	var s := await _open(save)
	var p: CreatureInstance = save.party[1]
	var boxed: CreatureInstance = save.storage[3]
	await _at(s, {"party": 1})
	s.accept()
	await _at(s, {"box": 3})
	s.accept()
	assert_that(save.party[1]).is_same(boxed)
	assert_that(save.storage[3]).is_same(p)
	s.close()


func test_box_to_party_appends_at_the_first_empty_party_slot() -> void:
	var save := _save(2, {9: "Boxed"})
	var s := await _open(save)
	var boxed: CreatureInstance = save.storage[9]
	await _at(s, {"box": 9})
	s.accept()
	await _at(s, {"party": 4})  # an empty party slot further down: still the next free place
	s.accept()
	assert_array(save.party).has_size(3)
	assert_that(save.party[2]).is_same(boxed)
	assert_object(save.storage[9]).is_null()
	s.close()


func test_a_refusal_keeps_the_creature_held_and_says_why() -> void:
	var save := _save(1, {0: "Boxed"})
	var s := await _open(save)
	await _at(s, {"party": 0})
	s.accept()
	await _at(s, {"box": 20})
	s.accept()
	assert_str(s.help_text()).is_equal("Keep at least one creature that can fight.")
	assert_array(s.held()).is_equal([{"party": 0}])
	assert_int(save.party.size()).is_equal(1)
	s.cancel()
	assert_array(s.held()).is_empty()
	s.close()


func test_refusal_texts() -> void:
	assert_str(StorageScreen.refusal_text("party_full")).is_equal("Your party is full.")
	assert_str(StorageScreen.refusal_text("no_room", 2)).is_equal("Need 2 more free slots.")
	assert_str(StorageScreen.refusal_text("no_room", 1)).is_equal("Need 1 more free slot.")


func test_cancel_puts_it_down_and_then_closes() -> void:
	var save := _save(2)
	var s := await _open(save)
	await _at(s, {"party": 1})
	s.accept()
	s.cancel()
	assert_array(s.held()).is_empty()
	assert_bool(s.party_buttons()[1].is_carried()).is_false()
	assert_object(_screen()).is_not_null()
	s.cancel()
	await get_tree().process_frame
	assert_object(_screen()).is_null()


func test_accept_on_an_empty_slot_with_nothing_held_does_nothing() -> void:
	var save := _save(2)
	var s := await _open(save)
	await _at(s, {"box": 5})
	s.accept()
	assert_array(s.held()).is_empty()
	await _at(s, {"party": 5})
	s.accept()
	assert_array(s.held()).is_empty()
	assert_int(_total(save)).is_equal(2)
	s.close()


func test_marks_toggle_and_ignore_empty_slots() -> void:
	var s := await _open(_save(3, {2: "B"}))
	await _at(s, {"party": 0})
	s.mark()
	assert_array(s.marks()).is_equal([{"party": 0}])
	assert_bool(s.party_buttons()[0].is_marked()).is_true()
	s.mark()
	assert_array(s.marks()).is_empty()
	assert_bool(s.party_buttons()[0].is_marked()).is_false()
	await _at(s, {"box": 7})
	s.mark()
	assert_array(s.marks()).is_empty()
	s.close()


func test_marking_in_another_container_clears_the_old_marks() -> void:
	var s := await _open(_save(3, {2: "B", 40: "C"}))
	await _at(s, {"party": 0})
	s.mark()
	await _at(s, {"party": 1})
	s.mark()
	assert_array(s.marks()).has_size(2)
	await _at(s, {"box": 2})
	s.mark()
	assert_array(s.marks()).is_equal([{"box": 2}])
	await _at(s, {"box": 40})  # another box counts as another container
	s.mark()
	assert_array(s.marks()).is_equal([{"box": 40}])
	s.close()


func test_a_marked_group_is_picked_up_with_a_count_badge() -> void:
	var save := _save(4)
	var s := await _open(save)
	await _at(s, {"party": 1})
	s.mark()
	await _at(s, {"party": 3})
	s.mark()
	await _at(s, {"party": 0})
	s.accept()
	assert_array(s.held()).is_equal([{"party": 1}, {"party": 3}])
	assert_str(s.party_buttons()[0].count_text()).is_equal("x2")
	assert_bool(s.party_buttons()[1].is_carried()).is_true()
	s.close()


func test_a_group_from_the_party_goes_into_the_box_in_reading_order() -> void:
	var save := _save(4, {10: "X", 11: "Y"})
	var s := await _open(save)
	var p1: CreatureInstance = save.party[1]
	var p2: CreatureInstance = save.party[2]
	await _at(s, {"party": 1})
	s.mark()
	await _at(s, {"party": 2})
	s.mark()
	s.accept()
	await _at(s, {"box": 10})
	s.accept()
	assert_that(save.storage[12]).is_same(p1)
	assert_that(save.storage[13]).is_same(p2)
	assert_array(save.party).has_size(2)
	assert_array(s.held()).is_empty()
	assert_array(s.marks()).is_empty()
	assert_int(_total(save)).is_equal(6)
	s.close()


func test_a_group_is_carried_to_another_box() -> void:
	var save := _save(1, {0: "A", 1: "B", 2: "C"})
	var s := await _open(save)
	var a: CreatureInstance = save.storage[0]
	var b: CreatureInstance = save.storage[1]
	await _at(s, {"box": 0})
	s.mark()
	await _at(s, {"box": 1})
	s.mark()
	s.accept()
	s.step_box(2)
	await _focus(s.box_buttons()[6])
	s.accept()
	assert_that(save.storage[66]).is_same(a)
	assert_that(save.storage[67]).is_same(b)
	assert_object(save.storage[0]).is_null()
	assert_that(save.storage[2]).is_not_null()
	s.close()


func test_a_group_with_too_little_room_says_how_many_more_and_moves_nothing() -> void:
	var save := _save(3)
	for i in range(0, save.storage.size() - 1):
		save.storage[i] = _mon("F%d" % i)
	var s := await _open(save)
	await _at(s, {"party": 1})
	s.mark()
	await _at(s, {"party": 2})
	s.mark()
	s.accept()
	await _at(s, {"box": 0})
	s.accept()
	assert_str(s.help_text()).is_equal("Need 1 more free slot.")
	assert_array(s.held()).has_size(2)
	assert_int(save.party.size()).is_equal(3)
	s.close()


func test_a_group_into_the_party_is_limited_by_room() -> void:
	var save := _save(db.balance.party_size - 1, {0: "A", 1: "B"})
	var s := await _open(save)
	await _at(s, {"box": 0})
	s.mark()
	await _at(s, {"box": 1})
	s.mark()
	s.accept()
	await _at(s, {"party": save.party.size()})
	s.accept()
	assert_str(s.help_text()).is_equal("Need 1 more free slot.")
	assert_int(save.party.size()).is_equal(db.balance.party_size - 1)
	assert_int(BoxStorage.count(save)).is_equal(2)
	s.close()


func test_a_group_that_would_leave_no_healthy_creature_is_refused() -> void:
	var save := _save(2)
	save.party[1].hp = 0
	var s := await _open(save)
	await _at(s, {"party": 0})
	s.mark()
	await _at(s, {"party": 1})
	s.mark()
	s.accept()
	await _at(s, {"box": 3})
	s.accept()
	assert_str(s.help_text()).is_equal("Keep at least one creature that can fight.")
	assert_int(save.party.size()).is_equal(2)
	s.close()


func test_closing_while_holding_loses_and_duplicates_nothing() -> void:
	var save := _save(3, {5: "B"})
	var s := await _open(save)
	var before := _total(save)
	await _at(s, {"party": 2})
	s.accept()
	s.step_box(1)
	s.close()
	assert_int(_total(save)).is_equal(before)
	assert_int(save.party.size()).is_equal(3)
	assert_that(BoxStorage.creature_at(save, 5)).is_not_null()


func test_the_accept_and_mark_inputs_reach_the_same_behaviour() -> void:
	var save := _save(2)
	var s := await _open(save)
	await _at(s, {"party": 1})
	await _press("mark")
	assert_array(s.marks()).is_equal([{"party": 1}])
	await _press("ui_accept")
	assert_array(s.held()).is_equal([{"party": 1}])
	await _press("ui_cancel")
	assert_array(s.held()).is_empty()
	s.close()


func test_every_operation_keeps_the_total() -> void:
	var save := _save(3, {1: "A", 2: "B"})
	var s := await _open(save)
	var total := _total(save)
	await _at(s, {"box": 1})
	s.accept()
	await _at(s, {"box": 2})
	s.accept()  # swap
	assert_int(_total(save)).is_equal(total)
	await _at(s, {"party": 0})
	s.accept()
	await _at(s, {"box": 20})
	s.accept()
	assert_int(_total(save)).is_equal(total)
	s.close()
