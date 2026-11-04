extends Node
## The one API that map pieces and .dialogue scripts use to read and change the
## playthrough (autoload `Story`). Acts on GameState.current; everything here is
## a thin wrapper so a pickup and a script line behave identically.
##
## In .dialogue files: `$> Story.give_item("salve")`, `if Story.flag("got_starter")`.


func _save() -> SaveGame:
	return GameState.current


func _story() -> StoryState:
	return GameState.current.story


# --- Flags, counters, one-time pieces ---------------------------------------------

func flag(id: String) -> bool:
	return GameState.has_game() and _story().flag(id)


func set_flag(id: String, on := true) -> void:
	Log.info(Log.STORY, "Flag set", {"flag": id, "on": on})
	_story().set_flag(id, on)


func count(id: String) -> int:
	return _story().count(id) if GameState.has_game() else 0


func add_count(id: String, n := 1) -> void:
	_story().add_count(id, n)
	Log.debug(Log.STORY, "Counter changed", {"counter": id, "by": n, "now": _story().count(id)})


func is_done(key: String) -> bool:
	return GameState.has_game() and _story().is_done(key)


func mark_done(key: String) -> void:
	Log.debug(Log.STORY, "Marked done", {"key": key})
	_story().mark_done(key)


# --- Bag and money ------------------------------------------------------------------

func give_item(id: String, n := 1) -> void:
	var inv := _save().inventory
	inv[id] = int(inv.get(id, 0)) + n
	Log.debug(Log.STORY, "Item given", {"item": id, "count": n, "now": inv[id]})


## Removes `n` of an item. Returns false (and removes nothing) when there aren't enough.
func take_item(id: String, n := 1) -> bool:
	if not has_item(id, n):
		return false
	var inv := _save().inventory
	inv[id] = int(inv[id]) - n
	Log.debug(Log.STORY, "Item taken", {"item": id, "count": n, "left": inv[id]})
	if inv[id] <= 0:
		inv.erase(id)
	return true


func has_item(id: String, n := 1) -> bool:
	return GameState.has_game() and int(_save().inventory.get(id, 0)) >= n


func money() -> int:
	return _save().money if GameState.has_game() else 0


func give_money(n: int) -> void:
	_save().money += n
	Log.debug(Log.STORY, "Money given", {"amount": n, "now": _save().money})


## Spends `n` money. Returns false (and spends nothing) when there isn't enough.
func take_money(n: int) -> bool:
	if money() < n:
		return false
	_save().money -= n
	Log.debug(Log.STORY, "Money taken", {"amount": n, "now": _save().money})
	return true


# --- Creatures ----------------------------------------------------------------------

## A fresh creature joins the party (or storage when the party is full).
## `starter` gives it starter Bond.
func give_creature(species: String, level: int, starter := false) -> CreatureInstance:
	var db := DataRegistry.db
	var c := CreatureInstance.create(db, species, level)
	if starter:
		Bond.make_starter(db, c)
	var to_party := BattleLauncher.add_to_party(db, _save(), c)
	Log.info(Log.STORY, "Creature given", {"species": species, "level": level, "starter": starter,
		"to": "party" if to_party else "storage"})
	return c


func party_size() -> int:
	return _save().party.size() if GameState.has_game() else 0


## Rests the whole party: full HP and energy, status cleared, "rested" Bond change.
func heal_party() -> void:
	Log.info(Log.STORY, "Party healed", {"party": _save().party.size()})
	for c: CreatureInstance in _save().party:
		Bond.rest(DataRegistry.db, c)


## Where the player wakes after losing a battle.
func set_last_heal(map_id: String, spawn_id: String) -> void:
	_story().last_heal = {"map": map_id, "spawn": spawn_id}
	Log.debug(Log.STORY, "Wake-up point set", {"map": map_id, "spawn": spawn_id})


# --- Minigames ---------------------------------------------------------------------

var _last_minigame: Dictionary = {}


## Plays a minigame from data/minigames.json over the paused map (await it in
## scripts). Returns its result { won, score, ... }; an unknown id counts as a loss.
func start_minigame(id: String, params := {}) -> Dictionary:
	Log.info(Log.MINIGAME, "Minigame started", {"id": id})
	var def := DataRegistry.db.minigame(id)
	if def == null:
		Log.error(Log.STORY, "start_minigame: no such minigame", {"id": id})
		_last_minigame = {"won": false, "score": 0}
		return _last_minigame
	return await start_minigame_scene(def.scene, params)


## Same, from a scene path (tests use a stub scene).
func start_minigame_scene(scene_path: String, params := {}) -> Dictionary:
	var world := Overworld.active
	if world != null:
		world.lock(Overworld.LOCK_MINIGAME)
	var layer := CanvasLayer.new()
	layer.layer = 75
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var game: Minigame = load(scene_path).instantiate()
	layer.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # cover the whole screen
	get_tree().paused = true
	game.begin(params)
	var result: Dictionary = await game.finished
	get_tree().paused = false
	layer.queue_free()
	if world != null and is_instance_valid(world):
		world.unlock(Overworld.LOCK_MINIGAME)
	_last_minigame = {"won": bool(result.get("won", false)), "score": int(result.get("score", 0))}
	_last_minigame.merge(result)
	Log.info(Log.MINIGAME, "Minigame finished", {"scene": scene_path, "won": _last_minigame.won,
		"score": _last_minigame.score})
	return _last_minigame


func last_minigame() -> Dictionary:
	return _last_minigame


func last_minigame_won() -> bool:
	return bool(_last_minigame.get("won", false))


# --- Battles --------------------------------------------------------------------------

## Tests set this to stand in for real battles: Callable(tamer_id) -> bool (won).
var battle_override: Callable
## { tamer_id, defeat_rules } of the last start_battle call (tests check story battles).
var last_battle_request: Dictionary = {}
var _last_won := false


## Battles a tamer from the data, then carries on (await it in scripts):
## "how many?", the battle over the map, then the outcome. Returns true for a win.
## `defeat_rules` false: a loss just heals the team (story battles you can lose).
func start_battle(tamer_id: String, defeat_rules := true) -> bool:
	last_battle_request = {"tamer_id": tamer_id, "defeat_rules": defeat_rules}
	Log.info(Log.STORY, "Story battle", {"tamer": tamer_id, "defeat_rules": defeat_rules,
		"override": battle_override.is_valid()})
	if battle_override.is_valid():
		_last_won = await battle_override.call(tamer_id)
		return _last_won
	var world := Overworld.active
	if world == null or not GameState.has_game():
		Log.error(Log.STORY, "start_battle: no overworld open", {"tamer": tamer_id})
		return false
	var t := DataRegistry.db.tamer(tamer_id)
	var n = await FieldCountPrompt.ask(world, t.max_active, "%s fields %d at a time." % [t.name, t.max_active], false)
	_last_won = await world.battles.run_battle(
		BattleLauncher.tamer_setup(DataRegistry.db, GameState.current, tamer_id, n), defeat_rules)
	return _last_won


func last_battle_won() -> bool:
	return _last_won


## Clears the last result, so a script that never battles can't reuse an old win.
func forget_last_battle() -> void:
	_last_won = false
