class_name CreatureCard
extends PanelContainer
## One creature at a glance: sprite, name, level, types, stat radar, HP/Stamina bars, moves, the active
## passive and the held item. Built from a CreatureInstance, so it suits party members, box creatures
## and the debug gallery alike. Long names are ellipsised; nothing spills outside the card.

## Short enough for the F1 gallery page, which the debug menu caps at 320px with its title.
const SIZE := Vector2(300, 272)
const INNER_W := 284
const SPRITE := 36

var _header: Label
var _moves: Array[Label] = []
var _passive: Label
var _held: Label


## "Name  Lv N".
func header_text() -> String:
	return _header.text if _header != null else ""


func move_texts() -> Array:
	return _moves.map(func(l: Label): return l.text)


func passive_text() -> String:
	return _passive.text if _passive != null else ""


func held_text() -> String:
	return _held.text if _held != null else ""


## An empty card (nothing under the cursor): the same panel with `text` centred.
func show_empty(text := "Empty") -> void:
	_reset()
	_header = _line(self, text, UIKit.MUTED, 13)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _reset() -> void:
	for child in get_children():
		remove_child(child)  # now, not at the end of the frame, so a rebuild never doubles up
		child.queue_free()
	_moves.clear()
	_header = null
	_passive = null
	_held = null
	custom_minimum_size = SIZE
	size = SIZE
	clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.PANEL
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)


func show_creature(db: Database, c: CreatureInstance) -> void:
	_reset()

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var sprite := CreatureSpriteSlot.new()
	sprite.configure(db, c.species, SPRITE)
	top.add_child(sprite)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 2)
	top.add_child(names)
	_header = _line(names, "%s  Lv %d" % [c.display_name(db), c.level], UIKit.TEXT, 13)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	names.add_child(chips)
	for type_id: String in c.species_def(db).types:
		chips.add_child(_chip(type_id.capitalize(), TypeColors.type_color(type_id)))

	var radar := StatRadar.new()
	radar.configure(db, c, Vector2(INNER_W, 112))
	col.add_child(radar)
	var bars := ResourceBars.new()
	bars.configure(c.hp, c.max_hp(db), c.energy, c.max_energy(db), INNER_W)
	col.add_child(bars)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	col.add_child(grid)
	for id: String in c.moves:
		var def := db.move(id)
		var l := _line(grid, def.name if def != null else id, UIKit.TEXT, 10)
		l.custom_minimum_size.x = (INNER_W - 8) / 2.0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_moves.append(l)

	var passive_id := Passives.active_id(c)
	var passive_def := db.passive(passive_id) if passive_id != "" else null
	_passive = _line(col, "Passive: " + (passive_def.name if passive_def != null else "none"), UIKit.MUTED, 10)
	var held := HeldItems.def_of(db, c)
	var held_name := "none" if c.held_item.is_empty() else (held.name if held != null else c.held_item)
	_held = _line(col, "Held: " + held_name, UIKit.MUTED, 10)


func _line(parent: Node, text: String, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _chip(text: String, bg: Color) -> PanelContainer:
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
	l.add_theme_color_override("font_color", Color(0, 0, 0) if bg.get_luminance() > 0.45 else Color(1, 1, 1))
	panel.add_child(l)
	return panel
