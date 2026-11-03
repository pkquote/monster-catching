extends CanvasLayer
## Changes scenes with a fade. Screens read `params` for data passed by the caller
## (e.g. where the settings screen should return to).

const SPLASH := "res://game/boot/splash.tscn"
const TITLE := "res://game/menus/title_menu.tscn"
const NEW_GAME := "res://game/menus/new_game.tscn"
const LOAD_GAME := "res://game/menus/load_menu.tscn"
const SETTINGS := "res://game/menus/settings_menu.tscn"
const WORLD := "res://game/world/placeholder_world.tscn"

const FADE_TIME := 0.2

var params: Dictionary = {}
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func is_busy() -> bool:
	return _busy


func goto(path: String, p: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	params = p
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks mid-fade
	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await out.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
