class_name PackCoverage
extends RefCounted
## Reports which parts of the content schema no `tp_` (test pack) entry exercises yet.
##
## Each family maps to the names that are in DataSchemas (or the base data, for
## types, statuses and field states) but are not used by any entry whose id starts
## with Database.TEST_PREFIX. An empty array means the family is fully covered; the
## key is always present. Entries without the prefix never count as covering.
##
## Ops: every key of DataSchemas.EFFECT_OPS is required and nothing is excluded. The
## validator only forbids the overworld ops (DataSchemas.FIELD_OPS) outside a `field`
## list and does not otherwise tie an op to moves, so an op counts when a tp_ entry
## uses it anywhere: a move's effects, an item's effects, or a passive / held item's
## effects, triggers or field list. Passive-only ops (stat_mod, type_power, ...) are
## therefore satisfied by passives, and overworld ops by `field` lists.
##
## A held item with no `use` is "permanent" (the validator's default).

const FAMILIES: PackedStringArray = ["effect_ops", "move_targets", "trigger_on", "when_keys", "use_kinds",
	"types_single", "types_dual_count", "statuses", "field_states"]
const MIN_DUAL_TYPED: int = 10


static func report(raw: RawData) -> Dictionary:
	var ops: Dictionary = {}
	var targets: Dictionary = {}
	var triggers: Dictionary = {}
	var whens: Dictionary = {}
	var uses: Dictionary = {}
	var statuses: Dictionary = {}
	var states: Dictionary = {}
	var single_types: Dictionary = {}
	var dual_count: int = 0

	for rec: Dictionary in raw.get_entries("moves"):
		var m: Dictionary = rec.entry
		if not _is_pack(m):
			continue
		targets[str(m.get("target", ""))] = true
		_scan_effects(m.get("effects", []), ops, whens, statuses, states)

	for rec: Dictionary in raw.get_entries("items"):
		var it: Dictionary = rec.entry
		if not _is_pack(it):
			continue
		_scan_effects(it.get("effects", []), ops, whens, statuses, states)
		var held: Variant = it.get("held")
		if held is Dictionary:
			uses[str(held.get("use", "permanent"))] = true
			_scan_behaviour(held, ops, triggers, whens, statuses, states)

	for rec: Dictionary in raw.get_entries("passives"):
		var p: Dictionary = rec.entry
		if _is_pack(p):
			_scan_behaviour(p, ops, triggers, whens, statuses, states)

	for rec: Dictionary in raw.get_entries("creatures"):
		var c: Dictionary = rec.entry
		if not _is_pack(c):
			continue
		var types: Variant = c.get("types", [])
		if types is Array:
			if types.size() == 1:
				single_types[str(types[0])] = true
			elif types.size() == 2:
				dual_count += 1

	var out: Dictionary = {}
	out["effect_ops"] = _missing(DataSchemas.EFFECT_OPS.keys(), ops)
	out["move_targets"] = _missing(DataSchemas.MOVE_TARGETS, targets)
	out["trigger_on"] = _missing(DataSchemas.TRIGGER_ON, triggers)
	out["when_keys"] = _missing(DataSchemas.WHEN.keys(), whens)
	out["use_kinds"] = _missing(DataSchemas.HELD.use.values, uses)
	out["types_single"] = _missing(_base_ids(raw, "types"), single_types)
	var dual: PackedStringArray = PackedStringArray()
	if dual_count < MIN_DUAL_TYPED:
		dual.append("need %d, have %d" % [MIN_DUAL_TYPED, dual_count])
	out["types_dual_count"] = dual
	out["statuses"] = _missing(_base_ids(raw, "statuses"), statuses)
	out["field_states"] = _missing(_base_ids(raw, "field_states"), states)
	return out


static func _is_pack(entry: Dictionary) -> bool:
	return Database.is_test_content(str(entry.get("id", "")))


## Ids of the shipped (non-pack) entries of `category`, sorted.
static func _base_ids(raw: RawData, category: String) -> Array:
	var out: Array = []
	for rec: Dictionary in raw.get_entries(category):
		var id: String = str(rec.entry.get("id", ""))
		if id != "" and not Database.is_test_content(id):
			out.append(id)
	out.sort()
	return out


static func _missing(required: Array, seen: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for name: String in required:
		if not seen.has(name):
			out.append(name)
	return out


## A passive's or held item's effects, field list and triggers.
static func _scan_behaviour(b: Dictionary, ops: Dictionary, triggers: Dictionary, whens: Dictionary,
		statuses: Dictionary, states: Dictionary) -> void:
	_scan_effects(b.get("effects", []), ops, whens, statuses, states)
	_scan_effects(b.get("field", []), ops, whens, statuses, states)
	var trigs: Variant = b.get("triggers", [])
	if not trigs is Array:
		return
	for t: Variant in trigs:
		if not t is Dictionary:
			continue
		triggers[str(t.get("on", ""))] = true
		_scan_when(t.get("when"), whens)
		_scan_effects(t.get("effects", []), ops, whens, statuses, states)


static func _scan_effects(effects: Variant, ops: Dictionary, whens: Dictionary, statuses: Dictionary,
		states: Dictionary) -> void:
	if not effects is Array:
		return
	for e: Variant in effects:
		if not e is Dictionary:
			continue
		var op: String = str(e.get("op", ""))
		ops[op] = true
		_scan_when(e.get("when"), whens)
		if op == "apply_status" and e.has("status"):
			statuses[str(e.status)] = true
		elif op == "apply_field_state" and e.has("state"):
			states[str(e.state)] = true


static func _scan_when(w: Variant, whens: Dictionary) -> void:
	if not w is Dictionary:
		return
	for k: Variant in w.keys():
		whens[str(k)] = true
