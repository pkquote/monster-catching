extends GdUnitTestSuite
## Coverage-by-construction checks for the test pack's moves (data_testpack/moves/).

const PACK_ROOT: String = "res://data_testpack"
const MOVES_DIR: String = "res://data_testpack/moves"
## `capture` needs an item context; it is registered with a real handler but is item-only.
const ITEM_ONLY_OPS: PackedStringArray = ["capture"]
## Ops that are legal in a move's effects but are runtime no-ops there (passive-registered);
## the pack carries them once each, to prove they load and are ignored.
const INERT_IN_MOVE_OPS: PackedStringArray = ["skip_chance", "scrap_power"]

var _db: Database
var _pack: Array[MoveDef] = []


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert_array(Array(result.errors)).is_empty()
	_db = result.db
	_pack.clear()
	for id: String in _db.ids("moves"):
		if Database.is_test_content(id):
			_pack.append(_db.move(id))


func _all_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: MoveDef in _pack:
		for e: Dictionary in m.effects:
			out.append(e)
	return out


func _has_effect(pred: Callable) -> bool:
	for e: Dictionary in _all_effects():
		if pred.call(e):
			return true
	return false


func _has_move(pred: Callable) -> bool:
	for m: MoveDef in _pack:
		if pred.call(m):
			return true
	return false


## Ops the engine really runs from a move: registered with a handler other than the
## passive no-op one, minus item-only and overworld ops.
func _engine_run_ops() -> Array[String]:
	var out: Array[String] = []
	var passive_script: Script = EffectOps.get_op("stat_mod").get_script()
	for op: String in DataSchemas.EFFECT_OPS:
		if op in DataSchemas.FIELD_OPS or op in ITEM_ONLY_OPS:
			continue
		if EffectOps.get_op(op).get_script() == passive_script:
			continue
		out.append(op)
	return out


func _move_rule(field: String) -> Dictionary:
	return DataSchemas.ENTRY["moves"][field]


func _op_rule(op: String, field: String) -> Dictionary:
	return DataSchemas.EFFECT_OPS[op][field]


func test_move_count() -> void:
	assert_int(_pack.size()).is_greater_equal(90)


func test_every_pack_move_id_starts_with_tp() -> void:
	var dir: DirAccess = DirAccess.open(MOVES_DIR)
	assert_object(dir).is_not_null()
	var seen: int = 0
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOVES_DIR + "/" + f))
		assert_bool(parsed is Dictionary).is_true()
		for entry: Dictionary in parsed.entries:
			seen += 1
			assert_str(String(entry.id)).starts_with("tp_")
	assert_int(seen).is_equal(_pack.size())


func test_pack_files_use_lf_endings_and_tp_prefix() -> void:
	var dir: DirAccess = DirAccess.open(MOVES_DIR)
	assert_object(dir).is_not_null()
	var seen: int = 0
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		seen += 1
		assert_bool(FileAccess.get_file_as_string(MOVES_DIR + "/" + f).contains("\r")).is_false()
		assert_bool(f.begins_with("tp_")).is_true()
	assert_int(seen).is_greater(0)


func test_every_target_kind_is_used() -> void:
	for kind: String in DataSchemas.MOVE_TARGETS:
		assert_bool(_has_move(func(m: MoveDef) -> bool: return m.target == kind)).override_failure_message("no pack move targets " + kind).is_true()


func test_every_category_present() -> void:
	for cat: String in _move_rule("category").values:
		assert_bool(_has_move(func(m: MoveDef) -> bool: return m.category == cat)).override_failure_message(cat).is_true()


func test_numeric_extremes_from_schema() -> void:
	var power: Dictionary = _move_rule("power")
	var acc: Dictionary = _move_rule("accuracy")
	var cost: Dictionary = _move_rule("cost")
	var prio: Dictionary = _move_rule("priority")
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.category != "status" and m.power == 1)).override_failure_message("power 1").is_true()
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.power == int(power.max))).override_failure_message("power max").is_true()
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.accuracy == int(acc.min))).override_failure_message("accuracy min").is_true()
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.accuracy == int(acc.max))).override_failure_message("accuracy max").is_true()
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.cost == int(cost.min))).override_failure_message("cost min").is_true()
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.cost == int(cost.max))).override_failure_message("cost max").is_true()
	assert_bool(_has_move(func(m: MoveDef) -> bool: return m.cost > 20)).override_failure_message("cost > 20").is_true()
	for p: int in range(int(prio.min), int(prio.max) + 1):
		assert_bool(_has_move(func(m: MoveDef) -> bool: return m.priority == p)).override_failure_message("priority %d" % p).is_true()


func test_every_engine_run_op_is_used() -> void:
	var ops: Array[String] = _engine_run_ops()
	for must: String in ["damage", "heal", "damage_fraction", "apply_status", "apply_field_state",
			"remove_field_state", "bonus_if_field", "stat_stage", "restore_energy"]:
		assert_bool(must in ops).override_failure_message("registry no longer runs " + must).is_true()
	for op: String in ops:
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == op)).override_failure_message("no pack move uses op " + op).is_true()


func test_inert_ops_are_present_in_moves() -> void:
	for op: String in INERT_IN_MOVE_OPS:
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == op)).override_failure_message(op).is_true()


func test_two_moves_for_every_type() -> void:
	assert_int(_db.ids("types").size()).is_equal(14)
	for type_id: String in _db.ids("types"):
		var n: int = 0
		for m: MoveDef in _pack:
			if m.type == type_id:
				n += 1
		assert_int(n).override_failure_message("type %s has %d pack moves" % [type_id, n]).is_greater_equal(2)


func test_every_status_and_field_state_is_applied_by_some_pack_move() -> void:
	for sid: String in _db.ids("statuses"):
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "apply_status" and e.status == sid and e.has("chance"))).override_failure_message(sid + " with chance").is_true()
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "apply_status" and e.status == sid and not e.has("chance"))).override_failure_message(sid + " without chance").is_true()
	for fid: String in _db.ids("field_states"):
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "apply_field_state" and e.state == fid)).override_failure_message(fid + " applied").is_true()
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "bonus_if_field" and e.state == fid)).override_failure_message(fid + " cashed in").is_true()
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "remove_field_state" and e.get("state", "") == fid)).override_failure_message(fid + " removed").is_true()


func test_field_op_variants() -> void:
	var stacks: Dictionary = _op_rule("apply_field_state", "stacks")
	var turns: Dictionary = _op_rule("apply_field_state", "turns")
	var checks: Dictionary = {
		"consume true": func(e: Dictionary) -> bool: return e.op == "bonus_if_field" and e.get("consume", false) == true,
		"consume explicit false": func(e: Dictionary) -> bool: return e.op == "bonus_if_field" and e.get("consume", true) == false,
		"remove without state": func(e: Dictionary) -> bool: return e.op == "remove_field_state" and not e.has("state"),
		"stacks max": func(e: Dictionary) -> bool: return e.op == "apply_field_state" and int(e.get("stacks", 0)) == int(stacks.max),
		"turns max": func(e: Dictionary) -> bool: return e.op == "apply_field_state" and int(e.get("turns", 0)) == int(turns.max),
		"turns min": func(e: Dictionary) -> bool: return e.op == "apply_field_state" and int(e.get("turns", 0)) == int(turns.min),
	}
	for label: String in checks:
		assert_bool(_has_effect(checks[label])).override_failure_message(label).is_true()
	for side: String in DataSchemas.SIDES:
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "apply_field_state" and e.side == side)).override_failure_message("apply side " + side).is_true()


func test_every_stat_has_a_stage_move() -> void:
	for stat: String in DataSchemas.STATS:
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "stat_stage" and e.stat == stat and int(e.stages) > 0)).override_failure_message(stat + " up").is_true()
		assert_bool(_has_effect(func(e: Dictionary) -> bool: return e.op == "stat_stage" and e.stat == stat and int(e.stages) < 0)).override_failure_message(stat + " down").is_true()


func test_edge_cases_present() -> void:
	var stages: Dictionary = _op_rule("stat_stage", "stages")
	var move_checks: Dictionary = {
		"priority > 0": func(m: MoveDef) -> bool: return m.priority > 0,
		"priority < 0": func(m: MoveDef) -> bool: return m.priority < 0,
		"always_hits": func(m: MoveDef) -> bool: return m.always_hits,
		"power-0 status": func(m: MoveDef) -> bool: return m.category == "status" and m.power == 0,
		"3+ effects": func(m: MoveDef) -> bool: return m.effects.size() >= 3,
	}
	for label: String in move_checks:
		assert_bool(_has_move(move_checks[label])).override_failure_message(label).is_true()
	var effect_checks: Dictionary = {
		"stage min": func(e: Dictionary) -> bool: return e.op == "stat_stage" and int(e.stages) == int(stages.min),
		"stage max": func(e: Dictionary) -> bool: return e.op == "stat_stage" and int(e.stages) == int(stages.max),
		"heal 1.0": func(e: Dictionary) -> bool: return e.op == "heal" and is_equal_approx(float(e.fraction), 1.0),
		"heal small": func(e: Dictionary) -> bool: return e.op == "heal" and float(e.fraction) <= 0.1,
		"damage_fraction 1.0": func(e: Dictionary) -> bool: return e.op == "damage_fraction" and is_equal_approx(float(e.fraction), 1.0),
		"damage_fraction small": func(e: Dictionary) -> bool: return e.op == "damage_fraction" and float(e.fraction) <= 0.1,
		"restore_energy": func(e: Dictionary) -> bool: return e.op == "restore_energy",
		"scale_with_stacks": func(e: Dictionary) -> bool: return e.op == "damage" and e.get("scale_with_stacks", false) == true,
		"damage power override": func(e: Dictionary) -> bool: return e.op == "damage" and e.has("power"),
		"damage type override": func(e: Dictionary) -> bool: return e.op == "damage" and e.has("type"),
		"effect target override": func(e: Dictionary) -> bool: return e.has("target"),
	}
	for label: String in effect_checks:
		assert_bool(_has_effect(effect_checks[label])).override_failure_message(label).is_true()
