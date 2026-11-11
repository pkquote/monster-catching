extends Node
## Unlocks achievements. Everything that changes a counter, the Codex, a story flag or a creature
## pushes a key into AchievementWatch; each frame this drains the keys and checks only the locked
## achievements that watch them, so an idle frame costs one empty check and a step costs one compare.
## `unlocked(id)` is the seam for a toast or a platform (Steam) bridge; nothing subscribes yet.

signal unlocked(id: String)

## Achievements checked so far (a diagnostic: tests use it to show what was and was not evaluated).
var checks := 0

var _index: Dictionary = {}
var _index_db: Database
var _known_save: SaveGame


func _process(_delta: float) -> void:
	flush()


## Drains the watch keys and unlocks whatever they have met. Returns the ids unlocked by this call.
func flush() -> PackedStringArray:
	var out := PackedStringArray()
	var save := GameState.current
	if save != _known_save:  # a new game or a load: catch up on everything already earned
		_known_save = save
		if save != null:
			AchievementWatch.push(AchievementWatch.ALL)
	if AchievementWatch.is_empty():
		return out
	var keys := AchievementWatch.drain()
	if save == null:
		return out
	var db := DataRegistry.db
	if db != _index_db:
		_index = Achievements.watch_index(db)
		_index_db = db
	var wanted := {}
	if keys.has(AchievementWatch.ALL):
		for id in db.ids("achievements"):
			wanted[id] = true
	else:
		for key in keys:
			for id in _index.get(key, PackedStringArray()):
				wanted[id] = true
	var candidates := wanted.keys().filter(func(id: String) -> bool: return not Achievements.is_unlocked(save, id))
	checks += candidates.size()
	for id in Achievements.check(db, save, candidates):
		if unlock(id):
			out.append(id)
	return out


## Unlocks `id` now. False when there is no game, no such achievement, or it is already unlocked.
func unlock(id: String) -> bool:
	var save := GameState.current
	if save == null or DataRegistry.db.achievement(id) == null or Achievements.is_unlocked(save, id):
		return false
	Achievements.unlock(save, id, int(Time.get_unix_time_from_system()))
	Log.info(Log.SAVE, "Achievement unlocked", {"id": id})
	unlocked.emit(id)
	return true
