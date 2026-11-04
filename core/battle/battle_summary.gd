class_name BattleSummary
extends RefCounted
## What a finished battle did to the playthrough, handed from BattleLauncher.apply_results
## to the battle scene's results panel and then to the overworld (BattleFlow.after_battle).

const WON := "won"
const LOST := "lost"
const FLED := "fled"
const DRAW := "draw"
## A wild battle won by catching at least one creature.
const CAPTURED := "captured"

var outcome := ""
## Display names of the creatures caught.
var captured: Array[String] = []
## How many of the caught creatures went to storage (party full).
var to_storage := 0
## Prize money paid by a tamer.
var money := 0
## The player's creatures that levelled, in party order.
var progress: Array[ProgressEntry] = []
## The tamer fought, or "" for a wild battle.
var tamer_id := ""


static func of(p_outcome: String, p_progress: Array = [], p_tamer_id := "") -> BattleSummary:
	var s := BattleSummary.new()
	s.outcome = p_outcome
	s.progress.assign(p_progress)
	s.tamer_id = p_tamer_id
	return s


## A win or a catch.
func is_win() -> bool:
	return outcome == WON or outcome == CAPTURED
