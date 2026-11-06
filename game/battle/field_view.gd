class_name FieldView
extends HBoxContainer
## One side's field-state chips ("Soaked ×2 · 3") plus its Underdog badge, after a
## "Your field:" / "Foe field:" tag (shown only when there's something to show).
## Each chip has a small label with the state's effect (generated from its data by
## EffectText.short), under the chip for the foe and over it for you. Stacks don't change a state's
## effect, so the text never does. A side normally holds one state (balance.max_field_states). The
## foe's view sits in the stage's top-left corner; yours is pinned to the bottom-right (anchor_bottom_right).
## Keeps its own mirror of the states so playback can show them change event by event.

## Width the effect text wraps at.
const EFFECT_WIDTH := 104

var side := 0
## Ordered: Array of { id, stacks, turns }
var states: Array = []
var underdog_text := ""
var _db: Database
var _anchor := Vector2.INF  # bottom-right corner to keep the view pinned to; INF = not pinned


func setup(p_side: int, db: Database) -> void:
	side = p_side
	_db = db
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Keeps the view's bottom-right corner at `corner` (stage coordinates) as its content changes size.
func anchor_bottom_right(corner: Vector2) -> void:
	_anchor = corner
	_relayout()


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


## The effect text under (or over) each state's chip, in order. For tests.
func effect_labels() -> Array:
	var out: Array = []
	for l: Node in find_children("EffectLabel", "Label", true, false):
		out.append((l as Label).text)
	return out


func newest_color() -> Color:
	return TypeColors.state_color(states.back().id) if not states.is_empty() else Color(0, 0, 0, 0)


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)  # now, not at the end of the frame: the deferred relayout must not count them
		c.queue_free()
	# Your view hangs from the stage's bottom edge, so its tag and badge line up with the chip at the bottom.
	var valign := Control.SIZE_SHRINK_END if side == 0 else Control.SIZE_SHRINK_BEGIN
	# The foe's chips sit in the top-left corner, away from its creatures, so say whose they are.
	if underdog_text != "" or not states.is_empty():
		var tag := Label.new()
		tag.text = "Foe field:" if side == 1 else "Your field:"
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", UIKit.TEXT)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		tag.add_theme_constant_override("outline_size", 3)
		tag.size_flags_vertical = valign
		add_child(tag)
	if underdog_text != "":
		var badge := _chip(underdog_text, UIKit.ACCENT, Color(0, 0, 0))
		badge.size_flags_vertical = valign  # not stretched to the tallest column
		add_child(badge)
	for s in states:
		var text := _db.field_state(s.id).name
		if int(s.stacks) > 1:
			text += " ×%d" % s.stacks
		text += " · %d" % s.turns
		var bg := TypeColors.state_color(s.id)
		var chip := _chip(text, bg, Color(0, 0, 0) if bg.get_luminance() > 0.45 else Color(1, 1, 1))
		var effect := EffectText.short(_db, _db.field_state(s.id).passive)
		if effect == "—":
			chip.size_flags_vertical = valign
			add_child(chip)
			continue
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.size_flags_vertical = valign
		if side == 0:  # the bottom edge has no room under the chip
			column.add_child(_effect_label(effect))
			column.add_child(chip)
		else:
			column.add_child(chip)
			column.add_child(_effect_label(effect))
		add_child(column)
	_relayout.call_deferred()


## Shrinks the view to its contents again after the chips changed.
func _relayout() -> void:
	if is_inside_tree():
		reset_size()
		if _anchor != Vector2.INF:
			position = _anchor - size


func _effect_label(text: String) -> Label:
	var l := Label.new()
	l.name = "EffectLabel"
	l.text = text
	l.custom_minimum_size = Vector2(EFFECT_WIDTH, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", UIKit.TEXT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	return l


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
