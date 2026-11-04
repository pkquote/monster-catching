extends Node
## The playthrough in progress: current save data, playtime, saving and loading.

var store := SaveStore.new()
var current: SaveGame
var current_path := ""
var _tracking := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if _tracking and current != null:
		current.playtime_sec += delta


func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func has_game() -> bool:
	return current != null


## Creates a new playthrough and its first manual save. Returns "" or an error.
func start_new_game(player_name: String) -> String:
	current = SaveGame.new_game(player_name, now_ms() / 1000, _rng)
	current_path = store.write(current, SaveGame.KIND_MANUAL, now_ms())
	if current_path == "":
		current = null
		return "Couldn't write the save file."
	return ""


## Loads a save as the current game. Returns "" or an error.
func load_from(path: String) -> String:
	var r := store.read(path)
	if not r.ok:
		Log.warn(Log.SAVE, "Load failed", {"path": path, "error": r.error})
		return r.error
	current = r.save
	for c: CreatureInstance in current.party + current.storage:
		Progression.backfill_pool(DataRegistry.db, c)
	current_path = path
	store.set_last(path)
	Log.info(Log.SAVE, "Loaded", {"path": path, "player": current.player_name,
		"location": current.location, "party": current.party.size(), "storage": current.storage.size()})
	return ""


func resume_path() -> String:
	return store.last_path()


func save_manual() -> String:
	return _write(SaveGame.KIND_MANUAL)


func autosave() -> String:
	return _write(SaveGame.KIND_AUTO)


## Called by the world when the player is in control (playtime runs, autosave).
func enter_world() -> void:
	_tracking = true
	autosave()


func leave_world() -> void:
	_tracking = false


func close_game() -> void:
	leave_world()
	current = null
	current_path = ""


## Set by the overworld while it's open: writes the player's exact position into
## `current` so every save (auto or manual) resumes where the player stands.
var position_provider: Callable


func _write(kind: String) -> String:
	if current == null:
		return ""
	if position_provider.is_valid():
		position_provider.call()
	var path := store.write(current, kind, now_ms())
	if path != "":
		current_path = path
		Log.info(Log.SAVE, "Saved", {"path": path, "kind": kind, "location": current.location})
	else:
		Log.error(Log.SAVE, "Save failed", {"kind": kind, "root": store.root})
	return path
