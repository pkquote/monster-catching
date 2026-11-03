extends Control
## Stand-in for the overworld until M3. Shows the current playthrough and lets
## the player save, open settings, or quit to the title. Autosaves on entry.

var _playtime: Label
var _status: Label


func _ready() -> void:
	if not GameState.has_game():
		SceneRouter.goto.call_deferred(SceneRouter.TITLE)
		return
	var s := GameState.current
	var col := UIKit.screen(self, "Welcome, %s" % s.player_name, 320)
	UIKit.label(col, "Location: %s" % s.location, UIKit.BODY_SIZE, UIKit.MUTED)
	_playtime = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.MUTED)
	var party := "Party: empty (creatures arrive with the overworld in M3)" if s.party.is_empty() \
		else "Party: %d creature(s)" % s.party.size()
	UIKit.label(col, party, UIKit.BODY_SIZE, UIKit.MUTED, true)
	UIKit.spacer(col, 6)
	var save := UIKit.button(col, "Save game", _save)
	UIKit.button(col, "Settings", func(): SceneRouter.goto(SceneRouter.SETTINGS, {"return_to": SceneRouter.WORLD}))
	UIKit.button(col, "Quit to title", _quit_to_title)
	_status = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.ACCENT)
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
