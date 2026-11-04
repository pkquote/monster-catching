class_name Emote
extends Node2D
## A speech-bubble mark ("!", "?", "...") that pops up over an actor for a moment.

const SECONDS := 0.6

var kind := "!"


## Shows `kind` over `actor` for `seconds` (awaitable). Instant in test mode.
static func show_over(actor: Node2D, kind_: String, seconds := SECONDS) -> void:
	if Overworld.instant:
		return
	var e := Emote.new()
	e.kind = kind_
	e.position = Vector2(0, -30)
	e.z_index = 20
	actor.add_child(e)
	await actor.get_tree().create_timer(seconds).timeout
	e.queue_free()


func _draw() -> void:
	draw_rect(Rect2(-9, -10, 18, 16), Color("f0f0f0"))
	draw_rect(Rect2(-9, -10, 18, 16), Color("2b2b2b"), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-7, 3), kind, HORIZONTAL_ALIGNMENT_CENTER, 14, 12, Color("2b2b2b"))
