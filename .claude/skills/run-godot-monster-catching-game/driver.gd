extends SceneTree
## Drives the real game in a window and saves PNG screenshots.
##
##   godot --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- [options]
##
## Options (after the `--`):
##   --mode=frontend      (default) full front-end tour: splash -> title -> new game -> world ->
##                        save -> quit -> load browser -> settings tabs -> rebind -> resume.
##                        Checks expectations and exits 1 if any fail.
##   --mode=progress     M4 tour: test party, Give XP to 16, Learn Move, Grow, Party reorder, Summary tabs,
##                        training, Reset Seed, Storage Box, unsafe zone.
##   --mode=passives     passives tour: Set passive (Undertow), its battle-entry banner, Set Affinity
##                        unlocks Finisher, the Passive Unlocked screen, Summary -> Use Finisher.
##   --mode=held          held-items tour: Summary -> Give held item (Oran Berry), a battle where it fires
##                        (banner naming it, "used up"), the Summary again with the item gone.
##   --mode=builder       F1 Custom battle team builder: full teams, All levels, slot editor, bag page,
##                        a 2v3 exhibition to the results; the save must be unchanged.
##   --mode=party         every screen that lists the party (Party, Summary, Bag targets, Storage,
##                        battle Swap and item targets) with a full party; --party-size=N (1-12)
##                        sets balance.party_size in memory only (data/balance.json is untouched).
##   --mode=bag           Menu -> Bag: the left pane follows the focused item (heal, held, capture and a
##                        very long description added in memory), Back shows "Pick an item.".
##   --mode=ui            F1 UI gallery: the creature card (sprite, radar, bars, moves) at Lv 5, 50 and 99
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
		"battle", "overworld", "progress", "passives", "held", "builder", "party", "bag", "ui":
			_tour(_opts.mode)
		_:
			_tour("frontend")


## Runs tours/<name>.gd: each tour is a file of its own that drives the game through
## this driver's helpers.
func _tour(name: String) -> void:
	var script = load("res://.claude/skills/run-godot-monster-catching-game/tours/%s.gd" % name)
	if script == null or not script.can_instantiate():
		# A tour that doesn't compile must fail the run straight away, not hang until a timeout.
		expect(false, "tour script tours/%s.gd loads (see the SCRIPT ERROR above)" % name)
		_finish()
		return
	var tour = script.new()
	tour.d = self
	await tour.run()


# --- Modes ---------------------------------------------------------------------------

func _run_scene() -> void:
	await process_frame
	var path: String = _opts.scene if _opts.scene != "" else ProjectSettings.get_setting("application/run/main_scene")
	change_scene_to_file(path)
	await _frames(int(_opts.frames))
	await shot(path.get_file().get_basename())
	_finish()


## The ProgressScreen (a CanvasLayer) that owns `m`, or null.
func _screen_of(m: CommandMenu) -> Node:
	var n: Node = m
	while n != null and not n.has_method("page_text"):
		n = n.get_parent()
	return n


func _screen_title(m: CommandMenu) -> String:
	var s := _screen_of(m)
	return s.title_text() if s != null else ""


func _screen_page(m: CommandMenu) -> String:
	var s := _screen_of(m)
	return s.page_text() if s != null else ""


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
