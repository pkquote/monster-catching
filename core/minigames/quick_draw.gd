class_name QuickDraw
extends RefCounted
## Quick Draw rules: after a random wait a "!" appears; press Accept within
## `window` seconds to win the round. Pressing before it appears loses the round.
## Best of `rounds`: winning more than half wins the game.

var window: float
var rounds: int
var round := 0
var wins := 0
var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator, window_ := 0.45, rounds_ := 5) -> void:
	_rng = rng
	window = window_
	rounds = rounds_


## Seconds to wait before the next "!".
func next_delay() -> float:
	return _rng.randf_range(1.0, 3.0)


## A press `seconds` after the "!" (negative = before it). Returns
## "early", "win", "slow", or "over" once all rounds are played.
func press(seconds: float) -> String:
	if is_over():
		return "over"
	round += 1
	if seconds < 0.0:
		return "early"
	if seconds <= window:
		wins += 1
		return "win"
	return "slow"


func is_over() -> bool:
	return round >= rounds


func result() -> Dictionary:
	return {"won": wins * 2 > rounds, "score": wins}
