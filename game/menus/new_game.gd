extends Control
## Name entry for a new playthrough.

const MAX_NAME := 12

var name_edit: LineEdit
var start_button: Button
var _error: Label


func _ready() -> void:
	var col := UIKit.screen(self, "New Game")
	UIKit.label(col, "What's your name?", UIKit.HEADING_SIZE)
	name_edit = LineEdit.new()
	name_edit.max_length = MAX_NAME
	name_edit.placeholder_text = "Your name"
	name_edit.text_changed.connect(func(_t): _refresh())
	name_edit.text_submitted.connect(func(_t): _start())
	col.add_child(name_edit)
	start_button = UIKit.button(col, "Start", _start)
	UIKit.button(col, "Back", _back)
	_error = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.DANGER, true)
	_refresh()
	name_edit.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not name_edit.has_focus():
		_back()


func clean_name() -> String:
	return name_edit.text.strip_edges()


func _refresh() -> void:
	start_button.disabled = clean_name().is_empty()


func _start() -> void:
	if clean_name().is_empty():
		return
	var err := GameState.start_new_game(clean_name())
	if err != "":
		_error.text = err
		return
	SceneRouter.goto(SceneRouter.WORLD)


func _back() -> void:
	SceneRouter.goto(SceneRouter.TITLE)
