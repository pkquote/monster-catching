extends GdUnitTestSuite
## A swap is the swapping creature's whole turn: the command phase stops asking for its other slots.


func test_a_swap_skips_the_actors_remaining_slots() -> void:
	# Underdog lead (bid 1) has three slots, then the ally (bid 2) has one.
	var needed: Array[int] = [1, 1, 1, 2]
	assert_int(BattleAction.next_slot(needed, 0, BattleAction.swap(1, 9))).is_equal(3)
	assert_int(BattleAction.next_slot(needed, 1, BattleAction.swap(1, 9))).is_equal(3)
	assert_int(BattleAction.next_slot(needed, 2, BattleAction.swap(1, 9))).is_equal(3)


func test_a_swap_in_the_last_slot_ends_the_list() -> void:
	var needed: Array[int] = [1, 1, 1]
	assert_int(BattleAction.next_slot(needed, 2, BattleAction.swap(1, 9))).is_equal(3)


func test_other_actions_advance_by_one() -> void:
	var needed: Array[int] = [1, 1, 2]
	for a: BattleAction in [BattleAction.use_move(1, "hit", 5), BattleAction.rest(1),
			BattleAction.use_item(1, "potion", 1)]:
		assert_int(BattleAction.next_slot(needed, 0, a)).is_equal(1)


func test_a_swap_does_not_skip_another_creatures_slots() -> void:
	var needed: Array[int] = [1, 2, 2]
	assert_int(BattleAction.next_slot(needed, 0, BattleAction.swap(1, 9))).is_equal(1)
