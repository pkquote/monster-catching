extends GdUnitTestSuite
## SpeciesScaffold: a new species line that validates against the shipped data (build), and the file
## writing the runner uses (write_line).

const TMP := "user://scaffold_test"

var raw: RawData
var db: Database


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	_clean_tmp()
	var errs := PackedStringArray()
	raw = DataLoader.read_raw("res://data", errs)
	assert_array(errs).override_failure_message("\n".join(errs)).is_empty()
	assert_array(DataValidator.validate(raw)).override_failure_message("Shipped data must validate before scaffolding").is_empty()
	db = Database.from_raw(raw)


func after_test() -> void:
	_clean_tmp()


# --- helpers ---

func _clean_tmp() -> void:
	for f in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP.path_join(f))


func _build(name: String = "wisp", types: Array = ["fire"], stages: int = 3) -> Dictionary:
	return SpeciesScaffold.build(db, name, types, stages)


func _entries(name: String = "wisp", types: Array = ["fire"], stages: int = 3) -> Array:
	var r := _build(name, types, stages)
	assert_bool(r.ok).override_failure_message(str(r.get("error", ""))).is_true()
	return r.doc.entries


func _max_dex() -> int:
	var m := 0
	for id in db.ids("creatures"):
		m = maxi(m, db.creature(id).dex)
	return m


## Rebuilds `db` from `raw` after removing every move of `type` (and every learnset entry naming one).
func _remove_moves_of_type(type: String) -> void:
	raw.entries.moves = raw.entries.moves.filter(func(r): return r.entry.type != type)
	for rec in raw.entries.creatures:
		rec.entry.learnset = rec.entry.learnset.filter(func(l): return raw.ids("moves").has(l.move))
	db = Database.from_raw(raw)


# --- build: shape ---

func test_three_stage_line_validates_with_the_shipped_data() -> void:
	for e: Dictionary in _entries():
		raw.add_entry("creatures", e)
	assert_array(DataValidator.validate(raw)).is_empty()


func test_dex_continues_from_the_shipped_maximum_and_stays_contiguous() -> void:
	var top := _max_dex()
	var nums: Array = []
	for id in db.ids("creatures"):
		nums.append(db.creature(id).dex)
	var new_dex: Array = _entries().map(func(e: Dictionary) -> int: return e.dex)
	assert_array(new_dex).is_equal([top + 1, top + 2, top + 3])
	nums.append_array(new_dex)
	nums.sort()
	assert_array(nums).is_equal(range(1, nums.size() + 1))


func test_ids_names_and_growth_chain() -> void:
	var es := _entries()
	assert_array(es.map(func(e): return e.id)).is_equal(["wisp_1", "wisp_2", "wisp_3"])
	assert_array(es.map(func(e): return e.name)).is_equal(["Wisp 1", "Wisp 2", "Wisp 3"])
	assert_array(es[0].growth).is_equal([{"level": 16, "default": true, "into": "wisp_2"}])
	assert_array(es[1].growth).is_equal([{"level": 32, "default": true, "into": "wisp_3"}])
	assert_bool(es[2].has("growth")).is_false()
	assert_str(es[0].description).is_equal("A new species. Replace this description.")


func test_one_stage_has_no_growth() -> void:
	var es := _entries("solo", ["water"], 1)
	assert_int(es.size()).is_equal(1)
	assert_bool(es[0].has("growth")).is_false()


func test_two_stages_has_one_growth_entry() -> void:
	var es := _entries("duo", ["water"], 2)
	assert_int(es.size()).is_equal(2)
	assert_array(es[0].growth).is_equal([{"level": 16, "default": true, "into": "duo_2"}])
	assert_bool(es[1].has("growth")).is_false()


func test_stats_rise_ten_per_stage() -> void:
	var es := _entries()
	assert_int(es[0].base_stats.size()).is_equal(9)
	for s: String in es[0].base_stats:
		assert_array([es[0].base_stats[s], es[1].base_stats[s], es[2].base_stats[s]]).is_equal([50, 60, 70])


func test_every_affinity_gets_a_passive() -> void:
	var e: Dictionary = _entries("a", ["fire"], 1)[0]
	assert_array(e.affinity_passives.keys()).contains_exactly_in_any_order(Array(db.ids("affinities")))


func test_one_passive_is_assigned() -> void:
	assert_int(_entries("a", ["fire"], 1)[0].passives.size()).is_equal(1)


func test_no_affinities_means_no_affinity_passives() -> void:
	raw.entries.erase("affinities")
	for rec in raw.entries.creatures:
		rec.entry.erase("affinity_passives")
	db = Database.from_raw(raw)
	assert_bool(_entries("a", ["fire"], 1)[0].has("affinity_passives")).is_false()


# --- build: the learnset ---

func test_first_type_picks_the_level_one_move() -> void:
	var fire: Dictionary = _entries("a", ["fire"], 1)[0]
	assert_str(db.move(fire.learnset[0].move).type).is_equal("fire")
	assert_int(fire.learnset[0].level).is_equal(1)
	assert_int(fire.learnset[1].level).is_equal(8)
	assert_str(fire.learnset[1].move).is_not_equal(fire.learnset[0].move)
	var mixed: Dictionary = _entries("b", ["ghost", "fire"], 1)[0]
	assert_str(db.move(mixed.learnset[0].move).type).is_equal("ghost")


func test_a_type_without_moves_falls_back_to_a_neutral_move() -> void:
	_remove_moves_of_type("light")
	var e: Dictionary = _entries("lite", ["light"], 1)[0]
	assert_str(db.move(e.learnset[0].move).type).is_equal("neutral")


func test_second_type_is_used_when_the_first_has_no_moves() -> void:
	_remove_moves_of_type("light")
	var e: Dictionary = _entries("lite", ["light", "fire"], 1)[0]
	assert_str(db.move(e.learnset[0].move).type).is_equal("fire")


func test_too_few_distinct_moves_is_rejected() -> void:
	raw.entries.moves = [raw.entries.moves[0]]
	db = Database.from_raw(raw)
	var r := _build("wisp", ["fire"], 1)
	assert_bool(r.ok).is_false()
	assert_str(r.error).contains("two moves")


# --- build: rejections ---

func test_bad_names_are_rejected() -> void:
	for bad: String in ["Wisp", "wi sp", "1wisp", ""]:
		var r := _build(bad)
		assert_bool(r.ok).override_failure_message("'%s'" % bad).is_false()
		assert_str(r.error).override_failure_message("'%s'" % bad).contains("snake_case")


func test_bad_types_are_rejected() -> void:
	assert_str(_build("wisp", ["nope"]).error).contains("unknown type 'nope'")
	assert_str(_build("wisp", []).error).contains("types must be")
	assert_str(_build("wisp", ["fire", "water", "grass"]).error).contains("types must be")
	assert_str(_build("wisp", ["fire", "fire"]).error).contains("twice")


func test_bad_stage_counts_are_rejected() -> void:
	assert_str(_build("wisp", ["fire"], 0).error).contains("stages must be")
	assert_str(_build("wisp", ["fire"], 4).error).contains("stages must be")


func test_a_name_whose_ids_already_exist_is_rejected() -> void:
	for e: Dictionary in _entries("emberkit"):
		raw.add_entry("creatures", e)
	var again := SpeciesScaffold.build(Database.from_raw(raw), "emberkit", ["fire"], 3)
	assert_bool(again.ok).is_false()
	assert_str(again.error).contains("emberkit_1")


# --- build: no side effects, output ---

func test_build_leaves_the_data_unchanged() -> void:
	var before_ids := {}
	for cat in ["moves", "passives", "creatures"]:
		before_ids[cat] = Array(db.ids(cat))
	var before_stats: Dictionary = db.creature("emberkit").base_stats.duplicate()
	_build()
	for cat: String in before_ids:
		assert_array(Array(db.ids(cat))).override_failure_message(cat).is_equal(before_ids[cat])
	assert_dict(db.creature("emberkit").base_stats).is_equal(before_stats)
	assert_bool(db.has("creatures", "wisp_1")).is_false()


func test_to_json_round_trips() -> void:
	var parsed: Variant = JSON.parse_string(SpeciesScaffold.to_json(_build().doc))
	assert_int(int(parsed.schema)).is_equal(1)
	assert_int(parsed.entries.size()).is_equal(3)


# --- write_line: the runner's logic ---

func test_write_line_writes_a_valid_file_and_refuses_to_overwrite() -> void:
	var r := SpeciesScaffold.write_line(raw, TMP, "wisp", ["fire"], 2)
	assert_bool(r.ok).override_failure_message(str(r.get("error", ""))).is_true()
	assert_bool(FileAccess.file_exists(TMP.path_join("wisp_line.json"))).is_true()
	var again := SpeciesScaffold.write_line(raw, TMP, "wisp", ["fire"], 2)
	assert_bool(again.ok).is_false()
	assert_str(again.error).contains("already exists")


func test_write_line_leaves_the_callers_raw_data_unchanged() -> void:
	var count: int = raw.get_entries("creatures").size()
	SpeciesScaffold.write_line(raw, TMP, "wisp", ["fire"], 2)
	assert_int(raw.get_entries("creatures").size()).is_equal(count)


func test_write_line_writes_nothing_when_the_result_would_not_validate() -> void:
	# A duplicate id in the existing data makes the combined data invalid, whatever the new line is.
	raw.add_entry("creatures", raw.get_entries("creatures")[0].entry.duplicate(true))
	var r := SpeciesScaffold.write_line(raw, TMP, "wisp", ["fire"], 1)
	assert_bool(r.ok).is_false()
	assert_str(r.error).contains("would not validate")
	assert_bool(FileAccess.file_exists(TMP.path_join("wisp_line.json"))).is_false()
