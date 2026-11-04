extends GdUnitTestSuite
## The storage screen: deposit, withdraw, swap, refusals, paging and the box piece.

var world: Overworld
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("storage_screen", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")


func after_test() -> void:
	WorldTest.close(world)


func _screen() -> StorageScreen:
	return WorldTest.find_screen(world, StorageScreen) as StorageScreen


func _open() -> StorageScreen:
	StorageScreen.run(world)
	await get_tree().process_frame
	return _screen()


func _pick(s: StorageScreen, prefix: String) -> void:
	assert_bool(s.menu.pick_label(prefix)).is_true()
	await get_tree().process_frame


func test_deposit_and_withdraw() -> void:
	var save := GameState.current
	var a := Story.give_creature("tidepup", 5)
	var b := Story.give_creature("emberkit", 5)
	var s := await _open()
	await _pick(s, "Party: Emberkit")
	await _pick(s, "Deposit")
	assert_int(save.party.size()).is_equal(1)
	assert_object(save.storage[0]).is_same(b)
	assert_str(s.title_text()).is_equal("Box — page 1 of 1")
	await _pick(s, "Box: Emberkit")
	await _pick(s, "Withdraw")
	assert_int(save.storage.size()).is_equal(0)
	assert_object(save.party[1]).is_same(b)
	assert_object(save.party[0]).is_same(a)


func test_swap() -> void:
	var save := GameState.current
	var a := Story.give_creature("tidepup", 5)
	var b := Story.give_creature("emberkit", 5)
	save.party.erase(b)
	save.storage.append(b)
	var s := await _open()
	await _pick(s, "Party: Tidepup")
	await _pick(s, "Swap")
	await _pick(s, "Box: Emberkit")
	assert_object(save.party[0]).is_same(b)
	assert_object(save.storage[0]).is_same(a)


func test_refusal_messages() -> void:
	var save := GameState.current
	Story.give_creature("tidepup", 5)
	var s := await _open()
	await _pick(s, "Party: Tidepup")
	await _pick(s, "Deposit")
	assert_str(s.page_text()).is_equal("Keep at least one creature that can fight.")
	assert_int(save.party.size()).is_equal(1)
	s.close()
	for i in 5:
		Story.give_creature("tidepup", 5)
	save.storage.append(CreatureInstance.create(DataRegistry.db, "emberkit", 5))
	s = await _open()
	await _pick(s, "Box: Emberkit")
	await _pick(s, "Withdraw")
	assert_str(s.page_text()).is_equal("Your party is full.")
	assert_int(save.storage.size()).is_equal(1)


func test_empty_box_text() -> void:
	Story.give_creature("tidepup", 5)
	var s := await _open()
	assert_str(s.page_text()).is_equal("The box is empty.")


func test_paging_12_in_box() -> void:
	var save := GameState.current
	for i in 18:
		Story.give_creature("tidepup", 5)
	assert_int(save.party.size()).is_equal(6)
	assert_int(save.storage.size()).is_equal(12)
	var s := await _open()
	assert_str(s.title_text()).is_equal("Box — page 1 of 2")
	assert_int(_count(s, "Box: ")).is_equal(10)
	assert_bool(s.menu.labels().has("Previous page")).is_false()
	await _pick(s, "Next page")
	assert_str(s.title_text()).is_equal("Box — page 2 of 2")
	assert_int(s.page).is_equal(1)
	assert_int(_count(s, "Box: ")).is_equal(2)
	assert_bool(s.menu.labels().has("Next page")).is_false()
	await _pick(s, "Previous page")
	assert_int(s.page).is_equal(0)


func test_full_screen_fits() -> void:
	for i in 18:
		Story.give_creature("tidepup", 5)
	var s := await _open()
	await get_tree().process_frame
	ScreenFit.check(self, s)
	await _pick(s, "Next page")
	await get_tree().process_frame
	ScreenFit.check(self, s)
	await _pick(s, "Party: ")
	await get_tree().process_frame
	ScreenFit.check(self, s)


func _count(s: StorageScreen, prefix: String) -> int:
	var n := 0
	for l in s.menu.labels():
		if l.begins_with(prefix):
			n += 1
	return n


func _place_box(tile: Vector2i) -> StorageBox:
	var box: StorageBox = load("res://game/overworld/pieces/storage_box.tscn").instantiate()
	world.map.entities().add_child(box)
	box.position = GameMap.centre_of(tile)
	return box


func test_storage_box_works_in_unsafe_zone() -> void:
	Story.give_creature("tidepup", 5)
	Story.give_creature("emberkit", 5)
	_place_box(Vector2i(2, 2))
	world.player.place(GameMap.centre_of(Vector2i(2, 3)), Vector2i.UP)
	assert_bool(world.is_safe_here()).is_false()
	world.interact()
	await get_tree().process_frame
	assert_object(_screen()).is_not_null()
	assert_bool(world.is_locked()).is_true()


func test_storage_box_refuses_last_healthy() -> void:
	var save := GameState.current
	var a := Story.give_creature("tidepup", 5)
	var b := Story.give_creature("emberkit", 5)
	a.hp = 0
	_place_box(Vector2i(6, 4))
	world.player.place(GameMap.centre_of(Vector2i(6, 5)), Vector2i.UP)
	world.interact()
	await get_tree().process_frame
	var s := _screen()
	assert_object(s).is_not_null()
	await _pick(s, "Party: Emberkit")
	await _pick(s, "Deposit")
	assert_str(s.page_text()).is_equal("Keep at least one creature that can fight.")
	assert_int(save.party.size()).is_equal(2)
	assert_object(save.party[1]).is_same(b)


func test_swap_from_party_can_page_the_box() -> void:
	var save := GameState.current
	for i in 17:
		Story.give_creature("tidepup", 5)
	var far := Story.give_creature("emberkit", 5)  # 18th: the box's 12th, on page 2
	assert_object(save.storage[11]).is_same(far)
	var s := await _open()
	await _pick(s, "Party: Tidepup")
	await _pick(s, "Swap")
	assert_bool(s.menu.labels().has("Next page")).is_true()
	await _pick(s, "Next page")
	await _pick(s, "Box: Emberkit")
	assert_object(save.party[0]).is_same(far)
