extends RefCounted
## The `frontend` tour (driver.gd --mode=frontend).
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, hold, press...) and
## its tree (d.root, d.current_scene, d.process_frame).

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var settings = d.root.get_node("Settings")
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)

	d.change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await d._frames(25)
	await d.shot("01_splash_credit")
	await d._frames(75)
	await d.shot("02_splash_title")
	await d.wait_scene("TitleMenu", 300)
	await d._frames(20)
	await d.shot("03_title_no_saves")

	# Real keyboard input: focus starts on New Game; Z is the default Accept key.
	await d.key(KEY_Z)
	await d.wait_scene("NewGame", 120)
	await d._frames(15)
	await d.shot("04_new_game_empty")
	d.expect(d.current_scene.start_button.disabled, "Start is disabled before typing a name")
	await d.type_text("Ana")
	await d.shot("05_new_game_typed")
	d.expect(not d.current_scene.start_button.disabled, "Start is enabled after typing a name")
	await d.key(KEY_ENTER)  # LineEdit submit starts the game
	await d.wait_scene("Overworld", 120)
	await d._frames(40)
	await d.shot("06_world_autosaved")
	await d.key(KEY_C)  # Menu
	await d.pick_menu("Save")
	await d._frames(5)
	await d.shot("07_world_saved")
	d.expect(gs.store.list().size() == 3, "3 saves exist (first save, autosave, manual save)")

	await d.pick_menu("Quit to title")
	await d.wait_scene("TitleMenu", 120)
	await d._frames(20)
	await d.shot("08_title_with_resume")
	d.expect(gs.resume_path() != "", "Resume target is set")

	d.press("Load Game")
	await d.wait_scene("LoadMenu", 120)
	await d._frames(20)
	await d.shot("09_load_menu")

	router.goto("res://game/menus/settings_menu.tscn", {"return_to": "res://game/menus/title_menu.tscn"})
	await d.wait_scene("SettingsMenu", 120)
	await d._frames(20)
	var sm = d.current_scene
	for i in sm.tabs.get_tab_count():
		sm.tabs.current_tab = i
		await d._frames(5)
		await d.shot("1%d_settings_%s" % [i, sm.tabs.get_tab_title(i).to_lower()])
	sm.bind_buttons["accept"]["keyboard"].pressed.emit()
	await d._frames(2)
	await d.key(KEY_K)
	await d._frames(2)
	await d.shot("14_settings_rebound")
	var bound := InputMap.action_get_events("accept").any(func(ev): return ev is InputEventKey and ev.physical_keycode == KEY_K)
	d.expect(bound, "Rebinding Accept to K reaches the input map")
	# Restore controls without pressing Back (Back writes settings.json).
	settings.data.reset_bindings()
	settings.apply_controls()

	router.goto("res://game/menus/title_menu.tscn")
	await d.wait_scene("TitleMenu", 120)
	await d._frames(20)
	await d.key(KEY_Z)  # focus is on Resume
	await d.wait_scene("Overworld", 120)
	await d._frames(20)
	await d.shot("15_resumed_world")
	d.expect(gs.has_game() and gs.current.player_name == "Ana", "Resume reloads the same playthrough")

	d._clear(d.RUN_SAVES)
	d._finish()
