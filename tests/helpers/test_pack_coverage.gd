extends GdUnitTestSuite
## PackCoverage: only tp_ entries count, and every family key is always present.


func _move(id: String, target: String, effects: Array) -> Dictionary:
	return FixtureDB.move(id, "neutral", "physical", 40, 100, target, effects)


func _report_with(entries: Array) -> Dictionary:
	var r: RawData = FixtureDB.raw()
	for rec: Array in entries:
		r.add_entry(rec[0], rec[1])
	return PackCoverage.report(r)


func test_all_family_keys_present_and_nothing_covered_without_a_pack() -> void:
	var rep: Dictionary = PackCoverage.report(FixtureDB.raw())
	for fam: String in PackCoverage.FAMILIES:
		assert_bool(rep.has(fam)).is_true()
	assert_int(rep.effect_ops.size()).is_equal(DataSchemas.EFFECT_OPS.size())
	assert_int(rep.move_targets.size()).is_equal(DataSchemas.MOVE_TARGETS.size())
	assert_array(Array(rep.trigger_on)).contains_exactly_in_any_order(DataSchemas.TRIGGER_ON)
	assert_array(Array(rep.use_kinds)).contains_exactly_in_any_order(["permanent", "consumed", "per_battle"])
	assert_array(Array(rep.types_dual_count)).contains_exactly(["need 10, have 0"])


func test_pack_moves_cover_their_ops_and_targets_only() -> void:
	var rep: Dictionary = _report_with([
		["moves", _move("tp_dmg", "one_enemy", [{"op": "damage"}])],
		["moves", _move("tp_heal", "self", [{"op": "heal", "fraction": 0.5}])],
	])
	assert_bool(rep.effect_ops.has("damage")).is_false()
	assert_bool(rep.effect_ops.has("heal")).is_false()
	assert_bool(rep.effect_ops.has("capture")).is_true()
	assert_int(rep.effect_ops.size()).is_equal(DataSchemas.EFFECT_OPS.size() - 2)
	assert_bool(rep.move_targets.has("one_enemy")).is_false()
	assert_bool(rep.move_targets.has("self")).is_false()
	assert_bool(rep.move_targets.has("two_enemies")).is_true()
	assert_int(rep.move_targets.size()).is_equal(DataSchemas.MOVE_TARGETS.size() - 2)


func test_non_pack_entries_do_not_cover() -> void:
	var rep: Dictionary = _report_with([
		["moves", _move("shipped_lower", "all", [{"op": "stat_stage", "stat": "patk", "stages": -1}])],
	])
	assert_bool(rep.effect_ops.has("stat_stage")).is_true()
	assert_bool(rep.move_targets.has("all")).is_true()


func test_passive_triggers_whens_and_held_use_kinds() -> void:
	var rep: Dictionary = _report_with([
		["passives", {"id": "tp_all_whens", "name": "W", "effects": [
			{"op": "stat_mod", "stat": "patk", "mult": 1.5, "when": {"hp_below": 0.5}},
			{"op": "stat_mod", "stat": "satk", "mult": 1.5, "when": {"underdog": true}},
			{"op": "stat_mod", "stat": "spd", "mult": 1.5, "when": {"field": "soaked", "side": "own"}}],
			"triggers": [{"on": "hit", "contact": true, "effects": [{"op": "heal", "fraction": 0.1}]},
				{"on": "faint", "when": {"underdog": true}, "effects": [{"op": "heal", "fraction": 0.1}]}],
			"field": [{"op": "encounter_rate", "mult": 0.5}]}],
		["items", {"id": "tp_held_consumed", "name": "H", "category": "held", "price": 1,
			"held": {"use": "consumed", "triggers": [{"on": "enter", "effects": [{"op": "heal", "fraction": 0.1}]}]}}],
		["items", {"id": "tp_held_default", "name": "H2", "category": "held", "price": 1,
			"held": {"effects": [{"op": "stat_mod", "stat": "pdef", "mult": 1.1}]}}],
		# A shipped-style held item must not count.
		["items", {"id": "shipped_held", "name": "H3", "category": "held", "price": 1,
			"held": {"use": "per_battle", "triggers": [{"on": "round_end", "effects": [{"op": "heal", "fraction": 0.1}]}]}}],
	])
	assert_array(Array(rep.when_keys)).is_empty()
	assert_array(Array(rep.trigger_on)).contains_exactly_in_any_order(["round_end", "knockout"])
	assert_array(Array(rep.use_kinds)).contains_exactly(["per_battle"])
	assert_bool(rep.effect_ops.has("encounter_rate")).is_false()
	assert_bool(rep.effect_ops.has("xp_mult")).is_true()


func test_partial_when_keys_are_listed() -> void:
	var rep: Dictionary = _report_with([
		["passives", {"id": "tp_one_when", "name": "W", "effects": [
			{"op": "stat_mod", "stat": "patk", "mult": 1.5, "when": {"hp_below": 0.5}}]}],
	])
	assert_array(Array(rep.when_keys)).contains_exactly_in_any_order(["underdog", "field", "side"])


func test_types_statuses_and_field_states() -> void:
	var rep: Dictionary = _report_with([
		["creatures", {"id": "tp_fire", "name": "F", "types": ["fire"]}],
		["creatures", {"id": "tp_duo", "name": "D", "types": ["water", "earth"]}],
		["creatures", {"id": "shipped_water", "name": "S", "types": ["water"]}],
		["moves", _move("tp_burner", "one_enemy", [{"op": "apply_status", "status": "burn"},
			{"op": "apply_field_state", "side": "enemy", "state": "soaked"}])],
	])
	assert_array(Array(rep.types_single)).contains_exactly_in_any_order(["neutral", "water", "electric", "earth"])
	assert_array(Array(rep.types_dual_count)).contains_exactly(["need 10, have 1"])
	assert_array(Array(rep.statuses)).contains_exactly_in_any_order(["shock", "chill"])
	assert_array(Array(rep.field_states)).contains_exactly_in_any_order(
		["charged", "scorched", "frosted", "overgrown"])


func test_ten_dual_typed_creatures_clear_the_dual_family() -> void:
	var entries: Array = []
	for i: int in 10:
		entries.append(["creatures", {"id": "tp_d%d" % i, "name": "D", "types": ["fire", "water"]}])
	var rep: Dictionary = _report_with(entries)
	assert_array(Array(rep.types_dual_count)).is_empty()
