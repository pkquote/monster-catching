# Two-Opponent Moves Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a move target `two_enemies` (the player picks any two foes) and make the multi-target damage penalty depend on how many creatures a move actually hits.

**Architecture:** `balance.json`'s single `spread_mult` becomes a `spread_mults` table read through `BalanceDef.spread_mult_for(count)`; `EffectContext.spread` (bool) becomes `spread_count` (int). `BattleAction` gains `second_target`, `BattleEngine.resolve_targets` gains the second choice, the AI scores foe pairs, and the battle scene gets a two-step target menu.

**Tech Stack:** Godot 4.7 GDScript, gdUnit4, JSON content. Run everything with `bash scripts/check.sh` (must end "All checks passed."). Never run two Godot processes at once.

**Spec:** [documentation/specs/2026-11-05-two-target-moves-design.md](../specs/2026-11-05-two-target-moves-design.md)

## Global Constraints

- **Never commit, stage or stash.** Leave changes in the working tree; the final message offers a commit message in the project's format.
- New move target key: `two_enemies`, valid on moves only (a `MOVE_TARGETS = TARGETS + ["two_enemies"]` list in `DataSchemas`; items, effect `target` overrides and passive trigger targets keep `TARGETS`). Keep `one_enemy`, `all_enemies`, `all` unchanged; do not rename or retarget any existing move.
- `balance.json`: `spread_mult` is replaced by `"spread_mults": {"2": 0.85, "3": 0.75}`. Validated: keys `"2"` and `"3"` required, values numbers 0..1, the `"3"` value not greater than the `"2"` value. `BalanceDef.spread_mult_for(count: int) -> float` returns 1.0 for count ≤ 1, the `"2"` value for 2, the `"3"` value for 3 or more. `BalanceDef.spread_mult` is removed.
- Spread count = the number of creatures the move's resolved targets contain (as today, before accuracy misses). Underdog's spread reduction still multiplies in for any count above 1: `mult *= spread_mult_for(count) * (1 - reduction)`.
- `two_enemies` hits exactly two distinct standing, active foes; a missing, invalid or duplicate pick is replaced by a random remaining foe (not when `allow_random` is false); with fewer than two active foes it hits those that exist; none gives `NO_TARGET`.
- `BattleAction.use_move(actor, move, target := -1, second_target := -1)`; existing callers are unchanged.
- Behaviour change (intended): an existing `all_enemies` or `all` move hitting exactly two creatures takes ×0.85 instead of ×0.75; three or more is unchanged.
- Multi-hit moves (one foe, several hits) are NOT part of this plan.
- New tests extend `GdUnitTestSuite` and follow the surrounding suites' helpers (`FixtureDB`, `ScreenFit`).

## Review Focus

1. A `two_enemies` move must never hit the same foe twice when two or more foes are standing: a duplicate, missing or invalid second pick is replaced by a different foe. Pinned in Task 2.
2. A foe that has fainted between selection and execution (an earlier action in the round knocked it out) must be replaced, not skipped or crash; with one foe left the move hits it once with no penalty; with none it emits `NO_TARGET`. Pinned in Task 2.
3. Every existing test and doc that assumed ×0.75 for a two-creature hit must be updated deliberately, and `all_enemies` against three foes must stay exactly as before. Pinned in Task 1.
4. In the two-step target menu, Back from step two must return to step one, cancelling step one must cancel the move choice, and two or fewer foes must skip the menu entirely. Pinned in Task 4.
5. The AI must not pick a pair containing an absorber over an equal pair without one, and `basic` must always produce two distinct legal targets. Pinned in Task 3.

---

### Task 1: Spread table and spread count

**Files:**
- Modify: `data/balance.json`, `tests/helpers/fixture_db.gd` (`FixtureDB.balance()`), `core/data/schemas.gd` (balance entry), `core/data/defs/balance_def.gd`, `core/battle/effects/effect_context.gd`, `core/battle/battle_math.gd`, `core/battle/action_runner.gd`, `core/battle/ai/battle_ai.gd` (`estimate_damage` and its callers), `tools/generate_compendium.gd` (the "Multi-target damage" line)
- Test: `tests/battle/test_underdog.gd`, `tests/battle/test_battle_engine.gd` (or the suite that covers multi-target damage), `tests/data/test_validator.gd`, plus every existing test that calls `BattleAI.estimate_damage(..., spread)` or builds balance with `spread_mult`

**Interfaces:**
- Produces: `BalanceDef.spread_mults: Dictionary` and `BalanceDef.spread_mult_for(count: int) -> float`; `EffectContext.spread_count: int` (default 1); `BattleAI.estimate_damage(engine, b, m, t, spread_count: int)` (replacing the `spread: bool` parameter; callers pass the number of creatures the move hits).

- [ ] **Step 1: Write failing tests.**
  - `test_spread_mult_for_counts`: with the real fixture table, `spread_mult_for(0)` and `(1)` are 1.0, `(2)` is 0.85, `(3)`, `(4)` and `(5)` are 0.75.
  - `test_damage_uses_the_count_table`: a damage computation with `spread_count` 1, 2 and 3 scales by 1.0, 0.85 and 0.75 (compare to the count-1 amount using `roll == false`).
  - `test_all_enemies_against_two_foes_takes_the_two_target_value` and `test_all_enemies_against_three_foes_is_unchanged` (an `all_enemies` move: 0.85 vs 0.75).
  - `test_all_in_a_3v3_takes_the_three_target_value` (five creatures hit).
  - `test_underdog_spread_reduction_stacks_for_two_and_three` (an Underdog side takes less than a non-Underdog one at both counts; extend `test_underdog_takes_less_spread_damage`).
  - In `tests/data/test_validator.gd`: `test_spread_mults_rules` — missing `"2"`, missing `"3"`, a value above 1, and a `"3"` value greater than the `"2"` value each fail; the shipped table passes.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** `balance.json` and `FixtureDB.balance()`: `"spread_mults": {"2": 0.85, "3": 0.75}` replacing `spread_mult`. `schemas.gd`: `spread_mults` as a `dict` with fields `"2"` and `"3"` (numbers 0..1); the "3 not above 2" rule goes in `validator.gd`'s cross rules (error on the balance single). `BalanceDef`: `spread_mults` (floats) and `spread_mult_for`; remove `spread_mult`. `EffectContext`: `var spread_count := 1` replacing `spread`. `BattleMath.damage`: `if ctx.spread_count > 1:` multiply by `spread_mult_for(ctx.spread_count) * (1.0 - reduction)`. `ActionRunner`: `ctx.spread_count = targets.size()`. `BattleAI.estimate_damage` and `best_damage`/`score` pass the count of creatures the move hits (`best_damage` uses the foe count for `all_enemies`/`all`, as its current bool does; `score` uses `targets.size()`). Compendium line becomes a two-value line ("Multi-target damage | x0.85 (two) / x0.75 (three or more)"), reading the table. Update every existing caller and test that used `spread` or `spread_mult` (grep `spread` across `core/`, `game/`, `tools/`, `tests/`, and the doc lines in `documentation/battle-engine.md`'s Spread row).
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 2: `two_enemies` target and engine resolution

**Files:**
- Modify: `core/data/schemas.gd` (`MOVE_TARGETS`, moves entry), `core/battle/battle_action.gd`, `core/battle/battle_engine.gd` (`resolve_targets`, `targets_for`, new `second_targets_for`), `core/battle/action_runner.gd` (pass `a.second_target`, add `two_enemies` to `CREATURE_TARGETS`), `tools/generate_compendium.gd` (`TARGET_LABELS`)
- Test: `tests/battle/test_battle_engine.gd` (or a new `tests/battle/test_two_target_moves.gd`), `tests/data/test_validator.gd`

**Interfaces:**
- Consumes: `EffectContext.spread_count` set from `targets.size()` (Task 1).
- Produces: `BattleAction.second_target: int`; `BattleAction.use_move(actor_bid, move_id, target_bid := -1, second_target_bid := -1)`; `BattleEngine.resolve_targets(user, key, chosen, second := -1, allow_random := true) -> Array[Battler]` (new parameter placed before `allow_random`; update every caller); `BattleEngine.second_targets_for(bid: int, move_id: String, first: int) -> Array[int]` (the other standing active foes, empty for a move that is not `two_enemies`); `targets_for` lists first-pick foes for `two_enemies`.

- [ ] **Step 1: Write failing tests** (fixture move `twin_strike` with `target: two_enemies` and a `damage` effect, plus a 1v3 and a 3v3 setup):
  - `test_two_enemies_hits_the_chosen_pair`: the `MOVE_USED` event lists exactly the two chosen foes, the third is untouched, and each took damage once.
  - `test_duplicate_second_pick_is_replaced` (Review Focus 1): `second == first` still hits two distinct foes; the same for a missing (`-1`) and an invalid (an ally, an unknown bid, a benched foe) second pick.
  - `test_first_pick_gone_at_execution_is_replaced` (Review Focus 2): an earlier action in the same round faints the chosen first foe; the move still hits two distinct standing foes.
  - `test_fewer_than_two_foes_hits_those_present`: with two foes both are hit; with one foe it is hit once with no spread penalty (damage equals the single-target amount for the same power); with none, `NO_TARGET`.
  - `test_resolve_targets_does_not_randomise_when_disallowed`: with `allow_random == false`, a duplicate or invalid second pick yields only the valid one (as the AI scoring path needs).
  - `test_second_targets_for_excludes_first_and_fainted_foes` and `test_targets_for_lists_first_pick_foes`; `test_second_targets_for_is_empty_for_other_targets`.
  - `test_use_move_without_second_target_behaves_as_before` (a `one_enemy` move with the old three-argument call).
  - `test_spread_penalty_applies_to_a_two_target_move` (each target takes ×0.85 vs the same move against one foe).
  - In `tests/data/test_validator.gd`: `test_two_enemies_valid_on_moves_only` — a move with `two_enemies` passes; an item with `target: two_enemies`, an effect with `"target": "two_enemies"`, and a passive trigger effect with that target each fail.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement** the signatures above. `resolve_targets` for `two_enemies`: take `chosen` and `second` if each is an active, alive foe and they differ; fill any gap from the remaining standing active foes at random (using `rng` only when `allow_random`); cap at two; fewer foes means fewer targets. `ActionRunner` passes `a.second_target` to `resolve_targets` for moves and `-1` for items. `schemas.gd`: moves' `target` uses `MOVE_TARGETS`; `TARGETS` stays for items, effect targets and trigger targets. `TARGET_LABELS["two_enemies"] = "Two foes"`.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 3: AI scores and picks pairs

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`choose`, `score`)
- Test: `tests/battle/test_ai.gd`, `tests/battle/test_ai_passives.gd`

**Interfaces:**
- Consumes: `BattleAction.use_move(..., second_target)`, `BattleEngine.second_targets_for`, `resolve_targets(..., second, allow_random)` (Task 2).
- Produces: `BattleAI.score(engine, b, m, target_bid, style, ref := -1.0, second_bid := -1) -> float` (the new trailing parameter is passed through to `resolve_targets`).

- [ ] **Step 1: Write failing tests** (fixture `twin_strike` as in Task 2):
  - `test_ai_picks_the_best_pair`: three foes with different HP and weaknesses; an aggressive AI choosing a `two_enemies` move picks the pair with the highest summed score (assert both targets).
  - `test_ai_prefers_a_pair_with_a_knockout`: one foe at 1 HP is always in the chosen pair.
  - `test_ai_avoids_a_pair_with_an_absorber` (Review Focus 5): a pair containing a creature with an `absorb_type` passive for the move's type loses to an equal pair without one.
  - `test_basic_ai_picks_two_distinct_legal_targets` (Review Focus 5): across several seeds the action's two targets are distinct standing foes.
  - `test_two_foe_case_needs_no_choice`: with two foes the AI action covers both (second target present or both resolved) and with one foe it hits that foe.
  - `test_score_of_a_pair_includes_the_spread_value`: `score` for a pair equals the sum of its per-target scores computed at count 2 (compare against the single-target score times the two-target multiplier within a tolerance).
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** In `choose`, for a `two_enemies` move expand each first-pick foe `t1` and each `t2` in `second_targets_for(bid, mid, t1)` with `t2` later than `t1` in the foe order (so each unordered pair is scored once; with exactly two foes there is one pair; with one foe, one option), creating options `use_move(bid, mid, t1, t2)` scored with `score(..., t1, style, ref, t2)`; `basic` scores 0 and picks randomly among the same options. `score` passes `second_bid` to `resolve_targets(b, m.target, target_bid, second_bid, false)`. Other target kinds are untouched.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 4: Two-step target menu

**Files:**
- Modify: `game/battle/battle_scene.gd` (`_choose_target`, the move branch that builds the action)
- Test: `tests/game/test_battle_scene_smoke.gd`

**Interfaces:**
- Consumes: `BattleEngine.second_targets_for`, `BattleAction.use_move(..., second)` (Task 2).
- Produces: `BattleScene._choose_target(...)` returning, for `two_enemies`, an `Array` `[first, second]` (a single `-1`/bid for other target kinds, `null` when cancelled); the move branch builds the action with both targets.

- [ ] **Step 1: Write failing tests** (smoke tests with a `two_enemies` fixture or shipped move on the real db; follow the existing menu-driving tests, using `menu.pick_label`):
  - `test_two_step_menu_with_three_foes`: the first menu lists the three foes; after picking one, the second menu lists the other two and its title names the first; picking one yields an action with `target` and `second_target` set to the two picks.
  - `test_two_or_fewer_foes_skip_the_target_menu`: with two foes the action is built with no target menu and covers both; with one foe, that foe.
  - `test_back_from_the_second_step_returns_to_the_first` (Review Focus 4): choosing Back at step two shows the three-foe menu again; picking a different first foe then works.
  - `test_cancelling_the_first_step_cancels_the_move_choice`: Back at step one returns to the move list.
  - `test_other_target_kinds_are_unchanged`: a `one_enemy` move still shows one menu and sets only `target`.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** `_choose_target` for `two_enemies`: foes = standing active foes; if `foes.size() <= 2` return their bids as the pair without a menu; otherwise run the first menu (title "Use X on...?"), then the second over `engine.second_targets_for(...)` with the title naming the first pick; Back at step two loops to step one; Back at step one returns `null`. The move branch unpacks the pair into `use_move(bid, mid, first, second)`. Keep the existing `hint` option so the focused foe is highlighted. Explicit types on locals (a Variant return needs explicit casting).
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 5: Content, docs and real-window check

**Files:**
- Modify: `data/moves/*.json` (a new moves file or the appropriate type file), `data/creatures/*.json` (additive learnset entries only), `documentation/battle-engine.md`, `documentation/specs/2026-11-03-monster-rpg-design.md` (§2.4), `documentation/specs/2026-11-05-two-target-moves-design.md` (Status), `.superpowers/HANDOFF.md`; the battle tour in `.claude/skills/run-godot-monster-catching-game/` only if a small step fits
- Test: `tests/data/` (a shipped-content test), the compendium run

- [ ] **Step 1: Write a failing shipped-content test**: `test_shipped_two_target_moves`: loading `res://data` yields no errors or warnings and at least three `two_enemies` moves, each learned by at least one species, with power 38–48, cost 4–5, accuracy 100.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect that test to fail.
- [ ] **Step 3: Content.** Three moves, taught additively: **Crossfire** (fire, special; Emberkit Lv 9), **Twin Lash** (grass, physical; Sprigling Lv 10), **Arc Pair** (electric, special; Voltmoth Lv 9), each `target: two_enemies`, accuracy 100, power in 38–48 and cost 4–5 chosen against comparable single-target moves (`ember_flick` 40/2, `vine_lash` 45/3, `spark_bite` 45/3, and `flare_burst` 45/7 for the all-foes tier), with descriptions that say they hit two foes. Do not edit or retarget any existing move, and do not touch `data/creatures` other than adding the three learnset entries (the files currently show unrelated whitespace-only changes; make the additive edits without reformatting or reverting anything else).
- [ ] **Step 4: Docs.** `battle-engine.md`: targeting (add `two_enemies`, `second_target`, how a missing or duplicate pick is replaced, the two-step selection), the Spread row (table keyed by number hit, Underdog still stacks), the AI paragraph (pair scoring). Main spec §2.4: the new target. Spec Status becomes `Implemented (plan: [documentation/plans/2026-11-05-two-target-moves.md](../plans/2026-11-05-two-target-moves.md))`. `HANDOFF.md`: what shipped, the behaviour change, and "multi-hit moves" as the next brainstorm.
- [ ] **Step 5: Verify in the real window.** Start a 1v3 debug battle with one of the new moves (use the existing battle tour or a temporary driver step; delete any temporary step afterwards), screenshot the two-step target menu and the battle, READ the images and report honestly what they show (both steps legible, nothing clipped, the second step names the first pick).
- [ ] **Step 6:** `bash scripts/check.sh` must end "All checks passed."; confirm the compendium lists the new moves with target "Two foes" and the Multi-target damage line shows both values. Then give the user the commit message.
