class_name CreatureView
extends Control
## One battler on the stage: placeholder sprite plus name, HP (and energy for the
## player's side) and status. Animations are awaitable so playback can sequence them.

const SPRITE := 46
const SIZE := Vector2(170, 52)
const BAR_W := 104

var bid := -1
var side := 0
var hp := 0
var max_hp := 1
var energy := 0
var max_energy := 1
var status := ""
var highlighted := false

var _types: PackedStringArray
var _initial := "?"
var _name_label: Label
var _hp_label: Label
var _status_label: Label
var _flash := 0.0


func setup(p_bid: int, p_side: int, display_name: String, level: int, types: PackedStringArray) -> void:
	bid = p_bid
	side = p_side
	_types = types
	_initial = display_name.trim_prefix("Wild ").trim_prefix("Foe ").substr(0, 1)
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = _label(Vector2(SPRITE + 8, 0), "%s  Lv %d" % [display_name, level], 11)
	_hp_label = _label(Vector2(SPRITE + 8, 30), "", 9)
	_status_label = _label(Vector2(SPRITE + 8, 40), "", 9)
	_status_label.add_theme_color_override("font_color", UIKit.ACCENT)


func set_level(display_name: String, level: int) -> void:
	_name_label.text = "%s  Lv %d" % [display_name, level]


func set_hp(value: int, maximum: int, animate := true) -> void:
	var from := hp
	max_hp = maxi(1, maximum)
	if not animate or not is_inside_tree():
		hp = value
		_refresh_labels()
		queue_redraw()
		return
	var t := create_tween()
	t.tween_method(func(v: float):
		hp = roundi(v)
		_refresh_labels()
		queue_redraw(), float(from), float(value), _dur(0.35))
	await t.finished


func set_energy(value: int, maximum: int) -> void:
	energy = value
	max_energy = maxi(1, maximum)
	_refresh_labels()
	queue_redraw()


func set_status(id: String, label: String) -> void:
	status = id
	_status_label.text = label.to_upper() if id != "" else ""


func set_highlight(on: bool) -> void:
	highlighted = on
	queue_redraw()


func flash() -> void:
	var t := create_tween()
	t.tween_method(func(v: float):
		_flash = v
		queue_redraw(), 1.0, 0.0, _dur(0.3))
	await t.finished


func nudge() -> void:
	var dir := Vector2(14, -6) if side == 0 else Vector2(-14, 6)
	var home := position
	var t := create_tween()
	t.tween_property(self, "position", home + dir, _dur(0.08))
	t.tween_property(self, "position", home, _dur(0.12))
	await t.finished


func appear() -> void:
	modulate.a = 0.0
	var home := position
	position = home + Vector2(0, -16)
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, _dur(0.25))
	t.tween_property(self, "position", home, _dur(0.25))
	await t.finished


func vanish() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, _dur(0.35))
	await t.finished
	visible = false


## Capture sequence: shrink, `shakes` wobbles, then either stay gone or pop back out.
func capture_sequence(shakes: int, success: bool) -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(0.2, 0.2), _dur(0.25))
	for i in shakes:
		t.tween_property(self, "rotation", 0.25, _dur(0.12))
		t.tween_property(self, "rotation", -0.25, _dur(0.12))
	t.tween_property(self, "rotation", 0.0, _dur(0.08))
	if not success:
		t.tween_property(self, "scale", Vector2.ONE, _dur(0.15))
	await t.finished


func _draw() -> void:
	var center := Vector2(SPRITE / 2.0, SPRITE / 2.0 + 2)
	var main := TypeColors.type_color(_types[0] if _types.size() > 0 else "")
	if highlighted:
		draw_circle(center, SPRITE / 2.0 + 4, UIKit.ACCENT)
	if _types.size() > 1:
		draw_circle(center, SPRITE / 2.0, TypeColors.type_color(_types[1]))
		draw_circle(center, SPRITE / 2.0 - 5, main)
	else:
		draw_circle(center, SPRITE / 2.0, main)
	if _flash > 0.0:
		draw_circle(center, SPRITE / 2.0, Color(1, 1, 1, _flash * 0.8))
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(_initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string(font, center + Vector2(-text_size.x / 2.0, 8), _initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(0, 0, 0, 0.65))
	# Bars
	var x := SPRITE + 8.0
	_bar(Vector2(x, 16), float(hp) / max_hp, _hp_color(float(hp) / max_hp), 6)
	if side == 0:
		_bar(Vector2(x, 24), float(energy) / max_energy, Color("5fa8e8"), 3)


func _bar(at: Vector2, fill: float, color: Color, height: int) -> void:
	draw_rect(Rect2(at, Vector2(BAR_W, height)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(at, Vector2(BAR_W * clampf(fill, 0.0, 1.0), height)), color)


static func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color("6cc96a")
	if ratio > 0.2:
		return Color("e8c04a")
	return Color("e2675c")


func _refresh_labels() -> void:
	if side == 0:
		_hp_label.text = "HP %d/%d   EN %d/%d" % [hp, max_hp, energy, max_energy]
	else:
		_hp_label.text = ""


func _label(at: Vector2, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.position = at
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UIKit.TEXT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l


static func _dur(seconds: float) -> float:
	return BattlePlayback.scaled(seconds)
