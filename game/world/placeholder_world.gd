extends Control
## Stand-in for the overworld until M3. Shows the playthrough and party, and offers
## save / settings / quit. Debug tools (test party, test battles) are in the F1
## DebugMenu overlay. Autoloads on entry (including when returning from a battle).

var _playtime: Label
var _status: Label


func _ready() -> void:
	if not GameState.has_game():
		SceneRouter.goto.call_deferred(SceneRouter.TITLE)
		return
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
		var hint := "Empty. Starters arrive with the overworld (M3)."
		if OS.is_debug_build():
			hint += " Press F1 for a test party."
		UIKit.label(info, hint, UIKit.BODY_SIZE, UIKit.MUTED, true)
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
	if OS.is_debug_build():
		UIKit.spacer(actions, 4)
		UIKit.label(actions, "F1: debug tools", UIKit.BODY_SIZE, UIKit.MUTED)
	_status = UIKit.label(actions, "", UIKit.BODY_SIZE, UIKit.ACCENT)
	GameState.enter_world()
	_status.text = "Autosaved."
	# The debug menu rebuilds this screen while it's open; leave its focus alone.
	if not DebugMenu.is_open():
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
