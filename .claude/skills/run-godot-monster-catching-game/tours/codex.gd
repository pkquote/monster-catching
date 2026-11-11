extends RefCounted
## The `codex` tour (driver.gd --mode=codex).
## New game -> Tidepup and Emberkit marked caught, Torrentusk seen, the rest unseen (on the save, no F1 page) ->
## Menu -> Codex -> Down through the rows with real keys: the left pane follows (a sprite, a seen name, an
## unseen silhouette) -> the unseen row does nothing -> the caught starter's page ("No wild habitat known"), a
## wild species' page (where to find it), the seen-only page ("Not caught yet") -> Back out to the world.
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, pick_menu, key...) and its tree.

var d

const VIEW := Rect2(0, 0, 640, 360)


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

	var save: SaveGame = gs.current
	Codex.mark_caught(save, "tidepup")
	Codex.mark_caught(save, "emberkit")
	Codex.mark_seen(save, "torrentusk")
	var ow = d.current_scene

	# 1. Menu -> Codex: the header counts and the first row's preview.
	await d.key(KEY_C)
	await d.pick_menu("Codex")
	await d._frames(5)
	var list := _screen(ow, CodexScreen) as CodexScreen
	d.expect(list != null, "the Codex list opened")
	if list == null:
		d._finish()
		return
	await d.shot("cdx01_list")
	var n: int = Codex.order(db).size()
	d.expect(list.page_text() == "Seen 3 / %d · Caught 2 / %d" % [n, n], "header counts (%s)" % list.page_text())
	d.expect(list.preview().name_text() == "#001 " + db.creature("tidepup").name and list.preview().status_text() == "Caught",
		"the preview shows the caught starter (%s | %s)" % [list.preview().name_text(), list.preview().status_text()])
	_expect_fits(list, "cdx01_list")

	# 2. Down to the seen row, then to the unseen row: the preview follows.
	await d.key(KEY_DOWN)
	await d._frames(4)
	await d.shot("cdx02_seen_row")
	d.expect(list.preview().status_text() == "Seen, not caught yet" and not list.preview().is_silhouette(),
		"the seen row previews its name (%s)" % list.preview().name_text())
	await d.key(KEY_DOWN)
	await d._frames(4)
	await d.shot("cdx03_unseen_row")
	d.expect(list.preview().is_silhouette() and list.preview().name_text() == "#003 ???" \
		and db.creature("mistcoil").name not in list.preview().name_text(),
		"the unseen row is a silhouette and leaks no name (%s)" % list.preview().name_text())

	# 3. The unseen row does nothing.
	await d.pick_menu("#003")
	await d._frames(4)
	d.expect(_screen(ow, CodexDetailPage) == null and list.menu.is_choosing(), "the unseen row opens nothing")

	# 4. Pages: the caught starter (no wild habitat), a wild species, the seen-only species.
	await _page(ow, "#001", "cdx04_page_starter", func(p: CodexDetailPage) -> bool:
		return "No wild habitat known" in p.page_text() and "Where to find it:" in p.page_text(), "the starter says no wild habitat")
	await _page(ow, "#004", "cdx05_page_wild", func(p: CodexDetailPage) -> bool:
		return "Route 1 – Route 1 tall grass" in p.page_text(), "a wild species lists Route 1")
	await _page(ow, "#002", "cdx06_page_seen", func(p: CodexDetailPage) -> bool:
		return "Not caught yet" in p.page_text(), "a seen species ends 'Not caught yet'")

	# 5. Back out: the list, then the pause menu, then the world.
	await d.pick_menu("Back")
	await d._frames(5)
	d.expect(_screen(ow, CodexScreen) == null, "Back closes the Codex")
	await d.pick_menu("Close")
	await d.wait_unlocked(ow)
	d._clear(d.RUN_SAVES)
	d._finish()


## Opens the page for the row starting `prefix`, screenshots it, checks `ok` and that it fits, then goes Back.
func _page(ow, prefix: String, shot_name: String, ok: Callable, what: String) -> void:
	await d.pick_menu(prefix)
	await d._frames(5)
	var page := _screen(ow, CodexDetailPage) as CodexDetailPage
	d.expect(page != null, "%s: the page opened" % shot_name)
	if page == null:
		return
	await d.shot(shot_name)
	d.expect(ok.call(page), "%s: %s (%s)" % [shot_name, what, page.page_text().replace("\n", " | ")])
	_expect_fits(page, shot_name)
	await d.pick_menu("Back")
	await d._frames(5)
	d.expect(_screen(ow, CodexDetailPage) == null, "%s: Back closes the page" % shot_name)


func _screen(ow: Node, cls: Script) -> Node:
	for n in ow.get_children():
		if is_instance_of(n, cls):
			return n
	return null


## The info panel and the menu area sit on the 640x360 screen without overlapping.
func _expect_fits(screen: ProgressScreen, what: String) -> void:
	var problems := ScreenFit.problems(screen)
	d.expect(problems.is_empty(), "%s: fits the screen (%s)" % [what, ", ".join(problems)])
