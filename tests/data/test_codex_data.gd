extends GdUnitTestSuite
## Every shipped creature has a Codex number.


func _shipped() -> Array:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "res://dialogue")
	var out: Array = []
	for id in result.db.ids("creatures"):
		out.append(result.db.creature(id))
	return out


func test_every_shipped_creature_has_a_unique_dex() -> void:
	var seen := {}
	for c: CreatureDef in _shipped():
		assert_int(c.dex).override_failure_message("%s has no dex" % c.id).is_greater_equal(1)
		assert_bool(seen.has(c.dex)).override_failure_message("dex %d repeated on %s" % [c.dex, c.id]).is_false()
		seen[c.dex] = true


func test_dex_numbers_are_contiguous_from_one() -> void:
	var nums: Array = _shipped().map(func(c: CreatureDef) -> int: return c.dex)
	nums.sort()
	var want: Array = range(1, nums.size() + 1)
	assert_array(nums).is_equal(want)
