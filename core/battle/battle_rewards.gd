class_name BattleRewards
extends BattlePart
## What a battle teaches its creatures: XP from knockouts, Bond changes and
## Affinity points. The formulas live in Progression; this decides when they apply.

## bid -> { affinity_id: points gained this battle }
var affinity_log: Dictionary = {}


## Affinity points for something `b` did (see balance.affinity_awards). Nothing a
## passive trigger's effects do earns any (PassiveRules.running).
func award(b: Battler, happening: String, times := 1) -> void:
	if b == null or engine.passive_rules.running():
		return
	var e := engine
	var points: Dictionary = e.db.balance.affinity_awards.get(happening, {})
	var before := b.creature.affinity_passive
	var aff := Progression.award_affinity(e.db, b.creature, happening, times)
	if aff == "":
		return
	# Only the player's creatures announce an awakening; a foe unlocks silently.
	if before == "" and b.creature.affinity_passive != "" and b.side == 0:
		e.emit({"type": BattleEvents.PASSIVE_UNLOCKED, "bid": b.bid, "passive": b.creature.affinity_passive})
	if not affinity_log.has(b.bid):
		affinity_log[b.bid] = {}
	affinity_log[b.bid][aff] = int(affinity_log[b.bid].get(aff, 0)) + int(points.points) * times


func bond(b: Battler, happening: String) -> void:
	var e := engine
	var change := Bond.change(e.db, b.creature, happening, e.setup.bond_gain if b.side == 0 else 1.0)
	if change != 0:
		e.emit({"type": BattleEvents.BOND, "bid": b.bid, "change": change, "bond": b.creature.bond,
			"reason": happening})


## Bond loss for fighting while worn out (once per battle per creature).
func check_overwork(b: Battler) -> void:
	if b.overworked:
		return
	var db := engine.db
	var cfg := db.balance.bond_cfg
	var low_hp := float(b.hp()) < float(b.creature.max_hp(db)) * float(cfg.overwork_hp)
	var low_energy := float(b.energy()) < float(b.creature.max_energy(db)) * float(cfg.overwork_energy)
	if low_hp or low_energy:
		b.overworked = true
		bond(b, "overworked")


## A creature fainted: Bond for it and its attacker, knockout credit, and XP
## for the player's side when a foe went down.
func on_faint(b: Battler) -> void:
	var e := engine
	bond(b, "fainted")
	var killer := e.battler(b.last_hit_by)
	if killer != null:
		award(killer, "knockout")
		bond(killer, "knockout")
	if b.side == 1:
		_award_xp_for(b)


func on_win(winner: int) -> void:
	for b in engine.sides[winner].battlers:
		if b.participated and not b.captured:
			bond(b, "battle_won")


func _award_xp_for(defeated: Battler) -> void:
	var e := engine
	if not e.setup.award_xp:
		return
	var bonus := float(e.sides[0].underdog.get("xp_bonus", 0.0))
	var amount := Stats.xp_reward(e.db.balance, defeated.creature.species_def(e.db).xp_yield,
		defeated.creature.level, not e.setup.is_wild, bonus)
	for p in e.sides[0].battlers:
		if p.participated and p.alive():
			var share := maxi(1, int(amount * Bond.xp_mult(e.db, p.creature) * e.setup.xp_mult))
			for ev in Progression.award_xp(e.db, p.creature, share, p.bid):
				e.emit(ev)
