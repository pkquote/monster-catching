extends RefCounted
## The `achievements` tour (driver.gd --mode=achievements).
## New game -> a creature given (earns First Catch through the real hooks and the service) -> Menu ->
## Achievements -> the header counts one, the focused row's preview shows progress, Down to First Catch
## (unlocked, with its date), Down to the hidden entry (masked: "???", nothing leaks) -> Back out.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, pick_menu, key...) and its tree.

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var db = d.root.get_node("DataRegistry").db
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d._frames(10)

	var ow = d.current_scene
	d.root.get_node("Story").give_creature("tidepup", 5)  # a creature joins: First Catch
	await d._frames(5)
	d.expect(gs.current.achievements.has("first_catch"), "giving a creature unlocked First Catch through the service")

	# 1. Menu -> Achievements: the header and the first row's preview.
	await d.key(KEY_C)
	await d.pick_menu("Achievements")
	await d._frames(5)
	var list := _screen(ow) as AchievementsScreen
	d.expect(list != null, "the Achievements list opened")
	if list == null:
		d._finish()
		return
	var n: int = Achievements.listed(db).size()
	await d.shot("ach01_list")
	d.expect(list.page_text() == "Unlocked 1 / %d" % n, "header counts one (%s)" % list.page_text())
	d.expect(list.preview().name_text() == "First Steps" and list.preview().status_text().begins_with("Progress"),
		"the first row previews its progress (%s | %s)" % [list.preview().name_text(), list.preview().status_text()])
	d.expect("First Catch ✓" in Array(list.menu.labels()), "First Catch reads as unlocked")
	_expect_fits(list, "ach01_list")

	# 2. Down to First Catch (the fourth row): unlocked, with its date.
	for i in 3:
		await d.key(KEY_DOWN)
	await d._frames(4)
	await d.shot("ach02_unlocked_row")
	d.expect(list.preview().name_text() == "First Catch" and list.preview().status_text().begins_with("Unlocked"),
		"the unlocked row shows its date (%s)" % list.preview().status_text())

	# 3. Down to the hidden entry (the last): masked, nothing leaks.
	for i in n - 4:
		await d.key(KEY_DOWN)
	await d._frames(4)
	await d.shot("ach03_hidden_row")
	var hidden = db.achievement("quick_on_the_draw")
	d.expect(list.preview().is_masked() and list.preview().name_text() == "???",
		"the hidden row is masked (%s)" % list.preview().name_text())
	d.expect(hidden.name not in list.preview().description_text() and hidden.description not in list.preview().description_text(),
		"the hidden row leaks no name or description")
	d.expect("???" in Array(list.menu.labels()), "the hidden row reads ???")

	# 4. Back out: the list, then the pause menu, then the world.
	await d.pick_menu("Back")
	await d._frames(5)
	d.expect(_screen(ow) == null, "Back closes Achievements")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)
	d._clear(d.RUN_SAVES)
	d._finish()


func _screen(ow: Node) -> Node:
	for n in ow.get_children():
		if n is AchievementsScreen:
			return n
	return null


## The info panel and the menu area sit on the 640x360 screen without overlapping.
func _expect_fits(screen: ProgressScreen, what: String) -> void:
	var problems := ScreenFit.problems(screen)
	d.expect(problems.is_empty(), "%s: fits the screen (%s)" % [what, ", ".join(problems)])
