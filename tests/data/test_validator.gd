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


func test_field_boost_needs_stacks_or_turns() -> void:
	var bare := _base()
	bare.entries.passives[0].entry = {"id": "steady", "name": "Steady",
		"effects": [{"op": "field_boost"}]}
	assert_str(_errors_for(bare)).contains("field_boost needs at least one of: stacks, turns")
	for given: Dictionary in [{"stacks": 1}, {"turns": 2}, {"stacks": 2, "turns": 3}]:
		var ok := _base()
		var eff: Dictionary = {"op": "field_boost"}
		eff.merge(given)
		ok.entries.passives[0].entry = {"id": "steady", "name": "Steady", "effects": [eff]}
		assert_str(_errors_for(ok)).is_empty()


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


func test_reaction_must_consume_an_input() -> void:
	var raw := _base()
	raw.entries.reactions[0].entry.consumes = []
	assert_str(_errors_for(raw)).contains("must consume at least one of its inputs")
	raw.entries.reactions[0].entry.consumes = ["charged"]
	assert_array(Array(DataValidator.validate(raw))).is_empty()


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


func test_unknown_growth_tier_fails() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"growth_rates": {"patk": "fats"}})
	var errs := _errors_for(raw)
	assert_str(errs).contains("[creatures:pup]")
	assert_str(errs).contains("fats")


func test_unknown_growth_stat_fails() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"growth_rates": {"speed": "fast"}})
	assert_str(_errors_for(raw)).contains("speed")


func test_valid_growth_rates_pass() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"growth_rates": {"patk": "fast", "spd": "slow"}})
	assert_array(Array(DataValidator.validate(raw))).is_empty()


func test_steady_tier_must_exist_and_be_one() -> void:
	for tiers in [{"slow": 0.8, "fast": 1.2}, {"slow": 0.8, "steady": 1.1, "fast": 1.2}]:
		var raw := _base()
		var b := FixtureDB.balance()
		b["growth_tiers"] = tiers
		raw.set_single("balance", b)
		assert_str(_errors_for(raw)).contains("steady")


func test_tier_rounding_to_steady_fails() -> void:
	var raw := _base()
	var b := FixtureDB.balance()
	b["growth_tiers"] = {"slow": 0.8, "steady": 1.0, "fast": 1.004}
	raw.set_single("balance", b)
	var errs := _errors_for(raw)
	assert_str(errs).contains("fast")
	assert_str(errs).contains("steady")


func test_normal_tiers_pass() -> void:
	var raw := _base()
	var b := FixtureDB.balance()
	b["growth_tiers"] = {"slow": 0.8, "steady": 1.0, "fast": 1.2}
	raw.set_single("balance", b)
	assert_array(Array(DataValidator.validate(raw))).is_empty()


func test_over_budget_species_warns_without_failing() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"growth_rates": {"patk": "fast", "pdef": "fast", "spd": "fast"}})
	assert_array(Array(DataValidator.validate(raw))).is_empty()
	var warns := DataValidator.warnings(raw)
	assert_int(warns.size()).is_equal(1)
	assert_str(warns[0]).contains("[creatures:pup]")
	assert_str(warns[0]).contains("warning: growth tiers sum to 3")


func test_slow_stats_offset_fast_ones() -> void:
	var raw := _base()
	raw.entries.creatures[0].entry = _creature({"growth_rates": {
		"patk": "fast", "pdef": "fast", "spd": "fast", "hp": "slow"}})
	assert_array(Array(DataValidator.warnings(raw))).is_empty()


func test_budget_counts_position_relative_to_steady() -> void:
	var raw := _base()
	var b := FixtureDB.balance()
	b["growth_tiers"] = {"slow": 0.8, "steady": 1.0, "fast": 1.2, "turbo": 1.5}
	raw.set_single("balance", b)
	raw.entries.creatures[0].entry = _creature({"growth_rates": {"patk": "turbo", "pdef": "fast", "spd": "fast"}})
	assert_int(DataValidator.warnings(raw).size()).is_equal(1)
	# turbo counts +1, not +2: turbo + fast is 2, within budget.
	raw.entries.creatures[0].entry = _creature({"growth_rates": {"patk": "turbo", "pdef": "fast"}})
	assert_array(Array(DataValidator.warnings(raw))).is_empty()


# --- Held items -------------------------------------------------------------

func _held_item(overrides: Dictionary = {}) -> Dictionary:
	var it := {"id": "charm", "name": "Charm", "category": "held", "price": 10,
		"held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}}
	it.merge(overrides, true)
	return it


func _heal_item() -> Dictionary:
	return {"id": "tonic", "name": "Tonic", "category": "heal", "price": 5, "target": "one_ally",
		"effects": [{"op": "heal", "fraction": 0.25}]}


func _with_item(item: Dictionary) -> RawData:
	var raw := _base()
	raw.add_entry("items", item)
	return raw


func test_held_item_valid_passes() -> void:
	var items := [
		_held_item(),
		_held_item({"id": "berry", "held": {"use": "consumed", "triggers": [
			{"on": "hit", "when": {"hp_below": 0.5}, "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]}}),
		_held_item({"id": "bell", "held": {"use": "per_battle", "scope": "allies", "triggers": [
			{"on": "enter", "effects": [{"op": "stat_mod", "stat": "spd", "mult": 1.1, "target": "self"}]}]}}),
		_held_item({"id": "lure", "held": {"field": [{"op": "encounter_rate", "mult": 0.5}]}}),
	]
	for it in items:
		assert_array(Array(DataValidator.validate(_with_item(it)))).is_empty()


func test_held_block_required_for_held_category() -> void:
	var it := _held_item()
	it.erase("held")
	assert_str(_errors_for(_with_item(it))).contains("[items:charm] held: required for category 'held'")


func test_held_block_rejected_on_other_categories() -> void:
	var it := _heal_item()
	it["held"] = {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}
	assert_str(_errors_for(_with_item(it))).contains("[items:tonic] held: only allowed for category 'held'")


func test_held_block_needs_effects_triggers_or_field() -> void:
	var errs := _errors_for(_with_item(_held_item({"held": {"use": "permanent"}})))
	assert_str(errs).contains("[items:charm] held: needs at least one of effects, triggers or field")


func test_consumed_and_per_battle_need_a_trigger_and_no_effects() -> void:
	var fx := [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]
	var trig := [{"on": "hit", "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]
	for use in ["consumed", "per_battle"]:
		var errs := _errors_for(_with_item(_held_item({"held": {"use": use, "effects": fx}})))
		assert_str(errs).contains("held.use: '%s' needs at least one trigger" % use)
		errs = _errors_for(_with_item(_held_item({"held": {"use": use, "effects": fx, "triggers": trig}})))
		assert_str(errs).contains("held.effects: '%s' items cannot have always-on effects" % use)
		errs = _errors_for(_with_item(_held_item({"held": {"use": use,
			"field": [{"op": "xp_mult", "mult": 1.1}]}})))
		assert_str(errs).contains("held.use: '%s' needs at least one trigger" % use)


func test_held_item_rejects_target_and_top_level_effects() -> void:
	var errs := _errors_for(_with_item(_held_item({"target": "self",
		"effects": [{"op": "heal", "fraction": 0.25}]})))
	assert_str(errs).contains("[items:charm] target: not allowed on a held item")
	assert_str(errs).contains("[items:charm] effects: not allowed on a held item")


func test_trigger_when_is_validated() -> void:
	var raw := _base()
	raw.add_entry("passives", {"id": "grit", "name": "Grit", "triggers": [
		{"on": "hit", "when": {"hp_below": 0.5}, "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]})
	assert_array(Array(DataValidator.validate(raw))).is_empty()
	raw.add_entry("passives", {"id": "bad", "name": "Bad", "triggers": [
		{"on": "hit", "when": {"bogus": 1}, "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]})
	assert_str(_errors_for(raw)).contains("when.bogus: unknown field")


func test_tamer_held_item_must_be_a_held_item() -> void:
	var tamer := func(held: String) -> Dictionary:
		return {"id": "rival", "name": "Rival", "max_active": 1, "ai": "basic", "reward_money": 1,
			"party": [{"species": "pup", "level": 5, "held_item": held}]}
	var raw := _with_item(_heal_item())
	raw.add_entry("items", _held_item())
	raw.add_entry("tamers", tamer.call("tonic"))
	assert_str(_errors_for(raw)).contains("[tamers:rival] party[0].held_item: 'tonic' is not a held item")
	raw.entries.tamers[0].entry = tamer.call("charm")
	assert_array(Array(DataValidator.validate(raw))).is_empty()
	raw.entries.tamers[0].entry = tamer.call("nope")
	assert_str(_errors_for(raw)).contains("unknown items id 'nope'")


func test_spread_mults_rules() -> void:
	assert_array(Array(DataValidator.validate(_base()))).is_empty()
	var bad := {
		"missing 2": {"3": 0.75},
		"missing 3": {"2": 0.85},
		"above 1": {"2": 1.5, "3": 0.75},
		"3 above 2": {"2": 0.7, "3": 0.8},
	}
	for label in bad:
		var raw := _base()
		var b := FixtureDB.balance()
		b["spread_mults"] = bad[label]
		raw.set_single("balance", b)
		assert_str(_errors_for(raw)).contains("spread_mults")


# --- two_enemies target -----------------------------------------------------

func test_two_enemies_valid_on_moves_only() -> void:
	var ok := _base()
	ok.add_entry("moves", _move({"id": "twin", "name": "Twin", "target": "two_enemies"}))
	assert_array(Array(DataValidator.validate(ok))).is_empty()

	var item := _heal_item()
	item["target"] = "two_enemies"
	assert_str(_errors_for(_with_item(item))).contains("[items:tonic] target").contains("two_enemies")

	var eff := _base()
	eff.entries.moves[0].entry = _move({"effects": [{"op": "damage", "target": "two_enemies"}]})
	assert_str(_errors_for(eff)).contains("two_enemies")

	var trig := _base()
	trig.entries.passives[0].entry = {"id": "steady", "name": "Steady", "triggers": [{"on": "hit",
		"effects": [{"op": "damage", "power": 10, "target": "two_enemies"}]}]}
	assert_str(_errors_for(trig)).contains("two_enemies")
