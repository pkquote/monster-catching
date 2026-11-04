extends GdUnitTestSuite
## The battle scene builds, reaches the command menu, and plays a round from
## scripted menu choices. Playback runs instantly.

var db: Database


func before() -> void:
	db = DataRegistry.db
	BattlePlayback.instant = true


func after() -> void:
	BattlePlayback.instant = false
	SceneRouter.params = {}


func _wait_phase(scene: Node, wanted: Array, max_frames := 600) -> void:
	for i in max_frames:
		if scene.phase in wanted and (scene.phase != "command" or scene.menu.is_choosing()):
			return
		await get_tree().process_frame


func _scene(setup: BattleSetup) -> Node:
	SceneRouter.params = {"setup": setup, "seed": 5}
	var scene: Node = auto_free(load("res://game/battle/battle_scene.tscn").instantiate())
	add_child(scene)
	return scene


func test_wild_battle_round_from_menus() -> void:
	var party := [CreatureInstance.create(db, "tidepup", 12), CreatureInstance.create(db, "emberkit", 10)]
	var pack := [CreatureInstance.create(db, "sprigling", 3)]
	var scene := _scene(BattleSetup.wild(party, pack, 1, {"lure_cage": 2}))
	await _wait_phase(scene, ["command"])
	assert_str(scene.phase).is_equal("command")
	assert_array(Array(scene.menu.labels())).contains(["Fight", "Items", "Swap", "Rest", "Run"])
	assert_int(scene.views.size()).is_equal(2)
	assert_bool(scene.menu.pick_label("Fight")).is_true()
	await get_tree().process_frame
	assert_bool(Array(scene.menu.labels()).any(func(l): return l.begins_with("Scrap"))).is_true()
	assert_bool(scene.menu.pick_label("Splash Jab")).is_true()
	await get_tree().process_frame
	if scene.menu.labels().has("Yes, go!"):
		scene.menu.pick_label("Yes, go!")
	await _wait_phase(scene, ["command", "results", "replace"])
	assert_bool(scene._log.any(func(ev): return ev.type == "move_used")).is_true()
	remove_child(scene)


func test_tamer_battle_hides_run_and_capture_items() -> void:
	var party := [CreatureInstance.create(db, "tidepup", 10), CreatureInstance.create(db, "voltmoth", 10)]
	var scene := _scene(BattleSetup.vs_tamer(db, party, "rival_01", 1, {"lure_cage": 2, "salve": 1, "reset_seed": 1}))
	await _wait_phase(scene, ["command"])
	assert_bool(scene.menu.labels().has("Run")).is_false()
	assert_bool(scene.menu.pick_label("Items")).is_true()
	await get_tree().process_frame
	var items := Array(scene.menu.labels())
	assert_bool(items.any(func(l): return l.begins_with("Salve"))).is_true()
	assert_bool(items.any(func(l): return l.begins_with("Lure Cage"))).is_false()
	assert_bool(items.any(func(l): return l.begins_with("Reset Seed"))).is_false()
	# Fielding 1 against the Rival's 2 makes the player the Underdog.
	assert_str(scene.fields[0].underdog_text).contains("UNDERDOG")
	remove_child(scene)


func test_custom_uneven_formats_reach_command() -> void:
	var s := SaveGame.new_game("Ana", 1000, RandomNumberGenerator.new())
	BattleLauncher.grant_test_party(db, s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	# 3v1: the foe is the Underdog. 1v3: the player is.
	for f in [[3, 1, true, 1], [1, 3, false, 0]]:
		var scene := _scene(BattleLauncher.custom_setup(db, s, f[0], f[1], 8, f[2], rng))
		await _wait_phase(scene, ["command"])
		assert_str(scene.phase).is_equal("command")
		assert_int(scene.views.size()).is_equal(f[0] + f[1])
		assert_str(scene.fields[f[3]].underdog_text).contains("UNDERDOG")
		assert_str(scene.fields[1 - f[3]].underdog_text).is_empty()
		remove_child(scene)
