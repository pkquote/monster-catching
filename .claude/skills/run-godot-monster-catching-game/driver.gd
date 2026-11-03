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
	if _opts.mode == "scene":
		_run_scene()
	else:
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


# --- Helpers (reuse these when adding new tours) ------------------------------------

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


## Presses the first Button in the current scene whose text matches.
func press(text: String) -> void:
	var stack: Array = [current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and n.text == text:
			n.pressed.emit()
			return
		stack.append_array(n.get_children())
	expect(false, "found button '%s'" % text)


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
