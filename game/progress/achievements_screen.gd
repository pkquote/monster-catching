class_name AchievementsScreen
extends ProgressScreen
## Achievements from the pause menu: every listed achievement in data order with its state, and a
## preview of the focused row on the left. A hidden locked achievement reads "???".

## Width of a row: the preview takes the left of the screen (set_side).
const COLUMN_WIDTH := 306

var _preview: AchievementPreview


## Runs until the player closes the list.
static func run(parent: Node, save: SaveGame = null, db: Database = null) -> void:
	var screen := AchievementsScreen.new()
	screen.use_game(save, db)
	parent.add_child(screen)
	await screen._loop()
	screen.close()


func _init() -> void:
	_preview = AchievementPreview.new()  # built before the screen joins the tree, as the Codex does
	set_side(_preview)


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH


func preview() -> AchievementPreview:
	return _preview


## "Name ✓" unlocked, "Name 7 / 10" locked with progress, "???" hidden and locked.
static func row_label(db: Database, save: SaveGame, id: String) -> String:
	var def := db.achievement(id)
	if Achievements.is_unlocked(save, id):
		return "%s ✓" % def.name
	if def.hidden:
		return "???"
	var p := Achievements.progress(db, save, id)
	return "%s %d / %d" % [def.name, p.current, p.target] if not p.is_empty() else def.name


## "Unlocked 3 / 11", over the listed achievements only.
static func header_text(db: Database, save: SaveGame) -> String:
	return "Unlocked %d / %d" % [Achievements.unlock_count(db, save), Achievements.listed(db).size()]


func _loop() -> void:
	var db := _db
	var save := _save
	var listed := Achievements.listed(db)
	_title.text = "Achievements"
	_body.text = header_text(db, save)
	var options: Array = []
	for id in listed:
		options.append({"label": row_label(db, save, id), "value": id, "hint": id})
	options.append({"label": "Back", "value": ""})
	if listed.is_empty():
		_preview.show_empty()
	else:
		_preview.show_entry(db, save, listed[0])
	menu.hovered.connect(_on_hover)
	while true:
		var picked = await menu.choose("", options, true, 1)
		if picked == null or picked == "":
			break
	menu.hovered.disconnect(_on_hover)


func _on_hover(hint: Variant) -> void:
	if hint is String:  # Back carries no achievement: the preview stays
		_preview.show_entry(_db, _save, hint)
