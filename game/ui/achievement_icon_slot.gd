class_name AchievementIconSlot
extends Control
## Placeholder achievement icon: a rounded square in a per-kind colour with one letter in the
## centre; greyed while the achievement is locked. Real art replaces the drawing in M8.

const KIND_COLORS := {
	"counter": Color("3f8fe0"),
	"codex": Color("b45be0"),
	"flag": Color("f2cf3d"),
	"creature": Color("5bb85a"),
	"unknown": Color("9aa0ae"),
}
const KIND_LETTERS := {"counter": "C", "codex": "D", "flag": "F", "creature": "M"}

const CORNER_RADIUS := 6
const INITIAL_COLOR := Color("1b1f2a")

var kind: String = ""
var icon_size: int = 48
var unlocked: bool = true


func configure(p_kind: String, p_icon_size: int = 48, p_unlocked: bool = true) -> void:
	kind = p_kind
	icon_size = p_icon_size
	unlocked = p_unlocked
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


func letter() -> String:
	return KIND_LETTERS.get(kind, "?")


func fill_color() -> Color:
	var base: Color = KIND_COLORS.get(kind, KIND_COLORS["unknown"])
	if unlocked:
		return base
	return Color.from_hsv(base.h, base.s * 0.15, base.v * 0.55)


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill_color()
	box.set_corner_radius_all(CORNER_RADIUS)
	draw_style_box(box, Rect2(Vector2.ZERO, Vector2(icon_size, icon_size)))
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(8, roundi(icon_size * 0.5))
	var text_size: Vector2 = font.get_string_size(letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := Vector2((icon_size - text_size.x) / 2.0,
			(icon_size - text_size.y) / 2.0 + font.get_ascent(font_size))
	draw_string(font, baseline, letter(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INITIAL_COLOR)
