class_name BattleAction
extends RefCounted
## One choice for one action slot in a round.

var kind: String  # "move" | "item" | "swap" | "rest" | "flee" | "pass"
var actor: int  # bid
var move: String = ""
var item: String = ""
## Target bid for creature-targeted moves/items (-1 = engine picks).
var target: int = -1
## Second target bid for "two_enemies" moves (-1 = engine picks).
var second_target: int = -1
## Bench bid to bring in for "swap".
var swap_in: int = -1


static func use_move(actor_bid: int, move_id: String, target_bid: int = -1, second_target_bid: int = -1) -> BattleAction:
	var a := BattleAction.new()
	a.kind = "move"
	a.actor = actor_bid
	a.move = move_id
	a.target = target_bid
	a.second_target = second_target_bid
	return a


static func use_item(actor_bid: int, item_id: String, target_bid: int = -1) -> BattleAction:
	var a := BattleAction.new()
	a.kind = "item"
	a.actor = actor_bid
	a.item = item_id
	a.target = target_bid
	return a


static func swap(actor_bid: int, bench_bid: int) -> BattleAction:
	var a := BattleAction.new()
	a.kind = "swap"
	a.actor = actor_bid
	a.swap_in = bench_bid
	return a


## Spend the action recovering energy (balance.energy.rest_fraction of max).
static func rest(actor_bid: int) -> BattleAction:
	var a := BattleAction.new()
	a.kind = "rest"
	a.actor = actor_bid
	return a


static func flee(actor_bid: int) -> BattleAction:
	var a := BattleAction.new()
	a.kind = "flee"
	a.actor = actor_bid
	return a


static func pass_turn(actor_bid: int) -> BattleAction:
	var a := BattleAction.new()
	a.kind = "pass"
	a.actor = actor_bid
	return a


func describe() -> String:
	match kind:
		"move": return "%d:%s->%d" % [actor, move, target]
		"item": return "%d:item %s->%d" % [actor, item, target]
		"swap": return "%d:swap->%d" % [actor, swap_in]
	return "%d:%s" % [actor, kind]


## The slot to ask about after `action` was chosen for slot `i` of `needed` (one bid per action slot).
## A swap is the swapping creature's whole turn, so its remaining slots are skipped; anything else
## moves on by one.
static func next_slot(needed: Array[int], i: int, action: BattleAction) -> int:
	var next := i + 1
	if action.kind == "swap":
		while next < needed.size() and needed[next] == action.actor:
			next += 1
	return next
