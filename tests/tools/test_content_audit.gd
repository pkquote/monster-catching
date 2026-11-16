extends GdUnitTestSuite
## ContentAudit on small synthetic data: every failure path of the five M9 guards.


func _raw() -> RawData:
	return FixtureDB.raw()


func _species(id: String, growth: Array = [], extra: Dictionary = {}) -> Dictionary:
	var c := {"id": id, "name": id.capitalize(), "types": ["neutral"], "base_stats": FixtureDB.stats({}),
		"catch_rate": 0.5, "xp_yield": 50, "learnset": [{"level": 1, "move": "hit"}], "passives": ["steady"]}
	if not growth.is_empty():
		c["growth"] = growth
	c.merge(extra, true)
	return c


func _locate(raw: RawData, areas: Array) -> void:
	raw.add_entry("locations", {"id": "loc", "name": "Loc", "areas": areas})


func _except(db: Database, cat: String, skip: Array) -> Array:
	var out: Array = []
	for id in db.ids(cat):
		if not skip.has(id):
			out.append(id)
	out.sort()
	return out


func _db(raw: RawData) -> Database:
	return Database.from_raw(raw)


# --- species ---

func test_species_given_by_dialogue_is_obtainable() -> void:
	var db := _db(_raw())
	var out := ContentAudit.unobtainable_species(db, 'Story.give_creature("flame", 5, true)')
	assert_array(out).is_equal(_except(db, "creatures", ["flame"]))


func test_species_in_a_used_table_is_obtainable() -> void:
	var raw := _raw()
	_locate(raw, ["e1"])
	var db := _db(raw)
	var out := ContentAudit.unobtainable_species(db, "")
	# blob is in the table; its evolutions fish, sparky and mole follow.
	assert_array(out).is_equal(_except(db, "creatures", ["blob", "fish", "sparky", "mole"]))


func test_unused_table_does_not_make_species_obtainable() -> void:
	var db := _db(_raw())
	assert_array(ContentAudit.unobtainable_species(db, "")).is_equal(_except(db, "creatures", []))


func test_evolution_target_of_an_obtainable_species_is_obtainable() -> void:
	# blob evolves into fish, sparky and mole; a three-stage chain hangs off fish.
	var raw := _raw()
	raw.add_entry("creatures", _species("fry"))
	raw.add_entry("creatures", _species("fry_2", [{"level": 5, "default": true, "into": "fry"}]))
	raw.entries.creatures.filter(func(r): return r.entry.id == "fish")[0].entry["growth"] = [
		{"level": 5, "default": true, "into": "fry_2"}]
	_locate(raw, ["e1"])
	var out := ContentAudit.unobtainable_species(_db(raw), "")
	for id: String in ["blob", "fish", "sparky", "mole", "fry_2", "fry"]:
		assert_array(out).not_contains([id])


func test_evolution_cycle_without_an_entry_is_reported() -> void:
	var raw := _raw()
	raw.add_entry("creatures", _species("cyc_a", [{"level": 5, "default": true, "into": "cyc_b"}]))
	raw.add_entry("creatures", _species("cyc_b", [{"level": 5, "default": true, "into": "cyc_a"}]))
	var out := ContentAudit.unobtainable_species(_db(raw), "")
	assert_array(out).contains(["cyc_a", "cyc_b"])


func test_self_evolution_is_not_obtainable() -> void:
	var raw := _raw()
	raw.add_entry("creatures", _species("selfy", [{"level": 5, "default": true, "into": "selfy"}]))
	assert_array(ContentAudit.unobtainable_species(_db(raw), "")).contains(["selfy"])


# --- passives ---

func test_orphan_passive_is_reported() -> void:
	var raw := _raw()
	for p in ["p_listed", "p_affinity", "p_orphan"]:
		raw.add_entry("passives", {"id": p, "name": p, "effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.0}]})
	raw.add_entry("creatures", _species("a", [], {"passives": ["p_listed"]}))
	raw.add_entry("creatures", _species("b", [], {"affinity_passives": {"striker": "p_affinity"}}))
	assert_array(ContentAudit.orphan_passives(_db(raw))).is_equal(["p_orphan"])


# --- items ---

func test_item_is_matched_by_whole_quoted_id() -> void:
	var raw := _raw()
	raw.add_entry("items", {"id": "clear_tonic", "name": "Clear Tonic", "category": "heal", "price": 1,
		"target": "one_ally", "effects": [{"op": "heal", "fraction": 0.5}]})
	var db := _db(raw)
	var out := ContentAudit.orphan_items(db, 'stock = PackedStringArray("clear_tonic")')
	assert_array(out).is_equal(_except(db, "items", ["clear_tonic"]))


# --- encounter tables ---

func test_unused_encounter_is_reported() -> void:
	var raw := _raw()
	assert_array(ContentAudit.unused_encounters(_db(raw))).is_equal(["e1"])
	_locate(raw, ["e1"])
	assert_array(ContentAudit.unused_encounters(_db(raw))).is_empty()


# --- moves ---

func test_move_of_a_populated_type_that_nobody_learns_is_orphan() -> void:
	var out := ContentAudit.orphan_moves(_db(_raw()))
	assert_array(out).contains(["wild_swing"])
	assert_array(out).not_contains(["hit"])


func test_move_of_an_unpopulated_type_passes() -> void:
	var raw := _raw()
	raw.add_entry("types", {"id": "ghost", "name": "Ghost", "description": "Test type.", "pros": ["p"], "cons": ["c"]})
	raw.add_entry("moves", FixtureDB.move("haunt", "ghost", "physical", 50, 100, "one_enemy", [{"op": "damage"}]))
	assert_array(ContentAudit.orphan_moves(_db(raw))).not_contains(["haunt"])


func test_fallback_move_is_never_orphan() -> void:
	# scrap is neutral, a populated type, and nobody learns it.
	assert_array(ContentAudit.orphan_moves(_db(_raw()))).not_contains(["scrap"])


# --- scanning ---

func test_shipped_files_include_dialogue_and_maps_and_the_text_reads_them() -> void:
	var files := ContentAudit.shipped_files()
	assert_bool(files.any(func(p: String) -> bool: return p.ends_with("story.dialogue"))).is_true()
	assert_bool(files.any(func(p: String) -> bool: return p.ends_with("town_01_center.tscn"))).is_true()
	assert_str(ContentAudit.shipped_text()).contains('Story.give_creature("tidepup"')


func test_comments_and_item_checks_do_not_count_as_giving() -> void:
	var text := "\n".join([
		'# $> Story.give_item("tonic")',
		'\t; stock = PackedStringArray("seed")',
		'$> Story.has_item("potion")',
		'$> Story.take_item("net", 2)',
		'$> Story.count_item("master_cage")',
		'# $> Story.give_creature("flame", 5)',
		'$> Story.give_item("cage")',
	])
	var db := _db(_raw())
	assert_array(ContentAudit.orphan_items(db, text)).is_equal(_except(db, "items", ["cage"]))
	assert_array(ContentAudit.unobtainable_species(db, text)).is_equal(_except(db, "creatures", []))


func test_items_are_placed_by_give_item_the_item_property_and_stock() -> void:
	var text := "\n".join([
		'$> Story.give_item("tonic", 5)',
		'item = "potion"',
		'stock = PackedStringArray("seed", "net")',
	])
	var db := _db(_raw())
	assert_array(ContentAudit.orphan_items(db, text)).is_equal(["cage", "master_cage"])


func test_a_cycle_reached_from_a_gift_is_obtainable_and_terminates() -> void:
	var raw := _raw()
	raw.add_entry("creatures", _species("cyc_a", [{"level": 5, "default": true, "into": "cyc_b"}]))
	raw.add_entry("creatures", _species("cyc_b", [{"level": 5, "default": true, "into": "cyc_a"}]))
	var out := ContentAudit.unobtainable_species(_db(raw), 'Story.give_creature("cyc_a", 5)')
	assert_array(out).not_contains(["cyc_a"])
	assert_array(out).not_contains(["cyc_b"])



func test_template_and_test_maps_are_not_shipped() -> void:
	for p: String in ContentAudit.shipped_files():
		var base: String = p.get_file()
		assert_bool(base.begins_with("test_") or base.begins_with("_")).override_failure_message(p).is_false()
