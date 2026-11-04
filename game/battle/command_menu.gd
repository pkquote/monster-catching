class_name CommandMenu
extends VBoxContainer
## The bottom panel's choice list. `choose()` shows options and returns the chosen
## value, or null if the player cancels (when cancelling is allowed).
##
## Option: { label: String, value: Variant, disabled: bool = false, hint: Variant = null }
## `hint` is passed to the `hovered` signal when an option gains focus (used to
## highlight targets on the stage).

signal picked(value: Variant)
signal hovered(hint: Variant)

const COLUMNS := 3

var _title: Label
var _grid: GridContainer
var _allow_cancel := false
var _active := false


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	_title = UIKit.label(self, "", UIKit.BODY_SIZE, UIKit.MUTED)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 3)
	add_child(_grid)


func choose(title: String, options: Array, allow_cancel := true, columns := COLUMNS) -> Variant:
	_clear()
	_title.text = title
	_grid.columns = columns
	_allow_cancel = allow_cancel
	var first: Button = null
	for o in options:
		var b := Button.new()
		b.text = o.label
		b.disabled = o.get("disabled", false)
		b.custom_minimum_size = Vector2(196 if columns >= 3 else 300, 22)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 11)
		var value = o.value
		b.pressed.connect(func(): _finish(value))
		var hint = o.get("hint")
		b.focus_entered.connect(func(): hovered.emit(hint))
		_grid.add_child(b)
		if first == null and not b.disabled:
			first = b
	_active = true
	if first != null:
		first.grab_focus.call_deferred()
	var result = await picked
	hovered.emit(null)
	return result


## Shows a message with no choices (e.g. during playback).
func show_idle(text: String = "") -> void:
	_clear()
	_title.text = text
	_active = false


func is_choosing() -> bool:
	return _active


## Picks an option by its label (used by the automated driver).
func pick_label(label: String) -> bool:
	for b in _grid.get_children():
		if b is Button and b.text.begins_with(label) and not b.disabled:
			b.pressed.emit()
			return true
	return false


func labels() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _grid.get_children():
		if b is Button:
			out.append(b.text)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if _active and _allow_cancel and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(null)


func _finish(value: Variant) -> void:
	if not _active:
		return
	_active = false
	picked.emit(value)


func _clear() -> void:
	for c in _grid.get_children():
		c.queue_free()
