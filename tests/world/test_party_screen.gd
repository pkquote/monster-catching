extends GdUnitTestSuite
## The party screen: rows, reordering, the storage gate and the Menu key in battle.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("party_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	WorldTest.close(world)


func _screen() -> PartyScreen:
	return WorldTest.find_screen(world, PartyScreen) as PartyScreen


func _open() -> PartyScreen:
	PartyScreen.run(world)
	await get_tree().process_frame
	return _screen()


func _pick(s: PartyScreen, prefix: String) -> void:
	assert_bool(s.menu.pick_label(prefix)).is_true()
	await get_tree().process_frame


func test_reorder_changes_lead() -> void:
	var a := Story.give_creature("tidepup", 5)
	var b := Story.give_creature("emberkit", 5)
	var s := await _open()
	await _pick(s, "Emberkit")
	await _pick(s, "Move")
	await _pick(s, "Tidepup")  # destination: the first slot
	assert_object(GameState.current.party[0]).is_same(b)
	assert_object(GameState.current.party[1]).is_same(a)
	assert_bool(s.menu.labels()[0].begins_with("Emberkit")).is_true()


func test_move_cancel_leaves_order() -> void:
	var a := Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	var s := await _open()
	await _pick(s, "Emberkit")
	await _pick(s, "Move")
	await _pick(s, "Cancel")
	assert_object(GameState.current.party[0]).is_same(a)


func test_storage_disabled_when_unsafe() -> void:
	Story.give_creature("tidepup", 5)
	world.player.place(GameMap.centre_of(Vector2i(2, 2)), Vector2i.DOWN)
	assert_bool(world.is_safe_here()).is_false()
	var s := await _open()
	await _pick(s, "Tidepup")
	assert_str(s.page_text()).is_equal("It isn't safe to swap creatures here.")
	assert_bool(s.menu.labels().has("Storage")).is_true()
	assert_bool(s.menu.pick_label("Storage")).is_false()


func test_storage_enabled_when_safe() -> void:
	Story.give_creature("tidepup", 5)
	world.player.place(GameMap.centre_of(Vector2i(6, 4)), Vector2i.DOWN)
	assert_bool(world.is_safe_here()).is_true()
	var s := await _open()
	await _pick(s, "Tidepup")
	assert_str(s.page_text()).is_not_equal("It isn't safe to swap creatures here.")
	assert_bool(s.menu.pick_label("Storage")).is_true()


func test_ready_to_grow_badge() -> void:
	var db := DataRegistry.db
	var ready := Story.give_creature("tidepup", 16)
	var young := Story.give_creature("emberkit", 5)
	assert_str(PartyScreen.row_text(db, ready)).contains("Ready to grow")
	assert_str(PartyScreen.row_text(db, young)).not_contains("Ready to grow")
	assert_str(PartyScreen.row_text(db, ready)).contains("Lv 16")
	var s := await _open()
	assert_bool(s.menu.labels()[0].contains("Ready to grow")).is_true()


func test_menu_key_ignored_in_battle() -> void:
	world.lock(Overworld.LOCK_BATTLE)  # as run_battle does
	world.battles.set("_battle_layer", CanvasLayer.new())
	assert_bool(world.battles.in_battle()).is_true()
	var ev := InputEventAction.new()
	ev.action = "menu"
	ev.pressed = true
	world._unhandled_input(ev)
	await get_tree().process_frame
	assert_bool(world.pause_menu.is_open()).is_false()
	world.battles.get("_battle_layer").free()
	world.battles.set("_battle_layer", null)
	world.unlock(Overworld.LOCK_BATTLE)


func _bars(btn: Button) -> Array[ProgressBar]:
	var out: Array[ProgressBar] = []
	for n in btn.get_children():
		if n is ProgressBar:
			out.append(n)
	return out


func test_rows_show_sprite_and_hp_energy_bars() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 5)
	c.hp = 7
	c.energy = 3
	var s := await _open()
	var btn: Button = null
	for n in s.menu.find_children("*", "Button", true, false):
		if n.text.begins_with("Tidepup"):
			btn = n
	assert_object(btn).is_not_null()
	assert_bool(btn.get_children().any(func(n): return n is CreatureSpriteSlot)).is_true()
	var bars := _bars(btn)
	assert_int(bars.size()).is_equal(2)
	assert_float(bars[0].max_value).is_equal(float(c.max_hp(db)))
	assert_float(bars[0].value).is_equal(7.0)
	assert_float(bars[1].max_value).is_equal(float(c.max_energy(db)))
	assert_float(bars[1].value).is_equal(3.0)
	assert_str(btn.text).contains("HP 7/")


func test_six_rows_and_back_fit_the_screen() -> void:
	for i in 6:
		Story.give_creature("tidepup", 5)
	var s := await _open()
	await get_tree().process_frame
	ScreenFit.check(self, s)


func test_summary_opens_from_row() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	await _pick(s, "Tidepup")
	await _pick(s, "Summary")
	var sum: SummaryScreen = null
	for n in world.get_children():
		if n is SummaryScreen:
			sum = n
	assert_object(sum).is_not_null()
	assert_str(sum.title_text()).contains("Tidepup")
	assert_bool(sum.menu.pick_label("Back")).is_true()
	await get_tree().process_frame
	assert_bool(s.menu.labels()[0].begins_with("Tidepup")).is_true()


## The longest row (status and growth badges) must end before the HP / energy bars.
func test_long_row_text_clears_the_bars() -> void:
	# Worst case: Tidepup is the only species that can show "Ready to grow"; level cap,
	# fully trained HP and Stamina (the most digits), and the longest status name.
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", db.balance.level_cap)
	c.training = {"hp": int(db.balance.training_cfg.max_per_stat), "stamina": int(db.balance.training_cfg.max_per_stat)}
	var longest := ""
	for id in db.ids("statuses"):
		if db.status(id).name.length() > longest.length():
			longest = db.status(id).name
	c.status = ""
	for id in db.ids("statuses"):
		if db.status(id).name == longest:
			c.status = id
	c.hp = c.max_hp(DataRegistry.db)
	c.energy = c.max_energy(DataRegistry.db)
	var s := await _open()
	var btn: Button = null
	for n in s.menu.find_children("*", "Button", true, false):
		if n.text.begins_with("Tidepup"):
			btn = n
	assert_str(btn.text).contains("Ready to grow")
	assert_str(btn.text).contains(longest.to_upper())
	var font := btn.get_theme_font("font")
	var size := btn.get_theme_font_size("font_size")
	var widest := 0.0
	for line in btn.text.split("
"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var text_end: float = btn.get_theme_stylebox("normal").content_margin_left + widest
	for bar in _bars(btn):
		assert_float(text_end).is_less_equal(bar.position.x)


func test_party_lead_passive_line() -> void:
	var lead := Story.give_creature("tidepup", 5)
	lead.passive = "undertow"  # has a field effect (encounter rate)
	var other := Story.give_creature("emberkit", 5)
	other.passive = "kindling"
	var s := await _open()
	assert_str(s.page_text()).is_equal("Lead passive: Undertow")
	await get_tree().process_frame
	ScreenFit.check(self, s)
	s.close()
	lead.passive = "tidal_heart"  # battle effects only: no line
	s = await _open()
	assert_str(s.page_text()).is_empty()
	s.close()
	lead.affinity_passive = "finisher"
	lead.active_passive = "affinity"
	lead.passive = "undertow"  # not active, so it doesn't count
	s = await _open()
	assert_str(s.page_text()).is_empty()


func _row_buttons(s: PartyScreen) -> Array:
	return s.menu.find_children("*", "Button", true, false)


func test_the_card_shows_the_first_creature_and_follows_the_cursor() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 6)
	Story.give_creature("sprigling", 7)
	var s := await _open()
	await get_tree().process_frame
	assert_object(s.card()).is_not_null()
	assert_str(s.card().header_text()).is_equal("Tidepup  Lv 5")
	_row_buttons(s)[2].grab_focus()
	await get_tree().process_frame
	assert_str(s.card().header_text()).is_equal("Sprigling  Lv 7")
	_row_buttons(s)[1].grab_focus()
	await get_tree().process_frame
	assert_str(s.card().header_text()).is_equal("Emberkit  Lv 6")


func test_focusing_back_keeps_the_last_creature_on_the_card() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 6)
	var s := await _open()
	await get_tree().process_frame
	_row_buttons(s)[1].grab_focus()
	await get_tree().process_frame
	var back: Button = null
	for b in _row_buttons(s):
		if b.text == "Back":
			back = b
	back.grab_focus()
	await get_tree().process_frame
	assert_str(s.card().header_text()).is_equal("Emberkit  Lv 6")


func test_rows_have_a_sprite_instead_of_a_swatch_icon() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	var row: Button = _row_buttons(s)[0]
	var sprites := row.get_children().filter(func(n): return n is CreatureSpriteSlot)
	assert_int(sprites.size()).is_equal(1)
	assert_object(row.icon).is_null()


func test_a_party_of_twelve_fits_and_the_card_stays_on_screen() -> void:
	var db := DataRegistry.db
	var old: int = db.balance.party_size
	db.balance.party_size = 12
	for i in 12:
		Story.give_creature("tidepup", 8 + i)
	var s := await _open()
	await get_tree().process_frame
	ScreenFit.check(self, s, true)
	assert_bool(ScreenFit.VIEW.encloses(s.card().get_global_rect().grow(-0.5))).is_true()
	s.close()
	db.balance.party_size = old
