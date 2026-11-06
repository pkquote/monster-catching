extends GdUnitTestSuite
## EffectText wording (shared with the compendium and in-game text).

var _db: Database


func before_test() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data")
	assert_bool(result.ok()).is_true()
	_db = result.db


## The lowest legal value for each field of an op, refs pointing at real ids.
func _minimal_effect(op: String) -> Dictionary:
	var e: Dictionary = {"op": op}
	var fields: Dictionary = DataSchemas.EFFECT_OPS[op]
	for key: String in fields:
		var rule: Dictionary = fields[key]
		match rule.t:
			"int", "number":
				e[key] = rule.min
			"ref":
				e[key] = _db.ids(rule.cat)[0]
			"enum":
				e[key] = rule["values"][0]
	return e


func test_every_effect_op_has_wording() -> void:
	for op: String in DataSchemas.EFFECT_OPS:
		var text: String = EffectText.effect(_db, _minimal_effect(op))
		assert_bool(text.is_empty()).override_failure_message("no wording for op %s" % op).is_false()
		assert_bool(text == op).override_failure_message("raw op name as wording for %s" % op).is_false()
		if "_" in op:
			assert_bool(text.contains(op)).override_failure_message("raw op name in wording for %s: %s" % [op, text]).is_false()


func test_known_sentences() -> void:
	assert_str(EffectText.effect(_db, {"op": "heal", "fraction": 0.33})).is_equal("Heals 33% max HP")
	assert_str(EffectText.effect(_db, {"op": "restore_energy", "fraction": 0.5})).is_equal("Restores 50% max energy")
	assert_str(EffectText.effect(_db, {"op": "capture", "mult": 0.8, "field_bonus": {"overgrown": 2.5}})) \
		.is_equal("Capture x0.8, x2.5 on Overgrown")
	assert_str(EffectText.effect(_db, {"op": "apply_status", "status": "burn", "chance": 10})).is_equal("Inflicts Burn (10%)")
	assert_str(EffectText.effect(_db, {"op": "apply_status", "status": "shock", "chance": 30, "target": "all_allies"})) \
		.is_equal("Inflicts Shock (30%) → all allies")
	assert_str(EffectText.effect(_db, {"op": "type_power", "type": "water", "mult": 1.2})).is_equal("Water moves x1.2")
	assert_str(EffectText.effect(_db, {"op": "incoming_type_mod", "type": "water", "mult": 0.5})).is_equal("Water damage taken x0.5")
	assert_str(EffectText.effect(_db, {"op": "field_boost", "stacks": 1})).is_equal("Its field states get +1 stack(s)")
	assert_str(EffectText.effect(_db, {"op": "field_boost", "turns": 1})).is_equal("Its field states get +1 round(s)")
	assert_str(EffectText.effect(_db, {"op": "type_power", "type": "fire", "mult": 1.5, "when": {"hp_below": 0.34}})) \
		.is_equal("Fire moves x1.5 [HP below 34%]")


func _check(effect: Dictionary, expected: String) -> void:
	assert_str(EffectText.effect(_db, effect)).is_equal(expected)


func test_remaining_op_sentences() -> void:
	_check({"op": "damage", "power": 40, "type": "fire"}, "Damage (power 40 Fire)")
	_check({"op": "damage_fraction", "fraction": 0.125}, "Loses 12.5% max HP each round")
	_check({"op": "skip_chance", "chance": 25}, "25% chance to lose its action")
	_check({"op": "bonus_if_field", "side": "own", "state": "soaked", "mult": 1.5}, "x1.5 if own side is Soaked")
	_check({"op": "stat_stage", "stat": "patk", "stages": -1}, "P.Atk -1")
	_check({"op": "stat_stage", "stat": "spd", "stages": 2}, "Spd +2")
	_check({"op": "stat_mod", "stat": "pdef", "mult": 1.3}, "P.Def x1.3")
	_check({"op": "absorb_type", "type": "water", "fraction": 0.25}, "Water damage heals 25% max HP instead")
	_check({"op": "status_immune", "status": "daze"}, "Can't be given Daze")
	_check({"op": "guard_stages", "stat": "patk"}, "Foes can't lower its P.Atk")
	_check({"op": "field_shelter", "state": "soaked"}, "Sheltered from Soaked")
	_check({"op": "reaction_power", "mult": 1.5}, "Reactions it triggers x1.5")
	_check({"op": "energy_discount", "type": "fire", "amount": 2}, "Fire moves cost 2 less")
	_check({"op": "rest_bonus", "fraction": 0.1}, "Rest restores +10% max energy")
	_check({"op": "scrap_power", "mult": 1.5}, "Scrap x1.5")
	_check({"op": "encounter_rate", "mult": 0.8}, "Wild encounter rate x0.8")
	_check({"op": "xp_mult", "mult": 1.1}, "XP earned x1.1")
	_check({"op": "bond_gain", "mult": 1.5}, "Bond gains x1.5")
	_check({"op": "remove_field_state", "side": "enemy", "state": "soaked"}, "Clears Soaked from the enemy side")
	_check({"op": "reset_training"}, "Returns all spent training points (field use only)")
	_check({"op": "apply_field_state", "side": "own", "state": "soaked", "stacks": 2, "turns": 3},
		"Applies Soaked to own side (2 stacks, 3 rounds)")


func test_optional_fields_absent() -> void:
	_check({"op": "damage"}, "Damage")
	_check({"op": "damage", "scale_with_stacks": true}, "Damage, scales with stacks consumed")
	_check({"op": "remove_field_state", "side": "enemy"}, "Clears all states from the enemy side")
	_check({"op": "incoming_type_mod", "mult": 0.75}, "All damage taken x0.75")
	_check({"op": "bonus_if_field", "side": "own", "state": "soaked", "mult": 2.0, "consume": true},
		"x2 if own side is Soaked (consumes it)")
	_check({"op": "bonus_if_field", "side": "own", "state": "soaked", "mult": 2.0, "consume": false},
		"x2 if own side is Soaked")
	_check({"op": "capture", "mult": 1.5}, "Capture x1.5")
	_check({"op": "energy_discount", "amount": 2}, "All moves cost 2 less")
	_check({"op": "guard_stages"}, "Foes can't lower its stats")
	_check({"op": "status_immune"}, "Can't be given a status")
	_check({"op": "apply_field_state", "side": "own", "state": "soaked"}, "Applies Soaked to own side")
	_check({"op": "apply_status", "status": "burn"}, "Inflicts Burn")
	# Oddity pinned as-is: with neither stacks nor turns the sentence ends in a trailing space.
	_check({"op": "field_boost"}, "Its field states get ")
	_check({"op": "field_boost", "stacks": 1, "turns": 2}, "Its field states get +1 stack(s) and +2 round(s)")


func test_when_conditions() -> void:
	assert_str(EffectText.when(_db, {"hp_below": 0.5})).is_equal("HP below 50%")
	assert_str(EffectText.when(_db, {"underdog": true})).is_equal("outnumbered")
	assert_str(EffectText.when(_db, {"field": "overgrown", "side": "own"})).is_equal("Overgrown on own side")
	assert_str(EffectText.when(_db, {"hp_below": 0.25, "underdog": true, "field": "soaked", "side": "enemy"})) \
		.is_equal("HP below 25%, outnumbered, Soaked on the enemy side")
	assert_str(EffectText.when(_db, {})).is_equal("")


func test_triggers_text() -> void:
	var hit: Array = [{"on": "hit", "contact": true, "chance": 30, "when": {"hp_below": 0.5},
		"effects": [{"op": "apply_status", "status": "chill"}]}]
	assert_str(EffectText.triggers(_db, hit)).is_equal("On being hit (physical) (30%) [HP below 50%]: Inflicts Chill")
	var enter: Array = [{"on": "enter", "contact": false, "chance": 100, "when": {},
		"effects": [{"op": "apply_field_state", "side": "own", "state": "overgrown"}]}]
	assert_str(EffectText.triggers(_db, enter)).is_equal("On entering: Applies Overgrown to own side")


func test_empty_list_is_dash() -> void:
	assert_str(EffectText.effects(_db, [])).is_equal("—")
	assert_str(EffectText.triggers(_db, [])).is_equal("—")
