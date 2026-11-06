extends RefCounted
## The `passives` tour (driver.gd --mode=passives).
## Test party -> Set passive (Tidepup's rolled passive = Undertow) -> a seeded wild battle
## whose opening fires Undertow's entry trigger (banner) -> Set Affinity Striker (unlocks
## Finisher) -> the Passive Unlocked screen (keep current) -> Summary with both passives ->
## Use Finisher.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, hold, press...) and
## its tree (d.root, d.current_scene, d.process_frame).

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var dm = d.root.get_node("DebugMenu")
	var db = d.root.get_node("DataRegistry").db
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d._frames(10)

	# 1. The test party (Tidepup leads) from the F1 menu.
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Get test party")
	await d._frames(10)
	d.expect(gs.current.party.size() == 3 and gs.current.party[0].species == "tidepup", "test party granted, Tidepup leads")
	var pup = gs.current.party[0]

	# 2. Set passive: Tidepup's Rolled slot = Undertow, made active.
	d.press("Set passive...")
	await d._frames(5)
	var opts = d._find_all(dm, "OptionButton")  # creature, passive, slot
	var passive_opt = opts[1]
	for i in passive_opt.item_count:
		if passive_opt.get_item_text(i) == "Undertow":
			passive_opt.select(i)
	opts[2].select(0)  # Rolled
	d._find_all(dm, "CheckBox")[0].button_pressed = true
	await d._frames(3)
	await d.shot("x01_set_passive_page")
	d.press("Apply")
	await d._frames(5)
	await d.shot("x02_set_passive_done")
	d.expect(pup.passive == "undertow" and pup.active_passive == "rolled", "Tidepup's active passive is Undertow (%s/%s)" % [pup.passive, pup.active_passive])
	d.expect("Undertow" in dm._status.text, "the status line names Undertow (%s)" % dm._status.text)
	await d.key(KEY_F1)
	await d._frames(5)

	# 3. A seeded wild battle against one level-5 Pebblet: Undertow fires on entry.
	var pack := [CreatureInstance.create(db, "pebblet", 5)]
	var setup = BattleLauncher.wild_setup(db, gs.current, pack, 1)
	router.goto("res://game/battle/battle_scene.tscn", {"setup": setup, "seed": 7})
	var caught := false
	for i in 900:  # catch the banner while it's fully faded in
		var b = d._battle()
		if b != null and b.last_passive_banner != null and is_instance_valid(b.last_passive_banner) \
				and b.last_passive_banner.visible and b.last_passive_banner.modulate.a > 0.95:
			caught = true
			break
		await d.process_frame
	await d.shot("x03_undertow_banner")
	var bs = d._battle()
	d.expect(caught and bs.last_passive_banner.text == "Tidepup's Undertow!",
		"the passive banner shows \"Tidepup's Undertow!\" (%s)" % (bs.last_passive_banner.text if caught else "no banner"))
	await d.wait_battle(["command"])
	await d._frames(5)
	await d.shot("x04_enemy_soaked")
	d.expect(bs._log.any(func(e): return e.type == "passive_triggered" and e.passive == "undertow"),
		"the battle log has Undertow's PASSIVE_TRIGGERED")
	d.expect(bs._log.any(func(e): return e.type == "field_applied" and e.side == 1 and e.state == "soaked"),
		"Undertow soaked the enemy side")

	# 4. Back to the world; Set Affinity Striker unlocks Finisher.
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 180)
	await d._frames(10)
	var ow = d.current_scene
	pup = gs.current.party[0]
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Set Affinity...")
	await d._frames(5)
	d.press("Striker")
	await d._frames(5)
	await d.shot("x05_affinity_unlocks_finisher")
	d.expect(pup.affinity_passive == "finisher", "Striker unlocked Finisher (%s)" % pup.affinity_passive)
	d.expect("Unlocked Finisher." in dm._status.text, "the status line reports the unlock (%s)" % dm._status.text)
	await d.key(KEY_F1)
	await d._frames(5)

	# 5. The Passive Unlocked screen (the one a battle shows after an unlock): keep current.
	var done := [false]
	var show_unlock := func():
		await PassiveUnlockScreen.run(ow, pup, db)
		done[0] = true
	show_unlock.call()
	await d._frames(10)
	await d.shot("x06_passive_unlocked_screen")
	var um = d._find_menu()
	d.expect(um != null and d._screen_title(um) == "Tidepup awakened Finisher!" and "Undertow" in d._screen_page(um)
		and "Finisher" in d._screen_page(um), "the unlock screen shows both passives (%s)" % (d._screen_page(um).replace("\n", " | ") if um else "no menu"))
	await d.pick_menu("Keep current")
	for i in 60:
		if done[0]:
			break
		await d.process_frame
	d.expect(done[0] and pup.active_passive == "rolled", "Keep current leaves Undertow active")

	# 6. Summary: both passives and "Use Finisher".
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d.pick_menu("Tidepup")
	await d.pick_menu("Summary")
	await d._frames(5)
	await d.shot("x07_summary_both_passives")
	var summ = d._find_all(d.current_scene, "CanvasLayer").filter(func(n): return n.get("mode") != null)[0]
	var sm = d._find_menu()
	d.expect(summ.mode == "top" and "Passive: Undertow" in summ.page_text(), "the Summary shows Undertow as active")
	d.expect(sm != null and "Use Finisher" in sm.labels(), "the Summary offers Use Finisher (%s)" % (sm.labels() if sm else []))
	await d.pick_menu("Use Finisher")
	await d._frames(5)
	await d.shot("x08_summary_finisher_active")
	sm = d._find_menu()
	d.expect(pup.active_passive == "affinity" and "Passive: Finisher" in summ.page_text(), "Use Finisher makes Finisher active")
	d.expect(sm != null and "Use Undertow" in sm.labels(), "the Summary now offers Use Undertow (%s)" % (sm.labels() if sm else []))
	await d.pick_menu("Back")
	await d._frames(3)
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)
	d._clear(d.RUN_SAVES)
	d._finish()
