# Held Items — Design

Date: 2026-11-05
Status: Implemented (plan: [documentation/plans/2026-11-05-held-items.md](../plans/2026-11-05-held-items.md))
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) §2 (battle rules).
Builds on the [creature passives design](2026-11-04-passives-design.md) (the held item reuses its effect
machinery), the [M4 progression design](2026-11-04-m4-progression-design.md) (the Summary screen) and the
[battle engine reference](../battle-engine.md).

## 1. Goal

Let the player find items and give one to a creature to hold. A held item works like a second passive:
always-on effects, battle triggers and overworld effects. Some are used up when they fire. Held items add a
choice on top of the creature's own passive without a second effect system.

**Success:** a player finds a held item, gives it to a creature on the Summary, sees it act in battle
(a banner naming the item, and a message when it is used up), keeps or loses it afterwards according to
its kind, and takes it back or swaps it outside battle. Held items are content (JSON) built from the
same effect ops and triggers as passives. Every usage kind is covered by tests and a real-window tour.

### Decisions

| Topic | Decision |
|---|---|
| Slots | One held item per creature |
| Effect model | A held item is a passive-style definition (`effects`, `triggers`, `field`, aura `scope`) on its `items` entry, run by the same `PassiveRules` choke points as passives |
| Usage kinds | `permanent`, `consumed` (gone when it fires), `per_battle` (fires once per battle, kept) |
| Giving | Outside battle only, through the Summary; held items sit in the bag until given |
| Overworld | The party lead's held item contributes `field` ops, as the lead's passive does |
| Saves | Schema 5; `held_item` per creature, default `""` |
| Acquisition | Existing item pickups, shops and tamer rewards; no new systems |

## 2. Data

### 2.1 Items

An `items` entry with category `held` carries a `held` block (required for `held` items, rejected on any other
category):

```json
{ "id": "oran_berry", "name": "Oran Berry", "description": "Restores a third of HP once, when it drops below half.",
  "category": "held", "price": 200,
  "held": {
    "use": "consumed",
    "triggers": [ { "on": "hit", "when": { "hp_below": 0.5 }, "effects": [ { "op": "heal", "fraction": 0.33 } ] } ]
  } }
```

`held` fields (all the passive shapes, validated by the same rules):

| Field | Meaning |
|---|---|
| `use` | `permanent` (default), `consumed` or `per_battle` |
| `scope` | `self` (default) or `allies` (an aura, as for passives) |
| `effects` | Always-on effects, each may carry `when` |
| `triggers` | `{ on, chance, contact, when, effects }`, with the passives' `on` values |
| `field` | Overworld ops (`encounter_rate`, `xp_mult`, `bond_gain`) |

Rules: a `held` block needs at least one of `effects`, `triggers`, `field`. `consumed` and `per_battle` need at
least one trigger and may not have always-on `effects` (they would never be "used"). `ItemDef.held` holds the
parsed block; a held item has no `target` and no top-level `effects`, so it cannot be used from the bag.

### 2.2 Trigger `when`

Triggers (for passives and held items) get an optional `when` using the existing `when` keys (`hp_below`,
`underdog`, `field` with `side`), checked on the creature that owns the trigger when the trigger would fire
(`PassiveRules.when_holds`). A trigger whose `when` fails does not fire and does not use the item up.

### 2.3 Creatures and tamers

- `CreatureInstance.held_item: String` (item id or `""`), carried by `to_dict`, `from_dict` and `copy_from`.
- Tamer party entries get an optional `held_item` (a `held` item id), so enemy creatures can hold items. Wild
  creatures hold none.

## 3. Saves

`SaveGame.SCHEMA` becomes 5; the migration adds `held_item: ""` to every party and storage creature. Giving moves
one count out of `inventory` onto the creature; taking back returns it; a swap does both. A creature holding an
item whose id no longer exists in the data keeps the id but the item is ignored (like a missing passive), and
`GameState.load_from` logs a warning.

## 4. Battle

### 4.1 Sources

`PassiveRules` reads a creature's held item as a second source beside its active passive:

- `effects_for(b)` adds the held item's always-on effects (each when its `when` holds) and, for `scope: allies`,
  the auras of allies' held items on the field. Each item id is counted once per beneficiary, as for passives.
- `fire(b, on, ...)` runs the creature's passive triggers, then its held item's triggers for the same `on`.
- The depth guard, "never after the battle is over", "faint fires as the creature goes down", the do-nothing
  skip (a heal at full HP) and "trigger effects earn no Affinity" apply unchanged.

### 4.2 Using the item up

- **`consumed`:** when one of its triggers fires, after the effects run, `held_item` is cleared on the battle's
  working copy and `ITEM_CONSUMED` `{ bid, item }` is emitted. `BattleEngine.commit` copies the copy back, so
  the real creature loses the item. An item whose trigger does nothing (skipped as above) is not used up.
- **`per_battle`:** `Battler` records the item as spent after its first firing and it cannot fire again that
  battle. The creature keeps it; the next battle starts fresh.
- **`permanent`:** nothing is recorded.

### 4.3 Events and display

`PASSIVE_TRIGGERED` gains an optional `item` id; when present the banner and message name the item
("Tidepup's Oran Berry!"). `ITEM_CONSUMED` plays as a message ("Tidepup's Oran Berry was used up."), and
`BattleText`, `BattlePlayback` and `tests/game/test_battle_text.gd` cover both.

### 4.4 AI

The AI's damage, protection and absorb awareness read `effects_for`, so held items count automatically. Its
retaliation estimate (`BattleAI._retaliation`) also reads the foe's held-item `hit` triggers. A `consumed`
item counts once. Nothing else about the AI changes.

## 5. Overworld

`Passives.field_mult(db, save, op)` multiplies the party lead's passive `field` entries and the lead's
held-item `field` entries with that op (party[0], fainted or not; 1.0 when neither has one).

## 6. UI

- **Summary:** a "Held item" line (name and description, or "none") on the Stats tab, and actions Give (a picker
  of `held` items in the bag), Swap (when one is held) and Take back. These only exist outside battle, and work
  for fainted and benched creatures.
- **Bag:** held items are listed but marked "Give it from the Summary".
- **Debug (F1):** no new page. No F1 page gives items; the held tour (`--mode=held`) puts the item in `inventory` directly.
- **Compendium:** a held-items section listing each item's usage kind, effects, triggers and field ops.
- **Content:** about five starter items covering the three usage kinds (for example a permanent stat charm, a
  `consumed` low-HP berry, a `per_battle` item, an item with an overworld `field` op, and one aura item).

## 7. Out of scope

Two held slots, moves that steal or knock off items, giving items during battle, trading, item durability,
and held items on wild creatures.

## 8. Testing

- **Data:** schema and validator tests for the `held` block, `use` rules, trigger `when`, the tamer
  `held_item`, and unknown item ids; `ItemDef.held` parsing.
- **Battle:** always-on, trigger and aura held items through `effects_for` and `fire`; a failing `when` neither
  fires nor uses the item up; `consumed` clears the copy and the real creature after `commit`; `per_battle`
  fires once per battle and is kept; a do-nothing trigger does not use the item; trigger effects earn no
  Affinity; events and text.
- **Overworld:** the lead's held-item `field` ops multiply with its passive's.
- **Saves:** `to_dict` / `from_dict` round trip; the v4 to v5 migration; a creature with an unknown item id loads.
- **UI:** Summary give, swap and take back, inventory counts, fits the screen with a long item name and
  description; the bag marks held items.
- **AI:** retaliation prices a foe's held-item hit trigger and cancels it with the attacker's protection.
- **Regression:** a creature with no held item behaves exactly as before.
- Docs: update `battle-engine.md` (sources, events) and the main spec's item and creature sections.
