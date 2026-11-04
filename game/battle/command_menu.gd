class_name CommandMenu
extends VBoxContainer
## The bottom panel's choice list. `choose()` shows options and returns the chosen
## value, or null if the player cancels (when cancelling is allowed).
##
## Option: { label: String, value: Variant, disabled: bool = false, hint: Variant = null }
## `hint` is passed to the `hovered` signal when an option gains focus (used to
## highlight targets on the stage). `decorate`: an optional Callable(Button) run
## on the new button, for icons and extra controls. `focus`: true marks the option that
## starts focused (the first enabled one when none is marked or it is disabled).

signal picked(value: Variant)
signal hovered(hint: Variant)

const COLUMNS := 3

## Fixed button width; 0 = the default (196 in 3 columns, 300 otherwise).
var button_width := 0

## Opt-in: Up/Down (and Tab) walk the enabled options in reading order, wrapping, even in
## several columns. Godot's own grid focus keeps to a column, which strands the others.
var linear_focus := false

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
	_title.visible = title != ""
	_grid.columns = columns
	_allow_cancel = allow_cancel
	var first: Button = null
	var marked: Button = null
	var enabled: Array[Button] = []
	for o in options:
		var b := Button.new()
		b.text = o.label
		b.disabled = o.get("disabled", false)
		var w := button_width if button_width > 0 else (196 if columns >= 3 else 300)
		b.custom_minimum_size = Vector2(w, 22)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 11)
		var decorate = o.get("decorate")
		if decorate is Callable:
			decorate.call(b)
		var value = o.value
		b.pressed.connect(func(): _finish(value))
		var hint = o.get("hint")
		b.focus_entered.connect(func(): hovered.emit(hint))
		_grid.add_child(b)
		if first == null and not b.disabled:
			first = b
		if not b.disabled:
			enabled.append(b)
			if marked == null and o.get("focus", false):
				marked = b
	if linear_focus:
		_chain(enabled)
	if marked != null:
		first = marked
	_active = true
	if first != null:
		_focus_later.call_deferred(first)
	var result = await picked
	hovered.emit(null)
	return result


## The deferred grab: the menu may have been closed (or cleared) in the meantime.
func _focus_later(b: Button) -> void:
	if is_instance_valid(b) and b.is_inside_tree():
		b.grab_focus()


## Links `buttons` into one focus loop: Up/Down and Tab/Shift+Tab step through them in order.
func _chain(buttons: Array[Button]) -> void:
	for i in buttons.size():
		var prev := buttons[posmod(i - 1, buttons.size())]
		var next := buttons[(i + 1) % buttons.size()]
		var b := buttons[i]
		b.focus_neighbor_top = b.get_path_to(prev)
		b.focus_neighbor_bottom = b.get_path_to(next)
		b.focus_previous = b.get_path_to(prev)
		b.focus_next = b.get_path_to(next)


## Shows a message with no choices (e.g. during playback).
func show_idle(text: String = "") -> void:
	_clear()
	_title.text = text
	_title.visible = text != ""
	_active = false


## Ends the current `choose()` with `value` (for keys the owning screen handles itself).
func interrupt(value: Variant) -> void:
	_finish(value)


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
