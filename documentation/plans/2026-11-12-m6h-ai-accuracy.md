# AI Accuracy Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four accuracy fixes in the battle AI: retaliation priced through the M6e trigger valuator, a knockout bonus that scales with `ref`, swap scoring that sees the bench creature's own passive, held item and ally auras, and an expected (not worst-case) threat in 2v2 and 3v3.

**Architecture:** All changes are in `core/battle/ai/battle_ai.gd` plus tests and docs. Task 1 is a refactor proven against the simulator; Tasks 2 to 4 change choices on purpose and are each measured against the previous state with the simulator. No engine, data or schema change.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4. Checks: `bash scripts/check.sh`.

**Spec:** [documentation/specs/2026-11-12-m6h-ai-accuracy-design.md](../specs/2026-11-12-m6h-ai-accuracy-design.md)

**Commits:** the user writes every commit in this project. Do not `git commit`, stage or stash (restore mutated files from a `cp` backup, never `git checkout`); each task ends with its test run, and the final message gives a suggested commit message.

**One suite:** run a single test file with
`"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<path>.gd --ignoreHeadlessMode -c`
where `GODOT` is the console exe named in `scripts/check.sh`. Below this is written `RUN <path>`. The simulator is `"$GODOT" --headless --path . -s tools/simulate.gd -- --battles=200 --seed=1 --format=2v2 --level=L --ai=A,B [--pack=0]`. A simulator **snapshot** is the output minus its first line and minus Godot's exit-time lines (`ObjectDB instances`, `resources still in use`, `Pages in use`), saved to the scratchpad directory; the four **baseline runs** are `--ai=tactician,aggressive`, `--ai=aggressive,tactician` and `--ai=tactician,basic` at level 10, and `--ai=tactician,aggressive` at level 40, each with the default pack and again with `--pack=0` (eight files).

## Global Constraints

- `basic` and `aggressive` are unaffected by every task (the retaliation weight of `aggressive` is 0; `basic` is never scored). `tactician`, `passive`, `defensive` and `trickster` may change in Tasks 2 to 4 only as the spec says.
- New constants and helpers in `BattleAI`: `KO_FACTOR := 1.4` and `static func ko_bonus(ref: float) -> float` (returns `KO_FACTOR * ref`); `static func _with_swapped_in(engine: BattleEngine, b: Battler, c: Battler, f: Callable) -> Variant`; `_share(m: MoveDef, n: int) -> float`. `KO_BONUS` is removed.
- Scoring never draws from `engine.rng`, emits no event, and leaves no engine state changed (slots, `active` flags, stages).
- `swap_score(engine, b, c, style, ref)` keeps its signature; `enter_value(engine, b, incoming, style := "tactician", ref := -1.0)` gains an optional `ref` (computed from `best_damage(engine, b)` when negative); `_retaliation(engine, b, m, t, ref, style)` gains `style`.
- The M6g targets must hold after Task 4 (2v2, 200 battles, seed 1, both orders, levels 10 and 40, against the tactician): `passive` wins at most 40%, `defensive` and `trickster` each between 35% and 65%, no style draws more than 2% of its battles. A miss caused by these changes is tuned with `KO_FACTOR` and reported, not relaxed.

## Review Focus

- A 2v2 lead that one foe move could knock out but that is hit by only one of two foes in expectation: it is no longer flagged doomed (intended), and `swap_score` stays finite and continuous there.
- `_with_swapped_in` when `b` has no slot (`slot_of` is -1, e.g. `b` not active), when `c` is already active, and when the callable returns a `float`: the slots and flags are restored in every path.
- Nested or repeated use: `_best_swap` evaluates candidates one after another; after each, the side's `active()` list and every battler's `active` flag are as before.
- A foe with an empty damaging move pool (only the fallback) keeps `threat` finite; a side with one creature (`n` = 1) keeps `threat` identical to today.
- Spread moves (`all`, `all_enemies`) count in full in `threat`, and an `all` move that hits the foe's own ally is not made cheaper by the share.
- A retaliation trigger on a held item that is `per_battle` and spent costs 0; a contact trigger vs a non-physical move costs 0; a trigger whose `when` fails costs 0.
- `ko_bonus` with a tiny `ref` (the floor of `best_damage` is 1) stays positive and the doomed-swap bonus still scales with it.
- `basic` consumes the same RNG as before; `aggressive` choices are unchanged.

---

### Task 1: Retaliation through `trigger_value`

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_retaliation`, its call in `score`)
- Test: `tests/battle/test_ai_accuracy.gd` (new)

**Interfaces:**
- Consumes: `_triggers(engine, holder, on) -> Array` and `trigger_value(engine, b, holder, trig, landing, ref, style, pending_status := "") -> float` (M6e).
- Produces: `_retaliation(engine, b, m, t, ref, style) -> float` (a positive cost to `b`).

- [ ] **Step 1: Capture the baseline** before any edit: the eight snapshots (four baseline runs, each with the default pack and with `--pack=0`). Run one twice and compare to confirm the output is deterministic. Expected: eight files, no `SCRIPT ERROR`.
- [ ] **Step 2: Write the failing tests** in `tests/battle/test_ai_accuracy.gd` (fixtures as in `test_ai_triggers.gd`: a raw from `FixtureDB.raw()` with these passives, validated):
  - `recoup`: `{"on": "hit", "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}`; `thorns_status`: a hit trigger inflicting `burn` on the attacker (`target` omitted); `contact_burn`: the same with `"contact": true`; plus a held item `scald_charm` with a `per_battle` hit trigger doing the same burn.
  - `test_a_foes_self_heal_on_hit_is_a_retaliation_cost`: the score of a non-lethal `hit` into a foe with `recoup` (foe damaged, so the heal is real) is lower than into the same foe without it, by `min(missing, fraction x max HP)` (the foe's gain).
  - `test_a_status_on_the_attacker_costs_what_status_value_says`: into a foe with `thorns_status` the score drops by `status_value(...)` of burn for the attacker.
  - `test_a_contact_trigger_is_ignored_for_a_non_physical_move`: with `contact_burn`, a physical move pays and a special move pays nothing.
  - `test_a_spent_per_battle_item_and_a_failed_when_cost_nothing`: set `held_spent` true, then give the trigger `"when": {"hp_below": 0.1}` on a full-HP foe: both cost 0.
- [ ] **Step 3: Run** `RUN battle/test_ai_accuracy`. Expected: the self-heal test FAILS (the old code ignores effects not landing on the attacker); the others may already pass.
- [ ] **Step 4: Implement.** `_retaliation` collects `_triggers(engine, t, "hit")`, skips a trigger when `trig.contact and m.category != "physical"`, and returns the negative of the sum of `trigger_value(engine, b, t, trig, b, ref, style)`. Pass `style` from `score`.
- [ ] **Step 5: Run** `RUN battle/test_ai_accuracy` and the AI suites unedited: `test_ai`, `test_ai_passives`, `test_ai_cure`, `test_ai_multi_hit`, `test_ai_triggers`, `test_ai_swaps`, `test_ai_styles`. Expected: PASS. A failing existing retaliation test means a real behavioural difference: find it, and rule on it in the ledger (an accepted difference needs the test updated and the reason recorded).
- [ ] **Step 6: Compare simulator snapshots** to the baseline. Expected: the `--pack=0` snapshots are identical (the shipped content has only simple attacker-landing triggers). The default-pack snapshots may differ (the test pack has richer triggers): record how, and ledger it as accepted.

### Task 2: A knockout bonus that scales with `ref`

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`KO_BONUS` replaced; `score`, `swap_score`), `tests/battle/test_ai_swaps.gd`, `tests/battle/test_ai_styles.gd` (the lines that read `BattleAI.KO_BONUS`)
- Test: `tests/battle/test_ai_accuracy.gd` (extend)

**Interfaces:**
- Produces: `KO_FACTOR`, `ko_bonus(ref: float) -> float`.

- [ ] **Step 1: Write the failing tests:**
  - `test_ko_bonus_scales_with_ref`: `ko_bonus(10.0)` is `14.0`, `ko_bonus(20.0)` is twice it, and `ko_bonus(1.0)` is positive.
  - `test_a_finishing_move_gains_ko_bonus_of_its_own_ref`: for a foe at 1 HP, the score of `hit` exceeds the score against the same foe at full HP by `ko_bonus(ref)` plus the landed-damage difference (compute both; the KO term is the remainder), for `tactician`; the `ko` weight (0 for `passive`) removes it.
  - `test_the_doomed_swap_bonus_scales`: a doomed-lead `swap_score` with the lead's best damage doubled (give the lead a stronger move) rises by exactly the change in `ko_bonus`.
  - Update the three existing tests that read `KO_BONUS` (`test_ai_swaps.gd` line with `1.0 - d_bench + BattleAI.KO_BONUS`, `test_ai_styles.gd` `avoided += BattleAI.KO_BONUS` twice and the damage/ko weights test) to use `BattleAI.ko_bonus(ref)` with `ref = BattleAI.best_damage(e, lead)`.
- [ ] **Step 2: Run** `RUN battle/test_ai_accuracy`. Expected: FAIL (`ko_bonus` missing; the edited tests do not parse).
- [ ] **Step 3: Implement** `KO_FACTOR := 1.4` and `ko_bonus`; replace both uses of `KO_BONUS` (`score`: `ko_bonus(ref) * prof.ko`; `swap_score`: `avoided += ko_bonus(ref)`); delete `KO_BONUS`.
- [ ] **Step 4: Run** the AI suites. Expected: PASS.
- [ ] **Step 5: Measure.** Snapshot the four baseline runs (default pack) and compare with Task 1's: record the side win rates, draws, average rounds and (with a temporary, uncommitted counter) swaps per battle for 2v2 at levels 10 and 40.

### Task 3: Evaluate a swap with the bench creature in place

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_with_swapped_in`, `swap_score`, `enter_value`)
- Test: `tests/battle/test_ai_accuracy.gd` (extend)

**Interfaces:**
- Produces: `_with_swapped_in(engine, b, c, f: Callable) -> Variant` (puts `c` in `b`'s slot with `b.active` false and `c.active` true, calls `f`, restores both, returns `f`'s result; `b` must be active); `enter_value(..., ref := -1.0)`.

Fixtures: passives `sponge` (`absorb_type` electric 0.25), `strong` (`stat_mod` patk x2), `guard_aura` (`scope` allies, `incoming_type_mod` x0.5); a foe whose best move is electric (`zap` from the fixture, special).

- [ ] **Step 1: Write the failing tests:**
  - `test_a_bench_absorber_removes_the_threat_it_would_absorb`: lead at full HP, bench creature without, then with `sponge`, foe's best move electric: `swap_score` rises by exactly `min(threat_without, bench HP)` (the bench creature now takes nothing).
  - `test_a_bench_stat_boost_counts_in_its_damage_edge`: bench with `strong`: `swap_score` rises by `best_damage` with the boost minus without (positive).
  - `test_an_active_allys_aura_covers_the_incoming_creature`: 2v1 with an ally carrying `guard_aura`: the same bench creature scores higher with the ally's aura than with a plain ally.
  - `test_the_in_place_evaluation_leaves_no_trace`: snapshot every slot occupant, every battler's `active` and `stages`, and `rng.state`; call `swap_score` for every bench creature of a 2v2 side; the snapshot is identical afterwards. Also `_with_swapped_in` called with an inactive `b` asserts or returns without changing anything (rule in the ledger).
  - `test_enter_value_counts_a_benched_creatures_field_boost`: a bench creature with `field_boost` and an `enter` field-state passive: `enter_value` through `swap_score` uses the boosted stacks.
- [ ] **Step 2: Run** `RUN battle/test_ai_accuracy`. Expected: the first three and the last FAIL; the "no trace" test fails on the missing helper.
- [ ] **Step 3: Implement.** `_with_swapped_in` as above. `swap_score` keeps `t_b` and `best_damage(b)` outside, and computes `threat(c)`, `best_damage(c)` and `enter_value(engine, b, c, style, ref)` inside one `_with_swapped_in` call (return them in an array). `enter_value` uses the passed `ref` when not negative.
- [ ] **Step 4: Run** the AI suites (`test_ai_swaps` and `test_ai_styles` included). Expected: PASS; a swap test that fixed its expectation on the old blind estimate is updated only if its fixture has a bench passive or aura (none should).
- [ ] **Step 5: Measure** as in Task 2 Step 5 and record the swap rate change.

### Task 4: Expected threat

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`threat`, `_share`)
- Test: `tests/battle/test_ai_accuracy.gd` (extend)

**Interfaces:**
- Produces: `_share(m: MoveDef, n: int) -> float` (1 for `all_enemies` and `all`, `min(2, n) / n` for `two_enemies`, `1 / n` otherwise; `n` at least 1).

- [ ] **Step 1: Write the failing tests:**
  - `test_share_by_move_target`: `_share` for `one_enemy`, `two_enemies` and `all_enemies` moves at n = 1, 2 and 3 equals 1, 1/2, 1/3; 1, 1, 2/3; 1, 1, 1.
  - `test_threat_halves_a_single_target_move_in_2v2_and_not_in_1v1`: a 2v2 (two foes with only a single-target move): `threat(x)` equals half of what the same foes give at n = 1 (compare against the sum of `estimate_damage`); in 1v1 `threat(x)` equals the plain sum.
  - `test_threat_counts_a_spread_move_in_full`: foes with `wave` (`all_enemies`) give the full estimate at n = 2.
  - `test_a_one_shot_lead_is_no_longer_flagged_doomed_by_one_of_two_foes`: a 2v2 lead whose HP equals one foe move's damage: at n = 2 the swap's knockout bonus is absent where it was present at n = 1 (compare the 1v1 and 2v2 fixtures).
- [ ] **Step 2: Run.** Expected: FAIL (`_share` missing, `threat` unchanged).
- [ ] **Step 3: Implement** `_share` and the change in `threat`: for each foe, `best` is the maximum over usable damaging moves of `estimate_damage(...) * _share(m, mine)`, where `mine` is the number of active creatures on `x`'s side (at least 1).
- [ ] **Step 4: Run** the AI suites. Expected: PASS; update an existing 2v2 swap test only if its expectation was the old worst-case threat, and record each in the ledger.
- [ ] **Step 5: Measure** as above.

### Task 5: Verification, docs, check

**Files:**
- Modify: `documentation/battle-engine.md` ("AI styles" swapping paragraph, "Passives and the AI" retaliation text, Testing table), `.superpowers/HANDOFF.md`, `.superpowers/2026-11-12-minors-and-docs-audit.md`

- [ ] **Step 1: Run the target matrix.** For 2v2, 200 battles, seed 1, both orders, levels 10 and 40: each of `passive`, `defensive` and `trickster` against `tactician` (12 runs; run them in the background and wait for completion, about a quarter of an hour). Record win shares, draws and rounds. Check the three M6g targets. If one is missed, tune `KO_FACTOR` (record each change as a ruling) and re-run; stop after three rounds and report what is still missed.
- [ ] **Step 2: Docs.** `battle-engine.md`: the knockout bonus is `KO_FACTOR` x `ref`; the swap paragraph drops the "benched creature's passive is missing" caveat and says the evaluation is done with the bench creature in the slot; expected threat; retaliation through `trigger_value` (and what it now covers); the Testing table row for `test_ai_accuracy.gd` (the drift test requires it). HANDOFF: an M6h entry in "State of the milestones" with the measured effects, rulings and what is left; the audit file's progress section and the group C items that are now done.
- [ ] **Step 3: Final run.** `bash scripts/check.sh`. Expected: "All checks passed." (If the seeded pack simulation shifts, handle the exemption lists as in M6e and M6g and ledger it.)
