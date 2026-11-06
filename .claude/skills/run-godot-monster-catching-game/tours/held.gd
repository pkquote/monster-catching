extends RefCounted
## The `held` tour (driver.gd --mode=held).
## Test party -> an Oran Berry in the bag -> Summary -> Give held item -> the Summary line ->
## a seeded wild battle with Tidepup below half HP: the berry fires (a banner naming it, then
## "was used up.") -> back in the world, the Summary says the item is gone.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, hold, press...) and
## its tree (d.root, d.current_scene, d.process_frame).

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var db = d.root.get_node("DataRegistry").db
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d._frames(10)

	# 1. The test party (Tidepup leads) from the F1 menu, plus a held item in the bag.
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Get test party")
	await d._frames(10)
	await d.key(KEY_F1)
	await d._frames(5)
	var pup = gs.current.party[0]
	d.expect(gs.current.party.size() == 3 and pup.species == "tidepup", "test party granted, Tidepup leads")
	gs.current.inventory["oran_berry"] = 1
	var ow = d.current_scene

	# 2. Menu -> Party -> Tidepup -> Summary -> Give held item -> Oran Berry.
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d.pick_menu("Tidepup")
	await d.pick_menu("Summary")
	await d._frames(5)
	await d.shot("h01_summary_no_item")
	var summ = d._find_all(d.current_scene, "CanvasLayer").filter(func(n): return n.get("mode") != null)[0]
	var sm = d._find_menu()
	d.expect("Held item: none" in summ.page_text(), "the Summary shows no held item")
	d.expect(sm != null and "Held item..." in sm.labels(), "the Summary offers Held item... (%s)" % (sm.labels() if sm else []))
	await d.pick_menu("Held item...")
	await d._frames(5)
	sm = d._find_menu()
	d.expect(sm != null and "Give held item" in sm.labels(), "the held list offers Give held item (%s)" % (sm.labels() if sm else []))
	await d.pick_menu("Give held item")
	await d._frames(5)
	await d.shot("h02_give_which_item")
	await d.pick_menu("Oran Berry")
	await d._frames(5)
	await d.shot("h03_summary_holds_berry")
	sm = d._find_menu()
	d.expect(pup.held_item == "oran_berry" and not gs.current.inventory.has("oran_berry"), "Tidepup holds the berry and the bag is empty of it")
	d.expect("Held item: Oran Berry" in summ.page_text(), "the Summary line names the Oran Berry (%s)" % summ.page_text().replace("\n", " | "))
	d.expect(sm != null and "Take back" in sm.labels(), "the held list now offers Take back")
	await d.pick_menu("Back")  # to the top level
	await d._frames(3)
	await d.pick_menu("Back")  # closes the Summary
	await d._frames(3)
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)

	# 3. A seeded wild battle with Tidepup under half HP: the berry fires on the first hit.
	pup.hp = int(pup.max_hp(db) * 0.45)
	var pack := [CreatureInstance.create(db, "pebblet", 5)]
	var setup = BattleLauncher.wild_setup(db, gs.current, pack, 1)
	router.goto("res://game/battle/battle_scene.tscn", {"setup": setup, "seed": 7})
	var banner_shot := false
	var used_shot := false
	var banner_text := ""
	var message_text := ""
	for i in 3000:
		var b = d._battle()
		if b == null:
			await d.process_frame
			continue
		if not banner_shot and b.last_passive_banner != null and is_instance_valid(b.last_passive_banner) \
				and b.last_passive_banner.visible and b.last_passive_banner.modulate.a > 0.95 \
				and "Oran Berry" in b.last_passive_banner.text:
			banner_text = b.last_passive_banner.text
			banner_shot = true
			await d.shot("h04_berry_banner")
		if not used_shot and "used up" in b._message.text:
			message_text = b._message.text
			used_shot = true
			await d.shot("h05_berry_used_up")
		if used_shot and banner_shot:
			break
		if b.phase == "results":
			break
		if b.phase == "command" and b.menu.is_choosing():
			await d.pick_menu("Fight")
			await d.pick_menu("")
			await d.pick_menu("")
			await d.pick_menu("Yes, go!")
		await d.process_frame
	d.expect(banner_shot and banner_text == "Tidepup's Oran Berry!", "the banner names the item (%s)" % banner_text)
	d.expect(used_shot and message_text == "Tidepup's Oran Berry was used up.", "the used-up message shows (%s)" % message_text)
	var bs = d._battle()
	await d.fight_to_end()
	await d._frames(10)
	d.expect(bs._log.any(func(e): return e.type == "item_consumed" and e.item == "oran_berry"), "the battle log has ITEM_CONSUMED for the berry")
	bs.continue_button.pressed.emit()
	for i in 300:
		if d._battle() == null:
			break
		await d.process_frame

	# 4. Back in the world the berry is gone.
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 180)
	await d._frames(10)
	ow = d.current_scene
	pup = gs.current.party[0]
	d.expect(pup.held_item == "", "Tidepup holds nothing after the battle (%s)" % pup.held_item)
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d.pick_menu("Tidepup")
	await d.pick_menu("Summary")
	await d._frames(5)
	await d.shot("h06_summary_item_gone")
	summ = d._find_all(d.current_scene, "CanvasLayer").filter(func(n): return n.get("mode") != null)[0]
	d.expect("Held item: none" in summ.page_text(), "the Summary shows no held item again")
	await d.pick_menu("Back")
	await d._frames(3)
	await d.pick_menu("Cancel")
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)
	d._clear(d.RUN_SAVES)
	d._finish()
