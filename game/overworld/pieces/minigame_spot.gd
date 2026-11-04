@tool
class_name MinigameSpot
extends Piece
## Accept while facing it: runs `title` from `dialogue`; that script starts the
## minigame (`$> Story.start_minigame("quick_draw")`) and decides any reward from
## Story.last_minigame(). Usually placed on an NPC's counter or table.

## Minigame id from data/minigames.json (checked by the map checker).
@export var minigame := ""
@export_file("*.dialogue") var dialogue := ""
@export var title := ""


func on_interact(w: Overworld) -> void:
	w.say(dialogue, title)


func marker_color() -> Color:
	return Color("c080ff")


func marker_label() -> String:
	return "minigame: " + minigame
