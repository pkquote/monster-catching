extends CanvasLayer
## Debug tools on any screen: press F1. Debug builds only (the editor, the
## run-skill driver, tests); exported release builds never open it.
##
## Pauses the game while open. Party tools need a loaded game; battles can't
## be started from inside a battle. Autoload: DebugMenu.

const TOGGLE_KEY := KEY_F1
const WILD_ENCOUNTER := "route_01_grass"
const TAMERS := [["scout_ana", "Scout Ana (1v1)"], ["rival_01", "Rival (2v2)"]]

var _root: Control
var _box: VBoxContainer
var _status: Label
var _rng := RandomNumberGenerator.new()
var _restore_focus: Control


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
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(260, 0)
	_box.add_theme_constant_override("separation", 4)
	panel.add_child(_box)
	_show_main()


func close() -> void:
	if not is_open():
		return
	_root.queue_free()
	_root = null
	_box = null
	get_tree().paused = false
	if is_instance_valid(_restore_focus) and _restore_focus.is_inside_tree():
		_restore_focus.grab_focus()
	_restore_focus = null


# --- Pages -------------------------------------------------------------------------

func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _show_main(status := "") -> void:
	_clear()
	UIKit.label(_box, "Debug (F1)", UIKit.HEADING_SIZE, UIKit.ACCENT)
	if not GameState.has_game():
		UIKit.label(_box, "Start or load a game to use the party and battle tools.", 11, UIKit.MUTED, true)
	else:
		var s := GameState.current
		var in_battle := _in_battle()
		var first := UIKit.button(_box, "Get test party", _grant_test_party)
		first.disabled = s.story.flag(BattleLauncher.TEST_FLAG) or in_battle
		UIKit.button(_box, "Heal party", _heal_party).disabled = s.party.is_empty() or in_battle
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
	UIKit.button(_box, "Close", close)
	_status = UIKit.label(_box, status, UIKit.BODY_SIZE, UIKit.ACCENT)
	_focus_first()


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
		Overworld.active.run_battle(setup)


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


func _focus_first() -> void:
	for c in _find_focusable(_box):
		c.grab_focus.call_deferred()
		return


func _find_focusable(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is BaseButton and not c.disabled:
			out.append(c)
		out.append_array(_find_focusable(c))
	return out
