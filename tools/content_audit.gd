class_name ContentAudit
extends RefCounted
## The M9 content guards as pure functions: each takes a Database (and, where the answer lives in
## dialogue or map scenes, their source text) and returns a sorted Array of offending ids; empty is clean.
## Used by tests/data/test_content_reachability.gd. Item and gift detection searches source text for
## specific call and property patterns, so renaming an id in a dialogue or scene must keep the string.

const DIALOGUE_ROOT := "res://dialogue"
const MAPS_ROOT := "res://game/maps"


## Every shipped .dialogue file and every map scene except test maps (test_*) and the template (_*).
static func shipped_files() -> Array:
	var out: Array = []
	_walk(DIALOGUE_ROOT, ".dialogue", out)
	for f in DirAccess.get_files_at(MAPS_ROOT):
		if f.ends_with(".tscn") and not f.begins_with("test_") and not f.begins_with("_"):
			out.append(MAPS_ROOT.path_join(f))
	out.sort()
	return out


static func shipped_text() -> String:
	var parts := PackedStringArray()
	for p: String in shipped_files():
		parts.append(FileAccess.get_file_as_string(p))
	return "\n".join(parts)


## Species nobody can obtain: not given by dialogue, not in a table some location uses, and not an
## evolution (repeated) of one that is.
static func unobtainable_species(db: Database, source: String) -> Array:
	var text := _without_comments(source)
	var reached := {}
	for id in db.ids("creatures"):
		if text.contains('give_creature("%s"' % id):
			reached[id] = true
	for loc in db.ids("locations"):
		for table_id in db.location(loc).areas:
			if not db.has("encounters", table_id):
				continue
			for row: Dictionary in db.encounter(table_id).table:
				reached[row.species] = true
	var changed := true
	while changed:
		changed = false
		for id: String in reached.keys():
			for g: Dictionary in db.creature(id).growth:
				if not reached.has(g.into):
					reached[g.into] = true
					changed = true
	return _missing(db.ids("creatures"), reached)


static func orphan_passives(db: Database) -> Array:
	var used := {}
	for id in db.ids("creatures"):
		var c := db.creature(id)
		for p in c.passives:
			used[p] = true
		for p in c.affinity_passives.values():
			used[p] = true
	return _missing(db.ids("passives"), used)


## Items nothing gives, sells or places. Placing is an allowlist of the three ways content supplies an
## item: `give_item("id"` in dialogue, an `item = "id"` pickup property, and a shop
## `stock = PackedStringArray(...)`. Any other mention of the id (a check, a removal, a flag) does not count.
static func orphan_items(db: Database, source: String) -> Array:
	var placed := _placed_item_ids(_without_comments(source))
	return _missing(db.ids("items"), placed)


static func unused_encounters(db: Database) -> Array:
	var used := {}
	for loc in db.ids("locations"):
		for t in db.location(loc).areas:
			used[t] = true
	return _missing(db.ids("encounters"), used)


## Moves some species could have (it has the move's type) but nobody learns. The fallback move is excluded.
static func orphan_moves(db: Database) -> Array:
	var learned := {}
	var populated := {}
	for id in db.ids("creatures"):
		var c := db.creature(id)
		for t in c.types:
			populated[t] = true
		for l: Dictionary in c.learnset:
			learned[l.move] = true
	var fallback: String = db.balance.energy_cfg.get("fallback_move", "")
	var out: Array = []
	for id in db.ids("moves"):
		if id != fallback and not learned.has(id) and populated.has(db.move(id).type):
			out.append(id)
	out.sort()
	return out


## The ids not in `used` (a Dictionary keyed by id), sorted.
static func _missing(ids, used: Dictionary) -> Array:
	var out: Array = []
	for id in ids:
		if not used.has(id):
			out.append(id)
	out.sort()
	return out


static func _walk(dir: String, suffix: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(suffix):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), suffix, out)


## `source` without its comment lines (`#` in dialogue, `;` in scenes).
static func _without_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		var s := line.strip_edges(true, false)
		if not (s.begins_with("#") or s.begins_with(";")):
			kept.append(line)
	return "\n".join(kept)


static func _placed_item_ids(text: String) -> Dictionary:
	var placed := {}
	var id_rx := RegEx.create_from_string(r'"([a-z0-9_]+)"')
	for pattern in [r'give_item\("([a-z0-9_]+)"', r'\bitem = "([a-z0-9_]+)"']:
		for m in RegEx.create_from_string(pattern).search_all(text):
			placed[m.get_string(1)] = true
	for m in RegEx.create_from_string(r'\bstock = PackedStringArray\(([^)]*)\)').search_all(text):
		for q in id_rx.search_all(m.get_string(1)):
			placed[q.get_string(1)] = true
	return placed
