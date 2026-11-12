# AI Swapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The tactician AI scores a swap for each bench creature next to its moves and Rest, and swaps when the swap beats the best move by a margin. `basic` and `aggressive` never swap.

**Architecture:** `BattleAI.swap_score(engine, b, c, style, ref)` sums four terms (damage avoided, offence, entry via M6e's `enter_value`, escape). `choose` adds the best swap as a candidate only for `tactician` and only for a creature that has acted since entering; `choose_all` tracks claimed bench creatures so two actives never take the same one and stops asking a swapper for more actions. One small engine change: `Battler.acted`.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4. Checks: `bash scripts/check.sh`.

**Spec:** [documentation/specs/2026-11-12-m6f-ai-swapping-design.md](../specs/2026-11-12-m6f-ai-swapping-design.md)

**Commits:** the user writes every commit in this project. Do not `git commit`, stage or stash; each task ends with its test run, and the final message gives a suggested commit message.

**One suite:** run a single test file with
`"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<path>.gd --ignoreHeadlessMode -c`
where `GODOT` is the console exe named in `scripts/check.sh`. Below this is written `RUN <path>`.

## Global Constraints

- Styles: only `tactician` considers swaps. `basic` and `aggressive` choose exactly as before.
- Score units: HP-equivalent, from the scoring creature's side, comparable to `score()` for moves. Non-HP terms are multiples of `ref` (`best_damage(engine, b)`).
- New constants in `BattleAI`: `OFFENCE_ROUNDS := 1.0` and `SWAP_MARGIN := 0.25` (x `ref`; a swap must beat the best non-swap score by `SWAP_MARGIN * ref`).
- Scoring never draws from `engine.rng`.
- A swap is the swapper's whole turn; the engine already enforces this. The AI must not ask the same bid for further actions after choosing a swap.
- The engine changes only by `Battler.acted` (Task 1). No data or schema change.
- Faint replacement choice and wild creatures (no bench) are out of scope.

## Review Focus

- A 2v2 side where both actives want the same single bench creature: one swap, no double claim.
- Underdog bonus actions (a bid repeated in `actions_needed`): a swap ends that bid's actions, and a non-swapper still gets all its own.
- A creature just placed (swap-in or faint replacement) never swaps out before it has acted once; battle-start creatures are not blocked.
- Ping-pong: after the AI swaps A out for B, B does not swap straight back to A next round although A looks better against the threat (the `acted` gate plus the margin must break the loop; test two consecutive rounds).
- No bench (1v1 with one creature, or all bench fainted): `choose` returns what it returned before.
- The same-round threat uses the foe's usable moves only (no energy means the fallback), so a foe with an empty move pool still has a finite threat.
- `basic` consumes the same RNG draws as before.

---

### Task 1: `Battler.acted`

**Files:**
- Modify: `core/battle/battler.gd` (new field), `core/battle/battle_engine.gd:547` (`place`), `core/battle/action_runner.gd:48` (`execute`)
- Test: `tests/battle/test_battler_acted.gd` (new)

**Interfaces:**
- Produces: `Battler.acted: bool`. True for every creature placed at battle start; false for a creature placed afterwards (swap-in or faint replacement); set true when the creature starts executing any action (including a swap or a skipped turn).

- [ ] **Step 1: Write the failing tests** in `tests/battle/test_battler_acted.gd`, using `FixtureDB` as `test_swaps.gd` does:
  - `test_lead_creatures_start_acted`: 1v1 engine; both actives have `acted == true`; a bench creature on side 0 (`FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])`) also has `acted == true` before it ever enters.
  - `test_swap_in_has_not_acted`: after `resolve_round([BattleAction.swap(lead.bid, bench.bid)])`, `bench.acted == false` and `lead.acted == true`.
  - `test_acts_once_it_acts`: next round `resolve_round([use_move(bench.bid, "hit", foe.bid)])`, `bench.acted == true`.
  - `test_faint_replacement_has_not_acted`: knock the lead out (set `hp` to 1 and have the foe hit it); the replacement's `acted == false`.
- [ ] **Step 2: Run** `RUN battle/test_battler_acted`. Expected: FAIL (property `acted` missing, or assertions failing).
- [ ] **Step 3: Implement.** `var acted := false` on `Battler`, documented as "has run an action since last placed". `BattleEngine.place`: `b.acted = _starting`. `ActionRunner.execute`: after the alive/active guard and before the `match`, `b.acted = true`. A battle-start creature on the bench is placed later by `place` only if it enters, so the bench creature in `test_lead_creatures_start_acted` needs `acted` initialised true: initialise the field as `true` and have `place` overwrite it, so a never-placed bench creature reads true.
- [ ] **Step 4: Run** `RUN battle/test_battler_acted`, then `RUN battle/test_swaps`. Expected: PASS.

### Task 2: `swap_score`

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (constants, `swap_score`, `threat`, `_escape_value`)
- Test: `tests/battle/test_ai_swaps.gd` (new)

**Interfaces:**
- Consumes: `Battler.acted` is not used here. From M6e: `enter_value(engine, b, incoming, style := "tactician") -> float`. Existing: `best_damage`, `estimate_damage`, `_hit_count`, `status_value`, `DEBUFF_VALUE`, `KO_BONUS`, `STATUS_HORIZON`.
- Produces: `static func threat(engine, x: Battler) -> float` (sum over `x`'s foes' active creatures of that foe's best expected damage on `x`; usable damaging moves only, `_hit_count` for spread, accuracy ignored, as `best_damage` does); `static func swap_score(engine, b: Battler, c: Battler, style: String, ref: float) -> float`.

Fixtures for this file follow `test_ai_triggers.gd`: build a `Database` from `FixtureDB.raw()`, add the passives and held item (`welcome_ward` enter passive, a `ward` field state, a slow-status such as a `skip_chance` status) it needs, and `_engine(...)` helpers that give side 0 a lead and bench creature.

- [ ] **Step 1: Write the failing tests** (each builds the engine, sets HP/stages directly, then calls `swap_score(e, lead, bench, "tactician", ref)`):
  - `test_damage_avoided_when_lead_is_doomed`: lead at 1 HP, bench at full HP, foe `hit`s; score > `KO_BONUS`.
  - `test_no_damage_avoided_when_lead_is_healthy`: both full HP and equal; damage and offence terms are 0 within 1.0 (the score equals `enter_value` + escape = 0 with no triggers, no stages).
  - `test_doomed_bench_gains_nothing`: both creatures at 1 HP; the damage-avoided term is 0 (score within 1.0 of the offence difference, which is 0 for identical species).
  - `test_offence_prefers_the_harder_hitter`: lead species hits less than the bench species; score > 0. Reverse: score < 0.
  - `test_entry_term_matches_enter_value`: bench with `welcome_ward`; `swap_score` minus the same bench without the passive equals `enter_value` to within 0.001.
  - `test_escape_counts_negative_stages`: set the lead's `spd` stage to -2 (Speed's `DEBUFF_VALUE` is non-zero); score rises by `DEBUFF_VALUE.spd * ref * 2` against stage 0. A +2 stage on the lead lowers the score by the same amount (ruling in the spec: positive stages are lost value).
  - `test_escape_counts_skip_status`: the lead has a `skip_chance` status with rounds left; score rises by `chance/100 * ref * min(rounds, STATUS_HORIZON)`; a status with only `damage_fraction` adds nothing.
  - `test_swap_score_draws_no_rng`: `rng.state` unchanged across a call (2v2 with a benched creature, as the M6e RNG test).
  - `test_threat_uses_each_foe_best_move`: 2v2 foes; `threat(lead)` equals the sum of each foe's best `estimate_damage` on the lead.
- [ ] **Step 2: Run** `RUN battle/test_ai_swaps`. Expected: FAIL (functions missing).
- [ ] **Step 3: Implement `threat` and `swap_score`** in `core/battle/ai/battle_ai.gd` with the constants from Global Constraints. `swap_score` is
  `min(threat(b), hp_b) - min(threat(c), hp_c)`, plus `KO_BONUS` when `threat(b) >= hp_b` and `threat(c) < hp_c`,
  plus `(best_damage(c) - best_damage(b)) * OFFENCE_ROUNDS`,
  plus `enter_value(engine, b, c, style)`,
  plus `_escape_value(engine, b, ref)`: `DEBUFF_VALUE.get(stat, 0.0) * ref * -stage` summed over every stage of `b` (negative stages add, positive subtract), plus `chance / 100 * ref * mini(status_turns, STATUS_HORIZON)` for each `skip_chance` effect of `b`'s status (as `status_value` reads `status_turns` as rounds left).
  `best_damage(c)` reads the foes, not `c`'s position, so it needs no change; if `estimate_damage` consults the user's `active` state, note it in a comment and the doc, as with `enter_value`.
- [ ] **Step 4: Run** `RUN battle/test_ai_swaps`. Expected: PASS, and `RUN battle/test_ai_triggers` still passes.

### Task 3: Choosing swaps, coordination, docs, simulator

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`choose`, `choose_all`), `documentation/battle-engine.md`, `.superpowers/HANDOFF.md`, `tests/battle/test_testpack_simulations.gd` (only if the pack run shifts, as in M6e)
- Test: `tests/battle/test_ai_swaps.gd` (extend)

**Interfaces:**
- Consumes: `swap_score`, `Battler.acted`, `SWAP_MARGIN`.
- Produces: `static func choose(engine, bid: int, style: String, claimed: Array[int] = []) -> BattleAction` (a swap is returned only for `tactician`, when `b.acted`, when a bench creature not in `claimed` has `swap_score > best non-swap score + SWAP_MARGIN * ref`); `choose_all` passes and extends `claimed` and skips a bid's remaining slots after it swaps.

- [ ] **Step 1: Write the failing tests** (extend `test_ai_swaps.gd`):
  - `test_doomed_tactician_swaps`: 2-creature side 0, lead at 1 HP facing a hard hitter; `choose` returns kind `"swap"` to the bench bid.
  - `test_healthy_tactician_does_not_swap`: both full HP; returns a move.
  - `test_margin_keeps_a_close_call`: set up a swap whose score exceeds the best move's by less than `SWAP_MARGIN * ref` (adjust the bench creature's HP until the gap is inside the margin, asserting the gap in the test); returns a move. A swap just past the margin is taken.
  - `test_basic_and_aggressive_never_swap`: the doomed fixture, for `"basic"` and `"aggressive"`, returns a move, and `basic` draws the same RNG count as before (compare `rng.state` against an engine with no bench).
  - `test_two_doomed_actives_claim_distinct_bench`: 2v2 with one bench creature; `choose_all(e, 0)` contains exactly one swap, and the other creature uses a move.
  - `test_two_doomed_actives_two_bench`: 2v2 with two bench creatures; two swaps with different `swap_in`.
  - `test_swapper_takes_no_further_actions`: Underdog or a side with `bonus_actions` of 1 (set `e.sides[0].underdog = {"bonus_actions": 1}`): a swapping bid appears once in the result; a non-swapper still appears twice.
  - `test_fresh_swap_in_does_not_swap_back`: after the AI swaps lead out, resolve the round; the newcomer (`acted == false`) gets a move even though its HP is low and the old lead is healthy; after it acts once, `choose` may swap it.
  - `test_no_bench_changes_nothing`: 1v1 with no bench creature; the result equals a move choice and `rng.state` is unchanged versus the previous behaviour (a swap-free engine).
- [ ] **Step 2: Run** `RUN battle/test_ai_swaps`. Expected: FAIL on the new tests (no swaps chosen).
- [ ] **Step 3: Implement `choose` and `choose_all`.** In `choose`, for `style == "tactician" and b.acted`, after the move/Rest options are built, find the best swap over `engine.sides[b.side].bench()` excluding `claimed`; return it only when `swap_score > best.score + SWAP_MARGIN * ref`. `choose_all` keeps `claimed: Array[int]` and `swapped: Array[int]`; for each bid in `actions_needed`, skip a bid in `swapped`; if the chosen action's kind is `"swap"`, append `swap_in` to `claimed` and the bid to `swapped`. No scoring path draws from `engine.rng`.
- [ ] **Step 4: Run** `RUN battle/test_ai_swaps`, then `bash scripts/check.sh`. Expected: all pass. If `test_testpack_simulations` fails on a trigger-coverage exemption, add the id to `EXEMPT_TRIGGERS` with a reason and ledger the ruling, as M6e did, or shrink the list if one now fires.
- [ ] **Step 5: Simulate before and after.** Using `tools/simulate.gd -- --battles=200 --seed=1 --format=2v2 --level=10 --ai=tactician,aggressive` (and `--level=40`, `--format=3v3`, and the reversed order), compare against the same runs on the previous commit (stash is not allowed: run "before" by temporarily making `choose` ignore swaps with a local edit, record, revert). Report the swap count per battle (add a temporary counter, do not commit it), the side win rates and the largest species shift. Flag a swap rate above 1 per battle or a win-rate move above 2 points.
- [ ] **Step 6: Docs.** `documentation/battle-engine.md`: "Passives and the AI" drops "the AI never swaps" and the `enter` bullet says `swap_score` calls `enter_value`; the AI styles table gets the tactician swap row; the test table gains `test_ai_swaps.gd` and `test_battler_acted.gd`; the `Battler` field is mentioned where battlers are described. `.superpowers/HANDOFF.md`: M6f entry with rulings and deferred minors; "What's next" lists M6g.
- [ ] **Step 7: Final run.** `bash scripts/check.sh`. Expected: "All checks passed."
