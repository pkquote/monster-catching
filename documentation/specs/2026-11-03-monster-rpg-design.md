# Monster-Catching RPG — Design Spec

Date: 2026-11-03
Status: Approved. M0–M4, creature passives and held items implemented; M5–M8 planned (see the roadmap).

## 1. Intent

A top-down monster-catching RPG built in Godot, intended to grow into a full,
shippable game. The player explores a 32x32 pixel-art overworld, catches
creatures, raises them, and battles wild creatures and NPC tamers in a
separate, more detailed turn-based battle scene.

Success means: a data-driven foundation that scales to hundreds of creatures,
moves and items, a battle engine that is fully testable without scenes, and
mechanics that feel distinct from the genre's defaults.

### Decisions made

| Topic | Decision |
|---|---|
| Engine | Godot 4.7, typed GDScript |
| Overworld | Top-down, 32x32 tiles, pixel-perfect scaling |
| Battle view | Separate scene, side-on diagonal stage (player lower-left, enemy upper-right), large sprites (96–128px) |
| Battle formats | 1v1, 2v2, 3v3 and uneven (e.g. 1v3); outnumbered side gets **Underdog** compensation |
| Signature mechanic 1 | **Field states and reactions**, held per side, interactable on both sides |
| Signature mechanic 2 | **Behavior-shaped growth** via Affinity tracks |
| Creature passives | Each creature rolls a **passive** for life and can unlock a second through Affinity; one is active at a time (always-on, triggered, protection and overworld effects). Design: [creature passives](2026-11-04-passives-design.md) |
| Held items | A creature holds one **held item** (an item with category `held`): always-on effects, triggers and overworld effects like a passive, and a usage kind (`permanent`, `consumed`, `per_battle`). Given and taken back on the Summary. Design: [held items](2026-11-05-held-items-design.md) |
| Catching | Capture items whose odds depend on HP, status and the target side's field states |
| Architecture | Headless `core/` engine, presentation in `game/`, event-stream boundary |
| Content data | JSON from day one, folder-per-type, many files per folder, id references |
| Dialogue / cutscenes | Dialogue Manager plugin (`.dialogue` files) |
| Tests | gdUnit4, headless |

### Assumptions (open to change)

- Party size 6, with a storage box.
- Per round, the player picks actions for all active creatures, then actions resolve in speed order.
- Placeholder art until systems are proven.

## 2. Core mechanics

### 2.1 Battle formats and Underdog

- Every battle has a `max_active` per side (1–3). NPC tamers define theirs; wild encounters spawn packs of 1–3.
- The player may field **fewer** creatures than allowed.
- When one side has fewer active creatures, it gains **Underdog**, scaled by the ratio
  `r = enemy_active / ally_active` (only when `r > 1`):
  - **Extra actions:** each underdog creature gains `floor((r - 1) * bonus_actions_per_ratio)` bonus actions per round.
    With the tuned rate of 0.5: 1v2 → +0, 1v3 → +1, 2v3 → +0.
  - **Spread reduction:** damage from multi-target moves reduced by `spread_reduction_per_ratio * (r - 1)`, capped.
  - **Stat bonus:** `+stat_bonus_per_ratio * (r - 1)` to Physical/Special Attack and Defense, capped.
  - **XP bonus:** `xp_bonus_per_ratio * (r - 1)`.
- Underdog is re-evaluated whenever active counts change (faints, swaps).
- Tuning target (from the simulator, equal AIs): the outnumbered side wins roughly 38–47%, so
  Underdog is a risk that pays off in XP rather than a free advantage.
- All numbers live in `data/balance.json`.

### 2.2 Field states (per side)

- Each side holds up to `max_field_states` (default 1; a state that doesn't react replaces the current one) states. Each state has `turns` remaining and `stacks` (max from data).
- Initial states: **Soaked, Scorched, Overgrown, Charged, Frosted**.
- Moves may apply, remove or consume states on **their own side or the opposing side**.
- Applying the same state adds a stack and refreshes its duration.
- States tick down at end of round; at 0 turns they are removed.
- States may passively modify stats, accuracy or type damage for creatures on that side (data-defined effects).

### 2.3 Reactions

When a state is applied to a side that already holds a state it reacts with, the reaction fires immediately:

| Reaction | Inputs | Effect |
|---|---|---|
| Conduction | Charged + Soaked | Shock damage to all creatures on that side; consumes Charged |
| Wildfire | Scorched + Overgrown | Burn damage-over-time to that side; consumes Overgrown |
| Icebound | Soaked + Frosted | Speed down to all on that side; consumes Soaked |
| Steam | Scorched + Frosted | Accuracy down on **both** sides; consumes both |

Reactions are data (`data/reactions.json`), each made of standard effect ops. The reaction's power scales with the stacks consumed. Reactions credit the **Catalyst** Affinity of the creature that triggered them.

### 2.4 Moves and the effect-op system

Moves, items, reactions, field-state passives and abilities all share one effect pipeline. Each is a list of `effects`, each with an `op` that maps to a handler class in `core/battle/effects/`. Adding a new behavior = one new handler; then any amount of content uses it from JSON.

Initial ops: `damage`, `heal`, `apply_status`, `apply_field_state`, `remove_field_state`, `bonus_if_field` (power multiplier, optional consume), `stat_stage`, `capture` (items only).

Targets: `self`, `one_ally`, `one_enemy`, `two_enemies` (the user picks two distinct foes; see the [two-opponent moves design](2026-11-05-two-target-moves-design.md)), `all_allies`, `all_enemies`, `all`, `own_side`, `enemy_side`.

### 2.5 Behavior-shaped growth

- Levels raise stats (base stats + growth curve) and unlock moves from a learnset.
- Each creature also has **Affinity tracks**: Striker, Warden, Catalyst, Trickster (defined in `data/affinities.json`).
- Battle events award Affinity points:
  - Striker: dealing damage, landing finishing blows.
  - Warden: taking hits for allies, healing, guarding.
  - Catalyst: applying field states, triggering reactions.
  - Trickster: inflicting status, stat drops, causing misses.
- A species may define `growth` branches at given levels. At that level, the branch whose `affinity` matches the creature's highest track (above a threshold) is offered; if none qualifies, the `default` branch (or no change).

### 2.6 Catching

- Wild battles only. Using a capture item is a turn action.
- Catch chance:
  `p = base_rate(species) * item_mult * hp_factor * status_mult * field_mult`, clamped to `[0, 1]`
  - `hp_factor = 1 - (hp / max_hp) * hp_weight` (from balance)
  - `field_mult` = product of the item's `field_bonus` for each matching state on the **target's side**
- Starter items: **Lure Cage** (plain), **Tide Net** (bonus on Soaked), **Snare Vine** (bonus on Overgrown).
- **Held items** are not used from the bag: the item category `held` has a `held` block (the same shape as a passive: `effects`, `triggers` with an optional `when`, `field`, plus `scope` and a usage kind `use` of `permanent`, `consumed` or `per_battle`). A creature holds at most one (`CreatureInstance.held_item`, saved from schema 5, also settable on tamer party members); the Summary's Stats tab gives, swaps and takes it back, and a consumed item is gone after the battle. Five starter items are sold at the Town 1 shop.

### 2.7 Stats

Every species defines 9 base stats. Bond is per creature, not per species.

| Stat | Key | Source | Used for |
|---|---|---|---|
| HP | `hp` | species | Hit points |
| Physical Attack / Defense | `patk` / `pdef` | species | Damage of `physical` moves (contact: punches, bites, tackles) |
| Special Attack / Defense | `satk` / `sdef` | species | Damage of `special` moves (beams, blasts, sprays) |
| Speed | `spd` | species | Turn order |
| Luck | `luck` | species | Stored and shown; no effect yet. Reserved for crits, proc chances, catch odds, drops |
| Resolve | `resolve` | species | Status and stat-drop resistance; rare chance to endure a knockout |
| Stamina | `stamina` | species | Size of the energy pool |
| Bond | `bond` | per creature | −100…+100; reflects how the creature is treated |

Formulas (integer division, `pct` = the stat's growth tier as a whole percent, 100 = steady): HP = `2·base·pct·Lv/10000 + Lv + 10`; other battle stats = `2·base·pct·Lv/10000 + 5`;
max energy = `2·base_stamina·pct·Lv/10000 + 20`. Training points (2.10) are added on top.
Each species may give any of its 9 base stats a growth tier (`slow` 80%, `steady` 100%, `fast` 120%; `growth_rates` in the species JSON, tier values in `balance.json`); unlisted stats are steady.

The level cap is 99. The formula's level-driven value is a creature's **growth** (`CreatureInstance.grown`); training is the part the player added. The Summary's Stats tab shows both: `Physical Attack 104 (92+12)` is a total of 104, from 92 growth and 12 training (an untrained stat shows only its total). A species' base stat and growth tier set its growth rate: about `base·pct/5000` per level, so at level 99 a base-50 stat reaches 84 (slow), 104 (steady) or 123 (fast), and a base-100 stat 163, 203 or 242, against at most +30 from training. The Summary marks a stat whose tier is not steady with ▲ (fast) or ▼ (slow).

### 2.8 Resolve

- **Resistance:** a status, or a stat drop from a foe, is resisted with chance
  `resist_cap × R / (R + R_avg)`, where `R` is the target's Resolve and `R_avg` is the Resolve of an
  average (base 50) creature at the attacker's level. An average creature resists 15% (cap 30%).
- **Endure:** once per battle, a hit that would knock the creature out leaves it at 1 HP, with chance
  `endure_cap × R / (R + R_avg)` (cap 10%, about 5% for an average creature).

### 2.9 Stamina and energy

- Each creature has an energy pool (`max energy` above). Current energy persists between battles
  and is saved, like HP.
- Every move has a `cost`: weak 0–2, standard 4–6, strong 8–12. A move can't be chosen without
  enough energy.
- Energy does not refill during battle, except with **Rest**: the creature spends its action to
  restore `rest_fraction` (25%) of its pool.
- **Scrap** (free, power-25 neutral physical move) is always available, so a drained team is never stuck.
- Recovery outside battle: rest points refill fully, items with the `restore_energy` op, and
  (M3) a slow trickle while walking in the party.

### 2.10 Training points

- Each level-up grants `points_per_level` (1) training points, which the player assigns to stats.
- One point adds +1 to a stat (+2 to HP). No stat can hold more than `max_per_stat` (30) points.
- Assignable: HP, Physical/Special Attack and Defense, Speed, Resolve, Stamina (not Luck, for now).
- Lets the player cover a weakness or push a strength. Respec comes with the M4 menus.

### 2.11 Bond

- Range −100…+100. Caught creatures start at 0; starters at +20.

**Gains and losses:**

| Happening | Bond |
|---|---|
| Wins a battle it took part in | +2 |
| Lands a knockout | +1 |
| Healed with an item | +1 |
| Rests at a rest point (M3) | +2 |
| Faints | −4 |
| Sent out or ordered to act below 25% HP or 20% energy (overwork, once per battle) | −2 |

**Negative Bond**, scaling linearly from 0 to −100:
- **Disobeys commands:** up to a 40% chance per action to ignore the order and use a random other
  move it can afford, or loaf around.
- **Weaker performance:** up to −20% to accuracy and damage.
- **Lashes out:** at −50 or below, a 5% chance to Scrap itself or a random ally instead of acting.

**Positive Bond:** up to +10% XP at +100.

All numbers live in `data/balance.json`.

## 3. Architecture

```
res://
  core/            Pure logic. Never touches Node, SceneTree, or autoloads.
    data/          JSON loader, schema checks, typed defs, Database, validator
    battle/        BattleState, BattleEngine, effect ops, fields, reactions, Underdog, AI
    progress/      XP/level curves, Affinity, growth branches, catch formula
    story/         StoryState (flags, counters)
  game/            Godot scenes and autoloads. Reads from core, holds no rules.
    autoload/      DataRegistry, GameState, SceneRouter, Story, Cutscene
    overworld/     Tilemaps, player, NPCs, encounter zones, triggers
    battle/        Diagonal stage, event playback, action menus
    ui/
  data/            JSON content
  dialogue/        Dialogue Manager .dialogue files
  tests/           gdUnit4 suites
  tools/           Headless validator, battle simulator
  addons/          gdUnit4, dialogue_manager
```

### 3.1 Boundary rules

- `core/` classes extend `RefCounted` (or are static). They never reference `Node`, scenes, or autoloads.
- `core` is given a `Database` and a seeded `RandomNumberGenerator` explicitly. Same seed + same inputs → same battle.
- The battle engine returns a list of **BattleEvent** dictionaries (`{type, ...}`), e.g. `move_used`, `damage`, `field_applied`, `reaction`, `faint`, `capture_attempt`. The battle scene plays these back as animations. The scene never computes outcomes.

### 3.2 Battle flow

1. `BattleEngine.new(db, rng, setup)` where `setup` describes sides, creatures, `max_active`, and `is_wild`.
2. Each round: the caller supplies an `Action` for every action slot (creatures × (1 + bonus actions)); AI supplies enemy actions.
3. `engine.resolve_round(actions) -> Array[BattleEvent]`: sort by priority then speed (ties broken by seeded RNG), run each action through the effect pipeline, check reactions, faints, end-of-round field ticks, Underdog recompute, battle end.
4. `engine.is_over()` / `engine.result()`: winner, captured creature, XP and Affinity awards.

## 4. Data

### 4.1 Layout

```
data/
  creatures/  moves/  items/  passives/  tamers/  encounters/     ← any number of *.json files
  types.json  statuses.json  field_states.json  reactions.json  affinities.json  balance.json
```

- Field rules for every category live in `core/data/schemas.gd`. Unknown fields are errors.
- Every file: `{ "schema": 1, "entries": [ ... ] }` (singleton files like `balance.json` use `{ "schema": 1, "data": { ... } }`).
- Every entry has a unique string `id` within its category (snake_case).
- Cross-references are by id.
- The loader merges all files in a folder; duplicate ids are errors.

### 4.2 Example entries

```json
{ "id": "tidepup", "name": "Tidepup", "types": ["water"],
  "base_stats": { "hp": 50, "patk": 45, "pdef": 45, "satk": 50, "sdef": 45, "spd": 50,
                  "luck": 50, "resolve": 45, "stamina": 55 },
  "catch_rate": 0.45, "xp_yield": 60,
  "learnset": [ { "level": 1, "move": "splash_jab" }, { "level": 7, "move": "riptide" } ],
  "growth": [ { "level": 16, "affinity": "striker", "into": "torrentusk" },
              { "level": 16, "affinity": "catalyst", "into": "mistcoil" } ] }
```

```json
{ "id": "riptide", "name": "Riptide", "type": "water", "category": "physical",
  "power": 55, "cost": 6, "accuracy": 95, "priority": 0, "target": "one_enemy",
  "effects": [ { "op": "bonus_if_field", "side": "target", "state": "soaked", "mult": 1.5, "consume": true },
               { "op": "damage" } ] }
```

### 4.3 Validation

`core/data/validator.gd` checks, per entry: required fields, field types, enum values (types, targets, ops, categories), numeric ranges, and every reference (moves in learnsets, growth targets, items in tamer bags, creatures in encounters, states in effects, reaction inputs). Errors include file path and entry id. Runs:

- at game boot (fails loudly in debug builds),
- headless: `godot --headless --path . --script res://tools/validate_data.gd` (exit code 1 on errors),
- in tests.

It also scans `dialogue/*.dialogue` for `start_battle("<id>")` and checks the tamer ids exist.

### 4.4 Export

`.json` and `.dialogue` files must be included in export presets (`include_filter = "data/*, dialogue/*"`).

## 5. Dialogue and cutscenes

- Written in Dialogue Manager `.dialogue` files under `res://dialogue/`.
- `Story` autoload: wraps `core/story/StoryState` (flags, counters), exposes `flag()`, `set_flag()`, `start_battle(tamer_id)` (awaitable), `last_battle_won()`.
- `Cutscene` autoload: awaitable actor/camera commands (`lock_player`, `move`, `face`, `pan_camera`, `fade`, `wait`).
- NPCs point at one dialogue file and title; branching on story state happens inside the dialogue (`if Story.flag("...")`). See the [M3 overworld design](2026-11-03-m3-overworld-design.md).
- Triggers: interact, area enter, map enter, battle result.
- The battle engine has no knowledge of dialogue.

## 6. Start flow, saves and settings

### 6.1 Screen flow

```
Splash ──► Title menu ──► Resume      (most recently loaded/written save; hidden if none)
 (any key   │             New Game ──► Name entry ──► new playthrough + first save ──► World
  skips)    │             Load Game ─► Save browser (grouped by playthrough) ──► World
            │             Settings ──► Audio · Display · Gameplay · Controls
            └             Quit
```

- Splash: studio/engine credit, then the title, then the menu. Any key skips. If game content
  fails validation, the splash shows the errors instead of continuing (debug aid).
- All scene changes go through the `SceneRouter` autoload (fade out, swap, fade in).
- Until M3, "World" is a placeholder screen: player name, playtime, location, party, and
  Save / Settings / Quit to Title. It autosaves on entry.

### 6.2 Saves

- Unlimited manual saves plus one autosave **per playthrough**:
  `user://saves/<playthrough_id>/autosave.json` and `save_<timestamp>.json`.
- `user://saves/last.json` records the most recently loaded or written save (the Resume target).
- A save holds: `schema`, `playthrough_id`, `kind` (manual/auto), player name, created and saved
  times, playtime, location label, party and storage (`CreatureInstance` dicts, including each creature's `held_item`), inventory,
  money, story flags.
- Writes are atomic: write `<file>.tmp`, then replace the real file. A leftover `.tmp` is used if
  the real file is missing.
- Unreadable or invalid saves are listed as damaged (with the reason) instead of crashing.
- Older schemas are migrated on load through a migration table.
- The save browser groups saves by playthrough (most recent playthrough first, newest save first)
  and offers Load and Delete (with confirmation).
- `core/save/` holds the format and file logic as plain classes that take a directory path, so
  tests use a temp folder; menus only call it.

### 6.3 Settings

Stored in `user://settings.json`, separate from saves; applied immediately and saved on leaving
the settings screen.

| Group | Settings |
|---|---|
| Audio | Master, Music, SFX volume (audio buses created at startup) |
| Display | Fullscreen, window scale 2×/3×/4×, VSync |
| Gameplay | Text speed (slow/normal/fast/instant), battle animation speed (1×/2×/4×), confirm before ending a turn |
| Controls | Keyboard and gamepad bindings for move up/down/left/right, accept, cancel, menu; reset to defaults |

Defaults, ranges and binding serialization live in `core/settings/`; the `Settings` autoload applies
them to the engine (audio buses, window, input map). Game actions are mirrored into Godot's built-in
`ui_*` actions so menus follow rebinds.

## 7. Milestones

| Milestone | Scope |
|---|---|
| **M0 Foundation** | Project settings (32x32 pixel, stretch), folder layout, gdUnit4 + Dialogue Manager installed, JSON loader, typed defs, Database, validator + headless tool, starter data, export filter |
| **M1 Battle engine** | Headless N-vs-M engine: speed order, types, damage, statuses, field states + reactions, Underdog, basic AI, catching, XP + Affinity awards; full tests; CLI battle simulator |
| **M1.5 Front end** | Splash, title menu, new game (name entry), save browser, settings (audio, display, gameplay, controls), placeholder world; save store with unlimited saves, per-playthrough autosave and Resume |
| **M2 Battle scene** | Diagonal stage, placeholder sprites, action menus, event playback, catch animation, results; test battles from the placeholder world. Detailed design: [M2 battle scene design](2026-11-03-m2-battle-scene-design.md) |
| **M3 Overworld + story** | One town + interiors + one route, editor-built maps with placeable pieces, 8-way movement, NPCs, Dialogue Manager conversations, starter cutscene, items and hidden items, tamers with line of sight, heal spot + shop, pause menu, defeat rules, minigame hook. Detailed design: [M3 overworld design](2026-11-03-m3-overworld-design.md) |
| **M4 Progression + menus** | Level-ups, one species with growth branches, party + storage menus, training-point and respec UI |
| **Creature passives** | Rolled and Affinity passives, battle triggers and banners, the Passive Unlocked screen, switching on the Summary, the lead's overworld effects. Detailed design: [creature passives design](2026-11-04-passives-design.md) |
| **Held items** | One held item per creature: permanent, consumed and per-battle items, auras, overworld effects, give/take on the Summary, AI awareness. Detailed design: [held items design](2026-11-05-held-items-design.md) |
| **M5 Visual menus** | Controls-tab scrolling, compendium re-audit, bag item summary pane; shared visual pieces (creature sprite slot, stat radar with HP and Stamina bars, summary card, item icon slot); Summary redesign; box grid with sprites and a hover summary card; party view. Detailed design: [roadmap M5-M8](2026-11-05-roadmap-m5-m8.md) |
| **M6 Engine backlog** | Multi-hit moves, a status-cure op, growth-tier content for shipped species, AI modelling of enter/round-end/faint/knockout triggers, remaining passive and held-item minors. See the [roadmap](2026-11-05-roadmap-m5-m8.md) |
| **M7 Collection and achievements** | Seen/caught tracking and a Codex with species detail pages (sprite, description, where to find it), an achievements framework with pluggable criteria kinds and placeholder icons, lifetime counters. See the [M7 design](2026-11-11-m7-collection-achievements-design.md) |
| **M8 Art and audio pipeline** | Art conventions and slots for sprites, icons and type badges, wiring placeholders to real art, audio hooks on the existing buses. See the [roadmap](2026-11-05-roadmap-m5-m8.md) |
| **M9 Content expansion** | The real creature set, moves, maps, story and tamers; retires the test content pack. See the [roadmap](2026-11-05-roadmap-m5-m8.md) |

Starter content: ~8 creatures, ~20 moves, 5 field states, 4 reactions, 3 capture items, 2 tamers, 1 encounter table (placeholders).

## 8. Testing

- gdUnit4 suites covering all of `core/`: loader, validator, damage, type chart, reactions, Underdog math, catch formula, Affinity and growth, StoryState.
- Seeded battle simulator (`tools/simulate.gd`) for AI-vs-AI balance runs.
- Validator runs headless on every commit.
- Scenes are verified by manual playtest.

## 9. Out of scope (for now)

Mod loading, localization files, spreadsheet import pipeline, online play.
