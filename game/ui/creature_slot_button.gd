class_name CreatureSlotButton
extends Button
## One focusable creature slot for the Box and Party screens: a sprite placeholder in a small square,
## a status mark (burn initial, "F" for fainted), a held-item dot, and the looks for an empty slot,
## a marked creature (accent corner tick) and a carried one (dimmed, its spot left behind).

const EMPTY_BG := Color("1f2431")
const FILLED_BG := Color("2e3547")
const EMPTY_LINE := Color("3a4258")

var _db: Database
var _creature: CreatureInstance
var _marked := false
var _carried := false
var _count := 0
var _sprite: CreatureSpriteSlot
var _badge: Label
var _count_label: Label
var _overlay: Control


## A null creature makes an empty slot.
func configure(db: Database, creature: CreatureInstance, p_size: int = 36) -> void:
	_db = db
	_creature = creature
	custom_minimum_size = Vector2(p_size, p_size)
	size = custom_minimum_size
	clip_text = true
	focus_mode = Control.FOCUS_ALL
	text = ""
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_sprite = null
	_apply_styles()
	if creature != null:
		_sprite = CreatureSpriteSlot.new()
		_sprite.configure(db, creature.species, p_size - 8)
		_sprite.position = Vector2(4, 4)
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_sprite)
	_badge = _tiny_label(Vector2(2, 0), UIKit.ACCENT)
	_badge.text = badge_text()
	_count_label = _tiny_label(Vector2(p_size - 20, p_size - 13), UIKit.TEXT)
	_count_label.size.x = 18
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_refresh_state()


func creature() -> CreatureInstance:
	return _creature


func set_marked(on: bool) -> void:
	_marked = on
	_refresh_state()


func set_carried(on: bool) -> void:
	_carried = on
	_refresh_state()


func is_marked() -> bool:
	return _marked


func is_carried() -> bool:
	return _carried


## The status initial, "F" when fainted, "" otherwise.
func badge_text() -> String:
	if _creature == null:
		return ""
	if _creature.hp <= 0:
		return "F"
	if _creature.status != "" and _db != null:
		var def := _db.status(_creature.status)
		return def.name.substr(0, 1).to_upper() if def != null else "!"
	return ""


## An "xN" badge, hidden for fewer than two.
func set_count_badge(n: int) -> void:
	_count = n
	_refresh_state()


func count_text() -> String:
	return "x%d" % _count if _count >= 2 else ""


func _refresh_state() -> void:
	_apply_styles()
	if _sprite != null:
		_sprite.modulate = Color(1, 1, 1, 0.3) if _carried else Color.WHITE
	if _count_label != null:
		_count_label.text = count_text()
	if _overlay != null:
		_overlay.queue_redraw()


func _draw_overlay() -> void:
	if _creature == null:
		return
	var w := custom_minimum_size.x
	if _marked:
		_overlay.draw_colored_polygon(PackedVector2Array([Vector2(w - 11, 0), Vector2(w, 0), Vector2(w, 11)]), UIKit.ACCENT)
	if _creature.held_item != "":
		_overlay.draw_circle(Vector2(5, custom_minimum_size.y - 5), 2.5, UIKit.TEXT)
	if _count >= 2:
		_overlay.draw_rect(Rect2(w - 20, custom_minimum_size.y - 13, 20, 13), Color(0, 0, 0, 0.6))


func _tiny_label(at: Vector2, colour: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("outline_size", 0)
	add_child(l)
	return l


func _apply_styles() -> void:
	var filled := _creature != null
	var base := _style(FILLED_BG if filled else EMPTY_BG, EMPTY_LINE if not filled else Color("4a5472"), 1)
	if _marked:
		base = _style(Color("4a4130"), UIKit.ACCENT, 2)
	add_theme_stylebox_override("normal", base)
	add_theme_stylebox_override("hover", _style(Color("3a4360"), UIKit.MUTED, 1))
	add_theme_stylebox_override("pressed", _style(Color("3a4360"), UIKit.ACCENT, 2))
	add_theme_stylebox_override("focus", _style(Color(1, 1, 1, 0.08), UIKit.ACCENT, 2))
	add_theme_stylebox_override("disabled", base)


static func _style(bg: Color, line: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(width)
	s.set_corner_radius_all(4)
	return s
