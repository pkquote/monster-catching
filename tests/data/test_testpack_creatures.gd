extends GdUnitTestSuite
## Coverage-by-construction checks for the test pack's creatures (data_testpack/creatures/).

const PACK_ROOT: String = "res://data_testpack"
const MIN_COUNT: int = 28
const MIN_DUAL: int = 10
const SHORT_LEARNSET_LATE_LEVEL: int = 40
## The F1 builder "can't learn" subject: it never learns any `tp_inflict_*` move nor any
## `tp_hit_*_chance_*` move (the eight status-applying moves a tester picks to see the labels).
const CANT_LEARN_ID: String = "tp_cant_learn_status_moves"

var _db: Database
var _raw: RawData
var _pack: Array[CreatureDef] = []


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert_array(Array(result.errors)).is_empty()
	_db = result.db
	var errors: PackedStringArray = PackedStringArray()
	_raw = DataLoader.read_raw("res://data", errors)
	DataLoader.read_raw(PACK_ROOT, errors, _raw, true)
	assert_array(Array(errors)).is_empty()
	_pack.clear()
	for id: String in _db.ids("creatures"):
		if Database.is_test_content(id):
			_pack.append(_db.creature(id))


func _any(pred: Callable) -> bool:
	for c: CreatureDef in _pack:
		if pred.call(c):
			return true
	return false


func _count(pred: Callable) -> int:
	var n: int = 0
	for c: CreatureDef in _pack:
		if pred.call(c):
			n += 1
	return n


func _stat_bounds() -> Dictionary:
	var rule: Dictionary = DataSchemas.ENTRY.creatures.base_stats.fields.hp
	return {"min": int(rule.get("min", 1)), "max": int(rule.get("max", 255))}


func _budget_total(c: CreatureDef) -> int:
	var total: int = 0
	for stat: String in c.growth_rates:
		var mult: float = float(_db.balance.growth_tiers.get(c.growth_rates[stat], 1.0))
		if mult > 1.0:
			total += 1
		elif mult < 1.0:
			total -= 1
	return total


func test_count_and_ids() -> void:
	assert_int(_pack.size()).is_greater_equal(MIN_COUNT)
	var seen: Dictionary = {}
	for c: CreatureDef in _pack:
		assert_bool(c.id.begins_with(Database.TEST_PREFIX)).is_true()
		assert_bool(seen.has(c.id)).override_failure_message("duplicate " + c.id).is_false()
		seen[c.id] = true
		assert_str(c.description).is_not_empty()


func test_every_type_appears_as_a_single_type() -> void:
	for type_id: String in _db.ids("types"):
		var found: bool = _any(func(c: CreatureDef) -> bool: return c.types.size() == 1 and c.types[0] == type_id)
		assert_bool(found).override_failure_message("no single-type creature of " + type_id).is_true()


func test_at_least_ten_dual_typed() -> void:
	assert_int(_count(func(c: CreatureDef) -> bool: return c.types.size() == 2)).is_greater_equal(MIN_DUAL)
	assert_bool(_any(func(c: CreatureDef) -> bool: return c.types.has("neutral"))).is_true()


func test_stat_shapes_by_values() -> void:
	var b: Dictionary = _stat_bounds()
	var s: Callable = func(c: CreatureDef, k: String) -> int: return int(c.base_stats[k])
	assert_bool(_any(func(c: CreatureDef) -> bool:
		var lo: int = maxi(s.call(c, "pdef"), s.call(c, "sdef"))
		return s.call(c, "patk") >= 2 * lo and s.call(c, "satk") >= 2 * lo and s.call(c, "hp") < 40)).override_failure_message("glass cannon").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool:
		var hi: int = maxi(s.call(c, "patk"), s.call(c, "satk"))
		return s.call(c, "pdef") >= 2 * hi and s.call(c, "sdef") >= 2 * hi and s.call(c, "hp") >= 2 * hi)).override_failure_message("wall").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return s.call(c, "spd") >= 120)).override_failure_message("speedster").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return s.call(c, "spd") <= 10 and s.call(c, "patk") >= 150)).override_failure_message("slow bruiser").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return s.call(c, "stamina") == b.min)).override_failure_message("energy starved").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return s.call(c, "luck") == b.max and s.call(c, "resolve") == b.max)).override_failure_message("luck/resolve").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool:
		for k: String in DataSchemas.BASE_STATS:
			if s.call(c, k) != b.min:
				return false
		return true)).override_failure_message("all minimum").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool:
		for k: String in DataSchemas.BASE_STATS:
			if s.call(c, k) != b.max:
				return false
		return true)).override_failure_message("all maximum").is_true()


func test_all_stats_present_and_within_schema_bounds() -> void:
	var b: Dictionary = _stat_bounds()
	for c: CreatureDef in _pack:
		for k: String in DataSchemas.BASE_STATS:
			assert_bool(c.base_stats.has(k)).override_failure_message(c.id + " lacks " + k).is_true()
			assert_int(int(c.base_stats[k])).is_between(b.min, b.max)


func test_catch_rate_and_xp_spread() -> void:
	var rule: Dictionary = DataSchemas.ENTRY.creatures.catch_rate
	assert_bool(_any(func(c: CreatureDef) -> bool: return is_equal_approx(c.catch_rate, float(rule.min)))).is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return is_equal_approx(c.catch_rate, float(rule.max)))).is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return c.xp_yield == 0)).is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool: return c.xp_yield >= 500)).is_true()
	var rates: Dictionary = {}
	for c: CreatureDef in _pack:
		rates[c.catch_rate] = true
	assert_int(rates.size()).is_greater_equal(8)


func test_every_growth_tier_is_used_by_several_species() -> void:
	for tier: String in _db.balance.growth_tiers:
		if tier == "steady":
			# Steady is the default for every unlisted stat; it counts when a creature lists none or lists it.
			assert_int(_count(func(c: CreatureDef) -> bool: return c.growth_rates.size() < DataSchemas.BASE_STATS.size())).is_greater_equal(3)
			continue
		var n: int = _count(func(c: CreatureDef) -> bool: return c.growth_rates.values().has(tier))
		assert_int(n).override_failure_message("tier %s used by %d" % [tier, n]).is_greater_equal(3)


func test_growth_budget_respected_and_one_species_spends_it_fully() -> void:
	var budget: int = _db.balance.growth_budget
	var full: int = 0
	for c: CreatureDef in _pack:
		assert_int(_budget_total(c)).override_failure_message(c.id).is_less_equal(budget)
		if _budget_total(c) == budget:
			full += 1
	assert_int(full).is_greater_equal(1)


func test_evolution_chains() -> void:
	var branched: int = 0
	for c: CreatureDef in _pack:
		var has_affinity: bool = false
		var has_default: bool = false
		for g: Dictionary in c.growth:
			assert_bool(_db.has("creatures", g.into)).override_failure_message(c.id + " into " + g.into).is_true()
			assert_bool(Database.is_test_content(g.into)).is_true()
			if g.affinity != "":
				has_affinity = true
				assert_bool(_db.has("affinities", g.affinity)).is_true()
			if g.default:
				has_default = true
		if has_affinity and has_default:
			branched += 1
	assert_int(branched).is_greater_equal(2)
	# A three-stage chain: a creature evolving into one that itself evolves.
	var three: bool = false
	for c: CreatureDef in _pack:
		for g: Dictionary in c.growth:
			if not _db.creature(g.into).growth.is_empty():
				three = true
	assert_bool(three).is_true()
	# The three-stage line starts with an Affinity branch and a default branch at the first stage.
	var first_stage_branched: bool = _any(func(c: CreatureDef) -> bool:
		var aff: bool = false
		var dflt: bool = false
		var next_evolves: bool = false
		for g: Dictionary in c.growth:
			aff = aff or g.affinity != ""
			dflt = dflt or g.default
			next_evolves = next_evolves or not _db.creature(g.into).growth.is_empty()
		return aff and dflt and next_evolves)
	assert_bool(first_stage_branched).is_true()


func test_passives_and_affinity_passives() -> void:
	var max_passives: int = int(DataSchemas.ENTRY.creatures.passives.max)
	var referenced: Dictionary = {}
	for c: CreatureDef in _pack:
		assert_int(c.passives.size()).override_failure_message(c.id).is_between(1, max_passives)
		for p: String in c.passives:
			assert_bool(Database.is_test_content(p)).override_failure_message(c.id + " uses base passive " + p).is_true()
			referenced[p] = true
		for aff: String in _db.ids("affinities"):
			assert_bool(c.affinity_passives.has(aff)).override_failure_message("%s lacks %s" % [c.id, aff]).is_true()
			assert_bool(_db.has("passives", c.affinity_passives[aff])).is_true()
			referenced[c.affinity_passives[aff]] = true
		assert_int(c.affinity_passives.size()).is_equal(_db.ids("affinities").size())
	for p: String in _db.ids("passives"):
		if Database.is_test_content(p):
			assert_bool(referenced.has(p)).override_failure_message("unused pack passive " + p).is_true()


func test_learnset_shapes() -> void:
	assert_bool(_any(func(c: CreatureDef) -> bool: return c.learnset.size() == 1)).override_failure_message("one move").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool:
		return c.learnset.size() >= 4 and c.learnset.all(func(l: Dictionary) -> bool: return l.level == 1))).override_failure_message("all level 1").is_true()
	assert_bool(_any(func(c: CreatureDef) -> bool:
		return c.learnset.any(func(l: Dictionary) -> bool: return l.level >= SHORT_LEARNSET_LATE_LEVEL))).override_failure_message("late").is_true()
	for c: CreatureDef in _pack:
		assert_bool(c.learnset.any(func(l: Dictionary) -> bool: return l.level == 1)).is_true()


func test_cant_learn_subject() -> void:
	var c: CreatureDef = _db.creature(CANT_LEARN_ID)
	assert_object(c).is_not_null()
	for l: Dictionary in c.learnset:
		var m: String = l.move
		assert_bool(m.begins_with("tp_inflict_") or "_chance_" in m).override_failure_message(m).is_false()
	# The inflict group and the chance group both exist in the pack, so the omission means something.
	var inflict: int = 0
	var chance: int = 0
	for id: String in _db.ids("moves"):
		inflict += 1 if id.begins_with("tp_inflict_") else 0
		chance += 1 if id.begins_with("tp_hit_") and "_chance_" in id else 0
	assert_int(inflict).is_equal(4)
	assert_int(chance).is_equal(6)


func test_move_loadouts() -> void:
	var is_status: Callable = func(m: String) -> bool: return _db.move(m).category == "status"
	# Four status moves only.
	assert_bool(_any(func(c: CreatureDef) -> bool:
		return c.learnset.size() == 4 and c.learnset.all(func(l: Dictionary) -> bool: return is_status.call(l.move)))).override_failure_message("status only").is_true()
	# Four attacking moves of one type, nothing else.
	assert_bool(_any(func(c: CreatureDef) -> bool:
		if c.learnset.size() != 4:
			return false
		var t: String = _db.move(c.learnset[0].move).type
		return c.learnset.all(func(l: Dictionary) -> bool:
			var m: MoveDef = _db.move(l.move)
			return m.type == t and m.category != "status"))).override_failure_message("four same-type attacks").is_true()
	# A move that costs more energy than the creature has at level 1.
	var base_energy: int = int(_db.balance.energy_cfg.base)
	assert_bool(_any(func(c: CreatureDef) -> bool:
		var cap: int = Stats.energy_at(int(c.base_stats.stamina), 1, base_energy)
		return c.learnset.any(func(l: Dictionary) -> bool: return _db.move(l.move).cost > cap))).override_failure_message("unaffordable move").is_true()


func test_learnsets_cover_every_category_target_and_pack_move() -> void:
	var categories: Dictionary = {}
	var targets: Dictionary = {}
	var learned: Dictionary = {}
	for c: CreatureDef in _pack:
		for l: Dictionary in c.learnset:
			var m: MoveDef = _db.move(l.move)
			categories[m.category] = true
			targets[m.target] = true
			learned[m.id] = true
	assert_int(categories.size()).is_equal(3)
	for t: String in DataSchemas.MOVE_TARGETS:
		assert_bool(targets.has(t)).override_failure_message("no learnable move targeting " + t).is_true()
	for id: String in _db.ids("moves"):
		if Database.is_test_content(id):
			assert_bool(learned.has(id)).override_failure_message("pack move never learned: " + id).is_true()


func test_pack_coverage_report_is_fully_empty() -> void:
	var report: Dictionary = PackCoverage.report(_raw)
	assert_array(Array(report["types_single"])).is_empty()
	assert_array(Array(report["types_dual_count"])).is_empty()
	for family: String in PackCoverage.FAMILIES:
		assert_array(Array(report[family])).override_failure_message("%s: %s" % [family, str(report[family])]).is_empty()
