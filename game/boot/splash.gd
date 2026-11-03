extends Control
## Studio credit, then the title, then the title menu. Any key skips.
## If game content failed validation, shows the errors instead (debug aid).

const CREDIT := "a game made with Godot"
const GAME_TITLE := "Monster Catching Game"
const TAGLINE := "Shape the field. Raise your team."

var _done := false
var _credit: Label
var _title: Control


func _ready() -> void:
	var col := UIKit.screen(self, "", 420)
	if not DataRegistry.errors.is_empty():
		_show_content_errors(col)
		return
	_credit = UIKit.label(col, CREDIT, UIKit.HEADING_SIZE, UIKit.MUTED)
	_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_box := VBoxContainer.new()
	col.add_child(title_box)
	UIKit.label(title_box, GAME_TITLE, UIKit.TITLE_SIZE, UIKit.ACCENT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.label(title_box, TAGLINE, UIKit.BODY_SIZE, UIKit.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = title_box
	_credit.modulate.a = 0.0
	_title.modulate.a = 0.0
	_title.visible = false

	var t := create_tween()
	t.tween_property(_credit, "modulate:a", 1.0, 0.5)
	t.tween_interval(0.9)
	t.tween_property(_credit, "modulate:a", 0.0, 0.4)
	t.tween_callback(func():
		_credit.visible = false
		_title.visible = true)
	t.tween_property(_title, "modulate:a", 1.0, 0.6)
	t.tween_interval(1.0)
	t.tween_callback(_continue)


func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
		and event.is_pressed()
	if pressed and DataRegistry.errors.is_empty():
		get_viewport().set_input_as_handled()
		_continue()


func _continue() -> void:
	if _done:
		return
	_done = true
	SceneRouter.goto(SceneRouter.TITLE)


func _show_content_errors(col: VBoxContainer) -> void:
	UIKit.label(col, "Game content failed validation", UIKit.HEADING_SIZE, UIKit.DANGER)
	UIKit.label(col, "Run tools/validate_data.gd for the full list.", UIKit.BODY_SIZE, UIKit.MUTED)
	var shown := DataRegistry.errors.slice(0, 8)
	UIKit.label(col, "\n".join(shown), 10, UIKit.TEXT, true)
