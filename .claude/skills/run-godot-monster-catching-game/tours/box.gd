extends RefCounted
## The `box` tour (driver.gd --mode=box): the slot-addressed creature boxes.
## New game -> F1 test party, Fill box x4 (48 creatures) -> the centre's Storage Box ->
## browse (the card follows the cursor) -> pick one up and place it (carry, placed) -> mark three
## and carry them to another box (group, group placed) -> a refusal -> F1 Unlock a box ->
## the Party screen with its card. Screenshots: bx01_browse ... bx07_party.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, key, press...) and its tree.

var d


func _storage():
	for n in d._find_all(d.current_scene, "CanvasLayer"):
		if n.get_script() != null and n.get_script().get_global_name() == "StorageScreen":
			return n
	return null


func _on_screen(s) -> bool:
	for b in s.party_buttons() + s.box_buttons() + [s.card()]:
		if not ScreenFit.VIEW.encloses(b.get_global_rect().grow(-0.5)):
			return false
	return true


func _at(s, loc: Dictionary) -> void:
	if loc.has("party"):
		s.party_buttons()[loc.party].grab_focus()
	else:
		s.show_box(BoxStorage.box_of(loc.box))
		s.box_buttons()[BoxStorage.index_in_box(loc.box)].grab_focus()
	await d._frames(3)


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
	var ow = d.current_scene
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Get test party")
	await d._frames(10)
	for i in 4:
		d.press("Fill box")
		await d._frames(5)
	d.expect(BoxStorage.count(gs.current) == 48, "48 creatures in the boxes (%d)" % BoxStorage.count(gs.current))
	await d.key(KEY_F1)
	await d._frames(5)

	await ow.change_map("town_01_center", "entry")
	await d._frames(10)
	ow.player.place(d._tile_centre(8, 3), Vector2i.UP)
	await d.key(KEY_Z)
	await d._frames(8)
	var s = _storage()
	d.expect(s != null, "the Storage Box opens the box screen")
	if s == null:
		d._finish()
		return
	d.expect(_on_screen(s), "every slot and the card are on the screen")
	await _at(s, {"box": 5})
	await d.shot("bx01_browse")
	d.expect(s.card().header_text() == s.box_buttons()[5].creature().display_name(db) + "  Lv %d" % s.box_buttons()[5].creature().level,
		"the card follows the cursor onto a box creature")

	# Pick one up (a box creature) and place it on an empty slot in box 3.
	var mover = s.box_buttons()[5].creature()
	await d.key(KEY_Z)
	await _at(s, {"box": 65})
	await d.shot("bx02_carry")
	d.expect(s.held().size() == 1, "one creature is held")
	await d.key(KEY_Z)
	await d._frames(5)
	await d.shot("bx03_placed")
	d.expect(BoxStorage.creature_at(gs.current, 65) == mover and BoxStorage.creature_at(gs.current, 5) == null,
		"the creature moved to the empty slot, leaving its old one empty")

	# Mark three in box 1 and carry them to box 2.
	for k in [0, 1, 2]:
		await _at(s, {"box": k})
		await d.key(KEY_V)
	d.expect(s.marks().size() == 3, "three creatures are marked")
	await d.key(KEY_Z)
	await d.key(KEY_PAGEDOWN)
	await _at(s, {"box": 30 + 10})
	await d.shot("bx04_group")
	d.expect(s.held().size() == 3 and s.header_text() == "Box 2 / 8", "three are carried to box 2")
	await d.key(KEY_Z)
	await d._frames(5)
	await d.shot("bx05_group_placed")
	d.expect(s.held().is_empty() and BoxStorage.count(gs.current) == 48, "the group was placed; nobody lost")

	# A refusal: the only healthy creature can't leave. Make the rest of the party faint.
	for i in range(1, gs.current.party.size()):
		gs.current.party[i].hp = 0
	await _at(s, {"party": 0})
	await d.key(KEY_Z)
	await _at(s, {"box": 100})
	await d.key(KEY_Z)
	await d._frames(5)
	await d.shot("bx06_refusal")
	d.expect(s.help_text() == "Keep at least one creature that can fight.", "the refusal is shown in the help line")
	await d.key(KEY_X)  # put it down
	await d.key(KEY_X)  # close
	await d.wait_unlocked(ow)

	# F1 > Unlock a box.
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Unlock a box")
	await d._frames(5)
	d.expect(gs.current.boxes_unlocked == 9, "Unlock a box opens a ninth box")
	await d.key(KEY_F1)
	await d._frames(5)

	# The Party screen with the card.
	await d.key(KEY_C)
	await d.pick_menu("Party")
	await d._frames(8)
	await d.shot("bx07_party")
	var pm = d._find_all(d.current_scene, "CanvasLayer").filter(func(n): return n.has_method("card") and n.get_script().get_global_name() == "PartyScreen")
	d.expect(not pm.is_empty() and pm[0].card().header_text().begins_with(gs.current.party[0].display_name(db)),
		"the Party screen's card shows the first creature")
	await d.pick_menu("Back")
	await d.pick_menu("Close")
	d._clear(d.RUN_SAVES)
	d._finish()
