extends GdUnitTestSuite
## Validator rules, exercised on small in-memory RawData sets.


func _base() -> RawData:
	var raw := RawData.new()
	raw.add_entry("types", {"id": "water", "name": "Water", "description": "Wet.",
		"pros": ["Splashy"], "cons": ["Soggy"]})
	for aff in ["striker", "warden", "catalyst", "trickster"]:
		raw.add_entry("affinities", {"id": aff, "name": aff.capitalize()})
	raw.add_entry("statuses", {"id": "burn", "name": "Burn", "turns": 3,
		"effects": [{"op": "damage_fraction", "fraction": 0.1}]})
	raw.add_entry("field_states", {"id": "soaked", "name": "Soaked", "max_stacks": 3, "default_turns": 3})
	raw.add_entry("field_states", {"id": "charged", "name": "Charged", "max_stacks": 3, "default_turns": 3})
	raw.add_entry("reactions", {"id": "conduction", "name": "Conduction",
		"inputs": ["charged", "soaked"], "consumes": ["charged"], "scope": "side",
		"effects": [{"op": "damage", "power": 40, "target": "all_allies"}]})
	raw.add_entry("passives", {"id": "steady", "name": "Steady",
		"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.0}]})
	raw.add_entry("moves", _move())
	raw.add_entry("moves", _move({"id": "scrap", "name": "Scrap", "cost": 0}))  # balance fallback_move
	raw.add_entry("creatures", _creature())
	raw.set_single("balance", FixtureDB.balance())
	return raw


func _move(overrides: Dictionary = {}) -> Dictionary:
	var m := {"id": "splash", "name": "Splash", "type": "water", "category": "physical",
		"power": 40, "cost": 2, "accuracy": 100, "target": "one_enemy", "effects": [{"op": "damage"}]}
	m.merge(overrides, true)
	return m


func _creature(overrides: Dictionary = {}) -> Dictionary:
	var c := {"id": "pup", "name": "Pup", "types": ["water"],
		"base_stats": FixtureDB.FLAT.duplicate(),
		"catch_rate": 0.5, "xp_yield": 50,
		"learnset": [{"level": 1, "move": "splash"}], "passives": ["steady"]}
	c.merge(overrides, true)
	return c


func _errors_for(raw: RawData) -> String:
	return "\n".join(DataValidator.validate(raw))


func test_minimal_valid_set_passes() -> void:
	assert_array(Array(DataValidator.validate(_base()))).is_empty()


func test_missing_required_field() -> void:
	var raw := _base()
	var c := _creature()
	c.erase("xp_yield")
	raw.entries.creatures[0].entry = c
	assert_str(_errors_for(raw)).contains("[creatures:pup] xp_yield: missing required field")


func test_unknown_field_is_an_error() -> void:
	var raw := _base()
	raw.entries.moves[0].entry = _move({"powr": 10})
	assert_str(_errors_for(raw)).contains("powr: unknown field")


func test_broken_reference() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"learnset": [{"level": 1, "move": "nope"}]})
	assert_str(_errors_for(raw)).contains("unknown moves id 'nope'")


func test_duplicate_ids() -> void:
	var raw := _base()
	raw.add_entry("moves", _move(), "data/moves/other.json")
	assert_str(_errors_for(raw)).contains("duplicate id")


func test_types_need_summary_fields() -> void:
	var raw := _base()
	raw.add_entry("types", {"id": "fire", "name": "Fire", "pros": []})
	var errs := _errors_for(raw)
	assert_str(errs).contains("[types:fire] description: missing required field")
	assert_str(errs).contains("[types:fire] pros: expected at least 1 element(s)")
	assert_str(errs).contains("[types:fire] cons: missing required field")


func test_bad_id_format() -> void:
	var raw := _base()
	raw.add_entry("types", {"id": "Fire Type", "name": "Fire"})
	assert_str(_errors_for(raw)).contains("snake_case")


func test_integer_and_range_checks() -> void:
	var raw := _base()
	raw.entries.moves[0].entry = _move({"accuracy": 150, "power": 12.5})
	var errs := _errors_for(raw)
	assert_str(errs).contains("accuracy: must be <= 100")
	assert_str(errs).contains("power: expected integer")


func test_unknown_effect_op() -> void:
	var raw := _base()
	raw.entries.moves[0].entry = _move({"effects": [{"op": "explode"}]})
	assert_str(_errors_for(raw)).contains("unknown effect op \"explode\"")


func test_effect_op_fields_are_checked() -> void:
	var raw := _base()
	raw.entries.moves[0].entry = _move({"effects": [
		{"op": "apply_field_state", "side": "enemy", "state": "lava"}]})
	assert_str(_errors_for(raw)).contains("unknown field_states id 'lava'")


func test_status_move_power_rule() -> void:
	var raw := _base()
	raw.entries.moves[0].entry = _move({"category": "status", "power": 40})
	assert_str(_errors_for(raw)).contains("status moves must have power 0")


func test_learnset_needs_level_one_move() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"learnset": [{"level": 5, "move": "splash"}]})
	assert_str(_errors_for(raw)).contains("needs at least one level-1 move")


func test_growth_branch_rules() -> void:
	var raw := _base()
	raw.add_entry("creatures", _creature({"id": "big_pup", "name": "Big Pup"}))
	raw.entries.creatures[0].entry = _creature({"growth": [
		{"level": 16, "into": "big_pup"},  # neither affinity nor default
		{"level": 16, "default": true, "into": "pup"},  # grows into itself
	]})
	var errs := _errors_for(raw)
	assert_str(errs).contains("exactly one of 'affinity' or 'default: true'")
	assert_str(errs).contains("cannot grow into itself")


func test_reaction_consumes_must_be_inputs() -> void:
	var raw := _base()
	raw.entries.reactions[0].entry.consumes = ["soaked", "charged"]
	assert_array(Array(DataValidator.validate(raw))).is_empty()
	raw.add_entry("field_states", {"id": "frosted", "name": "Frosted", "max_stacks": 1, "default_turns": 2})
	raw.entries.reactions[0].entry.consumes = ["frosted"]
	assert_str(_errors_for(raw)).contains("'frosted' is not one of the inputs")


func test_missing_balance_file() -> void:
	var raw := _base()
	raw.singles.erase("balance")
	assert_str(_errors_for(raw)).contains("balance.json: missing required file")


func test_dialogue_battle_references() -> void:
	var raw := _base()
	raw.dialogue_files["res://dialogue/x.dialogue"] = "do await Story.start_battle(\"ghost_tamer\")"
	assert_str(_errors_for(raw)).contains("unknown tamer id 'ghost_tamer'")


func test_minigame_scene_must_exist() -> void:
	var raw := _base()
	raw.add_entry("minigames", {"id": "qd", "name": "Quick Draw", "scene": "res://nowhere/missing.tscn"})
	assert_str(_errors_for(raw)).contains("scene file not found")
	raw = _base()
	raw.add_entry("minigames", {"id": "qd", "name": "Quick Draw", "scene": "res://game/overworld/overworld.tscn"})
	assert_array(Array(DataValidator.validate(raw))).is_empty()
