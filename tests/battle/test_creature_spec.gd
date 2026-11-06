extends GdUnitTestSuite
## CreatureSpec: one debug-team slot.

var db: Database


func before() -> void:
	var r: RawData = FixtureDB.raw()
	r.add_entry("passives", {"id": "keen", "name": "Keen", "description": "Test.",
		"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.0}]})
	r.add_entry("passives", {"id": "odd", "name": "Odd", "description": "Test.",
		"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.0}]})
	var gifted: Dictionary = FixtureDB._c("gifted", ["neutral"], FixtureDB.FLAT, [
		{"level": 1, "move": "hit"}, {"level": 5, "move": "mend"}])
	gifted["affinity_passives"] = {"striker": "keen"}
	r.add_entry("creatures", gifted)
	var dual: Dictionary = FixtureDB._c("dual", ["neutral"], FixtureDB.FLAT, [{"level": 1, "move": "hit"}])
	dual["affinity_passives"] = {"striker": "steady"}  # same id as its rolled passive
	r.add_entry("creatures", dual)
	var twice: Dictionary = FixtureDB._c("twice", ["neutral"], FixtureDB.FLAT, [
		{"level": 1, "move": "hit"}, {"level": 9, "move": "mend"}, {"level": 3, "move": "mend"}])
	r.add_entry("creatures", twice)
	r.add_entry("items", {"id": "charm", "name": "Charm", "category": "held", "price": 10,
		"held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}})
	var errors: PackedStringArray = DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	return rng


func _valid() -> CreatureSpec:
	var s: CreatureSpec = CreatureSpec.natural(db, "blob", 10, _rng())
	return s


func test_natural_moves_match_creature_create() -> void:
	for lv: int in [1, 5, 40]:
		var s: CreatureSpec = CreatureSpec.natural(db, "blob", lv, _rng())
		var expected: PackedStringArray = FixtureDB.make(db, "blob", lv).moves
		assert_array(Array(s.moves)).is_equal(Array(expected))
		assert_array(Array(s.natural_moves(db))).is_equal(Array(expected))
	assert_array(Array(CreatureSpec.natural(db, "blob", 40, _rng()).moves)) \
		.is_equal(["growl", "mend", "quick_jab", "wave"])


func test_natural_rolls_passive_and_has_no_item() -> void:
	var s: CreatureSpec = CreatureSpec.natural(db, "blob", 10, _rng())
	assert_str(s.passive).is_equal("steady")
	assert_str(s.held_item).is_equal("")
	assert_bool(s.moves_edited).is_false()


func test_move_standing_three_states() -> void:
	var learned: Dictionary = CreatureSpec.move_standing(db, "blob", 5, "mend")  # exactly at level
	assert_str(learned.state).is_equal(CreatureSpec.LEARNED)
	assert_int(learned.level).is_equal(5)
	var later: Dictionary = CreatureSpec.move_standing(db, "blob", 4, "mend")  # one level short
	assert_str(later.state).is_equal(CreatureSpec.LEARNS_LATER)
	assert_int(later.level).is_equal(5)
	var no: Dictionary = CreatureSpec.move_standing(db, "blob", 50, "zap")
	assert_str(no.state).is_equal(CreatureSpec.NOT_LEARNABLE)
	assert_int(no.level).is_equal(0)


func test_passive_standing() -> void:
	assert_str(CreatureSpec.passive_standing(db, "gifted", "steady")).is_equal(CreatureSpec.ROLLS)
	assert_str(CreatureSpec.passive_standing(db, "gifted", "keen")).is_equal(CreatureSpec.AFFINITY)
	assert_str(CreatureSpec.passive_standing(db, "gifted", "odd")).is_equal(CreatureSpec.NOT_NORMAL)


func test_validate_accepts_valid_spec() -> void:
	var s: CreatureSpec = _valid()
	s.held_item = "charm"
	assert_array(Array(s.validate(db))).is_empty()


func _errors_for(s: CreatureSpec) -> PackedStringArray:
	return s.validate(db)


func _assert_single_error(s: CreatureSpec, needle: String) -> void:
	var errs: PackedStringArray = _errors_for(s)
	assert_int(errs.size()).is_equal(1)
	assert_str(errs[0]).contains(needle)


func test_validate_rejects_bad_specs() -> void:
	var s: CreatureSpec = _valid()
	s.moves = PackedStringArray()
	_assert_single_error(s, "No moves")

	s = _valid()
	s.moves = PackedStringArray(["hit", "hit"])
	_assert_single_error(s, "Duplicate move 'hit'")

	s = _valid()
	s.moves = PackedStringArray(["hit", "growl", "mend", "quick_jab", "wave"])
	_assert_single_error(s, "More than 4 moves")

	s = _valid()
	s.moves = PackedStringArray(["hit", "growl", "mend", "quick_jab"])  # exactly max_moves is fine
	assert_array(Array(s.validate(db))).is_empty()

	s = _valid()
	s.species = "nope"
	_assert_single_error(s, "Unknown species 'nope'")

	s = _valid()
	s.moves = PackedStringArray(["nope"])
	_assert_single_error(s, "Unknown move 'nope'")

	s = _valid()
	s.passive = "nope"
	_assert_single_error(s, "Unknown passive 'nope'")

	s = _valid()
	s.held_item = "nope"
	_assert_single_error(s, "Unknown held item 'nope'")

	s = _valid()
	s.held_item = "potion"  # exists, but is not a held item
	_assert_single_error(s, "'potion' is not a held item")


func test_to_instance_clamps_level() -> void:
	var s: CreatureSpec = _valid()
	s.level = 0
	assert_int(s.to_instance(db, _rng()).level).is_equal(1)
	s.level = 500
	assert_int(s.to_instance(db, _rng()).level).is_equal(db.balance.level_cap)


func test_to_instance_applies_fields() -> void:
	var s: CreatureSpec = _valid()
	s.moves = PackedStringArray(["hit", "wave"])
	s.held_item = "charm"
	s.passive = "odd"
	var c: CreatureInstance = s.to_instance(db, _rng())
	assert_array(Array(c.moves)).is_equal(["hit", "wave"])
	assert_str(c.held_item).is_equal("charm")
	assert_str(c.passive).is_equal("odd")


func test_retarget_resets_natural_moves() -> void:
	var s: CreatureSpec = CreatureSpec.natural(db, "blob", 10, _rng())
	s.retarget(db, "blob", 3)
	assert_int(s.level).is_equal(3)
	assert_array(Array(s.moves)).is_equal(["hit", "growl"])
	s.retarget(db, "fish", 10)
	assert_str(s.species).is_equal("fish")
	assert_array(Array(s.moves)).is_equal(["splash"])


func test_retarget_keeps_edited_moves() -> void:
	var s: CreatureSpec = CreatureSpec.natural(db, "blob", 10, _rng())
	s.moves = PackedStringArray(["zap"])
	s.moves_edited = true
	s.retarget(db, "fish", 1)
	assert_str(s.species).is_equal("fish")
	assert_array(Array(s.moves)).is_equal(["zap"])


func test_round_trip_through_instance() -> void:
	var s: CreatureSpec = _valid()
	s.moves = PackedStringArray(["hit", "wave"])
	s.held_item = "charm"
	s.passive = "odd"
	s.level = 12
	var back: CreatureSpec = CreatureSpec.from_instance(s.to_instance(db, _rng()))
	assert_str(back.species).is_equal("blob")
	assert_int(back.level).is_equal(12)
	assert_array(Array(back.moves)).is_equal(["hit", "wave"])
	assert_str(back.held_item).is_equal("charm")
	assert_str(back.passive).is_equal("odd")
	# A copied creature keeps its exact moves through level/species changes.
	assert_bool(back.moves_edited).is_true()
	back.retarget(db, back.species, 1)
	assert_array(Array(back.moves)).is_equal(["hit", "wave"])


func test_labels() -> void:
	assert_str(CreatureSpec.move_label(db, "blob", 5, "mend")).is_equal("Mend ✓ Lv 5")
	assert_str(CreatureSpec.move_label(db, "blob", 4, "mend")).is_equal("Mend Lv 5 (later)")
	assert_str(CreatureSpec.move_label(db, "blob", 50, "zap")).is_equal("Zap ✗ can't learn")
	assert_str(CreatureSpec.passive_label(db, "gifted", "steady")).is_equal("Steady ★ rolls")
	assert_str(CreatureSpec.passive_label(db, "gifted", "keen")).is_equal("Keen (Affinity)")
	assert_str(CreatureSpec.passive_label(db, "gifted", "odd")).is_equal("Odd ✗ not normal")


func test_summary() -> void:
	var s: CreatureSpec = CreatureSpec.natural(db, "blob", 10, _rng())
	assert_str(s.summary(db)).is_equal("Natural at Lv 10: Growl, Mend, Quick Jab, Wave")


func test_passive_in_both_lists_counts_as_rolls() -> void:
	assert_str(CreatureSpec.passive_standing(db, "dual", "steady")).is_equal(CreatureSpec.ROLLS)


func test_move_standing_duplicate_learnset_entry_uses_lowest_level() -> void:
	var early: Dictionary = CreatureSpec.move_standing(db, "twice", 3, "mend")
	assert_str(early.state).is_equal(CreatureSpec.LEARNED)
	assert_int(early.level).is_equal(3)
	var before_it: Dictionary = CreatureSpec.move_standing(db, "twice", 2, "mend")
	assert_str(before_it.state).is_equal(CreatureSpec.LEARNS_LATER)
	assert_int(before_it.level).is_equal(3)


func test_unknown_species_fallbacks() -> void:
	var s: CreatureSpec = CreatureSpec.new()
	s.species = "nope"
	s.level = 10
	assert_array(Array(s.natural_moves(db))).is_empty()
	assert_str(CreatureSpec.move_label(db, "nope", 10, "hit")).is_equal("Hit ✗ can't learn")
	assert_str(CreatureSpec.passive_label(db, "nope", "steady")).is_equal("Steady ✗ not normal")
	assert_str(CreatureSpec.move_label(db, "blob", 10, "ghost_move")).is_equal("ghost_move ✗ can't learn")
	assert_str(CreatureSpec.passive_label(db, "blob", "ghost_passive")).is_equal("ghost_passive ✗ not normal")


func test_summary_prints_clamped_level() -> void:
	var s: CreatureSpec = CreatureSpec.natural(db, "blob", 500, _rng())
	assert_str(s.summary(db)).starts_with("Natural at Lv 99:")
