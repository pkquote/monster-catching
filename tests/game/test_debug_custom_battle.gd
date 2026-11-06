extends GdUnitTestSuite
## The F1 Custom battle team builder: format row, both teams, the slot editor and
## the bag editor. Battles it starts are exhibitions. Saves go to a throwaway folder.

var _suite: Dictionary
var db: Database
var world: Overworld


func before() -> void:
	_suite = WorldTest.begin_suite("debug_custom_battle")
	db = DataRegistry.db


func after() -> void:
	DebugMenu.close()
	WorldTest.end_suite(_suite)


func after_test() -> void:
	DebugMenu.close()
	WorldTest.close(world)
	world = null


# --- Helpers ----------------------------------------------------------------------

## A new game whose party is `party`, the overworld open, F1 open on the builder page.
func _open_builder(party: Array) -> DebugCustomBattlePage:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	for c: CreatureInstance in party:
		GameState.current.party.append(c)
	world = await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	DebugMenu.open()
	_button("Custom battle...").pressed.emit()
	await get_tree().process_frame
	assert_bool(DebugMenu._page is DebugCustomBattlePage).is_true()
	return DebugMenu._page as DebugCustomBattlePage


func _buttons(text: String) -> Array:
	var out: Array = []
	for n: Node in DebugMenu.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b.text == text and b.is_inside_tree():
			out.append(b)
	return out


func _button(text: String) -> Button:
	var all: Array = _buttons(text)
	assert_int(all.size()).override_failure_message("no button '%s'" % text).is_greater(0)
	return all[0] if not all.is_empty() else null


func _press(text: String) -> void:
	var b: Button = _button(text)
	assert_bool(b.disabled).override_failure_message("'%s' is disabled" % text).is_false()
	b.pressed.emit()
	await get_tree().process_frame


## The open page's drop-downs in tree order.
func _opts() -> Array:
	return Array(DebugMenu.find_children("*", "OptionButton", true, false))


func _spins() -> Array:
	return Array(DebugMenu.find_children("*", "SpinBox", true, false))


func _select(o: OptionButton, index: int) -> void:
	o.select(index)
	o.item_selected.emit(index)
	await get_tree().process_frame


## Selects the item whose metadata is `value` (an id, "" for none/empty).
func _select_meta(o: OptionButton, value: String) -> void:
	for i: int in o.item_count:
		if str(o.get_item_metadata(i)) == value:
			await _select(o, i)
			return
	fail("no option with id '%s'" % value)


func _texts(o: OptionButton) -> Array:
	var out: Array = []
	for i: int in o.item_count:
		out.append(o.get_item_text(i))
	return out


func _snapshot() -> String:
	var d: Dictionary = GameState.current.to_dict()
	d.erase("playtime_sec")
	d.erase("saved_unix")
	return JSON.stringify(d, "", true)


func _held_item_id() -> String:
	for id: String in db.ids("items"):
		if db.item(id).category == "held":
			return id
	return ""


# --- Builder page -----------------------------------------------------------------

func test_one_creature_party_can_build_a_3v3() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	assert_int(page.mine.size()).is_equal(1)
	var you: OptionButton = _opts()[0]
	assert_int(you.item_count).is_equal(1)  # a 1-creature team can only field 1
	await _press("Add creature")
	await _press("Add creature")
	assert_int(page.mine.size()).is_equal(3)
	await _select(_opts()[0], 2)  # you field 3, now offered
	await _select(_opts()[2], 1)  # tamer
	await _press("Foe team")
	await _press("Add creature")
	await _press("Add creature")
	await _select(_opts()[1], 2)  # foes field 3, now offered
	assert_int(page.foes.size()).is_equal(3)
	var setup: BattleSetup = page.make_setup()
	assert_bool(setup.exhibition).is_true()
	assert_bool(setup.is_wild).is_false()
	assert_int(setup.sides[0].party.size()).is_equal(3)
	assert_int(setup.sides[0].field_count).is_equal(3)
	assert_int(setup.sides[1].party.size()).is_equal(3)
	assert_int(setup.sides[1].field_count).is_equal(3)
	assert_object(setup.sides[0].party[0]).is_not_same(GameState.current.party[0])


func test_defaults_copy_the_party_and_roll_one_foe_at_party_level() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8),
		CreatureInstance.create(db, "emberkit", 12)])
	assert_int(page.mine.size()).is_equal(2)
	assert_str(page.mine[1].species).is_equal("emberkit")
	assert_int(page.foes.size()).is_equal(1)
	var foe: CreatureSpec = page.foes[0]
	assert_int(foe.level).is_equal(BattleLauncher.party_level(GameState.current))
	assert_array(Array(foe.moves)).is_equal(Array(foe.natural_moves(db)))
	assert_bool(page.wild).is_true()


func test_no_party_still_builds_a_team_at_level_5() -> void:
	var page: DebugCustomBattlePage = await _open_builder([])
	assert_int(page.mine.size()).is_equal(1)
	assert_int(page.foes[0].level).is_equal(5)
	assert_bool(_button("Fill from my party").disabled).is_true()
	assert_bool(_button("Start").disabled).is_false()


func test_fill_from_party_copies_up_to_party_size_with_moves_item_passive() -> void:
	var party: Array = []
	for i: int in db.balance.party_size + 1:
		party.append(CreatureInstance.create(db, "tidepup", 10 + i))
	var lead: CreatureInstance = party[0]
	lead.moves = PackedStringArray(["tackle", "riptide"])
	lead.held_item = _held_item_id()
	lead.passive = "sturdy"
	var page: DebugCustomBattlePage = await _open_builder([])
	GameState.current.party = party  # bigger than party_size, as after lowering it
	DebugMenu.refresh_page()
	await _press("Fill from my party")
	assert_int(page.mine.size()).is_equal(db.balance.party_size)
	var first: CreatureSpec = page.mine[0]
	assert_array(Array(first.moves)).is_equal(["tackle", "riptide"])
	assert_str(first.held_item).is_equal(lead.held_item)
	assert_str(first.passive).is_equal("sturdy")
	assert_int(page.mine[3].level).is_equal(13)


func test_all_levels_applies_to_one_team_only() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8),
		CreatureInstance.create(db, "emberkit", 8)])
	var foe_level: int = page.foes[0].level
	var my_moves: Array = page.mine.map(func(s: CreatureSpec) -> Array: return Array(s.moves))
	var spin: SpinBox = _spins()[0]
	spin.value = 20
	await _press("Apply")
	for i: int in page.mine.size():
		var s: CreatureSpec = page.mine[i]
		assert_int(s.level).is_equal(20)
		assert_array(Array(s.moves)).is_equal(my_moves[i])  # party copies keep their moves
	assert_int(page.foes[0].level).is_equal(foe_level)
	await _press("Foe team")
	(_spins()[0] as SpinBox).value = 33
	await _press("Apply")
	assert_int(page.foes[0].level).is_equal(33)
	# The default foe has natural moves: they follow the level.
	assert_array(Array(page.foes[0].moves)).is_equal(Array(page.foes[0].natural_moves(db)))
	assert_int(page.mine[0].level).is_equal(20)


func test_add_stops_at_party_size_and_remove_at_one() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	for i: int in db.balance.party_size + 3:
		if not _button("Add creature").disabled:
			await _press("Add creature")
	assert_int(page.mine.size()).is_equal(db.balance.party_size)
	assert_bool(_button("Add creature").disabled).is_true()
	assert_int(_buttons("Remove").size()).is_equal(db.balance.party_size)
	for i: int in db.balance.party_size + 3:
		var removes: Array = _buttons("Remove")
		if not (removes[0] as Button).disabled:
			(removes[0] as Button).pressed.emit()
			await get_tree().process_frame
	assert_int(page.mine.size()).is_equal(1)
	assert_bool((_buttons("Remove")[0] as Button).disabled).is_true()
	# A wild pack is capped at 3; a tamer team at party_size.
	await _press("Foe team")
	for i: int in db.balance.party_size + 3:
		if not _button("Add creature").disabled:
			await _press("Add creature")
	assert_int(page.foes.size()).is_equal(BattleLauncher.MAX_SIDE)
	await _select(_opts()[2], 1)  # tamer
	assert_bool(_button("Add creature").disabled).is_false()


func test_bench_marker_follows_the_field_count() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8),
		CreatureInstance.create(db, "emberkit", 8), CreatureInstance.create(db, "voltmoth", 8)])
	await _select(_opts()[0], 0)  # you field 1
	var benched: int = 0
	for n: Node in DebugMenu.find_children("*", "Label", true, false):
		if (n as Label).text == "bench":
			benched += 1
	assert_int(benched).is_equal(2)
	assert_int(page.my_field).is_equal(1)


func test_wild_foes_all_take_the_field() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _press("Foe team")
	await _press("Add creature")
	assert_bool((_opts()[1] as OptionButton).disabled).is_true()  # wild: the whole pack fights
	var setup: BattleSetup = page.make_setup()
	assert_bool(setup.is_wild).is_true()
	assert_int(setup.sides[1].field_count).is_equal(2)


func test_randomize_rolls_new_foes_at_the_same_levels() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _press("Foe team")
	await _press("Add creature")
	await _press("Add creature")
	var levels: Array = page.foes.map(func(s: CreatureSpec) -> int: return s.level)
	var before_specs: Array = page.foes.duplicate()
	await _press("Randomize")
	assert_int(page.foes.size()).is_equal(3)
	assert_array(page.foes.map(func(s: CreatureSpec) -> int: return s.level)).is_equal(levels)
	for i: int in 3:
		assert_object(page.foes[i]).is_not_same(before_specs[i])


# --- Slot editor ------------------------------------------------------------------

func _open_editor(page: DebugCustomBattlePage) -> DebugSlotEditor:
	(_buttons("Edit")[0] as Button).pressed.emit()
	await get_tree().process_frame
	assert_bool(DebugMenu._page is DebugSlotEditor).is_true()
	return DebugMenu._page as DebugSlotEditor


func test_slot_editor_level_change_resets_natural_moves_and_keeps_edited_ones() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var ed: DebugSlotEditor = await _open_editor(page)
	assert_bool(ed.spec.moves_edited).is_true()  # a party copy keeps its moves...
	await _press("Reset to natural")  # ...until reset to the natural set
	assert_bool(ed.spec.moves_edited).is_false()
	var level: SpinBox = _spins()[0]
	level.value = 14
	await get_tree().process_frame
	var natural14: PackedStringArray = CreatureSpec.natural(db, "tidepup", 14, DebugMenu.rng).moves
	assert_array(Array(ed.spec.moves)).is_equal(Array(natural14))
	assert_bool(Array(ed.spec.moves).has("tide_beam")).is_true()
	# Hand-edit slot 1: from now on level changes keep the moves.
	await _select_meta(_opts()[1], "ember_flick")
	assert_bool(ed.spec.moves_edited).is_true()
	var edited: Array = Array(ed.spec.moves)
	assert_str(edited[0]).is_equal("ember_flick")
	level.value = 5
	await get_tree().process_frame
	assert_array(Array(ed.spec.moves)).is_equal(edited)
	assert_int(ed.spec.level).is_equal(5)
	await _press("Done")
	assert_object(DebugMenu._page).is_same(page)
	assert_int(page.mine[0].level).is_equal(5)
	assert_str(page.mine[0].moves[0]).is_equal("ember_flick")


func test_party_moves_survive_all_levels_and_the_level_spinner() -> void:
	var c: CreatureInstance = CreatureInstance.create(db, "tidepup", 8)
	c.moves = PackedStringArray(["tide_beam", "ember_flick"])  # not the natural set
	var page: DebugCustomBattlePage = await _open_builder([])
	GameState.current.party = [c]
	DebugMenu.refresh_page()
	await _press("Fill from my party")
	assert_array(Array(page.mine[0].moves)).is_equal(["tide_beam", "ember_flick"])
	(_spins()[0] as SpinBox).value = 30
	await _press("Apply")
	assert_int(page.mine[0].level).is_equal(30)
	assert_array(Array(page.mine[0].moves)).is_equal(["tide_beam", "ember_flick"])
	var ed: DebugSlotEditor = await _open_editor(page)
	(_spins()[0] as SpinBox).value = 3
	await get_tree().process_frame
	assert_int(ed.spec.level).is_equal(3)
	assert_array(Array(ed.spec.moves)).is_equal(["tide_beam", "ember_flick"])
	await _press("Done")
	assert_array(Array(page.mine[0].moves)).is_equal(["tide_beam", "ember_flick"])
	assert_array(Array(page.make_setup().sides[0].party[0].moves)).is_equal(["tide_beam", "ember_flick"])


func test_species_change_keeps_edited_moves() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var ed: DebugSlotEditor = await _open_editor(page)
	await _press("Reset to natural")
	await _select_meta(_opts()[2], "ember_flick")
	var edited: Array = Array(ed.spec.moves)
	await _select_meta(_opts()[0], "voltmoth")
	assert_str(ed.spec.species).is_equal("voltmoth")
	assert_array(Array(ed.spec.moves)).is_equal(edited)
	# The labels follow the new species.
	var ember: String = CreatureSpec.move_label(db, "voltmoth", 8, "ember_flick")
	assert_str((_opts()[2] as OptionButton).get_item_text((_opts()[2] as OptionButton).selected)).is_equal(ember)


func test_slot_editor_labels_moves_and_passives() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _open_editor(page)
	var opts: Array = _opts()
	var move1: Array = _texts(opts[1])
	assert_bool(move1.has("%s ✓ Lv 1" % db.move("tackle").name)).is_true()
	assert_bool(move1.has("%s Lv 9 (later)" % db.move("riptide").name)).is_true()
	assert_bool(move1.has("%s ✗ can't learn" % db.move("ember_flick").name)).is_true()
	assert_int(move1.size()).is_equal(db.count("moves") + 1)  # every move plus the "(choose a move)" placeholder
	assert_bool(_texts(opts[2]).has("(empty)")).is_true()
	var held: Array = _texts(opts[5])
	assert_bool(held.has("(none)")).is_true()
	assert_bool(held.has(db.item(_held_item_id()).name)).is_true()
	var passives: Array = _texts(opts[6])
	assert_bool(passives.has("(none)")).is_true()
	assert_bool(passives.has("%s ★ rolls" % db.passive("tidal_heart").name)).is_true()
	assert_bool(passives.has("%s ✗ not normal" % db.passive("sturdy").name)).is_true()
	assert_bool(passives.has("%s (Affinity)" % db.passive("finisher").name)).is_true()
	assert_bool(_labels_text().contains("Natural at Lv 8")).is_true()


func _labels_text() -> String:
	var out: PackedStringArray = PackedStringArray()
	for n: Node in DebugMenu.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return "\n".join(out)


func test_slot_editor_refuses_duplicate_or_no_moves() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var ed: DebugSlotEditor = await _open_editor(page)
	var opts: Array = _opts()
	await _select_meta(opts[1], "tackle")
	await _select_meta(opts[2], "tackle")
	assert_bool(_button("Done").disabled).is_true()
	assert_str(_labels_text()).contains("Duplicate")
	await _select_meta(opts[2], "")
	await _select_meta(opts[3], "")
	await _select_meta(opts[4], "")
	assert_bool(_button("Done").disabled).is_false()
	assert_array(Array(ed.spec.moves)).is_equal(["tackle"])
	await _press("Reset to natural")
	assert_bool(ed.spec.moves_edited).is_false()
	assert_array(Array(ed.spec.moves)).is_equal(Array(ed.spec.natural_moves(db)))


func test_slot_editor_species_item_and_passive() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var ed: DebugSlotEditor = await _open_editor(page)
	await _press("Reset to natural")  # natural moves follow the species
	await _select_meta(_opts()[0], "emberkit")
	assert_str(ed.spec.species).is_equal("emberkit")
	assert_array(Array(ed.spec.moves)).is_equal(Array(ed.spec.natural_moves(db)))
	await _select_meta(_opts()[5], _held_item_id())
	await _select_meta(_opts()[6], "sturdy")
	await _press("Done")
	assert_str(page.mine[0].species).is_equal("emberkit")
	assert_str(page.mine[0].held_item).is_equal(_held_item_id())
	assert_str(page.mine[0].passive).is_equal("sturdy")
	var c: CreatureInstance = page.make_setup().sides[0].party[0]
	assert_str(c.held_item).is_equal(_held_item_id())
	assert_str(c.passive).is_equal("sturdy")


func test_cancel_leaves_the_slot_unchanged() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _open_editor(page)
	await _select_meta(_opts()[0], "emberkit")
	await _press("Cancel")
	assert_object(DebugMenu._page).is_same(page)
	assert_str(page.mine[0].species).is_equal("tidepup")


# --- Bag page ---------------------------------------------------------------------

func _bag_spin(id: String) -> SpinBox:
	for s: SpinBox in _spins():
		if str(s.get_meta("item", "")) == id:
			return s
	return null


func test_bag_editor_round_trip_reset_and_clear() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var inventory_before: Dictionary = GameState.current.inventory.duplicate()
	assert_dict(page.bag).is_equal(BattleLauncher.TEST_BAG)
	await _press("Bag...")
	assert_bool(DebugMenu._page is DebugBagPage).is_true()
	assert_int(_spins().size()).is_equal(db.count("items"))
	assert_float(_bag_spin("lure_cage").value).is_equal(float(BattleLauncher.TEST_BAG.lure_cage))
	_bag_spin("lure_cage").value = 9
	_bag_spin("salve").value = 0
	_bag_spin(_held_item_id()).value = 2
	await _press("Done")
	assert_object(DebugMenu._page).is_same(page)
	assert_int(int(page.bag.lure_cage)).is_equal(9)
	assert_bool(page.bag.has("salve")).is_false()
	assert_int(int(page.bag[_held_item_id()])).is_equal(2)
	assert_int(int(page.make_setup().sides[0].items.lure_cage)).is_equal(9)
	await _press("Bag...")
	assert_float(_bag_spin("lure_cage").value).is_equal(9.0)
	await _press("Clear all")
	assert_dict(page.bag).is_empty()
	assert_float(_bag_spin("lure_cage").value).is_equal(0.0)
	await _press("Reset to test bag")
	assert_dict(page.bag).is_equal(BattleLauncher.TEST_BAG)
	assert_float(_bag_spin("tonic").value).is_equal(float(BattleLauncher.TEST_BAG.tonic))
	await _press("Done")
	assert_dict(GameState.current.inventory).is_equal(inventory_before)


func test_state_survives_the_sub_pages() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _press("Add creature")
	await _select(_opts()[0], 1)
	var specs: Array = page.mine.duplicate()
	await _open_editor(page)
	await _press("Done")
	await _press("Bag...")
	await _press("Done")
	assert_object(DebugMenu._page).is_same(page)
	assert_int(page.mine.size()).is_equal(2)
	assert_object(page.mine[1]).is_same(specs[1])
	assert_int(page.my_field).is_equal(2)
	assert_int((_opts()[0] as OptionButton).selected).is_equal(1)


# --- Start / close ----------------------------------------------------------------

func _label_count(text: String) -> int:
	var n: int = 0
	for l: Node in DebugMenu.find_children("*", "Label", true, false):
		if (l as Label).text == text:
			n += 1
	return n


func test_unused_wild_rows_are_ignored_and_tamer_restores_them() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _select(_opts()[2], 1)  # tamer
	await _press("Foe team")
	for i: int in 4:
		await _press("Add creature")
	assert_int(page.foes.size()).is_equal(5)
	await _select(_opts()[2], 0)  # wild: rows 4 and 5 are unused, not deleted
	assert_int(page.foes.size()).is_equal(5)
	assert_int(_label_count("unused")).is_equal(2)
	(page.foes[4] as CreatureSpec).moves = PackedStringArray()  # broken, but unused
	assert_array(Array(page.errors())).is_empty()
	var setup: BattleSetup = page.make_setup()
	assert_int(setup.sides[1].party.size()).is_equal(BattleLauncher.MAX_SIDE)
	await _select(_opts()[2], 1)  # tamer again: all five are back, and checked
	assert_int(_label_count("unused")).is_equal(0)
	assert_int(page.foes.size()).is_equal(5)
	assert_str(page.errors()[0]).contains("Foe 5")
	assert_object(page.make_setup()).is_null()


func test_start_with_an_invalid_creature_starts_nothing() -> void:
	var c: CreatureInstance = CreatureInstance.create(db, "tidepup", 8)
	c.moves = PackedStringArray()
	var page: DebugCustomBattlePage = await _open_builder([c])
	assert_str(page.errors()[0]).contains("No moves")
	await _press("Start")
	for i: int in 3:
		await get_tree().process_frame
	assert_bool(DebugMenu.is_open()).is_true()
	assert_bool(world.battles.in_battle()).is_false()
	assert_str(DebugMenu._status.text).contains("You 1: No moves")


func test_closing_the_menu_mid_build_starts_nothing_and_keeps_the_save() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var save: SaveGame = GameState.current
	var before_snap: String = _snapshot()
	await _press("Add creature")
	await _open_editor(page)
	await _select_meta(_opts()[0], "emberkit")
	DebugMenu.close()
	for i: int in 5:
		await get_tree().process_frame
	assert_bool(DebugMenu.is_open()).is_false()
	assert_bool(world.battles.in_battle()).is_false()
	assert_object(GameState.current).is_same(save)
	assert_str(_snapshot()).is_equal(before_snap)


func test_start_runs_an_exhibition_over_the_world() -> void:
	await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	await _press("Start")
	for i: int in 5:
		await get_tree().process_frame
	assert_bool(DebugMenu.is_open()).is_false()
	assert_bool(world.battles.in_battle()).is_true()
	var layer: Node = world.battles.get("_battle_layer")
	var scene: Node = layer.get_child(0)
	assert_bool((scene.params.setup as BattleSetup).exhibition).is_true()
	assert_bool(scene.params.defeat_rules).is_false()


func test_custom_battle_needs_no_party() -> void:
	assert_str(GameState.start_new_game("Ana")).is_empty()
	world = await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	DebugMenu.open()
	assert_bool(_button("Custom battle...").disabled).is_false()
	assert_bool(_button("Wild battle (Route 1)").disabled).is_true()
	world.lock(Overworld.LOCK_MENU)
	DebugMenu.close()
	await get_tree().process_frame  # the closed panel is freed at the end of the frame
	DebugMenu.open()
	assert_bool(_button("Custom battle...").disabled).is_true()
	world.unlock(Overworld.LOCK_MENU)


func test_field_drop_down_shows_the_effective_count() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	page.my_field = 3  # wanted more than the team can field
	page.menu.refresh_page()
	await get_tree().process_frame
	var you: OptionButton = _opts()[0]
	assert_int(page.fielded(DebugCustomBattlePage.MINE)).is_equal(1)
	assert_int(you.item_count).is_equal(1)
	assert_int(you.selected).is_equal(0)
	page.add_creature(DebugCustomBattlePage.MINE)
	page.add_creature(DebugCustomBattlePage.MINE)
	page.menu.refresh_page()
	await get_tree().process_frame
	you = _opts()[0]
	assert_int(you.item_count).is_equal(3)
	assert_int(you.selected).is_equal(2)  # the wanted 3 applies again


func test_slot_editor_shows_a_placeholder_when_the_creature_has_no_moves() -> void:
	var page: DebugCustomBattlePage = await _open_builder([CreatureInstance.create(db, "tidepup", 8)])
	var ed: DebugSlotEditor = await _open_editor(page)
	ed.spec.moves = PackedStringArray()
	ed._show_moves()
	ed._refresh()
	var move1: OptionButton = _opts()[1]
	assert_str(move1.get_item_text(move1.selected)).is_equal(DebugSlotEditor.CHOOSE)
	assert_bool(_button("Done").disabled).is_true()
	await _select_meta(move1, "tackle")
	assert_bool(_button("Done").disabled).is_false()
