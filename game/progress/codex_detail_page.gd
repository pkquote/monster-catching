class_name CodexDetailPage
extends ProgressScreen
## One seen species: its sprite, number, name and status on the left; the type names, the description and
## where to find it on the right, with a Back row. An unseen species never opens.

## Location lines shown before "+N more places", so a long list can't push the page off the screen.
const MAX_LOCATION_LINES := 4
## Longest description shown (characters); longer ones end in an ellipsis so the page stays on screen.
const DESCRIPTION_MAX := 180
## Width of the Back row: the preview takes the left of the screen (set_side).
const COLUMN_WIDTH := 306

var _preview: CodexPreview


## Runs until the player picks Back. Does nothing for a species the player hasn't seen.
static func run(parent: Node, species: String, save: SaveGame = null, db: Database = null) -> void:
	var screen := CodexDetailPage.new()
	screen.use_game(save, db)
	if Codex.status(screen._save, species) == "unseen":
		screen._preview.free()  # built in _init and never parented, so it isn't freed with the screen
		screen.free()
		return
	parent.add_child(screen)
	await screen._show(species)
	screen.close()


func _init() -> void:
	_preview = CodexPreview.new()
	set_side(_preview)


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH


func preview() -> CodexPreview:
	return _preview


## The page text: the description (or a fallback), then "Where to find it:" with one line per place
## (capped), or where the species comes from when it has no wild habitat, then "Not caught yet" when it
## has only been seen.
static func body_text(db: Database, save: SaveGame, species: String) -> String:
	var def := db.creature(species)
	var lines := PackedStringArray()
	var description := def.description
	if description.length() > DESCRIPTION_MAX:
		description = description.substr(0, DESCRIPTION_MAX - 1).strip_edges() + "…"
	lines.append(description if description != "" else "No description yet.")
	lines.append("")
	lines.append("Where to find it:")
	var rows := Locations.for_species(db, species)
	if rows.is_empty():
		var from := Locations.evolves_from(db, species)
		if from != "" and Codex.caught(save, from):
			lines.append("Evolves from %s" % db.creature(from).name)
		else:
			lines.append("No wild habitat known")
	else:
		for i in mini(rows.size(), MAX_LOCATION_LINES):
			lines.append("- " + Locations.line(rows[i]))
		if rows.size() > MAX_LOCATION_LINES:
			lines.append("- +%d more places" % (rows.size() - MAX_LOCATION_LINES))
	if not Codex.caught(save, species):
		lines.append("")
		lines.append("Not caught yet")
	return "\n".join(lines)


func _show(species: String) -> void:
	var db := _db
	var save := _save
	var def := db.creature(species)
	_preview.show_entry(db, save, species)
	_title.text = " / ".join(Array(def.types).map(func(t: String) -> String: return db.type_def(t).name))
	_body.text = body_text(db, save, species)
	await menu.choose("", [{"label": "Back", "value": null}], true, 1)
