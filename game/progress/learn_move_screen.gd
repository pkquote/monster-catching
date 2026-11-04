class_name LearnMoveScreen
extends ProgressScreen
## Offers a pool move: replace one of the equipped moves, or keep it for later.

const KEEP := "Keep it for later"


## True if `move` was slotted. Cancel means keep.
static func run(parent: Node, c: CreatureInstance, move: String) -> bool:
	var screen := LearnMoveScreen.new()
	parent.add_child(screen)
	var slotted := await screen._ask(c, move)
	screen.close()
	return slotted


static func move_line(db: Database, id: String) -> String:
	var m := db.move(id)
	var type_def := db.type_def(m.type)
	var power := str(m.power) if m.power > 0 else "-"
	return "%s  %s %s  Power %s  Cost %d" % [m.name, type_def.name if type_def != null else m.type,
		m.category.capitalize(), power, m.cost]


func _ask(c: CreatureInstance, move: String) -> bool:
	var db := DataRegistry.db
	var m := db.move(move)
	_title.text = "%s wants to learn %s" % [c.display_name(db), m.name]
	var lines: PackedStringArray = ["New: " + move_line(db, move)]
	if m.description != "":
		lines.append(m.description)
	lines.append("Current moves:")
	var options: Array = []
	for slot in c.moves:
		lines.append(move_line(db, slot))
		options.append({"label": "Replace " + db.move(slot).name, "value": slot})
	options.append({"label": KEEP, "value": null})
	_body.text = "\n".join(lines)
	menu.button_width = 296  # two columns: the info panel above needs the height
	await get_tree().process_frame  # wrapped text needs a layout pass before it has a height
	var top: Control = _info.get_parent()
	_bottom.position.y = top.position.y + top.get_combined_minimum_size().y + 2
	var choice = await menu.choose("", options, true, 2)
	if choice == null:
		return false
	var slots := c.moves.duplicate()
	slots[slots.find(choice)] = move
	return Progression.set_moves(db, c, slots) == ""
