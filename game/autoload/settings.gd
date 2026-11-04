extends Node
## Loads GameSettings from disk and applies them to the engine: audio buses,
## window, and the input map. Menus edit `data`, call the matching apply_*(),
## and call save() when the player leaves the settings screen.

signal changed

const PATH := "user://settings.json"
const BASE_SIZE := Vector2i(640, 360)
const BUSES := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume"}
## Game action -> built-in UI action it also drives, so menus follow rebinds.
const UI_MIRROR := {"move_up": "ui_up", "move_down": "ui_down", "move_left": "ui_left",
	"move_right": "ui_right", "accept": "ui_accept", "cancel": "ui_cancel"}
const AXIS_DEADZONE := 0.5
## Fixed (not rebindable) actions: the party screens' previous/next creature.
const SHOULDER_ACTIONS := {
	"prev_creature": [KEY_PAGEUP, JOY_BUTTON_LEFT_SHOULDER],
	"next_creature": [KEY_PAGEDOWN, JOY_BUTTON_RIGHT_SHOULDER],
}

var data: GameSettings


func _ready() -> void:
	data = load_from_disk()
	_ensure_buses()
	apply_all()


func load_from_disk() -> GameSettings:
	if not FileAccess.file_exists(PATH):
		return GameSettings.new()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return GameSettings.from_dict(parsed) if parsed is Dictionary else GameSettings.new()


func save() -> void:
	SaveStore._write_atomic(PATH, JSON.stringify(data.to_dict(), "\t"))


func apply_all() -> void:
	apply_audio()
	apply_display()
	apply_controls()


func apply_audio() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx == -1:
			continue
		var v: float = data.get(BUSES[bus])
		AudioServer.set_bus_mute(idx, v <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	changed.emit()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if data.vsync else DisplayServer.VSYNC_DISABLED)
	if data.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var size := BASE_SIZE * data.window_scale
		var screen := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	changed.emit()


func apply_controls() -> void:
	for action in GameSettings.ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, AXIS_DEADZONE)
		InputMap.action_erase_events(action)
		for device in ["keyboard", "gamepad"]:
			for b in data.bindings[action][device]:
				InputMap.action_add_event(action, binding_to_event(b))
		if UI_MIRROR.has(action):
			var ui: String = UI_MIRROR[action]
			InputMap.action_erase_events(ui)
			for ev in InputMap.action_get_events(action):
				InputMap.action_add_event(ui, ev)
	for action in SHOULDER_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, AXIS_DEADZONE)
		InputMap.action_erase_events(action)
		var key := InputEventKey.new()
		key.physical_keycode = SHOULDER_ACTIONS[action][0]
		InputMap.action_add_event(action, key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = SHOULDER_ACTIONS[action][1]
		InputMap.action_add_event(action, pad)
	changed.emit()


# --- Binding <-> InputEvent ---------------------------------------------------------

static func binding_to_event(b: Dictionary) -> InputEvent:
	match b.type:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = b.keycode
			return k
		"joy_button":
			var j := InputEventJoypadButton.new()
			j.button_index = b.button
			return j
		_:
			var m := InputEventJoypadMotion.new()
			m.axis = b.axis
			m.axis_value = float(b.value)
			return m


## Binding dictionary for a pressed input, or {} if it can't be bound.
static func event_to_binding(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return {"type": "key", "keycode": code} if code != 0 else {}
	if ev is InputEventJoypadButton and ev.pressed:
		return {"type": "joy_button", "button": ev.button_index}
	if ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.6:
		return {"type": "joy_axis", "axis": ev.axis, "value": 1 if ev.axis_value > 0 else -1}
	return {}


const _PAD_BUTTONS := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right"}
const _PAD_AXES := {0: ["L-stick left", "L-stick right"], 1: ["L-stick up", "L-stick down"],
	2: ["R-stick left", "R-stick right"], 3: ["R-stick up", "R-stick down"], 4: ["LT", "LT"], 5: ["RT", "RT"]}


static func describe(b: Dictionary) -> String:
	match b.get("type"):
		"key":
			return OS.get_keycode_string(b.keycode)
		"joy_button":
			return _PAD_BUTTONS.get(int(b.button), "Button %d" % b.button)
		"joy_axis":
			var names: Array = _PAD_AXES.get(int(b.axis), ["Axis %d-" % b.axis, "Axis %d+" % b.axis])
			return names[0] if int(b.value) < 0 else names[1]
	return "—"


func _ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
