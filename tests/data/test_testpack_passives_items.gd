extends GdUnitTestSuite
## Coverage-by-construction checks for the test pack's passives and items
## (data_testpack/passives/, data_testpack/items/).

const PACK_ROOT: String = "res://data_testpack"
const PASSIVES_DIR: String = "res://data_testpack/passives"
const ITEMS_DIR: String = "res://data_testpack/items"
## Ops that only make sense as item effects, not as a passive's always-on effects.
const ITEM_ONLY_OPS: PackedStringArray = ["capture", "reset_training"]
## skip_chance is only read from status effects; as a passive effect it is inert, so no pack passive carries it.
const NOT_PASSIVE_OPS: PackedStringArray = ["skip_chance"]
## Item categories the pack leaves out (a key item has no effect to test).
const UNUSED_ITEM_CATEGORIES: PackedStringArray = ["key"]
const CHAIN_IDS: PackedStringArray = ["tp_chain_a", "tp_chain_b"]

var _db: Database
var _raw: RawData
var _passives: Array[PassiveDef] = []
var _items: Array[ItemDef] = []
var _helds: Array[ItemDef] = []


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert_array(Array(result.errors)).is_empty()
	_db = result.db
	var errors: PackedStringArray = PackedStringArray()
	_raw = DataLoader.read_raw("res://data", errors)
	DataLoader.read_raw(PACK_ROOT, errors, _raw, true)
	assert_array(Array(errors)).is_empty()
	_passives.clear()
	_items.clear()
	_helds.clear()
	for id: String in _db.ids("passives"):
		if Database.is_test_content(id):
			_passives.append(_db.passive(id))
	for id: String in _db.ids("items"):
		if Database.is_test_content(id):
			var it: ItemDef = _db.item(id)
			_items.append(it)
			if it.category == "held":
				_helds.append(it)


# --- helpers ------------------------------------------------------------------

## Every behaviour block in the pack: passives plus held items' `held` PassiveDefs.
func _behaviours() -> Array[PassiveDef]:
	var out: Array[PassiveDef] = []
	out.append_array(_passives)
	for it: ItemDef in _helds:
		out.append(it.held)
	return out


func _any(list: Array, pred: Callable) -> bool:
	for x: Variant in list:
		if pred.call(x):
			return true
	return false


func _triggers(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: PassiveDef in list:
		for t: Dictionary in p.triggers:
			out.append(t)
	return out


func _held_defs() -> Array:
	var out: Array = []
	for it: ItemDef in _helds:
		out.append(it.held)
	return out


func _has_trigger(list: Array, pred: Callable) -> bool:
	for t: Dictionary in _triggers(list):
		if pred.call(t):
			return true
	return false


func _item_has_effect(items: Array, pred: Callable) -> bool:
	for it: ItemDef in items:
		for e: Dictionary in it.effects:
			if pred.call(e):
				return true
	return false


func _ids_in_dir(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	assert_object(dir).is_not_null()
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path + "/" + f))
		assert_bool(parsed is Dictionary).is_true()
		for entry: Dictionary in parsed.entries:
			out.append(String(entry.id))
	return out


# --- sizes and hygiene --------------------------------------------------------

func test_passive_count() -> void:
	assert_int(_passives.size()).is_greater_equal(30)


func test_item_count() -> void:
	assert_int(_items.size()).is_greater_equal(23)


func test_ids_start_with_tp_and_are_unique() -> void:
	for dir_path: String in [PASSIVES_DIR, ITEMS_DIR]:
		var ids: Array[String] = _ids_in_dir(dir_path)
		assert_int(ids.size()).is_greater(0)
		var seen: Dictionary = {}
		for id: String in ids:
			assert_str(id).starts_with("tp_")
			assert_bool(seen.has(id)).override_failure_message("duplicate id " + id).is_false()
			seen[id] = true
	assert_int(_ids_in_dir(PASSIVES_DIR).size()).is_equal(_passives.size())
	assert_int(_ids_in_dir(ITEMS_DIR).size()).is_equal(_items.size())


func test_files_use_lf_endings_and_tp_prefix() -> void:
	for dir_path: String in [PASSIVES_DIR, ITEMS_DIR]:
		var dir: DirAccess = DirAccess.open(dir_path)
		assert_object(dir).is_not_null()
		var seen: int = 0
		for f: String in dir.get_files():
			if not f.ends_with(".json"):
				continue
			seen += 1
			assert_bool(f.begins_with("tp_")).is_true()
			assert_bool(FileAccess.get_file_as_string(dir_path + "/" + f).contains("\r")).is_false()
		assert_int(seen).is_greater(0)


func test_every_pack_entry_has_a_description() -> void:
	for p: PassiveDef in _passives:
		assert_str(p.description).override_failure_message(p.id).is_not_empty()
	for it: ItemDef in _items:
		assert_str(it.description).override_failure_message(it.id).is_not_empty()


# --- triggers ------------------------------------------------------------------

func test_every_trigger_kind_used_by_a_passive_and_a_held_item() -> void:
	for on: String in DataSchemas.TRIGGER_ON:
		assert_bool(_has_trigger(_passives, func(t: Dictionary) -> bool: return t.on == on)) \
			.override_failure_message("no pack passive triggers on " + on).is_true()
		assert_bool(_has_trigger(_held_defs(), func(t: Dictionary) -> bool: return t.on == on)) \
			.override_failure_message("no pack held item triggers on " + on).is_true()


func test_contact_true_and_false_hit_triggers() -> void:
	for list: Array in [_passives, _held_defs()]:
		assert_bool(_has_trigger(list, func(t: Dictionary) -> bool: return t.on == "hit" and t.contact == true)).is_true()
		assert_bool(_has_trigger(list, func(t: Dictionary) -> bool: return t.on == "hit" and t.contact == false)).is_true()


func test_trigger_chance_values_1_50_and_unset() -> void:
	var chance: Dictionary = DataSchemas.TRIGGERS.of.fields.chance
	for c: int in [int(chance.min), 50, int(chance.max)]:
		assert_bool(_has_trigger(_passives, func(t: Dictionary) -> bool: return t.chance == c)) \
			.override_failure_message("passive trigger chance %d" % c).is_true()
		assert_bool(_has_trigger(_held_defs(), func(t: Dictionary) -> bool: return t.chance == c)) \
			.override_failure_message("held trigger chance %d" % c).is_true()
	# "Unset" is the default 100 in the def; check the raw JSON really omits the key somewhere.
	var omitted: bool = false
	for rec: Dictionary in _raw.get_entries("passives"):
		if not Database.is_test_content(String(rec.entry.id)):
			continue
		for t: Dictionary in rec.entry.get("triggers", []):
			omitted = omitted or not t.has("chance")
	assert_bool(omitted).is_true()


func test_trigger_effects_use_the_attacker_target_and_other_targets() -> void:
	# Triggers may omit target (default lands on the attacker/self per trigger kind) or set one explicitly.
	assert_bool(_has_trigger(_passives, func(t: Dictionary) -> bool:
		return _any(t.effects, func(e: Dictionary) -> bool: return e.get("target", "") == "attacker"))).is_true()
	assert_bool(_has_trigger(_passives, func(t: Dictionary) -> bool:
		return _any(t.effects, func(e: Dictionary) -> bool: return e.get("target", "") == "self"))).is_true()
	assert_bool(_has_trigger(_passives, func(t: Dictionary) -> bool:
		return _any(t.effects, func(e: Dictionary) -> bool: return e.get("target", "") == "all_enemies"))).is_true()
	assert_bool(_has_trigger(_passives, func(t: Dictionary) -> bool:
		return _any(t.effects, func(e: Dictionary) -> bool: return not e.has("target")))).is_true()


# --- when conditions ------------------------------------------------------------

func test_every_when_field_is_used_on_effects_and_on_triggers() -> void:
	for key: String in DataSchemas.WHEN.keys():
		var on_effect: bool = false
		var on_trigger: bool = false
		for b: PassiveDef in _behaviours():
			for e: Dictionary in b.effects:
				on_effect = on_effect or e.get("when", {}).has(key)
			for t: Dictionary in b.triggers:
				on_trigger = on_trigger or t.when.has(key)
		assert_bool(on_effect).override_failure_message("no always-on effect uses when." + key).is_true()
		assert_bool(on_trigger).override_failure_message("no trigger uses when." + key).is_true()


func test_when_extremes_and_both_sides() -> void:
	var hp: Dictionary = DataSchemas.WHEN.hp_below
	var sides: Array = DataSchemas.WHEN.side.values
	var whens: Array[Dictionary] = []
	for b: PassiveDef in _behaviours():
		for e: Dictionary in b.effects:
			if e.has("when"):
				whens.append(e.when)
		for t: Dictionary in b.triggers:
			whens.append(t.when)
	assert_bool(_any(whens, func(w: Dictionary) -> bool: return w.has("hp_below") and is_equal_approx(float(w.hp_below), float(hp.min)))).is_true()
	assert_bool(_any(whens, func(w: Dictionary) -> bool: return w.has("hp_below") and is_equal_approx(float(w.hp_below), float(hp.max)))).is_true()
	assert_bool(_any(whens, func(w: Dictionary) -> bool: return w.get("underdog", true) == false)).is_true()
	for s: String in sides:
		assert_bool(_any(whens, func(w: Dictionary) -> bool: return w.get("side", "") == s)).override_failure_message("when.side " + s).is_true()


# --- held-item kinds ------------------------------------------------------------

func test_every_held_use_kind_with_each_trigger() -> void:
	for use: String in DataSchemas.HELD.use.values:
		assert_bool(_any(_helds, func(it: ItemDef) -> bool: return it.held_use == use)).override_failure_message("use " + use).is_true()
		if use == "permanent":
			continue
		# Spent kinds have no always-on effects, so every trigger kind is worth one of each.
		for on: String in DataSchemas.TRIGGER_ON:
			assert_bool(_any(_helds, func(it: ItemDef) -> bool:
				return it.held_use == use and _any(it.held.triggers, func(t: Dictionary) -> bool: return t.on == on))) \
				.override_failure_message("%s held item on %s" % [use, on]).is_true()
	assert_bool(_any(_helds, func(it: ItemDef) -> bool:
		return it.held_use == "permanent" and not it.held.triggers.is_empty())).is_true()
	assert_bool(_any(_helds, func(it: ItemDef) -> bool:
		return it.held_use == "permanent" and not it.held.effects.is_empty())).is_true()


func test_auras_among_passives_and_held_items() -> void:
	assert_bool(_any(_passives, func(p: PassiveDef) -> bool: return p.scope == "allies")).is_true()
	assert_bool(_any(_helds, func(it: ItemDef) -> bool: return it.held.scope == "allies")).is_true()
	assert_bool(_any(_passives, func(p: PassiveDef) -> bool: return p.scope == "self")).is_true()
	assert_bool(_any(_helds, func(it: ItemDef) -> bool: return it.held.scope == "self")).is_true()


func test_held_items_overlap_passive_effects() -> void:
	var held_effects: int = 0
	var overlaps: int = 0
	for it: ItemDef in _helds:
		for e: Dictionary in it.held.effects:
			held_effects += 1
			for p: PassiveDef in _passives:
				if _any(p.effects, func(pe: Dictionary) -> bool: return pe.op == e.op):
					overlaps += 1
					break
	assert_int(held_effects).is_greater(0)
	assert_int(overlaps).is_equal(held_effects)


func test_held_items_have_overworld_field_ops() -> void:
	assert_bool(_any(_helds, func(it: ItemDef) -> bool: return not it.held.field.is_empty())).is_true()


# --- passive persistent and overworld ops -----------------------------------------

func test_every_overworld_field_op_in_a_passive() -> void:
	for op: String in DataSchemas.FIELD_OPS:
		assert_bool(_any(_passives, func(p: PassiveDef) -> bool:
			return _any(p.field, func(e: Dictionary) -> bool: return e.op == op))) \
			.override_failure_message("no pack passive has field op " + op).is_true()


func test_overworld_mults_span_zero_to_max() -> void:
	var lo: float = INF
	var hi: float = -INF
	for p: PassiveDef in _passives:
		for e: Dictionary in p.field:
			lo = minf(lo, float(e.mult))
			hi = maxf(hi, float(e.mult))
	assert_float(lo).is_less(1.0)
	assert_float(hi).is_greater(1.0)


## Every op whose handler is the passive-only one (except overworld and item-only ops)
## must be carried by some pack passive's always-on effects.
func test_every_persistent_op_is_used_by_a_passive() -> void:
	var passive_script: Script = EffectOps.get_op("stat_mod").get_script()
	var checked: int = 0
	for op: String in DataSchemas.EFFECT_OPS:
		if op in DataSchemas.FIELD_OPS or op in ITEM_ONLY_OPS or op in NOT_PASSIVE_OPS:
			continue
		if EffectOps.get_op(op).get_script() != passive_script:
			continue
		checked += 1
		assert_bool(_any(_passives, func(p: PassiveDef) -> bool:
			return _any(p.effects, func(e: Dictionary) -> bool: return e.op == op))) \
			.override_failure_message("no pack passive carries persistent op " + op).is_true()
	assert_int(checked).is_greater(0)


func test_persistent_op_variants() -> void:
	var boost: Dictionary = DataSchemas.EFFECT_OPS.field_boost
	var mult: Dictionary = DataSchemas.EFFECT_OPS.type_power.mult
	var variants: Dictionary = {
		"status_immune any": func(e: Dictionary) -> bool: return e.op == "status_immune" and not e.has("status"),
		"status_immune one": func(e: Dictionary) -> bool: return e.op == "status_immune" and e.has("status"),
		"guard_stages any": func(e: Dictionary) -> bool: return e.op == "guard_stages" and not e.has("stat"),
		"guard_stages one": func(e: Dictionary) -> bool: return e.op == "guard_stages" and e.has("stat"),
		"incoming_type_mod any": func(e: Dictionary) -> bool: return e.op == "incoming_type_mod" and not e.has("type"),
		"incoming_type_mod typed": func(e: Dictionary) -> bool: return e.op == "incoming_type_mod" and e.has("type"),
		"energy_discount any": func(e: Dictionary) -> bool: return e.op == "energy_discount" and not e.has("type"),
		"energy_discount typed": func(e: Dictionary) -> bool: return e.op == "energy_discount" and e.has("type"),
		"field_boost bare": func(e: Dictionary) -> bool: return e.op == "field_boost" and not e.has("stacks") and not e.has("turns"),
		"field_boost max": func(e: Dictionary) -> bool: return e.op == "field_boost" and int(e.get("stacks", 0)) == int(boost.stacks.max) and int(e.get("turns", 0)) == int(boost.turns.max),
		"type_power zero": func(e: Dictionary) -> bool: return e.op == "type_power" and is_equal_approx(float(e.mult), float(mult.min)),
		"type_power max": func(e: Dictionary) -> bool: return e.op == "type_power" and is_equal_approx(float(e.mult), float(mult.max)),
		"absorb full": func(e: Dictionary) -> bool: return e.op == "absorb_type" and is_equal_approx(float(e.fraction), 1.0),
		"rest_bonus full": func(e: Dictionary) -> bool: return e.op == "rest_bonus" and is_equal_approx(float(e.fraction), 1.0),
	}
	for label: String in variants:
		var pred: Callable = variants[label]
		assert_bool(_any(_passives, func(p: PassiveDef) -> bool: return _any(p.effects, pred))) \
			.override_failure_message(label).is_true()
	for stat: String in DataSchemas.STATS:
		assert_bool(_any(_passives, func(p: PassiveDef) -> bool:
			return _any(p.effects, func(e: Dictionary) -> bool: return e.op == "stat_mod" and e.stat == stat))) \
			.override_failure_message("stat_mod " + stat).is_true()


# --- depth-guard pair ----------------------------------------------------------------

func test_depth_guard_pair() -> void:
	var holders: Array[PassiveDef] = []
	for id: String in CHAIN_IDS:
		assert_bool(_db.has("passives", id)).override_failure_message(id).is_true()
		holders.append(_db.passive(id))
	for p: PassiveDef in holders:
		# A hit trigger whose `damage` effect lands on the attacker (the other side) with the holder as
		# the attacker: a real hit that would set off the other holder's hit trigger.
		assert_bool(_any(p.triggers, func(t: Dictionary) -> bool:
			return t.on == "hit" and _any(t.effects, func(e: Dictionary) -> bool:
				return e.op == "damage" and e.get("target", "attacker") == "attacker"))) 			.override_failure_message(p.id).is_true()
		assert_str(p.description.to_lower()).contains("depth guard")


# --- items --------------------------------------------------------------------------------

func test_healing_items_span_small_and_full_and_energy() -> void:
	var heals: Array = _items.filter(func(it: ItemDef) -> bool: return it.category == "heal")
	assert_int(heals.size()).is_greater(0)
	var frac: Dictionary = DataSchemas.EFFECT_OPS.heal.fraction
	assert_bool(_item_has_effect(heals, func(e: Dictionary) -> bool: return e.op == "heal" and float(e.fraction) <= 0.1 and float(e.fraction) > float(frac.min))).is_true()
	assert_bool(_item_has_effect(heals, func(e: Dictionary) -> bool: return e.op == "heal" and is_equal_approx(float(e.fraction), float(frac.max)))).is_true()
	assert_bool(_item_has_effect(heals, func(e: Dictionary) -> bool: return e.op == "heal" and is_equal_approx(float(e.fraction), float(frac.min)))).is_true()
	assert_bool(_item_has_effect(heals, func(e: Dictionary) -> bool: return e.op == "restore_energy" and is_equal_approx(float(e.fraction), 1.0))).is_true()
	assert_bool(_item_has_effect(heals, func(e: Dictionary) -> bool: return e.op == "restore_energy" and float(e.fraction) < 1.0)).is_true()
	# No status-cure op exists in DataSchemas.EFFECT_OPS, so the "full cure" is a full heal plus full energy in one item.
	assert_bool(_any(heals, func(it: ItemDef) -> bool:
		return _any(it.effects, func(e: Dictionary) -> bool: return e.op == "heal" and is_equal_approx(float(e.fraction), 1.0)) \
			and _any(it.effects, func(e: Dictionary) -> bool: return e.op == "restore_energy" and is_equal_approx(float(e.fraction), 1.0)))).is_true()
	for it: ItemDef in heals:
		assert_str(it.target).override_failure_message(it.id).is_equal("one_ally")


func test_capture_items_include_weak_and_guaranteed() -> void:
	var caps: Array = _items.filter(func(it: ItemDef) -> bool: return it.category == "capture")
	assert_int(caps.size()).is_greater(0)
	var mult: Dictionary = DataSchemas.EFFECT_OPS.capture.mult
	assert_bool(_item_has_effect(caps, func(e: Dictionary) -> bool: return e.op == "capture" and float(e.mult) < 1.0 and float(e.mult) > float(mult.min))).is_true()
	assert_bool(_item_has_effect(caps, func(e: Dictionary) -> bool: return e.op == "capture" and is_equal_approx(float(e.mult), float(mult.min)))).is_true()
	assert_bool(_item_has_effect(caps, func(e: Dictionary) -> bool: return e.op == "capture" and is_equal_approx(float(e.mult), float(mult.max)))).is_true()
	assert_bool(_item_has_effect(caps, func(e: Dictionary) -> bool: return e.op == "capture" and float(e.mult) > 1.0 and float(e.mult) < float(mult.max))).is_true()
	assert_bool(_item_has_effect(caps, func(e: Dictionary) -> bool: return e.op == "capture" and e.has("field_bonus"))).is_true()
	assert_bool(_item_has_effect(caps, func(e: Dictionary) -> bool: return e.op == "capture" and not e.has("field_bonus"))).is_true()
	for it: ItemDef in caps:
		assert_str(it.target).override_failure_message(it.id).is_equal("one_enemy")


func test_training_item_present() -> void:
	var training: Array = _items.filter(func(it: ItemDef) -> bool: return it.category == "training")
	assert_int(training.size()).is_greater(0)
	assert_bool(_item_has_effect(training, func(e: Dictionary) -> bool: return e.op == "reset_training")).is_true()


func test_every_item_category_the_pack_owns_is_present() -> void:
	for cat: String in DataSchemas.ENTRY.items.category.values:
		if cat in UNUSED_ITEM_CATEGORIES:
			continue
		assert_bool(_any(_items, func(it: ItemDef) -> bool: return it.category == cat)).override_failure_message(cat).is_true()
	assert_bool(_any(_items, func(it: ItemDef) -> bool: return it.price == 0)).is_true()
	assert_bool(_any(_items, func(it: ItemDef) -> bool: return it.price >= 1000)).is_true()


# --- PackCoverage families this task alone can satisfy ---------------------------------

func test_pack_coverage_families_owned_by_this_task_are_empty() -> void:
	var report: Dictionary = PackCoverage.report(_raw)
	for family: String in ["trigger_on", "when_keys", "use_kinds"]:
		assert_array(Array(report[family])).override_failure_message(family + " " + str(report[family])).is_empty()


func test_persistent_and_overworld_ops_no_longer_uncovered() -> void:
	var missing: Array = Array(PackCoverage.report(_raw)["effect_ops"])
	var passive_script: Script = EffectOps.get_op("stat_mod").get_script()
	for op: String in missing:
		assert_bool(EffectOps.get_op(op).get_script() == passive_script and op not in ITEM_ONLY_OPS and op not in NOT_PASSIVE_OPS) \
			.override_failure_message("passive-only/item op %s still uncovered" % op).is_false()
	for op: String in ITEM_ONLY_OPS:
		assert_bool(op in missing).override_failure_message(op + " still uncovered").is_false()
