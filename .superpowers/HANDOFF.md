# Handoff: godot-monster-catching-game

Date: 2026-11-12. Branch: `milestone/M6`. Last commit: `09332e4` ("Make AI styles data and add passive, defensive and trickster (M6)").
Everything through M6g is committed. After that commit the working tree holds only the 2026-11-12 documentation sweep
(see "What changed in the docs sweep"), uncommitted for the user to commit.

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
- `documentation/battle-engine.md`: the engine API, round order, formulas, effect ops, passives and held items, **AI styles and swapping**, events, tests.
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
  `defensive`, `trickster` M6g), and **M7** (tracking, Codex screens, achievements).
- **Next in the roadmap:** M8 art and audio (all art is placeholder), M9 content expansion.
- **Facts worth knowing about the AI** (details in `battle-engine.md` → AI styles):
  - A style is an entry in `data/ai_styles.json`; a tamer's `ai` is optional and defaults to `basic`.
  - `basic`, `aggressive` and `tactician` were migrated to profiles without any change in behaviour (byte-identical simulator output).
  - Simulator (2v2, 200 battles, seed 1, both orders): `passive` wins about 16% (level 10) and 8% (level 40) against the tactician, `defensive` and `trickster` about 49%; swapping is neutral for the tactician's win rate.

## Open work
- **Minors:** the docs sweep and the test hardening are done (see the progress section of the audit). One triaged list is in `.superpowers/2026-11-12-minors-and-docs-audit.md` (what to drop, what to fix, test hardening, AI accuracy). The original passives list, with the cost of each if wrong, is `.superpowers/2026-11-04-passives-handoff.md`; per-piece minors of M6c to M6g are in the history file.
- **Possible, none requested:** the audit's remaining pieces (small behaviour fixes such as the stray `UNDERDOG` event after `BATTLE_END` in `replace()`; an AI accuracy pass; splitting the AI sections out of `battle-engine.md` into `documentation/ai.md`).
- **To do as part of M9:** reorganize `data/creatures/` by evolution family, one file per family, in subfolders by where the species is obtained (`starters/`, `route_01/`, ...), roughly 5 to 15 species per file. The loader already walks subfolders. Add two data tests: creature ids unique across files, and dex numbers unique with no gaps.
- Ask the user what is next before starting anything. New features go through brainstorming first.

## What changed in the docs sweep (2026-11-12, uncommitted)
- `documentation/battle-engine.md`: "four parts", the 15 missing suites in the Testing table, a new "Effect ops" reference, the `capture_failed` event.
- `tests/data/test_docs_drift.gd` (new): the guard described above.
- `README.md`, `documentation/developer-guide.md`: M6 status, roadmap bullets, AI styles in the content reference and "where do I find".
- Spec statuses: roadmap, M6e/f/g, logging, M2. The M6 list in the roadmap shows what was done.
- Code comments: `battle_ai.gd` header (six styles), `battle_engine.gd` ("four parts"); `tools/compendium_builder.gd` AI-styles table gained `trigger_setup`, `seeks_status` and `swap_avoid`.
- Bug found by the sweep: the M6g compendium AI-styles table printed a literal `%g` for every weight (GDScript format strings have no `%g`); fixed with `EffectText.num`, with two regression tests in `tests/data/test_compendium.gd`.
- This file was rewritten from 47 KB; the old one is `.superpowers/history/HANDOFF-through-M6g.md`.
