@tool
class_name Trigger
extends Piece
## Runs `title` from `dialogue` when the player's feet enter any of its tiles.
## `requires_flag` / `blocks_flag` gate it on story flags; `once` makes it run a
## single time per playthrough.

@export_file("*.dialogue") var dialogue := ""
@export var title := ""
@export var once := false
## Only fires while this flag is set ("" = always).
@export var requires_flag := ""
## Never fires while this flag is set ("" = never blocked).
@export var blocks_flag := ""
@export var size := Vector2i.ONE:
	set(v):
		size = Vector2i(maxi(1, v.x), maxi(1, v.y))
		size_tiles = size
		queue_redraw()


func _init() -> void:
	size_tiles = size


func can_fire() -> bool:
	if requires_flag != "" and not Story.flag(requires_flag):
		return false
	if blocks_flag != "" and Story.flag(blocks_flag):
		return false
	return not (once and Story.is_done(save_key()))


func on_enter(w: Overworld) -> void:
	if not can_fire():
		return
	if once:
		Story.mark_done(save_key())
	w.say(dialogue, title)  # not awaited: a cutscene may change map and free this trigger


func marker_color() -> Color:
	return Color("f060a0")


func marker_label() -> String:
	return "trigger: " + title
