# Status-cure op (M6)

Status: Implemented (plan: [documentation/plans/2026-11-06-m6-status-cure.md](../plans/2026-11-06-m6-status-cure.md)).

## Goal
Add a `cure_status` effect op so a real "full cure" item can exist (the test pack's `tp_full_restore`
stands in today), usable in battle, from the bag and from passive and held-item triggers. Add a `status`
trigger so a held item can cure the status it was just given. Ship one real item, Clear Tonic.

## Decisions
- Op: `{"op": "cure_status", "status"?: id}`. `status` is a ref to `statuses`, validated like
  `status_immune`'s. Omitted, it cures whatever status the target has; given, it cures only that one.
- A cure with nothing to cure (no status, a different status, or a fainted target) does nothing, emits
  nothing and spends nothing. This matches a heal at full HP.
- A cure earns no Affinity. Used from an item on an ally it earns the same Bond as a healing item
  (`healed_item`), and only when it actually cured something.
- New trigger `status` (added to `DataSchemas.TRIGGER_ON`). It fires from `inflict_status` right after
  `STATUS_APPLIED`, on the creature that received the status. `when` and `chance` work as on any trigger.
- The AI does not model the `status` trigger (same as enter, round-end, faint and knockout); this is
  documented in `documentation/battle-engine.md`.

## Engine
- `DataSchemas.EFFECT_OPS["cure_status"]`; handler `core/battle/effects/op_cure_status.gd`; registered in
  `EffectOps`; described in `EffectText.effect` (the compendium and bag share it).
- `BattleEngine.cure_status(target, status_id, from_item)`: if the target is alive and its status matches,
  clears `creature.status` and `Battler.status_turns`, emits `STATUS_ENDED` with a `cured: true` flag and
  awards `healed_item` Bond when `from_item`. The battle log reads "<Name> was cured of <Status>."
- `PassiveRules`: `_does_nothing` treats a `cure_status` whose targets have no matching status as doing
  nothing, so such a trigger is skipped with no banner and a consumed held item is not used up.
  `inflict_status` fires `status` triggers through the existing `fire` path (depth guard applies).

## Bag (`core/progress/field_items.gd`)
- `OPS` gains `cure_status`; the `fraction` requirement applies only to `heal` and `restore_energy`.
- `_would_gain` is true when the creature's status matches the effect. `usability` and `use` follow
  the existing flow: nothing to cure is `no_effect` and spends nothing; `use` returns a `cured` field.
- A combined heal + cure item works as a full restore.

## Battle items
No change. The battle item menu greys out only capture items (no room to catch), never heal items, so
cure items are listed and usable like Salve; using one on an unafflicted target does nothing but still
spends the item, as a heal at full HP does.

## AI (`core/battle/ai/battle_ai.gd`)
A `cure_status` effect on an afflicted ally is scored with the existing status-value weights; on a
creature with nothing to cure it scores zero. Documented under the AI section of `battle-engine.md`.

## Content
- Shipped: Clear Tonic (`data/items/healing.json`, category `heal`, target `one_ally`, effect
  `cure_status` with no `status`), stocked at the Town 1 shop (`tools/build_maps.gd` and
  `game/maps/town_01_center.tscn`). Price chosen during planning to sit with the other healing items.
- Test pack: `tp_full_restore` becomes a real full cure (heal, restore energy, cure) with a corrected
  description. New entries: a filtered cure item, a cure-any item, a cure move, a round-end cure
  passive, and a consumed held cure on the `status` trigger. The coverage guard
  (`tests/helpers/pack_coverage.gd`) requires the new op and trigger to be covered.

## Tests
- Unit: the op (match, mismatch, no status, fainted, filter), the engine event, Bond award, schema and
  validator (bad status ref), `EffectText`.
- Trigger: `status` fires once on application; a skipped cure does not use up a consumed item; the depth
  guard holds when a cure trigger is itself inside a trigger.
- Bag: `can_use`, `usability`, `use` for cure-only and combined items, including `no_effect`.
- AI: scores a cure on an afflicted ally and zero otherwise.
- Shipped content: Clear Tonic exists, is stocked in the Town 1 shop, and validates.
- Tour: use Clear Tonic from the bag on a burned creature (adds to the `bag` tour or a short new step).
- `bash scripts/check.sh` ends "All checks passed."; the compendium is regenerated.

## Out of scope
Statuses that persist differently out of battle, a multi-status cure list, an AI model for the `status`
trigger, and further cure content (M9).
