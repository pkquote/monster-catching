# Monster-Catching RPG — Design Spec

Date: 2026-11-03
Status: Approved for implementation (M0 → M1 first)

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
  - **Extra actions:** each underdog creature gains `floor(r) - 1` bonus actions per round (1v2 → +1, 1v3 → +2, 2v3 → +0).
  - **Spread reduction:** damage from multi-target moves reduced by `spread_reduction_per_ratio * (r - 1)`, capped.
  - **Stat bonus:** `+stat_bonus_per_ratio * (r - 1)` to Attack/Defense, capped.
  - **XP bonus:** `xp_bonus_per_ratio * (r - 1)`.
- Underdog is re-evaluated whenever active counts change (faints, swaps).
- All numbers live in `data/balance.json`.

### 2.2 Field states (per side)

- Each side holds up to `max_field_states` (default 3) states. Each state has `turns` remaining and `stacks` (max from data).
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

Targets: `self`, `one_ally`, `one_enemy`, `all_allies`, `all_enemies`, `all`, `own_side`, `enemy_side`.

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
  creatures/  moves/  items/  tamers/  encounters/     ← any number of *.json files
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
  "base_stats": { "hp": 45, "atk": 40, "def": 45, "spd": 50 },
  "catch_rate": 0.45, "xp_yield": 60,
  "learnset": [ { "level": 1, "move": "splash_jab" }, { "level": 7, "move": "riptide" } ],
  "growth": [ { "level": 16, "affinity": "striker", "into": "torrentusk" },
              { "level": 16, "affinity": "catalyst", "into": "mistcoil" } ] }
```

```json
{ "id": "riptide", "name": "Riptide", "type": "water", "category": "physical",
  "power": 50, "accuracy": 95, "priority": 0, "target": "one_enemy",
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
- NPC data lists conversations as `[{ "if": "<flag expr>", "file": "...", "title": "..." }]`; the first matching entry runs.
- Triggers: interact, area enter, map enter, battle result.
- The battle engine has no knowledge of dialogue.

## 6. Saves

JSON save files containing party/storage `CreatureInstance` data (species id, level, xp, hp, moves, affinity, nickname), inventory, story flags, and player position. Save files carry `schema` for migration.

## 7. Milestones

| Milestone | Scope |
|---|---|
| **M0 Foundation** | Project settings (32x32 pixel, stretch), folder layout, gdUnit4 + Dialogue Manager installed, JSON loader, typed defs, Database, validator + headless tool, starter data, export filter |
| **M1 Battle engine** | Headless N-vs-M engine: speed order, types, damage, statuses, field states + reactions, Underdog, basic AI, catching, XP + Affinity awards; full tests; CLI battle simulator |
| **M2 Battle scene** | Diagonal stage, placeholder sprites, action menus, event playback, catch animation |
| **M3 Overworld + story** | One town + one route, movement, NPCs, Dialogue Manager conversations, one cutscene, rival battle, wild encounters |
| **M4 Progression + saves** | Level-ups, one species with growth branches, party + storage menus, JSON save/load |

Starter content: ~8 creatures, ~20 moves, 5 field states, 4 reactions, 3 capture items, 2 tamers, 1 encounter table (placeholders).

## 8. Testing

- gdUnit4 suites covering all of `core/`: loader, validator, damage, type chart, reactions, Underdog math, catch formula, Affinity and growth, StoryState.
- Seeded battle simulator (`tools/simulate.gd`) for AI-vs-AI balance runs.
- Validator runs headless on every commit.
- Scenes are verified by manual playtest.

## 9. Out of scope (for now)

Mod loading, localization files, spreadsheet import pipeline, online play.
