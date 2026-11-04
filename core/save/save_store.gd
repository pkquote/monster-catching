class_name SaveStore
extends RefCounted
## Save files on disk: unlimited manual saves plus one autosave per playthrough.
##
##   <root>/<playthrough_id>/autosave.json
##   <root>/<playthrough_id>/save_<unix_ms>.json
##   <root>/last.json            -> { "path": "<most recently loaded or written save>" }
##
## Writes are atomic (temp file, then replace). Unreadable files are reported as
## damaged, never thrown. Takes a root directory so tests can use a temp folder.

const AUTOSAVE_FILE := "autosave.json"
const LAST_FILE := "last.json"

## schema -> Callable(Dictionary) -> Dictionary that upgrades a save by one version.
## Add an entry here whenever SaveGame.SCHEMA goes up.
static func migrations() -> Dictionary:
	return {1: _v1_to_v2, 2: _v2_to_v3}

var root: String


## Schema 1 -> 2 (M3): top-level `flags` move into `story`; no position yet, so the
## save resumes at the new-game spawn.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["story"] = {"flags": out.get("flags", {})}
	out.erase("flags")
	out["position"] = {}
	out["schema"] = 2
	return out


## Schema 2 -> 3 (M4): creatures gain a move pool. Starts as their current moves;
## GameState.load_from tops it up from the learnset (core can't see the database).
static func _v2_to_v3(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	for key in ["party", "storage"]:
		for c in out.get(key, []):
			c["move_pool"] = c.get("moves", []).duplicate()
	out["schema"] = 3
	return out


func _init(p_root: String = "user://saves") -> void:
	root = p_root


# --- Writing -------------------------------------------------------------------

## Writes `save` as a manual save (new file) or the playthrough's autosave.
## Updates saved_unix and the Resume pointer. Returns the file path, or "" on failure.
func write(save: SaveGame, kind: String, now_unix_ms: int) -> String:
	save.kind = kind
	save.saved_unix = now_unix_ms / 1000
	var dir := root.path_join(save.playthrough_id)
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return ""
	var path: String
	if kind == SaveGame.KIND_AUTO:
		path = dir.path_join(AUTOSAVE_FILE)
	else:
		path = dir.path_join("save_%d.json" % now_unix_ms)
		var n := 1
		while FileAccess.file_exists(path):
			path = dir.path_join("save_%d_%d.json" % [now_unix_ms, n])
			n += 1
	if not _write_atomic(path, JSON.stringify(save.to_dict(), "\t")):
		return ""
	set_last(path)
	return path


func set_last(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	_write_atomic(root.path_join(LAST_FILE), JSON.stringify({"path": path}))


## The Resume target, or "" if none or the file is gone.
func last_path() -> String:
	var lp := root.path_join(LAST_FILE)
	if not FileAccess.file_exists(lp):
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(lp))
	if not data is Dictionary or not data.get("path") is String:
		return ""
	var path: String = data.path
	return path if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp") else ""


func delete(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var ok := DirAccess.remove_absolute(path) == OK
	# Deleting the Resume target clears Resume.
	if ok and _last_raw() == path:
		DirAccess.remove_absolute(root.path_join(LAST_FILE))
	# Remove the playthrough folder once it's empty.
	var dir := path.get_base_dir()
	var d := DirAccess.open(dir)
	if d != null and d.get_files().is_empty() and d.get_directories().is_empty():
		DirAccess.remove_absolute(dir)
	return ok


# --- Reading -------------------------------------------------------------------

## Returns { ok: bool, save: SaveGame or null, error: String }.
func read(path: String) -> Dictionary:
	var real := path
	if not FileAccess.file_exists(real):
		if FileAccess.file_exists(path + ".tmp"):
			real = path + ".tmp"  # interrupted write: the temp copy is complete
		else:
			return _fail("file not found")
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(real)) != OK:
		return _fail("not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return _fail("not a save file")
	var d: Dictionary = json.data
	var version = d.get("schema")
	if not (version is int or version is float):
		return _fail("missing schema version")
	var v := int(version)
	var from_schema := v
	if v > SaveGame.SCHEMA:
		return _fail("made by a newer version of the game (schema %d)" % v)
	while v < SaveGame.SCHEMA:
		var steps := migrations()
		if not steps.has(v):
			return _fail("no upgrade path from schema %d" % v)
		d = steps[v].call(d)
		v += 1
	if from_schema < SaveGame.SCHEMA:
		Log.info(Log.SAVE, "Migrated", {"path": path, "from": from_schema, "to": SaveGame.SCHEMA})
	var save := SaveGame.from_dict(d)
	if save == null:
		return _fail("missing required fields")
	return {"ok": true, "save": save, "error": ""}


## Every save file, newest first. Each entry:
## { path, playthrough_id, kind, player_name, saved_unix, playtime_sec, location,
##   party_size, damaged: bool, error }
func list() -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for pid in d.get_directories():
		var dir := root.path_join(pid)
		var pd := DirAccess.open(dir)
		if pd == null:
			continue
		var files := {}
		for f in pd.get_files():
			if f.ends_with(".json"):
				files[f] = true
			elif f.ends_with(".json.tmp"):
				files[f.trim_suffix(".tmp")] = true  # orphaned temp of a missing file
		for f in files:
			out.append(_summary(dir.path_join(f), pid))
	out.sort_custom(func(a, b): return a.saved_unix > b.saved_unix)
	return out


## Saves grouped by playthrough: most recent playthrough first, newest save first.
## Each group: { playthrough_id, player_name, latest_unix, saves: Array }
func list_grouped() -> Array:
	var groups := {}
	var order: Array = []
	for entry in list():
		var pid: String = entry.playthrough_id
		if not groups.has(pid):
			groups[pid] = {"playthrough_id": pid, "player_name": entry.player_name,
				"latest_unix": entry.saved_unix, "saves": []}
			order.append(pid)
		if groups[pid].player_name == "" and entry.player_name != "":
			groups[pid].player_name = entry.player_name
		groups[pid].saves.append(entry)
	return order.map(func(pid): return groups[pid])


# --- Internals -------------------------------------------------------------------

func _summary(path: String, pid: String) -> Dictionary:
	var r := read(path)
	var entry := {"path": path, "playthrough_id": pid, "kind": "", "player_name": "",
		"saved_unix": 0, "playtime_sec": 0.0, "location": "", "party_size": 0,
		"damaged": not r.ok, "error": r.error}
	if r.ok:
		var s: SaveGame = r.save
		entry.kind = s.kind
		entry.player_name = s.player_name
		entry.saved_unix = s.saved_unix
		entry.playtime_sec = s.playtime_sec
		entry.location = s.location
		entry.party_size = s.party.size()
	else:
		entry.saved_unix = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	return entry


func _last_raw() -> String:
	var lp := root.path_join(LAST_FILE)
	if not FileAccess.file_exists(lp):
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(lp))
	return data.get("path", "") if data is Dictionary else ""


static func _write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		return false
	return DirAccess.rename_absolute(tmp, path) == OK


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "save": null, "error": reason}
