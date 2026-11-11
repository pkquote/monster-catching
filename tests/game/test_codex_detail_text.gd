extends GdUnitTestSuite
## The detail page's text: description, where to find it, the evolves-from and not-caught notes.

var save: SaveGame


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)


func _db(many_tables := false) -> Database:
	var raw := FixtureDB.raw()
	raw.add_entry("encounters", {"id": "t_a", "name": "Alpha grass", "pack_min": 1, "pack_max": 1,
		"table": [{"species": "blob", "weight": 1, "min_level": 1, "max_level": 3}]})
	raw.add_entry("encounters", {"id": "t_b", "name": "Beta grass", "pack_min": 1, "pack_max": 1,
		"table": [{"species": "blob", "weight": 1, "min_level": 5, "max_level": 7},
			{"species": "blob", "weight": 1, "min_level": 6, "max_level": 9}]})
	raw.add_entry("locations", {"id": "m1", "name": "Map One", "areas": ["t_a", "t_b"]})
	if many_tables:
		var areas: Array = []
		for i in 8:
			raw.add_entry("encounters", {"id": "t_s%d" % i, "name": "Sparky spot %d" % i, "pack_min": 1,
				"pack_max": 1, "table": [{"species": "sparky", "weight": 1, "min_level": 2, "max_level": 4}]})
			areas.append("t_s%d" % i)
		raw.add_entry("locations", {"id": "m3", "name": "Map Three", "areas": areas})
	for rec in raw.get_entries("creatures"):
		if rec.entry.id == "blob":
			rec.entry["description"] = "A round test blob."
	return Database.from_raw(raw)


func test_body_lists_each_location() -> void:
	Codex.mark_caught(save, "blob")
	var t := CodexDetailPage.body_text(_db(), save, "blob")
	assert_str(t).contains("Where to find it:")
	assert_str(t).contains("- Map One – Alpha grass, Lv 1–3")
	assert_str(t).contains("- Map One – Beta grass, Lv 5–9")


func test_body_uses_the_description_or_the_fallback() -> void:
	Codex.mark_caught(save, "blob")
	Codex.mark_caught(save, "fish")
	assert_str(CodexDetailPage.body_text(_db(), save, "blob")).starts_with("A round test blob.")
	assert_str(CodexDetailPage.body_text(_db(), save, "fish")).starts_with("No description yet.")


func test_body_caps_long_location_lists() -> void:
	Codex.mark_caught(save, "sparky")
	var t := CodexDetailPage.body_text(_db(true), save, "sparky")
	var rows := Array(t.split("\n")).filter(func(l: String) -> bool: return l.begins_with("- ") and l.contains(" – "))
	assert_int(rows.size()).is_equal(CodexDetailPage.MAX_LOCATION_LINES)
	assert_str(t).contains("- +%d more places" % (8 - CodexDetailPage.MAX_LOCATION_LINES))


func test_evolves_from_shows_only_when_the_source_is_caught() -> void:
	Codex.mark_caught(save, "mole")  # blob grows into mole; mole has no wild habitat
	var without := CodexDetailPage.body_text(_db(), save, "mole")
	assert_str(without).contains("No wild habitat known")
	assert_str(without).not_contains("Evolves from")
	Codex.mark_caught(save, "blob")
	var with := CodexDetailPage.body_text(_db(), save, "mole")
	assert_str(with).contains("Evolves from Blob")
	assert_str(with).not_contains("No wild habitat known")


func test_no_source_says_no_wild_habitat_known() -> void:
	Codex.mark_caught(save, "fast")
	assert_str(CodexDetailPage.body_text(_db(), save, "fast")).contains("No wild habitat known")


func test_not_caught_note_only_when_seen_not_caught() -> void:
	Codex.mark_seen(save, "blob")
	assert_str(CodexDetailPage.body_text(_db(), save, "blob")).contains("Not caught yet")
	Codex.mark_caught(save, "blob")
	assert_str(CodexDetailPage.body_text(_db(), save, "blob")).not_contains("Not caught yet")


func test_a_very_long_description_is_clipped_with_an_ellipsis() -> void:
	var raw := FixtureDB.raw()
	for rec in raw.get_entries("creatures"):
		if rec.entry.id == "blob":
			rec.entry["description"] = "word ".repeat(100)
	Codex.mark_caught(save, "blob")
	var first := CodexDetailPage.body_text(Database.from_raw(raw), save, "blob").split("\n")[0]
	assert_int(first.length()).is_less_equal(CodexDetailPage.DESCRIPTION_MAX)
	assert_str(first).ends_with("…")
