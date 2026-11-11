# M7 Collection and achievements — Design

Date: 2026-11-11
Status: Approved. 7a and 7b implemented; 7c (achievements) not started.
Parent: [Roadmap M5–M9](2026-11-05-roadmap-m5-m8.md) (M7 inserted here; art and audio become M8, content M9).
Builds on the [M5b shared visual pieces](2026-11-06-m5b-shared-visual-pieces-design.md) and the
[M5d Box and Party design](2026-11-06-m5d-box-and-party-design.md).

## 1. Goal

Track which creature species the player has seen and caught, show that in a Codex with a detail page per
species (sprite, description, where it can be found), and add an achievements framework that is cheap to
extend: an achievement is a data entry, a new kind of criterion is one small class, and each kind has a
placeholder icon. The core records unlocks and announces them without drawing anything, so a toast or a
platform bridge (Steam) can subscribe later.

**Success:** the player can open Codex and Achievements from the pause menu; seen and caught state is right
for every way a creature enters the game; adding an achievement of an existing kind needs only JSON; adding a
new kind needs one class, one schema entry and one registry line; all checks pass.

### Decisions

| Topic | Decision |
|---|---|
| Placement | New milestone M7 between engine backlog (M6) and art/audio (now M8); content expansion becomes M9 |
| Order | 7a Tracking, then 7b Codex screens, then 7c Achievements (7c reads 7a's data) |
| Codex scope | Seen and caught per species, a Codex list screen, and a per-species detail page |
| "Caught" | Every way a creature joins: capture, starter or gift, evolution; a backfill covers old saves |
| "Seen" | Every foe species sent out in a (non-exhibition) battle |
| Location reveal | A species' locations show once it is seen; unseen species are "???" and do not open |
| Criteria v1 | `counter`, `codex`, `flag`, `creature` |
| Unlock presentation | None yet. The service emits `unlocked(id)`; nothing subscribes. Achievement ids are stable strings so a platform bridge can map them |
| Rewards | None. An optional `reward` field can be added later without changing the data shape |
| Hidden achievements | Optional `hidden: true`: a locked hidden entry shows "???" |

## 2. Sub-projects

Each gets its own brainstorm, spec, plan and execution.

### 7a Tracking
- **Codex data:** `save.codex` maps species id to `{seen: bool, caught: bool}`; caught implies seen. A static
  `Codex` class in `core/progress/codex.gd`: `mark_seen`, `mark_caught`, `status`, `seen_count`, `caught_count`.
- **Hooks (one choke point per source):** `BattleLauncher.apply_results` marks every foe species that was
  sent out as seen and every captured creature as caught; `Story.give_creature` marks starters and gifts;
  evolution marks the new species; loading a save backfills caught from the party and every box. Exhibition
  battles track nothing (they already save nothing).
- **Counters:** lifetime stats live in the existing `story.counters` store under reserved ids. A `Counters`
  class (`add`, `get`, `BUILT_IN`) lists `battles_won`, `battles_fought`, `tamers_defeated`,
  `creatures_caught`, `creatures_evolved`, `items_used`, `money_earned` and `steps`. Hooks bump them at the
  same choke points, plus the overworld step. Details in the 7a spec.
- **Save:** schema 7 adds `codex`, with a migration that runs the backfill. Counters start at 0 on old saves.
- No screens. Tests per class, the migration, and each hook.

### 7b Codex screens
- **Codex list:** a pause-menu entry **Codex**: a paged list in species order, each row a small
  `CreatureSpriteSlot`, number, name and a caught/seen mark; unseen species are a silhouette and "???".
  A header shows "Seen n / N · Caught n / N".
- **Species detail page:** opens for seen species. A large `CreatureSpriteSlot`, the name, number and types,
  the creature's `description` (optional schema field that already exists; "No description yet." when
  absent), and **Where to find it**: one line per place, for example "Route 1 – Route 1 tall grass,
  Lv 2–5". A species with no wild source shows "Evolves from X" or "Given to you" where known, else "No wild
  habitat known". Seen but not caught adds a "Not caught yet" note. No stats or `CreatureCard` here.
- **Location data:** `tools/build_locations.tscn` (reading the map scenes) writes `data/locations.json` (new category `locations`, a
  "file" category) mapping each map to its encounter tables: its `default_encounter` and each
  `encounter_area` piece. The area label is the encounter table's own `name`. The validator checks every
  encounter id exists; the map check fails when the scenes and the file disagree. A shipped species without a
  description is a validation warning, fixed in 7b.
- Both screens are keyboard- and gamepad-navigable and fit 640x360 (`screen_fit`). Tour `--mode=codex`.

### 7c Achievements
- **Data:** category `achievements` (folder `data/achievements/*.json`), entries
  `{id, name, description, hidden?, criterion}`. One criterion per entry. Validated in `schemas.gd` and
  `validator.gd`.
- **Criteria kinds:** classes in `core/achievements/criteria/`, each with a schema block (like
  `DataSchemas.EFFECT_OPS`), `progress(db, save) -> {current, target}` and an icon category; registered in
  one place (like `EffectOps`).
  - `counter` `{stat, target}`: `story.counters[stat] >= target` (stat must be in `Counters.BUILT_IN`).
  - `codex` `{mode: seen|caught|species, target | species}`: codex counts, or one species caught.
  - `flag` `{flag}`: a story flag is set.
  - `creature` `{what: level|bond|evolved, target}`: highest level or Bond among owned creatures, or the
    `creatures_evolved` counter.
- **Evaluation:** `Achievements.evaluate(db, save)` is pure and returns the newly met ids. A service
  autoload calls it at checkpoints (after a battle, a story flag, a creature given or evolved, a load, every
  50 steps), writes `save.achievements[id] = unlock time`, and emits `unlocked(id)`.
- **Icons:** `AchievementIconSlot` (like `ItemIconSlot`): a colour and letter per criterion kind; locked
  entries are greyed. Real art arrives in M8.
- **Screen:** a pause-menu entry **Achievements**: a scrolling list with icon, name, description and the
  unlock date or progress ("7 / 10"); hidden locked entries show "???". Tour `--mode=achievements`.
- **Compendium:** an Achievements section.

## 3. Cross-cutting
- **Debug:** an F1 "Collection" page: mark species seen or caught, set counters, unlock or reset
  achievements.
- **Docs:** `documentation/compendium.md` gains an Achievements section and a "Found:" line per creature;
  a short reference for adding an achievement or a criterion kind goes in `documentation/`.
- **Testing:** unit tests for each class, the migration and the hooks; screen-fit tests; the two tours
  with screenshots checked; `bash scripts/check.sh` ends "All checks passed."

## 4. Dependencies
7a needs nothing new. 7b needs 7a and the M5b sprite slot. 7c needs 7a (counters, codex) and the M5b icon-slot
pattern; its screen needs the pause menu. M8 (art) fills the new icon and sprite slots.

## 5. Out of scope
Rewards, an unlock toast, a Steam or other platform bridge (the `unlocked(id)` signal is the seam), box
sorting by Codex number, per-sighting location tracking, gifts and tamer teams as listed locations, and
real art.
