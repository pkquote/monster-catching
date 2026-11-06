extends RefCounted
## The `progress` tour (driver.gd --mode=progress).
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
	await d._frames(10)
	var ow = d.current_scene

	# 1. The test party (Tidepup, Emberkit, Voltmoth at level 8) from the F1 menu.
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Get test party")
	await d._frames(10)
	await d.shot("p01_test_party")
	d.expect(gs.current.party.size() == 3, "test party granted")
	gs.current.inventory["reset_seed"] = 1

	# 2. Striker Affinity on Tidepup, then Give XP to level 16.
	d.press("Set Affinity...")
	await d._frames(5)
	d.press("Striker")
	await d._frames(5)
	await d.shot("p02_striker_affinity")
	d.expect(gs.current.party[0].affinity.get("striker", 0) > 0, "Tidepup got the Striker affinity")
	d.press("Give XP...")
	await d._frames(5)
	d.press("To level 16")
	await d._frames(10)

	# 3. Learn Move: replace a move on the first offer, keep the rest for later; 4. Grow now.
	var replaced := false
	var grew := false
	var offers := 0
	for i in 1200:
		var m = d._find_menu()
		if m != null:
			var labels = m.labels()
			if "Grow now" in labels:
				await d._frames(5)
				await d.shot("p05_grow_offer")
				d.expect("Torrentusk" in d._screen_page(m), "the Grow screen names Torrentusk (%s)" % d._screen_page(m).replace("\n", " "))
				m.pick_label("Grow now")
				grew = true
			elif labels.size() > 0 and labels[labels.size() - 1] == "Keep it for later":
				offers += 1
				await d._frames(5)
				if not replaced:
					await d.shot("p03_learn_move")
					d.expect("wants to learn" in d._screen_title(m), "Learn Move screen opens (%s)" % d._screen_title(m))
					var before := Array(gs.current.party[0].moves)
					m.pick_label("Replace")
					replaced = true
					await d._frames(5)
					d.expect(Array(gs.current.party[0].moves) != before, "a move was replaced (%s -> %s)" % [before, gs.current.party[0].moves])
				else:
					m.pick_label("Keep it for later")
			elif "OK" in labels and grew:
				await d._frames(5)
				await d.shot("p06_grown")
				d.expect("grew into" in d._screen_page(m), "the Grow screen says it grew (%s)" % d._screen_page(m))
				m.pick_label("OK")
			else:
				m.pick_label("")
			await d._frames(5)
		elif not ow.is_locked():
			break
		await d.process_frame
	await d._frames(10)
	d.expect(replaced and offers >= 1, "Learn Move was offered (%d offers)" % offers)
	d.expect(gs.current.party[0].species == "torrentusk", "Tidepup grew into Torrentusk (%s)" % gs.current.party[0].species)
	d.expect(not ow.is_locked(), "the world is unlocked after the progress screens")

	# 5. Party: move Torrentusk to second place.
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d._frames(5)
	await d.shot("p07_party")
	await d.pick_menu("Torrentusk")
	await d._frames(3)
	await d.shot("p08_party_row_menu")
	await d.pick_menu("Move")
	await d._frames(3)
	await d.shot("p09_party_move")
	await d.pick_menu("Emberkit")
	await d._frames(3)
	d.expect(gs.current.party[1].species == "torrentusk" and gs.current.party[0].species == "emberkit",
		"Torrentusk moved to second place (%s, %s)" % [gs.current.party[0].species, gs.current.party[1].species])

	# 6. Summary: the card, Moves..., Train.... 7. +1 Speed.
	await d.pick_menu("Torrentusk")
	await d.pick_menu("Summary")
	await d._frames(5)
	await d.shot("p10_summary_stats")
	var summ = d._find_all(d.current_scene, "CanvasLayer").filter(func(n): return n.get("mode") != null)[0]
	d.expect(summ.mode == "top" and summ.card().header_text().begins_with("Torrentusk"), "Summary opens on the top level with the card")
	await d.pick_menu("Moves...")
	await d._frames(5)
	await d.shot("p11_summary_moves")
	d.expect(summ.mode == "moves", "Moves... opens the moves list")
	await d.pick_menu("Back")
	await d._frames(3)
	await d.pick_menu("Train...")
	await d._frames(5)
	await d.shot("p12_summary_training")
	d.expect(summ.mode == "train", "Train... opens the training list")
	await d.pick_menu("+1 Speed")
	await d._frames(5)
	await d.shot("p13_trained_speed")
	d.expect(gs.current.party[1].trained("spd") == 1, "+1 Speed trained")
	await d.pick_menu("Back")  # to the top level
	await d._frames(3)
	await d.pick_menu("Back")  # closes the Summary
	await d._frames(3)
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")  # the party list
	await d._frames(3)

	# 8. Bag: Reset Seed -> Torrentusk -> Yes.
	await d.pick_menu("Bag")
	await d.pick_menu("Reset Seed")
	await d._frames(3)
	await d.shot("p14_seed_target")
	await d.pick_menu("Torrentusk")
	await d._frames(3)
	await d.shot("p15_seed_confirm")
	await d.pick_menu("Yes")
	await d._frames(3)
	await d.shot("p16_seed_done")
	await d.pick_menu("OK")
	d.expect(gs.current.party[1].trained("spd") == 0 and gs.current.inventory.get("reset_seed", 0) == 0,
		"the Reset Seed returned the training points and was used up")
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)

	# 9. The centre's Storage Box: deposit, then withdraw. (change_map for the trip.)
	await ow.change_map("town_01_center", "entry")
	await d._frames(10)
	ow.player.place(d._tile_centre(8, 3), Vector2i.UP)
	await d.key(KEY_Z)
	await d._frames(5)
	await d.shot("p17_storage_open")
	d.expect(d._find_menu() != null and d._screen_title(d._find_menu()).begins_with("Box"), "the Storage Box opens the storage screen")
	await d.pick_menu("Party: Voltmoth")
	await d._frames(3)
	await d.shot("p18_storage_party_row")
	await d.pick_menu("Deposit")
	await d._frames(5)
	await d.shot("p19_storage_deposited")
	d.expect(gs.current.party.size() == 2 and gs.current.storage.size() == 1, "Voltmoth deposited into the box")
	await d.pick_menu("Box: Voltmoth")
	await d.pick_menu("Withdraw")
	await d._frames(5)
	await d.shot("p20_storage_withdrawn")
	d.expect(gs.current.party.size() == 3 and gs.current.storage.size() == 0, "Voltmoth withdrawn again")
	await d.pick_menu("Back")
	await d.wait_unlocked(ow)

	# 10. Route 1's deep grass is unsafe: Party -> a row shows the message, Storage is disabled.
	await ow.change_map("route_01", "from_town")
	await d._frames(10)
	ow.roller._rate = 0.0
	ow.player.place(d._tile_centre(12, 7), Vector2i.RIGHT)
	await d.hold(KEY_D, 14)
	d.expect(not ow.is_safe_here(), "the deep grass corner is unsafe (%s)" % ow.player.feet_tile())
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d.pick_menu("Emberkit")
	await d._frames(3)
	await d.shot("p21_unsafe_party_row")
	var um = d._find_menu()
	d.expect(um != null and "It isn't safe to swap creatures here." in d._screen_page(um), "the party row page says it isn't safe to swap")
	d.expect(um != null and not um.pick_label("Storage"), "Storage can't be picked in the unsafe zone")
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	d._clear(d.RUN_SAVES)
	d._finish()
