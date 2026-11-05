# Two-Opponent Moves — Design

Date: 2026-11-05
Status: Implemented (plan: [documentation/plans/2026-11-05-two-target-moves.md](../plans/2026-11-05-two-target-moves.md))
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) §2.1 (formats, Underdog), §2.4 (moves).
Builds on the [battle engine reference](../battle-engine.md) and the [battle scene design](2026-11-03-m2-battle-scene-design.md).
Follow-on (separate spec and plan): multi-hit moves that hit one opponent more than once. See §7.

## 1. Goal

A move's own `target` decides how many creatures it hits. Today a move can hit one foe (`one_enemy`), every active foe
(`all_enemies`), or everyone else on the field (`all`). Add a move that hits **exactly two** opponents, chosen by the player,
and make the damage penalty depend on how many creatures a move hits.

**Success:** a move authored as `two_enemies` lets the player pick two foes (or hits whoever is there when two or fewer are
active); a move like Punch stays `one_enemy` and is unaffected; the spread penalty is 1.0 for one creature, a milder value for
two and the existing value for three or more, tunable in `balance.json`; the AI scores and picks pairs; every rule is covered
by tests and described in the docs.

### Decisions

| Topic | Decision |
|---|---|
| Scope of multi-target | Per move: only moves whose `target` is `two_enemies` (or `all_enemies` / `all`) hit more than one creature; no global rule |
| Two-opponent targeting | The player picks any two foes (two-step menu); no adjacency or randomness |
| Target names | Keep `one_enemy`, `all_enemies`, `all`; add `two_enemies`. No renames, no migration of shipped moves |
| Spread penalty | A table keyed by how many creatures the move actually hits; Underdog's spread reduction still stacks |
| Entire field | `all` unchanged: everyone on the field except the user, partners included |
| Multi-hit (one foe, several hits) | Out of scope here; separate follow-on spec |

## 2. Data

### 2.1 Targets

`DataSchemas` gains a move-only target list: `MOVE_TARGETS = TARGETS + ["two_enemies"]`. Moves use `MOVE_TARGETS`; items,
effect `target` overrides and passive trigger targets keep `TARGETS`, so `two_enemies` is invalid there and the validator
says so.

### 2.2 Spread table

`data/balance.json` replaces `spread_mult` with:

```json
"spread_mults": { "2": 0.85, "3": 0.75 }
```

Rules (validated): keys `"2"` and `"3"` are required; values are numbers from 0 to 1; the `"3"` value is not greater than the
`"2"` value. A move hitting more than three creatures uses the `"3"` value. `BalanceDef.spread_mult_for(count: int) -> float`
returns 1.0 for a count of 1 or less, the `"2"` value for 2, and the `"3"` value for 3 or more. `BalanceDef.spread_mult`
is removed; test fixtures and docs that mention it are updated.

## 3. Engine

- **`BattleAction`:** new `second_target: int = -1`; `use_move(actor, move, target := -1, second_target := -1)`. Existing
  calls are unchanged.
- **`resolve_targets(user, key, chosen, second := -1, allow_random := true)`** gains the second choice. For `two_enemies` it
  hits the chosen first and second foes when both are active, standing and different. A missing, invalid or duplicate pick
  is replaced by a random remaining foe (like `one_enemy` today; not when `allow_random` is false, as in AI scoring).
  With fewer than two active foes it hits those that exist.
- **`targets_for(bid, move)`** lists first-pick foes for `two_enemies`; new `second_targets_for(bid, move, first) -> Array[int]`
  lists the other standing foes for the second step.
- **Spread:** `EffectContext.spread` (bool) becomes `spread_count: int` (the number of creatures the move hits). The damage
  multiplier is `balance.spread_mult_for(spread_count)` (multiplied by `1 − Underdog spread reduction` for any count above 1, as now).
  The action runner sets it from the resolved targets (`targets.size()`); so does the AI's damage estimate. A `two_enemies`
  move against one foe takes no penalty; an `all_enemies` move against two foes takes the two-target value; `all` in a 3v3
  (five creatures) takes the three-target value.
- **Behaviour change to expect:** an existing `all_enemies` or `all` move that hits exactly two creatures now takes ×0.85 instead
  of ×0.75. Three or more is unchanged.
- **Events:** `move_used.targets` already lists every creature hit; no new event.

## 4. Battle UI

`BattleScene._choose_target` handles `two_enemies` in two steps and returns the pair. With two or fewer active foes there is
no menu. With three, step one is "Use X on…?" over the foes; step two is "Use X on <first> and…?" over the other standing foes,
and Back returns to step one. The action is built as `use_move(bid, move, first, second)`. Hint highlighting follows the
existing `hint` option.

## 5. AI

For a `two_enemies` move, `BattleAI.choose` enumerates every pair of standing foes (at most three), scores each pair with
the existing per-target scoring and the two-target spread value, and picks the best, so knockouts, absorbers and protections
are weighed per pair. `score` takes the second target. The `basic` style picks a random pair. Nothing else about scoring
changes.

## 6. Content, display and docs

- **Moves:** three new `two_enemies` moves, taught additively to three species (no existing move or learnset entry is
  removed or retargeted). Proposed, for review: **Crossfire** (fire, special; Emberkit, Lv 9), **Twin Lash** (grass,
  physical; Sprigling, Lv 10) and **Arc Pair** (electric, special; Voltmoth, Lv 9), each with power around 40–45, cost 4–5,
  accuracy 100, so that hitting two foes at ×0.85 each beats a single-target move of similar cost only when both targets are
  worth hitting. Final numbers are set in the plan against the comparable single-target moves.
- **Compendium:** target label "Two foes" for `two_enemies`; the Moves tables show it.
- **Docs:** `documentation/battle-engine.md` (targeting table, spread formula, `second_target`, the two-step selection) and the
  main spec §2.4.

## 7. Out of scope

- **Multi-hit moves** (one use hitting the same foe two or more times, such as a Double Kick): a separate mechanic with its
  own rules for accuracy, per-hit rolls, on-hit triggers and held items firing per hit. Brainstormed and specified separately.
- Adjacency or positional targeting, targeting two allies, retargeting existing moves, and items that hit two creatures.

## 8. Testing

- **Engine:** the chosen pair is hit; a missing, invalid or duplicate second pick is replaced at random (and not when
  `allow_random` is false); with one or two foes active the move hits those present, with no penalty for one;
  `second_targets_for` excludes the first pick and fainted foes; `use_move` without a second target behaves as before.
- **Spread:** the multiplier at 1, 2, 3 and 5 creatures hit; Underdog's reduction stacks for any count above 1; an
  `all_enemies` move against two foes takes the two-target value.
- **Validator and data:** `two_enemies` is accepted on moves only (items, effect targets and trigger targets reject it);
  `spread_mults` rules (missing key, value out of range, "3" above "2"); the shipped content has no errors or warnings.
- **AI:** it picks the best pair, prefers a pair containing a knockout, avoids a pair containing an absorber, and a
  `basic` AI picks a legal pair.
- **UI:** the two-step menu appears with three foes, is skipped with two or fewer, Back from step two returns to step one,
  and the resulting action carries both targets (battle-scene smoke tests).
- **Regression:** existing single-target, `all_enemies` (three foes), `all`, side and self moves are unchanged; the three
  new moves validate and appear in the compendium.
