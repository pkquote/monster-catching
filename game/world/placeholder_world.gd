extends Control
## Stand-in for the overworld until M3. Shows the playthrough and party, and offers
## save / settings / quit plus debug tools: a test party and test battles.
## Autosaves on entry (including when returning from a battle).

const WILD_ENCOUNTER := "route_01_grass"
const TAMERS := [["scout_ana", "Scout Ana (1v1)"], ["rival_01", "Rival (2v2)"]]

var _playtime: Label
var _status: Label
var _overlay: Control
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not GameState.has_game():
		SceneRouter.goto.call_deferred(SceneRouter.TITLE)
		return
	_rng.randomize()
	var s := GameState.current
	var col := UIKit.screen(self, "Welcome, %s" % s.player_name, 600)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	col.add_child(columns)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(300, 0)
	columns.add_child(info)
	UIKit.label(info, "Location: %s" % s.location, UIKit.BODY_SIZE, UIKit.MUTED)
	_playtime = UIKit.label(info, "", UIKit.BODY_SIZE, UIKit.MUTED)
	UIKit.label(info, "Money: %d" % s.money, UIKit.BODY_SIZE, UIKit.MUTED)
	UIKit.spacer(info, 4)
	UIKit.label(info, "Party", UIKit.HEADING_SIZE, UIKit.ACCENT)
	if s.party.is_empty():
		UIKit.label(info, "Empty. Starters arrive with the overworld (M3); use Get test party for now.",
			UIKit.BODY_SIZE, UIKit.MUTED, true)
	for c: CreatureInstance in s.party:
		var line := "%s  Lv %d   HP %d/%d   EN %d/%d   Bond %+d" % [c.display_name(DataRegistry.db), c.level,
			c.hp, c.max_hp(DataRegistry.db), c.energy, c.max_energy(DataRegistry.db), c.bond]
		if c.status != "":
			line += "   " + DataRegistry.db.status(c.status).name.to_upper()
		UIKit.label(info, line, 11, UIKit.TEXT if c.hp > 0 else UIKit.DANGER)
	if not s.storage.is_empty():
		UIKit.label(info, "+ %d in storage" % s.storage.size(), 11, UIKit.MUTED)
	if not s.inventory.is_empty():
		var bag := PackedStringArray()
		for id in s.inventory:
			bag.append("%s ×%d" % [DataRegistry.db.item(id).name, s.inventory[id]])
		UIKit.label(info, "Bag: " + ", ".join(bag), 11, UIKit.MUTED, true)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(220, 0)
	actions.add_theme_constant_override("separation", 4)
	columns.add_child(actions)
	var save := UIKit.button(actions, "Save game", _save)
	UIKit.button(actions, "Settings", func(): SceneRouter.goto(SceneRouter.SETTINGS, {"return_to": SceneRouter.WORLD}))
	UIKit.button(actions, "Quit to title", _quit_to_title)
	UIKit.spacer(actions, 4)
	UIKit.label(actions, "Debug (until M3)", UIKit.BODY_SIZE, UIKit.MUTED)
	if not s.flags.get(BattleLauncher.TEST_FLAG, false):
		UIKit.button(actions, "Get test party", _grant_test_party)
	if not s.party.is_empty():
		UIKit.button(actions, "Heal party", _heal_party)
		var can_fight := BattleLauncher.healthy_count(s) > 0
		UIKit.button(actions, "Wild battle (Route 1)", _start_wild).disabled = not can_fight
		for t in TAMERS:
			var tamer_id: String = t[0]
			UIKit.button(actions, t[1], func(): _start_tamer(tamer_id)).disabled = not can_fight
		UIKit.button(actions, "Custom battle...", _open_custom_battle).disabled = not can_fight
	_status = UIKit.label(actions, "", UIKit.BODY_SIZE, UIKit.ACCENT)
	GameState.enter_world()
	_status.text = "Autosaved."
	save.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if _playtime != null and GameState.has_game():
		_playtime.text = "Playtime: %s" % SaveGame.format_playtime(GameState.current.playtime_sec)


func _save() -> void:
	_status.text = "Saved." if GameState.save_manual() != "" else "Couldn't save!"


func _quit_to_title() -> void:
	GameState.autosave()
	GameState.close_game()
	SceneRouter.goto(SceneRouter.TITLE)


func _grant_test_party() -> void:
	BattleLauncher.grant_test_party(DataRegistry.db, GameState.current)
	GameState.autosave()
	get_tree().reload_current_scene()


func _heal_party() -> void:
	for c: CreatureInstance in GameState.current.party:
		c.heal_full(DataRegistry.db)
	GameState.autosave()
	get_tree().reload_current_scene()


func _start_wild() -> void:
	var pack := BattleLauncher.roll_wild_pack(DataRegistry.db, WILD_ENCOUNTER, _rng)
	var names := ", ".join(pack.map(func(c: CreatureInstance): return "%s Lv %d" % [c.display_name(DataRegistry.db), c.level]))
	var n = await _ask_field_count(pack.size(), "Wild %s!" % names)
	if n != null:
		_go(BattleLauncher.wild_setup(GameState.current, pack, n))


func _start_tamer(tamer_id: String) -> void:
	var t := DataRegistry.db.tamer(tamer_id)
	var n = await _ask_field_count(t.max_active, "%s fields %d at a time." % [t.name, t.max_active])
	if n != null:
		_go(BattleLauncher.tamer_setup(DataRegistry.db, GameState.current, tamer_id, n))


func _go(setup: BattleSetup) -> void:
	GameState.leave_world()
	SceneRouter.goto(SceneRouter.BATTLE, {"setup": setup, "return_to": SceneRouter.WORLD})


## Debug panel: pick any format (1v3, 3v1...), wild or tamer, and the foes' level.
func _open_custom_battle() -> void:
	var box := _open_overlay()
	UIKit.label(box, "Custom battle", UIKit.HEADING_SIZE, UIKit.ACCENT)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	var most := mini(BattleLauncher.MAX_SIDE, BattleLauncher.healthy_count(GameState.current))
	var mine := _option_row(grid, "You field", range(1, most + 1).map(func(i): return str(i)), most - 1)
	var theirs := _option_row(grid, "Foes", range(1, BattleLauncher.MAX_SIDE + 1).map(func(i): return str(i)), 0)
	var kind := _option_row(grid, "Foe kind", ["Wild", "Tamer"], 0)
	UIKit.label(grid, "Foe level")
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = DataRegistry.db.balance.level_cap
	level.value = BattleLauncher.party_level(GameState.current)
	grid.add_child(level)
	var note := UIKit.label(box, "", 11, UIKit.MUTED)
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
	UIKit.label(box, "Foes are random species. Wild foes can be caught; tamers use the tactician AI.",
		11, UIKit.MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	UIKit.button(row, "Start", func():
		var setup := BattleLauncher.custom_setup(DataRegistry.db, GameState.current, mine.selected + 1,
			theirs.selected + 1, int(level.value), kind.selected == 0, _rng)
		_close_overlay()
		_go(setup))
	UIKit.button(row, "Cancel", _close_overlay)
	mine.grab_focus.call_deferred()


func _option_row(grid: GridContainer, text: String, choices: Array, selected: int) -> OptionButton:
	UIKit.label(grid, text)
	var o := OptionButton.new()
	for c in choices:
		o.add_item(c)
	o.selected = selected
	grid.add_child(o)
	return o


## Dimmed full-screen overlay with a centred panel. Returns the panel's column.
func _open_overlay() -> VBoxContainer:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := UIKit.panel(center, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	return box


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


## Asks how many creatures to field (skipped when there's only one choice).
## Returns the count, or null if cancelled.
func _ask_field_count(format_size: int, intro: String) -> Variant:
	var most := BattleLauncher.max_fieldable(GameState.current, format_size)
	if most <= 1:
		return 1
	var box := _open_overlay()
	UIKit.label(box, intro, UIKit.BODY_SIZE, UIKit.TEXT)
	UIKit.label(box, "Send out how many? Fewer than the foe makes you the Underdog.", 11, UIKit.MUTED)
	var menu := CommandMenu.new()
	box.add_child(menu)
	var options: Array = []
	for i in range(most, 0, -1):
		var note := "" if i >= format_size else "  (Underdog)"
		options.append({"label": "%d creature%s%s" % [i, "" if i == 1 else "s", note], "value": i})
	var n = await menu.choose("", options, true, 1)
	_close_overlay()
	return n
