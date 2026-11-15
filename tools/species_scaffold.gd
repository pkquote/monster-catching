class_name SpeciesScaffold
extends RefCounted
## Builds the data for a new species line (1 to 3 stages) that validates against the shipped data.
## Pure: reads the Database, touches no file. tools/new_species_line.gd writes the result.
## The placeholders are valid, not good: the author replaces them.

const STAT_IDS := ["hp", "patk", "pdef", "satk", "sdef", "spd", "luck", "resolve", "stamina"]
const EVOLVE_STEP := 16


## { "ok": true, "doc": {schema, entries} } or { "ok": false, "error": String }.
static func build(db: Database, name: String, types: Array, stages: int) -> Dictionary:
	var rx := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	if rx.search(name) == null:
		return _fail("name '%s' must be lowercase snake_case" % name)
	if stages < 1 or stages > 3:
		return _fail("stages must be 1 to 3, got %d" % stages)
	if types.size() < 1 or types.size() > 2:
		return _fail("types must be 1 or 2, got %d" % types.size())
	if types.size() == 2 and types[0] == types[1]:
		return _fail("type '%s' is listed twice" % types[0])
	for t in types:
		if not db.has("types", t):
			return _fail("unknown type '%s'" % t)
	for i in range(1, stages + 1):
		if db.has("creatures", "%s_%d" % [name, i]):
			return _fail("species id '%s_%d' already exists" % [name, i])
	if db.count("passives") == 0:
		return _fail("the data has no passives to assign")

	var top := 0
	for id in db.ids("creatures"):
		top = maxi(top, db.creature(id).dex)
	var first: String = _pick_move(db, types, "")
	var second: String = _pick_move(db, types, first)
	if first == "" or second == "" or first == second:
		return _fail("the data needs at least two moves to fill a learnset")
	var passive: String = db.ids("passives")[0]

	var entries: Array = []
	for i in range(1, stages + 1):
		var stats := {}
		for s: String in STAT_IDS:
			stats[s] = 50 + 10 * (i - 1)
		var e := {
			"id": "%s_%d" % [name, i],
			"name": "%s %d" % [name.capitalize(), i],
			"dex": top + i,
			"description": "A new species. Replace this description.",
			"types": types.duplicate(),
			"base_stats": stats,
			"catch_rate": 0.45,
			"xp_yield": 50 * i,
			"learnset": [{"level": 1, "move": first}, {"level": 8, "move": second}],
			"passives": [passive],
		}
		if db.count("affinities") > 0:
			var ap := {}
			for a in db.ids("affinities"):
				ap[a] = passive
			e["affinity_passives"] = ap
		if i < stages:
			e["growth"] = [{"level": EVOLVE_STEP * i, "default": true, "into": "%s_%d" % [name, i + 1]}]
		entries.append(e)
	return {"ok": true, "doc": {"schema": 1, "entries": entries}}


static func to_json(doc: Dictionary) -> String:
	return JSON.stringify(doc, "\t") + "\n"


## The first move of the first type that has one (else the first neutral move) that is not `skip`.
static func _pick_move(db: Database, types: Array, skip: String) -> String:
	for want: String in types + ["neutral"]:
		for id in db.ids("moves"):
			if id != skip and db.move(id).type == want:
				return id
	return skip


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


## Builds the line and writes `<dir>/<name>_line.json`, but only when the file does not exist and the
## result validates. `raw` is the data `db` was built from; the new entries are added to it for the
## validation. Returns { ok, path, doc } or { ok: false, error }. Nothing is written on failure.
static func write_line(raw: RawData, db: Database, dir: String, name: String, types: Array, stages: int) -> Dictionary:
	var path := dir.path_join("%s_line.json" % name)
	if FileAccess.file_exists(path):
		return _fail("%s already exists; not overwriting" % path)
	var built := build(db, name, types, stages)
	if not built.ok:
		return built
	for e: Dictionary in built.doc.entries:
		raw.add_entry("creatures", e)
	var errors := DataValidator.validate(raw)
	if not errors.is_empty():
		return _fail("the new line would not validate:\n" + "\n".join(errors))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _fail("can't write %s" % path)
	f.store_string(to_json(built.doc))
	f.close()
	return {"ok": true, "path": path, "doc": built.doc}
