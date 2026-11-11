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
