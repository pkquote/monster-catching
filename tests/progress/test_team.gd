extends GdUnitTestSuite
## Party / storage box rules.

var db: Database


func before() -> void:
	db = DataLoader.load_database("res://data").db


func _mon(hp: int = -1) -> CreatureInstance:
	var c := CreatureInstance.create(db, "tidepup", 5)
	if hp >= 0:
		c.hp = hp
	return c


func _save(party: Array, box: Array = []) -> SaveGame:
	var s := SaveGame.new()
	s.party = party
	for c in box:
		BoxStorage.add(s, c)
	return s


func test_reorder_moves_lead() -> void:
	var a := _mon()
	var b := _mon()
	var c := _mon()
	var s := _save([a, b, c])
	assert_str(Team.reorder(s, 2, 0)).is_equal("")
	assert_array(s.party).is_equal([c, a, b])
	assert_str(Team.reorder(s, 0, 1)).is_equal("")
	assert_array(s.party).is_equal([a, c, b])


func test_deposit_refuses_last_healthy() -> void:
	var healthy := _mon()
	var fainted := _mon(0)
	var s := _save([healthy, fainted])
	assert_str(Team.deposit(db, s, 0)).is_equal("last_healthy")
	assert_array(s.party).has_size(2)
	assert_str(Team.deposit(db, s, 1)).is_equal("")
	assert_array(s.party).is_equal([healthy])
	assert_array(BoxStorage.all_creatures(s)).is_equal([fainted])


func test_withdraw_refuses_full_party() -> void:
	var party: Array = []
	for i in db.balance.party_size:
		party.append(_mon())
	var boxed := _mon()
	var s := _save(party, [boxed])
	assert_str(Team.withdraw(db, s, 0)).is_equal("party_full")
	assert_int(BoxStorage.count(s)).is_equal(1)
	s.party.pop_back()
	assert_str(Team.withdraw(db, s, 0)).is_equal("")
	assert_that(s.party.back()).is_same(boxed)
	assert_int(BoxStorage.count(s)).is_equal(0)


func test_swap_healthy_rule() -> void:
	var healthy := _mon()
	var fainted := _mon(0)
	var other_healthy := _mon()
	var s := _save([healthy, fainted], [_mon(0), other_healthy])
	var box_fainted: CreatureInstance = s.storage[0]
	assert_str(Team.swap(db, s, 0, 0)).is_equal("last_healthy")
	assert_that(s.party[0]).is_same(healthy)
	assert_str(Team.swap(db, s, 0, 1)).is_equal("")
	assert_that(s.party[0]).is_same(other_healthy)
	assert_that(s.storage[1]).is_same(healthy)
	assert_that(s.storage[0]).is_same(box_fainted)


func test_bad_indices() -> void:
	var s := _save([_mon()], [_mon()])
	assert_str(Team.reorder(s, -1, 0)).is_equal("bad_index")
	assert_str(Team.reorder(s, 0, 1)).is_equal("bad_index")
	assert_str(Team.reorder(s, 1, 0)).is_equal("bad_index")
	assert_str(Team.deposit(db, s, 1)).is_equal("bad_index")
	assert_str(Team.deposit(db, s, -1)).is_equal("bad_index")
	assert_str(Team.withdraw(db, s, 1)).is_equal("bad_index")
	assert_str(Team.swap(db, s, 1, 0)).is_equal("bad_index")
	assert_str(Team.swap(db, s, 0, 1)).is_equal("bad_index")


func test_box_keeps_arrival_order() -> void:
	var a := _mon()
	var b := _mon()
	var c := _mon()
	var s := _save([a, b, c])
	Team.deposit(db, s, 1)
	Team.deposit(db, s, 1)
	assert_array(BoxStorage.all_creatures(s)).is_equal([b, c])
	Team.withdraw(db, s, 0)
	assert_array(BoxStorage.all_creatures(s)).is_equal([c])
	assert_that(s.party.back()).is_same(b)


# --- move / move_group (slot model) ---

func _full_party() -> Array:
	var party: Array = []
	for i in db.balance.party_size:
		party.append(_mon())
	return party


func _total(s: SaveGame) -> int:
	return s.party.size() + BoxStorage.count(s)


func test_move_party_to_an_empty_box_slot() -> void:
	var a := _mon()
	var b := _mon()
	var s := _save([a, b])
	assert_str(Team.move(db, s, {"party": 0}, {"box": 7})).is_equal("")
	assert_that(s.storage[7]).is_same(a)
	assert_array(s.party).is_equal([b])


func test_move_box_to_the_party_end() -> void:
	var a := _mon()
	var boxed := _mon()
	var s := _save([a])
	s.storage[12] = boxed
	assert_str(Team.move(db, s, {"box": 12}, {"party": 1})).is_equal("")
	assert_array(s.party).is_equal([a, boxed])
	assert_object(s.storage[12]).is_null()


func test_move_box_to_box_empty_and_occupied() -> void:
	var a := _mon()
	var b := _mon()
	var s := _save([_mon()])
	s.storage[0] = a
	s.storage[1] = b
	assert_str(Team.move(db, s, {"box": 0}, {"box": 40})).is_equal("")
	assert_that(s.storage[40]).is_same(a)
	assert_object(s.storage[0]).is_null()
	assert_str(Team.move(db, s, {"box": 40}, {"box": 1})).is_equal("")
	assert_that(s.storage[1]).is_same(a)
	assert_that(s.storage[40]).is_same(b)


func test_move_party_onto_an_occupied_box_slot_swaps() -> void:
	var p := _mon()
	var q := _mon()
	var boxed := _mon()
	var s := _save([p, q])
	s.storage[3] = boxed
	assert_str(Team.move(db, s, {"party": 1}, {"box": 3})).is_equal("")
	assert_that(s.party[1]).is_same(boxed)
	assert_that(s.storage[3]).is_same(q)


func test_move_party_reorder() -> void:
	var a := _mon()
	var b := _mon()
	var c := _mon()
	var s := _save([a, b, c])
	assert_str(Team.move(db, s, {"party": 0}, {"party": 2})).is_equal("")
	assert_array(s.party).is_equal([b, c, a])


func test_move_last_healthy_rules() -> void:
	var healthy := _mon()
	var fainted := _mon(0)
	var s := _save([healthy, fainted])
	assert_str(Team.move(db, s, {"party": 0}, {"box": 0})).is_equal("last_healthy")
	assert_array(s.party).has_size(2)
	var other := _mon()
	s.storage[1] = other
	assert_str(Team.move(db, s, {"party": 0}, {"box": 1})).is_equal("")  # a healthy one swaps in
	assert_that(s.party[0]).is_same(other)


func test_move_party_full_bad_index_and_same_slot() -> void:
	var s := _save(_full_party())
	s.storage[0] = _mon()
	assert_str(Team.move(db, s, {"box": 0}, {"party": s.party.size()})).is_equal("party_full")
	assert_str(Team.move(db, s, {"box": 5}, {"party": 0})).is_equal("bad_index")  # empty source
	assert_str(Team.move(db, s, {"party": 99}, {"box": 0})).is_equal("bad_index")
	assert_str(Team.move(db, s, {"box": 0}, {"box": 9999})).is_equal("bad_index")
	assert_str(Team.move(db, s, {"party": 0}, {"party": 99})).is_equal("bad_index")
	assert_str(Team.move(db, s, {"box": 0}, {"box": 0})).is_equal("same_slot")
	assert_str(Team.move(db, s, {"party": 2}, {"party": 2})).is_equal("same_slot")
	assert_int(_total(s)).is_equal(db.balance.party_size + 1)


func test_move_box_to_a_party_slot_swaps_when_occupied() -> void:
	var p := _mon()
	var boxed := _mon()
	var s := _save([p, _mon()])
	s.storage[0] = boxed
	assert_str(Team.move(db, s, {"box": 0}, {"party": 0})).is_equal("")
	assert_that(s.party[0]).is_same(boxed)
	assert_that(s.storage[0]).is_same(p)


func test_move_group_fills_in_reading_order_skipping_occupied() -> void:
	var s := _save([_mon(), _mon(), _mon()])
	var g := [s.party[1], s.party[2]]
	s.storage[10] = _mon()
	s.storage[11] = _mon()
	var r := Team.move_group(db, s, [{"party": 1}, {"party": 2}], {"box": 10})
	assert_str(r.reason).is_equal("")
	assert_int(r.moved).is_equal(2)
	assert_that(s.storage[12]).is_same(g[0])
	assert_that(s.storage[13]).is_same(g[1])
	assert_int(s.party.size()).is_equal(1)


func test_move_group_crosses_a_box_boundary_and_never_swaps() -> void:
	var s := _save([_mon(), _mon(), _mon(), _mon()])
	var first: CreatureInstance = s.party[1]
	var second: CreatureInstance = s.party[2]
	var third: CreatureInstance = s.party[3]
	for i in range(28, 31):
		s.storage[i] = _mon()
	var r := Team.move_group(db, s, [{"party": 1}, {"party": 2}, {"party": 3}], {"box": 28})
	assert_str(r.reason).is_equal("")
	assert_that(s.storage[31]).is_same(first)
	assert_that(s.storage[32]).is_same(second)
	assert_that(s.storage[33]).is_same(third)
	assert_int(BoxStorage.count(s)).is_equal(6)


func test_move_group_within_the_box() -> void:
	var s := _save([_mon()])
	var a := _mon()
	var b := _mon()
	s.storage[0] = a
	s.storage[1] = b
	var r := Team.move_group(db, s, [{"box": 0}, {"box": 1}], {"box": 5})
	assert_str(r.reason).is_equal("")
	assert_that(s.storage[5]).is_same(a)
	assert_that(s.storage[6]).is_same(b)
	assert_object(s.storage[0]).is_null()
	assert_object(s.storage[1]).is_null()


func test_move_group_no_room_moves_nothing_and_reports_the_shortfall() -> void:
	var s := _save([_mon(), _mon(), _mon()])
	for i in range(0, BoxStorage.slot_count(s) - 1):
		s.storage[i] = _mon()
	var r := Team.move_group(db, s, [{"party": 1}, {"party": 2}], {"box": 0})
	assert_str(r.reason).is_equal("no_room")
	assert_int(r.short).is_equal(1)
	assert_int(r.moved).is_equal(0)
	assert_int(s.party.size()).is_equal(3)


func test_move_group_into_the_party_is_limited_by_room() -> void:
	var party := _full_party()
	party.pop_back()
	party.pop_back()  # two free places
	var s := _save(party)
	s.storage[0] = _mon()
	s.storage[1] = _mon()
	s.storage[2] = _mon()
	var tooMany := Team.move_group(db, s, [{"box": 0}, {"box": 1}, {"box": 2}], {"party": 0})
	assert_str(tooMany.reason).is_equal("no_room")
	assert_int(tooMany.short).is_equal(1)
	assert_int(BoxStorage.count(s)).is_equal(3)
	var ok := Team.move_group(db, s, [{"box": 0}, {"box": 1}], {"party": 0})
	assert_str(ok.reason).is_equal("")
	assert_int(s.party.size()).is_equal(db.balance.party_size)


func test_move_group_last_healthy_and_bad_index() -> void:
	var s := _save([_mon(), _mon(0)])
	var r := Team.move_group(db, s, [{"party": 0}, {"party": 1}], {"box": 0})
	assert_str(r.reason).is_equal("last_healthy")
	assert_int(s.party.size()).is_equal(2)
	var bad := Team.move_group(db, s, [{"party": 1}, {"box": 3}], {"box": 0})
	assert_str(bad.reason).is_equal("bad_index")
	assert_int(_total(s)).is_equal(2)
	# A healthy creature in the group alongside a healthy one staying is fine.
	var s2 := _save([_mon(), _mon(), _mon()])
	assert_str(Team.move_group(db, s2, [{"party": 1}, {"party": 2}], {"box": 0}).reason).is_equal("")


func test_deposit_goes_to_the_first_empty_slot_and_a_full_box_refuses() -> void:
	var s := _save([_mon(), _mon()])
	s.storage[0] = _mon()
	assert_str(Team.deposit(db, s, 1)).is_equal("")
	assert_object(s.storage[1]).is_not_null()
	for i in s.storage.size():
		if s.storage[i] == null:
			s.storage[i] = _mon()
	s.party.append(_mon())
	assert_str(Team.deposit(db, s, 1)).is_equal("box_full")


func test_room_left_counts_party_room_and_empty_slots() -> void:
	var s := _save(_full_party())
	assert_int(BattleLauncher.room_left(db, s)).is_equal(240)
	for i in 100:
		s.storage[i] = _mon()
	assert_int(BattleLauncher.room_left(db, s)).is_equal(140)
	s.party.pop_back()
	assert_int(BattleLauncher.room_left(db, s)).is_equal(141)
