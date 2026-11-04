class_name WorldTest
extends RefCounted
## Shared setup for suites that need the overworld or a playthrough:
##
##   var _state: Dictionary
##   var world: Overworld
##
##   func before() -> void:
##       _state = WorldTest.begin_suite("pieces")      # throwaway saves, instant text
##   func after() -> void:
##       WorldTest.end_suite(_state)                   # puts it all back, deletes the saves
##   func before_test() -> void:
##       world = await WorldTest.open(self, "test_a", "start")
##   func after_test() -> void:
##       WorldTest.close(world)
##
## Saves go to user://test_<name>_saves, which end_suite deletes.


## Points GameState at a throwaway save folder and (unless told otherwise) makes text
## appear instantly. Returns what end_suite needs to restore.
static func begin_suite(name: String, instant_text := true) -> Dictionary:
	var state := {"store": GameState.store, "text_speed": Settings.data.text_speed,
		"root": "user://test_%s_saves" % name}
	_delete_dir(state.root)
	GameState.store = SaveStore.new(state.root)
	if instant_text:
		Settings.data.text_speed = "instant"
	return state


## Undoes begin_suite: closes any game, restores the save store and text speed,
## clears the Story battle hook, and deletes the throwaway saves.
static func end_suite(state: Dictionary) -> void:
	GameState.close_game()
	GameState.store = state.store
	Settings.data.text_speed = state.text_speed
	Story.battle_override = Callable()
	_delete_dir(state.root)


## What open() does with the playthrough first.
const NEW_GAME := "new"    ## start a fresh game
const KEEP_GAME := "keep"  ## use the game the test already set up
const NO_GAME := "none"    ## close any game (debug-room behaviour)


## Opens the overworld under `parent` in instant mode, after starting / keeping /
## closing a game per `game`, and moves to `map`/`spawn` when given. Awaitable.
static func open(parent: Node, map := "", spawn := "", game := NEW_GAME) -> Overworld:
	Overworld.instant = true
	match game:
		NEW_GAME:
			GameState.start_new_game("Ana")
		NO_GAME:
			GameState.close_game()
	var world: Overworld = load("res://game/overworld/overworld.tscn").instantiate()
	parent.add_child(world)
	await parent.get_tree().process_frame
	if map != "":
		await world.change_map(map, spawn)
	return world


## Frees the overworld (directly, so no orphans are reported), leaves instant mode
## and closes the game.
static func close(world: Overworld) -> void:
	if is_instance_valid(world):
		world.free()
	Overworld.instant = false
	GameState.close_game()


## The first child of `root` that is an instance of `cls`, or null.
static func find_screen(root: Node, cls: Script) -> Node:
	for n in root.get_children():
		if is_instance_of(n, cls):
			return n
	return null


## Presses Accept (or picks the first answer) until the conversation is over.
static func finish_talk(world: Overworld, max_frames := 300) -> void:
	for i in max_frames:
		if not world.is_talking():
			return
		if world.dialogue_box.menu.is_choosing():
			world.dialogue_box.menu.pick_label(world.dialogue_box.menu.labels()[0])
		else:
			world.dialogue_box.press_accept()
		await world.get_tree().process_frame


static func _delete_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_delete_dir(path.path_join(sub))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
