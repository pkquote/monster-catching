extends GdUnitTestSuite
## Player movement: speed, diagonals, running, facing, walls and tile_entered.

const DT := 1.0 / 60.0

var map: GameMap
var player: Player


func before_test() -> void:
	map = load("res://game/maps/test_a.tscn").instantiate()
	add_child(map)
	player = load("res://game/overworld/player.tscn").instantiate()
	map.entities().add_child(player)
	player.place(GameMap.centre_of(Vector2i(2, 2)), Vector2i.DOWN)
	await get_tree().physics_frame


func after_test() -> void:
	map.free()  # frees the player too


func _walk(dir: Vector2, seconds: float, run := false) -> void:
	for i in roundi(seconds / DT):
		player.step(dir, run, DT)


func _walk_speed() -> float:
	return float(DataRegistry.db.balance.overworld_cfg.walk_speed) * GameMap.TILE


func test_diagonal_is_normalised() -> void:
	var start := player.position
	_walk(Vector2(1, 1), 0.5)
	assert_float((player.position - start).length()).is_equal_approx(_walk_speed() * 0.5, 1.5)


func test_run_is_faster() -> void:
	var start := player.position
	_walk(Vector2.RIGHT, 0.25, true)
	var run_dist := (player.position - start).length()
	assert_float(run_dist).is_equal_approx(float(DataRegistry.db.balance.overworld_cfg.run_speed) * GameMap.TILE * 0.25, 1.5)
	assert_float(run_dist).is_greater(_walk_speed() * 0.25)


func test_facing_follows_last_direction() -> void:
	player.press_dir("move_right", true)
	assert_object(player.facing).is_equal(Vector2i.RIGHT)
	player.press_dir("move_up", true)
	assert_object(player.facing).is_equal(Vector2i.UP)
	player.press_dir("move_up", false)
	assert_object(player.facing).is_equal(Vector2i.RIGHT)
	player.press_dir("move_right", false)
	assert_object(player.facing).is_equal(Vector2i.RIGHT)  # keeps the last facing


func test_walls_block() -> void:
	_walk(Vector2.LEFT, 2.0)
	assert_int(player.feet_tile().x).is_equal(1)  # the wall is column 0
	assert_bool(map.is_solid(player.feet_tile())).is_false()


func test_tile_entered_once_per_tile() -> void:
	var seen: Array = []
	player.tile_entered.connect(func(t): seen.append(t))
	_walk(Vector2.ZERO, 0.5)
	assert_array(seen).is_empty()
	# 3 tiles to the right at walk speed (4 tiles/s) takes 0.75 s.
	_walk(Vector2.RIGHT, 0.75)
	assert_array(seen).is_equal([Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)])


func test_place_does_not_emit() -> void:
	var seen: Array = []
	player.tile_entered.connect(func(t): seen.append(t))
	player.place(GameMap.centre_of(Vector2i(5, 3)), Vector2i.UP)
	assert_array(seen).is_empty()
	assert_object(player.feet_tile()).is_equal(Vector2i(5, 3))
	assert_object(player.front_tile()).is_equal(Vector2i(5, 2))


func test_locked_player_ignores_input_steps() -> void:
	player.locked = true
	var start := player.position
	player.physics_step_from_input(DT * 30)
	assert_object(player.position).is_equal(start)


# --- Corner slipping ----------------------------------------------------------------
# test_a's bottom wall (row 5) has a doorway at column 4 (x 128..160). The body is 20px wide.

func test_slips_through_a_doorway_when_nearly_lined_up() -> void:
	player.place(Vector2(4 * 32 + 16 + 7, 4 * 32 + 16), Vector2i.DOWN)  # body pokes 1px past the gap
	await get_tree().physics_frame
	_walk(Vector2.DOWN, 0.6)
	assert_int(player.feet_tile().y).is_equal(5)


func test_slips_from_the_other_side_too() -> void:
	player.place(Vector2(4 * 32 + 16 - 13, 4 * 32 + 16), Vector2i.DOWN)  # 7px past the left edge
	await get_tree().physics_frame
	_walk(Vector2.DOWN, 0.6)
	assert_int(player.feet_tile().y).is_equal(5)


func test_no_slip_when_far_off_the_gap() -> void:
	var x := 4 * 32 + 16 + 22.0  # would need a 16px nudge
	player.place(Vector2(x, 4 * 32 + 16), Vector2i.DOWN)
	await get_tree().physics_frame
	_walk(Vector2.DOWN, 0.6)
	assert_int(player.feet_tile().y).is_equal(4)
	assert_float(player.position.x).is_equal_approx(x, 0.01)


func test_no_slip_along_a_solid_wall() -> void:
	player.place(GameMap.centre_of(Vector2i(2, 4)), Vector2i.DOWN)
	await get_tree().physics_frame
	_walk(Vector2.DOWN, 0.6)
	assert_float(player.position.x).is_equal_approx(GameMap.centre_of(Vector2i(2, 4)).x, 0.01)
