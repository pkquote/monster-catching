extends CanvasLayer
## Debug tools on any screen: press F1. Debug builds only (the editor, the
## run-skill driver, tests); exported release builds never open it.
##
## Pauses the game while open. Party tools need a loaded game; battles can't
## be started from inside a battle. Autoload: DebugMenu.

const TOGGLE_KEY := KEY_F1
const WILD_ENCOUNTER := "route_01_grass"
const TARGET_LEVEL := 16
const BOX_FILL := 12
## Tallest a page may be (the panel adds its padding): keeps the panel on the 360px screen.
const MAX_PAGE_HEIGHT := 320.0
const TAMERS := [["scout_ana", "Scout Ana (1v1)"], ["rival_01", "Rival (2v2)"]]

var _root: Control
var _box: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _rng := RandomNumberGenerator.new()
var _restore_focus: Control
var _log_view: TextEdit
var _log_min: Log.Level = Log.Level.DEBUG
var _log_category := ""

const LOG_PAGE_WIDTH := 580.0
const LOG_VIEW_LINES := 300
const LOG_LEVELS: Array = [Log.Level.TRACE, Log.Level.DEBUG, Log.Level.INFO, Log.Level.WARN, Log.Level.ERROR]


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()


func is_open() -> bool:
	return _root != null


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or SceneRouter.is_busy():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == TOGGLE_KEY:
		get_viewport().set_input_as_handled()
		if is_open():
			close()
		else:
			open()


func open() -> void:
	if is_open() or (Overworld.active != null and Overworld.active.blocks_debug_menu()):
		return
	_restore_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := UIKit.panel(center, 12)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(260, 0)
	_box.add_theme_constant_override("separation", 4)
	_scroll.add_child(_box)
	_show_main()


func close() -> void:
	if not is_open():
		return
	_root.queue_free()
	_root = null
	_scroll = null
	_box = null
	get_tree().paused = false
	if is_instance_valid(_restore_focus) and _restore_focus.is_inside_tree():
		_restore_focus.grab_focus()
	_restore_focus = null


# --- Pages -------------------------------------------------------------------------

func _clear() -> void:
	_box.custom_minimum_size.x = 260
	_log_view = null
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _show_main(status := "") -> void:
	_clear()
	UIKit.label(_box, "Debug (F1)", UIKit.HEADING_SIZE, UIKit.ACCENT)
	_status = UIKit.label(_box, status, UIKit.BODY_SIZE, UIKit.ACCENT)  # up here: always in view
	if not GameState.has_game():
		UIKit.label(_box, "Start or load a game to use the party and battle tools.", 11, UIKit.MUTED, true)
	else:
		var s := GameState.current
		var in_battle := _in_battle()
		var first := UIKit.button(_box, "Get test party", _grant_test_party)
		first.disabled = s.story.flag(BattleLauncher.TEST_FLAG) or in_battle
		UIKit.button(_box, "Heal party", _heal_party).disabled = s.party.is_empty() or in_battle
		var can_tune := not s.party.is_empty() and not in_battle
		UIKit.button(_box, "Give XP...", _show_give_xp).disabled = not can_tune
		UIKit.button(_box, "Set Affinity...", _show_set_affinity).disabled = not can_tune
		UIKit.button(_box, "Fill box", _fill_box).disabled = in_battle
		UIKit.spacer(_box, 4)
		UIKit.label(_box, "Test battles", UIKit.BODY_SIZE, UIKit.MUTED)
		var can_fight := BattleLauncher.healthy_count(s) > 0 and not in_battle
		UIKit.button(_box, "Wild battle (Route 1)", _start_wild).disabled = not can_fight
		for t in TAMERS:
			var tamer_id: String = t[0]
			UIKit.button(_box, t[1], func(): _start_tamer(tamer_id)).disabled = not can_fight
		UIKit.button(_box, "Custom battle...", _show_custom).disabled = not can_fight
		if in_battle:
			UIKit.label(_box, "Finish the battle or close the menu to use these.", 11, UIKit.MUTED)
		elif s.party.is_empty():
			UIKit.label(_box, "Get a test party to unlock battles.", 11, UIKit.MUTED)
	UIKit.spacer(_box, 4)
	UIKit.button(_box, "Logs...", _show_logs)
	UIKit.button(_box, "Close", close)
	_focus_first()


# --- Logs page ----------------------------------------------------------------------

## Recent records (newest first) filtered by a minimum level and a category, the
## live level of each category, and where the session files are.
func _show_logs(status := "") -> void:
	_clear()
	_box.custom_minimum_size.x = LOG_PAGE_WIDTH
	UIKit.label(_box, "Logs", UIKit.HEADING_SIZE, UIKit.ACCENT)
	_status = UIKit.label(_box, status, UIKit.BODY_SIZE, UIKit.ACCENT)
	var filters := GridContainer.new()
	filters.columns = 4
	filters.add_theme_constant_override("h_separation", 8)
	_box.add_child(filters)
	var shown := _option_row(filters, "Show at least", LOG_LEVELS.map(Log.level_name), LOG_LEVELS.find(_log_min))
	shown.item_selected.connect(func(i: int) -> void: set_log_filter(LOG_LEVELS[i], _log_category))
	var cats: Array = [""] + Array(Log.CATEGORIES)
	var cat := _option_row(filters, "Category", cats.map(func(c): return "all" if c == "" else c),
		cats.find(_log_category))
	cat.item_selected.connect(func(i: int) -> void: set_log_filter(_log_min, cats[i]))
	_log_view = TextEdit.new()
	_log_view.editable = false
	_log_view.focus_mode = Control.FOCUS_NONE  # keyboard focus skips it (it would swallow Up/Down); the wheel scrolls it
	_log_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log_view.custom_minimum_size = Vector2(LOG_PAGE_WIDTH, 110)
	_log_view.add_theme_font_size_override("font_size", 10)
	_box.add_child(_log_view)
	_refresh_log_view()
	UIKit.label(_box, "Levels (change live; Save keeps them)", 11, UIKit.MUTED)
	var levels := GridContainer.new()
	levels.columns = 6
	levels.add_theme_constant_override("h_separation", 8)
	_box.add_child(levels)
	var all_levels: Array = LOG_LEVELS + [Log.Level.OFF]
	for c in ["default"] + Array(Log.CATEGORIES):
		var current: Log.Level = Log.default_level if c == "default" else Log.level_of(c)
		var pick := _option_row(levels, c, all_levels.map(Log.level_name), all_levels.find(current))
		pick.item_selected.connect(func(i: int) -> void: set_category_level(c, all_levels[i]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_box.add_child(row)
	UIKit.button(row, "Save levels", func() -> void:
		_status.text = "Levels saved." if Logging.save_levels() == OK else "Couldn't save the levels.")
	UIKit.button(row, "Open log folder", func() -> void: OS.shell_open(Logging.log_dir()))
	UIKit.button(row, "Refresh", _refresh_log_view)
	UIKit.button(row, "Back", func() -> void: _show_main())
	_focus_first()


## Shows records at or above `min_level` in `category` ("" = all).
func set_log_filter(min_level: Log.Level, category: String) -> void:
	_log_min = min_level
	_log_category = category
	_refresh_log_view()


## Changes a category's level ("default" changes the fallback level) right away.
func set_category_level(category: String, level: Log.Level) -> void:
	if category == "default":
		Log.default_level = level
	else:
		Log.set_level(category, level)
	Log.info(Log.SETTINGS, "Log level changed", {"category": category, "level": Log.level_name(level)})
	var note := "%s: %s" % [category, Log.level_name(level)]
	if category == "default" and _log_view != null:
		_show_logs(note)  # categories that follow the default show the new value
	elif _status != null:
		_status.text = note


## The lines the Logs page is showing (newest first).
func log_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for r in Logging.memory.filtered(_log_min, _log_category).slice(0, LOG_VIEW_LINES):
		out.append(Log.format(r))
	return out


func _refresh_log_view() -> void:
	if _log_view == null or not is_instance_valid(_log_view):
		return
	var lines := log_lines()
	_log_view.text = "\n".join(lines) if not lines.is_empty() else "(nothing at this level yet)"


## Any format (1v3, 3v1...), wild or tamer, and the foes' level.
func _show_custom() -> void:
	_clear()
	UIKit.label(_box, "Custom battle", UIKit.HEADING_SIZE, UIKit.ACCENT)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_box.add_child(grid)
	var save := GameState.current
	var most := mini(BattleLauncher.MAX_SIDE, BattleLauncher.healthy_count(save))
	var mine := _option_row(grid, "You field", range(1, most + 1).map(func(i): return str(i)), most - 1)
	var theirs := _option_row(grid, "Foes", range(1, BattleLauncher.MAX_SIDE + 1).map(func(i): return str(i)), 0)
	var kind := _option_row(grid, "Foe kind", ["Wild", "Tamer"], 0)
	UIKit.label(grid, "Foe level")
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = DataRegistry.db.balance.level_cap
	level.value = BattleLauncher.party_level(save)
	grid.add_child(level)
	var note := UIKit.label(_box, "", 11, UIKit.MUTED)
	var refresh := func():
		var a := mine.selected + 1
		var b := theirs.selected + 1
		var who := "Even fight."
		if a < b:
			who = "You're the Underdog."
		elif a > b:
			who = "The foe is the Underdog."
		note.text = "%dv%d   %s" % [a, b, who]
	for o: OptionButton in [mine, theirs]:
		o.item_selected.connect(refresh.unbind(1))
	refresh.call()
	UIKit.label(_box, "Foes are random species. Wild foes can be caught; tamers use the tactician AI.",
		11, UIKit.MUTED, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	UIKit.button(row, "Start", func():
		_go(BattleLauncher.custom_setup(DataRegistry.db, GameState.current, mine.selected + 1,
			theirs.selected + 1, int(level.value), kind.selected == 0, _rng)))
	UIKit.button(row, "Back", _show_main)
	_focus_first()


## Pick a party creature, then give it XP; the Learn Move / Grow screens follow.
func _show_give_xp() -> void:
	_clear()
	UIKit.label(_box, "Give XP", UIKit.HEADING_SIZE, UIKit.ACCENT)
	var pick := _creature_picker()
	var db := DataRegistry.db
	var cap: int = db.balance.level_cap
	UIKit.button(_box, "+1 level", func(): _give_xp(pick.selected, -1))
	var to16 := UIKit.button(_box, "To level %d" % mini(TARGET_LEVEL, cap), func(): _give_xp(pick.selected, mini(TARGET_LEVEL, cap)))
	var update := func():
		to16.disabled = GameState.current.party[pick.selected].level >= mini(TARGET_LEVEL, cap)
	pick.item_selected.connect(update.unbind(1))
	update.call()
	UIKit.button(_box, "Back", _show_main)
	_focus_first()


## Pick a party creature, then the Affinity track to push to the front.
func _show_set_affinity() -> void:
	_clear()
	UIKit.label(_box, "Set Affinity", UIKit.HEADING_SIZE, UIKit.ACCENT)
	var pick := _creature_picker()
	var db := DataRegistry.db
	for a: String in db.ids("affinities"):
		UIKit.button(_box, db.affinity(a).name, func(): _set_affinity(pick.selected, a))
	UIKit.button(_box, "Back", _show_main)
	_focus_first()


func _creature_picker() -> OptionButton:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_box.add_child(grid)
	var db := DataRegistry.db
	var names := GameState.current.party.map(
		func(c: CreatureInstance): return "%s Lv %d" % [c.display_name(db), c.level])
	return _option_row(grid, "Creature", names, 0)


## The shared "how many?" prompt; back to the main page when cancelled.
func _ask(format_size: int, intro: String) -> Variant:
	var n = await FieldCountPrompt.ask(self, format_size, intro)
	if n == null and is_open():
		_show_main()
	return n


# --- Actions -----------------------------------------------------------------------

func _grant_test_party() -> void:
	BattleLauncher.grant_test_party(DataRegistry.db, GameState.current)
	GameState.autosave()
	_refresh_world()
	_show_main("Test party added.")


func _heal_party() -> void:
	for c: CreatureInstance in GameState.current.party:
		c.heal_full(DataRegistry.db)
	GameState.autosave()
	_refresh_world()
	_show_main("Party healed.")


## Raises a party creature to `to_level` (or one level when -1), then runs the
## progress screens. The menu closes first: the screens can't run in a paused tree.
func _give_xp(index: int, to_level: int) -> void:
	var world := Overworld.active
	if world == null or index >= GameState.current.party.size():
		return
	var db := DataRegistry.db
	var c: CreatureInstance = GameState.current.party[index]
	if c.level >= db.balance.level_cap:
		_show_main("%s is at the level cap." % c.display_name(db))
		return
	var goal: int = c.level + 1 if to_level < 0 else mini(to_level, db.balance.level_cap)
	var before := c.level
	Progression.award_xp(db, c, maxi(1, Stats.xp_for_level(goal) - c.xp))
	var entry := Progression.progress_entry(db, c, before)
	close()
	_refresh_world()
	if entry != null:
		await world.battles.run_progress([entry])
	GameState.autosave()  # after the screens, so Learn Move / Grow choices are kept


## Sets `track` to the growth threshold + 10, and strictly above every other track
## (so, if another track is higher, to that track's points + 10).
func _set_affinity(index: int, track: String) -> void:
	var db := DataRegistry.db
	var c: CreatureInstance = GameState.current.party[index]
	var value: int = db.balance.growth_affinity_threshold + 10
	for a: String in db.ids("affinities"):
		if a != track:
			value = maxi(value, int(c.affinity.get(a, 0)) + 10)
	c.affinity[track] = value
	GameState.autosave()
	_show_main("%s: %s is now %d." % [c.display_name(db), db.affinity(track).name, value])


func _fill_box() -> void:
	var db := DataRegistry.db
	var ids := db.ids("creatures")
	var level := BattleLauncher.party_level(GameState.current)
	for i in BOX_FILL:
		GameState.current.storage.append(CreatureInstance.create(db, ids[_rng.randi() % ids.size()], level))
	GameState.autosave()
	_show_main("Added %d creatures to the box." % BOX_FILL)


func _start_wild() -> void:
	var db := DataRegistry.db
	var pack := BattleLauncher.roll_wild_pack(db, WILD_ENCOUNTER, _rng)
	var names := ", ".join(pack.map(func(c: CreatureInstance): return "%s Lv %d" % [c.display_name(db), c.level]))
	var n = await _ask(pack.size(), "Wild %s!" % names)
	if n != null:
		_go(BattleLauncher.wild_setup(GameState.current, pack, n))


func _start_tamer(tamer_id: String) -> void:
	var t := DataRegistry.db.tamer(tamer_id)
	var n = await _ask(t.max_active, "%s fields %d at a time." % [t.name, t.max_active])
	if n != null:
		_go(BattleLauncher.tamer_setup(DataRegistry.db, GameState.current, tamer_id, n))


## Starts a battle over the overworld (debug battles use the normal defeat rules).
func _go(setup: BattleSetup) -> void:
	close()
	if Overworld.active != null:
		Overworld.active.battles.run_battle(setup)


# --- Helpers -----------------------------------------------------------------------

## Battles (and the party tools) only make sense on the overworld, outside a battle.
func _in_battle() -> bool:
	return Overworld.active == null or Overworld.active.is_locked()


## Lets the current screen redraw anything that shows the party or bag.
func _refresh_world() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("refresh_hud"):
		scene.refresh_hud()


func _option_row(grid: GridContainer, text: String, choices: Array, selected: int) -> OptionButton:
	UIKit.label(grid, text)
	var o := OptionButton.new()
	for c in choices:
		o.add_item(c)
	o.selected = selected
	grid.add_child(o)
	return o


## Focus the first button; and let a page taller than the screen scroll (focus follows).
func _focus_first() -> void:
	_scroll.custom_minimum_size.y = minf(_box.get_combined_minimum_size().y, MAX_PAGE_HEIGHT)
	for c in _find_focusable(_box):
		# Deferred until the page is laid out; the page may be rebuilt or closed first.
		(func() -> void:
			if is_instance_valid(c) and c.is_inside_tree():
				c.grab_focus()).call_deferred()
		return


func _find_focusable(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is BaseButton and not c.disabled:
			out.append(c)
		out.append_array(_find_focusable(c))
	return out
