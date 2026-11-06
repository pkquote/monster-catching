class_name ResourceBars
extends Control
## HP and Stamina bars, each with its "cur / max" text. The battle's creature view shares the HP colour.

const STAMINA_COLOR := Color("5fa8e8")
const ROW_H := 14
const LABEL_W := 50
const FONT_SIZE := 9

var hp := 0
var max_hp := 0
var stamina := 0
var max_stamina := 0
var bar_width := 180


static func hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color("6cc96a")
	if ratio > 0.2:
		return Color("e8c04a")
	return Color("e2675c")


## 0..1; 0 when there is no maximum.
static func fill_fraction(current: int, maximum: int) -> float:
	if maximum <= 0:
		return 0.0
	return clampf(float(current) / float(maximum), 0.0, 1.0)


static func label(current: int, maximum: int) -> String:
	return "%d / %d" % [current, maximum]


func configure(current_hp: int, p_max_hp: int, current_stamina: int, p_max_stamina: int,
		p_width: int = 180) -> void:
	hp = current_hp
	max_hp = p_max_hp
	stamina = current_stamina
	max_stamina = p_max_stamina
	bar_width = p_width
	custom_minimum_size = Vector2(p_width, ROW_H * 2 + 2)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	_row(0, "HP", hp, max_hp, hp_color(fill_fraction(hp, max_hp)))
	_row(1, "Stamina", stamina, max_stamina, STAMINA_COLOR)


func _row(index: int, title: String, current: int, maximum: int, color: Color) -> void:
	var y := index * (ROW_H + 2)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, y + ROW_H - 3), title, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, FONT_SIZE, UIKit.TEXT)
	var text := label(current, maximum)
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var bar_x := float(LABEL_W)
	var bar_w := maxf(10.0, bar_width - LABEL_W - text_w - 6.0)
	draw_rect(Rect2(bar_x, y + 3, bar_w, ROW_H - 6), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(bar_x, y + 3, bar_w * fill_fraction(current, maximum), ROW_H - 6), color)
	draw_string(font, Vector2(bar_width - text_w, y + ROW_H - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, UIKit.TEXT)
