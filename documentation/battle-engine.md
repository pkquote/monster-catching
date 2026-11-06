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

### Actions

| Action | Constructor | Notes |
| --- | --- | --- |
| Move | `BattleAction.use_move(bid, move_id, target_bid, second_target_bid)` | Target is only needed for `one_enemy` / `one_ally` / `two_enemies` moves; `second_target_bid` is only read for `two_enemies`. An invalid target is replaced with a random valid one. |
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
| --- | --- |
| Extra actions per creature each round | `floor((r − 1) × bonus_actions_per_ratio)` (at 0.5: 1v2 +0, 1v3 +1, 2v3 +0) |
| Physical/Special Atk and Def | `+stat_bonus_per_ratio × (r − 1)`, capped |
| Damage taken from spread moves | `−spread_reduction_per_ratio × (r − 1)`, capped |
| XP | `+xp_bonus_per_ratio × (r − 1)` |

It is recalculated at battle start, after replacements, and at the end of every round.

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

Rules:

- Only creatures on the field and standing contribute, receive or fire anything (a `faint`
  trigger fires as its creature goes down). Nothing fires once the battle is decided, including
  the faint that decides it.
- Multipliers from different sources multiply. An aura counts once per passive id, however many
  allies hold it.
- Effects run by a trigger never set off further passive triggers (a depth guard in
  `PassiveRules`), and a creature a trigger's effects knock out fires no `faint` or `knockout`
  triggers.
- `chance` (1–100) rolls the battle RNG only when it is below 100.
- A trigger whose effects would all do nothing (only `heal` on creatures at full HP and
  `restore_energy` on creatures at full energy) is skipped: no banner, no events. Any other op
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

### Held items and the AI

The tactician's hit-retaliation estimate includes the target's held-item `hit` triggers (including `when` and
chance), and absorb, block and own-effect estimates read the held item through the same effect list as passives.

## AI styles

| Style | Behavior |
| --- | --- |
| `basic` | Random move and target. |
| `aggressive` | Highest expected damage, with a bonus for knockouts. Heals when below half HP. |
| `tactician` | Aggressive scoring plus value for setting up reactions on the enemy side, new states its team can follow up on, statuses and debuffs. Setup values are multiples of its best available damage, so they scale with level. It avoids triggering reactions on its own side. |

For a `two_enemies` move the AI builds one option per unordered pair of standing foes and scores the pair as a whole: the damage estimate uses the real spread count (2), the pair's knockouts and setup values add up, and the best pair wins. `basic` picks a random pair.

Every AI picks only moves it can afford, falls back on Scrap, and considers Rest below 20% energy.

### Passives and the AI

Damage estimates already include stat, type-power, resistance, Scrap and reaction passives. On top of that:

- **Absorb (aggressive and tactician):** damage a target's `absorb_type` passive would absorb counts as 0, and the heal it gives (capped at the target's missing HP) is subtracted for a foe or added for an ally. The AI stops hitting absorbers and may hit its own.
- **Blocks (tactician):** `status_immune`, `guard_stages` and `field_shelter` zero the value of the statuses, stat drops and reaction damage they block, in moves and in reactions.
- **Own passives (tactician):** `field_boost` stacks count toward a setup's reaction value, and `rest_bonus` scales Rest's value.
- **Retaliation (tactician):** a hit that doesn't knock the target out is charged the expected cost of the target's `hit` triggers on the attacker (status, stat drop or damage, weighted by chance; `contact` triggers need a physical move), less whatever the attacker's own passive blocks.

Not modelled: faint, knockout, enter and round-end triggers.

## Code layout

`BattleEngine` is the public face: the battle screen, the AI and effect ops call only it. It owns the
battle state, targeting, the mutations effect ops use (`deal_damage`, `heal`, `inflict_status`...)
and the round loop, and hands the rest to three parts (each extends `BattlePart`, which holds the
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
| `passive_triggered` | `bid`, `passive` (a trigger fired, or a passive blocked a status, a foe's stat drop or reaction damage, or absorbed a hit; see Passives) |
| `passive_unlocked` | `bid`, `passive` (an Affinity track first reached the threshold and unlocked the Affinity passive) |
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
| `test_formats.gd` | 1v1 to 3v3 with benches of 0, 3 and 9: the opening line-up, refilling slots, no creature on the field twice, every battle finishing; 1 vs a 12-creature party |
| `test_swaps.gd` | A swap is one action at priority 6; stages reset on leaving; refused swaps; 12-creature benches; entry triggers fire once per entry |
| `test_targeting_matrix.gd` | Every creature target key against 1–3 standing foes and allies, with the spread multiplier each hit takes |
| `test_multi_format_effects.gd` | In 2v2 and 3v3: auras (passive and held) cover every ally and no foe; a `consumed` item is used up once per holder when two holders fire in one round; a `per_battle` item fires once per battle across swaps; absorb on one target of a spread or `two_enemies` move spares only that target while the other takes the same spread-reduced damage; Underdog's stat bonus, spread reduction and extra actions for 1v2, 1v3 and 2v3, and none at even sizes |
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
