class_name ItemIconSlot
extends Control
## Placeholder item icon: a rounded square in a per-category colour with the category's
## initial in the centre. Real art replaces the drawing in M8.

const CATEGORY_COLORS := {
	"capture": Color("e2675c"),
	"heal": Color("5bb85a"),
	"battle": Color("e8883c"),
	"key": Color("f2cf3d"),
	"training": Color("3f8fe0"),
	"held": Color("b45be0"),
	"unknown": Color("9aa0ae"),
}

const CORNER_RADIUS := 6
const INITIAL_COLOR := Color("1b1f2a")

var category: String = ""
var icon_size: int = 48


static func initial_for(p_category: String) -> String:
	if p_category.is_empty():
		return "?"
	return p_category.substr(0, 1).to_upper()


func configure(p_category: String, p_icon_size: int = 48) -> void:
	category = p_category
	icon_size = p_icon_size
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


func fill_color() -> Color:
	return CATEGORY_COLORS.get(category, CATEGORY_COLORS["unknown"])


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill_color()
	box.set_corner_radius_all(CORNER_RADIUS)
	draw_style_box(box, Rect2(Vector2.ZERO, Vector2(icon_size, icon_size)))
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(8, roundi(icon_size * 0.5))
	var letter: String = initial_for(category)
	var text_size: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline: Vector2 = Vector2((icon_size - text_size.x) / 2.0,
			(icon_size - text_size.y) / 2.0 + font.get_ascent(font_size))
	draw_string(font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INITIAL_COLOR)
