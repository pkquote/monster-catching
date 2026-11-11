extends GdUnitTestSuite
## Where a species can be found, and how the locations file is built from the maps.


func _db() -> Database:
	var raw := FixtureDB.raw()
	raw.add_entry("encounters", {"id": "t_a", "name": "Alpha grass", "pack_min": 1, "pack_max": 1,
		"table": [{"species": "blob", "weight": 1, "min_level": 1, "max_level": 3},
			{"species": "fish", "weight": 1, "min_level": 2, "max_level": 4}]})
	raw.add_entry("encounters", {"id": "t_b", "name": "Beta grass", "pack_min": 1, "pack_max": 1,
		"table": [{"species": "blob", "weight": 1, "min_level": 5, "max_level": 7},
			{"species": "blob", "weight": 1, "min_level": 6, "max_level": 9}]})
	raw.add_entry("encounters", {"id": "t_c", "name": "Gamma reeds", "pack_min": 1, "pack_max": 1,
		"table": [{"species": "fish", "weight": 1, "min_level": 3, "max_level": 3}]})
	raw.add_entry("locations", {"id": "m1", "name": "Map One", "areas": ["t_a", "t_b"]})
	raw.add_entry("locations", {"id": "m2", "name": "Map Two", "areas": ["t_c"]})
	for rec in raw.get_entries("creatures"):
		if rec.entry.id == "flame":
			rec.entry["growth"] = [{"level": 5, "into": "mole", "default": true}]
	return Database.from_raw(raw)


func test_one_row_per_map_and_table() -> void:
	var rows := Locations.for_species(_db(), "blob")
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0].map).is_equal("Map One")
	assert_str(rows[0].area).is_equal("Alpha grass")
	assert_int(rows[0].min).is_equal(1)
	assert_int(rows[0].max).is_equal(3)
	assert_str(rows[1].area).is_equal("Beta grass")


func test_levels_merge_over_rows_of_one_table() -> void:
	var rows := Locations.for_species(_db(), "blob")
	assert_int(rows[1].min).is_equal(5)
	assert_int(rows[1].max).is_equal(9)


func test_a_table_without_the_species_gives_no_row() -> void:
	var rows := Locations.for_species(_db(), "fish")
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0].area).is_equal("Alpha grass")
	assert_str(rows[1].map).is_equal("Map Two")
	assert_str(rows[1].area).is_equal("Gamma reeds")


func test_species_with_no_wild_source_has_no_rows() -> void:
	assert_array(Locations.for_species(_db(), "mole")).is_empty()


func test_evolves_from_finds_the_source() -> void:
	assert_str(Locations.evolves_from(_db(), "fish")).is_equal("blob")


func test_evolves_from_takes_the_first_source_in_codex_order() -> void:
	# blob and flame both grow into mole; blob sorts first.
	assert_str(Locations.evolves_from(_db(), "mole")).is_equal("blob")


func test_evolves_from_is_empty_for_a_base_species() -> void:
	assert_str(Locations.evolves_from(_db(), "blob")).is_empty()


func test_line_formats_range_and_single_level() -> void:
	assert_str(Locations.line({"map": "Route 1", "area": "Route 1 tall grass", "min": 2, "max": 5})) \
		.is_equal("Route 1 – Route 1 tall grass, Lv 2–5")
	assert_str(Locations.line({"map": "Map Two", "area": "Gamma reeds", "min": 3, "max": 3})) \
		.is_equal("Map Two – Gamma reeds, Lv 3")


func _map(name: String, default_enc: String, areas: Array) -> Dictionary:
	var pieces: Array = []
	for a in areas:
		pieces.append({"type": "EncounterArea", "props": {"encounter": a}})
	pieces.append({"type": "Door", "props": {"encounter": "ignored"}})
	return {"name": name, "default_encounter": default_enc, "pieces": pieces}


func test_build_skips_test_maps_and_maps_without_encounters() -> void:
	var doc := Locations.build({
		"route": _map("Route", "t_a", []),
		"test_b": _map("Test Field", "t_a", []),
		"town": _map("Town", "", []),
	})
	assert_int(doc.schema).is_equal(1)
	assert_int(doc.entries.size()).is_equal(1)
	assert_str(doc.entries[0].id).is_equal("route")


func test_build_orders_default_then_areas_and_drops_duplicates() -> void:
	var doc := Locations.build({"route": _map("Route", "t_a", ["t_b", "t_a", "", "t_b"])})
	assert_array(doc.entries[0].areas).is_equal(["t_a", "t_b"])
	assert_str(doc.entries[0].name).is_equal("Route")


func test_build_falls_back_to_the_map_id_without_a_display_name() -> void:
	var doc := Locations.build({"route": _map("", "t_a", [])})
	assert_str(doc.entries[0].name).is_equal("route")


func test_build_sorts_maps_by_id() -> void:
	var doc := Locations.build({"b": _map("B", "t_a", []), "a": _map("A", "t_a", [])})
	assert_str(doc.entries[0].id).is_equal("a")
