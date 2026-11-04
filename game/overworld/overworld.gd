class_name Overworld
extends Node2D
## The overworld screen (SceneRouter.WORLD): one map at a time, the player, the
## camera and the screen fade. Pieces call back into it (change_map, say...).
##
## Locks: any system that needs the player to stand still takes a named lock
## (conversation, menu, map change, cutscene). The player moves only when no
## lock is held.

signal map_changed(map: GameMap)

const FADE_TIME := 0.2
const VIEW := Vector2(640, 360)
## Fallback map when nothing says where to start (no game loaded, debug runs).
const DEBUG_MAP := "test_a"

## Tests set this to skip fade waits.
static var instant := false

var map: GameMap
var player: Player
var camera: Camera2D
var banner: LocationBanner
var dialogue_box: DialogueBox
var pause_menu: PauseMenu
var shop_menu: ShopMenu

## Seeded per session; tests replace it (and `roller`) for deterministic rolls.
var rng := RandomNumberGenerator.new()
var roller: EncounterRoller
var walker: WalkTracker
## Tests set this to catch wild encounters instead of changing scene: Callable(table_id).
var wild_override: Callable
## The overworld that's open, if any (Story and the debug menu reach it here).
static var active: Overworld

## Where a cutscene points the camera (Vector2), or null to follow the player.
var camera_focus: Variant = null

var _locks: Dictionary = {}
var _last_location := ""
var _talking := false
var _battle_layer: CanvasLayer
## The tamer whose challenge is running: { tamer_id, key }. A win against them is
## marked before the battle's autosave.
var _challenger: Dictionary = {}
var _fade: ColorRect


func _ready() -> void:
	RenderingServer.set_default_clear_color(UIKit.BG)  # outside small indoor maps
	player = load("res://game/overworld/player.tscn").instantiate()
	player.tile_entered.connect(_on_tile_entered)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	banner = LocationBanner.new()
	add_child(banner)
	dialogue_box = DialogueBox.new()
	add_child(dialogue_box)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	shop_menu = ShopMenu.new()
	add_child(shop_menu)
	map_changed.connect(_on_map_changed)
	rng.randomize()
	roller = EncounterRoller.new(DataRegistry.db.balance, rng)
	walker = WalkTracker.new(DataRegistry.db.balance)
	active = self
	_start()
	if GameState.has_game():
		GameState.position_provider = store_position
		GameState.enter_world()  # playtime tracking + autosave on entry


func _exit_tree() -> void:
	if active == self:
		active = null
	if GameState.position_provider == Callable(self, "store_position"):
		store_position()
		GameState.position_provider = Callable()


## Where a new game begins (falls back to the debug room until that map exists).
static func new_game_map() -> String:
	return SaveGame.NEW_GAME_MAP if GameMap.exists(SaveGame.NEW_GAME_MAP) else DEBUG_MAP


func _start() -> void:
	var pos: Dictionary = GameState.current.position if GameState.has_game() else {}
	if GameMap.exists(pos.get("map", "")):
		load_map_at(pos.map, Vector2(pos.x, pos.y), Player.facing_from_name(pos.facing))
	else:
		# A game with no position starts at home; no game at all (debug runs) opens the test room.
		_swap_map(new_game_map() if GameState.has_game() else DEBUG_MAP)
		_place_at_spawn(SaveGame.NEW_GAME_SPAWN, Vector2i.DOWN)
	_last_location = map.display_name
	if GameState.has_game():
		GameState.current.location = map.display_name


## Writes the player's map, position and facing into the current save (no file write).
func store_position() -> void:
	if not GameState.has_game() or map == null:
		return
	GameState.current.position = {"map": map.map_id(), "x": player.position.x, "y": player.position.y,
		"facing": Player.facing_name(player.facing)}


func _on_map_changed(m: GameMap) -> void:
	if m.display_name != _last_location:
		_last_location = m.display_name
		banner.show_text(m.display_name)
	if GameState.has_game():
		GameState.current.location = m.display_name
		GameState.autosave()


func _process(_delta: float) -> void:
	_update_camera()


# --- Maps ------------------------------------------------------------------------

## Fade out, swap to `map_id`, put the player on `spawn_id`, fade in.
func change_map(map_id: String, spawn_id: String) -> void:
	if not GameMap.exists(map_id):
		Log.error(Log.WORLD, "change_map: no such map", {"map": map_id})
		return
	lock("map_change")
	await _fade_to(1.0)
	var facing := player.facing
	_swap_map(map_id)
	_place_at_spawn(spawn_id, facing)
	Log.info(Log.WORLD, "Map changed", {"map": map_id, "spawn": spawn_id, "tile": player.feet_tile()})
	map_changed.emit(map)
	await _fade_to(0.0)
	unlock("map_change")


## Loads a map and puts the player at an exact position (resuming a save).
func load_map_at(map_id: String, pos: Vector2, facing: Vector2i) -> void:
	_swap_map(map_id)
	player.place(pos, facing)
	Log.info(Log.WORLD, "Map loaded", {"map": map_id, "tile": player.feet_tile()})
	_update_camera()


func _swap_map(map_id: String) -> void:
	if player.get_parent() != null:
		player.get_parent().remove_child(player)
	if map != null:
		remove_child(map)
		map.queue_free()
	map = load(GameMap.path_of(map_id)).instantiate()
	add_child(map)
	move_child(map, 0)
	map.entities().add_child(player)


func _place_at_spawn(spawn_id: String, facing: Vector2i) -> void:
	var s := map.spawn(spawn_id)
	if s == null:
		Log.error(Log.WORLD, "Map has no such spawn; placing at its centre", {"map": map.map_id(), "spawn": spawn_id})
		player.place(Vector2(map.bounds().get_center()) * GameMap.TILE, facing)
	else:
		player.place(s.position, facing)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if is_locked():
		return
	if event.is_action_pressed("accept"):
		get_viewport().set_input_as_handled()
		interact()
	elif event.is_action_pressed("menu") and GameState.has_game():
		get_viewport().set_input_as_handled()
		open_pause_menu()


## Party / Bag / Save / Settings / Quit. Does nothing while anything holds a lock.
func open_pause_menu() -> void:
	if is_locked():
		return
	lock("menu")
	await pause_menu.run(self)
	if is_inside_tree():
		unlock("menu")


func open_shop(stock: PackedStringArray) -> void:
	if is_locked():
		return
	lock("menu")
	await shop_menu.run(stock)
	unlock("menu")


## The creature box. The Party screen (already under the "menu" lock) runs
## StorageScreen directly instead of calling this.
func open_storage() -> void:
	if is_locked():
		return
	lock("menu")
	await StorageScreen.run(self)
	unlock("menu")


## The F1 debug menu stays shut during conversations, cutscenes and map changes.
func blocks_debug_menu() -> bool:
	return _talking or _locks.has("map_change") or _locks.has("cutscene") or _locks.has("tamer") \
			or _locks.has("progress")


## Accept: runs the piece on the tile the player faces (NPC, item, sign...).
func interact() -> void:
	if is_locked():
		return
	var p := map.piece_at(player.front_tile())
	if p != null:
		Log.debug(Log.WORLD, "Interact", {"piece": p.save_key(), "tile": player.front_tile()})
		p.on_interact(self)


func _on_tile_entered(tile: Vector2i) -> void:
	var p := map.piece_at(tile)
	if p != null:
		Log.debug(Log.WORLD, "Stepped on piece", {"piece": p.save_key(), "tile": tile})
		p.on_enter(self)
		if is_locked():
			return  # a door or trigger took over
	if not GameState.has_game():
		return
	var save := GameState.current
	walker.on_tile(DataRegistry.db, save.party)
	if BattleLauncher.healthy_count(save) > 0:
		for t in map.pieces():
			if t is Tamer and (t as Tamer).sees(tile, map):
				Log.info(Log.WORLD, "Tamer spotted the player", {"tamer": (t as Tamer).tamer_id, "tile": tile})
				(t as Tamer).challenge(self)
				return
	if not map.indoor and map.is_encounter_tile(tile):
		var table := map.encounter_at(tile)
		if roller.on_grass_tile(table, BattleLauncher.healthy_count(save) > 0):
			Log.info(Log.WORLD, "Wild encounter", {"table": table, "tile": tile})
			start_wild(table)


# --- Battles -----------------------------------------------------------------------

## A tamer's challenge: (when spotted) "!" and walk up, then its before_title
## script, which battles. Lives here, not on the tamer: a loss can change map and
## free the tamer, and its lock must still be released.
func tamer_challenge(t: Tamer, approach: bool) -> void:
	var key := t.save_key()
	var dialogue := t.dialogue
	var title := t.before_title
	lock("tamer")
	_challenger = {"tamer_id": t.tamer_id, "key": key}
	if approach:
		await Emote.show_over(t, "!")
		var next_to: Vector2i = player.feet_tile() - t.facing
		if is_instance_valid(t) and next_to != t.tile():
			await t.walk_to(next_to)
		if is_instance_valid(t):
			player.place(player.position, -t.facing)
	Story.forget_last_battle()
	await say(dialogue, title)
	if Story.last_battle_won():
		Story.mark_done(key)
	_challenger = {}
	unlock("tamer")


## A wild encounter from `table_id`: "how many?", then the battle. Cancelling the
## prompt counts as running away.
func start_wild(table_id: String) -> void:
	if wild_override.is_valid():
		wild_override.call(table_id)
		return
	lock("battle")
	var db := DataRegistry.db
	var pack := BattleLauncher.roll_wild_pack(db, table_id, rng)
	var names := ", ".join(pack.map(func(c: CreatureInstance): return c.display_name(db)))
	var n = await FieldCountPrompt.ask(self, pack.size(), "A wild %s appeared!" % names)
	if n == null:
		roller.start_grace()
		unlock("battle")
		return
	await run_battle(BattleLauncher.wild_setup(GameState.current, pack, n))
	unlock("battle")


## Plays a battle over the paused map and applies the outcome. Returns true for
## a win (or a catch). With `defeat_rules` false a loss only heals the team
## (story battles); otherwise the player wakes at the last heal spot.
func run_battle(setup: BattleSetup, defeat_rules := true) -> bool:
	lock("battle")
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	_battle_layer = layer
	var scene = load(SceneRouter.BATTLE).instantiate()
	scene.params = {"setup": setup, "overlay": true, "defeat_rules": defeat_rules}
	layer.add_child(scene)
	var summary: Dictionary = await scene.finished
	summary["tamer_id"] = setup.tamer_id
	layer.queue_free()
	_battle_layer = null
	var won := await after_battle(summary, defeat_rules)
	unlock("battle")
	return won


func in_battle() -> bool:
	return _battle_layer != null


## Applies a finished battle's outcome on the overworld. Returns true for a win.
func after_battle(summary: Dictionary, defeat_rules: bool) -> bool:
	roller.start_grace()
	var won: bool = summary.get("outcome", "") in ["won", "captured"]
	if won and _challenger.get("tamer_id", "") != "" and _challenger.tamer_id == summary.get("tamer_id", ""):
		Story.mark_done(_challenger.key)  # before the autosave that carries the prize
	if summary.get("outcome", "") == "lost" and GameState.has_game():
		if defeat_rules:
			var r := Defeat.apply(DataRegistry.db, GameState.current)
			if not GameMap.exists(r.map):  # the heal spot's map was removed
				r.map = new_game_map()
				r.spawn = SaveGame.NEW_GAME_SPAWN
			await change_map(r.map, r.spawn)
			player.place(player.position, Vector2i.DOWN)
			var lines := [{"speaker": "", "text": "You hurried back to safety..." +
				(" You dropped %d money." % r.lost_money if r.lost_money > 0 else "")}]
			if _talking:
				await dialogue_box.show_lines(lines)  # inside a tamer's / story script
			else:
				await say_lines(lines)
		else:
			for c: CreatureInstance in GameState.current.party:
				c.heal_full(DataRegistry.db)
	await run_progress(summary.get("progress", []))
	if GameState.has_game():
		GameState.autosave()
	return won


## Level-up choices (Learn Move, Grow) after a battle, over the map.
func run_progress(progress: Array) -> void:
	if progress.is_empty():
		return
	lock("progress")
	await ProgressFlow.run(self, progress)
	unlock("progress")


# --- Conversations -------------------------------------------------------------------

## Runs `title` from a .dialogue file in the conversation box, locking the player.
## `extra` objects can be called from the script by method name (a heal spot's
## rest_here()). Ignored while another conversation is running.
func say(dialogue_path: String, title: String, extra: Array = []) -> void:
	if _talking:
		return
	var res: DialogueResource = load(dialogue_path) if ResourceLoader.exists(dialogue_path) else null
	if res == null:
		Log.error(Log.STORY, "say: no such dialogue file", {"file": dialogue_path})
		return
	_talking = true
	var had_cutscene := _locks.has("cutscene")
	lock("dialogue")
	Log.info(Log.STORY, "Dialogue started", {"file": dialogue_path, "title": title})
	await dialogue_box.run(res, title, [self] + extra)
	Log.info(Log.STORY, "Dialogue ended", {"file": dialogue_path, "title": title})
	if not had_cutscene and _locks.has("cutscene"):
		# A script that locks the player must unlock them; don't freeze the game if it forgot.
		Log.warn(Log.STORY, "Script ended without Cutscene.unlock_player(); control given back", {"file": dialogue_path, "title": title})
		unlock("cutscene")
	unlock("dialogue")
	_talking = false


## Shows plain lines ([{ speaker, text }]) without a dialogue file (signs, pickups).
func say_lines(lines: Array) -> void:
	if _talking:
		return
	_talking = true
	lock("dialogue")
	await dialogue_box.show_lines(lines)
	unlock("dialogue")
	_talking = false


## False while the player stands somewhere unsafe (storage, swapping are blocked).
func is_safe_here() -> bool:
	return not map.unsafe_at(player.feet_tile())


func is_talking() -> bool:
	return _talking


## Redraws on-screen info after outside changes (debug menu). Nothing to redraw yet.
func refresh_hud() -> void:
	pass


# --- Locks -----------------------------------------------------------------------

func lock(reason: String) -> void:
	if not _locks.has(reason):
		Log.debug(Log.WORLD, "Lock taken", {"reason": reason, "held": _locks.keys() + [reason]})
	_locks[reason] = true
	player.locked = true


func unlock(reason: String) -> void:
	if _locks.erase(reason):
		Log.debug(Log.WORLD, "Lock released", {"reason": reason, "held": _locks.keys()})
	player.locked = not _locks.is_empty()


func is_locked() -> bool:
	return not _locks.is_empty()


# --- Camera and fade --------------------------------------------------------------

## Follows the player, clamped to the map; maps smaller than the view are centred.
func _update_camera() -> void:
	if map == null or camera == null:
		return
	var b := map.bounds()
	var r := Rect2(Vector2(b.position * GameMap.TILE), Vector2(b.size * GameMap.TILE))
	var target: Vector2 = camera_focus if camera_focus != null else player.position
	var out := Vector2.ZERO
	for axis in 2:
		var half := VIEW[axis] / 2.0
		if r.size[axis] <= VIEW[axis]:
			out[axis] = r.position[axis] + r.size[axis] / 2.0
		else:
			out[axis] = clampf(target[axis], r.position[axis] + half, r.end[axis] - half)
	camera.position = out.round()


## Fades the screen to black (1.0) or back (0.0). Awaitable.
func fade(alpha: float) -> void:
	await _fade_to(alpha)


func _fade_to(alpha: float) -> void:
	if instant or is_equal_approx(_fade.color.a, alpha):
		_fade.color.a = alpha
		return
	var t := create_tween()
	t.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await t.finished
