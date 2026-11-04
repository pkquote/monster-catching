class_name DebugMainPage
extends DebugPage
## The first page: party tools, test battles, and the way to the other pages.

const WILD_ENCOUNTER := "route_01_grass"
const BOX_FILL := 12
const TAMERS := [["scout_ana", "Scout Ana (1v1)"], ["rival_01", "Rival (2v2)"]]


func title() -> String:
	return "Debug (F1)"


func build(box: VBoxContainer) -> void:
	if not GameState.has_game():
		UIKit.label(box, "Start or load a game to use the party and battle tools.", 11, UIKit.MUTED, true)
	else:
		var s := GameState.current
		var blocked: bool = menu.tools_blocked()
		var first := UIKit.button(box, "Get test party", _grant_test_party)
		first.disabled = s.story.flag(BattleLauncher.TEST_FLAG) or blocked
		UIKit.button(box, "Heal party", _heal_party).disabled = s.party.is_empty() or blocked
		var can_tune := not s.party.is_empty() and not blocked
		UIKit.button(box, "Give XP...", func(): menu.show_page(DebugGiveXpPage.new())).disabled = not can_tune
		UIKit.button(box, "Set Affinity...", func(): menu.show_page(DebugAffinityPage.new())).disabled = not can_tune
		UIKit.button(box, "Fill box", _fill_box).disabled = blocked
		UIKit.spacer(box, 4)
		UIKit.label(box, "Test battles", UIKit.BODY_SIZE, UIKit.MUTED)
		var can_fight := BattleLauncher.healthy_count(s) > 0 and not blocked
		UIKit.button(box, "Wild battle (Route 1)", _start_wild).disabled = not can_fight
		for t in TAMERS:
			var tamer_id: String = t[0]
			UIKit.button(box, t[1], func(): _start_tamer(tamer_id)).disabled = not can_fight
		UIKit.button(box, "Custom battle...", func(): menu.show_page(DebugCustomBattlePage.new())).disabled = not can_fight
		if blocked:
			UIKit.label(box, "Finish the battle or close the menu to use these.", 11, UIKit.MUTED)
		elif s.party.is_empty():
			UIKit.label(box, "Get a test party to unlock battles.", 11, UIKit.MUTED)
	UIKit.spacer(box, 4)
	UIKit.button(box, "Logs...", func(): menu.show_page(DebugLogsPage.new()))
	UIKit.button(box, "Close", menu.close)


func _grant_test_party() -> void:
	BattleLauncher.grant_test_party(DataRegistry.db, GameState.current)
	GameState.autosave()
	menu.refresh_world()
	menu.show_page(DebugMainPage.new(), "Test party added.")


func _heal_party() -> void:
	for c: CreatureInstance in GameState.current.party:
		c.heal_full(DataRegistry.db)
	GameState.autosave()
	menu.refresh_world()
	menu.show_page(DebugMainPage.new(), "Party healed.")


func _fill_box() -> void:
	var db := DataRegistry.db
	var ids := db.ids("creatures")
	var level := BattleLauncher.party_level(GameState.current)
	for i in BOX_FILL:
		GameState.current.storage.append(CreatureInstance.create(db, ids[menu.rng.randi() % ids.size()], level))
	GameState.autosave()
	menu.show_page(DebugMainPage.new(), "Added %d creatures to the box." % BOX_FILL)


func _start_wild() -> void:
	var db := DataRegistry.db
	var pack := BattleLauncher.roll_wild_pack(db, WILD_ENCOUNTER, menu.rng)
	var names := ", ".join(pack.map(func(c: CreatureInstance): return "%s Lv %d" % [c.display_name(db), c.level]))
	menu.ask_then_go(pack.size(), "Wild %s!" % names, DebugMainPage._wild_setup.bind(pack))


func _start_tamer(tamer_id: String) -> void:
	var t := DataRegistry.db.tamer(tamer_id)
	menu.ask_then_go(t.max_active, "%s fields %d at a time." % [t.name, t.max_active],
		DebugMainPage._tamer_setup.bind(tamer_id))


# Static, so the battle still starts if the page is gone by the time the count is picked.
static func _wild_setup(count: int, pack: Array) -> BattleSetup:
	return BattleLauncher.wild_setup(GameState.current, pack, count)


static func _tamer_setup(count: int, tamer_id: String) -> BattleSetup:
	return BattleLauncher.tamer_setup(DataRegistry.db, GameState.current, tamer_id, count)
