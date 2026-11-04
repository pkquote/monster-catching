class_name Minigame
extends Control
## Base for minigame scenes. Story.start_minigame() adds the scene over the paused
## map, calls begin(params), and waits for `finished`. The result must have at
## least `won: bool` and `score: int`; the calling .dialogue script decides rewards.
##
## Add one: extend this, list it in data/minigames.json ({ id, name, scene }),
## and point a MinigameSpot's dialogue at `Story.start_minigame("<id>")`.

signal finished(result: Dictionary)


## Called once after the scene is added. Override to start the game.
func begin(_params: Dictionary) -> void:
	pass
