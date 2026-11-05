class_name FixtureDB
extends RefCounted
## Small, hand-tuned content set for engine tests. Independent of data/ so
## balance changes to the real game never break tests.
##
## Every creature has flat 50 base stats unless noted, so damage is predictable.

const FLAT := {"hp": 50, "patk": 50, "pdef": 50, "satk": 50, "sdef": 50, "spd": 50,
	"luck": 50, "resolve": 50, "stamina": 50}


## FLAT with some stats changed.
static func stats(overrides: Dictionary) -> Dictionary:
	var d := FLAT.duplicate()
	d.merge(overrides, true)
	return d


static func balance() -> Dictionary:
	return {
		"level_cap": 99, "party_size": 6, "max_moves": 4, "stab": 1.25, "spread_mult": 0.75,
		"round_limit": 50, "max_field_states": 3, "growth_affinity_threshold": 10,
		# Resolve is off by default so status tests are deterministic; see build(overrides).
		"resolve": {"resist_cap": 0.0, "endure_cap": 0.0},
		"energy": {"base": 20, "rest_fraction": 0.25, "fallback_move": "scrap"},
		"training": {"points_per_level": 1, "max_per_stat": 30, "hp_per_point": 2},
		"bond": {"min": -100, "max": 100, "starter": 20, "disobey_max_chance": 0.4, "penalty_max": 0.2,
			"lash_out_threshold": -50, "lash_out_chance": 0.05, "xp_bonus_max": 0.1,
			"overwork_hp": 0.25, "overwork_energy": 0.2,
			"changes": {"battle_won": 2, "knockout": 1, "healed_item": 1, "rested": 2, "fainted": -4, "overworked": -2}},
		"underdog": {"bonus_actions_per_ratio": 1.0, "spread_reduction_per_ratio": 0.2, "spread_reduction_cap": 0.5,
			"stat_bonus_per_ratio": 0.15, "stat_bonus_cap": 0.4, "xp_bonus_per_ratio": 0.5},
		"catch": {"hp_weight": 0.8, "status_mult": 1.5},
		"overworld": {"walk_speed": 4.0, "run_speed": 7.0, "encounter_rate": 0.10, "encounter_grace_tiles": 4, "walk_energy_tiles": 8, "defeat_money_fraction": 0.10, "sell_fraction": 0.5},
		"xp": {"divisor": 5, "tamer_mult": 1.5},
		"affinity_awards": {
			"hit_dealt": {"affinity": "striker", "points": 1},
			"knockout": {"affinity": "striker", "points": 3},
			"hit_survived": {"affinity": "warden", "points": 1},
			"heal": {"affinity": "warden", "points": 2},
			"field_applied": {"affinity": "catalyst", "points": 2},
			"reaction_triggered": {"affinity": "catalyst", "points": 4},
			"field_cashed_in": {"affinity": "catalyst", "points": 1},
			"status_inflicted": {"affinity": "trickster", "points": 2},
			"stat_lowered": {"affinity": "trickster", "points": 1},
		},
	}


static func raw() -> RawData:
	var r := RawData.new()
	for t in [
		{"id": "neutral", "name": "Neutral"},
		{"id": "water", "name": "Water", "matchups": {"fire": 2.0}},
		{"id": "fire", "name": "Fire", "matchups": {"water": 0.5}},
		{"id": "electric", "name": "Electric", "matchups": {"earth": 0.0}},
		{"id": "earth", "name": "Earth"},
	]:
		t.merge({"description": "Test type.", "pros": ["Test pro"], "cons": ["Test con"]})
		r.add_entry("types", t)
	for a in ["striker", "warden", "catalyst", "trickster"]:
		r.add_entry("affinities", {"id": a, "name": a.capitalize()})
	r.add_entry("statuses", {"id": "burn", "name": "Burn", "turns": 2,
		"effects": [{"op": "damage_fraction", "fraction": 0.125}]})
	r.add_entry("statuses", {"id": "shock", "name": "Shock", "turns": 2,
		"effects": [{"op": "skip_chance", "chance": 100}]})
	r.add_entry("statuses", {"id": "chill", "name": "Chill", "turns": 3,
		"effects": [{"op": "stat_mod", "stat": "spd", "mult": 0.5}]})
	r.add_entry("field_states", {"id": "soaked", "name": "Soaked", "max_stacks": 3, "default_turns": 3,
		"passive": [{"op": "incoming_type_mod", "type": "electric", "mult": 1.5}]})
	r.add_entry("field_states", {"id": "charged", "name": "Charged", "max_stacks": 3, "default_turns": 3})
	r.add_entry("field_states", {"id": "scorched", "name": "Scorched", "max_stacks": 3, "default_turns": 3})
	r.add_entry("field_states", {"id": "frosted", "name": "Frosted", "max_stacks": 3, "default_turns": 3})
	r.add_entry("field_states", {"id": "overgrown", "name": "Overgrown", "max_stacks": 3, "default_turns": 2,
		"passive": [{"op": "stat_mod", "stat": "spd", "mult": 0.5}]})
	r.add_entry("reactions", {"id": "conduction", "name": "Conduction", "inputs": ["charged", "soaked"],
		"consumes": ["charged"], "scope": "side",
		"effects": [{"op": "damage", "power": 40, "type": "electric", "scale_with_stacks": true, "target": "all_allies"}]})
	r.add_entry("reactions", {"id": "steam", "name": "Steam", "inputs": ["scorched", "frosted"],
		"consumes": ["scorched", "frosted"], "scope": "both_sides",
		"effects": [{"op": "stat_stage", "stat": "acc", "stages": -1, "target": "all"}]})
	r.add_entry("reactions", {"id": "wildfire", "name": "Wildfire", "inputs": ["scorched", "overgrown"],
		"consumes": ["overgrown"], "scope": "side",
		"effects": [{"op": "apply_status", "status": "burn", "target": "all_allies"}]})

	var moves := [
		_m("hit", "neutral", "physical", 50, 100, "one_enemy", [{"op": "damage"}]),
		_m("splash", "water", "physical", 50, 100, "one_enemy", [{"op": "damage"}]),
		_m("zap", "electric", "special", 50, 100, "one_enemy", [{"op": "damage"}]),
		_m("wave", "water", "special", 40, 100, "all_enemies", [{"op": "damage"}]),
		_m("quake", "earth", "physical", 50, 100, "all", [{"op": "damage"}]),
		_m("quick_jab", "neutral", "physical", 30, 100, "one_enemy", [{"op": "damage"}], {"priority": 1}),
		_m("wild_swing", "neutral", "physical", 50, 1, "one_enemy", [{"op": "damage"}]),
		_m("riptide", "water", "physical", 50, 100, "one_enemy", [
			{"op": "bonus_if_field", "side": "target", "state": "soaked", "mult": 2.0, "consume": true},
			{"op": "damage"}]),
		_side_move("drench", "water", "soaked"),
		_side_move("charge_up", "electric", "charged"),
		_side_move("scorch", "fire", "scorched"),
		_side_move("frost", "water", "frosted"),
		_side_move("grow", "neutral", "overgrown"),
		_m("sweep", "earth", "status", 0, 100, "own_side", [{"op": "remove_field_state", "side": "own"}], {"always_hits": true}),
		_m("burn_touch", "fire", "status", 0, 100, "one_enemy", [{"op": "apply_status", "status": "burn"}], {"always_hits": true}),
		_m("jolt", "electric", "status", 0, 100, "one_enemy", [{"op": "apply_status", "status": "shock"}], {"always_hits": true}),
		_m("growl", "neutral", "status", 0, 100, "all_enemies", [{"op": "stat_stage", "stat": "patk", "stages": -1}], {"always_hits": true}),
		_m("mend", "neutral", "status", 0, 100, "self", [{"op": "heal", "fraction": 0.5}], {"always_hits": true}),
		_m("scrap", "neutral", "physical", 25, 100, "one_enemy", [{"op": "damage"}], {"cost": 0}),
		_m("blast", "neutral", "special", 50, 100, "one_enemy", [{"op": "damage"}]),
		_m("big_hit", "neutral", "physical", 90, 100, "one_enemy", [{"op": "damage"}], {"cost": 25}),
	]
	for m in moves:
		r.add_entry("moves", m)

	# A harmless passive so every fixture species validates; battle-test numbers stay unchanged.
	r.add_entry("passives", {"id": "steady", "name": "Steady", "description": "Test passive with no real effect.",
		"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.0}]})
	r.add_entry("creatures", _c("blob", ["neutral"], FLAT, [
		{"level": 1, "move": "hit"}, {"level": 3, "move": "growl"}, {"level": 5, "move": "mend"},
		{"level": 6, "move": "quick_jab"}, {"level": 8, "move": "wave"}], [
		{"level": 5, "affinity": "striker", "into": "fish"},
		{"level": 5, "affinity": "catalyst", "into": "sparky"},
		{"level": 5, "default": true, "into": "mole"}]))
	r.add_entry("creatures", _c("fish", ["water"], FLAT, [{"level": 1, "move": "splash"}]))
	r.add_entry("creatures", _c("flame", ["fire"], FLAT, [{"level": 1, "move": "hit"}]))
	r.add_entry("creatures", _c("sparky", ["electric"], FLAT, [{"level": 1, "move": "zap"}]))
	r.add_entry("creatures", _c("mole", ["earth"], FLAT, [{"level": 1, "move": "hit"}]))
	r.add_entry("creatures", _c("fast", ["neutral"], stats({"spd": 150}), [{"level": 1, "move": "hit"}]))
	r.add_entry("creatures", _c("slow", ["neutral"], stats({"spd": 5}), [{"level": 1, "move": "hit"}]))
	r.add_entry("creatures", _c("tank", ["neutral"], stats({"hp": 250}), [{"level": 1, "move": "hit"}]))
	# Physically tough, specially fragile.
	r.add_entry("creatures", _c("shell", ["neutral"], stats({"hp": 250, "pdef": 200, "sdef": 10}), [{"level": 1, "move": "hit"}]))
	# Never resists (resolve 1) / very resolute (resolve 255).
	r.add_entry("creatures", _c("meek", ["neutral"], stats({"hp": 250, "resolve": 1}), [{"level": 1, "move": "hit"}]))
	r.add_entry("creatures", _c("stoic", ["neutral"], stats({"hp": 250, "resolve": 255}), [{"level": 1, "move": "hit"}]))

	r.add_entry("items", {"id": "cage", "name": "Cage", "category": "capture", "price": 1, "target": "one_enemy",
		"effects": [{"op": "capture", "mult": 1.0}]})
	r.add_entry("items", {"id": "net", "name": "Net", "category": "capture", "price": 1, "target": "one_enemy",
		"effects": [{"op": "capture", "mult": 1.0, "field_bonus": {"soaked": 3.0}}]})
	r.add_entry("items", {"id": "master_cage", "name": "Master Cage", "category": "capture", "price": 1, "target": "one_enemy",
		"effects": [{"op": "capture", "mult": 10.0}]})
	r.add_entry("items", {"id": "tonic", "name": "Tonic", "category": "heal", "price": 1, "target": "one_ally",
		"effects": [{"op": "restore_energy", "fraction": 0.5}]})
	r.add_entry("items", {"id": "potion", "name": "Potion", "category": "heal", "price": 1, "target": "one_ally",
		"effects": [{"op": "heal", "fraction": 0.5}]})
	r.add_entry("items", {"id": "seed", "name": "Seed", "category": "training", "price": 1, "target": "one_ally",
		"effects": [{"op": "reset_training"}]})
	r.add_entry("tamers", {"id": "t1", "name": "T1", "max_active": 2, "ai": "aggressive", "reward_money": 1,
		"party": [{"species": "blob", "level": 5}, {"species": "fish", "level": 5}]})
	r.add_entry("encounters", {"id": "e1", "name": "E1", "pack_min": 1, "pack_max": 1,
		"table": [{"species": "blob", "weight": 1, "min_level": 1, "max_level": 2}]})
	r.set_single("balance", balance())
	return r


## `balance_overrides` replaces top-level balance keys, e.g. {"resolve": {...}}.
static func build(balance_overrides: Dictionary = {}) -> Database:
	var r := raw()
	if not balance_overrides.is_empty():
		var b := balance()
		b.merge(balance_overrides, true)
		r.set_single("balance", b)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Fixture data invalid:\n" + "\n".join(errors))
	return Database.from_raw(r)


static func make(db: Database, species: String, level: int = 10, moves: Array = []) -> CreatureInstance:
	return CreatureInstance.create(db, species, level, PackedStringArray(moves))


## Both sides controlled by the test (no AI). Returns a started engine.
static func engine(db: Database, party0: Array, party1: Array, field0: int = -1, field1: int = -1,
		seed_value: int = 1, wild := false, items0: Dictionary = {}) -> BattleEngine:
	var setup := BattleSetup.new()
	setup.is_wild = wild
	var max_active := maxi(1, maxi(field0 if field0 > 0 else 1, field1 if field1 > 0 else 1))
	setup.add_side(party0, max_active, field0 if field0 > 0 else max_active, items0)
	setup.add_side(party1, max_active, field1 if field1 > 0 else max_active)
	if wild:
		setup.sides[1].is_wild = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var e := BattleEngine.new(db, rng, setup)
	e.start()
	return e


static func events_of(events: Array, type: String) -> Array:
	return events.filter(func(ev): return ev.type == type)


static func _m(id: String, type: String, category: String, power: int, acc: int, target: String,
		effects: Array, extra: Dictionary = {}) -> Dictionary:
	var m := {"id": id, "name": id.capitalize(), "type": type, "category": category, "power": power,
		"cost": 2, "accuracy": acc, "target": target, "effects": effects}
	m.merge(extra, true)
	return m


static func _side_move(id: String, type: String, state: String) -> Dictionary:
	return _m(id, type, "status", 0, 100, "enemy_side",
		[{"op": "apply_field_state", "side": "enemy", "state": state}], {"always_hits": true})


static func _c(id: String, types: Array, stats: Dictionary, learnset: Array, growth: Array = []) -> Dictionary:
	var c := {"id": id, "name": id.capitalize(), "types": types, "base_stats": stats,
		"catch_rate": 0.5, "xp_yield": 50, "learnset": learnset,
		"passives": ["steady"]}
	if not growth.is_empty():
		c["growth"] = growth
	return c
