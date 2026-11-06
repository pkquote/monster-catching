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

## Most rows shown at once; 0 = no limit. A longer list is split into pages, each ending
## with "Previous page" and "Next page · n/m" (both wrap). Shorter lists are unchanged.
var max_rows := 0

const PREV_PAGE := "Previous page"
const NEXT_PAGE := "Next page"

var _title: Label
var _grid: GridContainer
var _allow_cancel := false
var _active := false
var _options: Array = []
var _columns := COLUMNS
var _page := 0


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
	_options = options
	_columns = columns
	_page = 0
	var per: int = _per_page()
	if per > 0:  # open on the page holding the marked option
		for i: int in options.size():
			if options[i].get("focus", false) and not options[i].get("disabled", false):
				_page = floori(float(i) / per)
				break
	_build("")
	_active = true
	var result = await picked
	hovered.emit(null)
	return result


## Number of pages the current list is shown in (1 when it isn't paged).
func page_count() -> int:
	var per: int = _per_page()
	return 1 if per == 0 else ceili(float(_options.size()) / per)


## Options per page when the list is paged (two slots go to the page buttons), else 0.
## Narrow menus need max_rows * columns >= 3 to be useful: one column with max_rows 3 shows
## a single option per page (and never fewer than one, however small the limit).
func _per_page() -> int:
	if max_rows <= 0 or _options.size() <= max_rows * _columns:
		return 0
	return maxi(1, max_rows * _columns - 2)


## Adds the buttons for the current page; `focus_nav` (PREV_PAGE / NEXT_PAGE) starts on
## that page button instead of the first enabled option.
func _build(focus_nav: String) -> void:
	var per: int = _per_page()
	var shown: Array = _options if per == 0 else _options.slice(_page * per, (_page + 1) * per)
	var first: Button = null
	var marked: Button = null
	var enabled: Array[Button] = []
	for o: Dictionary in shown:
		var value: Variant = o.value
		var b: Button = _add_button(o.label, o.get("disabled", false), func(): _finish(value), o.get("hint"))
		var decorate: Variant = o.get("decorate")
		if decorate is Callable:
			decorate.call(b)
		if first == null and not b.disabled:
			first = b
		if not b.disabled:
			enabled.append(b)
			if marked == null and o.get("focus", false):
				marked = b
	if per > 0:
		var prev: Button = _add_button(PREV_PAGE, false, func(): _turn_later.call_deferred(-1), null)
		var next: Button = _add_button("%s · %d/%d" % [NEXT_PAGE, _page + 1, page_count()], false,
			func(): _turn_later.call_deferred(1), null)
		enabled.append_array([prev, next] as Array[Button])
		if focus_nav == PREV_PAGE:
			marked = prev
		elif focus_nav == NEXT_PAGE:
			marked = next
		if first == null:
			first = next
	if linear_focus:
		_chain(enabled)
	if marked != null:
		first = marked
	if first != null:
		_focus_later.call_deferred(first)


func _add_button(label: String, disabled: bool, on_press: Callable, hint: Variant) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.disabled = disabled
	var w: int = button_width if button_width > 0 else (196 if _columns >= 3 else 300)
	b.custom_minimum_size = Vector2(w, 22)
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(on_press)
	b.focus_entered.connect(func(): hovered.emit(hint))
	_grid.add_child(b)
	return b


## Shows the page `step` away (wrapping), keeping focus on the page button pressed.
## Deferred from that button's own `pressed`, since it frees the button.
func _turn_later(step: int) -> void:
	if not _active or _per_page() == 0:
		return
	_page = posmod(_page + step, page_count())
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_build(PREV_PAGE if step < 0 else NEXT_PAGE)


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
	for c: Node in _grid.get_children():
		c.queue_free()
