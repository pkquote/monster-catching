extends GdUnitTestSuite
## Coverage guard for the test content pack (spec 2026-11-05-test-content-pack-design.md sections 1 and 4):
## PackCoverage finds nothing uncovered in any family over the real data/ plus data_testpack/, and the
## pack sizes stay at or above floors derived from the spec's targets (growing the pack is fine). One test per family, so a failure names it.

const PACK_ROOT: String = "res://data_testpack"
## Spec section 1 "Size": about 30 creatures, 100 moves, 25 items, 35 passives, 6 tamers, 4 encounter
## tables. These are lower bounds (roughly 90% of each target); there is no upper bound.
const SIZE_FLOORS: Dictionary = {"creatures": 28, "moves": 90, "items": 23, "passives": 30, "tamers": 6,
	"encounters": 4}

var _db: Database
var _report: Dictionary = {}


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert_array(Array(result.errors)).is_empty()
	_db = result.db
	var errors: PackedStringArray = PackedStringArray()
	var raw: RawData = DataLoader.read_raw("res://data", errors)
	DataLoader.read_raw(PACK_ROOT, errors, raw, true)
	assert_array(Array(errors)).is_empty()
	_report = PackCoverage.report(raw)


func _assert_family_covered(family: String) -> void:
	assert_bool(_report.has(family)).override_failure_message("report lacks family " + family).is_true()
	var missing: Array = Array(_report.get(family, PackedStringArray(["<missing family>"])))
	assert_array(missing).override_failure_message("uncovered %s: %s" % [family, str(missing)]).is_empty()


func _pack_count(category: String) -> int:
	var n: int = 0
	for id: String in _db.ids(category):
		if Database.is_test_content(id):
			n += 1
	return n


# --- one test per PackCoverage family -----------------------------------------------

func test_report_lists_exactly_the_known_families() -> void:
	# A family added to PackCoverage without a test below fails here.
	var expected: Array = ["effect_ops", "move_targets", "trigger_on", "when_keys", "use_kinds", "types_single",
		"types_dual_count", "statuses", "field_states"]
	assert_array(Array(PackCoverage.FAMILIES)).contains_exactly_in_any_order(expected)
	assert_array(_report.keys()).contains_exactly_in_any_order(expected)


func test_effect_ops_covered() -> void:
	_assert_family_covered("effect_ops")


func test_move_targets_covered() -> void:
	_assert_family_covered("move_targets")


func test_trigger_on_covered() -> void:
	_assert_family_covered("trigger_on")


func test_when_keys_covered() -> void:
	_assert_family_covered("when_keys")


func test_use_kinds_covered() -> void:
	_assert_family_covered("use_kinds")


func test_types_single_covered() -> void:
	_assert_family_covered("types_single")


func test_types_dual_count_covered() -> void:
	_assert_family_covered("types_dual_count")


func test_statuses_covered() -> void:
	_assert_family_covered("statuses")


func test_field_states_covered() -> void:
	_assert_family_covered("field_states")


func test_report_is_not_vacuous() -> void:
	# The families are judged against non-empty requirement lists.
	assert_int(DataSchemas.EFFECT_OPS.size()).is_greater(10)
	assert_int(DataSchemas.MOVE_TARGETS.size()).is_equal(9)
	assert_int(DataSchemas.TRIGGER_ON.size()).is_equal(5)
	assert_int(_db.ids("types").size()).is_equal(14)
	assert_int(_db.ids("statuses").size()).is_greater(0)
	assert_int(_db.ids("field_states").size()).is_greater(0)


# --- sizes (spec section 1, within 10%) -------------------------------------------------------

func _assert_size(category: String) -> void:
	var floor_: int = int(SIZE_FLOORS[category])
	var have: int = _pack_count(category)
	assert_int(have).override_failure_message("%s: pack has %d, floor %d" % [category, have, floor_]) 		.is_greater_equal(floor_)


func test_size_creatures() -> void:
	_assert_size("creatures")


func test_size_moves() -> void:
	_assert_size("moves")


func test_size_items() -> void:
	_assert_size("items")


func test_size_passives() -> void:
	_assert_size("passives")


func test_size_tamers() -> void:
	_assert_size("tamers")


func test_size_encounters() -> void:
	_assert_size("encounters")


func test_size_targets_cover_every_pack_category() -> void:
	var cats: Array = SIZE_FLOORS.keys()
	assert_int(cats.size()).is_equal(6)
	for cat: String in cats:
		assert_int(_pack_count(cat)).override_failure_message("no pack " + cat).is_greater(0)
