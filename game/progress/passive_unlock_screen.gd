class_name PassiveUnlockScreen
extends ProgressScreen
## After a battle in which a creature unlocked its Affinity passive: shows both
## passives and offers to make the new one active. Cancel means keep.

const SWITCH := "Switch to it"
const KEEP := "Keep current"


## True if the player switched to the Affinity passive.
static func run(parent: Node, c: CreatureInstance, db: Database = null) -> bool:
	var screen := PassiveUnlockScreen.new()
	screen.use_game(null, db)
	parent.add_child(screen)
	var switched := await screen._ask(c)
	screen.close()
	return switched


## "<name> — <description>" for passive `id`, or "" for an empty or unknown id.
static func passive_line(db: Database, id: String) -> String:
	var def := db.passive(id)
	if def == null:
		return ""
	return "%s — %s" % [def.name, def.description] if def.description != "" else def.name


func _ask(c: CreatureInstance) -> bool:
	var db := _db
	var def := db.passive(c.affinity_passive)
	var new_name := def.name if def != null else c.affinity_passive
	_title.text = "%s awakened %s!" % [c.display_name(db), new_name]
	var current := passive_line(db, c.passive)
	_body.text = "\n".join(PackedStringArray([
		"Current: " + (current if current != "" else "none"),
		"New: " + passive_line(db, c.affinity_passive),
		"Only one passive is active at a time. You can switch later from the Summary."]))
	var choice = await menu.choose("", [{"label": SWITCH, "value": true},
		{"label": KEEP, "value": false}], true, 1)
	if choice != true:
		return false
	return Passives.set_active(c, Passives.SLOT_AFFINITY) == ""
