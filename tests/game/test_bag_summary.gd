extends GdUnitTestSuite
## The bag's item summary pane: what it shows for an item, and that it fits the 404x344 page.

## Where SideMenu puts its info page, and the most room it has on the 640x360 screen.
const PAGE := Rect2(8, 8, 404, 344)
const LONG_DESCRIPTION := "An absurdly long description written only to stress the pane. " \
	+ "It keeps going well past anything a real item would say, sentence after sentence, " \
	+ "so the summary has to wrap it and then cut it short rather than spill out of the page. " \
	+ "More words follow here, and more after those, until it is several times too long. " \
	+ "Still going: the pane must clip or ellipsize this, never grow past the screen. " \
	+ "Still going: the pane must clip or ellipsize this, never grow past the screen. " \
	+ "Still going: the pane must clip or ellipsize this, never grow past the screen. " \
	+ "Still going: the pane must clip or ellipsize this, never grow past the screen. " \
	+ "Still going: the pane must clip or ellipsize this, never grow past the screen. " \
	+ "The end, at last."

var _base_db: Database
var db: Database
var save: SaveGame
var c: CreatureInstance


func before() -> void:
	_base_db = DataLoader.load_database("res://data").db


func before_test() -> void:
	db = _base_db
	save = SaveGame.new_game("Ana", 1000, RandomNumberGenerator.new())
	save.inventory = {"salve": 3, "oran_berry": 1, "lure_cage": 5}
	c = CreatureInstance.create(db, "tidepup", 10)
	save.party = [c]


## The shipped content plus `extra` item entries, built through the public raw-data route.
func _db_with(extra: Array) -> Database:
	var errors := PackedStringArray()
	var raw: RawData = DataLoader.read_raw("res://data", errors)
	assert_array(errors).is_empty()
	for entry: Dictionary in extra:
		raw.add_entry("items", entry)
	var problems: PackedStringArray = DataValidator.validate(raw)
	assert_array(problems).is_empty()
	return Database.from_raw(raw)


func _summary() -> BagSummary:
	var s: BagSummary = auto_free(BagSummary.new())
	add_child(s)
	return s


## The pane's bottom line (the usability line for a known item).
func _last_line(s: BagSummary) -> String:
	var lines := s.body_text().split("\n")
	return lines[lines.size() - 1]


func test_heal_item_shows_name_count_price_description_effect_and_usable() -> void:
	c.hp = 1
	var s := _summary()
	s.show_item(db, save, "salve")
	var salve := db.item("salve")
	assert_str(s.title_text()).is_equal("Salve")
	assert_str(s.icon_category()).is_equal("heal")
	var body := s.body_text()
	assert_str(body).contains("Owned: 3")
	assert_str(body).contains("Price: %d" % salve.price)
	assert_str(body).contains(salve.description)
	assert_str(body).contains(BagSummary.EFFECT_PREFIX + EffectText.effects(db, salve.effects))
	assert_str(body).contains(BagSummary.EFFECT_PREFIX + "Heals 33% max HP")
	assert_str(_last_line(s)).is_equal("Usable now.")


func test_heal_item_when_no_one_is_hurt() -> void:
	var s := _summary()
	s.show_item(db, save, "salve")
	assert_str(_last_line(s)).is_equal("Can't use: No one needs it right now.")
	assert_str(s.body_text()).not_contains("Usable now.")


func test_held_item_shows_held_effect_and_points_to_the_summary() -> void:
	var s := _summary()
	s.show_item(db, save, "oran_berry")
	var berry := db.item("oran_berry")
	assert_str(s.title_text()).is_equal("Oran Berry")
	assert_str(s.icon_category()).is_equal("held")
	var body := s.body_text()
	assert_str(body).contains("Owned: 1")
	assert_str(body).contains(berry.description)
	assert_str(body).contains(BagSummary.EFFECT_PREFIX + EffectText.triggers(db, berry.held.triggers))
	assert_str(body).contains("On being hit [HP below 50%]: Heals 25% max HP")
	assert_str(_last_line(s)).is_equal("Give it from the Summary.")


func test_capture_item_is_used_in_battle() -> void:
	var s := _summary()
	s.show_item(db, save, "lure_cage")
	assert_str(s.title_text()).is_equal("Lure Cage")
	assert_str(s.icon_category()).is_equal("capture")
	assert_str(s.body_text()).contains("Owned: 5")
	assert_str(_last_line(s)).is_equal("Used in battle.")


func test_an_item_with_no_effects_shows_a_dash() -> void:
	db = _db_with([{"id": "test_long", "name": "Plain Thing", "description": "Does nothing.",
		"category": "key", "price": 0}])
	save.inventory["test_long"] = 1
	var s := _summary()
	s.show_item(db, save, "test_long")
	assert_str(s.body_text()).contains(BagSummary.EFFECT_PREFIX + "—")
	assert_str(_last_line(s)).is_equal("Can't be used.")


func test_unknown_id() -> void:
	save.inventory["ghost"] = 2
	var s := _summary()
	s.show_item(db, save, "ghost")
	assert_str(s.title_text()).is_equal("ghost")
	assert_str(s.icon_category()).is_equal("unknown")
	assert_str(s.body_text()).contains("Owned: 2")
	assert_str(s.body_text()).contains("Unknown item.")
	assert_str(s.body_text()).not_contains(BagSummary.EFFECT_PREFIX)


func test_count_of_zero() -> void:
	var s := _summary()
	s.show_item(db, save, "tonic")
	assert_str(s.body_text()).contains("Owned: 0")


func test_show_empty_after_an_item_clears_it() -> void:
	var s := _summary()
	s.show_item(db, save, "salve")
	s.show_empty()
	assert_str(s.title_text()).is_equal("")
	assert_str(s.icon_category()).is_equal("")
	assert_str(s.body_text()).is_equal("Pick an item.")
	s.show_empty("Your bag is empty.")
	assert_str(s.body_text()).is_equal("Your bag is empty.")


## Lays `item_id` out in a copy of SideMenu's page panel; returns the summary (still in the tree).
func _laid_out(item_id: String) -> BagSummary:
	var root: Control = auto_free(Control.new())
	root.theme = UIKit.theme()
	root.size = Vector2(640, 360)
	add_child(root)
	var page := UIKit.panel(root, 10)
	page.position = PAGE.position
	page.custom_minimum_size = Vector2(PAGE.size.x, 0)
	var s := BagSummary.new()
	page.add_child(s)
	s.show_item(db, save, item_id)
	await _settle(s)
	return s


## Lets the wrapped labels take their width, then shrinks the page to its content.
func _settle(s: BagSummary) -> void:
	for i: int in 4:
		await get_tree().process_frame
	(s.get_parent() as Control).reset_size()
	await get_tree().process_frame


## The page fits PAGE, and every visible label (its full rendered height) sits inside the pane.
func _assert_fits(item_id: String) -> void:
	var s: BagSummary = await _laid_out(item_id)
	_assert_inside(s, item_id)


func _assert_inside(s: BagSummary, what: String) -> void:
	var page: Rect2 = (s.get_parent() as Control).get_global_rect()
	assert_bool(PAGE.grow(0.5).encloses(page)).override_failure_message(
		"%s: page %s does not fit %s" % [what, page, PAGE]).is_true()
	var pane: Rect2 = s.get_global_rect()
	for n: Node in s.find_children("*", "Label", true, false):
		var l: Label = n as Label
		if not l.is_visible_in_tree() or l.text == "":
			continue
		var r: Rect2 = l.get_global_rect()
		assert_bool(pane.grow(0.5).encloses(r)).override_failure_message(
			"%s: label '%s' %s leaves the pane %s" % [what, l.text.left(30), r, pane]).is_true()
		assert_float(r.size.y).override_failure_message("%s: label '%s' has no height" % [what, l.text.left(30)]).is_greater(0.0)
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			# A wrapped label is tall enough for every line it shows.
			var need: float = l.get_visible_line_count() * l.get_line_height()
			assert_float(r.size.y + 0.5).override_failure_message("%s: label '%s' is %.0f tall, needs %.0f" % [
				what, l.text.left(30), r.size.y, need]).is_greater_equal(need)


func test_longest_real_description_fits() -> void:
	var longest := ""
	for id: String in db.ids("items"):
		if longest == "" or db.item(id).description.length() > db.item(longest).description.length():
			longest = id
	save.inventory[longest] = 99
	await _assert_fits(longest)


func test_every_real_item_fits() -> void:
	for id: String in db.ids("items"):
		save.inventory[id] = 999
		await _assert_fits(id)


func test_a_very_long_description_is_cut_to_fit() -> void:
	db = _db_with([{"id": "test_long", "name": "A Very Long Item Name That Keeps Going And Going",
		"description": LONG_DESCRIPTION, "category": "heal", "price": 123456, "target": "one_ally",
		"effects": [{"op": "heal", "fraction": 0.5}, {"op": "restore_energy", "fraction": 0.5},
			{"op": "heal", "fraction": 0.25}]}])
	save.inventory["test_long"] = 999
	await _assert_fits("test_long")


func test_a_description_of_exactly_the_line_cap_shows_whole() -> void:
	db = _db_with([{"id": "test_long", "name": "Six Line Charm", "description": "x", "category": "held",
		"price": 999, "held": {"field": [{"op": "encounter_rate", "mult": 0.9}]}}])
	save.inventory["test_long"] = 1
	var s: BagSummary = await _laid_out("test_long")
	var words := PackedStringArray()
	var lines := 0
	while lines < BagSummary.DESCRIPTION_LINES and words.size() < 400:
		words.append("word%d" % words.size())
		db.item("test_long").description = " ".join(words)
		s.show_item(db, save, "test_long")
		await get_tree().process_frame
		lines = s.description_lines()
	assert_int(lines).is_equal(BagSummary.DESCRIPTION_LINES)
	await _settle(s)
	assert_int(s.description_lines()).is_equal(BagSummary.DESCRIPTION_LINES)
	assert_int(s.description_visible_lines()).is_equal(BagSummary.DESCRIPTION_LINES)
	_assert_inside(s, "six-line description")


func test_use_line_for_every_usability_reason() -> void:
	var cases: Array = [
		[true, "Usable now.", "Usable now."],
		[false, "Unknown item.", "Unknown item."],
		[false, "Give it from the Summary.", "Give it from the Summary."],
		[false, "Used in battle.", "Used in battle."],
		[false, "Can't be used.", "Can't be used."],
		[false, "Can't be used here.", "Can't be used here."],
		[false, "You don't have any.", "You don't have any."],
		[false, "No one needs it right now.", "Can't use: No one needs it right now."],
		[false, "No one has training points to return.", "Can't use: No one has training points to return."],
	]
	for c: Array in cases:
		assert_str(BagSummary.use_line({"ok": c[0], "reason": c[1]})).is_equal(c[2])


func test_use_line_covers_every_reason_field_items_gives() -> void:
	# Every reason string in FieldItems.usability is one of the cases above (a new reason must be added here).
	var src := FileAccess.get_file_as_string("res://core/progress/field_items.gd")
	var known := ["Usable now.", "Unknown item.", "Give it from the Summary.", "Used in battle.", "Can't be used.",
		"Can't be used here.", "You don't have any.", "No one needs it right now.", "No one has training points to return."]
	var re := RegEx.create_from_string("_usability\\((?:true|false), \"([^\"]+)\"\\)")
	var found: Array = []
	for m: RegExMatch in re.search_all(src):
		found.append(m.get_string(1))
	assert_array(found).contains_exactly_in_any_order(known)


func test_training_item_reasons_through_the_pane() -> void:
	save.inventory["reset_seed"] = 1
	var s := _summary()
	s.show_item(db, save, "reset_seed")
	assert_str(_last_line(s)).is_equal("Can't use: No one has training points to return.")
	c.training = {"patk": 2}
	s.show_item(db, save, "reset_seed")
	assert_str(_last_line(s)).is_equal("Usable now.")


func test_an_item_you_have_none_of_says_so() -> void:
	c.hp = 1
	save.inventory["salve"] = 0
	var s := _summary()
	s.show_item(db, save, "salve")
	assert_str(s.body_text()).contains("Owned: 0")
	assert_str(_last_line(s)).is_equal("You don't have any.")
	save.inventory.erase("salve")
	s.show_item(db, save, "salve")
	assert_str(_last_line(s)).is_equal("You don't have any.")
