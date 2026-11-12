# Multi-Hit Moves — Design

Date: 2026-11-11
Status: Implemented (plan: [documentation/plans/2026-11-11-m6c-multi-hit-moves.md](../plans/2026-11-11-m6c-multi-hit-moves.md)). One addition made while implementing: a multi-hit move also ends when the user itself faints mid-move (for example to a damaging hit trigger).
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) §2.4 (moves).
Builds on the [battle engine reference](../battle-engine.md) and the [two-opponent moves spec](2026-11-05-two-target-moves-design.md) (§7 left this as its follow-on).
Roadmap: the open M6 item "multi-hit moves" ([roadmap](2026-11-05-roadmap-m5-m8.md)).

## 1. Goal

A move can hit its target more than once in one use. The player still picks one foe. Each hit is a full hit: its own damage,
its own effect rolls and its own hit triggers. A hit that takes the target to 0 HP faints it immediately, and the remaining
hits carry on against the next foe, which is what makes these moves good at clearing a crowded field.

**Success:** a move authored with `hits` hits between its minimum and maximum number of times; moves without `hits` are
unchanged; a faint mid-move is processed at once and the rest of the hits spill to the next foe in slot order; the AI scores
the move by its expected hit count; every rule is covered by tests and described in the docs.

### Decisions

| Topic | Decision |
|---|---|
| Hit count | `hits: {min, max}`, rolled once per use from the battle RNG; `min == max` is a fixed count |
| Accuracy | Rolled once per move, as today, against the chosen target. If it connects, every hit lands, spill hits included |
| Effects | The move's whole effect list runs once per hit (a status chance is rolled per hit; a self effect on the move stacks per hit) |
| Faint mid-move | The target faints as soon as a hit takes it to 0 HP; the remaining hits go to the next standing foe in slot order |
| Targeting | Only `one_enemy` moves may carry `hits`; the player picks one target and the menu is unchanged |
| Spread penalty | None. Spill hits are not a spread, so `spread_count` stays 1 |
| Affinity awards | Earned once per move use, not per hit (see §3) |
| Content | Three example moves (§6) |

## 2. Data

A move gets an optional `hits` object:

```json
"hits": { "min": 2, "max": 5 }
```

Omitting `hits` means one hit, so every existing move is unchanged. Validated: `min` and `max` are integers; `1 <= min <= max
<= balance.max_hits`; `hits` is allowed only when the move's `target` is `one_enemy`, and the validator says so otherwise.
`min` and `max` both 1 is allowed but pointless (a warning is not needed).

`data/balance.json` gains `max_hits` (integer, 2 to 10, shipped value 5). `BalanceDef.max_hits` reads it; test fixtures that
build a balance file are updated. `MoveDef.hits_min` and `MoveDef.hits_max` (both 1 when `hits` is absent) and
`MoveDef.is_multi_hit() -> bool` expose it to the engine, the AI and the text generators.

## 3. Engine

`ActionRunner._move` after the single accuracy roll (the `ctx.targets` it builds today):

1. If the move is multi-hit, roll the count: `rng.randi_range(hits_min, hits_max)`; otherwise the count is 1 and the code
   path is today's.
2. For each hit: run `run_effects(ctx, m.effects)` against the current target, then `check_faints()`. If a side is
   defeated (`check_end`), stop.
3. If the target fainted, the next target is the next standing active foe in slot order, starting at the slot after the fainted
   foe and wrapping around the side. If none stands, stop. The new target replaces `ctx.targets` for the remaining hits and
   takes no new accuracy roll.
4. After the last hit, emit `HIT_COUNT` (see below) and run `finish_consume` once.

`check_faints()` already marks the creature fainted and inactive, fires its `FAINT` event, faint and knockout triggers
(except on the knockout that ends the battle) and awards XP; it does not bring in replacements, which happen between rounds,
so no creature can enter mid-move. A move that ends because the battle ended emits `HIT_COUNT` before the battle-end event.

- **Hit triggers, Resolve, absorbers:** each hit goes through `deal_damage` as now, so passive and held hit triggers, the
  once-per-battle Resolve endure and type absorption apply to every hit with no new code. `ctx.absorbed` is per move use as
  today; a later hit's damage op still reaches the absorber and absorbs again.
- **Affinity awards:** `hit_dealt` and `hit_survived` (`balance.affinity_awards`, 1 point each) are earned once per move
  use: the attacker's `hit_dealt` for the first damaging hit, and each target's `hit_survived` for the first hit it survives.
  Otherwise a 5-hit move would earn five times the Affinity of a single-hit move. The runner marks the later hits so
  `deal_damage` skips the awards.
- **Event:** `BattleEvents.HIT_COUNT` with `{bid, hits}` where `hits` is the number of hits actually landed (a 5-hit roll that
  finished a lone foe on hit 3 reports 3). It is emitted only for multi-hit moves. Existing events (`MOVE_USED`, `DAMAGE`,
  `FAINT`) are unchanged and per hit where they were.
- **`EffectContext`:** gains `hit_index: int` (0-based) so ops and the awards logic know which hit this is.

## 4. AI

`BattleAI.score` multiplies a damaging move's per-hit damage estimate by the mean hit count `(hits_min + hits_max) / 2` for
the chosen target, and counts hit-trigger retaliation (tactician) per expected hit. Spill hits are not modelled, the same as
the AI skips faint and knockout triggers; this is documented under "Passives and the AI" in `documentation/battle-engine.md`.
A single-hit move scores as before.

## 5. UI and text

- **Battle log:** after a multi-hit move, "Hit N times!" when N is 2 or more (`BattleScene` / the log formatter reading
  `HIT_COUNT`).
- **Codex and compendium:** the move's page and the Moves tables show "Hits 3 times" for a fixed count and "Hits 2-5 times"
  for a range; `effect_text` produces the line from the move's `hits`.
- **Target menu:** unchanged. The battle scene needs no new flow.

## 6. Content

Three new `one_enemy` moves, taught additively to three species (no existing move or learnset entry is removed or
retargeted), one for each way to use `hits`. Proposed, for review (final numbers are set in the plan against the comparable
single-target moves):

| Move | Type / category | Hits | Power (per hit) | Cost | Accuracy | Learned by |
|---|---|---|---|---|---|---|
| Twin Splash | water, special | 2 (fixed) | about 30 | 4 | 100 | Tidepup, Lv 15 |
| Needle Flurry | ice, physical | 3 (fixed) | about 22 | 5 | 95 | Frostling |
| Spark Volley | electric, special | 2-5 | about 16, with a small shock chance | 6 | 100 | Voltmoth |

Each is set so its expected total damage is a little above a single-target move of similar cost, to pay for the variance and
the energy. A shipped-content test pins the three moves (hits, target, who learns them).

## 7. Documentation

- `documentation/battle-engine.md`: the `hits` field, the per-hit effect rule, the faint-and-spill rule with a worked
  example, the Affinity rule, `HIT_COUNT`, and the AI's expected-hits scoring.
- The main spec §2.4 gets a one-line pointer. `documentation/compendium.md` is regenerated. The developer guide's roadmap line
  and `.superpowers/HANDOFF.md` are updated.

## 8. Out of scope

- Per-hit accuracy rolls, a hit count that depends on a stat or a passive, moves that spill to allies, multi-hit moves that
  also use `two_enemies` or the other multi-target kinds, and a fresh accuracy roll for the spill target.
- AI modelling of the spill, of faint and knockout triggers, and of the remaining open M6 items (the two pinned engine rulings
  and the passives minors).

## 9. Testing

- **Hit count:** a seeded range stays within `min`..`max` and every value in the range occurs across seeds; a fixed count is
  exact; a move without `hits` hits once and emits no `HIT_COUNT`.
- **Accuracy:** a missed move deals no hits and emits no `HIT_COUNT`; accuracy is rolled once however many hits follow.
- **Per-hit effects:** the damage op runs once per hit; a status chance is rolled per hit; a self buff on the move stacks per
  hit; `finish_consume` runs once.
- **Triggers and awards:** hit triggers fire per hit; Resolve's endure still happens once per battle; an absorber absorbs
  every hit; `hit_dealt` and `hit_survived` are awarded once per move use.
- **Faint and spill:** a hit that takes the target to 0 HP faints it at that moment (its `FAINT` event comes before the next
  `DAMAGE`); the remaining hits go to the next foe in slot order; wraparound (last slot to first); a lone foe ends the move
  early and `HIT_COUNT` reports the hits landed; a faint that ends the battle stops the move; no replacement enters
  mid-move.
- **Validator and data:** `hits` accepted on `one_enemy` only; rejected for every other target, for `min` below 1, `min` above
  `max`, or `max` above `balance.max_hits`; `balance.max_hits` range; the shipped content has no errors or warnings.
- **AI:** it scores a ranged move at the mean hit count, prefers a 3-hit move over a similar single-hit move when it does
  not knock out, and a single-hit move scores as before.
- **Text and UI:** the effect text for fixed and ranged counts; the log line "Hit N times!"; the compendium regenerates
  (battle-scene smoke test).
- **Regression:** existing single-hit, `two_enemies`, `all_enemies`, `all`, side and self moves are unchanged; the three new
  moves validate and appear in the compendium. A tour (`--mode=multihit` or an addition to an existing battle tour) shows a
  multi-hit move with a spill in the real window.
