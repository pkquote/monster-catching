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
		"overworld":
			_run_overworld()
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
	await wait_scene("Overworld", 120)
	await _frames(40)
	await shot("06_world_autosaved")
	await key(KEY_C)  # Menu
	await pick_menu("Save")
	await _frames(5)
	await shot("07_world_saved")
	expect(gs.store.list().size() == 3, "3 saves exist (first save, autosave, manual save)")

	await pick_menu("Quit to title")
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
	await wait_scene("Overworld", 120)
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
	router.goto(router.WORLD)
	await wait_scene("Overworld", 120)
	await key(KEY_F1)  # debug overlay
	await _frames(5)
	await shot("b00_debug_menu_empty_party")
	press("Get test party")
	await _frames(10)
	await wait_scene("Overworld", 60)
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
	await wait_battle_open()
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
	var bs := _battle()
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
	for i in 300:  # the battle closes and the map carries on underneath
		if _battle() == null and not current_scene.is_locked():
			break
		await process_frame
	await _frames(10)
	await shot("b09_world_after")
	expect(gs.store.list().any(func(e): return e.kind == SaveGame.KIND_AUTO), "world autosaved after battle")

	var setup := BattleLauncher.tamer_setup(root.get_node("DataRegistry").db, gs.current, "rival_01", 1)
	router.goto("res://game/battle/battle_scene.tscn", {"setup": setup, "seed": 11})
	await wait_battle_open()
	await wait_battle(["command"])
	await _frames(5)
	await shot("b10_rival_underdog")
	expect(_battle().fields[0].underdog_text.begins_with("UNDERDOG"), "fielding 1 vs 2 shows Underdog")

	# Custom battle panel: set up a 3v1 tamer fight from the world.
	router.goto(router.WORLD)
	await wait_scene("Overworld", 180)
	await key(KEY_F1)
	await _frames(5)
	press("Heal party")  # the random wild fight may have knocked someone out
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
	await wait_battle_open()
	await wait_battle(["command"])
	await _frames(5)
	await shot("b12_custom_3v1")
	await _frames(240)  # let the opening messages play so field chips can appear
	await shot("b13_custom_3v1_fields")
	expect(_battle().views.size() == 4 and _battle().fields[1].underdog_text.begins_with("UNDERDOG"),
		"custom 3v1 battle puts 4 creatures on the stage and makes the foe the Underdog")
	_clear(RUN_SAVES)
	_finish()


## Overworld tour: new game at home -> out the door -> the professor's cutscene ->
## pick a starter in the lab -> the lab rival battle -> back in control.
func _run_overworld() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var router := root.get_node("SceneRouter")
	gs.store = SaveStore.new(RUN_SAVES)
	_clear(RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await wait_scene("Overworld", 120)
	await _frames(10)
	var ow = current_scene
	await shot("o01_home")
	expect(ow.map.map_id() == "town_01_home", "a new game starts at home")
	await hold(KEY_D, 32)  # ends ~2px off the door column: corner-slipping carries you through
	await hold(KEY_S, 70)
	await wait_unlocked(ow)
	await _frames(10)
	await shot("o02_town")
	expect(ow.map.map_id() == "town_01", "the door leads into town (%s)" % ow.map.map_id())
	await hold(KEY_S, 12)  # onto the path: the professor stops you
	await _frames(40)
	await shot("o03_prof_stops_you")
	await talk_until(func(): return _find_menu() != null)
	await _frames(5)
	await shot("o04_lab_choice")
	expect(ow.map.map_id() == "town_01_lab", "the cutscene walks you to the lab")
	await pick_menu("Tidepup")
	await talk_until(func(): return _battle() != null)
	await wait_battle(["command"])
	await shot("o05_rival_battle")
	await fight_to_end()
	await shot("o06_rival_results")
	_battle().continue_button.pressed.emit()
	await talk_until(func(): return not ow.is_locked() and _battle() == null)
	await _frames(10)
	await shot("o07_back_in_lab")
	expect(gs.current.party.size() == 1 and root.get_node("Story").flag("got_starter"),
		"the starter joined the party (%d)" % gs.current.party.size())
	var story := root.get_node("Story")

	# Heal centre: rest at the counter, then buy a Salve.
	await ow.change_map("town_01_center", "entry")
	await _frames(10)
	gs.current.party[0].hp = 1
	ow.player.place(_tile_centre(3, 3), Vector2i.UP)
	await key(KEY_Z)
	await talk_until(func(): return _find_menu() != null)
	await shot("o08_heal_prompt")
	await pick_menu("Yes")
	await talk_until(func(): return not ow.is_locked())
	expect(gs.current.party[0].hp == gs.current.party[0].max_hp(root.get_node("DataRegistry").db)
		and gs.current.story.last_heal.get("map", "") == "town_01_center", "resting heals and sets the wake-up point")
	gs.current.money = 1000
	var salves: int = gs.current.inventory.get("salve", 0)
	ow.player.place(_tile_centre(7, 3), Vector2i.UP)
	await key(KEY_Z)
	await pick_menu("Buy")
	await pick_menu("Salve")
	await shot("o09_shop")
	await pick_menu("×1")
	await pick_menu("OK")
	await pick_menu("Back")
	await pick_menu("Leave")
	await _frames(5)
	expect(gs.current.inventory.get("salve", 0) == salves + 1 and gs.current.money == 850, "bought a Salve for 150")

	# Route 1: walk up the path into Scout Ana's line of sight. (A level-20 starter,
	# so the scripted fights are won and the tour stays on the route.)
	var starter = gs.current.party[0]
	starter.level = 20
	starter.heal_full(root.get_node("DataRegistry").db)
	await ow.change_map("route_01", "from_town")
	await _frames(10)
	await shot("o10_route")
	await hold(KEY_W, 270)
	await talk_until(func(): return _battle() != null)
	await wait_battle(["command"])
	await shot("o11_tamer_battle")
	await fight_to_end()
	_battle().continue_button.pressed.emit()
	await talk_until(func(): return not ow.is_locked() and _battle() == null)
	var ana = ow.map.entities().get_node("ScoutAna")
	expect(story.last_battle_request.get("tamer_id", "") == "scout_ana", "Scout Ana spotted you and battled")
	await shot("o12_after_tamer")

	# Tall grass: make every step roll an encounter, then run from it.
	gs.current.party[0].hp = gs.current.party[0].max_hp(root.get_node("DataRegistry").db)
	ow.roller._rate = 1.0
	ow.roller._grace = 0
	ow.player.place(_tile_centre(12, 26), Vector2i.RIGHT)
	await hold(KEY_D, 14)
	await pick_menu("1 creature")
	await wait_battle_open()
	await wait_battle(["command"])
	await shot("o13_wild_from_grass")
	expect(_battle().setup.is_wild, "stepping into tall grass started a wild battle")
	await pick_menu("Run")
	await pick_menu("Yes, go!")
	await wait_battle(["results"])
	_battle().continue_button.pressed.emit()
	await talk_until(func(): return not ow.is_locked() and _battle() == null)
	ow.roller._rate = 0.0

	# Quick Draw with the Sharpshooter.
	ow.player.place(_tile_centre(6, 7), Vector2i.UP)
	await key(KEY_Z)
	await talk_until(func(): return _find_menu() != null)
	await pick_menu("Let's play")
	var qd = null
	for i in 120:
		var found := _find_all(root, "Control").filter(func(n): return n.name == "QuickDraw")
		if not found.is_empty():
			qd = found[0]
			break
		await process_frame
	var shot_taken := false
	for i in 1500:
		if not is_instance_valid(qd):
			break
		if qd._big.text == "!":
			if not shot_taken:
				await shot("o14_quick_draw")
				shot_taken = true
			await key(KEY_Z)
		elif qd._done:
			await key(KEY_Z)
		await process_frame
	await talk_until(func(): return not ow.is_locked())
	expect(story.last_minigame().has("won"), "Quick Draw finished (%s)" % story.last_minigame())

	# Save from the pause menu, quit, and resume at the same spot.
	ow.player.place(_tile_centre(10, 30), Vector2i.DOWN)
	await key(KEY_C)
	await pick_menu("Save")
	await shot("o15_pause_menu")
	await pick_menu("Quit to title")
	await wait_scene("TitleMenu", 120)
	await _frames(20)
	await key(KEY_Z)  # Resume
	await wait_scene("Overworld", 180)
	await _frames(20)
	ow = current_scene
	await shot("o16_resumed")
	expect(ow.map.map_id() == "route_01" and ow.player.feet_tile() == Vector2i(10, 30),
		"Resume puts you back where you saved (%s %s)" % [ow.map.map_id(), ow.player.feet_tile()])
	_clear(RUN_SAVES)
	_finish()


func _tile_centre(x: int, y: int) -> Vector2:
	return Vector2(x * 32 + 16, y * 32 + 16)


## Presses Accept through conversations until `done` returns true (or ~20 s pass).
func talk_until(done: Callable, max_frames := 1200) -> void:
	for i in max_frames:
		if done.call():
			return
		if i % 6 == 0 and _find_menu() == null:
			await key(KEY_Z)
		await process_frame
	expect(false, "conversation reached its goal")


func wait_unlocked(ow, max_frames := 240) -> void:
	for i in max_frames:
		if not ow.is_locked():
			return
		await process_frame


## Picks the first affordable move against the first target every round until results.
func fight_to_end() -> void:
	for round in 40:
		await wait_battle(["command", "results", "replace"])
		var b := _battle()
		if b.phase == "results":
			return
		if b.phase == "replace":
			await pick_menu("")
			continue
		await pick_menu("Fight")
		await pick_menu("")
		await pick_menu("")
		await pick_menu("Yes, go!")
	await wait_battle(["results"])


# --- Helpers (reuse these when adding new tours) ------------------------------------

## Holds a key down for `frames` frames (real movement input), then releases it.
func hold(code: Key, frames: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		if pressed:
			await _frames(frames)
	await process_frame




## The battle on screen: the current scene when it's a battle, or the battle
## the overworld is showing over its map (overworld battles are overlays). Null if none.
func _battle() -> Node:
	if current_scene != null and current_scene.name == "BattleScene":
		return current_scene
	var found := _find_all(current_scene, "Control").filter(func(n): return n.name == "BattleScene")
	return found[0] if not found.is_empty() else null


func wait_battle_open(max_frames := 240) -> void:
	for i in max_frames:
		if _battle() != null and not root.get_node("SceneRouter").is_busy():
			return
		await process_frame
	expect(false, "a battle opened")


## Waits until the battle is in one of `phases` (and its menu is ready when choosing).
func wait_battle(phases: Array, max_frames := 2400) -> void:
	for i in max_frames:
		var s := _battle()
		if s != null and s.get("phase") in phases:
			if s.phase in ["command", "replace"] and not s.menu.is_choosing():
				await process_frame
				continue
			return
		await process_frame
	expect(false, "battle reached %s (at %s)" % [phases, _battle().get("phase") if _battle() else "no battle"])


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
	if from == null:
		return out
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
