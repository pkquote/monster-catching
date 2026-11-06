extends RefCounted
## The `bag` tour (driver.gd --mode=bag).
## Test party (Tidepup hurt) -> a heal, a held, a capture item and one with a very long
## description (added to the loaded content in memory only) in the bag -> Menu -> Bag ->
## Down through the list with real keys: the left pane shows each focused item, and Back
## shows "Pick an item." -> Salve's "use on who?" list replaces the pane -> back out.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, hold, press...) and
## its tree (d.root, d.current_scene, d.process_frame).

var d

## SideMenu's info page: at (8, 8), 404 wide, at most 344 tall.
const PAGE := Rect2(8, 8, 404, 344)
const LONG_ID := "tour_long_item"


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

	# 1. The test party from the F1 menu (Tidepup hurt, so the Salve is usable) and the bag.
	await d.key(KEY_F1)
	await d._frames(5)
	d.press("Get test party")
	await d._frames(10)
	await d.key(KEY_F1)
	await d._frames(5)
	var pup = gs.current.party[0]
	pup.hp = 1
	db._tables["items"][LONG_ID] = ItemDef.from_dict({"id": LONG_ID, "name": "Overlong Test Charm",
		"category": "held", "price": 999,
		"description": "A deliberately long description to check the bag pane: " + \
			"it goes on and on about nothing at all, sentence after sentence. ".repeat(8),
		"held": {"effects": [{"op": "type_power", "type": "water", "mult": 1.1}]}})
	gs.current.inventory = {"salve": 3, "oran_berry": 1, "lure_cage": 5, LONG_ID: 1}
	var ow = d.current_scene

	# 2. Menu -> Bag: the first item (Salve) is focused and shown.
	await d.key(KEY_C)
	await d.pick_menu("Bag")
	await d._frames(5)
	var pm = ow.pause_menu
	var s = pm.bag_summary()
	var steps: Array = [["bag01_salve", "Salve", "heal", "Usable now."],
		["bag02_oran_berry", "Oran Berry", "held", "Give it from the Summary."],
		["bag03_lure_cage", "Lure Cage", "capture", "Used in battle."],
		["bag04_long_description", "Overlong Test Charm", "held", "Give it from the Summary."]]
	for i: int in steps.size():
		var step: Array = steps[i]
		if i > 0:
			await d.key(KEY_DOWN)
			await d._frames(4)
		await d.shot(step[0])
		var body: String = s.body_text()
		d.expect(s.is_visible_in_tree() and s.title_text() == step[1] and s.icon_category() == step[2]
			and body.ends_with("\n" + step[3]), "%s: the pane shows %s (%s | %s)" % [step[0], step[1], s.title_text(), body.replace("\n", " | ")])
		_expect_fits(pm, step[0])
	await d.key(KEY_DOWN)  # Back
	await d._frames(4)
	await d.shot("bag05_back")
	d.expect(s.title_text() == "" and s.body_text() == "Pick an item.", "Back shows Pick an item. (%s)" % s.body_text())

	# 3. Salve -> the "use on who?" list replaces the pane; Back brings the pane back.
	await d.pick_menu("Salve")
	await d._frames(5)
	await d.shot("bag06_use_on_who")
	d.expect(not s.is_visible_in_tree() and "Use the Salve on who?" in pm.page_text(),
		"choosing the Salve shows the use-on-who page (%s)" % pm.page_text().replace("\n", " | "))
	await d.pick_menu("Back")
	await d._frames(5)
	d.expect(s.is_visible_in_tree() and s.title_text() == "Salve", "Back from the targets shows the pane again")
	await d.pick_menu("Back")
	await d._frames(5)
	await d.shot("bag07_menu_after")
	d.expect(not s.is_visible_in_tree(), "closing the bag hides the pane")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)
	db._tables["items"].erase(LONG_ID)
	d._clear(d.RUN_SAVES)
	d._finish()


## The info page sits inside its 404x344 area and every visible pane label inside the page.
func _expect_fits(pm, what: String) -> void:
	var page: Rect2 = pm._page.get_global_rect()
	var ok: bool = PAGE.grow(0.5).encloses(page)
	var s = pm.bag_summary()
	for l: Label in d._find_all(s, "Label"):
		if l.is_visible_in_tree() and not page.grow(0.5).encloses(l.get_global_rect()):
			ok = false
	d.expect(ok, "%s: the pane fits its 404x344 page (page %s)" % [what, page])
