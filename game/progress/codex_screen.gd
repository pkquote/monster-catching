class_name CodexScreen
extends ProgressScreen
## The Codex from the pause menu: every species in Codex order with its seen / caught mark, and a
## preview of the focused row on the left. An unseen row reads "#003 ???" and does nothing.

## Width of a row: the preview takes the left of the screen (set_side).
const COLUMN_WIDTH := 306

## Frames to wait before the list is put back at the top (the layout settles in the first one or two).
const TOP_FRAMES := 3

var _preview: CodexPreview
var _top_frames := 0


## Runs until the player closes the list.
static func run(parent: Node, save: SaveGame = null, db: Database = null) -> void:
	var screen := CodexScreen.new()
	screen.use_game(save, db)
	parent.add_child(screen)
	await screen._loop(parent)
	screen.close()


func _init() -> void:
	_preview = CodexPreview.new()  # built before the screen joins the tree, as the party screen does
	set_side(_preview)


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH


func preview() -> CodexPreview:
	return _preview


## "#001 Name ●" caught, "#002 Name ○" seen, "#003 ???" unseen.
static func row_label(db: Database, save: SaveGame, species: String) -> String:
	var number := Codex.number_text(db, species)
	match Codex.status(save, species):
		"caught":
			return "%s %s ●" % [number, db.creature(species).name]
		"seen":
			return "%s %s ○" % [number, db.creature(species).name]
	return "%s ???" % number


## "Seen 3 / 8 · Caught 2 / 8".
static func header_text(db: Database, save: SaveGame) -> String:
	var order := Codex.order(db)  # only species in the list count, not test content or removed species
	var seen := Array(order).filter(func(id: String) -> bool: return Codex.seen(save, id)).size()
	var caught := Array(order).filter(func(id: String) -> bool: return Codex.caught(save, id)).size()
	return "Seen %d / %d · Caught %d / %d" % [seen, order.size(), caught, order.size()]


func _loop(parent: Node) -> void:
	var db := _db
	var save := _save
	var order := Codex.order(db)
	var focus_id := ""
	while true:
		_title.text = "Codex"
		_body.text = header_text(db, save)
		var options: Array = []
		for id in order:
			options.append({"label": row_label(db, save, id), "value": id, "hint": id, "focus": id == focus_id})
		options.append({"label": "Back", "value": ""})
		if order.is_empty():
			_preview.show_empty()
		else:
			_preview.show_entry(db, save, focus_id if focus_id != "" else order[0])
		menu.hovered.connect(_on_hover)
		if focus_id == "":
			_scroll_to_top.call_deferred()
		var picked = await menu.choose("", options, true, 1)
		menu.hovered.disconnect(_on_hover)
		if picked == null or picked == "":
			return
		focus_id = picked
		if Codex.status(save, picked) != "unseen":
			visible = false  # hidden behind the page, not shown through it
			await CodexDetailPage.run(parent, picked, save, db)
			visible = true


## A long list opens scrolled down by a row: the first focus lands before the layout has settled. Put it back
## after a few frames. Counted in `_process`, not awaited, so closing the screen meanwhile cannot leave a
## coroutine resuming on a freed node.
func _scroll_to_top() -> void:
	_top_frames = TOP_FRAMES
	set_process(true)


func _process(_delta: float) -> void:
	_top_frames -= 1
	if _top_frames <= 0:
		_scroll.scroll_vertical = 0
		set_process(false)


func _on_hover(hint: Variant) -> void:
	if hint is String:  # Back and the end of a choice carry no species: the preview stays
		_preview.show_entry(_db, _save, hint)
