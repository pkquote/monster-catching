# Species Stat Growth Rates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each species a `slow` / `steady` / `fast` growth tier per stat that scales the level slope of its stats, show it on the Summary and in the compendium, and warn when a species is over its tier budget.

**Architecture:** Tiers live in `balance.json` (`growth_tiers`, `growth_budget`); species opt in with `growth_rates`. `Stats` formulas take an integer percent rate (default 100, which reproduces today's numbers exactly); `CreatureInstance.grown` looks the percent up from the species. Validation errors fail the build; the budget check is a separate warnings list that the loader and `validate_data.gd` print.

**Tech Stack:** Godot 4.7 GDScript, gdUnit4, JSON content. Run everything with `bash scripts/check.sh` (must end "All checks passed."). Never run two Godot processes at once.

**Spec:** [documentation/specs/2026-11-04-stat-growth-rates-design.md](../specs/2026-11-04-stat-growth-rates-design.md)

## Global Constraints

- **Never commit, stage or stash.** Leave changes in the working tree; the final message offers a commit message in the project's format.
- Tiers: `slow` 0.8, `steady` 1.0, `fast` 1.2. `growth_budget` is 2. `steady` must exist and equal exactly `1.0`.
- Formulas (integer division): `stat_at = (2·base·pct·level)/10000 + 5`; `hp_at = (2·base·pct·level)/10000 + level + 10`; `energy_at = (2·base_stamina·pct·level)/10000 + flat`. `pct = roundi(multiplier·100)`.
- Lv 99 values: base 50 gives slow 84, steady 104, fast 123; base 100 gives slow 163, steady 203, fast 242.
- The 8 shipped species stay all-`steady`; every shipped creature's stats must be unchanged.
- `growth_rates` keys are any of `DataSchemas.BASE_STATS` (`hp`, `patk`, `pdef`, `satk`, `sdef`, `spd`, `luck`, `resolve`, `stamina`). Do not confuse it with the existing `growth` field (evolution branches).
- New tests extend `GdUnitTestSuite` and follow the surrounding suites' helpers (`FixtureDB`, `WorldTest`, `ScreenFit`).

## Review Focus

1. A tier name in a species' `growth_rates` that is not in `growth_tiers` (a typo like `"fats"`) must fail validation, not silently fall back to `steady`. Pinned in Task 1.
2. `growth_tiers` missing `steady`, or with `steady` ≠ 1.0, must fail validation. Pinned in Task 1.
3. A species whose tiers shrink its stats (newly `slow`) must not load with HP or energy above the new maximum. Pinned in Task 3.
4. A tier multiplier such as `1.1` or `0.8` must give the exact percent (110, 80) despite float representation. Pinned in Task 1.
5. The Summary with every stat trained and marked `▲`/`▼` must still fit three cells per row without scrolling. Pinned in Task 4.

---

### Task 1: Data, defs and validation errors

**Files:**
- Modify: `data/balance.json`, `tests/helpers/fixture_db.gd` (`FixtureDB.balance()`), `core/data/schemas.gd` (balance and creatures entries), `core/data/validator.gd` (`_check_cross_rules`), `core/data/defs/balance_def.gd`, `core/data/defs/creature_def.gd`
- Test: `tests/data/test_validator.gd`, `tests/progress/test_growth_rates.gd` (new)

**Interfaces:**
- Produces: `BalanceDef.growth_tiers: Dictionary` (tier id → float), `BalanceDef.growth_budget: int`, `BalanceDef.growth_percent(tier: String) -> int`; `CreatureDef.growth_rates: Dictionary` (stat → tier id), `CreatureDef.growth_tier(stat: String) -> String` (`"steady"` when unlisted).

- [ ] **Step 1: Write failing tests.** In `tests/data/test_validator.gd`, using `_base()`/`_creature()`/`_errors_for`:
  - `test_unknown_growth_tier_fails`: creature with `"growth_rates": {"patk": "fats"}`; errors contain `[creatures:pup]` and `fats`.
  - `test_unknown_growth_stat_fails`: `"growth_rates": {"speed": "fast"}` (not a stat key) fails.
  - `test_valid_growth_rates_pass`: `{"patk": "fast", "spd": "slow"}` gives no errors.
  - `test_steady_tier_must_exist_and_be_one`: replace `growth_tiers` in the balance single with `{"slow": 0.8, "fast": 1.2}` (no steady), then with `{"slow": 0.8, "steady": 1.1, "fast": 1.2}`; each yields an error mentioning `steady`.
  In `tests/progress/test_growth_rates.gd` (new, `before()` builds `db := FixtureDB.build()`):
  - `test_growth_percent_is_exact`: with tiers `{"slow": 0.8, "steady": 1.0, "fast": 1.2, "odd": 1.1}` assert `growth_percent` is 80, 100, 120, 110.
  - `test_growth_tier_defaults_to_steady`: a def built from a dict with `growth_rates {"spd":"fast"}` returns `"fast"` for `spd` and `"steady"` for `patk`.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect these tests to fail (the existing suites still pass until the schema changes).
- [ ] **Step 3: Implement.**
  - `data/balance.json` and `FixtureDB.balance()`: add `"growth_tiers": {"slow": 0.8, "steady": 1.0, "fast": 1.2}` and `"growth_budget": 2`.
  - `schemas.gd` balance entry: `growth_tiers` as a `map` (key `{"t": "id"}`, value `{"t": "number", "min": 0.1, "max": 3.0}`), `growth_budget` as `{"t": "int", "min": 0, "max": 9}`. Creatures entry: optional `growth_rates` as a `map` whose key is `{"t": "enum", "values": BASE_STATS}` and value `{"t": "id"}`.
  - `validator.gd` `_check_cross_rules`: (a) balance: `growth_tiers` must have `steady` equal to `1.0` (use the `balance` single's `_file`/label as `_check_single` does); (b) each creature's `growth_rates` values must be keys of the balance `growth_tiers`, error path `growth_rates.<stat>`.
  - `BalanceDef`: fields above; `from_dict` copies `growth_tiers` (as floats) and `growth_budget`; `growth_percent(tier)` is `roundi(float(growth_tiers[tier]) * 100.0)`.
  - `CreatureDef`: `growth_rates` from `d.get("growth_rates", {})`; `growth_tier(stat)` returns `growth_rates.get(stat, "steady")`.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed." (including the real-data validity test).

### Task 2: Tier budget warnings

**Files:**
- Modify: `core/data/validator.gd`, `core/data/data_loader.gd` (`LoadResult`, `load_database`), `tools/validate_data.gd`
- Test: `tests/data/test_validator.gd`, `tests/data/test_data_loader.gd`

**Interfaces:**
- Consumes: Task 1's `growth_tiers`, `growth_budget`, `growth_rates` (read from raw data).
- Produces: `static func DataValidator.warnings(raw: RawData) -> PackedStringArray`; `DataLoader.LoadResult.warnings: PackedStringArray` (filled on every `load_database` that reaches validation).

- [ ] **Step 1: Write failing tests.**
  - In `test_validator.gd`: `test_over_budget_species_warns_without_failing`: creature with `growth_rates` of three `fast` stats (sum 3 > budget 2): `DataValidator.validate` returns no errors, `DataValidator.warnings` has exactly one entry containing `[creatures:pup]` and `3`. `test_slow_stats_offset_fast_ones`: three `fast` and one `slow` (sum 2) gives no warning. `test_budget_counts_position_relative_to_steady`: with tiers `{"slow":0.8,"steady":1.0,"fast":1.2,"turbo":1.5}`, one `turbo` and one `fast` and one more `fast` (sum 3) warns; `turbo` counts +1, not +2.
  - In `test_data_loader.gd`: `test_shipped_content_has_no_warnings`: `DataLoader.load_database(...)` result `warnings` is empty.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail (missing function).
- [ ] **Step 3: Implement** `DataValidator.warnings(raw)`: for each creature, sum `+1` per rate whose tier multiplier is above `1.0`, `-1` below; when the sum exceeds `growth_budget` add `"<file> [creatures:<id>]: growth tiers sum to <n> (budget <m>)"`, using the same file label format as errors. `load_database` fills `result.warnings` from it after validation succeeds. `validate_data.gd` prints each warning with `print` (so it is not an error) before the OK line; the exit code is unchanged. Confirm `scripts/check.sh`'s existing `grep -E "Data OK|^res://|^data/|failed"` shows them (the message starts with the `data/...` file path); adjust nothing if so.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed." Then temporarily give a shipped species three `fast` tiers, run `godot --headless --path . --script res://tools/validate_data.gd` and confirm the warning prints and the exit code is 0, then revert the edit.

### Task 3: Formulas, `grown()` and clamping

**Files:**
- Modify: `core/progress/stats.gd`, `core/progress/creature_instance.gd` (`grown`, `clamp_to_cap`)
- Test: `tests/progress/test_growth_rates.gd`, `tests/progress/test_progression.gd`

**Interfaces:**
- Consumes: `BalanceDef.growth_percent`, `CreatureDef.growth_tier` (Task 1).
- Produces: `Stats.hp_at(base, level, pct := 100)`, `Stats.stat_at(base, level, pct := 100)`, `Stats.energy_at(base_stamina, level, flat, pct := 100)`; `CreatureInstance.grown` applies the species tier; `clamp_to_cap` also clamps HP and energy to the current maximums even when the level is within the cap.

- [ ] **Step 1: Write failing tests** in `tests/progress/test_growth_rates.gd` (a `before()` db with a species `"blob"` from `FixtureDB`; set `db.creature("blob").growth_rates` directly in each test and restore afterwards):
  - `test_steady_matches_the_old_formulas`: for bases 1, 37, 50, 100, 255 and levels 1, 2, 17, 50, 99, `Stats.stat_at(b, l, 100)`, `hp_at(b, l, 100)` and `energy_at(b, l, 20, 100)` equal `(2*b*l)/100 + 5`, `(2*b*l)/100 + l + 10` and `(2*b*l)/100 + 20`.
  - `test_tier_table_at_level_99`: `stat_at(50, 99, 80) == 84`, `(50, 99, 100) == 104`, `(50, 99, 120) == 123`, `(100, 99, 80) == 163`, `(100, 99, 120) == 242`; `hp_at(50, 99, 120) == 2*50*120*99/10000 + 99 + 10`; `energy_at(50, 99, 20, 120) == 118 + 20`.
  - `test_grown_uses_the_species_tier`: with `blob` rates `{"patk": "fast", "hp": "slow", "stamina": "fast"}`, `grown` for those three matches `Stats` with 120/80/120 percent and an unlisted stat matches 100; `grown + training` still equals `max_hp`, `max_energy` and `stat`.
  - `test_every_shipped_creature_is_unchanged`: load the real db (`DataLoader.load_database("res://data", "res://dialogue").db`); for every creature, levels 1, 10, 50, 99 and all nine stats, `CreatureInstance.create(...).grown(db, stat)` equals the old formula from the species base stat.
  - `test_clamp_pulls_hp_and_energy_down_after_a_tier_shrinks_stats`: a level-50 `blob` at full HP and energy, then set its species `growth_rates` to slow for `hp` and `stamina`; after `clamp_to_cap(db)` its `hp` and `energy` do not exceed `max_hp` and `max_energy`.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement** the three `Stats` signatures (integer maths as in Global Constraints); `grown` passes `db.balance.growth_percent(species_def(db).growth_tier(stat_name))`; `clamp_to_cap` keeps its level/XP handling but always finishes with `hp = mini(hp, max_hp(db))` and `energy = mini(energy, max_energy(db))`. `GameState.load_from` already calls it.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 4: Summary markers

**Files:**
- Modify: `game/progress/summary_screen.gd` (`_render_stats`)
- Test: `tests/world/test_summary_screen.gd`

**Interfaces:**
- Consumes: `CreatureDef.growth_tier(stat)` (Task 1), `grown` (Task 3).

- [ ] **Step 1: Write failing tests** (each sets `DataRegistry.db.creature("tidepup").growth_rates` and restores it to `{}` at the end of the test and in `after_test()`):
  - `test_stats_tab_marks_fast_and_slow_stats`: tidepup Lv 10 with `{"spd": "fast", "pdef": "slow"}`; the page text contains `"Speed %d▲"` and `"Physical Defense %d▼"` with the creature's totals, and a `steady` stat (Luck) has no marker.
  - `test_marker_comes_before_the_training_split`: add 3 training to `spd`; the text contains `"Speed %d▲ (%d+3)"` using `grown` and the total.
  - `test_stats_tab_fits_with_every_stat_trained_and_marked`: tidepup Lv 99, every `TRAINABLE_STATS` entry trained to 30, `growth_rates` alternating `fast`/`slow` across all nine stats; `ScreenFit.check(self, s)` passes.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement** in `_render_stats`: after the total, append `▲` for `fast` (multiplier above 1.0) or `▼` for `slow` (below), glued to the number (`"Speed 124▲"`), before any `(growth+trained)` part. If the real window shows the glyph as a missing-character box (check in Task 5), use `^` and `v` instead and update the tests.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 5: Compendium, docs and end-to-end check

**Files:**
- Modify: `tools/generate_compendium.gd`, `documentation/specs/2026-11-04-stat-growth-rates-design.md` (Status), `documentation/specs/2026-11-03-monster-rpg-design.md` (§2.7), `documentation/battle-engine.md` (stat formulas), `.superpowers/HANDOFF.md`
- Test: run-based (no suite; the compendium is generated)

**Interfaces:**
- Consumes: `CreatureDef.growth_rates`/`growth_tier`, `BalanceDef.growth_percent`, `Stats` percent signatures.

- [ ] **Step 1: Implement** in `generate_compendium.gd`: for each creature add a "Growth:" bullet listing only non-`steady` tiers (`P.Atk fast, Spd slow`), omitted when none; add a "Lv 99 stats" bullet with the nine growth values (via `Stats` with the species' percents, no training) and their six-stat total in the same style as the base-stat total column.
- [ ] **Step 2: Verify the compendium:** temporarily set a shipped species' `growth_rates` to `{"patk": "fast", "spd": "slow"}`, run `godot --headless --path . --script res://tools/generate_compendium.gd`, and confirm `documentation/compendium.md` shows the Growth bullet and Lv 99 values for that species only (every other species shows no Growth bullet); revert the data edit and regenerate.
- [ ] **Step 3: Verify the real window:** with the same temporary species edit still applied (tidepup is the Summary tour's creature), run the progress tour from the `run-godot-monster-catching-game` skill, view `p10_summary_stats.png` to confirm the markers render as glyphs and the page fits; then revert the data edit.
- [ ] **Step 4: Docs.** Spec Status becomes `Implemented (plan: …)`. In the main spec §2.7 and `battle-engine.md`, replace the stat formulas with the percent versions and add one line on tiers. In `HANDOFF.md`, replace the "Stat growth (in progress)" section with what shipped, and list marking the shipped species with tiers as the follow-up content pass.
- [ ] **Step 5:** Run `bash scripts/check.sh` with all temporary edits reverted; expect "All checks passed.", `git status` showing no change to `data/creatures/`, and the compendium unchanged apart from the new Lv 99 lines. Then give the user the commit message.
