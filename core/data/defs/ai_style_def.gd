class_name AiStyleDef
extends RefCounted
## One AI style: a profile of weights that BattleAI reads (see data/ai_styles.json and "AI styles" in
## documentation/battle-engine.md). 1.0 means "as the tactician does today".

var id: String
var name: String
var description: String
## Choose a random option, no scoring (basic).
var random: bool
## Weights on the terms of a move's score.
var damage: float
var ko: float
var retaliation: float
var setup: float
var buff: float
var heal: float
var rest: float
## The multiplier on setup effects (statuses, stages, energy, cures, field states) inside trigger values.
var trigger_setup: float
## Whether a foe's status triggers can raise the score of inflicting a status (false: capped at 0).
var seeks_status: bool
## "best" scores attacks by damage, "weakest" by how weak they are.
var attack: String
var swap: bool
var swap_margin: float
var swap_avoid: float


static func from_dict(d: Dictionary) -> AiStyleDef:
	var s := AiStyleDef.new()
	s.id = d.id
	s.name = d.name
	s.description = d.get("description", "")
	s.random = bool(d.random)
	s.damage = float(d.damage)
	s.ko = float(d.ko)
	s.retaliation = float(d.retaliation)
	s.setup = float(d.setup)
	s.buff = float(d.buff)
	s.heal = float(d.heal)
	s.rest = float(d.rest)
	s.trigger_setup = float(d.trigger_setup)
	s.seeks_status = bool(d.seeks_status)
	s.attack = d.attack
	s.swap = bool(d.swap)
	s.swap_margin = float(d.swap_margin)
	s.swap_avoid = float(d.swap_avoid)
	return s
