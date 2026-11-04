class_name SideSetup
extends RefCounted
## One side of a BattleSetup, before the battle starts.

## The creatures this side brings. The engine battles on copies of them and only
## writes the results back when asked (BattleEngine.commit), so these stay untouched
## until the battle is over.
var party: Array = []
## Field slots in this format (the most this side could have out at once).
var max_active := 1
## How many it actually fields (<= max_active). Fewer than the foe means Underdog.
var field_count := 1
## item id -> count. The engine uses its own copy.
var items: Dictionary = {}
## AI style ("basic", "aggressive", "tactician"), or "" for a side the caller controls.
var ai := ""
var is_wild := false
## Fill empty slots from the bench automatically at the end of each round.
var auto_replace := false
