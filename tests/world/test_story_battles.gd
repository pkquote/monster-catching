extends GdUnitTestSuite
## What the overworld does after a battle, and Story.start_battle's test hook.

var world: Overworld
var _suite: Dictionary




func before() -> void:
	_suite = WorldTest.begin_suite("story_battles", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	world = await WorldTest.open(self, "test_b", "middle")
	var c := Story.give_creature("tidepup", 5)
	c.hp = 0
	GameState.current.money = 1000


func after_test() -> void:
	WorldTest.close(world)


func test_story_battle_without_defeat_rules() -> void:
	var won := await world.battles.after_battle(BattleSummary.of("lost"), false)
	assert_bool(won).is_false()
	assert_int(GameState.current.party[0].hp).is_greater(0)
	assert_int(GameState.current.money).is_equal(1000)
	assert_str(world.map.map_id()).is_equal("test_b")


func test_loss_with_defeat_rules_respawns() -> void:
	Settings.data.text_speed = "instant"
	var result: Array = []
	var run := func(): result.append(await world.battles.after_battle(BattleSummary.of("lost"), true))
	run.call()
	for i in 100:
		if not result.is_empty():
			break
		world.dialogue_box.press_accept()
		await get_tree().process_frame
	assert_array(result).is_equal([false])
	assert_int(GameState.current.money).is_equal(900)
	assert_int(GameState.current.party[0].hp).is_greater(0)
	assert_str(world.map.map_id()).is_equal(Overworld.new_game_map())
	assert_bool(world.is_locked()).is_false()


func test_win_counts_and_capture_counts() -> void:
	assert_bool(await world.battles.after_battle(BattleSummary.of("won"), true)).is_true()
	assert_bool(await world.battles.after_battle(BattleSummary.of("captured"), true)).is_true()
	assert_bool(await world.battles.after_battle(BattleSummary.of("fled"), true)).is_false()
	assert_str(world.map.map_id()).is_equal("test_b")


func test_battle_override_hook() -> void:
	Story.battle_override = func(_id: String) -> bool: return true
	assert_bool(await Story.start_battle("scout_ana")).is_true()
	assert_bool(Story.last_battle_won()).is_true()
	Story.battle_override = func(_id: String) -> bool: return false
	assert_bool(await Story.start_battle("scout_ana")).is_false()
	assert_bool(Story.last_battle_won()).is_false()
	Story.battle_override = Callable()


func test_losing_inside_a_conversation_still_explains() -> void:
	Settings.data.text_speed = "instant"
	world.say("res://tests/fixtures/test_talk.dialogue", "hello")  # a tamer's script is running
	await get_tree().process_frame
	var run := func(): await world.battles.after_battle(BattleSummary.of("lost"), true)
	run.call()
	var shown := ""
	for i in 60:
		if world.dialogue_box.shown_text().begins_with("You hurried back"):
			shown = world.dialogue_box.shown_text()
			break
		await get_tree().process_frame
	assert_str(shown).contains("You dropped 100 money")


func test_loss_wakes_at_start_when_heal_map_is_gone() -> void:
	Settings.data.text_speed = "instant"
	GameState.current.story.last_heal = {"map": "no_such_map", "spawn": "heal"}
	var result: Array = []
	var run := func(): result.append(await world.battles.after_battle(BattleSummary.of("lost"), true))
	run.call()
	for i in 100:
		if not result.is_empty():
			break
		world.dialogue_box.press_accept()
		await get_tree().process_frame
	assert_str(world.map.map_id()).is_equal(Overworld.new_game_map())
	assert_object(world.player.feet_tile()).is_equal(world.map.spawn(SaveGame.NEW_GAME_SPAWN).tile())
