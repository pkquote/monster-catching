@tool
class_name Spawn
extends Piece
## An arrival point: doors, new games and defeat respawns place the player here.

@export var id := "":
	set(v):
		id = v
		queue_redraw()


func is_marker() -> bool:
	return true


func marker_color() -> Color:
	return Color("50c0f0")


func marker_label() -> String:
	return "spawn: " + id
