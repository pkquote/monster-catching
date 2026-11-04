extends SceneTree
## Drives the real game in a window and saves PNG screenshots.
##
##   godot --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- [options]
##
## Options (after the `--`):
##   --mode=frontend      (default) full front-end tour: splash -> title -> new game -> world ->
##                        save -> quit -> load browser -> settings tabs -> rebind -> resume.
##                        Checks expectations and exits 1 if any fail.
##   --mode=scene         open one scene, wait, screenshot. Use with --scene / --frames.
##   --scene=res://...    scene for --mode=scene (default: the project's main scene)
##   --frames=N           frames to wait before the screenshot in scene mode (default 60)
##   --out=<dir>          screenshot folder (default user://run_shots, printed on exit)
##
## The tour uses an isolated save folder (user://run_saves, deleted afterwards) and never
## writes settings.json, so the player's real saves and settings are untouched.

const RUN_SAVES := "user://run_saves"

var _opts := {"mode": "frontend", "scene": "", "frames": "60", "out": "user://run_shots"}
var _out := ""
var _failures := 0
var _log_lines := PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1]
	_out = ProjectSettings.globalize_path(_opts.out)
	DirAccess.make_dir_recursive_absolute(_out)
	match _opts.mode:
		"scene":
			_run_scene()
		"battle":
			_run_battle()
		_:
			_run_frontend()


# --- Modes ---------------------------------------------------------------------------

func _run_scene() -> void:
	await process_frame
	var path: String = _opts.scene if _opts.scene != "" else ProjectSettings.get_setting("application/run/main_scene")
	change_scene_to_file(path)
	await _frames(int(_opts.frames))
	await shot(path.get_file().get_basename())
	_finish()


func _run_frontend() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var router := root.get_node("SceneRouter")
	var settings := root.get_node("Settings")
	gs.store = SaveStore.new(RUN_SAVES)
	_clear(RUN_SAVES)

	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(25)
	await shot("01_splash_credit")
	await _frames(75)
	await shot("02_splash_title")
	await wait_scene("TitleMenu", 300)
	await _frames(20)
	await shot("03_title_no_saves")

	# Real keyboard input: focus starts on New Game; Z is the default Accept key.
	await key(KEY_Z)
	await wait_scene("NewGame", 120)
	await _frames(15)
	await shot("04_new_game_empty")
	expect(current_scene.start_button.disabled, "Start is disabled before typing a name")
	await type_text("Ana")
	await shot("05_new_game_typed")
	expect(not current_scene.start_button.disabled, "Start is enabled after typing a name")
	await key(KEY_ENTER)  # LineEdit submit starts the game
	await wait_scene("PlaceholderWorld", 120)
	await _frames(40)
	await shot("06_world_autosaved")
	press("Save game")
	await _frames(5)
	await shot("07_world_saved")
	expect(gs.store.list().size() == 3, "3 saves exist (first save, autosave, manual save)")

	press("Quit to title")
	await wait_scene("TitleMenu", 120)
	await _frames(20)
	await shot("08_title_with_resume")
	expect(gs.resume_path() != "", "Resume target is set")

	press("Load Game")
	await wait_scene("LoadMenu", 120)
	await _frames(20)
	await shot("09_load_menu")

	router.goto("res://game/menus/settings_menu.tscn", {"return_to": "res://game/menus/title_menu.tscn"})
	await wait_scene("SettingsMenu", 120)
	await _frames(20)
	var sm := current_scene
	for i in sm.tabs.get_tab_count():
		sm.tabs.current_tab = i
		await _frames(5)
		await shot("1%d_settings_%s" % [i, sm.tabs.get_tab_title(i).to_lower()])
	sm.bind_buttons["accept"]["keyboard"].pressed.emit()
	await _frames(2)
	await key(KEY_K)
	await _frames(2)
	await shot("14_settings_rebound")
	var bound := InputMap.action_get_events("accept").any(func(ev): return ev is InputEventKey and ev.physical_keycode == KEY_K)
	expect(bound, "Rebinding Accept to K reaches the input map")
	# Restore controls without pressing Back (Back writes settings.json).
	settings.data.reset_bindings()
	settings.apply_controls()

	router.goto("res://game/menus/title_menu.tscn")
	await wait_scene("TitleMenu", 120)
	await _frames(20)
	await key(KEY_Z)  # focus is on Resume
	await wait_scene("PlaceholderWorld", 120)
	await _frames(20)
	await shot("15_resumed_world")
	expect(gs.has_game() and gs.current.player_name == "Ana", "Resume reloads the same playthrough")

	_clear(RUN_SAVES)
	_finish()


## Battle tour: new game -> test party -> wild battle from the world (attack, throw a
## cage, finish) -> results -> world; then a 1-vs-2 Rival battle (Underdog).
func _run_battle() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var router := root.get_node("SceneRouter")
	gs.store = SaveStore.new(RUN_SAVES)
	_clear(RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto("res://game/world/placeholder_world.tscn")
	await wait_scene("PlaceholderWorld", 120)
	await key(KEY_F1)  # debug overlay
	await _frames(5)
	await shot("b00_debug_menu_empty_party")
	press("Get test party")
	await _frames(10)
	await wait_scene("PlaceholderWorld", 60)
	await _frames(5)
	await shot("b01_debug_menu_with_party")
	expect(gs.current.party.size() == 3, "test party granted from the F1 menu")

	# The Rival is always 2v2, so its "how many?" prompt always appears. Cancel it.
	press("Rival (2v2)")
	await _frames(5)
	await shot("b02_field_count")
	expect(_find_menu() != null, "field-count prompt appears for a 2v2 tamer")
	await key(KEY_X)  # Cancel
	await _frames(5)
	expect(_find_menu() == null, "cancelling the prompt closes it")

	press("Wild battle (Route 1)")
	await _frames(5)
	await pick_menu("1 creature")  # no-op when the pack is a single creature
	await wait_scene("BattleScene", 180)
	await wait_battle(["command"])
	await shot("b03_wild_command")
	await key(KEY_F1)  # the overlay works mid-battle, but battles can't start from it
	await _frames(5)
	await shot("b03b_debug_menu_in_battle")
	expect(paused and _find_button("Wild battle (Route 1)").disabled, "F1 in battle pauses and disables test battles")
	await key(KEY_F1)
	await _frames(5)
	await pick_menu("Fight")
	await shot("b04_moves")
	await pick_menu("Splash Jab")
	await pick_menu("")  # first target, if asked
	await pick_menu("Yes, go!")
	await _frames(20)
	await shot("b05_playback")
	var bs := current_scene
	await wait_battle(["command", "results", "replace"])
	if bs.phase == "command":
		await pick_menu("Items")
		await shot("b06_items")
		await pick_menu("Lure Cage")
		await pick_menu("")
		await pick_menu("Yes, go!")
		await _frames(30)
		await shot("b07_capture")
	# Fight until the battle ends.
	for round in 30:
		await wait_battle(["command", "results", "replace"])
		if bs.phase == "results":
			break
		if bs.phase == "replace":
			await pick_menu("")
			continue
		await pick_menu("Fight")
		await pick_menu("")  # first affordable move
		await pick_menu("")
		await pick_menu("Yes, go!")
	await wait_battle(["results"])
	await _frames(10)
	await shot("b08_results")
	expect(bs.phase == "results", "wild battle reached results (%s)" % bs.summary.get("outcome", "?"))
	bs.continue_button.pressed.emit()
	await wait_scene("PlaceholderWorld", 180)
	await _frames(10)
	await shot("b09_world_after")
	expect(gs.store.list().any(func(e): return e.kind == SaveGame.KIND_AUTO), "world autosaved after battle")

	var setup := BattleLauncher.tamer_setup(root.get_node("DataRegistry").db, gs.current, "rival_01", 1)
	router.goto("res://game/battle/battle_scene.tscn", {"setup": setup, "seed": 11})
	await wait_scene("BattleScene", 180)
	await wait_battle(["command"])
	await _frames(5)
	await shot("b10_rival_underdog")
	expect(current_scene.fields[0].underdog_text.begins_with("UNDERDOG"), "fielding 1 vs 2 shows Underdog")

	# Custom battle panel: set up a 3v1 tamer fight from the world.
	router.goto(SceneRouter.WORLD)
	await wait_scene("PlaceholderWorld", 180)
	await key(KEY_F1)
	await _frames(5)
	press("Custom battle...")
	await _frames(5)
	var opts := _find_all(root.get_node("DebugMenu"), "OptionButton")
	opts[0].select(2)  # you field 3
	opts[0].item_selected.emit(2)
	opts[2].select(1)  # tamer
	await _frames(3)
	await shot("b11_custom_panel")
	press("Start")
	await wait_scene("BattleScene", 180)
	await wait_battle(["command"])
	await _frames(5)
	await shot("b12_custom_3v1")
	await _frames(240)  # let the opening messages play so field chips can appear
	await shot("b13_custom_3v1_fields")
	expect(current_scene.views.size() == 4 and current_scene.fields[1].underdog_text.begins_with("UNDERDOG"),
		"custom 3v1 battle puts 4 creatures on the stage and makes the foe the Underdog")
	_clear(RUN_SAVES)
	_finish()


# --- Helpers (reuse these when adding new tours) ------------------------------------

## Waits until the battle scene is in one of `phases` (and its menu is ready when choosing).
func wait_battle(phases: Array, max_frames := 2400) -> void:
	for i in max_frames:
		var s := current_scene
		if s != null and s.get("phase") in phases:
			if s.phase in ["command", "replace"] and not s.menu.is_choosing():
				await process_frame
				continue
			return
		await process_frame
	expect(false, "battle reached %s (at %s)" % [phases, current_scene.get("phase")])


## Picks a CommandMenu option whose label starts with `label` ("" = first enabled one),
## in the current scene. Does nothing if no menu is choosing.
func pick_menu(label: String) -> void:
	await _frames(2)
	var n := _find_menu()
	if n == null:
		return
	if label == "":
		for b in n._grid.get_children():
			if b is Button and not b.disabled:
				b.pressed.emit()
				break
	else:
		n.pick_label(label)
	await _frames(2)


## The CommandMenu currently waiting for a choice, or null.
func _find_menu() -> CommandMenu:
	for top in _search_roots():
		var stack: Array = [top]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is CommandMenu and n.is_choosing():
				return n
			stack.append_array(n.get_children())
	return null

## Every node of class `cls` under `from`, in tree order.
func _find_all(from: Node, cls: String) -> Array:
	var out: Array = []
	for c in from.get_children():
		if c.is_class(cls):
			out.append(c)
		out.append_array(_find_all(c, cls))
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits until the current scene's root node is `node_name` and the fade is done.
func wait_scene(node_name: String, max_frames: int) -> void:
	for i in max_frames:
		if current_scene != null and current_scene.name == node_name and not root.get_node("SceneRouter").is_busy():
			return
		await process_frame
	expect(false, "reached scene %s (stuck on %s)" % [node_name, current_scene.name if current_scene else "null"])


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	_log("shot " + path)


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


## Types into the focused control. LineEdit needs `unicode`, not just keycodes.
func type_text(text: String) -> void:
	for ch in text:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(ch.to_upper())
			ev.physical_keycode = ev.keycode
			ev.unicode = ch.unicode_at(0)
			ev.pressed = pressed
			Input.parse_input_event(ev)
			await process_frame


## Presses the first Button whose text matches, in the debug overlay if it's open,
## otherwise in the current scene.
func press(text: String) -> void:
	var b := _find_button(text)
	if b == null:
		expect(false, "found button '%s'" % text)
		return
	b.pressed.emit()


func _find_button(text: String) -> Button:
	for top in _search_roots():
		var stack: Array = [top]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Button and n.text == text:
				return n
			stack.append_array(n.get_children())
	return null


## The debug overlay (an autoload, outside current_scene) first when it's open.
func _search_roots() -> Array:
	var dm := root.get_node("DebugMenu")
	return [dm, current_scene] if dm.is_open() else [current_scene]


func expect(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1


func _log(s: String) -> void:
	_log_lines.append(s)
	print("[driver] ", s)


func _finish() -> void:
	var f := FileAccess.open(_out.path_join("driver.log"), FileAccess.WRITE)
	f.store_string("\n".join(_log_lines) + "\n")
	f.close()
	print("[driver] screenshots in %s" % _out)
	print("[driver] %s" % ("ALL CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _clear(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_clear(dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
