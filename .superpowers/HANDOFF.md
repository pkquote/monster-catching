# Handoff: godot-monster-catching-game

Date: 2026-11-13. Branch: `milestone/M6`. Last commit: `6ea9988` ("Make the AI's knockout, swap and retaliation numbers hold at every level and format (M6)").
Everything through M6h (the AI accuracy pass) is committed. The working tree holds only a pinning test for
friendly-fire knockout credit (not a bug: see the audit) and the split of the AI docs into `documentation/ai.md`, uncommitted for the user to commit.

## Read this first: standing rules
- **Never commit, stage or stash.** The user writes every commit. Leave changes in the working tree.
- When you finish a piece of work, give the user a commit message in this format:
  ```
  {{title}}
  - {{point 1}}
  - {{point 2}}

  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
  ```
- **Milestone pieces are tagged in the title.** Any commit for a piece of a milestone (M5, M6, ...) gets the milestone number at the end of the title, `<title> (Mx)`, with `x` the milestone number, followed by a bullet list (no prose paragraph), then the co-author line:
  ```
  <title> (Mx)
  - <point 1>
  - <point 2>
  - <point 3>

  Co-Authored-By: ...
  ```
  For example, M7a is `Add Codex tracking and lifetime counters (M7)` with bullets for the Codex data and backfill (schema 7), the eight lifetime counters and where they are bumped, and the no-op/exhibition behaviour. Work outside a milestone keeps the plain format above.
- **Process.** The user follows superpowers: brainstorm → spec → plan → execute → review.
  - Specs go in `documentation/specs/` and plans in `documentation/plans/`.
  - The user approves each section of a design, then the written spec, then picks how the plan is executed. The user has chosen "Native" (inline) for the M6e to M6g pieces and "Subagent-driven" before that.
- The project memory is in `~/.claude/projects/.../memory/` and has the no-commits rule.


## Project
Godot 4.7.2 (.NET build, but GDScript only) monster-catching RPG.
- **`core/`** is pure logic: RefCounted classes with no nodes or autoloads. It holds the data defs, battle engine (and AI), progression and saves.
- **`game/`** holds the scenes and UI: autoloads, battle scene, overworld, progression screens, debug menu.
- **`data/`** holds JSON content per category (creatures, moves, items, passives, AI styles, tamers, ...). Every category is checked by `core/data/schemas.gd` and `core/data/validator.gd`.
- **`tests/`** uses GdUnit suites. Shared helpers are `tests/helpers/fixture_db.gd`, `world_test.gd` and `screen_fit.gd`.

## Where the documentation is
- `README.md`: what the game is, layout, running, checks.
- `documentation/developer-guide.md`: how to change things (a recipe per change), where things live, troubleshooting.
- `documentation/battle-engine.md`: the engine API, round order, formulas, effect ops, passives and held items, events, tests.
- `documentation/ai.md`: the battle AI: styles (`data/ai_styles.json`), scoring, swapping, what it values from passives, held items and triggers.
- `documentation/compendium.md`: generated from `data/` (never edit by hand). Also `map-building.md`, `codex.md`, `tracking.md`, `achievements.md`, `logging.md`.
- `documentation/specs/` (the design of each piece) and `documentation/plans/` (how it was built). The roadmap is `specs/2026-11-05-roadmap-m5-m8.md`.
- `tests/data/test_docs_drift.gd` fails when an event, an effect op or a battle suite is missing from `battle-engine.md`.
- `.superpowers/history/HANDOFF-through-M6g.md`: the full per-piece history (rulings, simulator numbers, deferred minors) that this page used to hold.

## How to run and test
- Godot console: `/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`
- Full check: `bash scripts/check.sh`. It covers data validation, dialogue check, map check, all test suites and compendium generation, and must end with "All checks passed."
- After adding a new `class_name` file, run `godot --headless --path . --import` once (`check.sh` does) or the class is not found.
- The `.claude/skills/run-godot-monster-catching-game/` skill launches and drives the real game.
  - Tours: `--mode=frontend|battle|overworld|progress|passives|held|builder|party|bag|ui|box`, each in `tours/*.gd`.
  - In tour files, `d` is untyped, so values derived from it use `=`, not `:=`.
- Godot test runs share save files, so don't run two test or Godot processes at once.
- `tools/simulate.gd -- --battles=200 --seed=1 --format=2v2 --level=10 --ai=tactician,aggressive` runs AI against AI (any two style ids from `data/ai_styles.json`); the output is deterministic for a seed, so it doubles as a no-regression check for AI changes.

## State of the milestones
- **Done:** M0 to M5 (engine, battle scene, overworld, progression, box and party screens, shared UI), **M6 engine backlog**
  (status cure; growth tiers and starter evolutions M6b; multi-hit moves M6c; the pinned `one_ally` and Underdog-swap rulings M6d;
  AI modelling of knockout/faint/status/round-end/enter triggers M6e; AI swapping M6f; AI styles as data plus `passive`,
  `defensive`, `trickster` M6g; the AI accuracy pass M6h), and **M7** (tracking, Codex screens, achievements).
- **Next in the roadmap:** M8 art and audio (all art is placeholder), M9 content expansion.
- **Facts worth knowing about the AI** (details in `battle-engine.md` → AI styles):
  - A style is an entry in `data/ai_styles.json`; a tamer's `ai` is optional and defaults to `basic`.
  - `basic`, `aggressive` and `tactician` were migrated to profiles without any change in behaviour (byte-identical simulator output).
  - Simulator (2v2, 200 battles, seed 1, both orders): `passive` wins about 16% (level 10) and 8% (level 40) against the tactician, `defensive` and `trickster` about 49%; swapping is neutral for the tactician's win rate.

## Open work
- **Minors:** the docs sweep, the test hardening and the small behaviour fixes are done (see the progress section of the audit). One triaged list is in `.superpowers/2026-11-12-minors-and-docs-audit.md` (what to drop, what to fix, test hardening, AI accuracy). The original passives list, with the cost of each if wrong, is `.superpowers/2026-11-04-passives-handoff.md`; per-piece minors of M6c to M6g are in the history file.
- **Possible, none requested:** the small AI modelling gaps listed in the audit (each needs simulator runs); M9 groundwork (reorganize `data/creatures/`); a brainstorm of M8 (art and audio) or M9 (content).
- **To do as part of M9:** reorganize `data/creatures/` by evolution family, one file per family, in subfolders by where the species is obtained (`starters/`, `route_01/`, ...), roughly 5 to 15 species per file. The loader already walks subfolders. Add two data tests: creature ids unique across files, and dex numbers unique with no gaps.
- Ask the user what is next before starting anything. New features go through brainstorming first.

## What changed in M6h, the AI accuracy pass (2026-11-12, committed in `6ea9988`)
Spec `documentation/specs/2026-11-12-m6h-ai-accuracy-design.md`, plan `documentation/plans/2026-11-12-m6h-ai-accuracy.md`.
- **Retaliation through `trigger_value`:** the tactician's hit-trigger cost no longer has its own code. A foe's self-heal on hit now counts as a cost, more ops are priced, and the style's `trigger_setup` applies. `trigger_value` now sets `ctx.attacker` for hit triggers (a bug that M6e never hit). Simulator output was byte-identical to the baseline on shipped data and on the test pack.
- **Scaled knockout bonus:** `KO_BONUS` 30 is replaced by `ko_bonus(ref)` = `KO_FACTOR` 1.4 x `ref` (30 only suited level 10: 1.4 best hits there, 0.5 at level 40, 0.3 at level 70).
- **Swap scoring in place:** `BattleAI._with_swapped_in` evaluates `threat(c)`, `best_damage(c)` and `enter_value(c)` with the bench creature standing in the leaver's slot, so its passive, held item, `field_boost` and the allies' auras count.
- **Expected threat:** `threat(x)` weights each foe move by `_share` (single target 1/n, `two_enemies` min(2, n)/n, spread 1).
- **Measured (2v2, 200 battles, seed 1):** swaps per battle about 0.55 to 0.8 before and after; tactician win shares moved at most 2 points at each step; the M6g targets still hold (passive 16.0% and 9.8% against the tactician, defensive about 49%, trickster 47.5% and 50.2%, draws under 2%).
- **Review fixes (Opus):** hit triggers are priced at the HP the target is left with (the engine fires them after the damage), and a consumed or per_battle item is charged once per move, not per hit; this mattered for the shipped Oran Berry, which the old retaliation code ignored (the spec had wrongly said shipped numbers were unchanged). The doomed knockout bonus now flips where the expected threat reaches `hp_b`, which is not a 50% knockout chance (documented, not changed).
- **Tests:** `tests/battle/test_ai_accuracy.gd` (18). Some fixtures in `test_ai_swaps.gd` and `test_ai_styles.gd` changed: the doomed-swap cases use a `brute` lead, a `wall` bench and weak foes, because at the old fixture scale (a foe's threat as large as the lead's own damage) the scaled bonus no longer made a swap worth it; real data has threat about 0.4 x `ref`.
- **Not done:** a test for a benched creature's `field_boost` (an own helpful state's value does not depend on stacks, so nothing observable); `KO_FACTOR` was not tuned.
