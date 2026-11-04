extends RefCounted
## The `overworld` tour (driver.gd --mode=overworld).
## Overworld tour: new game at home -> out the door -> the professor's cutscene ->
## pick a starter in the lab -> the lab rival battle -> back in control.
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
	await d.shot("o01_home")
	d.expect(ow.map.map_id() == "town_01_home", "a new game starts at home")
	await d.hold(KEY_D, 32)  # ends ~2px off the door column: corner-slipping carries you through
	await d.hold(KEY_S, 70)
	await d.wait_unlocked(ow)
	await d._frames(10)
	await d.shot("o02_town")
	d.expect(ow.map.map_id() == "town_01", "the door leads into town (%s)" % ow.map.map_id())
	await d.hold(KEY_S, 12)  # onto the path: the professor stops you
	await d._frames(40)
	await d.shot("o03_prof_stops_you")
	await d.talk_until(func(): return d._find_menu() != null)
	await d._frames(5)
	await d.shot("o04_lab_choice")
	d.expect(ow.map.map_id() == "town_01_lab", "the cutscene walks you to the lab")
	await d.pick_menu("Tidepup")
	await d.talk_until(func(): return d._battle() != null)
	await d.wait_battle(["command"])
	await d.shot("o05_rival_battle")
	await d.fight_to_end()
	await d.shot("o06_rival_results")
	d._battle().continue_button.pressed.emit()
	await d.talk_until(func(): return not ow.is_locked() and d._battle() == null)
	await d._frames(10)
	await d.shot("o07_back_in_lab")
	d.expect(gs.current.party.size() == 1 and d.root.get_node("Story").flag("got_starter"),
		"the starter joined the party (%d)" % gs.current.party.size())
	var story = d.root.get_node("Story")

	# Heal centre: rest at the counter, then buy a Salve.
	await ow.change_map("town_01_center", "entry")
	await d._frames(10)
	gs.current.party[0].hp = 1
	ow.player.place(d._tile_centre(3, 3), Vector2i.UP)
	await d.key(KEY_Z)
	await d.talk_until(func(): return d._find_menu() != null)
	await d.shot("o08_heal_prompt")
	await d.pick_menu("Yes")
	await d.talk_until(func(): return not ow.is_locked())
	d.expect(gs.current.party[0].hp == gs.current.party[0].max_hp(d.root.get_node("DataRegistry").db)
		and gs.current.story.last_heal.get("map", "") == "town_01_center", "resting heals and sets the wake-up point")
	gs.current.money = 1000
	var salves: int = gs.current.inventory.get("salve", 0)
	ow.player.place(d._tile_centre(7, 3), Vector2i.UP)
	await d.key(KEY_Z)
	await d.pick_menu("Buy")
	await d.pick_menu("Salve")
	await d.shot("o09_shop")
	await d.pick_menu("×1")
	await d.pick_menu("OK")
	await d.pick_menu("Back")
	await d.pick_menu("Leave")
	await d._frames(5)
	d.expect(gs.current.inventory.get("salve", 0) == salves + 1 and gs.current.money == 850, "bought a Salve for 150")

	# Route 1: walk up the path into Scout Ana's line of sight. (A level-20 starter,
	# so the scripted fights are won and the tour stays on the route.)
	var starter = gs.current.party[0]
	starter.level = 20
	starter.heal_full(d.root.get_node("DataRegistry").db)
	await ow.change_map("route_01", "from_town")
	await d._frames(10)
	await d.shot("o10_route")
	await d.hold(KEY_W, 270)
	await d.talk_until(func(): return d._battle() != null)
	await d.wait_battle(["command"])
	await d.shot("o11_tamer_battle")
	await d.fight_to_end()
	d._battle().continue_button.pressed.emit()
	await d.talk_until(func(): return not ow.is_locked() and d._battle() == null)
	var ana = ow.map.entities().get_node("ScoutAna")
	d.expect(story.last_battle_request.get("tamer_id", "") == "scout_ana", "Scout Ana spotted you and battled")
	await d.shot("o12_after_tamer")

	# Tall grass: make every step roll an encounter, then run from it.
	gs.current.party[0].hp = gs.current.party[0].max_hp(d.root.get_node("DataRegistry").db)
	ow.roller._rate = 1.0
	ow.roller._grace = 0
	ow.player.place(d._tile_centre(12, 26), Vector2i.RIGHT)
	await d.hold(KEY_D, 14)
	await d.pick_menu("1 creature")
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d.shot("o13_wild_from_grass")
	d.expect(d._battle().setup.is_wild, "stepping into tall grass started a wild battle")
	await d.pick_menu("Run")
	await d.pick_menu("Yes, go!")
	await d.wait_battle(["results"])
	d._battle().continue_button.pressed.emit()
	await d.talk_until(func(): return not ow.is_locked() and d._battle() == null)
	ow.roller._rate = 0.0

	# Quick Draw with the Sharpshooter.
	ow.player.place(d._tile_centre(6, 7), Vector2i.UP)
	await d.key(KEY_Z)
	await d.talk_until(func(): return d._find_menu() != null)
	await d.pick_menu("Let's play")
	var qd = null
	for i in 120:
		var found = d._find_all(d.root, "Control").filter(func(n): return n.name == "QuickDraw")
		if not found.is_empty():
			qd = found[0]
			break
		await d.process_frame
	var shot_taken := false
	for i in 1500:
		if not is_instance_valid(qd):
			break
		if qd._big.text == "!":
			if not shot_taken:
				await d.shot("o14_quick_draw")
				shot_taken = true
			await d.key(KEY_Z)
		elif qd._done:
			await d.key(KEY_Z)
		await d.process_frame
	await d.talk_until(func(): return not ow.is_locked())
	d.expect(story.last_minigame().has("won"), "Quick Draw finished (%s)" % story.last_minigame())

	# Save from the pause menu, quit, and resume at the same spot.
	ow.player.place(d._tile_centre(10, 30), Vector2i.DOWN)
	await d.key(KEY_C)
	await d.pick_menu("Save")
	await d.shot("o15_pause_menu")
	await d.pick_menu("Quit to title")
	await d.wait_scene("TitleMenu", 120)
	await d._frames(20)
	await d.key(KEY_Z)  # Resume
	await d.wait_scene("Overworld", 180)
	await d._frames(20)
	ow = d.current_scene
	await d.shot("o16_resumed")
	d.expect(ow.map.map_id() == "route_01" and ow.player.feet_tile() == Vector2i(10, 30),
		"Resume puts you back where you saved (%s %s)" % [ow.map.map_id(), ow.player.feet_tile()])
	d._clear(d.RUN_SAVES)
	d._finish()
