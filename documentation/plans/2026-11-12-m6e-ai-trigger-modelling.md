# AI Trigger Modelling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The tactician and aggressive AI styles price `knockout`, `faint`, `status` and `round_end` triggers in move scoring, and a tested `enter_value` waits for M6f's swap logic.

**Architecture:** One shared valuator in `core/battle/ai/battle_ai.gd`, `trigger_value`, prices one trigger's effect list from the scoring creature's side (signed by whose side the effect lands on, weighted by chance and `when`, and scaled per style: setup effects x0.5 for aggressive). `score` calls it in four places (a lethal hit, a status effect, heal urgency, non-lethal damage credit). The field-state branch of `_setup_value` is extracted so the valuator can reuse it. No engine, data or schema change.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4. Checks: `bash scripts/check.sh`.

**Spec:** [documentation/specs/2026-11-12-m6e-ai-trigger-modelling-design.md](../specs/2026-11-12-m6e-ai-trigger-modelling-design.md)

**Commits:** the user writes every commit in this project. Do not `git commit`, stage or stash; each task ends with its test run, and the final message gives a suggested commit message.

**One suite:** run a single test file with
`"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<path>.gd --ignoreHeadlessMode -c`
where `GODOT` is the console exe named in `scripts/check.sh`. Below this is written `RUN <path>`.

## Global Constraints

- Styles: `tactician` and `aggressive` read the new terms; `basic` scores exactly as before (its `score` is not even used for choosing).
- Sign convention: every value is from the scoring creature `b`'s side. A creature's gain counts for its owner (`landing.side == b.side` is +1, else -1).
- Each trigger's value is multiplied by `chance / 100`; a trigger whose `when` fails (checked on the holder) is 0; a `per_battle` held item that is `held_spent` is ignored (a `consumed` item counts once).
- Style weight: effects paid in HP (`damage`, `heal`) x1.0 for both styles; setup effects (`apply_status`, `stat_stage`, `restore_energy`, `cure_status`, `apply_field_state`) x1.0 for tactician and x`AGGRESSIVE_SETUP_MULT` (0.5) for aggressive.
- New constants in `BattleAI`: `ENERGY_VALUE := 0.25` (x `ref` per full energy bar), `AGGRESSIVE_SETUP_MULT := 0.5`.
- Scoring must never draw from `engine.rng`.
- `hit` retaliation (`_retaliation`), absorb, blocks, cure values and every existing AI test stay unchanged.
- Test code must not contain the literals `tp_` or `testpack` outside the test pack's own files.

## Review Focus

Inputs the spec implies but no task's own happy-path tests would catch; each has a test in the task that owns it.

1. A trigger whose `when` fails, or a spent `per_battle` item, must be worth exactly 0 (Task 2).
2. A faint trigger with its own `target` (for example `all_allies` of the holder) must be charged to those creatures, not the killer (Task 2).
3. A multi-hit finishing move and a two-foe spread move: the knockout and faint terms are charged once per finished target, not once per hit (Task 2).
4. A `heal` trigger on a creature at full HP is worth 0, and a foe's round-end heal never makes a lethal hit worse (Tasks 2 and 3).
5. A status effect on a foe that already has a status or blocks it adds no `status`-trigger term (Task 3).

## Interfaces (shared by all tasks)

```gdscript
# core/battle/ai/battle_ai.gd
const ENERGY_VALUE := 0.25
const AGGRESSIVE_SETUP_MULT := 0.5

static func trigger_value(engine: BattleEngine, b: Battler, holder: Battler, trig: Dictionary,
		landing: Battler, ref: float, style: String) -> float
static func enter_value(engine: BattleEngine, b: Battler, incoming: Battler, style := "tactician") -> float
static func round_end_hp(engine: BattleEngine, t: Battler, hp_after := -1) -> float
static func _field_state_value(engine: BattleEngine, b: Battler, source: Battler, e: Dictionary,
		side_index: int, ref: float, for_trigger := false) -> float
```

`trig` is one entry of a `PassiveDef.triggers` array (`{on, chance, contact, when, effects}`); `landing` is the creature
an effect without its own `target` lands on.

---

### Task 1: Extract the field-state value and baseline the simulator

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_setup_value`, `apply_field_state` branch at about lines 314-361)
- Create: none. Baseline output goes to the scratchpad directory (`$SCRATCH/sim_before_*.txt`).

**Interfaces:**
- Produces: `_field_state_value(engine, b, source, e, side_index, ref, for_trigger := false) -> float`, used by Task 2.

- [ ] **Step 1: Baseline.** Run `RUN battle/test_ai.gd`, `battle/test_ai_passives.gd`, `battle/test_ai_cure.gd`, `battle/test_ai_multi_hit.gd`. Expected: all PASSED. Then run the simulator four times and save each output:
  `"$GODOT" --headless --path . --script res://tools/simulate.gd -- --battles=200 --seed=1 --format=2v2 --level=<L> --ai=<A>,<B>`
  for `L` in 10 and 40 and `(A,B)` in `(tactician,aggressive)` and `(aggressive,tactician)`. Expected: each prints a win-rate summary.

- [ ] **Step 2: Extract.** Move the body of `_setup_value`'s `"apply_field_state"` match arm into
  `static func _field_state_value(engine, b, source, e, side_index, ref, for_trigger := false) -> float`. The arm computes the absolute side index `s` and the ctx itself today; the new function takes `side_index` (that `s`) instead, and uses `engine.passive_rules.field_boost(source).x` where the arm used `field_boost(b)`. `_setup_value` keeps computing `s` from its move target and calls the function with `source = b`, `for_trigger = false`, `value += ...` and `continue` as today. `for_trigger` is not read yet.

- [ ] **Step 3: Verify unchanged.** Rerun the four AI suites (Expected: all PASSED) and the four simulator runs; each must be byte-identical to its Step 1 file (`diff`). Expected: no differences.

---

### Task 2: The valuator, plus the knockout and faint terms

**Files:**
- Modify: `core/battle/ai/battle_ai.gd`
- Create: `tests/battle/test_ai_triggers.gd`

**Interfaces:**
- Consumes: `_field_state_value` (Task 1), `status_value`, `DEBUFF_VALUE`, `state_benefit`, `NEW_STATE`, `BattleMath.damage`.
- Produces: `trigger_value(...)` and `_kill_triggers_value(engine, b, t, ref, style) -> float` (the user's `knockout` triggers plus the target's `faint` triggers when `b` finishes `t`), used by `score`; Task 3 reuses `trigger_value`.

The test suite is built around one fixture and helpers (later tasks add to it).

- [ ] **Step 1: Write the failing tests** in `tests/battle/test_ai_triggers.gd`. Fixture in `before()`: `FixtureDB.raw()` plus these passives (each merged with `name` and `description` like `test_ai_passives.gd`), validated, then `Database.from_raw`:
  - `ko_heal`: `knockout` trigger, effects `[heal 0.25]` (HP currency).
  - `ko_speed`: `knockout`, effects `[stat_stage spd +1]` (setup currency).
  - `faint_burn`: `faint`, effects `[damage power 40]` (HP currency, lands on the killer).
  - `faint_soak`: `faint`, effects `[apply_field_state side "enemy" state "soaked"]` (lands on the killer's side; `soaked` is hostile in the fixture).
  - `faint_ally`: `faint`, effects `[heal 0.5 with target "all_allies"]`.
  - `ko_when_low`: `knockout`, `when {hp_below: 0.5}`, effects `[heal 0.25]`.
  - `ko_half`: `knockout`, `chance 50`, effects `[heal 0.25]`.
  Plus held item `ko_charm` (category `held`, `held.use "per_battle"`, a `knockout` trigger healing 0.25), following the item shape in `test_ai_passives.gd`.
  Helpers: `_make(species, passive, moves, level := 10, held := "")`; `_engine(my_passive, foe_passive := "", my_hp_fraction := 0.5, foe_hp := 1)` builds a 1v1 engine with side 0 `blob` knowing `["hit"]` and side 1 `tank`, sets the user's HP to `my_hp_fraction x max_hp` and the foe's HP to `foe_hp`; `_score(e, style)` scores `hit` from side 0 against the foe; `_ref(e)` is `BattleAI.best_damage(e, user)`.
  Tests (assertions, with `base = _score(_engine(""), style)`):
  - `test_a_finishing_move_is_credited_with_the_users_knockout_trigger`: for both `"tactician"` and `"aggressive"`, `_score(_engine("ko_heal"), s) - base` equals `minf(0.5 x max_hp, 0.25 x max_hp)`, so `0.25 x max_hp` to within 0.001.
  - `test_the_knockout_term_is_only_for_a_lethal_hit`: with `foe_hp` large, `_score(_engine("ko_heal"), s) == base_for_that_hp` for both styles.
  - `test_setup_effects_scale_with_ref_and_by_style`: tactician delta for `ko_speed` is `DEBUFF_VALUE["spd"] x ref x 1` (0.08 x ref); aggressive delta is `AGGRESSIVE_SETUP_MULT` x that.
  - `test_hp_effects_are_valued_equally_by_both_styles`: the `ko_heal` delta is identical for tactician and aggressive.
  - `test_a_failing_when_or_a_spent_item_is_worth_nothing`: `ko_when_low` with the user at full HP has delta 0 (and at 40% HP the full 0.25 x max_hp); a creature holding `ko_charm` has the delta, and with `held_spent = true` delta 0.
  - `test_chance_weights_the_trigger`: `ko_half` delta is half of `ko_heal`'s.
  - `test_a_heal_trigger_at_full_hp_is_worth_nothing`: `ko_heal` with the user at full HP, delta 0.
  - `test_the_targets_faint_trigger_is_charged_to_the_killer`: `faint_burn` on the foe lowers the lethal move's score by the damage the trigger would do to the user (`min(hp, BattleMath.damage(...))`, computed in the test with an `EffectContext` as `_retaliation` does), for both styles.
  - `test_a_hostile_field_state_on_our_side_is_a_cost`: `faint_soak` lowers the score by `NEW_STATE x ref` for tactician and by `AGGRESSIVE_SETUP_MULT x NEW_STATE x ref` for aggressive.
  - `test_a_faint_trigger_with_its_own_target_is_charged_there`: `faint_ally` on the foe heals the foe's allies, not the killer: in a 1v2 engine (foe slots 0 and 1, hp of foe 0 set to 1, foe 1 hurt) the lethal move's score drops by the heal foe 1 would get (negative for the AI), and with the foe alone (no allies standing) the delta is 0.
  - `test_finishing_an_ally_pays_the_faint_term_only`: in a 2v1 engine, a move that kills the AI's own ally on a `ko_heal` user does not gain the knockout credit but does lose `faint_burn`'s cost when the ally holds it.
  - `test_each_finished_target_pays_once`: a `two_enemies` move (add the test's own move, as `test_ai_passives.gd` does) that kills both foes pays each foe's `faint_burn` once, and a multi-hit move (`hits {min 3, max 3}`) that kills pays the knockout credit once.
  - `test_scoring_never_draws_from_the_rng`: `e.rng.state` is identical before and after `_score` with `ko_heal`, `faint_burn` and `faint_soak` in play.
  - `test_basic_style_is_unchanged`: `BattleAI.score(e, user, move, foe_bid, "basic")` equals its value with no trigger passives.

- [ ] **Step 2: Run to verify they fail.** `RUN battle/test_ai_triggers.gd`. Expected: FAILED (the deltas are 0 because nothing is modelled).

- [ ] **Step 3: Implement `trigger_value(engine, b, holder, trig, landing, ref, style)`.** Return 0 when `when_holds(holder, trig.when)` is false. Build one `EffectContext` (`user = holder`, `source = "passive"`, `attacker = landing` when the trigger is `faint` or `hit`, `target_side = holder.side`). For each effect: resolve its creatures with `engine._effect_targets(ctx, e.target)` when it has a `target`, else `[landing]`; skip dead ones. Value per creature `t`, then multiplied by `+1` if `t.side == b.side` else `-1`, then by `AGGRESSIVE_SETUP_MULT` when `style == "aggressive"` and the op is a setup op, then summed and multiplied by `trig.chance / 100`:
  - `damage`: `-minf(t.hp(), BattleMath.damage(engine, ctx_for_t, e, t, false).amount)`, a ctx built like `_retaliation`'s (user = holder, attacker = the killer, targets = [t]); the HP sign flips with the side rule above (damage to the AI's side is negative, to a foe positive).
  - `heal`: `+minf(missing HP, fraction x max HP)`.
  - `apply_status`: `-status_value(engine, t, e.status, ref) x (e.get("chance", 100) / 100)`, 0 when `t.status() != ""` or `blocks_status(t, e.status)`.
  - `stat_stage`: `DEBUFF_VALUE.get(e.stat, 0.1) x ref x stages`; 0 for a negative `stages` when `guards_stage(t, e.stat, holder)`.
  - `restore_energy`: `ENERGY_VALUE x ref x minf(fraction, 1 - energy / max energy)`.
  - `cure_status`: `+status_value(engine, t, t.status(), ref, t.status_turns)` when `t` has a matching status.
  - `apply_field_state`: not per creature. Once per effect, `side_index = ctx.side_index(e.side)` with `ctx.target_side = holder.side`; value `_field_state_value(engine, b, holder, e, side_index, ref, true)`, scaled by the style weight, not signed by creature side.
  Other ops are 0.
  In `_field_state_value`, when `for_trigger` is true and `side_index == b.side` and the state's `state_benefit` is below 0, return `-NEW_STATE x ref` (before the existing own-side branch, which stays as is for `for_trigger` false).

- [ ] **Step 4: Implement `_kill_triggers_value(engine, b, t, ref, style)`** and call it from `score`. It sums `trigger_value` over (a) `b`'s `knockout` triggers (passive def triggers plus the held item's, skipping a `per_battle` item that is `held_spent`), landing `b`, holder `b`, only when `t.side != b.side`, and (b) `t`'s `faint` triggers, holder `t`, landing `b`. In `score`'s target loop, when `style != "basic"` and `est >= float(t.hp())`, add `_kill_triggers_value(...)` to `value` for both a foe target and an ally target (for an ally the function returns only the faint part). Collect the passive and held trigger lists with one small helper, `_triggers(engine, holder, on) -> Array`, that mirrors `_retaliation`'s collection.

- [ ] **Step 5: Run to verify they pass.** `RUN battle/test_ai_triggers.gd`, then `RUN battle/test_ai.gd`, `battle/test_ai_passives.gd`, `battle/test_ai_cure.gd`, `battle/test_ai_multi_hit.gd`. Expected: all PASSED.

---

### Task 3: The status and round_end terms, and enter_value

**Files:**
- Modify: `core/battle/ai/battle_ai.gd`, `tests/battle/test_ai_triggers.gd`

**Interfaces:**
- Consumes: `trigger_value`, `_triggers` (Task 2).
- Produces: `round_end_hp`, `enter_value` (used by M6f).

- [ ] **Step 1: Write the failing tests.** Extend the fixture: passives `taunt` (`status` trigger, `stat_stage patk +1` landing on itself), `taunt_half` (same, `chance 50`), `thorn_status` (`status` trigger, `damage power 30`), `photo` (`round_end`, `heal 0.25`), `welcome_soak` (`enter`, `apply_field_state side "enemy" state "soaked"`), `welcome_ward` (`enter`, `apply_field_state side "own" state "ward"`, with a new fixture field state `ward`, `passive [stat_mod patk 1.2]`), `welcome_when` (`enter`, `when {hp_below: 0.5}`, same effect as `welcome_ward`). Fixture moves: `mend` (status, target `self`, `[heal 0.5]`, `always_hits`), `ignite` (status, `one_enemy`, `[apply_status burn]`, `always_hits`), `ignite_half` (same with effect `chance 50`).
  Tests:
  - `test_a_status_move_into_a_punishing_status_trigger_scores_lower`: `ignite` against a foe with `taunt` is lower than against a plain foe by `DEBUFF_VALUE["patk"] x ref x 1` for tactician, and by `AGGRESSIVE_SETUP_MULT` of that for aggressive (whose base `ignite` score is 0, so the score equals the negative term).
  - `test_aggressive_never_seeks_a_status_for_its_trigger`: against `thorn_status` (a trigger that hurts the foe), the tactician's `ignite` score rises by the damage and the aggressive `ignite` score stays equal to the plain-foe score (the term is clamped to 0).
  - `test_status_term_weights_both_chances`: `ignite_half` against `taunt_half` is a quarter of `ignite` against `taunt`.
  - `test_no_status_term_when_the_status_cannot_land`: the same cost is 0 against a foe that already has a status, and against a foe whose passive is `status_immune` plus `taunt`-like trigger (a second passive is not possible, so give the foe a held item with the trigger and the passive `status_immune`).
  - `test_own_round_end_healing_lowers_heal_urgency`: with the user at 40% HP, `mend` scores `0.5 x max_hp` without `photo` and `(0.6 - 0.25) x max_hp` with it (missing HP minus the round-end heal, to within 0.001), for both styles.
  - `test_a_foes_round_end_heal_lowers_a_non_lethal_hit_only`: with the foe at an HP above the move's estimate, `hit` scores lower against a `photo` foe by `minf(heal, est)`, where the heal is `min(foe's missing HP after the hit, 0.25 x max HP)`; with the foe at 1 HP the lethal `hit` scores the same with and without `photo`.
  - `test_enter_value_signs`: `enter_value(e, user, incoming)` is positive for an ally `welcome_soak` (a hostile state on the foe), positive for `welcome_ward` on the AI's side, negative for a foe holding `welcome_soak` (it lands on the AI's side) and for a foe `welcome_ward` (it helps the foe), 0 for a creature with no passive, 0 for `welcome_when` while the incoming creature is above half HP, and half of `welcome_soak`'s value with `chance 50`.

- [ ] **Step 2: Run to verify they fail.** `RUN battle/test_ai_triggers.gd`. Expected: FAILED on the new tests only.

- [ ] **Step 3: Implement the status term** in `score`'s effects loop: for each `apply_status` effect, for each target that is a foe with `status() == ""` and not blocking it, add `chance_e x (sum of trigger_value over the target's "status" triggers, holder = landing = the target)`. For `aggressive`, the term is `minf(0.0, term)`. It applies to both non-basic styles and is in addition to the tactician's `_setup_value` status value.

- [ ] **Step 4: Implement `round_end_hp(engine, t, hp_after := -1) -> float`:** the expected end-of-round HP change of `t` from its `round_end` triggers (`_triggers(engine, t, "round_end")`): for each trigger whose `when` holds on `t`, chance-weighted, a `heal` effect landing on `t` adds `minf(missing HP, fraction x max HP)` (missing HP computed from `hp_after` when given, else `t.hp()`), and a `damage` effect landing on `t` subtracts the damage (capped at `t`'s HP). Effects with another `target` are ignored. Use it in `score`: (a) in the `heal` branch replace `missing` with `maxf(0.0, missing - round_end_hp(engine, b))`; (b) in the foe branch, for a non-lethal hit (`est < t.hp()`), reduce `landed` by `round_end_hp(engine, t, t.hp() - roundi(est))`, floored at 0 (`landed = maxf(0.0, landed - ...)`). Both are applied for non-basic styles.

- [ ] **Step 5: Implement `enter_value(engine, b, incoming, style := "tactician") -> float`:** `ref = best_damage(engine, b)`; the sum over `_triggers(engine, incoming, "enter")` of `trigger_value(engine, b, incoming, trig, incoming, ref, style)`. Add a doc comment that M6f's swap scoring calls it and that nothing in `choose` does yet.

- [ ] **Step 6: Run to verify they pass.** `RUN battle/test_ai_triggers.gd`, then the four existing AI suites. Expected: all PASSED.

---

### Task 4: Real data, simulations, docs and the full check

**Files:**
- Modify: `tests/battle/test_ai_triggers.gd`, `documentation/battle-engine.md`, `.superpowers/HANDOFF.md`

- [ ] **Step 1: Write the failing real-data test** `test_shipped_triggers_move_the_score` in `tests/battle/test_ai_triggers.gd`. Load `DataLoader.load_database("res://data", "res://dialogue")` (assert no errors), build a 1v1 engine from it with a Lv 20 Tidepup (`splash_jab`) against a Lv 20 Pebblet at 1 HP, and compare a tactician's and an aggressive AI's `splash_jab` score with the user's passive set to `""`, `cold_snap` (setup: +1 Speed), `finisher` (setup: energy; set the user's energy below max) and, for the foe, `ember_trail`. Assert: `cold_snap` and `finisher` each raise the score for both styles; `ember_trail` on the foe lowers it for both styles. Run it. Expected: it passes, because Tasks 2 and 3 are done, so this is a regression guard on real data and not a RED step. Each assertion compares scores that must differ, so a delta of 0 means the trigger was not read and fails it.

- [ ] **Step 2: Pack and simulation runs.** Run `RUN battle/test_testpack_simulations.gd` and the 30-seed pack simulation (`tests/battle/test_testpack_mechanics.gd` and the suites `check.sh` runs). Expected: PASSED; if an `EXEMPT_MOVES` or `EXEMPT_TRIGGERS` entry is now fielded, or a new miss appears, report it by name and update the exemption list with the reason only if the AI's choice legitimately changed. Run the four Task 1 simulator commands again to `$SCRATCH/sim_after_*.txt` and compare with the before files: report each win-rate shift. Expected: no new outlier (a species whose win rate moves by more than 10 points).

- [ ] **Step 3: Docs.** In `documentation/battle-engine.md` "Passives and the AI": add one bullet per rule (knockout, faint, status, round_end, enter) with the style weights, the own-side-hostile-state rule, and the aggressive clamp; replace "Not modelled: faint, knockout, enter, round-end and status triggers." with "Not modelled: own-side `status` triggers, and `enter` in move scoring (`enter_value` is for the swap logic in M6f)." Add `test_ai_triggers.gd` to the test-suite table. Update the AI-styles table row for `aggressive` ("... reads knockout, faint, status and round-end triggers, weighting setup effects at half"). In `.superpowers/HANDOFF.md` add an "M6e AI trigger modelling" entry (what shipped, rulings, deferred minors, next: M6f swap AI then M6g styles), update the header and "What's next".

- [ ] **Step 4: Full check.** `bash scripts/check.sh`. Expected: "All checks passed."
