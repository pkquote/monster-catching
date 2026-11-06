extends RefCounted
## The `builder` tour (driver.gd --mode=builder): the F1 Custom battle team builder.
## New game -> test party -> Custom battle -> grow your team to party_size, All levels ->
## Foe team (tamer, party_size creatures, 3 on the field) -> slot editor (a can't-learn move,
## the move list open) -> bag page -> a 2v3 exhibition fought to the results panel ->
## the save is unchanged and nothing was autosaved. Every page must fit the 640x360 screen
## with its content inside the 340px column.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, press...) and its tree.

var d
var dm
var page


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var db = d.root.get_node("DataRegistry").db
	dm = d.root.get_node("DebugMenu")
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Get test party")
	await d._frames(10)
	var before = _snapshot(gs)
	var saves_before = gs.store.list().size()

	d.press("Custom battle...")
	await d._frames(5)
	page = dm._page
	d.expect(page is DebugCustomBattlePage, "Custom battle opens the team builder")
	await d.shot("t01_builder_default")
	_fits("builder (default)")
	var size = db.balance.party_size
	for i in size:
		if not d._find_button("Add creature").disabled:
			d.press("Add creature")
			await d._frames(2)
	d.expect(page.mine.size() == size, "your team grows to party_size (%d)" % size)
	await _select(0, 1)  # you field 2
	var spin = d._find_all(dm, "SpinBox")[0]
	spin.value = 40
	d.press("Apply")
	await d._frames(3)
	d.expect(page.mine.all(func(s): return s.level == 40), "All levels sets your whole team")
	await d.shot("t02_builder_your_team_full")
	_fits("builder (your team of %d)" % size)
	await _scroll_bottom("t03_builder_your_team_bottom")

	d.press("Foe team")
	await d._frames(3)
	await _select(2, 1)  # tamer
	await _select(1, 2)  # foes field 3
	for i in size:
		if not d._find_button("Add creature").disabled:
			d.press("Add creature")
			await d._frames(2)
	d.expect(page.foes.size() == size, "a tamer foe team grows to party_size")
	d.expect(page.foes.all(func(s): return s.level < 40), "All levels left the foe team alone")
	await d.shot("t04_builder_foe_team_full")
	_fits("builder (foe team)")

	# Slot editor on foe 1: a move it can't learn shows the warning colour.
	# The first row's Edit (d._find_button searches from the end).
	d._find_all(dm, "Button").filter(func(b): return b.text == "Edit")[0].pressed.emit()
	await d._frames(4)
	d.expect(dm._page is DebugSlotEditor, "Edit opens the slot editor")
	await d.shot("t05_slot_editor")
	_fits("slot editor")
	var ed = dm._page
	var move2 = d._find_all(dm, "OptionButton")[2]
	for i in move2.item_count:
		if move2.get_item_text(i).contains("can't learn"):
			move2.select(i)
			move2.item_selected.emit(i)
			break
	await d._frames(3)
	d.expect(ed.spec.moves_edited, "picking a move marks the moves as hand-edited")
	await d.shot("t06_slot_editor_cant_learn")
	move2.show_popup()
	await d._frames(4)
	await d.shot("t07_slot_editor_move_list")
	move2.get_popup().hide()
	await d._frames(2)
	d.press("Done")
	await d._frames(4)
	d.expect(dm._page == page and page.foes[0].moves_edited, "Done keeps the edit and returns to the same builder")

	d.press("Your team")
	await d._frames(3)
	d.press("Bag...")
	await d._frames(4)
	d.expect(dm._page is DebugBagPage, "Bag... opens the bag page")
	await d.shot("t08_bag_page")
	_fits("bag page")
	await _scroll_bottom("t09_bag_page_bottom")
	d.press("Done")
	await d._frames(4)
	d.expect(page.mine.size() == size and page.my_field == 2, "the builder kept its state across the sub-pages")

	d.press("Start")
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d._frames(30)
	await d.shot("t10_exhibition_2v3")
	var bs = d._battle()
	d.expect(bs.engine.sides[0].active().size() == 2 and bs.engine.sides[1].active().size() == 3,
		"the exhibition starts 2v3")
	await d.fight_to_end()
	await d._frames(10)
	await d.shot("t11_exhibition_results")
	d.expect(bs.phase == "results", "the exhibition reached the results panel (%s)"
		% (bs.summary.outcome if bs.summary != null else "?"))
	d.expect(Array(bs.result_lines(bs.engine.result())).has("Exhibition — nothing was saved."),
		"the results say nothing was saved")
	bs.continue_button.pressed.emit()
	for i in 300:
		if d._battle() == null and not d.current_scene.is_locked():
			break
		await d.process_frame
	await d._frames(10)
	await d.shot("t12_world_after")
	d.expect(_snapshot(gs) == before, "the save is unchanged after the exhibition")
	d.expect(gs.store.list().size() == saves_before, "no autosave after the exhibition")
	d._clear(d.RUN_SAVES)
	d._finish()


## Picks item `index` of the page's `n`-th drop-down (looked up again: the page redraws).
func _select(n, index) -> void:
	var o = d._find_all(dm, "OptionButton")[n]
	o.select(index)
	o.item_selected.emit(index)
	await d._frames(3)


func _scroll_bottom(name) -> void:
	dm._scroll.scroll_vertical = 100000
	await d._frames(3)
	await d.shot(name)
	dm._scroll.scroll_vertical = 0
	await d._frames(2)


## The panel is on the 640x360 screen and nothing in the page is wider than its column.
func _fits(what) -> void:
	var panel = dm._scroll.get_parent()
	var rect = panel.get_global_rect()
	var screen = Rect2(Vector2.ZERO, Vector2(640, 360))
	d.expect(screen.encloses(rect), "%s: panel %s fits the screen" % [what, rect])
	var content = dm._box.get_combined_minimum_size().x
	d.expect(content <= dm._page.width() + 0.5, "%s: content %.0fpx fits the %.0fpx column" % [what, content, dm._page.width()])


## The save without what the running overworld legitimately updates.
func _snapshot(gs):
	var dict = gs.current.to_dict()
	for k in ["playtime_sec", "saved_unix", "location", "position"]:
		dict.erase(k)
	return JSON.stringify(dict, "", true)
