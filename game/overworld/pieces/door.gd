@tool
class_name Door
extends Piece
## Walk into it to go to `target_spawn` on map `target_map`.

## Map id (file name in res://game/maps without .tscn).
@export var target_map := "":
	set(v):
		target_map = v
		queue_redraw()
## Spawn id on the target map.
@export var target_spawn := ""


func on_enter(world: Node) -> void:
	world.change_map(target_map, target_spawn)


func marker_color() -> Color:
	return Color("f0a040")


func marker_label() -> String:
	return "→ " + target_map
