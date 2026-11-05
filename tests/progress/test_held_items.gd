extends GdUnitTestSuite
## Held items on creatures: give / take / swap against the bag, persistence.

var db: Database


func before() -> void:
	var raw := FixtureDB.raw()
	raw.add_entry("items", {"id": "charm", "name": "Charm", "category": "held", "price": 10,
		"held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}})
	raw.add_entry("items", {"id": "berry", "name": "Berry", "category": "held", "price": 10,
		"held": {"use": "consumed", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.2}]}})
	db = Database.from_raw(raw)


func _creature() -> CreatureInstance:
	return CreatureInstance.create(db, "blob", 5)


func _save(inv: Dictionary) -> SaveGame:
	var s := SaveGame.new()
	s.inventory = inv
	return s


func _total(save: SaveGame, c: CreatureInstance, ids: Array) -> int:
	var n := 0
	for id in ids:
		n += int(save.inventory.get(id, 0))
		if c.held_item == id:
			n += 1
	return n


func test_give_moves_one_from_the_bag_to_the_creature() -> void:
	var s := _save({"charm": 2})
	var c := _creature()
	var r := HeldItems.give(db, s, c, "charm")
	assert_bool(r.ok).is_true()
	assert_str(r.returned).is_empty()
	assert_str(c.held_item).is_equal("charm")
	assert_dict(s.inventory).is_equal({"charm": 1})


func test_give_removes_the_inventory_key_at_zero() -> void:
	var s := _save({"charm": 1})
	var c := _creature()
	HeldItems.give(db, s, c, "charm")
	assert_bool(s.inventory.has("charm")).is_false()


func test_swap_returns_the_old_item_to_the_bag() -> void:
	var s := _save({"berry": 1})
	var c := _creature()
	c.held_item = "charm"
	var r := HeldItems.give(db, s, c, "berry")
	assert_bool(r.ok).is_true()
	assert_str(c.held_item).is_equal("berry")
	assert_dict(s.inventory).is_equal({"charm": 1})
	assert_str(r.returned).is_equal("charm")


func test_swap_with_the_last_copy_conserves_items() -> void:
	var s := _save({"berry": 1, "charm": 2})
	var c := _creature()
	c.held_item = "charm"
	var before_total := _total(s, c, ["berry", "charm"])
	HeldItems.give(db, s, c, "berry")
	assert_int(_total(s, c, ["berry", "charm"])).is_equal(before_total)
	# Swapping the same item for itself changes nothing.
	var s2 := _save({"charm": 1})
	var c2 := _creature()
	c2.held_item = "charm"
	HeldItems.give(db, s2, c2, "charm")
	assert_int(_total(s2, c2, ["charm"])).is_equal(2)


func test_give_rejects_a_non_held_item_and_an_empty_bag() -> void:
	var s := _save({"tonic": 1, "charm": 0})
	var c := _creature()
	var r := HeldItems.give(db, s, c, "tonic")
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("not_held_item")
	r = HeldItems.give(db, s, c, "charm")
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("none_left")
	assert_str(c.held_item).is_empty()
	assert_dict(s.inventory).is_equal({"tonic": 1, "charm": 0})


func test_take_returns_the_item_to_the_bag() -> void:
	var s := _save({"charm": 1})
	var c := _creature()
	c.held_item = "charm"
	var r := HeldItems.take(s, c)
	assert_bool(r.ok).is_true()
	assert_str(c.held_item).is_empty()
	assert_dict(s.inventory).is_equal({"charm": 2})


func test_take_from_an_empty_creature_errors() -> void:
	var s := _save({})
	var r := HeldItems.take(s, _creature())
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("empty")
	assert_dict(s.inventory).is_empty()


func test_unknown_held_id_is_ignored() -> void:
	var s := _save({})
	var c := _creature()
	c.held_item = "ghost"
	assert_object(HeldItems.def_of(db, c)).is_null()
	assert_bool(HeldItems.take(s, c).ok).is_true()
	assert_dict(s.inventory).is_equal({"ghost": 1})


func test_def_of_finds_the_item() -> void:
	var c := _creature()
	assert_object(HeldItems.def_of(db, c)).is_null()
	c.held_item = "charm"
	assert_str(HeldItems.def_of(db, c).id).is_equal("charm")


func test_held_item_round_trips_and_copies() -> void:
	var c := _creature()
	c.held_item = "charm"
	assert_str(CreatureInstance.from_dict(c.to_dict()).held_item).is_equal("charm")
	var other := _creature()
	other.copy_from(c)
	assert_str(other.held_item).is_equal("charm")
	assert_str(CreatureInstance.from_dict({"species": "blob", "level": 1, "xp": 0, "hp": 1, "moves": []}).held_item).is_empty()
