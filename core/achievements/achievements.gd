class_name Achievements
extends RefCounted
## Pure achievement logic over a Database and a SaveGame: which are listed, how far along each is,
## which watch keys each depends on, and which locked ones are now met. Nothing here writes a save
## except `unlock` and `reset`; the AchievementService decides when to check.


## Ids shown to the player, in data order (test content is left out).
static func listed(db: Database) -> PackedStringArray:
	var out := PackedStringArray()
	for id in db.ids("achievements"):
		if not Database.is_test_content(id):
			out.append(id)
	return out


static func is_unlocked(save: SaveGame, id: String) -> bool:
	return save.achievements.has(id)


## How many listed achievements are unlocked (ids the data no longer has are ignored).
static func unlock_count(db: Database, save: SaveGame) -> int:
	var n := 0
	for id in listed(db):
		if is_unlocked(save, id):
			n += 1
	return n


## `{"current": int, "target": int}` for `id`; empty when the id or its kind is unknown.
static func progress(db: Database, save: SaveGame, id: String) -> Dictionary:
	var def := db.achievement(id)
	if def == null:
		return {}
	var criterion := Criteria.for_kind(str(def.criterion.get("kind", "")))
	return criterion.progress(db, save, def.criterion) if criterion != null else {}


static func is_met(db: Database, save: SaveGame, id: String) -> bool:
	var p := progress(db, save, id)
	return not p.is_empty() and p.current >= p.target


## Watch key -> the ids that depend on it.
static func watch_index(db: Database) -> Dictionary:
	var index := {}
	for id in db.ids("achievements"):
		var def := db.achievement(id)
		var criterion := Criteria.for_kind(str(def.criterion.get("kind", "")))
		if criterion == null:
			continue
		for key in criterion.watches(def.criterion):
			if not index.has(key):
				index[key] = PackedStringArray()
			index[key].append(id)
	return index


## The ids among `ids` that are locked and met. Writes nothing.
static func check(db: Database, save: SaveGame, ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in ids:
		if not is_unlocked(save, id) and is_met(db, save, id):
			out.append(id)
	return out


## The locked, met ids among the achievements that watch `keys`; every locked one when `keys` is
## empty or holds AchievementWatch.ALL.
static func evaluate(db: Database, save: SaveGame, keys: PackedStringArray) -> PackedStringArray:
	if keys.is_empty() or keys.has(AchievementWatch.ALL):
		return check(db, save, Array(db.ids("achievements")))
	var index := watch_index(db)
	var ids := {}
	for key in keys:
		for id in index.get(key, PackedStringArray()):
			ids[id] = true
	return check(db, save, ids.keys())


static func unlock(save: SaveGame, id: String, unix: int) -> void:
	save.achievements[id] = unix


## Locks `id` again, or every achievement when `id` is empty.
static func reset(save: SaveGame, id: String = "") -> void:
	if id.is_empty():
		save.achievements.clear()
	else:
		save.achievements.erase(id)
