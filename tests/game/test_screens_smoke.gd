extends GdUnitTestSuite
## Every front-end screen loads and builds without script errors, and the
## Settings autoload round-trips bindings through real InputEvents.

const SCREENS := [
	"res://game/boot/splash.tscn",
	"res://game/menus/title_menu.tscn",
	"res://game/menus/new_game.tscn",
	"res://game/menus/load_menu.tscn",
	"res://game/menus/settings_menu.tscn",
]


func test_screens_build() -> void:
	for path in SCREENS:
		var scene: PackedScene = load(path)
		assert_object(scene).is_not_null()
		var node: Control = auto_free(scene.instantiate())
		add_child(node)
		await get_tree().process_frame
		assert_int(node.get_child_count()).is_greater(0)
		node.set_process_input(false)
		remove_child(node)


func test_new_game_requires_a_name() -> void:
	var node: Control = auto_free(load("res://game/menus/new_game.tscn").instantiate())
	add_child(node)
	await get_tree().process_frame
	assert_bool(node.start_button.disabled).is_true()
	node.name_edit.text = "   "
	node._refresh()
	assert_bool(node.start_button.disabled).is_true()
	node.name_edit.text = "  Ana "
	node._refresh()
	assert_bool(node.start_button.disabled).is_false()
	assert_str(node.clean_name()).is_equal("Ana")
	remove_child(node)


func test_settings_screen_has_four_tabs_and_all_bindings() -> void:
	var node: Control = auto_free(load("res://game/menus/settings_menu.tscn").instantiate())
	add_child(node)
	await get_tree().process_frame
	assert_int(node.tabs.get_tab_count()).is_equal(4)
	for action in GameSettings.ACTIONS:
		assert_str(node.bind_buttons[action].keyboard.text).is_not_equal("—")
	remove_child(node)


func test_bindings_convert_to_events_and_back() -> void:
	for action in GameSettings.ACTIONS:
		for device in ["keyboard", "gamepad"]:
			for b in GameSettings.default_bindings()[action][device]:
				var ev := Settings.binding_to_event(b)
				if ev is InputEventKey or ev is InputEventJoypadButton:
					ev.pressed = true
				assert_dict(Settings.event_to_binding(ev)).is_equal(b)
				assert_str(Settings.describe(b)).is_not_empty()


func test_controls_are_applied_to_the_input_map() -> void:
	Settings.apply_controls()
	for action in GameSettings.ACTIONS:
		assert_bool(InputMap.has_action(action)).is_true()
	# Menus follow game bindings.
	assert_int(InputMap.action_get_events("ui_accept").size()).is_equal(InputMap.action_get_events("accept").size())


# --- Larger parties: every party screen at balance.party_size 12 ------------------
# Each screen is built with a full party of 12 (nicknamed Mon01..Mon12) and checked
# for fitting the 640x360 screen, and every party member must be reachable.

const BIG := 12
## BattleScene's bottom panel, below the stage (STAGE_H = 236).
const BATTLE_AREA := Rect2(0, 236, 640, 124)

var _old_party_size := 0
var _old_game: SaveGame


func before_test() -> void:
	_old_party_size = DataRegistry.db.balance.party_size
	DataRegistry.db.balance.party_size = BalanceDef.MAX_PARTY_SIZE
	_old_game = GameState.current


func after_test() -> void:
	DataRegistry.db.balance.party_size = _old_party_size
	GameState.current = _old_game
	BattlePlayback.instant = false
	SceneRouter.params = {}


func _mon(n: int, prefix: String = "Mon", level: int = 10) -> CreatureInstance:
	var species: Array[String] = ["tidepup", "emberkit", "voltmoth", "sprigling"]
	var c: CreatureInstance = CreatureInstance.create(DataRegistry.db, species[n % species.size()], level)
	c.nickname = "%s%02d" % [prefix, n + 1]
	return c


func _big_save(box: int = 0) -> SaveGame:
	var save: SaveGame = SaveGame.new()
	for i: int in BIG:
		save.party.append(_mon(i))
	for i: int in box:
		save.storage.append(_mon(i, "Box"))
	return save


func _buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for n: Node in root.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if not b.is_queued_for_deletion() and b.is_visible_in_tree():
			out.append(b)
	return out


func _button(root: Node, prefix: String) -> Button:
	for b: Button in _buttons(root):
		if b.text.begins_with(prefix):
			return b
	return null


## Walks the pages of `menu` by picking `turn` (up to `turns` times) and returns
## {"names": the creature names ("Mon01") on enabled buttons whose text holds "<prefix>NN",
## "off": the buttons seen outside `area`}.
func _reach(menu: CommandMenu, prefix: String, area: Rect2, turn: String = "Next page",
		turns: int = 6) -> Dictionary:
	var names: Dictionary = {}
	var off: Array[String] = []
	var re: RegEx = RegEx.create_from_string(prefix + "\\d\\d")
	for step: int in turns + 1:
		await get_tree().process_frame
		await get_tree().process_frame
		for b: Button in _buttons(menu):
			if not area.encloses(b.get_global_rect().grow(-0.5)):
				off.append("%s %s" % [b.text, b.get_global_rect()])
			var m: RegExMatch = re.search(b.text)
			if m != null and not b.disabled:
				var hit: String = m.get_string()
				names[hit.get_slice(" ", hit.get_slice_count(" ") - 1)] = true  # "Party: Mon01" -> "Mon01"
		if not menu.pick_label(turn):
			break
	return {"names": names, "off": off}


func _expect_all(found: Dictionary, prefix: String, count: int, skip: Array = []) -> void:
	var missing: Array[String] = []
	for i: int in count:
		var want: String = "%s%02d" % [prefix, i + 1]
		if not skip.has(want) and not found.names.has(want):
			missing.append(want)
	assert_array(missing).is_empty()
	assert_array(found.off).is_empty()


func test_big_party_page_reaches_every_row() -> void:
	var save: SaveGame = _big_save()
	var s: PartyScreen = PartyScreen.new()
	s.use_game(save, DataRegistry.db)
	add_child(s)
	s._loop()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(Array(ScreenFit.problems(s))).is_empty()
	var area: Rect2 = s.menu_area().get_global_rect()
	for i: int in BIG:
		var b: Button = _button(s.menu, "Mon%02d" % (i + 1))
		assert_object(b).is_not_null()
		b.grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
		# The list scrolls to follow focus: the focused row is inside the visible area.
		assert_bool(area.encloses(b.get_global_rect().grow(-0.5))).override_failure_message(
			"Mon%02d at %s is outside the menu area %s" % [i + 1, b.get_global_rect(), area]).is_true()
	s.close()


func test_big_party_summary_steps_through_everyone() -> void:
	var save: SaveGame = _big_save()
	SummaryScreen.run(self, save.party, 0, save, DataRegistry.db)
	await get_tree().process_frame
	var s: SummaryScreen = WorldTest.find_screen(self, SummaryScreen) as SummaryScreen
	await get_tree().process_frame
	ScreenFit.check(self, s)
	var seen: Array[String] = []
	for i: int in BIG:
		seen.append(s.title_text().get_slice(" ", 0))
		await get_tree().process_frame
		assert_bool(s.menu.pick_label("Next creature")).is_true()
		await get_tree().process_frame
	var want: Array[String] = []
	for i: int in BIG:
		want.append("Mon%02d" % (i + 1))
	assert_array(seen).is_equal(want)
	s.close()


func test_big_party_storage_fits_and_reaches_everyone() -> void:
	var save: SaveGame = _big_save(15)
	StorageScreen.run(self, save, DataRegistry.db)
	await get_tree().process_frame
	var s: StorageScreen = WorldTest.find_screen(self, StorageScreen) as StorageScreen
	await get_tree().process_frame
	ScreenFit.check(self, s)
	var area: Rect2 = s.menu_area().get_global_rect()
	_expect_all(await _reach(s.menu, "Party: Mon", area, "Party page"), "Mon", BIG)
	ScreenFit.check(self, s)
	_expect_all(await _reach(s.menu, "Box: Box", area, "Next page"), "Box", 15)
	# Swap a box creature with the last party creature, picked from the party pages.
	assert_bool(s.menu.pick_label("Previous page")).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(s.menu.pick_label("Box: Box01")).is_true()
	await get_tree().process_frame
	assert_bool(s.menu.pick_label("Swap with a party creature")).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	ScreenFit.check(self, s)
	_expect_all(await _reach(s.menu, "Party: Mon", area, "Party page"), "Mon", BIG)
	var box01: CreatureInstance = save.storage[0]
	for i: int in 3:
		await get_tree().process_frame
		await get_tree().process_frame
		if s.menu.pick_label("Party: Mon12"):
			break
		assert_bool(s.menu.pick_label("Party page")).is_true()
	await get_tree().process_frame
	assert_object(save.party[11]).is_same(box01)
	s.close()


func _storage_pick(s: StorageScreen, label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(s.menu.pick_label(label)).override_failure_message("no option " + label).is_true()
	await get_tree().process_frame


## Deposit and withdraw act on the creature picked on party page 2, by identity.
func test_big_party_storage_deposit_and_withdraw_from_party_page_two() -> void:
	var save: SaveGame = _big_save(3)
	var mon10: CreatureInstance = save.party[9]
	StorageScreen.run(self, save, DataRegistry.db)
	await get_tree().process_frame
	var s: StorageScreen = WorldTest.find_screen(self, StorageScreen) as StorageScreen
	await _storage_pick(s, "Party page")
	assert_bool(Array(s.menu.labels()).has("Party page 2 of 2")).is_true()
	await _storage_pick(s, "Party: Mon10")
	await _storage_pick(s, "Deposit")
	assert_int(save.party.size()).is_equal(BIG - 1)
	assert_bool(save.party.has(mon10)).is_false()
	assert_object(save.storage.back()).is_same(mon10)
	assert_str(save.party[9].nickname).is_equal("Mon11")
	# Still on party page 2, which now ends with Mon12; withdraw Mon10 back from the box.
	assert_bool(Array(s.menu.labels()).any(func(l: String) -> bool: return l.begins_with("Party: Mon12"))).is_true()
	await _storage_pick(s, "Box: Mon10")
	await _storage_pick(s, "Withdraw")
	assert_int(save.party.size()).is_equal(BIG)
	assert_object(save.party.back()).is_same(mon10)
	assert_bool(save.storage.has(mon10)).is_false()
	assert_bool(Array(s.menu.labels()).any(func(l: String) -> bool: return l.begins_with("Party: Mon10"))).is_true()
	ScreenFit.check(self, s)
	s.close()


## The side menu shows 11 rows unpaged: ten item types and Back, as before larger parties.
func test_bag_with_ten_items_does_not_page() -> void:
	var save: SaveGame = _big_save()
	var ids: PackedStringArray = DataRegistry.db.ids("items")
	assert_int(ids.size()).is_greater_equal(10)
	for i: int in 10:
		save.inventory[ids[i]] = 1
	GameState.current = save
	var m: PauseMenu = auto_free(PauseMenu.new())
	add_child(m)
	m._open("Menu")
	m._bag()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(m.menu.page_count()).is_equal(1)
	assert_int(m.menu.labels().size()).is_equal(11)
	for b: Button in _buttons(m.menu):
		assert_bool(ScreenFit.VIEW.encloses(b.get_global_rect().grow(-0.5))).override_failure_message(
			"%s at %s is off the screen" % [b.text, b.get_global_rect()]).is_true()
	m._close()
	remove_child(m)


func test_big_party_bag_target_list_fits() -> void:
	var save: SaveGame = _big_save()
	save.inventory = {"salve": 3}
	GameState.current = save
	var m: PauseMenu = auto_free(PauseMenu.new())
	add_child(m)
	m._open("Menu")
	m._bag()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(m.menu.pick_label("Salve")).is_true()
	_expect_all(await _reach(m.menu, "Mon", ScreenFit.VIEW), "Mon", BIG)
	m._close()
	remove_child(m)


func _big_battle(lead_level: int = 10, foe_level: int = 5) -> Node:
	BattlePlayback.instant = true
	var party: Array = []
	for i: int in BIG:
		party.append(_mon(i, "Mon", lead_level if i == 0 else 10))
	var pack: Array = [CreatureInstance.create(DataRegistry.db, "sprigling", foe_level)]
	SceneRouter.params = {"setup": BattleSetup.wild(party, pack, 1, {"salve": 2}), "seed": 5}
	var scene: Node = auto_free(load("res://game/battle/battle_scene.tscn").instantiate())
	add_child(scene)
	for i: int in 600:
		if scene.phase == "command" and scene.menu.is_choosing():
			break
		await get_tree().process_frame
	assert_str(scene.phase).is_equal("command")
	await get_tree().process_frame
	return scene


func test_big_party_battle_swap_menu_reaches_the_bench() -> void:
	var scene: Node = await _big_battle()
	assert_bool(scene.menu.pick_label("Swap")).is_true()
	var found: Dictionary = await _reach(scene.menu, "Mon", BATTLE_AREA)
	_expect_all(found, "Mon", BIG, ["Mon01"])
	assert_bool(found.names.has("Mon01")).is_false()  # the lead is on the field
	remove_child(scene)


func test_big_party_battle_item_targets_reach_everyone() -> void:
	var scene: Node = await _big_battle()
	assert_bool(scene.menu.pick_label("Items")).is_true()
	await get_tree().process_frame
	assert_bool(scene.menu.pick_label("Salve")).is_true()
	_expect_all(await _reach(scene.menu, "Mon", BATTLE_AREA), "Mon", BIG)
	remove_child(scene)


## Twelve participants, each with XP, a level, a new move and Bond, still fit the results panel.
func test_big_party_results_panel_fits() -> void:
	var scene: Node = await _big_battle()
	var events: Array = []
	for b: Battler in scene.engine.sides[0].battlers:
		events.append({"type": "xp_gain", "bid": b.bid, "amount": 123})
		events.append({"type": "level_up", "bid": b.bid, "level": 11})
		events.append({"type": "move_learned", "bid": b.bid, "move": "scrap"})
		events.append({"type": "bond", "bid": b.bid, "change": 2})
	scene._log = events
	scene.summary = BattleSummary.of(BattleSummary.WON, [], "")
	scene._show_results(scene.engine.result())
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = scene._results_panel
	assert_bool(ScreenFit.VIEW.encloses(panel.get_global_rect().grow(-0.5))).override_failure_message(
		"results panel %s is off the screen" % panel.get_global_rect()).is_true()
	assert_bool(ScreenFit.VIEW.encloses(scene.continue_button.get_global_rect())).is_true()
	remove_child(scene)


## With six creatures nothing pages: the lists look as they did before larger parties.
func test_six_creature_lists_do_not_page() -> void:
	var save: SaveGame = _big_save(15)
	save.party.resize(6)
	StorageScreen.run(self, save, DataRegistry.db)
	await get_tree().process_frame
	var s: StorageScreen = WorldTest.find_screen(self, StorageScreen) as StorageScreen
	await get_tree().process_frame
	ScreenFit.check(self, s)
	var party_rows: int = Array(s.menu.labels()).filter(func(l: String) -> bool: return l.begins_with("Party: ")).size()
	assert_int(party_rows).is_equal(6)
	assert_bool(Array(s.menu.labels()).any(func(l: String) -> bool: return l.begins_with("Party page"))).is_false()
	s.close()
	save.inventory = {"salve": 3}
	GameState.current = save
	var m: PauseMenu = auto_free(PauseMenu.new())
	add_child(m)
	m._open("Menu")
	m._bag()
	await get_tree().process_frame
	assert_bool(m.menu.pick_label("Salve")).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(m.menu.page_count()).is_equal(1)
	assert_int(m.menu.labels().size()).is_equal(7)  # six creatures and Back
	m._close()
	remove_child(m)


func test_big_party_send_out_menu_reaches_the_bench() -> void:
	var scene: Node = await _big_battle(1, 60)
	for i: int in 3000:
		if scene.phase == "replace" and scene.menu.is_choosing():
			break
		if scene.phase == "command" and scene.menu.is_choosing():
			await get_tree().process_frame
			var labels: PackedStringArray = scene.menu.labels()
			if labels.has("Fight"):
				scene.menu.pick_label("Fight")
			else:
				for l: String in labels:
					if scene.menu.pick_label(l):
						break
		await get_tree().process_frame
	assert_str(scene.phase).is_equal("replace")
	var found: Dictionary = await _reach(scene.menu, "Mon", BATTLE_AREA)
	_expect_all(found, "Mon", BIG, ["Mon01"])
	remove_child(scene)
