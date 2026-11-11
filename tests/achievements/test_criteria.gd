extends GdUnitTestSuite
## The four criteria kinds: progress, watch keys and the boundary at the target.

var db: Database
var save: SaveGame


func before() -> void:
	db = FixtureDB.build()


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)
	save.party.clear()
	save.storage.fill(null)


func _p(c: Dictionary) -> Dictionary:
	return Criteria.for_kind(c.kind).progress(db, save, c)


func test_counter_progress_and_boundary() -> void:
	var c := {"kind": "counter", "stat": "steps", "target": 10}
	assert_dict(_p(c)).is_equal({"current": 0, "target": 10})
	Counters.add(save, "steps", 4)
	assert_dict(_p(c)).is_equal({"current": 4, "target": 10})
	Counters.add(save, "steps", 6)
	assert_dict(_p(c)).is_equal({"current": 10, "target": 10})
	Counters.add(save, "steps", 5)
	assert_dict(_p(c)).is_equal({"current": 10, "target": 10})  # clamped, still met


func test_counter_watches_its_stat() -> void:
	var c := {"kind": "counter", "stat": "steps", "target": 10}
	assert_array(Array(Criteria.for_kind("counter").watches(c))).is_equal(["counter:steps"])


func test_codex_counts_only_species_in_the_list() -> void:
	var raw := FixtureDB.raw()
	var proto: Dictionary = raw.get_entries("creatures")[0].entry.duplicate(true)
	proto["id"] = "tp_extra"
	raw.add_entry("creatures", proto)
	var with_pack := Database.from_raw(raw)
	var listed := Codex.order(with_pack)[0]
	var seen := {"kind": "codex", "mode": "seen", "target": 3}
	Codex.mark_seen(save, "tp_extra")  # test content: not in the Codex
	Codex.mark_seen(save, "removed_species")  # no longer in the data
	assert_int(Criteria.for_kind("codex").progress(with_pack, save, seen).current).is_equal(0)
	Codex.mark_seen(save, listed)
	assert_int(Criteria.for_kind("codex").progress(with_pack, save, seen).current).is_equal(1)


func test_codex_caught_counts_caught_not_seen() -> void:
	var caught := {"kind": "codex", "mode": "caught", "target": 2}
	Codex.mark_seen(save, "blob")
	assert_int(_p(caught).current).is_equal(0)
	Codex.mark_caught(save, "blob")
	assert_int(_p(caught).current).is_equal(1)


func test_codex_species_mode_flips_when_caught() -> void:
	var c := {"kind": "codex", "mode": "species", "species": "blob"}
	Codex.mark_seen(save, "blob")
	assert_dict(_p(c)).is_equal({"current": 0, "target": 1})
	Codex.mark_caught(save, "blob")
	assert_dict(_p(c)).is_equal({"current": 1, "target": 1})


func test_codex_problem_needs_the_right_field() -> void:
	var k := Criteria.for_kind("codex")
	assert_str(k.problem({"kind": "codex", "mode": "species"})).is_not_empty()
	assert_str(k.problem({"kind": "codex", "mode": "seen"})).is_not_empty()
	assert_str(k.problem({"kind": "codex", "mode": "species", "species": "blob"})).is_empty()
	assert_str(k.problem({"kind": "codex", "mode": "caught", "target": 2})).is_empty()
	assert_array(Array(k.watches({}))).is_equal(["codex"])


func test_flag_progress() -> void:
	var c := {"kind": "flag", "flag": "met_prof"}
	assert_dict(_p(c)).is_equal({"current": 0, "target": 1})
	save.story.set_flag("met_prof")
	assert_dict(_p(c)).is_equal({"current": 1, "target": 1})
	assert_array(Array(Criteria.for_kind("flag").watches(c))).is_equal(["flag:met_prof"])


func test_creature_level_uses_the_highest_across_party_and_boxes() -> void:
	var c := {"kind": "creature", "what": "level", "target": 20}
	assert_int(_p(c).current).is_equal(0)  # no creatures
	save.party.append(FixtureDB.make(db, "blob", 7))
	save.storage[0] = FixtureDB.make(db, "blob", 15)
	assert_dict(_p(c)).is_equal({"current": 15, "target": 20})
	assert_array(Array(Criteria.for_kind("creature").watches(c))).is_equal(["creature"])


func test_creature_bond_negative_shows_zero_and_is_not_met() -> void:
	var c := {"kind": "creature", "what": "bond", "target": 50}
	var cr := FixtureDB.make(db, "blob", 5)
	cr.bond = -30
	save.party.append(cr)
	assert_dict(_p(c)).is_equal({"current": 0, "target": 50})
	cr.bond = 80
	assert_dict(_p(c)).is_equal({"current": 50, "target": 50})


func test_creature_evolved_follows_the_counter() -> void:
	var c := {"kind": "creature", "what": "evolved", "target": 2}
	Counters.add(save, "creatures_evolved")
	assert_dict(_p(c)).is_equal({"current": 1, "target": 2})
	assert_array(Array(Criteria.for_kind("creature").watches(c))).contains_exactly_in_any_order(
		["creature", "counter:creatures_evolved"])


func test_registry() -> void:
	assert_object(Criteria.for_kind("nope")).is_null()
	assert_array(Array(Criteria.kinds())).contains_exactly_in_any_order(["counter", "codex", "flag", "creature"])
