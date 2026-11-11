extends GdUnitTestSuite
## The seen / caught record per species.

var db: Database
var save: SaveGame


func before() -> void:
	db = FixtureDB.build()


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)


func test_unseen_by_default() -> void:
	assert_str(Codex.status(save, "blob")).is_equal("unseen")
	assert_bool(Codex.seen(save, "blob")).is_false()
	assert_bool(Codex.caught(save, "blob")).is_false()


func test_mark_seen_then_caught() -> void:
	assert_bool(Codex.mark_seen(save, "blob")).is_true()
	assert_bool(Codex.mark_seen(save, "blob")).is_false()
	assert_str(Codex.status(save, "blob")).is_equal("seen")
	assert_bool(Codex.mark_caught(save, "blob")).is_true()
	assert_str(Codex.status(save, "blob")).is_equal("caught")
	assert_bool(Codex.seen(save, "blob")).is_true()
	assert_bool(Codex.mark_caught(save, "blob")).is_false()


func test_caught_implies_seen() -> void:
	Codex.mark_caught(save, "fish")
	assert_bool(Codex.seen(save, "fish")).is_true()
	assert_bool(Codex.caught(save, "fish")).is_true()


func test_counts() -> void:
	Codex.mark_seen(save, "blob")
	Codex.mark_caught(save, "fish")
	assert_int(Codex.seen_count(save)).is_equal(2)
	assert_int(Codex.caught_count(save)).is_equal(1)


func test_backfill_marks_party_and_every_box_slot() -> void:
	save.party = [FixtureDB.make(db, "blob", 5)]
	save.storage[save.storage.size() - 1] = FixtureDB.make(db, "fish", 5)
	Codex.backfill(save)
	assert_bool(Codex.caught(save, "blob")).is_true()
	assert_bool(Codex.caught(save, "fish")).is_true()
	assert_int(Codex.caught_count(save)).is_equal(2)


func test_backfill_keeps_existing_marks() -> void:
	Codex.mark_seen(save, "mole")
	save.party = [FixtureDB.make(db, "blob", 5)]
	Codex.backfill(save)
	assert_str(Codex.status(save, "mole")).is_equal("seen")
	assert_str(Codex.status(save, "blob")).is_equal("caught")


func _numbered_db() -> Database:
	var raw := FixtureDB.raw()
	for rec in raw.get_entries("creatures"):
		if rec.entry.id == "fish":
			rec.entry["dex"] = 2
		elif rec.entry.id == "flame":
			rec.entry["dex"] = 1
	return Database.from_raw(raw)


func test_order_puts_numbered_species_first_then_by_id() -> void:
	var order := Codex.order(_numbered_db())
	assert_str(order[0]).is_equal("flame")
	assert_str(order[1]).is_equal("fish")
	var rest := Array(order).slice(2)
	var sorted := rest.duplicate()
	sorted.sort()
	assert_array(rest).is_equal(sorted)
	assert_int(order.size()).is_equal(_numbered_db().count("creatures"))


func test_order_breaks_a_dex_tie_by_id() -> void:
	var raw := FixtureDB.raw()
	for rec in raw.get_entries("creatures"):
		if rec.entry.id == "fish" or rec.entry.id == "flame":
			rec.entry["dex"] = 5  # a duplicate the validator rejects, but the order must still be stable
	var order := Codex.order(Database.from_raw(raw))
	assert_str(order[0]).is_equal("fish")
	assert_str(order[1]).is_equal("flame")


func test_order_leaves_out_test_pack_creatures() -> void:
	var raw := FixtureDB.raw()
	var proto: Dictionary = raw.get_entries("creatures")[0].entry.duplicate(true)
	proto["id"] = "tp_extra"
	raw.add_entry("creatures", proto)
	var d := Database.from_raw(raw)
	assert_bool(d.has("creatures", "tp_extra")).is_true()
	assert_bool(Codex.order(d).has("tp_extra")).is_false()


func test_number_text_pads_to_three_digits() -> void:
	var d := _numbered_db()
	assert_str(Codex.number_text(d, "flame")).is_equal("#001")
	assert_str(Codex.number_text(d, "fish")).is_equal("#002")


func test_number_text_without_dex_is_dashes() -> void:
	assert_str(Codex.number_text(_numbered_db(), "blob")).is_equal("#---")
