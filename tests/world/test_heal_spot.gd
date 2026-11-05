extends GdUnitTestSuite
## Resting at the heal centre: full heal, the "rested" Bond change, wake-up point.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("heal")


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "town_01_center", "heal")


func after_test() -> void:
	WorldTest.close(world)


func _hurt_creature() -> CreatureInstance:
	var c := Story.give_creature("tidepup", 5)
	c.hp = 1
	c.energy = 0
	c.status = "burn"
	c.bond = 0
	return c


func _talk(pick: String) -> void:
	for i in 300:
		if not world.is_talking():
			return
		var menu := world.dialogue_box.menu
		if menu.is_choosing():
			menu.pick_label(pick)
		else:
			world.dialogue_box.press_accept()
		await get_tree().process_frame


func test_resting_heals_and_sets_wake_up_point() -> void:
	var c := _hurt_creature()
	world.player.place(GameMap.centre_of(Vector2i(3, 3)), Vector2i.UP)
	world.interact()
	await get_tree().process_frame
	assert_bool(world.is_talking()).is_true()
	await _talk("Yes")
	assert_int(c.hp).is_equal(c.max_hp(DataRegistry.db))
	assert_int(c.energy).is_equal(c.max_energy(DataRegistry.db))
	assert_str(c.status).is_equal("")
	assert_int(c.bond).is_equal(int(DataRegistry.db.balance.bond_cfg.changes.rested))
	assert_dict(GameState.current.story.last_heal).is_equal({"map": "town_01_center", "spawn": "heal"})


func test_lead_passive_scales_rest_bond() -> void:
	var c := Story.give_creature("sprigling", 5)
	c.passive = "photosynth"  # Bond gains x1.25
	c.bond = 0
	world.player.place(GameMap.centre_of(Vector2i(3, 3)), Vector2i.UP)
	world.interact()
	await get_tree().process_frame
	await _talk("Yes")
	assert_int(c.bond).is_equal(roundi(int(DataRegistry.db.balance.bond_cfg.changes.rested) * 1.25))


func test_saying_no_changes_nothing() -> void:
	var c := _hurt_creature()
	world.player.place(GameMap.centre_of(Vector2i(3, 3)), Vector2i.UP)
	world.interact()
	await get_tree().process_frame
	await _talk("No")
	assert_int(c.hp).is_equal(1)
	assert_dict(GameState.current.story.last_heal).is_empty()
