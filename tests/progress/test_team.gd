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
	s.storage = box
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
	assert_array(s.storage).is_equal([fainted])


func test_withdraw_refuses_full_party() -> void:
	var party: Array = []
	for i in db.balance.party_size:
		party.append(_mon())
	var boxed := _mon()
	var s := _save(party, [boxed])
	assert_str(Team.withdraw(db, s, 0)).is_equal("party_full")
	assert_array(s.storage).has_size(1)
	s.party.pop_back()
	assert_str(Team.withdraw(db, s, 0)).is_equal("")
	assert_that(s.party.back()).is_same(boxed)
	assert_array(s.storage).is_empty()


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
	assert_array(s.storage).is_equal([b, c])
	Team.withdraw(db, s, 0)
	assert_array(s.storage).is_equal([c])
	assert_that(s.party.back()).is_same(b)
