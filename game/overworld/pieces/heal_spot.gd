@tool
class_name HealSpot
extends Piece
## A rest point (usually a heal-centre counter). Accept: "Rest your team?" -> full
## heal, the "rested" Bond change, and this becomes where you wake after a loss.

const DIALOGUE := "res://dialogue/common/heal.dialogue"

## Spawn id on this map where the player wakes up after losing a battle.
@export var respawn := "heal"


func on_interact(w: Overworld) -> void:
	w.say(DIALOGUE, "heal", [self])


## Called from heal.dialogue (`$> rest_here()`).
func rest_here() -> void:
	Story.heal_party()
	Story.set_last_heal(_map().map_id(), respawn)


func marker_color() -> Color:
	return Color("ff8080")


func marker_label() -> String:
	return "heal → " + respawn
