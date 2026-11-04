class_name GameSettings
extends RefCounted
## Player settings: defaults, valid ranges, and (de)serialization.
## Pure data; the Settings autoload applies these to the engine.
##
## Input bindings are stored as plain dictionaries so this class never touches
## InputEvent objects:
##   { "type": "key", "keycode": int }
##   { "type": "joy_button", "button": int }
##   { "type": "joy_axis", "axis": int, "value": -1 or 1 }

const SCHEMA := 1

const TEXT_SPEEDS := ["slow", "normal", "fast", "instant"]
const BATTLE_SPEEDS := [1, 2, 4]
const WINDOW_SCALES := [2, 3, 4]

## Rebindable game actions, in the order the Controls tab shows them.
const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "accept", "cancel", "menu", "run"]
const ACTION_LABELS := {
	"move_up": "Move up", "move_down": "Move down", "move_left": "Move left", "move_right": "Move right",
	"accept": "Accept", "cancel": "Cancel / back", "menu": "Menu", "run": "Run",
}

var master_volume := 0.8
var music_volume := 0.8
var sfx_volume := 0.8
var fullscreen := false
var window_scale := 2
var vsync := true
var text_speed := "normal"
var battle_speed := 1
var confirm_end_turn := true
## action -> { "keyboard": Array[binding], "gamepad": Array[binding] }
var bindings: Dictionary = default_bindings()


static func default_bindings() -> Dictionary:
	return {
		"move_up": {"keyboard": [_key(KEY_UP), _key(KEY_W)], "gamepad": [_jbtn(JOY_BUTTON_DPAD_UP), _jaxis(JOY_AXIS_LEFT_Y, -1)]},
		"move_down": {"keyboard": [_key(KEY_DOWN), _key(KEY_S)], "gamepad": [_jbtn(JOY_BUTTON_DPAD_DOWN), _jaxis(JOY_AXIS_LEFT_Y, 1)]},
		"move_left": {"keyboard": [_key(KEY_LEFT), _key(KEY_A)], "gamepad": [_jbtn(JOY_BUTTON_DPAD_LEFT), _jaxis(JOY_AXIS_LEFT_X, -1)]},
		"move_right": {"keyboard": [_key(KEY_RIGHT), _key(KEY_D)], "gamepad": [_jbtn(JOY_BUTTON_DPAD_RIGHT), _jaxis(JOY_AXIS_LEFT_X, 1)]},
		"accept": {"keyboard": [_key(KEY_Z), _key(KEY_ENTER)], "gamepad": [_jbtn(JOY_BUTTON_A)]},
		"cancel": {"keyboard": [_key(KEY_X), _key(KEY_ESCAPE)], "gamepad": [_jbtn(JOY_BUTTON_B)]},
		"menu": {"keyboard": [_key(KEY_C), _key(KEY_TAB)], "gamepad": [_jbtn(JOY_BUTTON_START)]},
		"run": {"keyboard": [_key(KEY_SHIFT)], "gamepad": [_jbtn(JOY_BUTTON_X)]},
	}


static func _key(code: int) -> Dictionary:
	return {"type": "key", "keycode": code}


static func _jbtn(button: int) -> Dictionary:
	return {"type": "joy_button", "button": button}


static func _jaxis(axis: int, value: int) -> Dictionary:
	return {"type": "joy_axis", "axis": axis, "value": value}


## Replaces the primary (first) binding of one device for an action.
func rebind(action: String, device: String, binding: Dictionary) -> void:
	if not bindings.has(action) or not device in ["keyboard", "gamepad"]:
		return
	var list: Array = bindings[action][device]
	if list.is_empty():
		list.append(binding)
	else:
		list[0] = binding


func reset_bindings() -> void:
	bindings = default_bindings()


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"audio": {"master": master_volume, "music": music_volume, "sfx": sfx_volume},
		"display": {"fullscreen": fullscreen, "window_scale": window_scale, "vsync": vsync},
		"gameplay": {"text_speed": text_speed, "battle_speed": battle_speed, "confirm_end_turn": confirm_end_turn},
		"controls": bindings.duplicate(true),
	}


## Reads settings, keeping defaults for anything missing or invalid.
static func from_dict(d: Dictionary) -> GameSettings:
	var s := GameSettings.new()
	var audio: Dictionary = d.get("audio", {}) if d.get("audio") is Dictionary else {}
	s.master_volume = _volume(audio.get("master"), s.master_volume)
	s.music_volume = _volume(audio.get("music"), s.music_volume)
	s.sfx_volume = _volume(audio.get("sfx"), s.sfx_volume)
	var display: Dictionary = d.get("display", {}) if d.get("display") is Dictionary else {}
	if display.get("fullscreen") is bool:
		s.fullscreen = display.fullscreen
	if _is_num(display.get("window_scale")) and int(display.window_scale) in WINDOW_SCALES:
		s.window_scale = int(display.window_scale)
	if display.get("vsync") is bool:
		s.vsync = display.vsync
	var gameplay: Dictionary = d.get("gameplay", {}) if d.get("gameplay") is Dictionary else {}
	if gameplay.get("text_speed") in TEXT_SPEEDS:
		s.text_speed = gameplay.text_speed
	if _is_num(gameplay.get("battle_speed")) and int(gameplay.battle_speed) in BATTLE_SPEEDS:
		s.battle_speed = int(gameplay.battle_speed)
	if gameplay.get("confirm_end_turn") is bool:
		s.confirm_end_turn = gameplay.confirm_end_turn
	var controls: Dictionary = d.get("controls", {}) if d.get("controls") is Dictionary else {}
	for action in ACTIONS:
		var entry = controls.get(action)
		if not entry is Dictionary:
			continue
		for device in ["keyboard", "gamepad"]:
			var list = entry.get(device)
			if list is Array and not list.is_empty() and list.all(func(b): return valid_binding(b)):
				s.bindings[action][device] = list.map(func(b): return _normalize(b))
	return s


static func valid_binding(b: Variant) -> bool:
	if not b is Dictionary:
		return false
	match b.get("type"):
		"key":
			return _is_num(b.get("keycode")) and int(b.keycode) > 0
		"joy_button":
			return _is_num(b.get("button")) and int(b.button) >= 0
		"joy_axis":
			return _is_num(b.get("axis")) and _is_num(b.get("value")) and absf(float(b.value)) == 1.0
	return false


static func _normalize(b: Dictionary) -> Dictionary:
	match b.type:
		"key":
			return _key(int(b.keycode))
		"joy_button":
			return _jbtn(int(b.button))
	return _jaxis(int(b.axis), int(b.value))


static func _volume(v: Variant, fallback: float) -> float:
	return clampf(float(v), 0.0, 1.0) if _is_num(v) else fallback


static func _is_num(v: Variant) -> bool:
	return v is int or v is float
