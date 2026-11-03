# Content Compendium

> Generated from `data/` by `tools/generate_compendium.gd`. Do not edit by hand;
> change the JSON and regenerate.

| Category | Count |
|---|---|
| [Creatures](#creatures) | 8 |
| [Moves](#moves) | 21 |
| [Items](#items) | 4 |
| [Statuses](#statuses) | 4 |
| [Field States](#field-states) | 5 |
| [Reactions](#reactions) | 4 |
| [Types](#types) | 7 |
| [Affinities](#affinities) | 4 |
| [Tamers](#tamers) | 2 |
| [Encounters](#encounters) | 1 |

## Types

Damage multiplier when the **row** type attacks the **column** type. Blank means x1.

| Attacker \ Defender | Earth | Electric | Fire | Grass | Ice | Neutral | Water |
|---|---|---|---|---|---|---|---|
| **Earth** |  | x2 | x2 | x0.5 |  |  |  |
| **Electric** | x0 | x0.5 |  | x0.5 |  |  | x2 |
| **Fire** | x0.5 |  | x0.5 | x2 | x2 |  | x0.5 |
| **Grass** | x2 |  | x0.5 | x0.5 |  |  | x2 |
| **Ice** | x2 |  | x0.5 | x2 | x0.5 |  |  |
| **Neutral** | x0.75 |  |  |  |  |  |  |
| **Water** | x2 |  | x2 | x0.5 |  |  | x0.5 |

## Statuses

Conditions on a single creature. Each lasts a set number of rounds.

| Status | Id | Rounds | Effect | Description |
|---|---|---|---|---|
| **Burn** | `burn` | 4 | Loses 6.25% max HP each round | Loses a little HP each round. |
| **Chill** | `chill` | 3 | Spd x0.75 | Speed is reduced. |
| **Daze** | `daze` | 3 | Acc x0.8 | Accuracy is reduced. |
| **Shock** | `shock` | 3 | 25% chance to lose its action | May lose its action to muscle spasms. |

## Field States

Held per side (max 3 at once). Passive effects apply to every creature on that side.

| State | Id | Max stacks | Default rounds | Passive | Reacts with |
|---|---|---|---|---|---|
| **Charged** | `charged` | 3 | 3 | Electric damage taken x1.15 | Soaked → Conduction |
| **Frosted** | `frosted` | 3 | 4 | Acc x0.95 | Soaked → Icebound, Scorched → Steam |
| **Overgrown** | `overgrown` | 3 | 5 | Spd x0.9 | Scorched → Wildfire |
| **Scorched** | `scorched` | 3 | 3 | Grass damage taken x1.2; Ice damage taken x1.2 | Frosted → Steam, Overgrown → Wildfire |
| **Soaked** | `soaked` | 3 | 4 | Electric damage taken x1.25; Fire damage taken x0.75 | Charged → Conduction, Frosted → Icebound |

- **Charged:** Static crackles in the air.
- **Frosted:** Rime coats the ground. Footing is poor.
- **Overgrown:** Tangled growth slows everyone on this side.
- **Scorched:** Embers smoulder underfoot. Grass and ice suffer.
- **Soaked:** Ground is flooded. Electric hits harder here, fire fizzles.

## Reactions

Fire immediately when an incoming state meets one already on that side. "All allies" means every creature on the side where the reaction fired.

| Reaction | Inputs | Consumes | Scope | Effects |
|---|---|---|---|---|
| **Conduction** | Charged + Soaked | Charged | That side | Damage (power 40 Electric), scales with stacks consumed → all allies; Inflicts Shock (30%) → all allies |
| **Icebound** | Soaked + Frosted | Soaked | That side | Spd -2 → all allies; Inflicts Chill → all allies |
| **Steam** | Scorched + Frosted | Scorched, Frosted | Both sides | Acc -1 → everyone |
| **Wildfire** | Scorched + Overgrown | Overgrown | That side | Damage (power 30 Fire), scales with stacks consumed → all allies; Inflicts Burn → all allies |

- **Conduction:** Current races through the water, shocking everyone standing in it.
- **Icebound:** Standing water freezes solid around their feet.
- **Steam:** A scalding cloud blankets the whole battlefield.
- **Wildfire:** The undergrowth catches. Everything on this side burns.

## Affinities

Growth tracks filled by how a creature is used in battle. Growth branches need at least 30 points in the matching track.

| Affinity | Id | Grows from |
|---|---|---|
| **Catalyst** | `catalyst` | Grows from shaping the field and triggering reactions. |
| **Striker** | `striker` | Grows from dealing damage and landing finishing blows. |
| **Trickster** | `trickster` | Grows from statuses, debuffs, and making foes miss. |
| **Warden** | `warden` | Grows from absorbing hits, healing, and protecting allies. |

## Creatures

| Creature | Types | HP | Atk | Def | Spd | Total | Catch | XP |
|---|---|---|---|---|---|---|---|---|
| [Emberkit](#emberkit) | Fire | 45 | 50 | 40 | 60 | 195 | 45% | 55 |
| [Frostling](#frostling) | Ice | 50 | 45 | 50 | 45 | 190 | 40% | 55 |
| [Mistcoil](#mistcoil) | Water / Ice | 70 | 55 | 60 | 80 | 265 | 10% | 160 |
| [Pebblet](#pebblet) | Earth | 60 | 55 | 70 | 25 | 210 | 50% | 50 |
| [Sprigling](#sprigling) | Grass | 55 | 40 | 55 | 35 | 185 | 50% | 50 |
| [Tidepup](#tidepup) | Water | 50 | 45 | 45 | 50 | 190 | 40% | 60 |
| [Torrentusk](#torrentusk) | Water / Earth | 75 | 85 | 70 | 55 | 285 | 10% | 160 |
| [Voltmoth](#voltmoth) | Electric | 40 | 45 | 35 | 75 | 195 | 40% | 55 |

### Emberkit

`emberkit` · Fire

*Leaves smouldering pawprints wherever it runs.*

- **Base stats:** HP 45 · Atk 50 · Def 40 · Spd 60
- **Catch rate:** 45% base · **XP yield:** 55

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Tackle | Neutral | 40 | 100% |
| 1 | Ember Flick | Fire | 40 | 100% |
| 6 | Scorch Field | Fire | — | — |
| 11 | Flare Burst | Fire | 45 | 90% |

### Frostling

`frostling` · Ice

*A shy spirit that frosts the ground when startled.*

- **Base stats:** HP 50 · Atk 45 · Def 50 · Spd 45
- **Catch rate:** 40% base · **XP yield:** 55

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Frost Nip | Ice | 40 | 100% |
| 6 | Rime Veil | Ice | — | — |
| 14 | Glacier Crash | Ice | 80 | 85% |

### Mistcoil

`mistcoil` · Water / Ice

*A serpent of fog that turns battlefields into marshes.*

- **Base stats:** HP 70 · Atk 55 · Def 60 · Spd 80
- **Catch rate:** 10% base · **XP yield:** 160
- **Grows from:** Tidepup (Lv 16, Catalyst Affinity)

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Drench | Water | — | — |
| 1 | Rime Veil | Ice | — | — |
| 18 | Glacier Crash | Ice | 80 | 85% |

### Pebblet

`pebblet` · Earth

*Mistaken for a rock until it headbutts your shin.*

- **Base stats:** HP 60 · Atk 55 · Def 70 · Spd 25
- **Catch rate:** 50% base · **XP yield:** 50

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Pebble Toss | Earth | 40 | 100% |
| 1 | Brace | Neutral | — | — |
| 7 | Dust Sweep | Earth | — | — |
| 13 | Quake Stomp | Earth | 70 | 100% |

### Sprigling

`sprigling` · Grass

*A sprout that plants seeds in every footprint.*

- **Base stats:** HP 55 · Atk 40 · Def 55 · Spd 35
- **Catch rate:** 50% base · **XP yield:** 50

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Vine Lash | Grass | 45 | 100% |
| 4 | Seed Carpet | Grass | — | — |
| 8 | Regrowth | Grass | — | — |

### Tidepup

`tidepup` · Water

*A pup that splashes puddles into its foes' paths.*

- **Base stats:** HP 50 · Atk 45 · Def 45 · Spd 50
- **Catch rate:** 40% base · **XP yield:** 60
- **Grows into:** Lv 16 → **Torrentusk** (Striker Affinity); Lv 16 → **Mistcoil** (Catalyst Affinity); Lv 16 → **Torrentusk** (default)

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Tackle | Neutral | 40 | 100% |
| 1 | Splash Jab | Water | 40 | 100% |
| 5 | Drench | Water | — | — |
| 9 | Riptide | Water | 55 | 95% |
| 12 | Taunting Howl | Neutral | — | 100% |

### Torrentusk

`torrentusk` · Water / Earth

*Grew up charging through floods, tusks first.*

- **Base stats:** HP 75 · Atk 85 · Def 70 · Spd 55
- **Catch rate:** 10% base · **XP yield:** 160
- **Grows from:** Tidepup (Lv 16, Striker Affinity), Tidepup (Lv 16, default)

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Splash Jab | Water | 40 | 100% |
| 1 | Riptide | Water | 55 | 95% |
| 18 | Quake Stomp | Earth | 70 | 100% |

### Voltmoth

`voltmoth` · Electric

*Its wingbeats leave the air prickling with static.*

- **Base stats:** HP 40 · Atk 45 · Def 35 · Spd 75
- **Catch rate:** 40% base · **XP yield:** 55

| Lv | Move | Type | Power | Acc |
|---|---|---|---|---|
| 1 | Spark Bite | Electric | 45 | 100% |
| 5 | Static Field | Electric | — | — |
| 12 | Thunder Cascade | Electric | 50 | 90% |

## Moves

Grouped by type. Effects run top to bottom; `bonus_if_field` modifiers apply to the damage or heal after them.

### Earth moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Dust Sweep** | `dust_sweep` | Status | — | — | 0 | Own side | Clears all states from own side<br>*Clears every state from your own side.* | Pebblet |
| **Pebble Toss** | `pebble_toss` | Physical | 40 | 100% | 0 | One enemy | Damage | Pebblet |
| **Quake Stomp** | `quake_stomp` | Physical | 70 | 100% | 0 | Everyone | Damage<br>*Shakes the whole field, allies included.* | Pebblet, Torrentusk |

### Electric moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Spark Bite** | `spark_bite` | Physical | 45 | 100% | 0 | One enemy | Damage; Inflicts Shock (15%) | Voltmoth |
| **Static Field** | `static_field` | Status | — | — | 0 | Enemy side | Applies Charged to the enemy side<br>*Charges the air over the enemy side.* | Voltmoth |
| **Thunder Cascade** | `thunder_cascade` | Special | 50 | 90% | 0 | All enemies | x1.4 if the target's side is Charged; Damage | Voltmoth |

### Fire moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Ember Flick** | `ember_flick` | Special | 40 | 100% | 0 | One enemy | Damage; Inflicts Burn (10%) | Emberkit |
| **Flare Burst** | `flare_burst` | Special | 45 | 90% | 0 | All enemies | x1.6 if the target's side is Scorched (consumes it); Damage<br>*Hits every foe; far stronger on a Scorched side.* | Emberkit |
| **Scorch Field** | `scorch_field` | Status | — | — | 0 | Enemy side | Applies Scorched to the enemy side<br>*Sets the enemy side smouldering.* | Emberkit |

### Grass moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Regrowth** | `regrowth` | Status | — | — | 0 | Self | x1.5 if own side is Overgrown; Heals 33% max HP<br>*Heals; heals more on your own Overgrown side.* | Sprigling |
| **Seed Carpet** | `seed_carpet` | Status | — | — | 0 | Enemy side | Applies Overgrown to the enemy side<br>*Grows a thicket on the enemy side.* | Sprigling |
| **Vine Lash** | `vine_lash` | Physical | 45 | 100% | 0 | One enemy | Damage | Sprigling |

### Ice moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Frost Nip** | `frost_nip` | Physical | 40 | 100% | 0 | One enemy | Damage; Inflicts Chill (20%) | Frostling |
| **Glacier Crash** | `glacier_crash` | Physical | 80 | 85% | 0 | One enemy | Damage | Frostling, Mistcoil |
| **Rime Veil** | `rime_veil` | Status | — | — | 0 | Enemy side | Applies Frosted to the enemy side<br>*Coats the enemy side in frost.* | Frostling, Mistcoil |

### Neutral moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Brace** | `brace` | Status | — | — | 0 | Self | Def +1<br>*Raises Defense.* | Pebblet |
| **Tackle** | `tackle` | Physical | 40 | 100% | 0 | One enemy | Damage | Emberkit, Tidepup |
| **Taunting Howl** | `taunting_howl` | Status | — | 100% | 0 | All enemies | Atk -1<br>*Lowers every foe's Attack.* | Tidepup |

### Water moves

| Move | Id | Cat. | Power | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|
| **Drench** | `drench` | Status | — | — | 0 | Enemy side | Applies Soaked to the enemy side<br>*Floods the enemy side.* | Mistcoil, Tidepup |
| **Riptide** | `riptide` | Physical | 55 | 95% | 0 | One enemy | x1.5 if the target's side is Soaked (consumes it); Damage<br>*Stronger on a Soaked side, draining the water.* | Tidepup, Torrentusk |
| **Splash Jab** | `splash_jab` | Physical | 40 | 100% | 0 | One enemy | Damage | Tidepup, Torrentusk |

## Items

| Item | Id | Category | Price | Target | Effects | Description |
|---|---|---|---|---|---|---|
| **Lure Cage** | `lure_cage` | Capture | 100 | One enemy | Capture x1 | A plain woven cage. Works anywhere. |
| **Salve** | `salve` | Heal | 150 | One ally | Heals 33% max HP | Restores a third of a creature's HP. |
| **Snare Vine** | `snare_vine` | Capture | 250 | One enemy | Capture x0.8, x2.5 on Overgrown | Far more effective on an Overgrown side. |
| **Tide Net** | `tide_net` | Capture | 250 | One enemy | Capture x0.8, x2.5 on Soaked | Far more effective on a Soaked side. |

## Tamers

NPC opponents. *Max active* is how many creatures they field at once.

### Rival

`rival_01` · Max active **2** · AI `tactician` · Reward 500

| Creature | Lv | Moves |
|---|---|---|
| Voltmoth | 7 | Spark Bite, Static Field |
| Frostling | 7 | Frost Nip, Rime Veil *(latest learnset)* |

**Items:** Salve x1

### Scout Ana

`scout_ana` · Max active **1** · AI `basic` · Reward 200

| Creature | Lv | Moves |
|---|---|---|
| Sprigling | 5 | Vine Lash, Seed Carpet *(latest learnset)* |
| Emberkit | 6 | Tackle, Ember Flick, Scorch Field *(latest learnset)* |

## Encounters

Wild encounter tables. Chance is per creature in the pack.

### Route 1 tall grass

`route_01_grass` · Pack size 1–2

| Creature | Chance | Levels |
|---|---|---|
| Sprigling | 35% | 2–5 |
| Emberkit | 25% | 3–5 |
| Voltmoth | 20% | 3–6 |
| Pebblet | 15% | 3–6 |
| Frostling | 5% | 5–7 |

## Balance

Global tuning values from `data/balance.json`.

| Setting | Value |
|---|---|
| Level cap | 100 |
| Party size | 6 |
| Max moves per creature | 4 |
| Same-type attack bonus | x1.25 |
| Max field states per side | 3 |
| Growth Affinity threshold | 30 |
| Underdog spread reduction | 20% per ratio step, max 50% |
| Underdog stat bonus | 15% per ratio step, max 40% |
| Underdog XP bonus | 50% per ratio step |
| Catch HP weight | 0.8 |

