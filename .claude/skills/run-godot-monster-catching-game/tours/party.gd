extends RefCounted
## The `party` tour (driver.gd --mode=party [--party-size=N]): every screen that lists the
## party, with a full party of N (default: balance.party_size; 1 to BalanceDef.MAX_PARTY_SIZE).
## N is set on the loaded content in memory only: data/balance.json is never written.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, key, pick_menu...) and its tree.

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var db: Database = d.root.get_node("DataRegistry").db
	var size: int = clampi(int(d._opts.get("party-size", str(db.balance.party_size))), 1, BalanceDef.MAX_PARTY_SIZE)
	db.balance.party_size = size
	var tag: String = "q%02d_" % size
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d._frames(10)
	var ow = d.current_scene

	# A full party of `size` (levels 8, 9, ... so the rows differ) and 12 in the box.
	var species: Array[String] = ["tidepup", "emberkit", "voltmoth", "sprigling"]
	gs.current.party.clear()
	for i: int in size:
		gs.current.party.append(CreatureInstance.create(db, species[i % species.size()], 8 + i))
	for i: int in 12:
		gs.current.storage.append(CreatureInstance.create(db, species[(i + 1) % species.size()], 5))
	gs.current.inventory["salve"] = 3
	d.expect(gs.current.party.size() == size, "a party of %d" % size)

	# 1. Menu -> Party: the list (it scrolls to follow focus when longer than the screen).
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d._frames(5)
	await d.shot(tag + "01_party_list")
	for i: int in size - 1:
		await d.key(KEY_DOWN)
	await d._frames(5)
	await d.shot(tag + "02_party_list_last_row")
	var focused = d.root.gui_get_focus_owner()
	var last_label: String = PartyScreen.row_text(db, gs.current.party[size - 1])
	d.expect(focused is Button and focused.text == last_label and ScreenFit.VIEW.encloses(focused.get_global_rect()),
		"Down reaches the last party row, on screen (%s)" % (focused.text if focused is Button else "no focus"))

	# 2. Summary of the last creature (the focused row), then Next creature all the way round.
	await d.key(KEY_Z)
	await d.pick_menu("Summary")
	await d._frames(5)
	await d.shot(tag + "03_summary")
	var summ = d._find_all(d.current_scene, "CanvasLayer").filter(func(n): return n.get("tab") != null)[0]
	for i: int in size - 1:
		await d.pick_menu("Next creature")
	await d._frames(5)
	await d.shot(tag + "04_summary_after_next")
	d.expect(summ.creature() == gs.current.party[size - 2] or size == 1,
		"Next creature steps through the whole party (on %s)" % summ.creature().display_name(db))
	await d.pick_menu("Back")
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")  # the party list

	# 3. Bag -> Salve: the "use on who?" list.
	await d.pick_menu("Bag")
	await d.pick_menu("Salve")
	await d._frames(5)
	await d.shot(tag + "05_bag_target_list")
	var bm = d._find_menu()
	d.expect(bm != null and _all_on_screen(bm), "the bag target list fits the screen")
	if bm != null and bm.page_count() > 1:
		await d.pick_menu("Next page")
		await d._frames(5)
		await d.shot(tag + "06_bag_target_list_page2")
	await d.key(KEY_X)
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)

	# 4. The centre's Storage Box: party rows beside box rows.
	await ow.change_map("town_01_center", "entry")
	await d._frames(10)
	ow.player.place(d._tile_centre(8, 3), Vector2i.UP)
	await d.key(KEY_Z)
	await d._frames(5)
	await d.shot(tag + "07_storage")
	var sm = d._find_menu()
	var screen = d._screen_of(sm) if sm != null else null
	d.expect(screen != null and ScreenFit.problems(screen).is_empty() and not ScreenFit.needs_scroll(screen),
		"the storage screen fits without scrolling")
	if sm != null and sm.labels().size() > 0 and Array(sm.labels()).any(func(l): return l.begins_with("Party page")):
		await d.pick_menu("Party page")
		await d._frames(5)
		await d.shot(tag + "08_storage_party_page2")
		d.expect(not ScreenFit.needs_scroll(screen), "party page 2 fits without scrolling")
	await d.pick_menu("Box: ")
	await d.pick_menu("Swap with a party creature")
	await d._frames(5)
	await d.shot(tag + "09_storage_swap_pick_party")
	d.expect(not ScreenFit.needs_scroll(screen), "the swap party list fits without scrolling")
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")
	await d.wait_unlocked(ow)

	# 5. A singles wild battle: the Swap menu holds the whole bench, then an item's targets.
	var pack: Array = [CreatureInstance.create(db, "sprigling", 3)]
	router.goto("res://game/battle/battle_scene.tscn",
		{"setup": BattleSetup.wild(gs.current.party, pack, 1, {"salve": 2}), "seed": 11})
	await d.wait_scene("BattleScene", 240)
	await d.wait_battle(["command"])
	await d.pick_menu("Swap")
	await d._frames(5)
	await d.shot(tag + "10_battle_swap")
	var wm = d._find_menu()
	d.expect(wm != null and _all_on_screen(wm), "the swap menu fits the screen")
	if wm != null and wm.page_count() > 1:
		await d.pick_menu("Next page")
		await d._frames(5)
		await d.shot(tag + "11_battle_swap_page2")
		await d.key(KEY_Z)  # focus stays on Next page: Accept wraps round to page 1
		await d._frames(5)
		d.expect(Array(wm.labels()).any(func(l): return l.begins_with("Next page") and l.ends_with("1/%d" % wm.page_count())),
			"Accept on Next page wraps to page 1 (%s)" % ", ".join(wm.labels()))
	await d.key(KEY_X)
	await d.pick_menu("Items")
	await d.pick_menu("Salve")
	await d._frames(5)
	await d.shot(tag + "12_battle_item_targets")
	var tm = d._find_menu()
	d.expect(tm != null and _all_on_screen(tm), "the item target list fits the screen")
	d._clear(d.RUN_SAVES)
	d._finish()


## True when every option button of `m` lies on the 640x360 screen.
func _all_on_screen(m: CommandMenu) -> bool:
	for b in m._grid.get_children():
		if b is Button and not b.is_queued_for_deletion() and not ScreenFit.VIEW.encloses(b.get_global_rect().grow(-0.5)):
			return false
	return true
