extends GdUnitTestSuite
## The stat radar's values, fixed scale, growth marks and geometry.

var db: Database
var _saved_rates: Dictionary


func before() -> void:
	db = DataRegistry.db
	_saved_rates = db.creature("tidepup").growth_rates.duplicate()


func after_test() -> void:
	db.creature("tidepup").growth_rates = _saved_rates.duplicate()


func _pup(level: int) -> CreatureInstance:
	return CreatureInstance.create(db, "tidepup", level)


func test_ceiling_matches_the_formula() -> void:
	assert_int(StatRadar.ceiling(db)).is_equal(Stats.stat_at(100, db.balance.level_cap))


func test_axes_follow_the_key_order_and_values() -> void:
	var c := _pup(20)
	c.training["satk"] = 7
	var axes := StatRadar.axes(db, c)
	assert_int(axes.size()).is_equal(7)
	for i: int in StatRadar.KEYS.size():
		assert_str(axes[i].key).is_equal(StatRadar.KEYS[i])
		assert_int(axes[i].value).is_equal(c.stat(db, StatRadar.KEYS[i]))
	assert_int(axes[2].value).is_equal(c.grown(db, "satk") + 7)


func test_fraction_is_value_over_ceiling() -> void:
	var c := _pup(40)
	for a: Dictionary in StatRadar.axes(db, c):
		assert_float(a.fraction).is_equal_approx(float(a.value) / float(StatRadar.ceiling(db)), 0.0001)


func test_fraction_clamps_at_the_rim() -> void:
	var c := _pup(db.balance.level_cap)
	c.training["patk"] = 500
	var a: Dictionary = StatRadar.axes(db, c)[0]
	assert_float(a.fraction).is_equal(1.0)
	assert_int(a.value).is_equal(c.stat(db, "patk"))
	assert_int(a.value).is_greater(StatRadar.ceiling(db))


func test_level_one_fraction_is_small_but_positive() -> void:
	for a: Dictionary in StatRadar.axes(db, _pup(1)):
		assert_float(a.fraction).is_greater(0.0)
		assert_float(a.fraction).is_less(0.2)


func test_marks_follow_growth_tier() -> void:
	db.creature("tidepup").growth_rates = {"patk": "fast", "pdef": "slow", "satk": "steady"}
	var axes := StatRadar.axes(db, _pup(30))
	assert_str(axes[0].mark).is_equal("▲")
	assert_str(axes[1].mark).is_equal("▼")
	assert_str(axes[2].mark).is_equal("")


func test_vertex_zero_points_up_and_one_is_clockwise() -> void:
	var top := StatRadar.vertex(0, 1.0, 10.0)
	assert_float(top.x).is_equal_approx(0.0, 0.001)
	assert_float(top.y).is_equal_approx(-10.0, 0.001)
	assert_float(StatRadar.vertex(1, 1.0, 10.0).x).is_greater(0.0)
	assert_vector(StatRadar.vertex(3, 0.0, 10.0)).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))


func test_draws_without_error() -> void:
	var r: StatRadar = StatRadar.new()
	add_child(auto_free(r))
	r.configure(db, _pup(1))
	await get_tree().process_frame
	r.configure(db, _pup(99))
	await get_tree().process_frame
	assert_vector(r.custom_minimum_size).is_equal(Vector2(180, 150))
