extends GdUnitTestSuite
## Grass encounters on the overworld, encounter areas, walking energy.

var world: Overworld
var started: Array = []
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("encounters", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")
	started.clear()
	world.battles.wild_override = func(table_id: String): started.append(table_id)
	# Every grass tile rolls an encounter, so the tests are deterministic.
	var always := FixtureDB.build({"overworld": {"walk_speed": 4.0, "run_speed": 7.0, "encounter_rate": 1.0,
		"encounter_grace_tiles": 4, "walk_energy_tiles": 8, "defeat_money_fraction": 0.1, "sell_fraction": 0.5}})
	world.roller = EncounterRoller.new(always.balance, world.rng)


func after_test() -> void:
	WorldTest.close(world)


func _enter(tile: Vector2i) -> void:
	world.player.place(GameMap.centre_of(tile), Vector2i.DOWN)
	world.player.tile_entered.emit(tile)


func test_area_overrides_default() -> void:
	assert_str(world.map.encounter_at(Vector2i(2, 2))).is_equal("route_01_deep_grass")
	assert_str(world.map.encounter_at(Vector2i(6, 6))).is_equal("route_01_grass")


func test_grass_starts_a_wild_battle() -> void:
	Story.give_creature("tidepup", 5).passive = ""  # a rolled Undertow would lower the rate
	_enter(Vector2i(6, 6))
	assert_array(started).is_equal(["route_01_grass"])
	_enter(Vector2i(5, 6))  # plain grass: nothing
	_enter(Vector2i(2, 3))
	assert_array(started).is_equal(["route_01_grass", "route_01_deep_grass"])


func test_indoor_never_rolls() -> void:
	Story.give_creature("tidepup", 5)
	world.map.indoor = true
	_enter(Vector2i(6, 6))
	assert_array(started).is_empty()


func test_no_healthy_creatures_no_roll() -> void:
	_enter(Vector2i(6, 6))
	var c := Story.give_creature("tidepup", 5)
	c.hp = 0
	_enter(Vector2i(7, 6))
	assert_array(started).is_empty()


func test_walking_restores_energy() -> void:
	var c := Story.give_creature("tidepup", 5)
	c.energy = 0
	for i in 8:
		_enter(Vector2i(1 + i % 2, 5))  # plain grass, alternating tiles
	assert_int(c.energy).is_equal(1)


func test_lead_passive_scales_the_encounter_rate() -> void:
	Story.give_creature("tidepup", 5).passive = "undertow"  # encounters x0.8
	Story.give_creature("emberkit", 5).passive = ""
	world.rng.seed = 5
	for i in 40:
		_enter(Vector2i(6, 6))
	assert_int(started.size()).is_greater(0)
	assert_int(started.size()).is_less(40)


func test_non_lead_passive_leaves_the_rate_alone() -> void:
	Story.give_creature("emberkit", 5).passive = ""
	Story.give_creature("tidepup", 5).passive = "undertow"
	for i in 40:
		_enter(Vector2i(6, 6))
	assert_int(started.size()).is_equal(40)
