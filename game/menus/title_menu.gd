extends Control
## Resume (last save) · New Game · Load Game · Settings · Quit

var resume_button: Button


func _ready() -> void:
	var col := UIKit.screen(self, "Monster Catching Game")
	var resume_path := GameState.resume_path()
	if resume_path != "":
		var r := GameState.store.read(resume_path)
		if r.ok:
			var s: SaveGame = r.save
			resume_button = UIKit.button(col, "Resume  ·  %s  ·  %s" % [s.player_name, SaveGame.format_playtime(s.playtime_sec)],
				func(): _load(resume_path))
	var new_button := UIKit.button(col, "New Game", func(): SceneRouter.goto(SceneRouter.NEW_GAME))
	UIKit.button(col, "Load Game", func(): SceneRouter.goto(SceneRouter.LOAD_GAME))
	UIKit.button(col, "Settings", func(): SceneRouter.goto(SceneRouter.SETTINGS, {"return_to": SceneRouter.TITLE}))
	UIKit.button(col, "Quit", func(): get_tree().quit())
	(resume_button if resume_button != null else new_button).grab_focus.call_deferred()


func _load(path: String) -> void:
	var err := GameState.load_from(path)
	if err == "":
		SceneRouter.goto(SceneRouter.WORLD)
	else:
		push_warning("Resume failed: " + err)
		SceneRouter.goto(SceneRouter.LOAD_GAME)
