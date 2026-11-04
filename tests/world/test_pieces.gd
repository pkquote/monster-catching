extends GdUnitTestSuite
## Talking to NPCs, picking up visible and hidden items, signs and triggers.
## Uses the pieces placed on the test maps (tools/build_maps.gd).

var world: Overworld
var _old_store: SaveStore
var _old_speed := ""


func before() -> void:
	_old_store = GameState.store
	GameState.store = SaveStore.new("user://test_pieces_saves")
	_old_speed = Settings.data.text_speed
	Settings.data.text_speed = "instant"


func after() -> void:
	GameState.store = _old_store
	Settings.data.text_speed = _old_speed


func before_test() -> void:
	Overworld.instant = true
	GameState.start_new_game("Ana")
	world = load("res://game/overworld/overworld.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await world.change_map("test_a", "start")


func after_test() -> void:
	world.free()
	Overworld.instant = false
	GameState.close_game()


func _stand(tile: Vector2i, facing: Vector2i) -> void:
	world.player.place(GameMap.centre_of(tile), facing)


## Presses Accept / first response until no conversation is running.
func _finish_talk() -> void:
	for i in 200:
		if not world.is_talking():
			return
		if world.dialogue_box.menu.is_choosing():
			world.dialogue_box.menu.pick_label(world.dialogue_box.menu.labels()[0])
		else:
			world.dialogue_box.press_accept()
		await get_tree().process_frame


func _walk_onto(tile: Vector2i, from_dir: Vector2i) -> void:
	_stand(tile - from_dir, from_dir)
	for i in 30:
		world.player.step(Vector2(from_dir), false, 1.0 / 60.0)
		if world.player.feet_tile() == tile:
			break
	await get_tree().process_frame


func test_pickup_collected_once() -> void:
	_stand(Vector2i(1, 3), Vector2i.DOWN)
	world.interact()
	await get_tree().process_frame
	assert_str(world.dialogue_box.shown_text()).is_equal("Found a Salve!")
	await _finish_talk()
	assert_int(GameState.current.inventory.get("salve", 0)).is_equal(1)
	assert_object(world.map.piece_at(Vector2i(1, 4))).is_null()
	await world.change_map("test_b", "middle")
	await world.change_map("test_a", "start")
	assert_object(world.map.piece_at(Vector2i(1, 4))).is_null()
	_stand(Vector2i(1, 3), Vector2i.DOWN)
	world.interact()
	await _finish_talk()
	assert_int(GameState.current.inventory.get("salve", 0)).is_equal(1)


func test_hidden_item_found_by_facing() -> void:
	_stand(Vector2i(5, 4), Vector2i.LEFT)
	world.interact()
	assert_bool(world.is_talking()).is_false()
	_stand(Vector2i(5, 4), Vector2i.RIGHT)
	world.interact()
	await _finish_talk()
	assert_int(GameState.current.inventory.get("tonic", 0)).is_equal(1)
	world.interact()
	await _finish_talk()
	assert_int(GameState.current.inventory.get("tonic", 0)).is_equal(1)


func test_npc_turns_to_player_and_talks() -> void:
	var npc := world.map.piece_at(Vector2i(6, 1)) as Npc
	assert_object(npc).is_not_null()
	assert_bool(world.map.is_solid(Vector2i(6, 1))).is_true()
	_stand(Vector2i(5, 1), Vector2i.RIGHT)
	world.interact()
	await get_tree().process_frame
	assert_object(npc.facing).is_equal(Vector2i.LEFT)
	assert_bool(world.is_talking()).is_true()
	await _finish_talk()
	assert_bool(Story.flag("talked")).is_true()


func test_sign_shows_text() -> void:
	await world.change_map("test_b", "middle")
	_stand(Vector2i(6, 3), Vector2i.UP)
	world.interact()
	await get_tree().process_frame
	assert_str(world.dialogue_box.shown_text()).is_equal("Test field. Mind the grass.")
	await _finish_talk()


func test_trigger_flags_and_once() -> void:
	await world.change_map("test_b", "middle")
	Story.set_flag("gate_off")
	await _walk_onto(Vector2i(8, 5), Vector2i.RIGHT)
	assert_bool(world.is_talking()).is_false()
	Story.set_flag("gate_off", false)
	await _walk_onto(Vector2i(9, 5), Vector2i.RIGHT)  # the trigger is 2 tiles wide
	assert_bool(world.is_talking()).is_true()
	await _finish_talk()
	assert_bool(Story.flag("talked")).is_true()
	Story.set_flag("talked", false)
	await world.change_map("test_a", "start")
	await world.change_map("test_b", "middle")
	await _walk_onto(Vector2i(8, 5), Vector2i.RIGHT)
	assert_bool(world.is_talking()).is_false()
	assert_bool(Story.flag("talked")).is_false()


func test_accept_while_locked_does_nothing() -> void:
	_stand(Vector2i(5, 1), Vector2i.RIGHT)
	world.lock("menu")
	world.interact()
	assert_bool(world.is_talking()).is_false()
	world.unlock("menu")


func test_wander_stays_in_range() -> void:
	await world.change_map("test_b", "middle")
	var npc: Npc = null
	for p in world.map.pieces():
		if p is Npc and (p as Npc).wander_tiles > 0:
			npc = p
	assert_object(npc).is_not_null()
	var home := npc.home_tile()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 200:
		npc.wander_tick(world, rng)
		var t := npc.tile()
		assert_int(maxi(absi(t.x - home.x), absi(t.y - home.y))).is_less_equal(npc.wander_tiles)
		assert_bool(world.map.is_solid(t, npc)).is_false()
		assert_bool(t == world.player.feet_tile()).is_false()


func test_wander_avoids_every_tile_the_player_overlaps() -> void:
	await world.change_map("test_b", "middle")
	var npc := world.map.entities().get_node("Walker") as Npc  # home (10, 6)
	# Feet on (8, 6), but the body pokes 2px into (9, 6).
	world.player.place(Vector2(8 * 32 + 24, 6 * 32 + 16), Vector2i.RIGHT)
	assert_object(world.player.feet_tile()).is_equal(Vector2i(8, 6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var visited := {}
	for i in 300:
		npc.wander_tick(world, rng)
		visited[npc.tile()] = true
	assert_bool(visited.has(Vector2i(9, 6))).is_false()
	assert_bool(visited.has(Vector2i(8, 6))).is_false()


func test_interact_after_walking_down_into_an_npc() -> void:
	await world.change_map("test_b", "middle")
	world.player.place(GameMap.centre_of(Vector2i(10, 5)), Vector2i.DOWN)  # the Walker stands at (10, 6)
	await get_tree().physics_frame
	for i in 30:
		world.player.step(Vector2.DOWN, false, 1.0 / 60.0)
	world.interact()
	await get_tree().process_frame
	assert_bool(world.is_talking()).is_true()
	await _finish_talk()


func test_is_safe_here_follows_unsafe_area() -> void:
	await world.change_map("test_b", "middle")
	_stand(Vector2i(2, 2), Vector2i.DOWN)
	assert_bool(world.is_safe_here()).is_false()
	_stand(Vector2i(6, 4), Vector2i.DOWN)
	assert_bool(world.is_safe_here()).is_true()
	# The marker never catches interaction.
	assert_object(world.map.piece_at(Vector2i(2, 2))).is_null()
