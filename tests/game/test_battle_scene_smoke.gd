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


func test_passive_banner_plays() -> void:
	var pup := CreatureInstance.create(db, "tidepup", 12)
	pup.passive = ""
	var pack := [CreatureInstance.create(db, "sprigling", 3)]
	pack[0].passive = ""
	var scene := _scene(BattleSetup.wild([pup], pack, 1, {}))
	await _wait_phase(scene, ["command"])
	var bid: int = scene.engine.sides[0].active()[0].bid
	var pb := BattlePlayback.new(scene, db)
	await pb.play({"type": BattleEvents.PASSIVE_TRIGGERED, "bid": bid, "passive": "undertow"})
	var banner: Label = scene.last_passive_banner
	assert_str(banner.text).is_equal("Tidepup's Undertow!")
	assert_int(banner.get_theme_font_size("font_size")).is_less(UIKit.TITLE_SIZE)
	assert_bool(ScreenFit.VIEW.encloses(banner.get_global_rect())).is_true()
	# A second banner over the same creature, while the first still shows, sits above it.
	# (Called directly: playback's own pause would let the first one fade in the test's fast time.)
	scene.passive_banner("One", bid)
	var one: Label = scene.last_passive_banner
	scene.passive_banner("Two", bid)
	assert_bool(scene.last_passive_banner.get_rect().intersects(one.get_rect())).is_false()
	# A creature that has left the field still gets a banner, kept on screen.
	scene.release_view(bid)
	await pb.play({"type": BattleEvents.PASSIVE_TRIGGERED, "bid": bid, "passive": "undertow"})
	assert_bool(ScreenFit.VIEW.encloses(scene.last_passive_banner.get_global_rect())).is_true()
	await pb.play({"type": BattleEvents.PASSIVE_TRIGGERED, "bid": 999, "passive": "undertow"})
	assert_bool(scene._log.filter(func(ev): return ev.type == BattleEvents.PASSIVE_TRIGGERED).size() == 3).is_true()
	remove_child(scene)


func test_item_consumed_plays_as_a_message_without_a_banner() -> void:
	var pup := CreatureInstance.create(db, "tidepup", 12)
	pup.passive = ""
	var pack := [CreatureInstance.create(db, "sprigling", 3)]
	pack[0].passive = ""
	var scene := _scene(BattleSetup.wild([pup], pack, 1, {}))
	await _wait_phase(scene, ["command"])
	var bid: int = scene.engine.sides[0].active()[0].bid
	var pb := BattlePlayback.new(scene, db)
	var banner_before: Label = scene.last_passive_banner
	await pb.play({"type": BattleEvents.ITEM_CONSUMED, "bid": bid, "item": "salve"})
	assert_object(scene.last_passive_banner).is_same(banner_before)
	assert_bool(scene._log.any(func(ev): return ev.type == BattleEvents.ITEM_CONSUMED)).is_true()
	remove_child(scene)


func test_command_screen_shows_active_passive() -> void:
	var pup := CreatureInstance.create(db, "tidepup", 12)
	pup.passive = "tidal_heart"
	var pack := [CreatureInstance.create(db, "sprigling", 3)]
	pack[0].passive = ""
	var scene := _scene(BattleSetup.wild([pup], pack, 1, {}))
	await _wait_phase(scene, ["command"])
	var title: Label = scene.menu._title
	assert_str(title.text).contains("Tidepup").contains("Tidal Heart")
	assert_bool(ScreenFit.VIEW.encloses(title.get_global_rect())).is_true()
	remove_child(scene)
	# No passive: no passive line.
	var plain := CreatureInstance.create(db, "tidepup", 12)
	plain.passive = ""
	var pack2 := [CreatureInstance.create(db, "sprigling", 3)]
	pack2[0].passive = ""
	var scene2 := _scene(BattleSetup.wild([plain], pack2, 1, {}))
	await _wait_phase(scene2, ["command"])
	assert_str(scene2.menu._title.text).is_equal("What will Tidepup do?")
	remove_child(scene2)


func test_held_items_are_not_offered_in_the_items_menu() -> void:
	var party := [CreatureInstance.create(db, "tidepup", 10), CreatureInstance.create(db, "voltmoth", 10)]
	var scene := _scene(BattleSetup.vs_tamer(db, party, "rival_01", 1, {"salve": 1, "oran_berry": 1}))
	await _wait_phase(scene, ["command"])
	assert_bool(scene.menu.pick_label("Items")).is_true()
	await get_tree().process_frame
	var items := Array(scene.menu.labels())
	assert_bool(items.any(func(l): return l.begins_with("Salve"))).is_true()
	assert_bool(items.any(func(l): return l.begins_with("Oran Berry"))).is_false()
	remove_child(scene)
