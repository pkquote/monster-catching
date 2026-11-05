# Held Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let creatures hold one item whose passive-style effects, triggers and overworld ops run in battle and the overworld, with permanent, consumed and per-battle usage kinds, given and taken on the Summary.

**Architecture:** A `held` block on an `items` entry is parsed into a `PassiveDef` (`ItemDef.held`) plus a usage kind, so `PassiveRules` runs it through the same always-on, trigger and aura paths as passives. `CreatureInstance.held_item` stores the id (save schema 5). `HeldItems` (core) does the give/take/swap bookkeeping against the bag; the Summary calls it.

**Tech Stack:** Godot 4.7 GDScript, gdUnit4, JSON content. Run everything with `bash scripts/check.sh` (must end "All checks passed."). Never run two Godot processes at once.

**Spec:** [documentation/specs/2026-11-05-held-items-design.md](../specs/2026-11-05-held-items-design.md)

## Global Constraints

- **Never commit, stage or stash.** Leave changes in the working tree; the final message offers a commit message in the project's format.
- One held item per creature: `CreatureInstance.held_item: String` (`""` = none). Usage kinds are exactly `permanent` (default), `consumed`, `per_battle`.
- `held` block fields: `use`, `scope` (`self` default | `allies`), `effects` (with `when`), `triggers` (`on` from `TRIGGER_ON`, `chance`, `contact`, `when`, `effects`), `field` (overworld ops). Item category value: `held`.
- Validator rules: a `held` block is required for category `held` and rejected otherwise; it needs at least one of `effects`/`triggers`/`field`; `consumed` and `per_battle` need at least one trigger and no always-on `effects`; a `held` item has no `target` and no top-level `effects`; a tamer's `held_item` must reference a `held` item.
- Triggers (passives and held items) get an optional `when` using the existing keys (`hp_below`, `underdog`, `field` with `side`), checked on the trigger's owner via `PassiveRules.when_holds`. A trigger whose `when` fails, whose `chance` roll fails, or whose effects would do nothing does not fire and does not use a `consumed` item up.
- Save schema becomes 5; the migration adds `held_item: ""` to every party and storage creature.
- Held items give no bag use: `FieldItems.can_use` stays false for them.
- Trigger effects from held items earn no Affinity and never chain (the existing depth guard and `running()` rule apply).
- New tests extend `GdUnitTestSuite` and follow the surrounding suites' helpers (`FixtureDB`, `WorldTest`, `ScreenFit`).

## Review Focus

1. A `consumed` item whose trigger `when` fails, whose chance roll fails, or whose effects would do nothing (a heal at full HP) must stay on the creature. Pinned in Task 4.
2. A `consumed` item that fires must be gone from the real creature after `commit`, including when the creature faints or the battle ends the same round. Pinned in Task 4.
3. Give, swap and take back must never duplicate or lose an item: bag count and held id always sum to what the player had, including swapping with the last copy in the bag. Pinned in Task 2.
4. A creature holding an item id that no longer exists in the data must still load, be ignored in battle, and show something sane on the Summary. Pinned in Tasks 2 and 6.
5. A protection effect (status immunity, absorb, stage guard, shelter) that comes from a held item must name the item in its banner, not the creature's passive. Pinned in Task 3.

---

### Task 1: Data shape, validation and defs

**Files:**
- Modify: `core/data/schemas.gd` (items entry, a shared trigger rule used by passives and held items, tamer party entry), `core/data/validator.gd`, `core/data/defs/item_def.gd`, `core/data/defs/passive_def.gd`, `core/data/defs/tamer_def.gd`
- Test: `tests/data/test_validator.gd`, `tests/data/test_held_items_data.gd` (new)

**Interfaces:**
- Produces: `ItemDef.held: PassiveDef` (null when the item is not `held`; its `id`/`name`/`description` are the item's), `ItemDef.held_use: String` (`"permanent"` default); `PassiveDef.triggers[i].when: Dictionary` (`{}` when absent); `TamerDef.party[i].held_item: String` (`""` when absent). Items category enum gains `held`.

- [ ] **Step 1: Write failing tests.** In `tests/data/test_validator.gd` (using `_base()`/`_errors_for`; add a helper `_held_item(overrides)` returning a valid `held` item entry such as a permanent `stat_mod` charm):
  - `test_held_item_valid_passes` (a permanent charm, a `consumed` item with a `hit` trigger, a `per_battle` item, an item with only a `field` op).
  - `test_held_block_required_for_held_category` and `test_held_block_rejected_on_other_categories`.
  - `test_held_block_needs_effects_triggers_or_field`.
  - `test_consumed_and_per_battle_need_a_trigger_and_no_effects` (four failing cases: each kind with no trigger; each kind with always-on `effects`).
  - `test_held_item_rejects_target_and_top_level_effects`.
  - `test_trigger_when_is_validated`: a passive trigger with `"when": {"hp_below": 0.5}` passes; `"when": {"bogus": 1}` fails.
  - `test_tamer_held_item_must_be_a_held_item`: a tamer party entry with `"held_item"` of a heal item fails; of a `held` item passes; unknown id fails.
  In `tests/data/test_held_items_data.gd` (`before()` builds a `Database` from a raw set with the held items above):
  - `test_item_def_parses_held_block`: `db.item(id).held` is a `PassiveDef` with the item's id and name, its `triggers[0].when` and `chance`/`contact` defaults, and `held_use` is `"consumed"`; a non-held item has `held == null`.
  - `test_held_use_defaults_to_permanent`; `test_tamer_def_reads_held_item` (`""` when absent).
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.**
  - `schemas.gd`: extract the passive `triggers` array rule into one constant used by both `passives` and the new `held` block, adding `"when"` as an optional dict whose fields mirror the keys the validator already accepts for effect `when` (reuse that definition rather than restating it). Items entry: category enum gains `held`; new optional `held` dict (`use` enum, `scope` enum, `effects` with `when`, `triggers`, `field`). Tamer party entry: optional `held_item` ref to `items`.
  - `validator.gd` `_check_cross_rules`: the item rules from Global Constraints (messages name the item id and the field); the tamer `held_item` category check (the schema ref already checks existence).
  - `PassiveDef.from_dict`: each trigger dict also carries `when` (`{}` default, duplicated). `ItemDef.from_dict`: when `category == "held"`, build `held` with `PassiveDef.from_dict` over the block merged with `id`, `name`, `description`, and set `held_use` from `use`. `TamerDef.from_dict`: party entries carry `held_item`.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed." (shipped content has no held items yet, so nothing else changes).

### Task 2: Creature field, saves and give/take helpers

**Files:**
- Create: `core/progress/held_items.gd`
- Modify: `core/progress/creature_instance.gd`, `core/save/save_game.gd` (`SCHEMA`), `core/save/save_store.gd` (migration), `core/battle/battle_setup.gd` (tamer party), `game/autoload/game_state.gd` (`load_from`)
- Test: `tests/progress/test_held_items.gd` (new), `tests/save/` (the existing save-store suite; extend it)

**Interfaces:**
- Consumes: `ItemDef.held` (Task 1).
- Produces: `CreatureInstance.held_item: String`; `HeldItems.def_of(db: Database, c: CreatureInstance) -> ItemDef` (null when none or the id is unknown); `HeldItems.give(db: Database, save: SaveGame, c: CreatureInstance, item_id: String) -> Dictionary` returning `{ok: bool, error: String, returned: String}` with errors `"not_held_item"` and `"none_left"`, where `returned` is the previous item id sent back to the bag by a swap (`""` if none); `HeldItems.take(save: SaveGame, c: CreatureInstance) -> Dictionary` returning `{ok, error}` with error `"empty"`.

- [ ] **Step 1: Write failing tests** in `tests/progress/test_held_items.gd` (a `FixtureDB`-based db with two held items `charm` and `berry`):
  - `test_give_moves_one_from_the_bag_to_the_creature`: inventory `{charm: 2}` → creature holds `charm`, inventory `{charm: 1}`.
  - `test_give_removes_the_inventory_key_at_zero`.
  - `test_swap_returns_the_old_item_to_the_bag`: holding `charm`, give `berry` with `{berry: 1}` → holds `berry`, inventory `{charm: 1}` and `returned == "charm"`; `test_swap_with_the_last_copy_conserves_items` sums counts before and after (Review Focus 3).
  - `test_give_rejects_a_non_held_item_and_an_empty_bag`: a heal item gives `"not_held_item"`, no change; an id with count 0 gives `"none_left"`, no change.
  - `test_take_returns_the_item_to_the_bag` and `test_take_from_an_empty_creature_errors`.
  - `test_unknown_held_id_is_ignored`: a creature with `held_item = "ghost"` makes `def_of` return null and `take` still returns the id to the bag.
  - `test_held_item_round_trips_and_copies`: `from_dict(to_dict())` and `copy_from` carry `held_item`.
  - In the save-store suite: `test_v4_to_v5_adds_held_item` (a schema-4 dict gets `held_item == ""` on party and storage creatures and `schema == 5`), and a full load of a v4 file succeeds.
  - A tamer party entry with `held_item` produces a battle creature with that item (`BattleSetup` test, in the existing suite that covers tamer setup).
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** `CreatureInstance`: `var held_item: String = ""`, carried by `to_dict`, `from_dict` (default `""`) and `copy_from`. `SaveGame.SCHEMA = 5`; add `4: _v4_to_v5` to `SaveStore.migrations()`. `HeldItems` as above (spend/return use the same inventory dictionary conventions as `FieldItems._spend`; `give` checks category via `db.item(item_id).category == "held"`). `BattleSetup`: apply a tamer party entry's `held_item` where it applies `passive`. `GameState.load_from`: log a warning (`Log.warn(Log.SAVE, ...)`) for any creature whose `held_item` is not `""` and not in the data, leaving it in place.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 3: Always-on effects, auras, overworld ops and protection banners

**Files:**
- Modify: `core/battle/passive_rules.gd`, `core/battle/battle_engine.gd` (`emit_passive` and its callers), `core/battle/effects/op_damage.gd`, `core/progress/passives.gd` (`field_mult`), `game/battle/battle_text.gd`
- Test: `tests/battle/test_held_items_battle.gd` (new), `tests/progress/test_passives.gd` (field mult)

**Interfaces:**
- Consumes: `HeldItems.def_of`, `ItemDef.held` (Tasks 1–2).
- Produces: `PassiveRules.held_def(b: Battler) -> PassiveDef` (the holder's held item as a def, or null); `PassiveRules.last_item: String` (the item id that supplied the effect matched by the most recent `_source`/`absorbs` call, `""` when the effect came from a passive); `BattleEngine.emit_passive(b: Battler, item := "")`, emitting `PASSIVE_TRIGGERED` with `passive` set to `""` and an `item` key when `item != ""`.

- [ ] **Step 1: Write failing tests.** In `test_held_items_battle.gd` (a `before()` db with fixture held items: a permanent `stat_mod` charm, a permanent `status_immune` charm, an `absorb_type` charm, a `guard_stages` charm, an aura charm (`scope: allies`, `incoming_type_mod`), plus a plain creature without items):
  - `test_held_effects_apply_like_passives`: `effects_for` contains the charm's effect and the stat changes; a creature without an item is unchanged (regression).
  - `test_held_item_and_passive_effects_stack`: a creature with a passive `stat_mod` and a held `stat_mod` gets both.
  - `test_held_effect_respects_when`.
  - `test_held_aura_reaches_allies_and_counts_once`: two allies on the field holding the same aura item give each beneficiary the effect once; an unrelated item id adds its own.
  - `test_unknown_or_benched_held_item_gives_nothing`: an unknown id and a benched or fainted holder contribute nothing.
  - `test_protection_banner_names_the_item` (Review Focus 5): for each of status immunity, absorb, stage guard (and shelter if a fixture exists), the emitted `PASSIVE_TRIGGERED` has an `item` equal to the charm and `passive == ""`; the same protection from a passive still names the passive and has no `item`.
  - In `tests/game/test_battle_text.gd`: a `passive_triggered` event with an `item` renders `"<Name>'s <Item name>!"`.
  - In `tests/progress/test_passives.gd`: `field_mult` multiplies the lead's passive and its held item's `field` entries; a non-lead's item is ignored; no lead gives 1.0.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** `held_def` returns `HeldItems.def_of(...)`'s `held` when the battler is on the field and alive, else null. `_collect` also adds the holder's held-item effects (when each `when` holds) and, for allies' held items with `scope: allies`, the aura effects, deduped by item id separately from passive ids (mark `last_item` so `_source` records which source supplied the match; extend the parallel `holders` array with a parallel `items` array). `absorbs` sets `last_item` the same way. `emit_passive(b, item)` as in Interfaces; its callers (the absorb, status-immune and stage-guard sites in `battle_engine.gd`, and the shelter site in `op_damage.gd`) pass `passive_rules.last_item` read right after the source lookup. `BattleText` names `db.item(ev.item).name` when `item` is present. `Passives.field_mult` also multiplies `field` entries of the lead's held item.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 4: Triggers, `when`, and using items up

**Files:**
- Modify: `core/battle/passive_rules.gd` (`fire`), `core/battle/battler.gd`, `core/battle/battle_events.gd`, `game/battle/battle_text.gd`, `game/battle/battle_playback.gd`
- Test: `tests/battle/test_held_items_battle.gd`, `tests/game/test_battle_text.gd`, `tests/progress/test_passives.gd` (passive trigger `when`)

**Interfaces:**
- Consumes: `PassiveRules.held_def`, `last_item`, `emit_passive(b, item)` (Task 3); `ItemDef.held_use` (Task 1).
- Produces: `Battler.held_spent: bool` (per-battle usage flag); `BattleEvents.ITEM_CONSUMED` (`"item_consumed"`, payload `{bid, item}`, added to `BattleEvents.ALL`).

- [ ] **Step 1: Write failing tests** (fixture items: a `consumed` berry `hit` trigger with `when: {hp_below: 0.5}` healing, a `per_battle` item whose `hit` trigger lowers the attacker's `patk`, a permanent `enter` item applying a field state, a `consumed` item that heals on `round_end`):
  - `test_item_trigger_fires_and_names_the_item`: the event has the item; effects land (heal, stat drop).
  - `test_passive_triggers_run_before_item_triggers_for_the_same_event`.
  - `test_trigger_when_gates_firing_for_passives_and_items`: above the HP threshold nothing fires, below it fires.
  - `test_consumed_item_is_cleared_and_announced`: after firing, `creature.held_item == ""` on the battle copy, one `ITEM_CONSUMED`, and after `engine.commit(0)` the **real** creature's `held_item` is `""` (Review Focus 2); a second hit fires nothing.
  - `test_consumed_item_survives_when_it_does_not_fire` (Review Focus 1): `when` false; chance 50 with a seeded rng roll that fails; a `round_end` heal at full HP; in each case the item is still held, no `ITEM_CONSUMED`, and the real creature keeps it after commit.
  - `test_consumed_item_is_gone_after_the_creature_faints_and_battle_ends`: a consumed `faint`-adjacent case (the consuming hit is the knockout blow's predecessor, then the creature faints and the battle ends) still commits `held_item == ""`.
  - `test_per_battle_item_fires_once_and_is_kept`: second hit does not fire, `held_item` unchanged, and in a new engine built from the same creature it fires again.
  - `test_permanent_item_fires_every_time` and `test_held_trigger_effects_earn_no_affinity_and_do_not_chain`.
  - In `test_battle_text.gd`: `item_consumed` renders `"<Name>'s <Item name> was used up."`; add `item_consumed` playback coverage (a message, no banner) in the existing playback smoke suite.
  - In `tests/progress/test_passives.gd`: a passive trigger with a failing `when` does not fire.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** `fire` builds the list of sources for the battler (its active passive's def, then `held_def` unless the item is `per_battle` and `held_spent`), runs the existing trigger loop over each (adding the `when` check via `when_holds(b, t.when)` before the chance roll), emits `emit_passive`-style events with `item` for the item source, and after a held trigger actually fires: `consumed` clears `b.creature.held_item` and emits `ITEM_CONSUMED`; `per_battle` sets `b.held_spent`. The do-nothing skip and chance failure `continue` before any of this, so they never use the item. `BattleEvents.ITEM_CONSUMED` registered in `ALL`. `BattleText` and `BattlePlayback` handle `item_consumed` as a plain message (no banner); the `PASSIVE_TRIGGERED` banner path already works from Task 3.
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 5: AI reads held-item retaliation

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_retaliation`)
- Test: `tests/battle/test_ai_passives.gd`

**Interfaces:**
- Consumes: `PassiveRules.held_def`, `Battler.held_spent`, `ItemDef.held_use` (Tasks 3–4).

- [ ] **Step 1: Write failing tests** in `test_ai_passives.gd` (add held fixture items to its `before()`): `test_retaliation_prices_a_held_item_hit_trigger` (a foe holding a `permanent` item whose `hit` trigger burns the attacker scores a tactician contact hit lower than a plain foe); `test_retaliation_cancelled_by_attackers_protection_for_items`; `test_spent_per_battle_item_adds_no_retaliation` (set `held_spent = true`); `test_consumed_item_costs_the_same_as_a_permanent_one_for_this_hit` (a `consumed` and a `permanent` item with the same `hit` trigger lower the score by the same amount); `test_trigger_when_gates_the_estimate` (a `when` that fails now adds no cost).
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** `_retaliation` iterates the foe's passive def and, unless `held_spent`, its held def, applying the same per-trigger costing and now skipping triggers whose `when` fails (`passive_rules.when_holds(t_battler, trig.when)`).
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 6: Summary give, swap and take back; bag marker

**Files:**
- Modify: `game/progress/summary_screen.gd` (stats tab line and actions, `_act`), `game/overworld/ui/pause_menu.gd` (`_bag`)
- Test: `tests/world/test_summary_screen.gd`

**Interfaces:**
- Consumes: `HeldItems.give/take/def_of` (Task 2).

- [ ] **Step 1: Write failing tests** (the real db is shared and Task 7's content does not exist yet: in `before_test` add two test held items to `DataRegistry.db` and give them to the player through `GameState.current.inventory`, and remove them again in `after_test`):
  - `test_summary_shows_the_held_item_line`: "Held item: none" and, after giving, the item's name and description.
  - `test_give_from_the_summary`: pick the Give action, pick an item from the picker; the creature holds it and the bag count drops.
  - `test_swap_and_take_back_conserve_items` (Review Focus 3, through the UI).
  - `test_give_is_offered_only_with_held_items_in_the_bag`.
  - `test_unknown_held_id_shows_a_fallback` (Review Focus 4): a creature holding `"ghost"` shows the raw id (or "unknown item") without error and Take back still works.
  - `test_summary_fits_with_a_long_item_name_and_description`: `ScreenFit.check` with a held item whose name and description are long, all stats trained.
  - A pause-menu bag test: opening a held item from the bag shows its description and "Give it from the Summary." and no "Use on who?" prompt.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect the new tests to fail.
- [ ] **Step 3: Implement.** Stats tab: add a "Held item" line (name and description; `none`; the id when `def_of` is null). Options: Give (when the bag holds any `held` item), Swap (when one is held and the bag has another) and Take back (when one is held), each a `{"held": "give" | "swap" | "take"}` value handled in `_act`: the give/swap path lists the bag's `held` items (`"%s ×%d"`) with Back, then calls `HeldItems.give`; take calls `HeldItems.take`; both set `_notice` like the other actions. `PauseMenu._bag`: for a `held` item, the existing non-usable page appends "Give it from the Summary."
- [ ] **Step 4:** Run `bash scripts/check.sh`; expect "All checks passed."

### Task 7: Content, compendium, docs and tour

**Files:**
- Create: `data/items/held.json`, `.claude/skills/run-godot-monster-catching-game/tours/held.gd`
- Modify: `tools/generate_compendium.gd`, `.claude/skills/run-godot-monster-catching-game/driver.gd` and `SKILL.md` (register `--mode=held`), `documentation/battle-engine.md`, `documentation/specs/2026-11-03-monster-rpg-design.md`, `documentation/specs/2026-11-05-held-items-design.md` (Status), `.superpowers/HANDOFF.md`
- Test: `tests/data/test_held_items_data.gd` (shipped-content test)

- [ ] **Step 1: Write a failing shipped-content test**: `test_shipped_held_items_cover_every_usage_kind`: loading `res://data` yields at least one `held` item of each `use` kind, one with an aura `scope`, one with a `field` op, and no validation errors or warnings.
- [ ] **Step 2:** Run `bash scripts/check.sh`; expect that test to fail.
- [ ] **Step 3: Content.** `data/items/held.json` with about five items (names and values are yours to choose, within the existing balance): a permanent charm (`stat_mod` or `type_power`), a `consumed` berry (`hit` trigger, `when: {hp_below: 0.5}`, `heal`), a `per_battle` item (a `hit` trigger that lowers the attacker's stat), a permanent item with a `field` op (for example `encounter_rate`), and an aura item (`scope: allies`, `incoming_type_mod`). Give each a price, description, and place them in at least one shop or pickup so the player can find them (follow how `training.json`'s Reset Seed is stocked).
- [ ] **Step 4: Compendium.** `generate_compendium.gd` gets a "Held items" section: each item's usage kind, aura scope, effects, triggers (with `when`) and field ops, in the same style as the passives section.
- [ ] **Step 5: Tour.** `tours/held.gd`, modelled on `tours/passives.gd`: new game, F1, get the test party and a held item, Summary → Give, check the Summary line, start a debug battle where the item fires (a banner naming the item, and for a `consumed` item the "used up" message), return to the Summary and check the item is gone. Register `--mode=held` in `driver.gd` and document it in `SKILL.md`.
- [ ] **Step 6: Docs.** `battle-engine.md`: held items as a trigger/effect source, `ITEM_CONSUMED`, trigger `when`, usage kinds. Main spec: items and creatures sections. Spec Status becomes `Implemented (plan: ...)`. `HANDOFF.md`: replace the held-items pointer with what shipped and what is not done.
- [ ] **Step 7: Verify.** Run the tour (`timeout 300 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=held --out="$TEMP/held_shots" 2>&1 | grep "\[driver\]"`), read the screenshots to confirm the banner, message and Summary render, then `bash scripts/check.sh` must end "All checks passed." Then give the user the commit message.
