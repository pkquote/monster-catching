# AI Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI styles data: a new `ai_styles` content category (`data/ai_styles.json`) holding weight profiles that the existing scoring reads. `basic`, `aggressive` and `tactician` become entries that behave exactly as today, `basic` is the default for a tamer with no `ai`, and three new entries are added: `passive` (easier: heals, buffs and Rest first, else its weakest hit), `defensive` (survival and swapping) and `trickster` (statuses, debuffs, field setup).

**Architecture:** Task 1 adds the category (schema, `AiStyleDef`, `Database` accessor, JSON with the three existing styles, compendium section, fixtures, optional tamer `ai`). Task 2 replaces every style-name comparison in `BattleAI` with reads of `engine.db.ai_style(id)`, proven behavior-identical. Tasks 3 and 4 add the new styles (a buff term and a weakest-hit mode, then rows). Task 5 wires the test pack, tools and docs.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4, JSON data. Checks: `bash scripts/check.sh`.

**Spec:** [documentation/specs/2026-11-12-m6g-ai-styles-design.md](../specs/2026-11-12-m6g-ai-styles-design.md)

**Commits:** the user writes every commit in this project. Do not `git commit`, stage or stash; each task ends with its test run, and the final message gives a suggested commit message.

**One suite:** run a single test file with
`"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<path>.gd --ignoreHeadlessMode -c`
where `GODOT` is the console exe named in `scripts/check.sh`. Below this is written `RUN <path>`. The simulator is `"$GODOT" --headless --path . -s tools/simulate.gd -- --battles=200 --seed=1 --format=2v2 --level=L --ai=A,B`.

## Global Constraints

- `basic`, `aggressive` and `tactician` choose exactly as before. Proof: every existing AI suite passes unchanged, and the simulator output (first line excluded) is byte-identical to the baseline of Task 1 Step 1 for the four baseline runs.
- Category: `ai_styles` is a `"file"` category (`data/ai_styles.json`, `{schema, entries}`), entries `{id, name, description (optional), ...fields}`. Fields, all required: `random` bool; `damage`, `ko`, `retaliation`, `setup`, `buff`, `heal`, `rest`, `trigger_setup`, `swap_margin`, `swap_avoid` numbers 0 to 3; `seeks_status` bool; `attack` enum `best` | `weakest`; `swap` bool.
- Entry values (the spec's table; the three existing styles are exact, the new ones are first values tuned only with the simulator, every change is reported):

| Field | basic | aggressive | tactician | passive | defensive | trickster |
|---|---|---|---|---|---|---|
| random | true | false | false | false | false | false |
| damage | 1.0 | 1.0 | 1.0 | 1.0 | 0.7 | 0.6 |
| ko | 1.0 | 1.0 | 1.0 | 0.0 | 1.0 | 1.0 |
| retaliation | 1.0 | 0.0 | 1.0 | 1.0 | 1.5 | 1.0 |
| setup | 1.0 | 0.0 | 1.0 | 1.0 | 0.5 | 1.5 |
| buff | 0.0 | 0.0 | 0.0 | 1.0 | 0.5 | 0.5 |
| heal | 1.0 | 1.0 | 1.0 | 1.5 | 1.5 | 1.0 |
| rest | 1.0 | 1.0 | 1.0 | 2.0 | 1.5 | 1.0 |
| trigger_setup | 1.0 | 0.5 | 1.0 | 1.0 | 1.0 | 1.0 |
| seeks_status | true | false | true | true | true | true |
| attack | best | best | best | weakest | best | best |
| swap | false | false | true | false | true | false |
| swap_margin | 0.25 | 0.25 | 0.25 | 0.25 | 0.1 | 0.25 |
| swap_avoid | 1.0 | 1.0 | 1.0 | 1.0 | 1.5 | 1.0 |

- Tamers: `ai` becomes `{"t": "ref", "cat": "ai_styles", "opt": true}`; `TamerDef.ai` is `"basic"` when absent. A side the caller controls keeps `ai == ""` and never reaches `BattleAI`. Existing tamer data is not edited. The launcher keeps `basic` for wild and `tactician` for Sparring Partner.
- An unknown style id in `BattleAI` asserts (via `engine.db.ai_style(id)` returning null). `tools/simulate.gd` rejects an unknown `--ai=` name.
- New constant in `BattleAI`: `WEAK_ATTACK_BAND := 0.5` (HP-equivalent units, the score range of attacks for `attack == "weakest"`).
- Scoring never draws from `engine.rng`.
- The simulator targets (spec section 5): `passive` wins at most 40% against `tactician`; `defensive` and `trickster` each win 35% to 65% against `tactician`; no style draws more than 2% of its battles. A missed target is tuned by number (a JSON edit) and reported, not relaxed.

## Review Focus

- A `passive` side whose every non-attack option is worth 0 (a status on an already-statused foe, a heal at full HP): it must still attack (weakest hit), not sit on a pointless move.
- `passive` against a foe it could knock out with its weakest move: it does not chase the knockout (`ko` 0), but a lethal weakest hit still lands if it is the only damaging option; no crash.
- `passive` at low energy with Rest available and a heal available: the higher-weighted one wins, and Rest still only appears under `LOW_ENERGY`.
- A `passive` heal move at full HP is worth 0, not negative.
- `defensive` with no bench or with a claimed bench creature: unchanged from the tactician's guards (`acted`, `claimed`).
- `trickster` with a status move into a foe that already has a status or blocks it: the value is 0, so a hit wins.
- A database built without the `ai_styles` category (a hand-built `RawData` in a test) fails with a clear assertion, not a null-reference crash.
- A tamer with no `ai`, a tamer naming an unknown style, and a fixture battle side with `ai == ""`.
- `basic` draws exactly the same RNG as before.

---

### Task 1: The `ai_styles` data category (existing three styles)

**Files:**
- Create: `core/data/defs/ai_style_def.gd`, `data/ai_styles.json`, `tests/data/test_ai_styles_data.gd`
- Modify: `core/data/schemas.gd` (category, schema, tamer `ai`), `core/data/database.gd` (builder, accessor), `core/data/defs/tamer_def.gd` (default), `tools/compendium_builder.gd` (section), `tests/helpers/fixture_db.gd` (`raw()` adds the shipped entries), any test whose hand-built `RawData` includes tamers (`tests/data/test_validator.gd`) if it now misses `ai_styles`

**Interfaces:**
- Produces: `AiStyleDef` with `id`, `name`, `description` and the fourteen fields as typed vars named as in Global Constraints (`random`, `damage`, ... `swap_avoid`; `attack` a String); `Database.ai_style(id: String) -> AiStyleDef` (null when absent); `TamerDef.ai` defaulting to `"basic"`.

- [ ] **Step 1: Capture the baseline.** Before editing any code, run four simulator commands (2v2, 200 battles, seed 1: `--ai=tactician,aggressive`, `--ai=aggressive,tactician` and `--ai=basic,tactician` at level 10, and `--ai=tactician,aggressive` at level 40) and save each output without its first line to the scratchpad directory as `m6g_base_<n>.txt`. Expected: four files, no `SCRIPT ERROR`.
- [ ] **Step 2: Write the failing tests** in `tests/data/test_ai_styles_data.gd`:
  - `test_shipped_styles_validate`: loading the real data (`DataLoader`, as the other data tests do) gives no validation errors.
  - `test_the_three_existing_styles_match_the_table`: `ai_style("basic")`, `("aggressive")`, `("tactician")` equal the Global Constraints values, field by field (table-driven).
  - `test_ai_style_is_a_def_and_unknown_is_null`: `ai_style("tactician")` is an `AiStyleDef`; `ai_style("nope")` is null.
  - `test_validator_rejects_bad_entries`: a hand-built `RawData` with a style missing a field, with `damage` 4.0, and with `attack` "sideways" each yield an error naming the field.
  - `test_tamer_ai_is_a_reference`: a tamer whose `ai` is `"nope"` is rejected (`unknown ai_styles id 'nope'`); a tamer without `ai` validates and loads with `ai == "basic"`.
- [ ] **Step 3: Run** `RUN data/test_ai_styles_data`. Expected: FAIL (category and def missing).
- [ ] **Step 4: Implement.** Add `"ai_styles": "file"` to `CATEGORIES` and its schema (the field table above; `id`, `name`, `description` optional). Add `AiStyleDef.from_dict`. Register it in `Database._builders` and add `ai_style(id)`. Write `data/ai_styles.json` with the three existing entries (names "Basic", "Aggressive", "Tactician"; one-line descriptions). Change the tamer schema's `ai` as in Global Constraints and default `TamerDef.ai` to `"basic"`. Add a compendium section "AI Styles" (a table of id, name and the weights) following `_statuses()`. `FixtureDB.raw()` reads `data/ai_styles.json` and adds its entries (one helper in `FixtureDB`, so tests run on the real weights). Fix any test that hand-builds a tamer and now needs the entries.
- [ ] **Step 5: Run** `RUN data/test_ai_styles_data`, then `bash scripts/check.sh`. Expected: PASS ("All checks passed."; the compendium is regenerated).
- [ ] **Step 6: Re-run the four baseline simulator commands** and diff against the baseline. Expected: identical (nothing reads the category yet).

### Task 2: Read the profile instead of the style name (behavior-preserving)

**Files:**
- Modify: `core/battle/ai/battle_ai.gd`
- Test: `tests/battle/test_ai_styles.gd` (new)

**Interfaces:**
- Consumes: `engine.db.ai_style(id) -> AiStyleDef` from Task 1.
- Produces: `static func profile(engine: BattleEngine, style: String) -> AiStyleDef` (asserts when the id is unknown, naming it); `rest_score(engine, b, style := "tactician") -> float` (times `rest`); `swap_score` and `_best_swap` take the real style; `choose` reads `swap` and `swap_margin`.

- [ ] **Step 1: Write the failing tests** in `tests/battle/test_ai_styles.gd` (engine from `FixtureDB.engine`, fixtures as in `test_ai_swaps.gd`):
  - `test_profile_resolves_each_style`: `profile(e, id)` returns the entry for the three ids.
  - `test_rest_score_scales_with_the_rest_weight`: `rest_score(e, b, "tactician")` equals `rest_score(e, b)`; after setting `db.ai_style("tactician").rest = 2.0` in the test (restore it after) it doubles.
  - `test_swap_avoid_scales_the_damage_avoided_term`: with `swap_avoid` set to 2.0 on a copy used for the style (set on the tactician def and restore), a doomed-lead `swap_score` rises by exactly the damage-avoided term (`min(t_b, hp_b) - min(t_c, hp_c)` plus the knockout bonus).
  - `test_heal_weight_scales_a_heal_move`: setting `heal` 2.0 doubles the heal part of a heal move's score.
  - `test_unknown_style_asserts`: skip if GdUnit cannot assert-catch; otherwise `profile(e, "nope")` fails with the id in the message.
- [ ] **Step 2: Run** `RUN battle/test_ai_styles`. Expected: FAIL (`profile` missing).
- [ ] **Step 3: Implement** `profile` and replace every style-name comparison in `battle_ai.gd` by a profile read, keeping the arithmetic identical:
  - `choose`: `random` replaces `style == "basic"` (every place); a swap is considered when `swap` and `b.acted`, with `swap_margin * ref`.
  - `score`: damage landed (foe and ally branches) times `damage`; `KO_BONUS` and `_kill_triggers_value` times `ko`; retaliation times `retaliation` (charged when the weight is not 0); the heal value times `heal`; `_setup_value` times `setup` (skipped at 0); the status-trigger term applies when not `random`.
  - `_style_weight` returns `trigger_setup` for setup ops and 1.0 for `damage` and `heal`; `_status_trigger_value` caps at 0 when `seeks_status` is false.
  - `swap_score(engine, b, c, style, ref)`: the damage-avoided part (including its knockout bonus) times `swap_avoid`; `_best_swap` passes the style through.
  - `rest_score` takes `style` and multiplies by `rest`; `choose` passes the style.
  - Delete `AGGRESSIVE_SETUP_MULT` if no test still reads it; if a test does, keep it and leave a comment that the data value is authoritative.
- [ ] **Step 4: Run** `RUN battle/test_ai_styles` and every AI suite: `RUN battle/test_ai`, `test_ai_passives`, `test_ai_cure`, `test_ai_multi_hit`, `test_ai_triggers`, `test_ai_swaps`. Expected: PASS, no existing test edited.
- [ ] **Step 5: Prove no drift.** Re-run the four baseline simulator commands and diff. Expected: identical. Any difference is a regression (a weight applied where the old code applied none): find it and fix it first.

### Task 3: Own buffs and the `passive` style

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_buff_value`, the `weakest` mode, `WEAK_ATTACK_BAND`), `data/ai_styles.json` (the `passive` entry)
- Test: `tests/battle/test_ai_styles.gd` (extend)

**Interfaces:**
- Consumes: `profile`, `score`, `choose`, `rest_score` from Task 2.
- Produces: `static func _buff_value(engine, b, m, targets, ref) -> float` (each `stat_stage` effect with positive stages landing on the user or an ally: `DEBUFF_VALUE[stat] x ref x stages` per creature, 0 for a creature already at `STAGE_MAX`); the `passive` entry.

Fixtures: a self buff (`stat_stage`, `patk`, 1 stage, target `self`), a weak hit (power 20), a strong hit (power 90), and a status move into an already-statused foe.

- [ ] **Step 1: Write the failing tests:**
  - `test_buff_value_is_zero_for_the_existing_styles`: the self-buff scores 0 for `tactician` and `aggressive`.
  - `test_buff_value_for_passive`: the same move scores `DEBUFF_VALUE.patk * ref` (within 0.001) for `passive`; 0 at `STAGE_MAX`.
  - `test_passive_prefers_a_buff_to_any_attack`: knows the buff, a weak and a strong hit; `choose` returns the buff.
  - `test_passive_heals_below_half`: a creature at 30% HP with a heal move picks it over attacks and a buff.
  - `test_passive_attacks_weakly_when_nothing_else`: knows only a weak and a strong hit; returns the weak one, and not the knockout when the strong hit would finish the foe.
  - `test_passive_takes_a_hit_over_a_pointless_move`: a status into an already-statused foe (value 0) and a weak hit: the hit.
  - `test_heal_at_full_hp_is_not_rewarded`: a heal move at full HP does not beat a weak hit for `passive`.
  - `test_passive_prefers_rest_at_low_energy`: at `LOW_ENERGY` with only attacks, Rest wins; `rest_score` for `passive` is twice the tactician's.
  - `test_passive_never_swaps`: a doomed lead with a healthy bench returns a move.
  - `test_passive_scoring_draws_no_rng`: `rng.state` unchanged over a `choose`.
  - extend `test_the_three_existing_styles_match_the_table` in `test_ai_styles_data.gd` with `passive`'s row.
- [ ] **Step 2: Run** `RUN battle/test_ai_styles` and `RUN data/test_ai_styles_data`. Expected: new tests FAIL.
- [ ] **Step 3: Implement.** `_buff_value` called from `score` as `buff * _buff_value(...)` (skipped at 0). For `attack == "weakest"`, the damaging foe branch of `score` contributes `WEAK_ATTACK_BAND * (1.0 - 0.5 * min(1, est / max(ref, 1.0))) / targets.size()` instead of the landed-damage credit (a range of 0.25 to 0.5, so the strongest attack still beats a pointless 0 move), with no `KO_BONUS`, and retaliation still subtracts. Add the `passive` entry to `data/ai_styles.json` with the Global Constraints values.
- [ ] **Step 4: Run** the suites above and the six AI suites. Expected: PASS.
- [ ] **Step 5: Re-run the four baseline simulator commands.** Expected: still identical to the baseline.

### Task 4: `defensive` and `trickster`

**Files:**
- Modify: `data/ai_styles.json` (two entries)
- Test: `tests/battle/test_ai_styles.gd`, `tests/data/test_ai_styles_data.gd` (extend)

**Interfaces:**
- Consumes: every profile field already read in Task 2.
- Produces: the `defensive` and `trickster` entries.

- [ ] **Step 1: Write the failing tests:**
  - `test_defensive_heals_at_a_higher_hp_than_the_tactician`: sweep the creature's HP down from full in 5% steps; the first HP at which each style prefers a heal move over a mid-power hit is strictly higher for `defensive`.
  - `test_defensive_takes_a_swap_the_tactician_declines`: from the margin sweep of `test_ai_swaps.gd`, a case with a gap over 0.1 x `ref` and at most 0.25 x `ref`: `choose` returns a swap for `defensive` and a move for `tactician`.
  - `test_defensive_values_damage_avoided_more`: `swap_score(..., "defensive", ...)` exceeds the tactician's in a doomed-lead fixture by exactly the extra 0.5 of the damage-avoided term.
  - `test_defensive_charges_more_retaliation`: against a foe with a `hit` retaliation trigger, a non-lethal hit scores lower for `defensive` than for `tactician`.
  - `test_trickster_prefers_a_status_to_an_equal_hit`: a status move and a hit of equal tactician score: `trickster` picks the status; `tactician` is unchanged.
  - `test_trickster_still_takes_a_knockout`: a finishing hit against a status move: the hit.
  - `test_trickster_ignores_a_blocked_status`: a status into a foe that already has one or blocks it adds 0; a hit wins.
  - extend the data test with the two rows.
- [ ] **Step 2: Run** both suites. Expected: new tests FAIL (entries missing).
- [ ] **Step 3: Add the two entries** to `data/ai_styles.json` with the Global Constraints values. No code change.
- [ ] **Step 4: Run** both suites and the six AI suites. Expected: PASS. If a behavior test fails because a first value is wrong (for example `defensive` never heals earlier), change the number in the JSON (and the table in the data test and the spec), not the behavior test, and ledger it as a ruling.
- [ ] **Step 5: Re-run the four baseline simulator commands.** Expected: still identical.

### Task 5: Test pack, tools, simulator targets, docs

**Files:**
- Modify: `tools/simulate.gd` (help comment; reject an unknown `--ai=` name using `ai_style`), `core/battle/side_setup.gd` (comment), `data_testpack/tamers/tp_tamers.json` (four tamers), `tests/battle/test_testpack_simulations.gd` (`AIS` and, if the seeded run shifts, `EXEMPT_TRIGGERS` and its comment), `tests/data/test_testpack_tamers_encounters.gd` (only if a count assertion breaks), `documentation/battle-engine.md`, `documentation/developer-guide.md` (where data categories are listed), `.superpowers/HANDOFF.md`

- [ ] **Step 1: Add the tamers** `tp_tamer_passive_2v2`, `tp_tamer_defensive_2v2`, `tp_tamer_trickster_2v2` (each `max_active` 2, with the party, items and reward of `tp_tamer_tactician_2v2` and its own `ai`) and `tp_tamer_default_ai_1v1` (a copy of the basic 1v1 tamer with no `ai` field). Set `AIS` in `test_testpack_simulations.gd` to the six ids and update its header comment. In `tools/simulate.gd`, reject an unknown `--ai=` name with a message listing the ids from the database.
- [ ] **Step 2: Write the failing test** `test_a_tamer_without_ai_uses_basic` in `tests/data/test_testpack_tamers_encounters.gd` (the pack's default-AI tamer loads with `ai == "basic"`). Run it before Step 1's tamer exists; Expected: FAIL, then PASS after.
- [ ] **Step 3: Run** `bash scripts/check.sh`. Expected: PASS. Known follow-ups: the pack simulation's seeded runs shift (as in M6e), so a trigger-coverage exemption may need adding or become unused (ledger it as a ruling and change `EXEMPT_TRIGGERS` as M6e did); a count assertion over all tamers must be updated by the four new ones.
- [ ] **Step 4: Simulator targets.** For 2v2 at levels 10 and 40, 200 battles, seed 1, run each new style against `tactician` and against `basic` (both orders). Record win shares, draws and average rounds in the ledger. Check the three targets in Global Constraints. If one is missed, tune the numbers in that style's JSON entry (record each change as a ruling, and keep the spec table and the data test in step) and re-run; stop after three rounds and report what is still missed.
- [ ] **Step 5: Docs.** `documentation/battle-engine.md`: "AI styles" gets the profile table (all fields, all six entries), the three new styles' descriptions, the weakest-hit rule, the default-style rule and the note that styles are data in `data/ai_styles.json`; the test table gains `test_ai_styles.gd` and `test_ai_styles_data.gd`. `documentation/developer-guide.md`: `ai_styles` in the category list and a line on adding a style. `.superpowers/HANDOFF.md`: an M6g entry with rulings, simulator results and deferred minors; "What's next" says the M6 engine items are done except the passives minors and asks the user.
- [ ] **Step 6: Final run.** `bash scripts/check.sh`. Expected: "All checks passed."
