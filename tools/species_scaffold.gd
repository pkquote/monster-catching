class_name SpeciesScaffold
extends RefCounted
## Builds the data for a new species line (1 to 3 stages) that validates against the shipped data.
## build() is pure: it reads a Database and touches no file. write_line() writes the result for
## tools/new_species_line.gd, after checking that the combined data validates.
## The placeholders are valid, not good: the author replaces them.

const STAT_IDS := ["hp", "patk", "pdef", "satk", "sdef", "spd", "luck", "resolve", "stamina"]
const EVOLVE_STEP := 16
const BASE_STAT := 50
const STAT_PER_STAGE := 10
const CATCH_RATE := 0.45
const XP_YIELD_PER_STAGE := 50
const SECOND_MOVE_LEVEL := 8
const DESCRIPTION := "A new species. Replace this description."


## { "ok": true, "doc": {schema, entries} } or { "ok": false, "error": String }.
static func build(db: Database, name: String, types: Array, stages: int) -> Dictionary:
	var problem := _problem(db, name, types, stages)
	if problem != "":
		return _fail(problem)
	var top := 0
	for id in db.ids("creatures"):
		top = maxi(top, db.creature(id).dex)
	var first: String = _pick_move(db, types, "")
	var second: String = _pick_move(db, types, first)
	if first == "" or second == "" or first == second:
		return _fail("the data needs at least two moves to fill a learnset")
	var entries: Array = []
	for i in range(1, stages + 1):
		entries.append(_stage(db, name, types, i, stages, top + i, [first, second]))
	return {"ok": true, "doc": {"schema": 1, "entries": entries}}


## The first reason the arguments can't make a line, or "" when they can.
static func _problem(db: Database, name: String, types: Array, stages: int) -> String:
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(name) == null:
		return "name '%s' must be lowercase snake_case" % name
	if stages < 1 or stages > 3:
		return "stages must be 1 to 3, got %d" % stages
	if types.size() < 1 or types.size() > 2:
		return "types must be 1 or 2, got %d" % types.size()
	if types.size() == 2 and types[0] == types[1]:
		return "type '%s' is listed twice" % types[0]
	for t in types:
		if not db.has("types", t):
			return "unknown type '%s'" % t
	for i in range(1, stages + 1):
		if db.has("creatures", "%s_%d" % [name, i]):
			return "species id '%s_%d' already exists" % [name, i]
	if db.count("passives") == 0:
		return "the data has no passives to assign"
	return ""


## Stage `i` (1-based) of a `stages`-stage line; `moves` are the level-1 and second learnset moves.
static func _stage(db: Database, name: String, types: Array, i: int, stages: int, dex: int, moves: Array) -> Dictionary:
	var stats := {}
	for s: String in STAT_IDS:
		stats[s] = BASE_STAT + STAT_PER_STAGE * (i - 1)
	var passive: String = db.ids("passives")[0]
	var e := {
		"id": "%s_%d" % [name, i],
		"name": "%s %d" % [name.capitalize(), i],
		"dex": dex,
		"description": DESCRIPTION,
		"types": types.duplicate(),
		"base_stats": stats,
		"catch_rate": CATCH_RATE,
		"xp_yield": XP_YIELD_PER_STAGE * i,
		"learnset": [{"level": 1, "move": moves[0]}, {"level": SECOND_MOVE_LEVEL, "move": moves[1]}],
		"passives": [passive],
	}
	if db.count("affinities") > 0:
		var ap := {}
		for a in db.ids("affinities"):
			ap[a] = passive
		e["affinity_passives"] = ap
	if i < stages:
		e["growth"] = [{"level": EVOLVE_STEP * i, "default": true, "into": "%s_%d" % [name, i + 1]}]
	return e


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


## Builds the line from `raw` and writes `<dir>/<name>_line.json`, but only when the file does not exist and
## the data with the new line added validates (checked on a copy: `raw` is left unchanged). Returns
## { ok, path, doc } or { ok: false, error }. Nothing is written on failure.
static func write_line(raw: RawData, dir: String, name: String, types: Array, stages: int) -> Dictionary:
	var path := dir.path_join("%s_line.json" % name)
	if FileAccess.file_exists(path):
		return _fail("%s already exists; not overwriting" % path)
	var built := build(Database.from_raw(raw), name, types, stages)
	if not built.ok:
		return built
	var combined := RawData.new()
	combined.entries = raw.entries.duplicate(true)
	combined.singles = raw.singles.duplicate(true)
	combined.dialogue_files = raw.dialogue_files.duplicate()
	for e: Dictionary in built.doc.entries:
		combined.add_entry("creatures", e)
	var errors := DataValidator.validate(combined)
	if not errors.is_empty():
		return _fail("the new line would not validate:\n" + "\n".join(errors))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _fail("can't write %s" % path)
	f.store_string(to_json(built.doc))
	f.close()
	return {"ok": true, "path": path, "doc": built.doc}
