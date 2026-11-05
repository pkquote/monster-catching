# Creature Passives — Design

Date: 2026-11-04
Status: Implemented (plan: [documentation/plans/2026-11-04-passives.md](../plans/2026-11-04-passives.md))
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) §2 (battle rules), §2.5 (Affinity).
Builds on the [battle engine reference](../battle-engine.md) and the [M4 progression design](2026-11-04-m4-progression-design.md).

## 1. Goal

Give every creature a passive ability that changes how it plays: boosting a move type, setting a field
state when it enters, shrugging off stat drops, and so on. Each creature rolls one passive for life and
can unlock a second through Affinity; the player chooses which one is active. Only one passive is
active at a time.

**Success:** passives are content (JSON) built from a small set of effect types and triggers; a player
sees a passive fire in battle, unlocks an Affinity passive after a battle, switches between the two on
the Summary, and the lead creature's passive affects the overworld. Every effect type and trigger is
covered by tests and a real-window tour.

### Decisions

| Topic | Decision |
|---|---|
| Passive families | Always-on (type power, stat boost, type resistance, conditional boosts), triggered (enter, hit, round end, knockout, faint), protection (status immunity, stat-drop guard, field shelter), game-specific (field crafter, energy saver, ally aura, overworld field abilities) |
| Rolled passive | Each species lists 1–2; a creature rolls one when it is made and keeps it for life |
| Affinity passive | Each species lists passives per Affinity track. The first time one of the creature's tracks reaches the growth threshold (30) and the species has a passive for it, that passive unlocks for good. One unlock per creature |
| Active passive | One active at a time. Unlocking adds an option; the player picks rolled or Affinity (after-battle prompt, Summary). Only the active passive does anything |
| Stacking | Multipliers from different sources multiply; the same aura from two allies counts once; triggered effects never set off further passive triggers |
| Overworld | `field` effects of the party lead's active passive apply |

### Out of scope

Foe-passive details in the compendium beyond listing each species' passives; tamer AI that plays
around passives; passive-changing items; breeding or inheritance; more than one active passive.

## 2. Data

### 2.1 Passive definitions (`data/passives/*.json`, category `passives`)

```json
{ "id": "tidal_heart", "name": "Tidal Heart", "description": "Water moves hit 20% harder.",
  "scope": "self",
  "effects":  [ { "op": "type_power", "type": "water", "mult": 1.2 } ],
  "triggers": [ { "on": "enter", "chance": 100,
                  "effects": [ { "op": "apply_field_state", "side": "enemy", "state": "soaked" } ] } ],
  "field":    [ { "op": "encounter_rate", "mult": 0.8 } ] }
```

| Field | Meaning |
|---|---|
| `scope` | `"self"` (default) or `"allies"`: an aura that applies its `effects` to every creature on the same side's field, itself included |
| `effects` | Always-on effects (§3.1–3.4), each with an optional `when` condition |
| `triggers` | `{ on, chance? (1–100, default 100), contact? (hit only), effects }`; `effects` reuse the existing effect ops |
| `field` | Overworld effects (§3.5) |

All of `effects`, `triggers` and `field` are optional; a passive needs at least one. The validator checks
ops, fields, references, `on` values and `when` keys like every other content category.

### 2.2 Species

`data/creatures/*.json` entries gain:

- `"passives": [id, id?]`: one or two possible rolled passives (required).
- `"affinity_passives": { track: id }`: any subset of the Affinity tracks (optional).

### 2.3 Creatures and saves

`CreatureInstance` gains `passive: String` (rolled), `affinity_passive: String` ("" until unlocked) and
`active_passive: String` (`"rolled"` or `"affinity"`, default `"rolled"`).

- **Rolling:** `CreatureInstance.create` rolls `passive` uniformly from the species list with a passed
  RNG (wild, caught, given, starter and tamer creatures alike). A tamer's party entry may name a
  `passive` to fix it.
- **Growth:** the rolled passive keeps its position in the list (first → first, second → second, or the
  new species' first if it lists only one). The Affinity passive switches to the new species' passive for
  the same track if there is one, otherwise it is kept. `active_passive` is unchanged.
- **Save schema v4:** the migration fills `passive` for every creature from its species list,
  deterministically (an index from a hash of the creature's species, level and XP), unlocks
  `affinity_passive` for any creature already at 30+ in a track (the highest such track; ties by track
  order), and sets `active_passive` to `"rolled"`. Unknown species keep empty passives (logged).

## 3. Effect types

### 3.1 Always on

| Op | Fields | Effect |
|---|---|---|
| `type_power` (new) | `type`, `mult` | The creature's moves of `type` deal ×`mult` |
| `stat_mod` (exists) | `stat`, `mult` | Stat ×`mult` |
| `incoming_type_mod` (exists; now also from creatures) | `type` (optional: omitted = all damage), `mult` | Damage taken ×`mult` |

Any always-on effect may carry `when`:

| `when` | True while |
|---|---|
| `{"hp_below": f}` | HP is below `f` × max HP |
| `{"underdog": true}` | its side is outnumbered |
| `{"field": state, "side": "own" \| "enemy"}` | that state is on that side |

Conditions are checked on every read, so effects switch on and off as things change.

### 3.2 Triggers

| `on` | Fires | Default target |
|---|---|---|
| `enter` | when it is placed on the field (battle start, swap, replacement). At battle start all entry triggers fire after both sides are placed, fastest first | `self` |
| `hit` | after it takes damage and is still standing; `contact: true` = physical moves only | `attacker` |
| `round_end` | end of each round while on the field, before field states tick | `self` |
| `knockout` | it knocks out a foe | `self` |
| `faint` | it faints | `attacker` (side ops use `side`) |

Trigger effects reuse `apply_field_state`, `stat_stage`, `apply_status`, `heal`, `restore_energy`,
`damage_fraction`, with the existing `target` override (`self`, `attacker`, `all_allies`, `all_enemies`).
New op `absorb_type` (`type`, `fraction`): damage of `type` heals `fraction` × max HP instead.

### 3.3 Protection

| Op | Fields | Effect |
|---|---|---|
| `status_immune` | `status` (optional: omitted = every status) | The status can't be inflicted |
| `guard_stages` | `stat` (optional) | Foes can't lower its stages; its own moves still can |
| `field_shelter` | `state` | That state's passives don't affect it, and reactions involving that state don't damage it |

### 3.4 Game-specific

| Op | Fields | Effect |
|---|---|---|
| `field_boost` | `stacks`, `turns` | Field states it applies get +`stacks` and +`turns` |
| `reaction_power` | `mult` | Reactions its states trigger deal ×`mult` |
| `energy_discount` | `type` (optional), `amount` | Moves (of `type`) cost `amount` less energy, never below 0 |
| `rest_bonus` | `fraction` | Rest restores an extra `fraction` of max energy |
| `scrap_power` | `mult` | Scrap deals ×`mult` |

With `scope: "allies"`, all always-on, protection and game-specific effects apply to allies on the field.
Triggers stay on the creature itself.

### 3.5 Overworld (`field`, the party lead's active passive)

| Op | Fields | Effect |
|---|---|---|
| `encounter_rate` | `mult` | Wild encounter rate ×`mult` (`EncounterRoller`) |
| `xp_mult` | `mult` | XP the party earns ×`mult` (battle rewards) |
| `bond_gain` | `mult` | Bond gains (not losses) ×`mult` |

### 3.6 Stacking and safety

Multipliers from different sources (own passive, ally auras, field states, statuses) multiply. An aura
from two allies with the same passive id counts once. Effects run by a trigger never fire further
passive triggers (a depth guard), so passives can't loop.

## 4. Engine

- New battle part `PassiveRules` (`core/battle/passive_rules.gd`), beside `ActionRunner`, `FieldRules`
  and `BattleRewards`.
- `BattleEngine.passives(b)` additionally returns the active passive's `effects` (when their `when` holds)
  and allied auras. `BattleMath.damage` reads the attacker's `type_power` and the target's own
  `incoming_type_mod`; `effective_stat` already reads `stat_mod` from `passives(b)`.
- Hooks: `place()` → `enter`; `deal_damage()` → `hit` and `absorb_type`; the faint check → `knockout` and
  `faint`; end of round → `round_end`; `inflict_status()` → `status_immune`; `shift_stage()` from a foe
  → `guard_stages`; `FieldRules.apply()` → `field_boost`; reaction damage → `reaction_power` and
  `field_shelter`; `ActionRunner` move cost / Rest / Scrap → `energy_discount`, `rest_bonus`,
  `scrap_power`.
- Events: `PASSIVE_TRIGGERED { bid, passive }` whenever a passive visibly acts (a trigger fires, a status or
  stat drop is blocked, a hit is absorbed); silent for always-on multipliers. `PASSIVE_UNLOCKED
  { bid, passive }` when an Affinity track first reaches 30 in battle. Both get `BattleText` lines.
- Unlocking lives in `Progression.award_affinity`: when a track crosses the threshold for the first time,
  the creature has no `affinity_passive`, and the species lists one for that track, it is set.
  `ProgressEntry` gains `unlocked_passive: String`.

## 5. Screens

- **Battle:** a small banner over the creature when `PASSIVE_TRIGGERED` plays ("Tidepup's Tidal Heart!"),
  then the effect's own message. The command screen shows each player creature's active passive name.
- **After-battle step:** for an entry with `unlocked_passive`, a **Passive Unlocked** screen: "Tidepup
  awakened Riptide Rush!", both passives' descriptions, **Switch to it** / **Keep current**. It runs after
  Learn Move and before Grow.
- **Summary (Stats tab):** the active passive's name and description; the other one greyed ("Not active")
  or, before an unlock, a hint ("Unlocks when a track reaches 30"). "Use <other passive>" switches,
  anywhere outside battle.
- **Party screen:** "Lead passive: …" when the lead's active passive has `field` effects.

## 6. Starting content

16 rolled passives (two per species) and 4 shared Affinity passives (every species lists all four).

| Species | Rolled A | Rolled B |
|---|---|---|
| Tidepup | Tidal Heart: Water moves ×1.2 | Undertow: on entering, Soaked on the enemy side; overworld ×0.8 encounters |
| Torrentusk | Tidal Heart | Bulwark Hide: Earth damage taken ×0.7; foes can't lower its Physical Defense |
| Mistcoil | Fog Weaver: field states it applies +1 turn | Chill Skin: hit by a physical move, 30% Chill the attacker |
| Emberkit | Kindling: below 1/3 HP, Fire moves ×1.5 | Ember Trail: on fainting, Scorched on the enemy side |
| Sprigling | Photosynth: end of round, heal 1/16; overworld Bond gains ×1.25 | Rootbed: on entering, Overgrown on its own side; can't be Dazed |
| Voltmoth | Static Wings: Electric moves cost 2 less | Lightning Rod: Electric damage heals 25% instead |
| Frostling | Frost Guard: can't be Chilled; Ice damage taken ×0.5 | Cold Snap: on a knockout, +1 Speed; overworld XP ×1.1 |
| Pebblet | Sturdy: foes can't lower its stats | Rubble Pile: while outnumbered, Physical Defense ×1.3 |

| Track | Affinity passive |
|---|---|
| Striker | Finisher: on a knockout, restore 15% energy; Scrap ×1.5 |
| Warden | Guardian Aura (aura): all damage taken ×0.9 |
| Catalyst | Reaction Spark: reactions it triggers ×1.3; its field states +1 stack |
| Trickster | Slippery: can't be given a status; Rest restores +15% |

Exact numbers are first-pass balance and live in the data.

## 7. Debug tools (F1)

- **Set Affinity** also performs the unlock (as reaching 30 in battle would).
- **Set passive...**: pick a party creature, a passive id and the slot (rolled / Affinity), and whether to
  make it active.

## 8. Testing

- **Data:** validator rules (unknown ids, ops, `on`, `when` keys, missing `passives`); rolling;
  growth carry-over; v3 → v4 migration.
- **Engine:** every always-on op and `when` condition switching; each trigger; `absorb_type`;
  `status_immune`; `guard_stages` (own moves still lower own stats); `field_shelter`; the game-specific
  ops; auras (counted once); the no-chaining guard; only the active passive applies.
- **Progression and screens:** unlock happens once and only for listed tracks; the Passive Unlocked screen
  (Switch / Keep) and its place in the after-battle order; the Summary switch.
- **Overworld:** the lead's encounter, XP and Bond effects.
- **Tour:** a passive banner in battle, the unlock screen, switching on the Summary.
