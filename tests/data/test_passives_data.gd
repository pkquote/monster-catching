extends GdUnitTestSuite
## Passive content: shipped data, parsing and validator rules.

const TRACKS := ["striker", "warden", "catalyst", "trickster"]

var db: Database


func before() -> void:
	db = DataLoader.load_database("res://data", "res://dialogue").db


func _errors_with_passive(passive: Dictionary) -> String:
	var raw := FixtureDB.raw()
	raw.add_entry("passives", passive)
	return "\n".join(DataValidator.validate(raw))


func test_all_species_have_passives() -> void:
	assert_int(db.count("passives")).is_greater(0)
	for id in db.ids("creatures"):
		var c := db.creature(id)
		assert_int(c.passives.size()).is_between(1, 2)
		for pid in c.passives:
			assert_object(db.passive(pid)).is_not_null()


func test_shared_affinity_passives_listed() -> void:
	for id in db.ids("creatures"):
		var c := db.creature(id)
		for track in TRACKS:
			assert_bool(c.affinity_passives.has(track)).is_true()
			assert_object(db.passive(c.affinity_passives[track])).is_not_null()


func test_passive_def_parses() -> void:
	var p := db.passive("tidal_heart")
	assert_str(p.name).is_equal("Tidal Heart")
	assert_str(p.scope).is_equal("self")
	assert_int(p.effects.size()).is_equal(1)
	assert_str(p.effects[0].op).is_equal("type_power")
	assert_float(p.effects[0].mult).is_equal(1.2)
	assert_array(p.triggers).is_empty()
	assert_str(db.passive("guardian_aura").scope).is_equal("allies")
	var undertow := db.passive("undertow")
	assert_str(undertow.triggers[0].on).is_equal("enter")
	assert_int(undertow.triggers[0].chance).is_equal(100)
	assert_float(undertow.field[0].mult).is_equal(0.8)


func test_validator_rejects_bad_passive_data() -> void:
	assert_str(_errors_with_passive({"id": "bad", "name": "Bad",
		"effects": [{"op": "explode"}]})).contains(
		"[passives:bad] effects[0].op: unknown effect op \"explode\"")
	assert_str(_errors_with_passive({"id": "bad", "name": "Bad",
		"triggers": [{"on": "sneeze", "effects": [{"op": "heal", "fraction": 0.1}]}]})).contains(
		"[passives:bad] triggers[0].on: expected one of [\"enter\", \"hit\", \"round_end\", \"knockout\", \"faint\", \"status\"] (got \"sneeze\")")
	assert_str(_errors_with_passive({"id": "bad", "name": "Bad",
		"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1, "when": {"mood": true}}]})).contains(
		"[passives:bad] effects[0].when.mood: unknown field")
	assert_str(_errors_with_passive({"id": "bad", "name": "Bad"})).contains(
		"[passives:bad]: needs at least one of effects, triggers or field")
	assert_str(_errors_with_passive({"id": "bad", "name": "Bad",
		"triggers": [{"on": "enter", "chance": 0, "effects": [{"op": "heal", "fraction": 0.1}]}]})).contains(
		"[passives:bad] triggers[0].chance: must be >= 1")


func test_validator_rejects_species_without_passives() -> void:
	var raw := FixtureDB.raw()
	raw.entries.creatures[0].entry.erase("passives")
	assert_str("\n".join(DataValidator.validate(raw))).contains(
		"[creatures:blob] passives: missing required field")
