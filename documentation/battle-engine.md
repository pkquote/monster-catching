# Battle Engine Reference (M1)

The battle engine lives in `core/battle/` and `core/progress/`. It never touches nodes, scenes or
autoloads. It takes a `Database`, a seeded `RandomNumberGenerator` and a `BattleSetup`, and
reports everything that happens as a list of event dictionaries. The M2 battle scene will play
those events back as animations and never compute outcomes itself.

Tuning numbers live in `data/balance.json`; see the Balance section of the
[compendium](compendium.md) for current values.

## Using the engine

```gdscript
var rng := RandomNumberGenerator.new()
rng.seed = some_seed                       # same seed + same choices = same battle
var setup := BattleSetup.vs_tamer(db, player_party, "rival_01")   # or BattleSetup.wild(...)
var engine := BattleEngine.new(db, rng, setup)
var events := engine.start()

while not engine.is_over():
    var actions := []
    for bid in engine.actions_needed(0):     # one entry per action slot (Underdog repeats a bid)
        actions.append(BattleAction.use_move(bid, "riptide", target_bid))
    events = engine.resolve_round(actions)   # AI sides pick their own actions
    for i in engine.pending_replacements(0):
        engine.replace(0, chosen_bench_bid)  # optional: leaving a slot empty keeps you outnumbered

var result := engine.result()  # { winner, reason, captured, rounds, affinity }
engine.commit(0)               # write the player's creatures back (BattleLauncher does this)
```

- Side 0 is always the player. Battlers are identified by a battle-unique `bid`.
- The battle works on **copies** of the creatures in the setup. HP, energy, status, XP, level,
  moves, Bond and Affinity change on the copies (`engine.battler(bid).creature`); the originals
  (`battler.source`) are untouched until `engine.commit(side)` writes the copies back. A battle
  that's abandoned is simply never committed, and nothing outside the battle changes while it runs.
  Captured creatures are not written back; `result().captured` holds them.
- Each side of a `BattleSetup` is a typed `SideSetup` (`party`, `max_active`, `field_count`,
  `items`, `ai`, `is_wild`, `auto_replace`).
- `BattleSetup.wild(party, pack, field_count)` and `BattleSetup.vs_tamer(db, party, tamer_id, field_count)`
  let the player field fewer creatures than the format allows, which triggers Underdog.

### Targeting

Move targets: `self`, `one_ally`, `one_enemy`, `two_enemies`, `all_allies`, `all_enemies`, `all`, `own_side`, `enemy_side`.

- `targets_for(bid, move_id)` lists the legal first picks (the standing foes for `one_enemy` and `two_enemies`, `[-1]` when no choice is needed).
- `two_enemies` hits two distinct standing foes: `BattleAction.target` and `BattleAction.second_target`. `second_targets_for(bid, move_id, first)` lists the legal second picks (the other standing foes).
- `resolve_targets` keeps each valid pick (a standing, active foe), drops a missing, invalid or duplicate one, then fills the gaps at random from the remaining standing foes. With one foe left the move hits just that one (and takes no spread reduction); with none it reports `no_target`.
- In the battle scene the player picks in two steps: `BattleScene._choose_target` shows the first menu, then `_choose_two_targets` shows a second menu titled with the first pick's name. Cancelling the second step returns to the first. With two or fewer foes standing the menu is skipped.

### Multi-hit moves

A `one_enemy` move may carry `"hits": {"min": 2, "max": 5}`: one use hits its target that many times (`min == max` is a fixed count; a move without `hits` hits once). `balance.max_hits` (5 in the shipped data, 2–10 allowed) caps `hits.max`, and the validator rejects `hits` on any other target. `MoveDef.hits_min`, `hits_max`, `is_multi_hit()` and `mean_hits()` expose it.

- **Accuracy is rolled once per move,** as for any move, against the chosen target. If it connects, every hit lands, spill hits included. A miss deals no hits and emits no `hit_count`.
- **The whole `effects` list runs once per hit** (`ActionRunner._run_hits`): a status chance is rolled per hit and a self effect on the move would stack per hit, so such moves are balanced one by one. `EffectContext.hit_index` is the 0-based hit. The count is drawn from the battle RNG only for multi-hit moves, so other moves' seeded outcomes are unchanged. `finish_consume` runs once, after the last hit.
- **Each hit goes through `deal_damage`,** so hit triggers (passive and held), the once-per-battle Resolve endure and type absorption apply to every hit. `hit_dealt` and `hit_survived` Affinity is earned once per move use, not per hit (`BattleEngine.begin_multi_hit` / `_award_hit`).
- **A faint is processed between hits.** After each hit `check_faints()` runs: the creature faints at once (its `faint` event and its faint and knockout triggers), then the remaining hits go to the next standing active foe in slot order, wrapping around the side (`BattleEngine.next_foe_after`). Spill hits take no new accuracy roll and no spread penalty (`spread_count` stays 1). Benched creatures are never hit and no replacement enters mid-move (replacements come at end of round).
  Example, 3 foes in slots 0, 1, 2, the user aims `triple` (3 hits) at slot 2, which has 1 HP: `damage` slot 2, `faint` slot 2, then `damage` slot 0 twice.
- **Each hit starts fresh:** `ctx.mult` (a `bonus_if_field` multiplier) is reset before every hit, so a field cash-in applies once per hit and does not compound; the consumed state is removed once, after the last hit.
- **A hit that neither hurts nor is absorbed ends the move** (an immune foe: "It doesn't affect X..." shows once, not once per hit). Such a hit is not counted, so `hit_count.hits` is 0 and no "Hit N times!" line shows; a hit absorbed by a passive does count (the absorber heals every hit). The op sets `EffectContext.connected` when it dealt or absorbed damage.
- **The move ends early** when no foe is left standing, when the battle is decided, or when the user itself faints (for example to a damaging hit trigger).
- **`hit_count`** `{bid, hits}` closes a multi-hit move with the number of hits that landed (a 5-hit roll that finished the last foe on hit 3 reports 3); it comes before `battle_end` when the move ended the battle. The battle text line reads "Hit N times!" for N of 2 or more. In the battle's move menu (`BattleText.move_label`) and the Learn Move / Summary line (`LearnMoveScreen.move_line`) a multi-hit move's power carries its count, "P20 x3" / "Power 16 x2-5" (`EffectText.hits_short`), so it is not read as a weak single hit.

### Actions

| Action | Constructor | Notes |
| --- | --- | --- |
| Move | `BattleAction.use_move(bid, move_id, target_bid, second_target_bid)` | Target is only needed for `one_enemy` / `one_ally` / `two_enemies` moves; `second_target_bid` is only read for `two_enemies`. An invalid target is replaced with a random valid one: a standing foe for `one_enemy` / `two_enemies`, a standing ally (the user included) for `one_ally`. |
| Item | `BattleAction.use_item(bid, item_id, target_bid)` | Uses up one item from the side's bag. Capture items only work in wild battles. Healing items can target benched allies. |
| Swap | `BattleAction.swap(bid, bench_bid)` | The creature leaving the field has its stat stages reset. |
| Rest | `BattleAction.rest(bid)` | Restores `rest_fraction` of max energy instead of acting. |
| Flee | `BattleAction.flee(bid)` | Wild battles only; always succeeds. |
| Pass | `BattleAction.pass_turn(bid)` | Does nothing. |

## Round order

1. Actions sort by priority (Flee 7, Swap 6, Item 5, then each move's own `priority`), then
   effective Speed, then a seeded random tie-break.
2. Each action runs if its creature is still on the field and conscious. Shock-style
   `skip_chance` statuses can cancel a move.
3. Faints are checked after every action, and the battle can end mid-round.
4. At end of round: status effects run (e.g. Burn damage) and count down, passive `round_end`
   triggers fire (fastest first), field states count down,
   AI and wild sides refill empty slots, the player gets `replacement_needed`, and Underdog is
   recalculated.
5. After `round_limit` rounds the battle ends in a draw (`reason: "round_limit"`).

## Formulas

| What | Formula |
| --- | --- |
| HP | `2·base·pct·Lv/10000 + Lv + 10` (`pct` = growth tier percent: slow 80, steady 100, fast 120) |
| Atk / Def / Spd | `2·base·pct·Lv/10000 + 5` |
| XP to reach a level | `Lv³` |
| Stat stages (−6…+6) | Atk/Def/Spd: `(2+s)/2` or `2/(2−s)`. Accuracy: `(3+s)/3` or `3/(3−s)` |
| Max energy | `2·base_stamina·pct·Lv/10000 + energy.base` (+1 per Stamina training point) |
| Training | Each point adds +1 to a stat, +`hp_per_point` to HP |
| Effective stat | raw (incl. training) × stage × passive `stat_mod`s (status, own side's field states and creature passives) × (1 + Underdog stat bonus, P/S Atk and Def only) |
| Damage | `((2·Lv/5 + 2) · power · A/D) / 50 + 2` × same-type bonus × type matchup × field bonus × attacker's `type_power` (and `scrap_power` for Scrap, `reaction_power` for its reactions) × target's `incoming_type_mod`s (side field states and passives) × spread × Bond performance × roll(0.85–1.0), minimum 1. `A/D` is P.Atk/P.Def for physical moves and S.Atk/S.Def for special moves |
| Spread | Moves hitting more than one creature: × `spread_mult_for(count)` × (1 − target side's Underdog spread reduction). `balance.spread_mults` is a table keyed by the number of creatures hit (`{"2": 0.85, "3": 0.75}`); only keys "2" and "3" are allowed, and three or more creatures use the "3" value. `count` is the creatures the move actually hits (`ActionRunner` sets `EffectContext.spread_count`), so a `two_enemies` move with one foe left is not reduced. Underdog's reduction stacks on top. |
| Reaction damage | Uses the triggering creature's level with Atk/Def = 1, no same-type bonus. `scale_with_stacks` multiplies power by stacks consumed |
| Hit chance | `accuracy × accuracy multiplier` (includes Bond performance). Moves on yourself or allies, and `always_hits` moves, never miss |
| Resolve resistance | `resist_cap × R / (R + R_avg)`; `R_avg` = Resolve of a base-50 creature at the attacker's level. Applies to statuses and to stat drops from foes |
| Endure | Same formula with `endure_cap`; once per battle, a knockout blow from a foe leaves 1 HP |
| Catch chance | `catch_rate × item mult × (1 − HP% × hp_weight) × status bonus × field bonuses on the target's side`, clamped 0–1 |
| XP per defeated foe | `yield × level / divisor` (× `tamer_mult` vs tamers) × (1 + Underdog XP bonus). Every conscious creature that has been on the field gets the full amount |

## How the shipped species are tiered (M6b)
Every shipped species gets growth tiers from one rule (pinned in `tests/data/test_growth_tiers_data.gd`, which lists every
species' tiers): a stat 8 or more above the species' own average across its nine base stats is `fast`, 8 or more below is
`slow`, at most two of each, biggest gaps first. Two fast and two slow net 0 against `growth_budget`, so a species'
total growth stays neutral and only its shape changes: specialists grow more specialised. A species with no stat that
far from its average (Tidepup, Frostling) stays all-steady. Ties are broken by hand (see the test). When you add a
species, apply the same rule and add it to that test; the validator only warns when a species is over budget.

The three starters each evolve at Lv 16 by dominant Affinity (with a default branch): Tidepup into Torrentusk or Mistcoil,
Emberkit into Blazefox (Striker and default) or Cinderwisp (Catalyst), Sprigling into Thornwall (Warden and default) or
Mossweaver (Trickster). Starters and evolved forms are never in an encounter table; the evolved forms are evolution-only.

## Energy

- Every move has a `cost`, paid when the move is used. A move costing more than the creature's
  current energy is rejected (`action_invalid`, reason `no_energy`). `engine.usable_moves(bid)` lists
  what the creature can afford right now.
- Energy lives on the `CreatureInstance` and carries between battles. It only refills in battle
  through Rest or items with `restore_energy`.
- The fallback move (`energy.fallback_move`, Scrap) costs nothing and is always usable, even
  though it is not in any learnset.
- `BattleSetup.exhibition` (default false, set by `BattleLauncher.exhibition_setup`) marks a debug custom battle: its teams are temporary creatures, and the flag suppresses everything that would reach the save (XP/Bond/HP/bag/money/capture writes, defeat rules, the "patched up" line, autosave, progress screens); the results panel says "Exhibition — nothing was saved."
- `BattleSetup.award_xp = false` turns off XP (the simulator does this, since only side 0 earns XP).
- `BattleSetup.xp_mult` and `bond_gain` (default 1.0) scale side 0's XP and positive Bond changes
  (rounded, at least 1; losses are never scaled). `BattleLauncher` sets both from the party lead's
  overworld passive (`Passives.field_mult`).

## Bond

Bond (−100…+100) is stored on the `CreatureInstance`. Changes come from `balance.bond.changes`:

| Happening | When |
| --- | --- |
| `battle_won` | Every creature on the winning side that took part |
| `knockout` | The creature that landed the blow |
| `fainted` | The creature that fainted |
| `healed_item` | A creature healed by an item |
| `overworked` | Sent out or ordered to act below `overwork_hp` HP or `overwork_energy` energy (once per battle) |
| `rested` | `Bond.rest()` at a rest point (overworld) |

Negative Bond, scaling linearly to `bond.min`: a `disobey_max_chance` chance to use a random
other usable move or loaf around (`disobeyed`), a `penalty_max` cut to accuracy and damage, and
at `lash_out_threshold` or below a `lash_out_chance` chance to Scrap itself or an ally instead
(`lashed_out`). Positive Bond multiplies XP by up to `1 + xp_bonus_max`.

## Field states and reactions

- Each side holds up to `max_field_states` states (shipped: 1). A new state that doesn't react with the current one replaces the oldest (`field_removed`, reason `replaced`). With a cap of 1 a side's state is removed by a reaction that consumes it or by a different state applied over it; setting up the next state is a choice the player makes.
- Re-applying a state the side already has adds stacks (up to its `max_stacks`) and refreshes its duration.
- Applying a state that reacts with one already there fires the reaction instead:
  - States listed in `consumes` are removed. Their stacks (plus the incoming stacks, if the incoming state is consumed) become `stacks_consumed`.
  - The incoming state still lands unless the reaction consumes it. Every reaction must consume at least one of its two inputs (validator), so a one-state side is never left holding both.
  - The reaction's effects run against the side it fired on (`scope: side`) or everyone (`scope: both_sides`). In reaction effects, `all_allies` means that side's creatures.
  - States that a reaction's own effects apply never trigger another reaction (no chains).
- `bonus_if_field` multiplies the damage or heal that follows it in the same move. With `consume: true`, the state is removed after the move finishes.

## Statuses

- One status per creature at a time. Applying another fails (`status_failed`).
- A status lasts its data-defined `turns`, counted at end of round. It is stored on the
  `CreatureInstance`, so it carries over between battles until healed.

## Underdog

When one side has fewer creatures on the field (`r = enemy / ally > 1`):

| Bonus | Value |
| --- | --- |
| Extra actions per creature each round | `floor((r − 1) × bonus_actions_per_ratio)` (at 0.5: 1v2 +0, 1v3 +1, 2v3 +0) |
| Physical/Special Atk and Def | `+stat_bonus_per_ratio × (r − 1)`, capped |
| Damage taken from spread moves | `−spread_reduction_per_ratio × (r − 1)`, capped |
| XP | `+xp_bonus_per_ratio × (r − 1)` |

It is recalculated at battle start, after replacements, and at the end of every round.

A swap is the swapping creature's whole turn: its other action slots that round are dropped and the newcomer does not act. The battle scene stops asking for those slots once a swap is picked (`BattleAction.next_slot`).

## Affinity

Battle happenings add points to Affinity tracks on the creature responsible. The point values
come from `balance.affinity_awards`:

| Happening | Credited to |
| --- | --- |
| `hit_dealt`, `knockout` | The attacker |
| `hit_survived` | The creature that took the hit and stayed up |
| `heal` | The healer |
| `field_applied`, `reaction_triggered`, `field_cashed_in` | The creature whose move did it |
| `status_inflicted`, `stat_lowered` | The creature that inflicted it on a foe |

A knockout is credited to the last creature that damaged the one that fainted (`Battler.last_hit_by`), so a status tick that delivers the final HP still credits whoever hit it last, and an absorbed hit never counts as a hit. This is deliberate: the status was part of that attacker's pressure, and it keeps a tick from awarding nothing.

Nothing a passive trigger's effects do earns Affinity (for anyone), so a passive can't steer which
Affinity passive unlocks or which growth branch is taken. Bond is unaffected.

`Progression.growth_target(db, creature)` picks the growth branch. It uses the lowest growth level
the creature has reached, then the branch matching its dominant Affinity if that track has at least
`growth_affinity_threshold` points, and otherwise the default branch.
`Progression.apply_growth` changes the species. Showing and confirming growth is M4 UI work.

## Passives

Every creature has a rolled passive (`CreatureInstance.passive`, picked from the species'
`passives` list when it is made) and may unlock an Affinity passive (`affinity_passive`). The first
time one of its Affinity tracks reaches `growth_affinity_threshold` (30) and the species lists a
passive for that track (`affinity_passives`), `Progression.award_affinity` sets it, once per
creature. In battle that emits `passive_unlocked`; the after-battle Passive Unlocked screen then
offers to switch. `active_passive` (`"rolled"` or `"affinity"`) picks which one is active, and
**only the active passive does anything** (`Passives.active_id`, `Passives.set_active`). The design
is [documentation/specs/2026-11-04-passives-design.md](specs/2026-11-04-passives-design.md);
the definitions live in `data/passives/*.json`.

A passive definition has up to three lists:

| List | What it holds |
| --- | --- |
| `effects` | Always-on effects, each with an optional `when` (`hp_below`, `underdog`, `field` + `side`), checked on every read. With `scope: "allies"` they are an aura on every creature on the holder's side of the field, the holder included (the `when` is checked on the holder) |
| `triggers` | `{ on, chance?, contact?, effects }`. The effects are ordinary effect ops run with `source: "passive"` |
| `field` | Overworld effects of the party lead's active passive: `encounter_rate`, `xp_mult`, `bond_gain` (`Passives.field_mult`) |

Always-on ops: `type_power`, `stat_mod`, `incoming_type_mod`; protection: `status_immune`,
`guard_stages` (foes only; its own side can still lower its stages), `field_shelter` (that state's
effects skip it and its reactions don't damage it); game-specific: `field_boost`, `reaction_power`,
`energy_discount` (never below 0; also decides which moves are affordable), `rest_bonus`,
`scrap_power`; and `absorb_type` (damage of that type heals a share of max HP instead, even through
a type immunity, and doesn't count as a hit). `engine.passives(b)` returns every always-on effect currently
on `b`: its side's field states (minus any it shelters from), its status, and
`engine.passive_rules.effects_for(b)` (its own active passive plus allied auras).

| Trigger `on` | Fires | Effects land on (no `target` of their own) |
| --- | --- | --- |
| `enter` | Placed on the field: swap, replacement, or battle start (after both sides are placed, fastest first; ties by bid) | itself |
| `hit` | Took damage from a foe and is still standing. `contact: true` = physical moves only | the attacker |
| `round_end` | End of each round while on the field, before field states count down (fastest first) | itself |
| `knockout` | It knocked out a foe | itself |
| `faint` | It fainted | the creature that knocked it out |
| `status` | A status was just applied to it (after `status_applied`; a blocked, resisted or failed status doesn't fire it) | itself |

Rules:

- Only creatures on the field and standing contribute, receive or fire anything (a `faint`
  trigger fires as its creature goes down). Nothing fires once the battle is decided, including
  the faint that decides it.
- Multipliers from different sources multiply. An aura counts once per passive id, however many
  allies hold it.
- Effects run by a trigger never set off further passive triggers (a depth guard in
  `PassiveRules`), and a creature a trigger's effects knock out fires no `faint` or `knockout`
  triggers. That includes `status`: a status given by another trigger's effects (a contact-burn
  passive, say) does not set off the target's `status` trigger.
- `chance` (1–100) rolls the battle RNG only when it is below 100.
- A trigger whose effects would all do nothing (only `heal` on creatures at full HP,
  `restore_energy` on creatures at full energy and `cure_status` on creatures with no matching
  status) is skipped: no banner, no events, and a consumed held item is not used up. Any other op
  counts as doing something.

`passive_triggered { bid, passive }` is emitted whenever a passive visibly acts: before a
trigger's effects run, and when a passive **blocks or absorbs** something: `status_immune` stops
a status, `guard_stages` stops a foe's stat drop, `field_shelter` stops a reaction's damage, or
`absorb_type` turns a hit into healing. In a block or an aura, `bid` is the creature whose passive
did it (the aura holder, not necessarily the protected creature). Always-on multipliers are silent.
The battle scene shows it as a small banner over that creature ("Tidepup's Undertow!") that fades
on its own while the effect's own events play.

## Held items

An item with category `held` carries a `held` block, parsed into `ItemDef.held` (a `PassiveDef` with the item's own
id, name and description) and `ItemDef.held_use`. A creature holds one (`CreatureInstance.held_item`; tamer party
members may set `held_item` too). `PassiveRules.effects_for` and `fire` treat the held item as a second source
beside the active passive: its always-on `effects` (and `scope: "allies"` auras) and its `triggers` work exactly
as above, and the banner names the item ("Tidepup's Oran Berry!"). The overworld `field` list of the party lead's
held item combines with the passive's in `Passives.field_mult`. Design:
[documentation/specs/2026-11-05-held-items-design.md](specs/2026-11-05-held-items-design.md); the items live in
`data/items/held.json`.

A trigger may carry a `when` (same conditions as an always-on effect: `hp_below`, `underdog`, `field` + `side`),
checked on the holder when the trigger would fire; a failing `when` fires nothing, emits no banner and does not
spend the item. Triggers on passives may use it too.

| `use` | Behaviour |
| --- | --- |
| `permanent` (default) | Always held; always-on effects and triggers work every time |
| `consumed` | Needs at least one trigger and no always-on `effects`. The first time a trigger fires, the item is spent: `item_consumed { bid, item }` is emitted ("Tidepup's Oran Berry was used up."), the battler loses it, and the creature really has no item after the battle |
| `per_battle` | Needs at least one trigger and no always-on `effects`. The item fires once per battle: the first trigger that fires spends it for the rest of that battle. The creature keeps the item and it is ready again next battle |

`item_consumed` follows the `passive_triggered` banner of the same trigger (the effects run between them). Held
items give no bag use and cannot be given in battle. The effects a held item's trigger runs earn no Affinity,
like any passive trigger.

## AI

An AI-controlled side (a tamer's `ai`, wild creatures) gets its actions from `BattleAI.choose_all` at the start of
`resolve_round`, and refills its own empty slots (`auto_replace`). How it chooses is a style, a data entry in
`data/ai_styles.json`: `basic` picks at random, `aggressive` maximises expected damage, `tactician` adds setup,
reactions, statuses and swapping, and `passive`, `defensive` and `trickster` reweigh those terms. Styles, scoring,
swapping and what the AI values from passives, held items and triggers are in [ai.md](ai.md).

## Code layout

`BattleEngine` is the public face: the battle screen, the AI and effect ops call only it. It owns the
battle state, targeting, the mutations effect ops use (`deal_damage`, `heal`, `inflict_status`...)
and the round loop, and hands the rest to four parts (each extends `BattlePart`, which holds the
engine weakly so the engine can be freed):

| Part | File | Owns |
| --- | --- | --- |
| `engine.actions` | `action_runner.gd` | turn order; running moves (energy, skipped turns, Bond misbehaviour), items, swaps, Rest, fleeing |
| `engine.field_rules` | `field_rules.gd` | applying, stacking, pushing out, expiring and cashing in field states; reactions |
| `engine.rewards` | `battle_rewards.gd` | XP from knockouts, Bond changes, Affinity points and the per-battle Affinity log (and `passive_unlocked`) |
| `engine.passive_rules` | `passive_rules.gd` | creature passives: always-on effects and auras, `when` conditions, triggers and the depth guard, protection checks, energy and damage multipliers |

## Events

Event names are constants in `BattleEvents` (`core/battle/battle_events.gd`); emit with those, not
string literals. In debug builds `emit()` reports unknown types, and `tests/battle/test_battle_events.gd`
checks that real battles only send known types and that `BattleText` describes each type or lists it
in `SILENT`. To add an event: add the constant (and to `ALL`), emit it, add a row here, and handle it
in `BattleText` (and `BattlePlayback` if it changes what's on screen).

| Event | Key fields |
| --- | --- |
| `battle_start` | `wild`, `tamer`, `slots` |
| `send_out` | `side`, `slot`, `bid`, `species`, `level`, `hp`, `max_hp`, `energy`, `max_energy` |
| `round_start` | `round` |
| `move_used` | `bid`, `move`, `targets`, `side` |
| `item_used` | `bid`, `item`, `targets`, `left` |
| `swap_out` | `bid`, `side`, `slot` (followed by `send_out`) |
| `miss`, `no_effect`, `no_target` | `bid`, `target` |
| `hit_count` | `bid` (the user), `hits` (hits landed; multi-hit moves only) |
| `damage` | `bid`, `amount`, `hp`, `max_hp`, `by`, `damage_type`, `effectiveness` |
| `endured` | `bid` (survived at 1 HP through Resolve) |
| `resisted` | `bid`, `status` or `stat` |
| `energy` | `bid`, `change`, `energy`, `max_energy` |
| `rest` | `bid` |
| `bond` | `bid`, `change`, `bond`, `reason` |
| `disobeyed` | `bid`, `ordered`, `did` (`""` = loafed around) |
| `lashed_out` | `bid`, `target` |
| `heal` | `bid`, `amount`, `hp`, `max_hp` |
| `status_applied`, `status_failed`, `status_ended` | `bid`, `status` (`has` on failure; `status_ended` also has `cured: true` when a `cure_status` effect cleared it, absent when it ran out) |
| `action_skipped` | `bid`, `status` |
| `stat_stage` | `bid`, `stat`, `change`, `stage` |
| `field_applied` | `side`, `state`, `stacks`, `turns`, `by` |
| `field_removed` | `side`, `state`, `reason`: `expired` \| `replaced` \| `reacted` \| `cashed_in` \| `cleared` |
| `reaction` | `reaction`, `side`, `inputs`, `stacks`, `by` |
| `capture_attempt` | `bid`, `target`, `item`, `chance`, `success` |
| `capture_failed` | `bid`, `target`, `reason` (`not_wild`: a capture item used on a tamer's creature) |
| `captured` | `bid`, `species` |
| `faint` | `bid`, `side` |
| `xp_gain`, `level_up`, `move_learned`, `move_offered` | `bid`, `amount` / `level` / `move` |
| `passive_triggered` | `bid`, `passive` (a trigger fired, or a passive blocked a status, a foe's stat drop or reaction damage, or absorbed a hit; see Passives) |
| `passive_unlocked` | `bid`, `passive` (an Affinity track first reached the threshold and unlocked the Affinity passive) |
| `underdog` | `side`, `ratio`, `bonus_actions`, `stat_bonus`, `spread_reduction`, `xp_bonus` |
| `replacement_needed` | `side`, `count` |
| `pass`, `fled` | `bid` |
| `action_invalid` | `bid`, `reason` |
| `battle_end` | `winner` (−1 = none), `reason`: `defeat` \| `fled` \| `round_limit`, `captured`, `rounds` |

## Effect ops

Moves, items, statuses, passives, held items and reactions are lists of effects: `{"op": ..., fields...}`. Every op may
also carry `target` (who it lands on; see Targeting) and a trigger or passive effect may carry `when`. The fields and
ranges are `DataSchemas.EFFECT_OPS`; a test fails if this table misses an op. `EffectText.effect()` writes the sentence
the compendium shows.

| Op | Fields | Does |
| --- | --- | --- |
| `damage` | `power`, `type`, `scale_with_stacks` | Deals damage (the move's own power and type unless given); `scale_with_stacks` scales with the stacks a reaction consumed |
| `heal` | `fraction` | Restores that fraction of max HP |
| `restore_energy` | `fraction` | Restores that fraction of max energy |
| `apply_status` | `status`, `chance` | Inflicts a status (blocked by `status_immune`, or a creature that already has one) |
| `cure_status` | `status` | Cures that status, or any status when none is named |
| `stat_stage` | `stat`, `stages` | Raises or lowers a stat stage (-3 to 3 per effect; stages reset on leaving the field) |
| `apply_field_state` | `side`, `state`, `stacks`, `turns` | Puts a field state on a side (see Field states and reactions) |
| `remove_field_state` | `side`, `state` | Clears one state, or every state when none is named |
| `bonus_if_field` | `side`, `state`, `mult`, `consume` | Multiplies the move's damage while that state is on the side; `consume` uses it up (a cash-in) |
| `damage_fraction` | `fraction` | Status effect: loses that fraction of max HP each round |
| `skip_chance` | `chance` | Status effect: that percent chance to lose its action |
| `stat_mod` | `stat`, `mult` | Always-on multiplier on a stat (a status, passive, held item or field state) |
| `incoming_type_mod` | `type`, `mult` | Damage taken (of that type, or all) is multiplied |
| `type_power` | `type`, `mult` | Moves of that type deal more or less |
| `absorb_type` | `type`, `fraction` | Damage of that type heals this fraction of max HP instead |
| `status_immune` | `status` | Cannot be given that status, or any |
| `guard_stages` | `stat` | Foes cannot lower that stat, or any |
| `field_shelter` | `state` | Sheltered from that field state's effects |
| `field_boost` | `stacks`, `turns` | Field states this creature applies get extra stacks and rounds |
| `reaction_power` | `mult` | Reactions this creature triggers hit harder or softer |
| `energy_discount` | `type`, `amount` | Moves (of that type, or all) cost less energy |
| `rest_bonus` | `fraction` | Rest restores extra max energy |
| `scrap_power` | `mult` | The fallback move Scrap deals more or less |
| `encounter_rate` | `mult` | Wild encounter rate (overworld) |
| `xp_mult` | `mult` | XP the creature earns |
| `bond_gain` | `mult` | Bond gains |
| `capture` | `mult`, `field_bonus` | A capture item's strength, with a bonus per field state on the target's side |
| `reset_training` | none | Returns all spent training points (field use only) |

## Adding a new effect op

1. Add its fields to `DataSchemas.EFFECT_OPS` in `core/data/schemas.gd`.
2. Write `core/battle/effects/op_<name>.gd`, extending `EffectOp`. Override `per_target()` to return
   false for side-level effects.
3. Register it in `EffectOps.get_op()`. A test fails if the schema lists an op that has no handler.
4. Describe it in `EffectText.effect()` in `core/data/effect_text.gd`.

## Balance simulator

```bash
godot --headless --path . --script res://tools/simulate.gd -- --battles=500 --format=2v2 --level=10 --ai=tactician,aggressive
```

It prints win rates per side, draws, average rounds, how often each reaction fires, and each
species' win rate. `--party` is clamped to 1..`balance.party_size` and never below the larger
fielded side (with `party_size` 6, `--party=12` runs with 6 and says so). Battle `i` uses one RNG
seeded `seed + i` for the parties (species and rolled passives) and the battle, so a seed replays. Passives vary with the seed now (the battle RNG is passed to `CreatureInstance.create`), so numbers differ from older runs.

`--pack=1` (the default) also loads the debug test content pack (`res://data_testpack`, skipped
when the folder is missing) and draws species from `data/` plus the pack; `--pack=0` uses `data/`
only. The species table prints each id next to its name, so `tp_` rows stand out:

```bash
godot --headless --path . --script res://tools/simulate.gd -- --battles=50 --format=2v3 --party=6 --pack=0
```

## Test content pack

`data_testpack/` is a debug-only body of content (30 creatures, 92 moves, 35 passives, 27 items,
6 tamers, 4 encounter tables) built to exercise the engine far beyond the 8 shipped creatures: every
effect op, move target kind, trigger, `when` condition and held-item use kind, extreme stats and
costs, and dummies named for what they test (`tp_water_wall`, `tp_chain_a`, ...). It is a scaffold
and will be deleted as the real creature set grows. Spec:
[2026-11-05-test-content-pack-design.md](specs/2026-11-05-test-content-pack-design.md).

- **Loading.** `DataLoader.load_database(data_root, dialogue_root, packs)` reads each pack root
  like `data/` (missing category folders are skipped, a pack `balance.json` is ignored) and merges it
  before validation, so a clashing id or a dangling reference is an ordinary validation error.
  `DataRegistry` passes `PACK_ROOT` (`res://data_testpack`) only when `OS.is_debug_build()` and the
  folder exists, so release builds and clones without the folder never see it. If `data/` plus
  the pack fails validation, `DataRegistry.load_with_fallback` logs the errors (`Log.DATA`, error)
  and loads `data/` alone, so a broken pack can't stop a debug session.
  `DataLoader.pack_has_entries(root)` tells whether a root holds any content.
- **The `tp_` rule.** Every pack id starts with `tp_`; `Database.is_test_content(id)` is that prefix
  check. The pack reuses types, statuses, field states, reactions, affinities and balance from
  `data/`, and nothing in `data/`, maps, shops, story or the compendium refers to it.
- **Saves.** Pack content must never reach a real save. Code that picks a random species for a
  party or box uses `BattleLauncher.save_safe_species(db)` (sorted, no `tp_` ids), as F1 **Fill
  box** does through `BattleLauncher.fill_box`; F1 **Set passive**, which writes to the real party,
  lists only `DebugPassivePage.save_safe_passives(db)`. Wild and tamer rolls have no filter: they
  read their tables, and the base-only validation pass proves shipped tables name only shipped
  content. Any new picker that writes a content id into a save must filter with
  `Database.is_test_content`.
- **F1 builder.** In a debug build, F1 → **Custom battle** lists the whole database, so every pack
  creature, move, held item and passive is pickable (the `tp_` names make them easy to spot), and
  the foe randomiser draws from it. Custom battles are exhibitions, so nothing is saved.
- **Simulator.** `tools/simulate.gd --pack=1` (default) includes the pack, `--pack=0` excludes it.
- **Validation.** `tools/validate_data.gd` (and `scripts/check.sh`) prints `Data OK` for `data/`
  alone and `Data+pack OK` for `data/` plus the pack (only when the pack has content).
- **Coverage guard.** `tests/helpers/pack_coverage.gd` lists every op, target kind, trigger, `when`
  key, use kind, type, status and field state in `DataSchemas` and reports what no pack entry uses;
  `tests/data/test_testpack_coverage.gd` fails when the schemas gain one the pack doesn't cover.
- **Suites.** `tests/data/test_testpack_*.gd` (loader, content per category, coverage, removal),
  `tests/battle/test_testpack_mechanics.gd` (one pinned behaviour per mechanic family),
  `tests/battle/test_testpack_simulations.gd` (seeded AI battles over the whole pack, below) and
  `tests/game/test_testpack_safety.gd` (Fill box, wild and tamer paths never yield `tp_` content).

### Removal checklist

1. Delete `data_testpack/`.
2. In `game/autoload/data_registry.gd`, delete `PACK_ROOT` and the `packs` var/if/append in
   `_ready`, and call `DataLoader.load_database(DATA_ROOT, DIALOGUE_ROOT)` (the
   `load_with_fallback` helper can go too).
3. Delete `tests/data/test_testpack_*.gd`, `tests/battle/test_testpack_*.gd`,
   `tests/game/test_testpack_safety.gd`, `tests/helpers/pack_coverage.gd` and
   `tests/helpers/test_pack_coverage.gd` (with their `.uid` files).
4. In `scripts/check.sh`, drop `|Data\+pack OK` from the `== Data` grep; in
   `tools/validate_data.gd`, the pack pass (it is already skipped when the folder is missing); in
   `tools/simulate.gd`, the `--pack` option (optional: it is a no-op without the folder).
5. Docs: remove the `data_testpack/` bullet in `README.md` (Notes), this "Test content pack"
   section, the `--pack` paragraph under "Balance simulator", the pack rows and paragraph under
   "Testing", and the "Test content pack" section of `.superpowers/HANDOFF.md`.
6. Run `bash scripts/check.sh`; it must end "All checks passed.".

`Database.is_test_content`, `BattleLauncher.save_safe_species` and `DataLoader`'s `packs`
parameter can stay: they are harmless without a pack (so can `DebugPassivePage.save_safe_passives`).
`tests/data/test_testpack_removal.gd` checks that `data/` validates alone and that no text file under
`data/`, `game/`, `core/` or `dialogue/` refers to the pack except `data_registry.gd`, `database.gd`,
`battle_launcher.gd` and `debug_passive_page.gd`; it does not scan `tools/`, `scripts/`, `tests/` or
the docs.

## Testing

The engine suites live in `tests/battle/` and run headless with the rest (`bash scripts/check.sh`).
Most use the hand-tuned `FixtureDB` content (`tests/helpers/fixture_db.gd`), adding their own
passives, held items and moves to `FixtureDB.raw()`, so real balance changes don't break them.

| Suite | Covers |
| --- | --- |
| `test_battle_engine.gd` | Turn flow, damage, statuses, swaps, faints, XP and determinism (the same seed gives the same event log) |
| `test_stats_energy_bond.gd` | The Physical/Special split, energy and Rest, Resolve and Endure, and Bond in battle |
| `test_field_reactions.gd` | Field states per side, passives that touch them, and reactions |
| `test_underdog.gd` | Underdog compensation for the outnumbered side: bonus actions, stat bonus, spread reduction, XP |
| `test_two_target_moves.gd` | Moves aimed at two chosen foes (`two_enemies`): picking, replacement and the spread penalty |
| `test_capture_items.gd` | Catching, items, fleeing, and tamer battle setup |
| `test_cure_status.gd` | The `cure_status` op and the `status` trigger: moves, items, passives and held items |
| `test_passives_battle.gd` | Creature passives in battle: always-on effects, `when` conditions and ally auras |
| `test_held_items_battle.gd` | Held items in battle: always-on effects, ally auras and protection banners |
| `test_battle_events.gd` | Every event the engine sends is a known `BattleEvents` type, and the battle screen describes each type or keeps it silent |
| `test_battle_summary.gd` | `BattleSummary` and `ProgressEntry`: the typed results a battle hands to the overworld |
| `test_creature_spec.gd` | `CreatureSpec`: one debug-team slot |
| `test_ai.gd` | AI choices and the effect-op registry (every schema op has a handler) |
| `test_ai_passives.gd` | How the AI weighs passives: absorbs, protections, the user's own modifiers and what a foe's hit triggers do back |
| `test_ai_cure.gd` | How the AI scores moves with a `cure_status` effect |
| `test_formats.gd` | 1v1 to 3v3 with benches of 0, 3 and 9: the opening line-up, refilling slots, no creature on the field twice, every battle finishing; 1 vs a 12-creature party |
| `test_swaps.gd` | A swap is one action at priority 6 and an Underdog creature's whole turn (`test_swap_slots.gd` covers the scene's slot skipping); stages reset on leaving; refused swaps; 12-creature benches; entry triggers fire once per entry |
| `test_targeting_matrix.gd` | Every creature target key against 1–3 standing foes and allies, with the spread multiplier each hit takes |
| `test_one_ally_retarget.gd` | An illegal `one_ally` pick (fainted, missing, a foe) becomes a random standing ally, the user included; a legal pick is kept with no RNG draw |
| `test_multi_format_effects.gd` | In 2v2 and 3v3: auras (passive and held) cover every ally and no foe; a `consumed` item is used up once per holder when two holders fire in one round; a `per_battle` item fires once per battle across swaps; absorb on one target of a spread or `two_enemies` move spares only that target while the other takes the same spread-reduced damage; Underdog's stat bonus, spread reduction and extra actions for 1v2, 1v3 and 2v3, and none at even sizes |
| `test_multi_hit_moves.gd` | Fixed and ranged hit counts, accuracy rolled once, the effect list and hit triggers per hit, Resolve once, Affinity once per move, a faint processed between hits with the spill in slot order (wraparound, fainted slots and the bench skipped, a lone foe, the battle-ending hit, the attacker fainting) |
| `test_ai_multi_hit.gd` | A multi-hit move is estimated and scored at its mean hit count; retaliation counts per expected hit |
| `test_ai_styles.gd` | Styles read from data: the weights scale the terms they name (rest, swap-avoid, heal, damage, ko, setup, retaliation), the reference constants match the data; `passive` (own buffs, buff over attack, heals below half, weakest hit and no chasing a knockout, a hit over a pointless move, no reward for a full-HP heal, Rest at low energy, never swaps, no RNG); `defensive` (heals earlier, takes a swap the tactician declines, damage avoided and retaliation weighed more); `trickster` (status over hit, still takes a knockout, ignores a blocked status) |
| `test_ai_accuracy.gd` | The M6h accuracy pass: retaliation priced through `trigger_value` (a foe's self-heal on hit, contact, a spent per_battle item, `when`); the knockout bonus scaling with `ref` (finishing move, doomed swap, `ko` weight); a bench creature scored in place (absorber, stat boost, an ally's aura, nothing left behind); expected threat (the share by move target, spread in full, one of two foes not doomed, one creature unchanged) |
| `test_ai_swaps.gd` | `swap_score` terms (damage avoided, offence, entry, stages and skip status) and `threat`; the tactician swaps a doomed creature and not a healthy one, a swap is chosen exactly when it clears `SWAP_MARGIN`, `basic` and `aggressive` never swap, two actives claim distinct bench creatures, a swapper takes no further actions, a fresh swap-in does not swap back, no bench, no RNG draw |
| `test_battler_acted.gd` | `Battler.acted`: true at battle start, false after a swap-in or faint replacement, true once the creature acts |
| `test_replace_settling.gd` | What `replace()` settles: a replacement whose entry knocks out the last foes leaves `battle_end` as the last event (Underdog is refreshed first), and a knocked-out foe on an auto-replace side is refilled at once, not a round later |
| `test_ai_triggers.gd` | The AI prices knockout, faint, status, round-end and enter triggers: HP effects equal for both styles, setup effects at half for aggressive, `when`, chance, spent items, own-target effects, once per finished target, no RNG draw, `basic` unchanged, shipped passives |
| `test_simulation_invariants.gd` | Seeded AI battles on the real data (see below) and a stalled battle that ends in a draw at exactly `round_limit` |
| `test_testpack_mechanics.gd` | One pinned behaviour per mechanic family on the test pack: each move op, priority, accuracy, energy, every target kind in 2v3, every trigger kind, held use kinds, the depth guard, all 8 reactions, Underdog tamer content |
| `test_testpack_simulations.gd` | Seeded AI battles over `data/` plus the test pack (see below) |

`test_simulation_invariants.gd` plays formats 1v1, 2v2, 3v3, 1v3 and 2v3 × seeds 1–20 the way the
simulator does (tactician vs aggressive, random species with rolled passives at level 5 on odd seeds
and 40 on even ones, a random held item on about a third of the creatures, benches of 0, 1, 3, 6 and 9).
After every round it checks:

- every battler's HP is within `[0, max_hp]`;
- no event's `bid`, `by`, `target` or `targets` names an unknown bid (`-1` is allowed for "nobody");
- a fainted creature has no action events (`move_used`, `item_used`, `rest`, `pass`, `fled`,
  `swap_out`, `disobeyed`, `lashed_out`, `action_skipped`, `capture_attempt`) and receives no
  `damage`, `heal`, `status_applied` or `stat_stage` after its `faint`, until a `send_out` places it
  again (with HP above 0);
- the battle ends within `round_limit` with exactly one `battle_end`, matching `result()`.

Each run is played twice and the two event logs must be identical (`JSON.stringify`), and every
format must have at least one battle won outright, so the simulation isn't all draws. It takes about
25 seconds.

`test_testpack_simulations.gd` runs the same checks over `data/` plus the test pack: formats 1v1,
2v2, 3v3, 1v3, 2v3 and 3v3 with 6-creature teams × seeds 1–10, level 5 on odd seeds and 60 on even
ones, AI styles rotating through basic, tactician and aggressive. Every creature is a pack species
(every other one dealt in turn, the rest random pack picks, so growing `data/` doesn't shift the
run) and pack moves, passives and held items are dealt out in turn, so the run is fixed for a given
pack. On top of the invariants and the replay check: fewer than 5% of battles may
draw at `round_limit` (0 of 60 do today); every pack creature, passive and held item is fielded;
every pack move appears in a `move_used`; every pack passive or held item with triggers shows a
`passive_triggered` banner. Misses must be listed in the suite's `EXEMPT_MOVES` (2 today: moves the
AI scores below any attack) or `EXEMPT_TRIGGERS` (2 today: a 1% trigger and an Underdog knockout
item), each with a reason and a cap, and the run prints them. It takes about 9 seconds.
