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
```

- Side 0 is always the player. Battlers are identified by a battle-unique `bid`.
- HP, status, XP, level, moves and Affinity are written straight to each `CreatureInstance`,
  so the party is already up to date when the battle ends.
- `BattleSetup.wild(party, pack, field_count)` and `BattleSetup.vs_tamer(db, party, tamer_id, field_count)`
  let the player field fewer creatures than the format allows, which triggers Underdog.

### Actions

| Action | Constructor | Notes |
|---|---|---|
| Move | `BattleAction.use_move(bid, move_id, target_bid)` | Target is only needed for `one_enemy` / `one_ally` moves. An invalid target is replaced with a random valid one. |
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
4. At end of round: status effects run (e.g. Burn damage) and count down, field states count down,
   AI and wild sides refill empty slots, the player gets `replacement_needed`, and Underdog is
   recalculated.
5. After `round_limit` rounds the battle ends in a draw (`reason: "round_limit"`).

## Formulas

| What | Formula |
|---|---|
| HP | `2·base·Lv/100 + Lv + 10` |
| Atk / Def / Spd | `2·base·Lv/100 + 5` |
| XP to reach a level | `Lv³` |
| Stat stages (−6…+6) | Atk/Def/Spd: `(2+s)/2` or `2/(2−s)`. Accuracy: `(3+s)/3` or `3/(3−s)` |
| Max energy | `2·base_stamina·Lv/100 + energy.base` (+1 per Stamina training point) |
| Training | Each point adds +1 to a stat, +`hp_per_point` to HP |
| Effective stat | raw (incl. training) × stage × passive `stat_mod`s (status + own side's field states) × (1 + Underdog stat bonus, P/S Atk and Def only) |
| Damage | `((2·Lv/5 + 2) · power · A/D) / 50 + 2` × same-type bonus × type matchup × field bonus × target side's `incoming_type_mod`s × spread × Bond performance × roll(0.85–1.0), minimum 1. `A/D` is P.Atk/P.Def for physical moves and S.Atk/S.Def for special moves |
| Spread | Moves hitting more than one creature: × `spread_mult` × (1 − target side's Underdog spread reduction) |
| Reaction damage | Uses the triggering creature's level with Atk/Def = 1, no same-type bonus. `scale_with_stacks` multiplies power by stacks consumed |
| Hit chance | `accuracy × accuracy multiplier` (includes Bond performance). Moves on yourself or allies, and `always_hits` moves, never miss |
| Resolve resistance | `resist_cap × R / (R + R_avg)`; `R_avg` = Resolve of a base-50 creature at the attacker's level. Applies to statuses and to stat drops from foes |
| Endure | Same formula with `endure_cap`; once per battle, a knockout blow from a foe leaves 1 HP |
| Catch chance | `catch_rate × item mult × (1 − HP% × hp_weight) × status bonus × field bonuses on the target's side`, clamped 0–1 |
| XP per defeated foe | `yield × level / divisor` (× `tamer_mult` vs tamers) × (1 + Underdog XP bonus). Every conscious creature that has been on the field gets the full amount |

## Energy

- Every move has a `cost`, paid when the move is used. A move costing more than the creature's
  current energy is rejected (`action_invalid`, reason `no_energy`). `engine.usable_moves(bid)` lists
  what the creature can afford right now.
- Energy lives on the `CreatureInstance` and carries between battles. It only refills in battle
  through Rest or items with `restore_energy`.
- The fallback move (`energy.fallback_move`, Scrap) costs nothing and is always usable, even
  though it is not in any learnset.
- `BattleSetup.award_xp = false` turns off XP (the simulator does this, since only side 0 earns XP).

## Bond

Bond (−100…+100) is stored on the `CreatureInstance`. Changes come from `balance.bond.changes`:

| Happening | When |
|---|---|
| `battle_won` | Every creature on the winning side that took part |
| `knockout` | The creature that landed the blow |
| `fainted` | The creature that fainted |
| `healed_item` | A creature healed by an item |
| `overworked` | Sent out or ordered to act below `overwork_hp` HP or `overwork_energy` energy (once per battle) |
| `rested` | `Progression.rest()` at a rest point (overworld) |

Negative Bond, scaling linearly to `bond.min`: a `disobey_max_chance` chance to use a random
other usable move or loaf around (`disobeyed`), a `penalty_max` cut to accuracy and damage, and
at `lash_out_threshold` or below a `lash_out_chance` chance to Scrap itself or an ally instead
(`lashed_out`). Positive Bond multiplies XP by up to `1 + xp_bonus_max`.

## Field states and reactions

- Each side holds up to `max_field_states` states. A new state pushes out the oldest one.
- Re-applying a state the side already has adds stacks (up to its `max_stacks`) and refreshes its duration.
- Applying a state that reacts with one already there fires the reaction instead:
  - States listed in `consumes` are removed. Their stacks (plus the incoming stacks, if the incoming state is consumed) become `stacks_consumed`.
  - The incoming state still lands unless the reaction consumes it.
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
|---|---|
| Extra actions per creature each round | `floor((r − 1) × bonus_actions_per_ratio)` (at 0.5: 1v2 +0, 1v3 +1, 2v3 +0) |
| Physical/Special Atk and Def | `+stat_bonus_per_ratio × (r − 1)`, capped |
| Damage taken from spread moves | `−spread_reduction_per_ratio × (r − 1)`, capped |
| XP | `+xp_bonus_per_ratio × (r − 1)` |

It is recalculated at battle start, after replacements, and at the end of every round.

## Affinity

Battle happenings add points to Affinity tracks on the creature responsible. The point values
come from `balance.affinity_awards`:

| Happening | Credited to |
|---|---|
| `hit_dealt`, `knockout` | The attacker |
| `hit_survived` | The creature that took the hit and stayed up |
| `heal` | The healer |
| `field_applied`, `reaction_triggered`, `field_cashed_in` | The creature whose move did it |
| `status_inflicted`, `stat_lowered` | The creature that inflicted it on a foe |

`Progression.growth_target(db, creature)` picks the growth branch. It uses the lowest growth level
the creature has reached, then the branch matching its dominant Affinity if that track has at least
`growth_affinity_threshold` points, and otherwise the default branch.
`Progression.apply_growth` changes the species. Showing and confirming growth is M4 UI work.

## AI styles

| Style | Behavior |
|---|---|
| `basic` | Random move and target. |
| `aggressive` | Highest expected damage, with a bonus for knockouts. Heals when below half HP. |
| `tactician` | Aggressive scoring plus value for setting up reactions on the enemy side, new states its team can follow up on, statuses and debuffs. Setup values are multiples of its best available damage, so they scale with level. It avoids triggering reactions on its own side. |

Every AI picks only moves it can afford, falls back on Scrap, and considers Rest below 20% energy.

## Events

| Event | Key fields |
|---|---|
| `battle_start` | `wild`, `tamer`, `slots` |
| `send_out` | `side`, `slot`, `bid`, `species`, `level`, `hp`, `max_hp`, `energy`, `max_energy` |
| `round_start` | `round` |
| `move_used` | `bid`, `move`, `targets`, `side` |
| `item_used` | `bid`, `item`, `targets`, `left` |
| `swap_out` | `bid`, `side`, `slot` (followed by `send_out`) |
| `miss`, `no_effect`, `no_target` | `bid`, `target` |
| `damage` | `bid`, `amount`, `hp`, `max_hp`, `by`, `damage_type`, `effectiveness` |
| `endured` | `bid` (survived at 1 HP through Resolve) |
| `resisted` | `bid`, `status` or `stat` |
| `energy` | `bid`, `change`, `energy`, `max_energy` |
| `rest` | `bid` |
| `bond` | `bid`, `change`, `bond`, `reason` |
| `disobeyed` | `bid`, `ordered`, `did` (`""` = loafed around) |
| `lashed_out` | `bid`, `target` |
| `heal` | `bid`, `amount`, `hp`, `max_hp` |
| `status_applied`, `status_failed`, `status_ended` | `bid`, `status` (`has` on failure) |
| `action_skipped` | `bid`, `status` |
| `stat_stage` | `bid`, `stat`, `change`, `stage` |
| `field_applied` | `side`, `state`, `stacks`, `turns`, `by` |
| `field_removed` | `side`, `state`, `reason`: `expired` \| `pushed_out` \| `reacted` \| `cashed_in` \| `cleared` |
| `reaction` | `reaction`, `side`, `inputs`, `stacks`, `by` |
| `capture_attempt` | `bid`, `target`, `item`, `chance`, `success` |
| `captured` | `bid`, `species` |
| `faint` | `bid`, `side` |
| `xp_gain`, `level_up`, `move_learned`, `move_offered` | `bid`, `amount` / `level` / `move` |
| `underdog` | `side`, `ratio`, `bonus_actions`, `stat_bonus`, `spread_reduction`, `xp_bonus` |
| `replacement_needed` | `side`, `count` |
| `pass`, `fled` | `bid` |
| `action_invalid` | `bid`, `reason` |
| `battle_end` | `winner` (−1 = none), `reason`: `defeat` \| `fled` \| `round_limit`, `captured`, `rounds` |

## Adding a new effect op

1. Add its fields to `DataSchemas.EFFECT_OPS` in `core/data/schemas.gd`.
2. Write `core/battle/effects/op_<name>.gd`, extending `EffectOp`. Override `per_target()` to return
   false for side-level effects.
3. Register it in `EffectOps.get_op()`. A test fails if the schema lists an op that has no handler.
4. Describe it in `_effect()` in `tools/generate_compendium.gd`.

## Balance simulator

```bash
godot --headless --path . --script res://tools/simulate.gd -- --battles=500 --format=2v2 --level=10 --ai=tactician,aggressive
```

It prints win rates per side, draws, average rounds, how often each reaction fires, and each
species' win rate.
