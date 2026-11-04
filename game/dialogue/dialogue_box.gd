class_name DialogueBox
extends CanvasLayer
## The conversation box used for every Dialogue Manager conversation and every
## one-off message ("Found a Salve!"). Speaker name above a bottom panel, text
## typed out at the Text speed setting; Accept finishes the line, then advances.
## Responses use a CommandMenu.

signal _advanced

const CHARS_PER_SEC := {"slow": 20.0, "normal": 45.0, "fast": 90.0, "instant": 0.0}
const HEIGHT := 92

var menu: CommandMenu

var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _typed := 0.0
var _speed := 0.0


func _ready() -> void:
	layer = 60
	var root := Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Anchored to the bottom edge and growing upward, so answers never fall off screen.
	var dock := VBoxContainer.new()
	dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_left = 8
	dock.offset_right = -8
	dock.offset_bottom = -8
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dock)
	_panel = UIKit.panel(dock, 10)
	_panel.custom_minimum_size = Vector2(0, HEIGHT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_panel.add_child(col)
	_speaker = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.ACCENT)
	_text = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.TEXT, true)
	_text.custom_minimum_size = Vector2(600, 34)
	menu = CommandMenu.new()
	menu.custom_minimum_size = Vector2(600, 0)
	col.add_child(menu)
	_panel.visible = false


func _process(delta: float) -> void:
	if is_typing():
		_typed += delta * _speed
		_text.visible_characters = int(_typed)


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and not menu.is_choosing() and event.is_action_pressed("accept"):
		get_viewport().set_input_as_handled()
		press_accept()


# --- Running -----------------------------------------------------------------------

## Runs `title` of a .dialogue resource to the end. `states` are extra objects the
## script can call (the overworld); autoloads like Story are found by name.
func run(resource: DialogueResource, title: String, states: Array = []) -> void:
	_panel.visible = true
	var line: DialogueLine = await DialogueManager.get_next_dialogue_line(resource, title, states)
	while line != null:
		await _show(line.character, line.text)
		var next := line.next_id
		var allowed := line.responses.filter(func(r): return r.is_allowed)
		if not allowed.is_empty():
			while is_typing():  # let the question finish (Accept skips ahead)
				await get_tree().process_frame
			var options := allowed.map(func(r): return {"label": r.text, "value": r.next_id})
			next = await menu.choose("", options, false, 1)
		else:
			await _advanced
		line = await DialogueManager.get_next_dialogue_line(resource, next, states)
	_close()


## Shows plain lines ([{ speaker, text }]) one after another, without a file.
func show_lines(lines: Array) -> void:
	_panel.visible = true
	for l in lines:
		await _show(str(l.get("speaker", "")), str(l.get("text", "")))
		await _advanced
	_close()


## Accept: finish the typing line, or move on.
func press_accept() -> void:
	if is_typing():
		_text.visible_characters = -1
		return
	_advanced.emit()


func is_typing() -> bool:
	return _panel.visible and _text.visible_characters != -1 \
		and _text.visible_characters < _text.get_total_character_count()


func shown_text() -> String:
	return _text.text


func visible_now() -> bool:
	return _panel.visible


func _show(speaker: String, text: String) -> void:
	_panel.visible = true
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_text.text = text
	_speed = float(CHARS_PER_SEC.get(Settings.data.text_speed, 45.0))
	_typed = 0.0
	_text.visible_characters = -1 if _speed <= 0.0 else 0


func _close() -> void:
	menu.show_idle()
	_panel.visible = false
