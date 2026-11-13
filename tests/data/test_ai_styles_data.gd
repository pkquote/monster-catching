extends GdUnitTestSuite
## AI styles are content: data/ai_styles.json is validated, loaded into the Database as AiStyleDef, and a tamer's
## `ai` refers to one (optional, defaulting to basic).

const FIELDS := ["random", "damage", "ko", "retaliation", "setup", "buff", "heal", "rest", "trigger_setup",
	"seeks_status", "attack", "swap", "swap_margin", "swap_avoid"]

## The spec's table, one row per style, in FIELDS order.
const ROWS := {
	"basic": [true, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, true, "best", false, 0.25, 1.0],
	"aggressive": [false, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.5, false, "best", false, 0.25, 1.0],
	"tactician": [false, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, true, "best", true, 0.25, 1.0],
	"passive": [false, 1.0, 0.0, 1.0, 1.0, 1.0, 1.5, 2.0, 1.0, true, "weakest", false, 0.25, 1.0],
	"defensive": [false, 0.7, 1.0, 1.5, 0.5, 0.5, 1.5, 1.5, 1.0, true, "best", true, 0.1, 1.5],
	"trickster": [false, 0.6, 1.0, 1.0, 1.5, 0.5, 1.0, 1.0, 1.0, true, "best", false, 0.25, 1.0],
}

var db: Database


func before() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	assert(result.errors.is_empty(), "Shipped data invalid:\n" + "\n".join(result.errors))
	db = result.db


func _style(overrides: Dictionary = {}) -> Dictionary:
	var s := {"id": "odd", "name": "Odd"}
	for i in FIELDS.size():
		s[FIELDS[i]] = ROWS.tactician[i]
	s.merge(overrides, true)
	return s


func _errors_with_style(style: Dictionary) -> String:
	var raw := FixtureDB.raw()
	raw.add_entry("ai_styles", style)
	return "\n".join(DataValidator.validate(raw))


func _errors_with_tamer(tamer: Dictionary) -> String:
	var raw := FixtureDB.raw()
	raw.add_entry("tamers", tamer)
	return "\n".join(DataValidator.validate(raw))


func _tamer(extra: Dictionary) -> Dictionary:
	var t := {"id": "rival", "name": "Rival", "max_active": 1, "reward_money": 1,
		"party": [{"species": "blob", "level": 5}]}
	t.merge(extra, true)
	return t


func test_the_existing_styles_match_the_table() -> void:
	for id in ROWS:
		var s := db.ai_style(id)
		assert_object(s).is_not_null()
		for i in FIELDS.size():
			assert_that(s.get(FIELDS[i])).override_failure_message("%s.%s" % [id, FIELDS[i]]).is_equal(ROWS[id][i])


func test_ai_style_is_a_def_and_unknown_is_null() -> void:
	assert_object(db.ai_style("tactician")).is_instanceof(AiStyleDef)
	assert_str(db.ai_style("tactician").name).is_equal("Tactician")
	assert_object(db.ai_style("nope")).is_null()


func test_validator_rejects_bad_entries() -> void:
	assert_str(_errors_with_style(_style())).is_empty()
	var missing := _style()
	missing.erase("heal")
	assert_str(_errors_with_style(missing)).contains("[ai_styles:odd] heal: missing required field")
	assert_str(_errors_with_style(_style({"damage": 4.0}))).contains("damage")
	assert_str(_errors_with_style(_style({"attack": "sideways"}))).contains("attack: expected one of")
	assert_str(_errors_with_style(_style({"swap": "yes"}))).contains("swap: expected bool")


func test_tamer_ai_is_a_reference() -> void:
	assert_str(_errors_with_tamer(_tamer({"ai": "nope"}))).contains("unknown ai_styles id 'nope'")
	assert_str(_errors_with_tamer(_tamer({"ai": "aggressive"}))).is_empty()


func test_a_tamer_without_ai_uses_basic() -> void:
	assert_str(_errors_with_tamer(_tamer({}))).is_empty()
	var raw := FixtureDB.raw()
	raw.add_entry("tamers", _tamer({}))
	assert_str(Database.from_raw(raw).tamer("rival").ai).is_equal("basic")
