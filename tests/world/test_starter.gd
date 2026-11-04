extends GdUnitTestSuite
## New game: start at home, the starter choice in the lab, the lab rival battle,
## and the town exit blocked until you have a creature.

const LAB := "res://dialogue/town_01/story.dialogue"

var world: Overworld
var battles: Array = []
var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("starter")


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	battles.clear()
	Story.battle_override = func(id: String) -> bool:
		battles.append(id)
		return true
	world = await WorldTest.open(self)


func after_test() -> void:
	WorldTest.close(world)


## Presses Accept until the conversation ends, picking responses starting with `pick`.
func _talk(pick := "") -> void:
	for i in 400:
		if not world.is_talking():
			return
		var menu := world.dialogue_box.menu
		if menu.is_choosing():
			menu.pick_label(pick if pick != "" else menu.labels()[0])
		else:
			world.dialogue_box.press_accept()
		await get_tree().process_frame


func test_new_game_starts_at_home() -> void:
	assert_str(world.map.map_id()).is_equal("town_01_home")
	assert_object(world.player.feet_tile()).is_equal(world.map.spawn("start").tile())


func test_choosing_a_starter() -> void:
	await world.change_map("town_01_lab", "entry")
	world.say(LAB, "choose")
	await get_tree().process_frame
	await _talk("Emberkit")
	var party := GameState.current.party
	assert_int(party.size()).is_equal(1)
	assert_str(party[0].species).is_equal("emberkit")
	assert_int(party[0].level).is_equal(5)
	assert_int(party[0].bond).is_equal(DataRegistry.db.balance.bond_cfg.starter)
	assert_int(GameState.current.inventory.get("lure_cage", 0)).is_equal(5)
	assert_bool(Story.flag("got_starter")).is_true()
	assert_array(battles).is_equal(["rival_lab"])
	assert_dict(Story.last_battle_request).is_equal({"tamer_id": "rival_lab", "defeat_rules": false})


func test_exit_blocked_without_starter() -> void:
	await world.change_map("town_01", "from_home")
	var gate := world.map.piece_at(Vector2i(15, 1))
	assert_object(gate).is_instanceof(Trigger)
	world.player.place(GameMap.centre_of(Vector2i(15, 1)), Vector2i.UP)
	gate.on_enter(world)
	await get_tree().process_frame
	assert_bool(world.is_talking()).is_true()
	await _talk()
	assert_object(world.player.feet_tile()).is_equal(Vector2i(15, 3))
	Story.set_flag("got_starter")
	assert_bool((gate as Trigger).can_fire()).is_false()


func test_professor_leaves_town_after_the_intro() -> void:
	await world.change_map("town_01", "from_home")
	assert_object(_actor("prof")).is_not_null()
	Story.set_flag("met_prof")
	await world.change_map("town_01_home", "from_town")
	await world.change_map("town_01", "from_home")
	assert_object(_actor("prof")).is_null()


func _actor(id: String) -> Npc:
	for p in world.map.pieces():
		if p is Npc and (p as Npc).actor_id == id:
			return p
	return null


func test_starter_choice_only_once() -> void:
	await world.change_map("town_01_lab", "entry")
	world.say(LAB, "choose")
	await get_tree().process_frame
	await _talk("Emberkit")
	world.say(LAB, "choose")  # e.g. the intro fired late and jumped here again
	await get_tree().process_frame
	await _talk("Tidepup")
	assert_int(GameState.current.party.size()).is_equal(1)
	assert_int(GameState.current.inventory.get("lure_cage", 0)).is_equal(5)
	assert_array(battles).is_equal(["rival_lab"])


func test_intro_never_fires_after_the_starter() -> void:
	await world.change_map("town_01", "from_home")
	var intro := world.map.entities().get_node("Intro") as Trigger
	Story.set_flag("got_starter")  # took the starter without passing the intro
	assert_bool(intro.can_fire()).is_false()


func test_exit_blocked_when_walking_along_row_1() -> void:
	await world.change_map("town_01", "from_home")
	world.player.place(GameMap.centre_of(Vector2i(13, 1)), Vector2i.RIGHT)
	for i in 40:
		world.player.step(Vector2.RIGHT, false, 1.0 / 60.0)
		if world.is_locked():
			break
	await get_tree().process_frame
	assert_bool(world.is_talking()).is_true()
	await _talk()
	assert_str(world.map.map_id()).is_equal("town_01")
