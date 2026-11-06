extends GdUnitTestSuite
## Exhibition (custom) battles change nothing in the save, even on a loss or a capture.

var _state: Dictionary
var db: Database
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before() -> void:
	_state = WorldTest.begin_suite("exhibition")
	db = DataRegistry.db
	BattlePlayback.instant = true
	rng.seed = 11


func after() -> void:
	BattlePlayback.instant = false
	WorldTest.end_suite(_state)


func after_test() -> void:
	GameState.close_game()


func _snapshot() -> String:
	return JSON.stringify(GameState.current.to_dict(), "", true)


## The save without fields the running overworld legitimately updates (playtime, location).
func _stable_snapshot() -> String:
	var d: Dictionary = GameState.current.to_dict()
	d.erase("playtime_sec")
	d.erase("saved_unix")
	d.erase("location")
	d.erase("position")
	return JSON.stringify(d, "", true)


func _spec(species: String, level: int) -> CreatureSpec:
	return CreatureSpec.natural(db, species, level, rng)


func _new_game() -> void:
	GameState.start_new_game("Ana")
	BattleLauncher.grant_test_party(db, GameState.current)
	GameState.current.inventory["lure_cage"] = 20
	GameState.current.money = 321
	GameState.current.story.set_flag("exhibition_probe")


func _scene(setup: BattleSetup, seed_value: int) -> Node:
	var scene: Node = load("res://game/battle/battle_scene.tscn").instantiate()
	scene.params = {"setup": setup, "overlay": true, "seed": seed_value}
	add_child(scene)
	return scene


## Plays the scene to its end and returns the summary it emits (null on timeout).
## mode: "rest" passes every turn, "fight" uses the first move on the first target,
## "capture" throws lure cages at the first foe until one holds.
func _drive(scene: Node, mode: String) -> BattleSummary:
	var done: Array = []
	scene.finished.connect(func(s: BattleSummary): done.append(s))
	for i in 6000:
		if not done.is_empty():
			return done[0]
		if scene.phase == "command" and scene.menu.is_choosing():
			await _command(scene, mode)
		elif scene.phase == "replace" and scene.menu.is_choosing():
			scene.menu.pick_label(scene.menu.labels()[0])
		elif scene.phase == "results" and scene.continue_button != null:
			scene.continue_button.pressed.emit()
		await get_tree().process_frame
	return null


func _command(scene: Node, mode: String) -> void:
	var labels: PackedStringArray = scene.menu.labels()
	if labels.has("Yes, go!"):
		scene.menu.pick_label("Yes, go!")
	elif mode == "capture" and labels.has("Items"):
		scene.menu.pick_label("Items")
		await get_tree().process_frame
		scene.menu.pick_label("Lure Cage")
		await get_tree().process_frame
		scene.menu.pick_label("Wild")
	elif mode == "fight" and labels.has("Fight"):
		scene.menu.pick_label("Fight")
		await get_tree().process_frame
		scene.menu.pick_label(scene.menu.labels()[0])
		await get_tree().process_frame
		if scene.menu.is_choosing():
			scene.menu.pick_label(scene.menu.labels()[0])
	else:
		scene.menu.pick_label("Rest")


func test_a_lost_tamer_exhibition_leaves_the_save_untouched() -> void:
	_new_game()
	var before_snap: String = _snapshot()
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("tidepup", 1)], 1,
		[_spec("emberkit", 60)], 1, false, GameState.current.inventory, rng)
	var scene: Node = _scene(setup, 4)
	var summary: BattleSummary = await _drive(scene, "fight")
	assert_object(summary).is_not_null()
	assert_str(summary.outcome).is_equal(BattleSummary.LOST)
	assert_str(_snapshot()).is_equal(before_snap)
	assert_int(GameState.current.money).is_equal(321)
	scene.queue_free()


func test_a_won_exhibition_pays_nothing_and_changes_nothing() -> void:
	_new_game()
	var before_snap: String = _snapshot()
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("emberkit", 60)], 1,
		[_spec("tidepup", 1)], 1, false, GameState.current.inventory, rng)
	var xp_before: int = setup.sides[0].party[0].xp
	var scene: Node = _scene(setup, 4)
	var summary: BattleSummary = await _drive(scene, "fight")
	assert_object(summary).is_not_null()
	assert_str(summary.outcome).is_equal(BattleSummary.WON)
	assert_int(summary.money).is_equal(0)
	# XP is awarded inside the battle (visible on the temporary creature), never saved.
	assert_int(scene.engine.sides[0].battlers[0].creature.xp).is_greater(xp_before)
	assert_bool(scene._log.any(func(ev): return ev.type == "xp_gain")).is_true()
	assert_str(_snapshot()).is_equal(before_snap)
	scene.queue_free()


func test_a_wild_exhibition_capture_does_not_reach_party_or_storage() -> void:
	_new_game()
	var party_before: int = GameState.current.party.size()
	var before_snap: String = _snapshot()
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("emberkit", 30)], 1,
		[_spec("tidepup", 1)], 1, true, GameState.current.inventory, rng)
	var scene: Node = _scene(setup, 6)
	var summary: BattleSummary = await _drive(scene, "capture")
	assert_object(summary).is_not_null()
	# The throw really succeeded: the engine holds the capture and its bag copy was spent.
	assert_str(summary.outcome).is_equal(BattleSummary.CAPTURED)
	assert_array(summary.captured).contains_exactly(["Tidepup"])
	assert_int(scene.engine.result().captured.size()).is_equal(1)
	assert_int(int(scene.engine.sides[0].items.get("lure_cage", 0))).is_less(20)
	assert_int(GameState.current.party.size()).is_equal(party_before)
	assert_int(BoxStorage.count(GameState.current)).is_equal(0)
	assert_int(int(GameState.current.inventory.lure_cage)).is_equal(20)
	assert_str(_snapshot()).is_equal(before_snap)
	scene.queue_free()


func test_results_panel_says_nothing_was_saved() -> void:
	_new_game()
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("tidepup", 1)], 1,
		[_spec("emberkit", 60)], 1, false, {}, rng)
	var scene: Node = _scene(setup, 4)
	for i in 6000:
		if scene.phase == "results":
			break
		if scene.phase == "command" and scene.menu.is_choosing():
			await _command(scene, "fight")
		elif scene.phase == "replace" and scene.menu.is_choosing():
			scene.menu.pick_label(scene.menu.labels()[0])
		await get_tree().process_frame
	assert_str(scene.phase).is_equal("results")
	var lines: Array = Array(scene.result_lines(scene.engine.result()))
	assert_bool(lines.has("Exhibition — nothing was saved.")).is_true()
	scene.queue_free()


## A store that counts writes: an autosave rewrites one file, so a file count can't see it.
class CountingStore extends SaveStore:
	var writes: int = 0

	func write(save: SaveGame, kind: String, now_unix_ms: int) -> String:
		writes += 1
		return super.write(save, kind, now_unix_ms)


## Opens the overworld over the current game with a counting store, runs the exhibition
## through BattleFlow.run_battle(defeat_rules true) and returns [world, result, store, stable snapshot before].
func _play_in_world(setup: BattleSetup) -> Array:
	var world: Overworld = await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	var before: String = _stable_snapshot()  # after the world opened (its entry autosave)
	var counting: CountingStore = CountingStore.new(GameState.store.root)
	GameState.store = counting
	var result: Array = []
	var driver: Callable = func() -> void:
		result.append(await world.battles.run_battle(setup, true))
	driver.call()
	var layer: Node = null
	for i: int in 600:
		layer = world.battles.get("_battle_layer")
		if layer != null and layer.get_child_count() > 0:
			break
		await get_tree().process_frame
	assert_bool(world.battles.in_battle()).is_true()
	var scene: Node = layer.get_child(0)
	for i: int in 6000:
		if not result.is_empty():
			break
		if scene.phase == "command" and scene.menu.is_choosing():
			await _command(scene, "fight")
		elif scene.phase == "results" and scene.continue_button != null:
			scene.continue_button.pressed.emit()
		await get_tree().process_frame
	assert_bool(result.is_empty()).is_false()
	return [world, result[0], counting, before]


func test_run_battle_exhibition_skips_after_battle_and_starts_grace() -> void:
	_new_game()
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("emberkit", 60)], 1,
		[_spec("tidepup", 1)], 1, false, {}, rng)
	var played: Array = await _play_in_world(setup)
	var world: Overworld = played[0]
	var counting: CountingStore = played[2]
	assert_bool(played[1]).is_true()
	assert_bool(world.battles.in_battle()).is_false()
	assert_int(counting.writes).is_equal(0)  # no autosave
	assert_str(_stable_snapshot()).is_equal(played[3])
	assert_int(int(world.roller.get("_grace"))).is_greater(0)
	assert_bool(world.is_locked()).is_false()


func test_run_battle_lost_exhibition_does_not_heal_save_or_defeat() -> void:
	_new_game()
	for c: CreatureInstance in GameState.current.party:
		c.hp = maxi(1, c.max_hp(db) / 2)
	var hp_before: Array = GameState.current.party.map(func(c: CreatureInstance) -> int: return c.hp)
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("tidepup", 1)], 1,
		[_spec("emberkit", 60)], 1, false, {}, rng)
	var played: Array = await _play_in_world(setup)
	var world: Overworld = played[0]
	var counting: CountingStore = played[2]
	assert_bool(played[1]).is_false()  # really lost
	for c: CreatureInstance in GameState.current.party:
		assert_int(c.hp).is_less(c.max_hp(db))
	var hp_after: Array = GameState.current.party.map(func(c: CreatureInstance) -> int: return c.hp)
	assert_array(hp_after).is_equal(hp_before)
	assert_int(counting.writes).is_equal(0)  # no autosave: saved_unix, location, position untouched
	assert_str(_stable_snapshot()).is_equal(played[3])
	assert_int(GameState.current.money).is_equal(321)
	assert_bool(world.is_locked()).is_false()
	assert_int(int(world.roller.get("_grace"))).is_greater(0)


func test_lost_exhibition_panel_does_not_claim_a_heal() -> void:
	_new_game()
	var setup: BattleSetup = BattleLauncher.exhibition_setup(db, [_spec("tidepup", 1)], 1,
		[_spec("emberkit", 60)], 1, false, {}, rng)
	var scene: Node = _scene(setup, 4)
	for i: int in 6000:
		if scene.phase == "results":
			break
		if scene.phase == "command" and scene.menu.is_choosing():
			await _command(scene, "fight")
		elif scene.phase == "replace" and scene.menu.is_choosing():
			scene.menu.pick_label(scene.menu.labels()[0])
		await get_tree().process_frame
	assert_str(scene.summary.outcome).is_equal(BattleSummary.LOST)
	var lines: Array = Array(scene.result_lines(scene.engine.result()))
	assert_str(lines[-1]).is_equal("Exhibition — nothing was saved.")
	for l: String in lines:
		assert_bool(l.contains("patched up") or l.contains("hurried back")).is_false()
	scene.queue_free()
