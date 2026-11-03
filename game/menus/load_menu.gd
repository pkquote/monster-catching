extends Control
## Save browser: saves grouped by playthrough, newest first. Load or delete.

var _list: VBoxContainer
var _confirm: ConfirmationDialog
var _pending_delete := ""
var _status: Label


func _ready() -> void:
	var col := UIKit.screen(self, "Load Game", 460)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_status = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.DANGER, true)
	var back := UIKit.button(col, "Back", _back)

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Delete this save? This can't be undone."
	_confirm.ok_button_text = "Delete"
	_confirm.confirmed.connect(_delete_confirmed)
	add_child(_confirm)

	_rebuild()
	var first := _first_button()
	(first if first != null else back).grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirm.visible:
		_back()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var groups := GameState.store.list_grouped()
	if groups.is_empty():
		UIKit.label(_list, "No saves yet.", UIKit.BODY_SIZE, UIKit.MUTED)
		return
	for g in groups:
		var player: String = g.player_name if g.player_name != "" else "Unknown tamer"
		UIKit.label(_list, player, UIKit.HEADING_SIZE, UIKit.ACCENT)
		for entry in g.saves:
			_add_row(entry)
		UIKit.spacer(_list, 4)


func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_list.add_child(row)
	var path: String = entry.path
	if entry.damaged:
		var l := UIKit.label(row, "Damaged save: %s" % entry.error, UIKit.BODY_SIZE, UIKit.DANGER, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		var kind := "Autosave" if entry.kind == SaveGame.KIND_AUTO else "Save"
		var text := "%s  ·  %s  ·  %s  ·  %s" % [kind, entry.location, SaveGame.format_playtime(entry.playtime_sec),
			UIKit.format_time(entry.saved_unix)]
		var b := UIKit.button(row, text, func(): _load(path))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UIKit.button(row, "Delete", func(): _ask_delete(path))


func _first_button() -> Button:
	for row in _list.get_children():
		for c in row.get_children():
			if c is Button:
				return c
	return null


func _load(path: String) -> void:
	var err := GameState.load_from(path)
	if err != "":
		_status.text = "Couldn't load: " + err
		return
	SceneRouter.goto(SceneRouter.WORLD)


func _ask_delete(path: String) -> void:
	_pending_delete = path
	_confirm.popup_centered()


func _delete_confirmed() -> void:
	if _pending_delete != "":
		GameState.store.delete(_pending_delete)
		_pending_delete = ""
		_rebuild()


func _back() -> void:
	SceneRouter.goto(SceneRouter.TITLE)
