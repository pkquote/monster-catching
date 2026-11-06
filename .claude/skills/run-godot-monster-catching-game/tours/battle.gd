extends RefCounted
## The `battle` tour (driver.gd --mode=battle).
## Battle tour: new game -> test party -> wild battle from the world (attack, throw a
## cage, finish) -> results -> world; then a 1-vs-2 Rival battle (Underdog).
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, hold, press...) and
## its tree (d.root, d.current_scene, d.process_frame).

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d.key(KEY_F1)  # debug overlay
	await d._frames(5)
	await d.shot("b00_debug_menu_empty_party")
	d.press("Get test party")
	await d._frames(10)
	await d.wait_scene("Overworld", 60)
	await d._frames(5)
	await d.shot("b01_debug_menu_with_party")
	d.expect(gs.current.party.size() == 3, "test party granted from the F1 menu")

	# The Rival is always 2v2, so its "how many?" prompt always appears. Cancel it.
	d.press("Rival (2v2)")
	await d._frames(5)
	await d.shot("b02_field_count")
	d.expect(d._find_menu() != null, "field-count prompt appears for a 2v2 tamer")
	await d.key(KEY_X)  # Cancel
	await d._frames(5)
	d.expect(d._find_menu() == null, "cancelling the prompt closes it")

	d.press("Wild battle (Route 1)")
	await d._frames(5)
	await d.pick_menu("1 creature")  # no-op when the pack is a single creature
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d.shot("b03_wild_command")
	await d.key(KEY_F1)  # the overlay works mid-battle, but battles can't start from it
	await d._frames(5)
	await d.shot("b03b_debug_menu_in_battle")
	d.expect(d.paused and d._find_button("Wild battle (Route 1)").disabled, "F1 in battle pauses and disables test battles")
	await d.key(KEY_F1)
	await d._frames(5)
	await d.pick_menu("Fight")
	await d.shot("b04_moves")
	await d.pick_menu("Splash Jab")
	await d.pick_menu("")  # first target, if asked
	await d.pick_menu("Yes, go!")
	await d._frames(20)
	await d.shot("b05_playback")
	var bs = d._battle()
	await d.wait_battle(["command", "results", "replace"])
	if bs.phase == "command":
		await d.pick_menu("Items")
		await d.shot("b06_items")
		await d.pick_menu("Lure Cage")
		await d.pick_menu("")
		await d.pick_menu("Yes, go!")
		await d._frames(30)
		await d.shot("b07_capture")
	# Fight until the battle ends.
	for round in 30:
		await d.wait_battle(["command", "results", "replace"])
		if bs.phase == "results":
			break
		if bs.phase == "replace":
			await d.pick_menu("")
			continue
		await d.pick_menu("Fight")
		await d.pick_menu("")  # first affordable move
		await d.pick_menu("")
		await d.pick_menu("Yes, go!")
	await d.wait_battle(["results"])
	await d._frames(10)
	await d.shot("b08_results")
	d.expect(bs.phase == "results", "wild battle reached results (%s)" % (bs.summary.outcome if bs.summary != null else "?"))
	bs.continue_button.pressed.emit()
	for i in 300:  # the battle closes and the map carries on underneath
		if d._battle() == null and not d.current_scene.is_locked():
			break
		await d.process_frame
	await d._frames(10)
	await d.shot("b09_world_after")
	d.expect(gs.store.list().any(func(e): return e.kind == SaveGame.KIND_AUTO), "world autosaved after battle")

	var setup = BattleLauncher.tamer_setup(d.root.get_node("DataRegistry").db, gs.current, "rival_01", 1)
	router.goto("res://game/battle/battle_scene.tscn", {"setup": setup, "seed": 11})
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d._frames(5)
	await d.shot("b10_rival_underdog")
	d.expect(d._battle().fields[0].underdog_text.begins_with("UNDERDOG"), "fielding 1 vs 2 shows Underdog")

	# Custom battle panel: set up a 3v1 tamer fight from the world.
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 180)
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Heal party")  # the random wild fight may have knocked someone out
	await d._frames(5)
	d.press("Custom battle...")
	await d._frames(5)
	# The team builder redraws on each change, so look the drop-downs up again each time.
	var opts = d._find_all(d.root.get_node("DebugMenu"), "OptionButton")
	opts[0].select(2)  # you field 3
	opts[0].item_selected.emit(2)
	await d._frames(2)
	opts = d._find_all(d.root.get_node("DebugMenu"), "OptionButton")
	opts[2].select(1)  # tamer
	opts[2].item_selected.emit(1)
	await d._frames(3)
	await d.shot("b11_custom_panel")
	d.press("Start")
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d._frames(5)
	await d.shot("b12_custom_3v1")
	await d._frames(240)  # let the opening messages play so field chips can appear
	await d.shot("b13_custom_3v1_fields")
	d.expect(d._battle().views.size() == 4 and d._battle().fields[1].underdog_text.begins_with("UNDERDOG"),
		"custom 3v1 battle puts 4 creatures on the stage and makes the foe the Underdog")
	# Field-state effect labels: one state per side. Soaked is replaced by Radiant (the longest text),
	# the way the engine does it: the old state is removed, then the new one applied.
	for side in 2:
		d._battle().fields[side].applied("soaked", 1, 4)
	await d._frames(8)
	await d.shot("b14_field_state_single")
	for side in 2:
		d._battle().fields[side].removed("soaked")
		d._battle().fields[side].applied("radiant", 1, 4)
	await d._frames(8)
	await d.shot("b14_field_effect_labels")
	d.expect(d._battle().fields[0].effect_labels().size() == 1 and d._battle().fields[1].effect_labels().size() == 1,
		"each side shows one field state with its effect label")

	# The crowded case: 3v3 with a field state on each side.
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 180)
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Heal party")
	await d._frames(5)
	d.press("Custom battle...")
	await d._frames(5)
	opts = d._find_all(d.root.get_node("DebugMenu"), "OptionButton")
	opts[0].select(2)  # you field 3
	opts[0].item_selected.emit(2)
	await d._frames(2)
	d.press("Foe team")
	await d._frames(3)
	for i in 2:  # the foe team needs three creatures before it can field three
		d.press("Add creature")
		await d._frames(2)
	opts = d._find_all(d.root.get_node("DebugMenu"), "OptionButton")
	opts[1].select(2)  # foes field 3
	opts[1].item_selected.emit(2)
	await d._frames(3)
	d.press("Start")
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d._frames(240)
	for side in 2:
		d._battle().fields[side].applied("radiant", 1, 4)
	await d._frames(8)
	await d.shot("b15_field_effect_labels_3v3")
	d.expect(d._battle().views.size() == 6, "a 3v3 battle puts 6 creatures on the stage")
	d._clear(d.RUN_SAVES)
	d._finish()
