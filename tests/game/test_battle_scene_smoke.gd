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
	var scene: Node = _scene(BattleSetup.wild(party, pack, 1, {"lure_cage": 2}))
	await _wait_phase(scene, ["command"])
	assert_str(scene.phase).is_equal("command")
	assert_array(Array(scene.menu.labels())).contains(["Fight", "Items", "Swap", "Rest", "Run"])
	assert_int(scene.views.size()).is_equal(2)
	assert_bool(scene.menu.pick_label("Fight")).is_true()
	await get_tree().process_frame
	assert_bool(Array(scene.menu.labels()).any(func(l): return l.begins_with("Scrap"))).is_true()
	assert_bool(scene.menu.pick_label("Splash Jab")).is_true()
	await get_tree().process_frame
	# The Underdog side gets extra actions; spend them resting so only the move under test hits.
	while scene.menu._title.text.begins_with("What will") and scene.menu.pick_label("Rest"):
		await get_tree().process_frame
	if scene.menu.labels().has("Yes, go!"):
		scene.menu.pick_label("Yes, go!")
	await _wait_phase(scene, ["command", "results", "replace"])
	assert_bool(scene._log.any(func(ev): return ev.type == "move_used")).is_true()
	remove_child(scene)


func test_tamer_battle_hides_run_and_capture_items() -> void:
	var party := [CreatureInstance.create(db, "tidepup", 10), CreatureInstance.create(db, "voltmoth", 10)]
	var scene: Node = _scene(BattleSetup.vs_tamer(db, party, "rival_01", 1, {"lure_cage": 2, "salve": 1, "reset_seed": 1}))
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var team: Array = []
	for species: String in ["tidepup", "emberkit", "voltmoth"]:
		team.append(CreatureSpec.natural(db, species, 8, rng))
	# 3v1: the foe is the Underdog. 1v3: the player is.
	for f in [[3, 1, true, 1], [1, 3, false, 0]]:
		var scene: Node = _scene(BattleLauncher.exhibition_setup(db, team, f[0], team.slice(0, f[1]), f[1], f[2],
			{}, rng))
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
	var scene: Node = _scene(BattleSetup.wild([pup], pack, 1, {}))
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
	var scene: Node = _scene(BattleSetup.wild([pup], pack, 1, {}))
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
	var scene: Node = _scene(BattleSetup.wild([pup], pack, 1, {}))
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
	var scene: Node = _scene(BattleSetup.vs_tamer(db, party, "rival_01", 1, {"salve": 1, "oran_berry": 1}))
	await _wait_phase(scene, ["command"])
	assert_bool(scene.menu.pick_label("Items")).is_true()
	await get_tree().process_frame
	var items := Array(scene.menu.labels())
	assert_bool(items.any(func(l): return l.begins_with("Salve"))).is_true()
	assert_bool(items.any(func(l): return l.begins_with("Oran Berry"))).is_false()
	remove_child(scene)


# --- Two-step target menu for two_enemies moves ----------------------------------------

var _jab_target := ""


## Makes Splash Jab a two_enemies move for the test (restored in after_test).
func _make_jab_two_target() -> void:
	_jab_target = db.move("splash_jab").target
	db.move("splash_jab").target = "two_enemies"


func after_test() -> void:
	if _jab_target != "":
		db.move("splash_jab").target = _jab_target
		_jab_target = ""


func _foes_scene(species: Array) -> Node:
	var party := [CreatureInstance.create(db, "tidepup", 12)]
	var pack: Array = species.map(func(s): return CreatureInstance.create(db, s, 3))
	return _scene(BattleSetup.wild(party, pack, 1, {}))


func _foe_bids(scene: Node) -> Array:
	return scene.engine.sides[1].active().map(func(t): return t.bid)


func _has_label(scene: Node, prefix: String) -> bool:
	return Array(scene.menu.labels()).any(func(l): return l.begins_with(prefix))


func _pick(scene: Node, label: String) -> void:
	if label == "Fight":
		# Low enough that Rest stays available for the Underdog's extra actions.
		for b in scene.engine.sides[0].active():
			b.creature.energy = 4
	assert_bool(scene.menu.pick_label(label)).is_true()
	await get_tree().process_frame


## Confirms the turn and plays the round; returns the distinct foe bids the player's move damaged.
func _damaged_foes(scene: Node, foes: Array) -> Array:
	# The Underdog side gets extra actions; spend them resting so only the move under test hits.
	while scene.menu._title.text.begins_with("What will") and scene.menu.pick_label("Rest"):
		await get_tree().process_frame
	if scene.menu.labels().has("Yes, go!"):
		scene.menu.pick_label("Yes, go!")
	await _wait_phase(scene, ["command", "results", "replace"])
	var hit: Array = []
	for ev in scene._log:
		if ev.type == BattleEvents.DAMAGE and foes.has(ev.bid) and not hit.has(ev.bid):
			hit.append(ev.bid)
	hit.sort()
	return hit


func test_two_step_menu_with_three_foes() -> void:
	_make_jab_two_target()
	var scene := _foes_scene(["sprigling", "emberkit", "voltmoth"])
	await _wait_phase(scene, ["command"])
	var foes := _foe_bids(scene)
	await _pick(scene, "Fight")
	await _pick(scene, "Splash Jab")
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on...?")
	assert_int(scene.menu.labels().size()).is_equal(3)
	await _pick(scene, "Wild Emberkit")
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on Wild Emberkit and...?")
	assert_int(scene.menu.labels().size()).is_equal(2)
	assert_bool(_has_label(scene, "Wild Emberkit")).is_false()
	await _pick(scene, "Wild Voltmoth")
	var hit := await _damaged_foes(scene, foes)
	var want := [foes[1], foes[2]]
	want.sort()
	assert_array(hit).is_equal(want)
	remove_child(scene)


func test_two_or_fewer_foes_skip_the_target_menu() -> void:
	_make_jab_two_target()
	var scene := _foes_scene(["sprigling", "emberkit"])
	await _wait_phase(scene, ["command"])
	var foes := _foe_bids(scene)
	# The pick itself names both foes (the old fall-through returned -1 and left it to the engine).
	var me: int = scene.engine.sides[0].active()[0].bid
	var pair: Variant = await scene._choose_two_targets(me, "splash_jab", "Use Splash Jab on...?")
	assert_array(pair).is_equal([foes[0], foes[1]])
	await _pick(scene, "Fight")
	await _pick(scene, "Splash Jab")
	# No target menu: straight to the end-of-turn prompt, covering both foes.
	assert_bool(scene.menu._title.text.begins_with("Use Splash Jab")).is_false()
	var hit := await _damaged_foes(scene, foes)
	var want := foes.duplicate()
	want.sort()
	assert_array(hit).is_equal(want)
	remove_child(scene)
	var one := _foes_scene(["sprigling"])
	await _wait_phase(one, ["command"])
	var lone := _foe_bids(one)
	var me_one: int = one.engine.sides[0].active()[0].bid
	var single: Variant = await one._choose_two_targets(me_one, "splash_jab", "Use Splash Jab on...?")
	assert_array(single).is_equal([lone[0], -1])
	await _pick(one, "Fight")
	await _pick(one, "Splash Jab")
	assert_bool(one.menu._title.text.begins_with("Use Splash Jab")).is_false()
	assert_array(await _damaged_foes(one, lone)).is_equal(lone)
	remove_child(one)


func test_back_from_the_second_step_returns_to_the_first() -> void:
	_make_jab_two_target()
	var scene := _foes_scene(["sprigling", "emberkit", "voltmoth"])
	await _wait_phase(scene, ["command"])
	var foes := _foe_bids(scene)
	await _pick(scene, "Fight")
	await _pick(scene, "Splash Jab")
	await _pick(scene, "Wild Emberkit")
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on Wild Emberkit and...?")
	scene.menu._finish(null)
	await get_tree().process_frame
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on...?")
	assert_int(scene.menu.labels().size()).is_equal(3)
	await _pick(scene, "Wild Sprigling")
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on Wild Sprigling and...?")
	await _pick(scene, "Wild Voltmoth")
	var hit := await _damaged_foes(scene, foes)
	var want := [foes[0], foes[2]]
	want.sort()
	assert_array(hit).is_equal(want)
	remove_child(scene)


func test_cancelling_the_first_step_cancels_the_move_choice() -> void:
	_make_jab_two_target()
	var scene := _foes_scene(["sprigling", "emberkit", "voltmoth"])
	await _wait_phase(scene, ["command"])
	await _pick(scene, "Fight")
	await _pick(scene, "Splash Jab")
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on...?")
	scene.menu._finish(null)
	await get_tree().process_frame
	# Back on the move list.
	assert_str(scene.menu._title.text).contains("choose a move")
	assert_bool(_has_label(scene, "Splash Jab")).is_true()
	remove_child(scene)


func test_other_target_kinds_are_unchanged() -> void:
	var scene := _foes_scene(["sprigling", "emberkit", "voltmoth"])
	await _wait_phase(scene, ["command"])
	var foes := _foe_bids(scene)
	await _pick(scene, "Fight")
	await _pick(scene, "Splash Jab")
	assert_str(scene.menu._title.text).is_equal("Use Splash Jab on...?")
	assert_int(scene.menu.labels().size()).is_equal(3)
	await _pick(scene, "Wild Voltmoth")
	assert_array(await _damaged_foes(scene, foes)).is_equal([foes[2]])
	remove_child(scene)
