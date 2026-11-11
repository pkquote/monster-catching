class_name CreatureSpriteSlot
extends Control
## Placeholder creature sprite: a circle in the creature's type colours (a second ring for a dual
## type) with the species initial in the centre. The battle's creature view draws through the same
## helper. Real art replaces `draw_placeholder` in M8.

const NO_TYPE := Color("9aa0ae")

var species: String = ""
var types: PackedStringArray = PackedStringArray()
var initial: String = "?"
var sprite_size: int = 48


static func initial_for(p_name: String) -> String:
	return p_name.substr(0, 1) if not p_name.is_empty() else "?"


static func body_color(p_types: PackedStringArray) -> Color:
	return TypeColors.type_color(p_types[0]) if p_types.size() > 0 else NO_TYPE


## The outer ring's colour: the second type's, or fully transparent for one or no type.
static func ring_color(p_types: PackedStringArray) -> Color:
	return TypeColors.type_color(p_types[1]) if p_types.size() > 1 else Color(0, 0, 0, 0)


static func draw_placeholder(canvas: CanvasItem, center: Vector2, radius: float,
		p_types: PackedStringArray, p_initial: String, flash := 0.0) -> void:
	var main := body_color(p_types)
	if p_types.size() > 1:
		canvas.draw_circle(center, radius, ring_color(p_types))
		canvas.draw_circle(center, radius - 5.0 * radius / 23.0, main)
	else:
		canvas.draw_circle(center, radius, main)
	if flash > 0.0:  # a hit flash sits over the body, under the letter
		canvas.draw_circle(center, radius, Color(1, 1, 1, flash * 0.8))
	var font := ThemeDB.fallback_font
	var font_size := maxi(8, roundi(radius * 22.0 / 23.0))
	var text_size := font.get_string_size(p_initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	canvas.draw_string(font, center + Vector2(-text_size.x / 2.0, font_size * 8.0 / 22.0), p_initial,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.65))


func configure(db: Database, species_id: String, p_size: int = 48) -> void:
	species = species_id
	var def := db.creature(species_id)
	types = def.types if def != null else PackedStringArray()
	initial = initial_for(def.name if def != null else "")
	sprite_size = p_size
	custom_minimum_size = Vector2(p_size, p_size)
	queue_redraw()


func _draw() -> void:
	var r := sprite_size / 2.0
	draw_placeholder(self, Vector2(r, r), r, types, initial)
