extends Minigame
## Quick Draw: wait for the "!", then press Accept as fast as you can.
## params: { window: float (seconds, default 0.45), rounds: int (default 5) }

var game: QuickDraw

var _big: Label
var _info: Label
var _shown_at := -1.0  # seconds since start when the "!" appeared; -1 = not yet
var _clock := 0.0
var _waiting_for_press := false
var _done := false
var _rng := RandomNumberGenerator.new()


func begin(params: Dictionary) -> void:
	_rng.randomize()
	game = QuickDraw.new(_rng, float(params.get("window", 0.45)), int(params.get("rounds", 5)))
	theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(400, 0)
	center.add_child(col)
	UIKit.label(col, "Quick Draw", UIKit.TITLE_SIZE, UIKit.ACCENT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big = UIKit.label(col, "", 48, UIKit.TEXT)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info = UIKit.label(col, "Press Accept the moment the ! appears.", UIKit.BODY_SIZE, UIKit.MUTED)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_round()


func _process(delta: float) -> void:
	_clock += delta


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("accept"):
		return
	get_viewport().set_input_as_handled()
	if _done:
		finished.emit(game.result())
		return
	if not _waiting_for_press:
		return
	var outcome := game.press(_clock - _shown_at if _shown_at >= 0.0 else -1.0)
	_waiting_for_press = false
	_big.text = {"early": "Too soon!", "win": "Got it!", "slow": "Too slow!"}.get(outcome, "")
	_info.text = "Round %d of %d   ·   %d won" % [game.round, game.rounds, game.wins]
	await get_tree().create_timer(0.8).timeout
	if game.is_over():
		_done = true
		var r := game.result()
		_big.text = "You win!" if r.won else "Not this time."
		_info.text = "%d of %d rounds. Press Accept." % [r.score, game.rounds]
	else:
		_next_round()


func _next_round() -> void:
	_shown_at = -1.0
	_big.text = "..."
	_waiting_for_press = true
	var my_round := game.round
	await get_tree().create_timer(game.next_delay()).timeout
	if game.round == my_round and _waiting_for_press:
		_shown_at = _clock
		_big.text = "!"
