extends GdUnitTestSuite
## Slot-addressed box storage.

var db: Database


func before() -> void:
	db = FixtureDB.build()


func _mon() -> CreatureInstance:
	return FixtureDB.make(db, "blob", 5)


func _fill(s: SaveGame) -> void:
	for i in s.storage.size():
		s.storage[i] = _mon()


func test_a_fresh_save_has_eight_empty_boxes() -> void:
	var s := SaveGame.new()
	assert_int(s.boxes_unlocked).is_equal(8)
	assert_int(BoxStorage.slot_count(s)).is_equal(240)
	assert_int(BoxStorage.box_count(s)).is_equal(8)
	assert_int(BoxStorage.count(s)).is_equal(0)
	assert_int(BoxStorage.empty_count(s)).is_equal(240)
	assert_object(s.storage[0]).is_null()


func test_slot_arithmetic_round_trips() -> void:
	for slot in [0, 29, 30, 239]:
		var b := BoxStorage.box_of(slot)
		var i := BoxStorage.index_in_box(slot)
		assert_int(BoxStorage.slot_of(b, i)).is_equal(slot)
	assert_int(BoxStorage.box_of(29)).is_equal(0)
	assert_int(BoxStorage.box_of(30)).is_equal(1)
	assert_int(BoxStorage.index_in_box(31)).is_equal(1)


func test_creature_at_is_null_for_empty_and_out_of_range() -> void:
	var s := SaveGame.new()
	var c := _mon()
	s.storage[3] = c
	assert_that(BoxStorage.creature_at(s, 3)).is_same(c)
	assert_object(BoxStorage.creature_at(s, 4)).is_null()
	assert_object(BoxStorage.creature_at(s, -1)).is_null()
	assert_object(BoxStorage.creature_at(s, 240)).is_null()


func test_first_empty_with_and_without_a_start() -> void:
	var s := SaveGame.new()
	s.storage[0] = _mon()
	s.storage[1] = _mon()
	assert_int(BoxStorage.first_empty(s)).is_equal(2)
	assert_int(BoxStorage.first_empty(s, 5)).is_equal(5)
	s.storage[5] = _mon()
	assert_int(BoxStorage.first_empty(s, 5)).is_equal(6)
	_fill(s)
	assert_int(BoxStorage.first_empty(s)).is_equal(-1)
	s.storage[10] = null
	assert_int(BoxStorage.first_empty(s, 11)).is_equal(-1)  # no wrap


func test_count_empty_count_and_order() -> void:
	var s := SaveGame.new()
	var a := _mon()
	var b := _mon()
	s.storage[40] = a
	s.storage[7] = b
	assert_int(BoxStorage.count(s)).is_equal(2)
	assert_int(BoxStorage.empty_count(s)).is_equal(238)
	assert_array(BoxStorage.all_creatures(s)).is_equal([b, a])


func test_add_fills_the_first_hole_and_fails_when_full() -> void:
	var s := SaveGame.new()
	s.storage[0] = _mon()
	s.storage[2] = _mon()
	var c := _mon()
	assert_bool(BoxStorage.add(s, c)).is_true()
	assert_that(s.storage[1]).is_same(c)
	_fill(s)
	assert_bool(BoxStorage.add(s, _mon())).is_false()


func test_unlock_box_adds_thirty_slots_and_stops_at_the_ceiling() -> void:
	var s := SaveGame.new()
	assert_bool(BoxStorage.unlock_box(s)).is_true()
	assert_int(s.boxes_unlocked).is_equal(9)
	assert_int(s.storage.size()).is_equal(270)
	assert_object(s.storage[269]).is_null()
	while BoxStorage.unlock_box(s):
		pass
	assert_int(s.boxes_unlocked).is_equal(BoxStorage.MAX_BOXES)
	assert_int(s.storage.size()).is_equal(BoxStorage.MAX_BOXES * BoxStorage.BOX_SIZE)


func test_ensure_boxes_only_grows() -> void:
	var s := SaveGame.new()
	BoxStorage.ensure_boxes(s, 10)
	assert_int(s.boxes_unlocked).is_equal(10)
	BoxStorage.ensure_boxes(s, 4)
	assert_int(s.boxes_unlocked).is_equal(10)
	BoxStorage.ensure_boxes(s, 999)
	assert_int(s.boxes_unlocked).is_equal(BoxStorage.MAX_BOXES)
