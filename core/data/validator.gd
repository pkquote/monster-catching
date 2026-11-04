class_name DataValidator
extends RefCounted
## Validates RawData against DataSchemas plus cross-entry rules.
## Returns a list of human-readable error strings: "file [category:id] path: message".

const _ID_PATTERN := "^[a-z][a-z0-9_]*$"
const _BATTLE_CALL_PATTERN := "start_battle\\(\\s*\"([^\"]+)\"\\s*\\)"

var _raw: RawData
var _ids: Dictionary = {}  # category -> {id: true}
var _errors: PackedStringArray = []
var _id_regex := RegEx.create_from_string(_ID_PATTERN)

# Context for error messages while walking an entry.
var _file := ""
var _label := ""


static func validate(raw: RawData) -> PackedStringArray:
	var v := DataValidator.new()
	return v._run(raw)


func _run(raw: RawData) -> PackedStringArray:
	_raw = raw
	for cat in DataSchemas.CATEGORIES:
		_ids[cat] = raw.ids(cat)

	for cat in DataSchemas.CATEGORIES:
		if DataSchemas.CATEGORIES[cat] == "single":
			_check_single(cat)
		else:
			_check_category(cat)

	_check_cross_rules()
	_check_dialogue()
	return _errors


# --- Category walking -------------------------------------------------------

func _check_single(cat: String) -> void:
	if not _raw.singles.has(cat):
		_errors.append("data/%s.json: missing required file" % cat)
		return
	var rec: Dictionary = _raw.singles[cat]
	_file = rec.file
	_label = "[%s]" % cat
	_check_fields(rec.data, DataSchemas.ENTRY[cat], "")


func _check_category(cat: String) -> void:
	var seen := {}
	for rec in _raw.get_entries(cat):
		var entry: Dictionary = rec.entry
		_file = rec.file
		var id = entry.get("id", "?")
		_label = "[%s:%s]" % [cat, id]
		if id is String and seen.has(id):
			_err("", "duplicate id (first defined in %s)" % seen[id])
		elif id is String:
			seen[id] = rec.file
		_check_fields(entry, DataSchemas.ENTRY[cat], "")


func _check_fields(obj: Dictionary, fields: Dictionary, path: String) -> void:
	for key in fields:
		var rule: Dictionary = fields[key]
		var sub := _join(path, key)
		if not obj.has(key):
			if not rule.get("opt", false):
				_err(sub, "missing required field")
			continue
		_check_value(obj[key], rule, sub)
	for key in obj:
		if not fields.has(key):
			_err(_join(path, str(key)), "unknown field")


func _check_value(value: Variant, rule: Dictionary, path: String) -> void:
	match rule.t:
		"string":
			if not value is String or value.is_empty():
				_err(path, "expected non-empty string")
		"id":
			if not value is String or _id_regex.search(value) == null:
				_err(path, "id must be snake_case (got %s)" % JSON.stringify(value))
		"bool":
			if not value is bool:
				_err(path, "expected bool")
		"int":
			if not _is_number(value) or float(value) != floorf(float(value)):
				_err(path, "expected integer")
			else:
				_check_range(float(value), rule, path)
		"number":
			if not _is_number(value):
				_err(path, "expected number")
			else:
				_check_range(float(value), rule, path)
		"enum":
			if not value in rule.values:
				_err(path, "expected one of %s (got %s)" % [rule.values, JSON.stringify(value)])
		"ref":
			if not value is String:
				_err(path, "expected %s id" % rule.cat)
			elif not _ids[rule.cat].has(value):
				_err(path, "unknown %s id '%s'" % [rule.cat, value])
		"array":
			if not value is Array:
				_err(path, "expected array")
				return
			if rule.has("min") and value.size() < rule.min:
				_err(path, "expected at least %d element(s)" % rule.min)
			if rule.has("max") and value.size() > rule.max:
				_err(path, "expected at most %d element(s)" % rule.max)
			for i in value.size():
				_check_value(value[i], rule.of, "%s[%d]" % [path, i])
		"dict":
			if not value is Dictionary:
				_err(path, "expected object")
			else:
				_check_fields(value, rule.fields, path)
		"map":
			if not value is Dictionary:
				_err(path, "expected object")
				return
			for k in value:
				_check_value(k, rule.key, "%s.<key %s>" % [path, k])
				_check_value(value[k], rule.value, "%s.%s" % [path, k])
		"effects":
			_check_effects(value, path)
		_:
			_err(path, "schema error: unknown rule type '%s'" % rule.t)


func _check_effects(value: Variant, path: String) -> void:
	if not value is Array:
		_err(path, "expected array of effects")
		return
	for i in value.size():
		var eff = value[i]
		var sub := "%s[%d]" % [path, i]
		if not eff is Dictionary:
			_err(sub, "expected effect object")
			continue
		var op = eff.get("op")
		if not DataSchemas.EFFECT_OPS.has(op):
			_err(sub + ".op", "unknown effect op %s" % JSON.stringify(op))
			continue
		var fields: Dictionary = DataSchemas.EFFECT_OPS[op].duplicate()
		fields["op"] = {"t": "string"}
		fields["target"] = {"t": "enum", "values": DataSchemas.TARGETS, "opt": true}
		_check_fields(eff, fields, sub)


func _check_range(n: float, rule: Dictionary, path: String) -> void:
	if rule.has("min") and n < rule.min:
		_err(path, "must be >= %s" % rule.min)
	if rule.has("max") and n > rule.max:
		_err(path, "must be <= %s" % rule.max)


# --- Rules that span fields or entries -------------------------------------

func _check_cross_rules() -> void:
	for rec in _raw.get_entries("creatures"):
		var c: Dictionary = rec.entry
		_file = rec.file
		_label = "[creatures:%s]" % c.get("id", "?")
		var learnset = c.get("learnset", [])
		if learnset is Array and not learnset.any(func(l): return l is Dictionary and l.get("level") == 1.0):
			_err("learnset", "needs at least one level-1 move")
		var growth = c.get("growth", [])
		if growth is Array:
			var defaults_per_level := {}
			for g in growth:
				if not g is Dictionary:
					continue
				if g.get("into") == c.get("id"):
					_err("growth", "creature cannot grow into itself")
				if g.has("affinity") == g.get("default", false):
					_err("growth", "each branch needs exactly one of 'affinity' or 'default: true'")
				if g.get("default", false):
					var lvl = g.get("level")
					if defaults_per_level.has(lvl):
						_err("growth", "more than one default branch at level %s" % lvl)
					defaults_per_level[lvl] = true

	for rec in _raw.get_entries("encounters"):
		var e: Dictionary = rec.entry
		_file = rec.file
		_label = "[encounters:%s]" % e.get("id", "?")
		if _is_number(e.get("pack_min")) and _is_number(e.get("pack_max")) and e.pack_min > e.pack_max:
			_err("pack_min", "pack_min must be <= pack_max")
		for row in e.get("table", []):
			if row is Dictionary and _is_number(row.get("min_level")) and _is_number(row.get("max_level")) \
					and row.min_level > row.max_level:
				_err("table", "min_level must be <= max_level for %s" % row.get("species"))

	for rec in _raw.get_entries("reactions"):
		var r: Dictionary = rec.entry
		_file = rec.file
		_label = "[reactions:%s]" % r.get("id", "?")
		var inputs = r.get("inputs", [])
		for s in r.get("consumes", []):
			if inputs is Array and not s in inputs:
				_err("consumes", "'%s' is not one of the inputs" % s)

	for rec in _raw.get_entries("minigames"):
		var g: Dictionary = rec.entry
		_file = rec.file
		_label = "[minigames:%s]" % g.get("id", "?")
		if g.get("scene") is String and not ResourceLoader.exists(g.scene):
			_err("scene", "scene file not found: %s" % g.scene)

	for rec in _raw.get_entries("moves"):
		var m: Dictionary = rec.entry
		_file = rec.file
		_label = "[moves:%s]" % m.get("id", "?")
		if m.get("category") == "status" and m.get("power", 0) != 0.0:
			_err("power", "status moves must have power 0")
		if m.get("category") in ["physical", "special"] and m.get("power", 0) == 0.0:
			_err("power", "damaging moves need power > 0")


func _check_dialogue() -> void:
	var regex := RegEx.create_from_string(_BATTLE_CALL_PATTERN)
	for path in _raw.dialogue_files:
		var text: String = _raw.dialogue_files[path]
		for m in regex.search_all(text):
			var tamer := m.get_string(1)
			if not _ids["tamers"].has(tamer):
				_errors.append("%s: start_battle references unknown tamer id '%s'" % [path, tamer])


# --- Helpers ----------------------------------------------------------------

func _err(path: String, msg: String) -> void:
	var where := _label if path.is_empty() else "%s %s" % [_label, path]
	_errors.append("%s %s: %s" % [_file, where, msg])


static func _join(path: String, key: String) -> String:
	return key if path.is_empty() else "%s.%s" % [path, key]


static func _is_number(v: Variant) -> bool:
	return v is int or v is float
