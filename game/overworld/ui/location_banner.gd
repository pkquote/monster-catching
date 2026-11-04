class_name LocationBanner
extends CanvasLayer
## The place name that slides in at the top-left when entering a new location.

signal shown(text: String)

const HOLD := 2.0

var _panel: PanelContainer
var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = 40
	_panel = UIKit.panel(self, 8)
	_panel.position = Vector2(8, -40)
	_label = UIKit.label(_panel, "", UIKit.HEADING_SIZE, UIKit.TEXT)
	_panel.visible = false


func show_text(text: String) -> void:
	_label.text = text
	_panel.visible = true
	shown.emit(text)
	if _tween != null:
		_tween.kill()
	if Overworld.instant:
		return
	_tween = create_tween()
	_tween.tween_property(_panel, "position:y", 8.0, 0.25).from(-40.0)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_panel, "position:y", -40.0, 0.25)
	_tween.tween_callback(func(): _panel.visible = false)
