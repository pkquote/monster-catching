extends Control
## Audio · Display · Gameplay · Controls. Changes apply immediately and are
## written to disk when leaving the screen.

const TEXT_SPEED_LABELS := {"slow": "Slow", "normal": "Normal", "fast": "Fast", "instant": "Instant"}

var tabs: TabContainer
## { action: { device: Button } }
var bind_buttons: Dictionary = {}
var _listening := {}  # { action, device } while waiting for an input to bind


func _ready() -> void:
	var col := UIKit.screen(self, "Settings", 460)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(460, 220)
	col.add_child(tabs)
	_build_audio()
	_build_display()
	_build_gameplay()
	_build_controls()
	UIKit.button(col, "Back", _back)
	tabs.get_tab_bar().grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if _listening.is_empty():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	var b := Settings.event_to_binding(event)
	if b.is_empty():
		return
	var device := "keyboard" if b.type == "key" else "gamepad"
	if device != _listening.device:
		return
	get_viewport().set_input_as_handled()
	Settings.data.rebind(_listening.action, device, b)
	Settings.apply_controls()
	_stop_listening()


func _unhandled_input(event: InputEvent) -> void:
	if _listening.is_empty() and event.is_action_pressed("ui_cancel"):
		_back()


# --- Tabs ------------------------------------------------------------------------

func _tab(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	tabs.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


func _row(parent: Node, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UIKit.label(row, label_text)
	l.custom_minimum_size = Vector2(150, 0)
	return row


func _build_audio() -> void:
	var v := _tab("Audio")
	for entry in [["Master volume", "master_volume"], ["Music volume", "music_volume"], ["Sound effects", "sfx_volume"]]:
		var row := _row(v, entry[0])
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(180, 0)
		slider.value = roundi(float(Settings.data.get(entry[1])) * 100.0)
		row.add_child(slider)
		var value_label := UIKit.label(row, "%d%%" % slider.value)
		var prop: String = entry[1]
		slider.value_changed.connect(func(val: float):
			Settings.data.set(prop, val / 100.0)
			value_label.text = "%d%%" % val
			Settings.apply_audio())


func _build_display() -> void:
	var v := _tab("Display")
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.data.fullscreen
	v.add_child(fs)
	var scale_row := _row(v, "Window scale")
	var scale_opt := OptionButton.new()
	for s in GameSettings.WINDOW_SCALES:
		scale_opt.add_item("%dx  (%dx%d)" % [s, Settings.BASE_SIZE.x * s, Settings.BASE_SIZE.y * s])
	scale_opt.selected = GameSettings.WINDOW_SCALES.find(Settings.data.window_scale)
	scale_opt.disabled = Settings.data.fullscreen
	scale_row.add_child(scale_opt)
	var vsync := CheckBox.new()
	vsync.text = "VSync"
	vsync.button_pressed = Settings.data.vsync
	v.add_child(vsync)
	fs.toggled.connect(func(on: bool):
		Settings.data.fullscreen = on
		scale_opt.disabled = on
		Settings.apply_display())
	scale_opt.item_selected.connect(func(i: int):
		Settings.data.window_scale = GameSettings.WINDOW_SCALES[i]
		Settings.apply_display())
	vsync.toggled.connect(func(on: bool):
		Settings.data.vsync = on
		Settings.apply_display())


func _build_gameplay() -> void:
	var v := _tab("Gameplay")
	var text_row := _row(v, "Text speed")
	var text_speed := OptionButton.new()
	for s in GameSettings.TEXT_SPEEDS:
		text_speed.add_item(TEXT_SPEED_LABELS[s])
	text_speed.selected = GameSettings.TEXT_SPEEDS.find(Settings.data.text_speed)
	text_speed.item_selected.connect(func(i: int): Settings.data.text_speed = GameSettings.TEXT_SPEEDS[i])
	text_row.add_child(text_speed)
	var battle_row := _row(v, "Battle animations")
	var battle := OptionButton.new()
	for s in GameSettings.BATTLE_SPEEDS:
		battle.add_item("%dx speed" % s)
	battle.selected = GameSettings.BATTLE_SPEEDS.find(Settings.data.battle_speed)
	battle.item_selected.connect(func(i: int): Settings.data.battle_speed = GameSettings.BATTLE_SPEEDS[i])
	battle_row.add_child(battle)
	var confirm := CheckBox.new()
	confirm.text = "Confirm before ending a turn"
	confirm.button_pressed = Settings.data.confirm_end_turn
	confirm.toggled.connect(func(on: bool): Settings.data.confirm_end_turn = on)
	v.add_child(confirm)


func _build_controls() -> void:
	var v := _tab("Controls")
	UIKit.label(v, "Select a binding, then press the new key or button. Esc cancels.", UIKit.BODY_SIZE, UIKit.MUTED, true)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	for header in ["Action", "Keyboard", "Gamepad"]:
		UIKit.label(grid, header, UIKit.BODY_SIZE, UIKit.ACCENT)
	for action in GameSettings.ACTIONS:
		UIKit.label(grid, GameSettings.ACTION_LABELS[action])
		bind_buttons[action] = {}
		for device in ["keyboard", "gamepad"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(110, 0)
			b.pressed.connect(func(): _start_listening(action, device))
			grid.add_child(b)
			bind_buttons[action][device] = b
	UIKit.button(v, "Reset controls to defaults", func():
		Settings.data.reset_bindings()
		Settings.apply_controls()
		_refresh_bindings())
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action in bind_buttons:
		for device in bind_buttons[action]:
			var list: Array = Settings.data.bindings[action][device]
			bind_buttons[action][device].text = Settings.describe(list[0]) if not list.is_empty() else "—"


func _start_listening(action: String, device: String) -> void:
	_refresh_bindings()
	_listening = {"action": action, "device": device}
	bind_buttons[action][device].text = "Press a key…" if device == "keyboard" else "Press a button…"


func _stop_listening() -> void:
	_listening = {}
	_refresh_bindings()


func _back() -> void:
	Settings.save()
	SceneRouter.goto(SceneRouter.params.get("return_to", SceneRouter.TITLE))
