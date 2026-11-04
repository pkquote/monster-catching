class_name FieldView
extends HBoxContainer
## One side's field-state chips ("Soaked ×2 · 3") plus its Underdog badge, after a
## "Your field:" / "Foe field:" tag (shown only when there's something to show).
## Keeps its own mirror of the states so playback can show them change event by event.

var side := 0
## Ordered: Array of { id, stacks, turns }
var states: Array = []
var underdog_text := ""
var _db: Database


func setup(p_side: int, db: Database) -> void:
	side = p_side
	_db = db
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func applied(state: String, stacks: int, turns: int) -> void:
	for s in states:
		if s.id == state:
			s.stacks = stacks
			s.turns = turns
			_rebuild()
			return
	states.append({"id": state, "stacks": stacks, "turns": turns})
	_rebuild()


func removed(state: String) -> void:
	states = states.filter(func(s): return s.id != state)
	_rebuild()


## Re-sync with the engine (picks up end-of-round countdowns).
func sync(field: Field) -> void:
	states = field.snapshot()
	_rebuild()


func set_underdog(bonus_actions: int, ratio: float) -> void:
	underdog_text = "" if ratio <= 1.0 else "UNDERDOG" + (" +%d" % bonus_actions if bonus_actions > 0 else "")
	_rebuild()


func newest_color() -> Color:
	return TypeColors.state_color(states.back().id) if not states.is_empty() else Color(0, 0, 0, 0)


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	# The foe's chips sit in the top-left corner, away from its creatures, so say whose they are.
	if underdog_text != "" or not states.is_empty():
		var tag := Label.new()
		tag.text = "Foe field:" if side == 1 else "Your field:"
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", UIKit.TEXT)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		tag.add_theme_constant_override("outline_size", 3)
		add_child(tag)
	if underdog_text != "":
		add_child(_chip(underdog_text, UIKit.ACCENT, Color(0, 0, 0)))
	for s in states:
		var text := _db.field_state(s.id).name
		if int(s.stacks) > 1:
			text += " ×%d" % s.stacks
		text += " · %d" % s.turns
		var bg := TypeColors.state_color(s.id)
		add_child(_chip(text, bg, Color(0, 0, 0) if bg.get_luminance() > 0.45 else Color(1, 1, 1)))


static func _chip(text: String, bg: Color, fg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(4)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", fg)
	panel.add_child(l)
	return panel
