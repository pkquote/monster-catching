extends GdUnitTestSuite
## Tamers who spot the player along their line of sight.

var world: Overworld
var battles: Array = []
var _old_store: SaveStore
var _old_speed := ""


func before() -> void:
	_old_store = GameState.store
	GameState.store = SaveStore.new("user://test_tamers_saves")
	_old_speed = Settings.data.text_speed
	Settings.data.text_speed = "instant"


func after() -> void:
	GameState.store = _old_store
	Settings.data.text_speed = _old_speed
	Story.battle_override = Callable()


func before_test() -> void:
	Overworld.instant = true
	GameState.start_new_game("Ana")
	battles.clear()
	Story.battle_override = func(id: String) -> bool:
		battles.append(id)
		return true
	await _open()
	await world.change_map("test_b", "middle")


func after_test() -> void:
	world.free()
	Overworld.instant = false
	GameState.close_game()


func _open() -> void:
	world = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame


func _tamer(n: String) -> Tamer:
	return world.map.entities().get_node(n) as Tamer


func _enter(tile: Vector2i, facing := Vector2i.RIGHT) -> void:
	world.player.place(GameMap.centre_of(tile), facing)
	world.player.tile_entered.emit(tile)


func _finish_talk() -> void:
	for i in 300:
		if not world.is_locked():
			return
		if world.dialogue_box.menu.is_choosing():
			world.dialogue_box.menu.pick_label(world.dialogue_box.menu.labels()[0])
		else:
			world.dialogue_box.press_accept()
		await get_tree().process_frame


func test_tamer_spots_player_in_line() -> void:
	Story.give_creature("tidepup", 5)
	_enter(Vector2i(7, 4))
	await get_tree().process_frame
	assert_bool(world.is_locked()).is_true()
	await _finish_talk()
	var watcher := _tamer("Watcher")
	assert_object(watcher.tile()).is_equal(Vector2i(8, 4))  # walked up next to the player
	assert_object(world.player.facing).is_equal(Vector2i.RIGHT)
	assert_array(battles).is_equal(["scout_ana"])
	assert_bool(watcher.beaten()).is_true()


func test_beaten_tamer_is_in_the_battle_autosave() -> void:
	# The battle's autosave carries the prize money, so it must also carry "beaten":
	# closing the game straight after a win must not allow a second prize.
	Story.give_creature("tidepup", 5)
	var key := _tamer("Watcher").save_key()
	var saved: Array = []
	Story.battle_override = func(id: String) -> bool:
		await world.battles.after_battle(BattleSummary.of("won", [], id), true)
		var r := GameState.store.read(GameState.current_path)
		saved.append((r.save as SaveGame).story.is_done(key))
		return true
	_enter(Vector2i(7, 4))
	await _finish_talk()
	assert_array(saved).is_equal([true])


func test_wall_blocks_sight() -> void:
	Story.give_creature("tidepup", 5)
	_enter(Vector2i(5, 2))  # behind the sign
	await get_tree().process_frame
	assert_bool(world.is_locked()).is_false()
	_enter(Vector2i(7, 2))
	await get_tree().process_frame
	assert_bool(world.is_locked()).is_true()
	await _finish_talk()


func test_beaten_tamer_ignores_player() -> void:
	Story.give_creature("tidepup", 5)
	Story.mark_done(_tamer("Watcher").save_key())
	_enter(Vector2i(7, 4))
	await get_tree().process_frame
	assert_bool(world.is_locked()).is_false()
	world.player.place(GameMap.centre_of(Vector2i(9, 4)), Vector2i.RIGHT)
	world.interact()
	await get_tree().process_frame
	assert_str(world.dialogue_box.shown_text()).is_equal("You beat me fair.")
	await _finish_talk()
	assert_array(battles).is_empty()


func test_no_challenge_without_healthy_creatures() -> void:
	_enter(Vector2i(7, 4))
	await get_tree().process_frame
	assert_bool(world.is_locked()).is_false()
	world.player.place(GameMap.centre_of(Vector2i(9, 4)), Vector2i.RIGHT)
	world.interact()
	await get_tree().process_frame
	assert_str(world.dialogue_box.shown_text()).is_equal("Your team can't fight right now!")
	await _finish_talk()
	assert_array(battles).is_empty()


func test_resume_in_sight_waits_for_a_step() -> void:
	Story.give_creature("tidepup", 5)
	GameState.current.position = {"map": "test_b", "x": 272.0, "y": 144.0, "facing": "right"}  # (8, 4)
	world.free()
	await _open()
	assert_bool(world.is_locked()).is_false()
	_enter(Vector2i(7, 4))
	await get_tree().process_frame
	assert_bool(world.is_locked()).is_true()
	await _finish_talk()


func test_losing_and_waking_elsewhere_never_soft_locks() -> void:
	# A loss sends the player to another map, which frees the tamer mid-challenge.
	Story.give_creature("tidepup", 5)
	Story.battle_override = func(_id: String) -> bool:
		await world.change_map("test_a", "start")
		return false
	_enter(Vector2i(7, 4))
	await get_tree().process_frame
	await _finish_talk()
	assert_str(world.map.map_id()).is_equal("test_a")
	assert_bool(world.is_locked()).is_false()
