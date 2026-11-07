class_name BattleText
extends RefCounted
## Turns one engine event into the message shown in the battle's text line.
## Returns "" for events that are shown only visually (bars, chips) or by the UI.
##
## `names` is a Callable(bid: int) -> String that returns a display name
## ("Tidepup", "Wild Sprigling", "Foe Voltmoth").

const STAT_NAMES := {"patk": "Physical Attack", "pdef": "Physical Defense", "satk": "Special Attack",
	"sdef": "Special Defense", "spd": "Speed", "acc": "Accuracy", "resolve": "Resolve", "luck": "Luck"}
const SILENT := ["round_start", "energy", "bond", "replacement_needed", "capture_attempt"]


static func describe(ev: Dictionary, db: Database, names: Callable, tamer_name: String = "") -> String:
	match ev.type:
		"battle_start":
			return "%s wants to battle!" % tamer_name if tamer_name != "" else "Wild creatures appeared!"
		"send_out":
			if ev.side == 0:
				return "Go, %s!" % _n(names, ev, "bid")
			if tamer_name != "":
				return "%s sent out %s!" % [tamer_name, _n(names, ev, "bid")]
			return "%s appeared!" % _n(names, ev, "bid")
		"move_used":
			return "%s used %s!" % [_n(names, ev, "bid"), db.move(ev.move).name]
		"item_used":
			return "%s used a %s." % [_n(names, ev, "bid"), db.item(ev.item).name]
		"swap_out":
			return "%s, come back!" % _n(names, ev, "bid") if ev.side == 0 else "%s withdrew %s." % [tamer_name, _n(names, ev, "bid")]
		"miss":
			return "%s avoided the attack!" % _n(names, ev, "target")
		"no_effect":
			return "It doesn't affect %s..." % _n(names, ev, "bid")
		"no_target":
			return "But there was no target..."
		"damage":
			var eff := float(ev.get("effectiveness", 1.0))
			if eff > 1.0:
				return "It's super effective!"
			if eff > 0.0 and eff < 1.0:
				return "It's not very effective..."
			if int(ev.get("by", -1)) == -1:
				return "%s is hurt!" % _n(names, ev, "bid")
			return ""
		"heal":
			return "%s recovered %d HP." % [_n(names, ev, "bid"), ev.amount] if ev.amount > 0 else "%s's HP is already full." % _n(names, ev, "bid")
		"status_applied":
			return "%s is now %s!" % [_n(names, ev, "bid"), db.status(ev.status).name.to_lower()]
		"status_failed":
			return "%s is already %s." % [_n(names, ev, "bid"), db.status(ev.has).name.to_lower()]
		"status_ended":
			if ev.get("cured", false):
				return "%s was cured of %s." % [_n(names, ev, "bid"), db.status(ev.status).name.to_lower()]
			return "%s is no longer %s." % [_n(names, ev, "bid"), db.status(ev.status).name.to_lower()]
		"action_skipped":
			return "%s is %s and can't act!" % [_n(names, ev, "bid"), db.status(ev.status).name.to_lower()]
		"stat_stage":
			var stat: String = STAT_NAMES.get(ev.stat, ev.stat)
			var change := int(ev.change)
			if change == 0:
				return "%s's %s won't change any further!" % [_n(names, ev, "bid"), stat]
			var how := "rose" if change > 0 else "fell"
			if absi(change) >= 2:
				how = "sharply " + how
			return "%s's %s %s!" % [_n(names, ev, "bid"), stat, how]
		"field_applied":
			var stacks := int(ev.stacks)
			return "%s covers %s!%s" % [db.field_state(ev.state).name, side_label(int(ev.side)),
				"" if stacks <= 1 else " (×%d)" % stacks]
		"field_removed":
			var state := db.field_state(ev.state).name
			var side := side_label(int(ev.side))
			match ev.reason:
				"expired": return "The %s on %s faded." % [state.to_lower(), side]
				"replaced": return "The %s on %s was replaced." % [state.to_lower(), side]
				"cashed_in": return "The %s on %s was used up." % [state.to_lower(), side]
				"cleared": return "The %s on %s was cleared away." % [state.to_lower(), side]
			return ""
		"reaction":
			return "%s! %s" % [db.reaction(ev.reaction).name, db.reaction(ev.reaction).description]
		"captured":
			return "Gotcha! %s was caught!" % _n(names, ev, "bid")
		"capture_failed":
			return "You can't catch another tamer's creature!"
		"faint":
			return "%s fainted!" % _n(names, ev, "bid")
		"xp_gain":
			return "%s gained %d XP." % [_n(names, ev, "bid"), ev.amount]
		"level_up":
			return "%s grew to level %d!" % [_n(names, ev, "bid"), ev.level]
		"move_learned":
			return "%s learned %s!" % [_n(names, ev, "bid"), db.move(ev.move).name]
		"move_offered":
			return "%s wants to learn %s, but already knows %d moves." % [_n(names, ev, "bid"), db.move(ev.move).name, db.balance.max_moves]
		"passive_triggered":
			var source: String = db.item(ev.item).name if ev.has("item") else db.passive(ev.passive).name
			return "%s's %s!" % [_n(names, ev, "bid"), source]
		"item_consumed":
			return "%s's %s was used up." % [_n(names, ev, "bid"), db.item(ev.item).name]
		"passive_unlocked":
			return "%s awakened %s!" % [_n(names, ev, "bid"), db.passive(ev.passive).name]
		"underdog":
			if float(ev.ratio) <= 1.0:
				return ""
			var extra := int(ev.bonus_actions)
			var bits := PackedStringArray()
			if extra > 0:
				bits.append("+%d action%s" % [extra, "" if extra == 1 else "s"])
			bits.append("+%d%% Atk/Def" % roundi(float(ev.stat_bonus) * 100.0))
			bits.append("+%d%% XP" % roundi(float(ev.xp_bonus) * 100.0))
			return "%s outnumbered! Underdog: %s." % ["You're" if ev.side == 0 else "The foe is", ", ".join(bits)]
		"pass":
			return "%s is waiting." % _n(names, ev, "bid")
		"rest":
			return "%s rests and recovers energy." % _n(names, ev, "bid")
		"fled":
			return "Got away safely!"
		"action_invalid":
			return "%s can't do that right now." % _n(names, ev, "bid")
		"endured":
			return "%s held on through sheer resolve!" % _n(names, ev, "bid")
		"resisted":
			return "%s resisted!" % _n(names, ev, "bid")
		"disobeyed":
			if ev.did == "":
				return "%s is ignoring you and loafing around!" % _n(names, ev, "bid")
			return "%s ignored your order!" % _n(names, ev, "bid")
		"lashed_out":
			return "%s lashed out at %s!" % [_n(names, ev, "bid"), _n(names, ev, "target")]
		"battle_end":
			match ev.reason:
				"fled": return ""
				"round_limit": return "The battle dragged on too long. It's a draw."
			return "You won!" if ev.winner == 0 else "You lost..."
	return ""


static func _n(names: Callable, ev: Dictionary, key: String) -> String:
	return names.call(int(ev.get(key, -1)))


static func side_label(side: int) -> String:
	return "your side" if side == 0 else "the enemy side"
