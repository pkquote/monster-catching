extends RefCounted
## The `ui` tour (driver.gd --mode=ui).
## New game -> F1 -> UI gallery: the creature card (sprite, radar, bars, moves, passive, held item)
## for a creature at Lv 5, 50 and 99, then a dual-type species with a very long nickname and a held item.
## Checks that nothing in the card spills outside its rect.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, press, key...) and its tree.

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

	await d.key(KEY_F1)
	await d._frames(5)
	d.press("UI gallery...")
	await d._frames(10)
	var menu = d.root.get_node("DebugMenu")
	var page = menu._page
	d.expect(page != null and page.card != null, "the UI gallery page opens with a creature card")

	for level in [5, 50, 99]:
		page.level_spin.value = level
		await d._frames(8)
		await d.shot("u%02d_lv%d" % [[5, 50, 99].find(level) + 1, level])
		d.expect(page.card.header_text().ends_with("Lv %d" % level), "the card shows Lv %d" % level)
		d.expect(_outside(page.card).is_empty(), "nothing spills outside the card at Lv %d: %s" % [level, _outside(page.card)])

	# A dual-type species with a long nickname and a held item, trained.
	var dual := 0
	var db = d.root.get_node("DataRegistry").db
	for i in page.species_pick.item_count:
		if db.creature(page._species_ids[i]).types.size() > 1:
			dual = i
			break
	page.species_pick.select(dual)
	page.species_pick.item_selected.emit(dual)
	page.nickname_edit.text = "Sir Reginald Bartholomew the Magnificent Third"
	page.nickname_edit.text_changed.emit(page.nickname_edit.text)
	page.item_pick.select(5)
	page.item_pick.item_selected.emit(5)
	page.trained_spin.value = 30
	await d._frames(8)
	await d.shot("u04_dual_long_name")
	d.expect(_outside(page.card).is_empty(), "a long nickname stays inside the card: %s" % [_outside(page.card)])

	d._clear(d.RUN_SAVES)
	d._finish()


func _outside(card: Control) -> Array:
	var bad: Array = []
	var rect: Rect2 = card.get_global_rect().grow(0.5)
	for n in card.find_children("*", "Control", true, false):
		var r: Rect2 = n.get_global_rect()
		if n.visible and r.size.x > 0.0 and not rect.encloses(r):
			bad.append("%s %s" % [n.get_class(), r])
	return bad
