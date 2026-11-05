class_name BattleFlow
extends Node
## Battles on the overworld (Overworld.battles): tamer challenges, wild encounters,
## the battle scene shown over the paused map, and what happens after (defeat
## rules, the Learn Move / Grow step, the autosave).
##
## It lives on the overworld, not on a tamer or a script, because a loss can change
## map and free whoever started the battle, and the locks must still be released.

## Tests set this to catch wild encounters instead of starting one: Callable(table_id).
var wild_override: Callable

var _world: Overworld
var _battle_layer: CanvasLayer
## The tamer whose challenge is running ("" = none). A win against them is marked
## before the battle's autosave.
var _challenger_tamer := ""
var _challenger_key := ""


func _init(world: Overworld) -> void:
	_world = world
	name = "BattleFlow"


## A tamer's challenge: (when spotted) "!" and walk up, then its before_title
## script, which battles.
func tamer_challenge(t: Tamer, approach: bool) -> void:
	var w := _world
	var key := t.save_key()
	var dialogue := t.dialogue
	var title := t.before_title
	w.lock(Overworld.LOCK_TAMER)
	_challenger_tamer = t.tamer_id
	_challenger_key = key
	if approach:
		await Emote.show_over(t, "!")
		var next_to: Vector2i = w.player.feet_tile() - t.facing
		if is_instance_valid(t) and next_to != t.tile():
			await t.walk_to(next_to)
		if is_instance_valid(t):
			w.player.place(w.player.position, -t.facing)
	Story.forget_last_battle()
	await w.say(dialogue, title)
	if Story.last_battle_won():
		Story.mark_done(key)
	_challenger_tamer = ""
	_challenger_key = ""
	w.unlock(Overworld.LOCK_TAMER)


## A wild encounter from `table_id`: "how many?", then the battle. Cancelling the
## prompt counts as running away.
func start_wild(table_id: String) -> void:
	if wild_override.is_valid():
		wild_override.call(table_id)
		return
	var w := _world
	w.lock(Overworld.LOCK_BATTLE)
	var db := DataRegistry.db
	var pack := BattleLauncher.roll_wild_pack(db, table_id, w.rng)
	var names := ", ".join(pack.map(func(c: CreatureInstance): return c.display_name(db)))
	var n = await FieldCountPrompt.ask(w, pack.size(), "A wild %s appeared!" % names)
	if n == null:
		w.roller.start_grace()
		w.unlock(Overworld.LOCK_BATTLE)
		return
	await run_battle(BattleLauncher.wild_setup(db, GameState.current, pack, n))
	w.unlock(Overworld.LOCK_BATTLE)


## Plays a battle over the paused map and applies the outcome. Returns true for
## a win (or a catch). With `defeat_rules` false a loss only heals the team
## (story battles); otherwise the player wakes at the last heal spot.
func run_battle(setup: BattleSetup, defeat_rules := true) -> bool:
	_world.lock(Overworld.LOCK_BATTLE)
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	_battle_layer = layer
	var scene = load(SceneRouter.BATTLE).instantiate()
	scene.params = {"setup": setup, "overlay": true, "defeat_rules": defeat_rules}
	layer.add_child(scene)
	var summary: BattleSummary = await scene.finished  # carries setup.tamer_id
	layer.queue_free()
	_battle_layer = null
	var won := await after_battle(summary, defeat_rules)
	_world.unlock(Overworld.LOCK_BATTLE)
	return won


func in_battle() -> bool:
	return _battle_layer != null


## Applies a finished battle's outcome on the overworld. Returns true for a win.
func after_battle(summary: BattleSummary, defeat_rules: bool) -> bool:
	var w := _world
	w.roller.start_grace()
	var won := summary.is_win()
	if won and _challenger_tamer != "" and _challenger_tamer == summary.tamer_id:
		Story.mark_done(_challenger_key)  # before the autosave that carries the prize
	if summary.outcome == BattleSummary.LOST and GameState.has_game():
		if defeat_rules:
			await _apply_defeat()
		else:
			for c: CreatureInstance in GameState.current.party:
				c.heal_full(DataRegistry.db)
	await run_progress(summary.progress)
	if GameState.has_game():
		GameState.autosave()
	return won


## Level-up choices (Learn Move, Grow) after a battle, over the map.
func run_progress(progress: Array[ProgressEntry]) -> void:
	if progress.is_empty():
		return
	_world.lock(Overworld.LOCK_PROGRESS)
	await ProgressFlow.run(_world, progress)
	_world.unlock(Overworld.LOCK_PROGRESS)


## Lost with defeat rules: patched up, some money dropped, back at the last heal spot.
func _apply_defeat() -> void:
	var w := _world
	var r := Defeat.apply(DataRegistry.db, GameState.current)
	if not GameMap.exists(r.map):  # the heal spot's map was removed
		r.map = Overworld.new_game_map()
		r.spawn = SaveGame.NEW_GAME_SPAWN
	await w.change_map(r.map, r.spawn)
	w.player.place(w.player.position, Vector2i.DOWN)
	var lines := [{"speaker": "", "text": "You hurried back to safety..." +
		(" You dropped %d money." % r.lost_money if r.lost_money > 0 else "")}]
	if w.is_talking():
		await w.dialogue_box.show_lines(lines)  # inside a tamer's / story script
	else:
		await w.say_lines(lines)
