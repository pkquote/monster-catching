# Content Compendium

> Generated from `data/` by `tools/generate_compendium.gd`. Do not edit by hand;
> change the JSON and regenerate.

| Category | Count |
|---|---|
| [Creatures](#creatures) | 8 |
| [Moves](#moves) | 44 |
| [Items](#items) | 5 |
| [Statuses](#statuses) | 4 |
| [Field States](#field-states) | 12 |
| [Reactions](#reactions) | 8 |
| [Types](#types) | 14 |
| [Affinities](#affinities) | 4 |
| [Tamers](#tamers) | 2 |
| [Encounters](#encounters) | 1 |

## Types

14 types. Creatures can have up to 2, giving 105 possible single and dual types; 8 are in use so far.

### Type guide

*Pros* and *cons* are written in `data/types.json`. The matchup lines are computed from the chart below.

#### Neutral

*A blank slate. Ordinary creatures relying on plain strength and instinct, neither strong nor weak against anything.*

- **Pros:** Never resisted: hits every type for normal damage; No weaknesses at all; Pairs with any second type without adding weaknesses or changing matchups
- **Cons:** Never hits anything for bonus damage; Resists nothing
- **Hits hard:** —
- **Hits weakly:** —
- **Weak to:** —
- **Resists:** —
- **Creatures:** —

#### Fire

*Heat, flame and fury. Burns living things and melts metal.*

- **Pros:** Strong against Grass, Ice and Iron; Resists Fire, Grass, Ice and Iron; Natural fit for Scorched-field setups
- **Cons:** Weak to Water and Earth; Fizzles against Water, Earth and other Fire
- **Hits hard:** Grass, Ice, Iron
- **Hits weakly:** Fire, Water, Earth
- **Weak to:** Water, Earth
- **Resists:** Fire, Grass, Ice, Iron
- **Creatures:** Emberkit

#### Water

*Tides, rain and pressure. Quenches flame, erodes stone and shorts out machines.*

- **Pros:** Strong against Fire, Earth and Virtual; Resists Fire, Water and Iron; Sets up Soaked for Conduction and Icebound
- **Cons:** Weak to Grass and Electric; Absorbed by Grass and other Water
- **Hits hard:** Fire, Earth, Virtual
- **Hits weakly:** Water, Grass
- **Weak to:** Grass, Electric
- **Resists:** Fire, Water, Iron
- **Creatures:** Tidepup, Torrentusk, Mistcoil

#### Grass

*Roots, vines and growth. Drinks water and splits stone, but burns easily.*

- **Pros:** Strong against Water and Earth; Resists Water, Grass, Electric and Earth; Overgrown fields slow the enemy and fuel Wildfire
- **Cons:** Weak to Fire and Ice; Can't cut through Fire, Grass or Iron
- **Hits hard:** Water, Earth
- **Hits weakly:** Fire, Grass, Iron
- **Weak to:** Fire, Ice
- **Resists:** Water, Grass, Electric, Earth
- **Creatures:** Sprigling

#### Electric

*Lightning and current. Races through water and metal, and overloads machines.*

- **Pros:** Strong against Water, Iron and Virtual; Resists Electric, Iron and Virtual; Triggers Conduction on Soaked fields
- **Cons:** Weak to Earth; Has no effect at all on Earth; Dissipates into Grass and other Electric
- **Hits hard:** Water, Iron, Virtual
- **Hits weakly:** Grass, Electric
- **No effect on:** Earth
- **Weak to:** Earth
- **Resists:** Electric, Iron, Virtual
- **Creatures:** Voltmoth

#### Ice

*Frost and cold. Freezes plants and cracks the ground, but melts under heat.*

- **Pros:** Strong against Grass and Earth; Resists Ice; Frosted fields set up Icebound and Steam
- **Cons:** Weak to Fire and Iron; Struggles against Fire, Ice and Iron
- **Hits hard:** Grass, Earth
- **Hits weakly:** Fire, Ice, Iron
- **Weak to:** Fire, Iron
- **Resists:** Ice
- **Creatures:** Frostling, Mistcoil

#### Earth

*Stone, sand and soil. Grounds lightning, smothers fire and crushes metal.*

- **Pros:** Strong against Fire, Electric and Iron; Immune to Electric; Resists Fire
- **Cons:** Weak to Water, Grass and Ice; Can't touch what isn't solid: weak against Ghost and Grass
- **Hits hard:** Fire, Electric, Iron
- **Hits weakly:** Grass, Ghost
- **Weak to:** Water, Grass, Ice
- **Resists:** Fire
- **Immune to:** Electric
- **Creatures:** Pebblet, Torrentusk

#### Magic

*Arcane power, runes and enchantment. Banishes spirits and wards off darkness.*

- **Pros:** Strong against Ghost and Dark; Resists Magic, Dark and Virtual
- **Cons:** Weak to Mental and Iron (focus breaks spells; cold iron grounds them); Can't overcome Iron, Virtual or other Magic
- **Hits hard:** Ghost, Dark
- **Hits weakly:** Magic, Iron, Virtual
- **Weak to:** Mental, Iron
- **Resists:** Magic, Virtual, Dark
- **Creatures:** —

#### Mental

*Psychic force, willpower and illusion. Overwhelms simple minds and disrupts spellcasting.*

- **Pros:** Strong against Magic and Ghost; Resists Mental
- **Cons:** Weak to Ghost, Dark and Virtual: fragile defensively; Mental and Ghost are each strong against the other; Little effect on Iron, Dark, Virtual or other Mental
- **Hits hard:** Magic, Ghost
- **Hits weakly:** Mental, Iron, Virtual, Dark
- **Weak to:** Virtual, Ghost, Dark
- **Resists:** Mental
- **Creatures:** —

#### Iron

*Metal, armour and machinery. A defensive wall that shatters ice and grounds magic.*

- **Pros:** Resists Grass, Ice, Magic, Mental, Dark, Light and Iron; Strong against Ice and Magic
- **Cons:** Weak to Fire, Electric, Earth and Virtual; Few offensive targets; struggles against Fire, Water, Electric and Iron
- **Hits hard:** Ice, Magic
- **Hits weakly:** Fire, Water, Electric, Iron
- **Weak to:** Fire, Electric, Earth, Virtual
- **Resists:** Grass, Ice, Magic, Mental, Iron, Dark, Light
- **Creatures:** —

#### Virtual

*Digital constructs and living code. Hacks machines and floods minds with data.*

- **Pros:** Strong against Iron and Mental; Resists Magic, Mental and Virtual
- **Cons:** Weak to Water, Electric and Ghost (shorts, surges, and things in the machine); Can't parse Magic; weak against Electric, Ghost and other Virtual
- **Hits hard:** Mental, Iron
- **Hits weakly:** Electric, Magic, Virtual, Ghost
- **Weak to:** Water, Electric, Ghost
- **Resists:** Magic, Mental, Virtual
- **Creatures:** —

#### Ghost

*Spirits and echoes of the departed. Haunts minds and possesses machines; hard to pin down.*

- **Pros:** Strong against Mental and Virtual; Resists Earth and Virtual
- **Cons:** Weak to Magic, Light and Mental: Mental and Ghost are each strong against the other; Fades against Dark and Light
- **Hits hard:** Mental, Virtual
- **Hits weakly:** Dark, Light
- **Weak to:** Magic, Mental, Light
- **Resists:** Earth, Virtual
- **Creatures:** —

#### Dark

*Shadow, stealth and fear. Clouds the mind and swallows light.*

- **Pros:** Strong against Mental and Light; Resists Mental, Ghost and Dark
- **Cons:** Weak to Magic and Light; Held back by Magic wards, Iron and other Dark
- **Hits hard:** Mental, Light
- **Hits weakly:** Magic, Iron, Dark
- **Weak to:** Magic, Light
- **Resists:** Mental, Ghost, Dark
- **Creatures:** —

#### Light

*Radiance and purity. Dispels shadows and spirits, but glances off polished metal.*

- **Pros:** Strong against Dark and Ghost; Resists Ghost and Light; Only one weakness
- **Cons:** Weak to Dark: Light and Dark are each strong against the other; Only two offensive targets; Iron and other Light resist it
- **Hits hard:** Ghost, Dark
- **Hits weakly:** Iron, Light
- **Weak to:** Dark
- **Resists:** Ghost, Light
- **Creatures:** —

### Type chart

Damage multiplier when the **row** type attacks the **column** type. Blank means x1.

| Attacker \ Defender | Neutral | Fire | Water | Grass | Electric | Ice | Earth | Magic | Mental | Iron | Virtual | Ghost | Dark | Light |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Neutral** |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **Fire** |  | x0.5 | x0.5 | x2 |  | x2 | x0.5 |  |  | x2 |  |  |  |  |
| **Water** |  | x2 | x0.5 | x0.5 |  |  | x2 |  |  |  | x2 |  |  |  |
| **Grass** |  | x0.5 | x2 | x0.5 |  |  | x2 |  |  | x0.5 |  |  |  |  |
| **Electric** |  |  | x2 | x0.5 | x0.5 |  | x0 |  |  | x2 | x2 |  |  |  |
| **Ice** |  | x0.5 |  | x2 |  | x0.5 | x2 |  |  | x0.5 |  |  |  |  |
| **Earth** |  | x2 |  | x0.5 | x2 |  |  |  |  | x2 |  | x0.5 |  |  |
| **Magic** |  |  |  |  |  |  |  | x0.5 |  | x0.5 | x0.5 | x2 | x2 |  |
| **Mental** |  |  |  |  |  |  |  | x2 | x0.5 | x0.5 | x0.5 | x2 | x0.5 |  |
| **Iron** |  | x0.5 | x0.5 |  | x0.5 | x2 |  | x2 |  | x0.5 |  |  |  |  |
| **Virtual** |  |  |  |  | x0.5 |  |  | x0.5 | x2 | x2 | x0.5 | x0.5 |  |  |
| **Ghost** |  |  |  |  |  |  |  |  | x2 |  | x2 |  | x0.5 | x0.5 |
| **Dark** |  |  |  |  |  |  |  | x0.5 | x2 | x0.5 |  |  | x0.5 | x2 |
| **Light** |  |  |  |  |  |  |  |  |  | x0.5 |  | x2 | x2 | x0.5 |

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
| **Charged** | `charged` | 3 | 3 | Electric damage taken x1.15 | Soaked → Conduction, Glitched → Overload, Magnetized → Railstorm |
| **Enchanted** | `enchanted` | 3 | 4 | S.Def x1.15 | — |
| **Frosted** | `frosted` | 3 | 4 | Acc x0.95 | Soaked → Icebound, Scorched → Steam |
| **Glitched** | `glitched` | 3 | 3 | Virtual damage taken x1.2; Resolve x0.9 | Charged → Overload |
| **Haunted** | `haunted` | 3 | 4 | Resolve x0.8; Ghost damage taken x1.15 | Hazed → Nightmare |
| **Hazed** | `hazed` | 3 | 3 | S.Def x0.9; Mental damage taken x1.2 | Haunted → Nightmare |
| **Magnetized** | `magnetized` | 3 | 4 | Spd x0.9; Electric damage taken x1.15 | Charged → Railstorm |
| **Overgrown** | `overgrown` | 3 | 5 | Spd x0.9 | Scorched → Wildfire |
| **Radiant** | `radiant` | 3 | 4 | Dark damage taken x0.75; Ghost damage taken x0.75; Acc x1.1 | Shrouded → Eclipse |
| **Scorched** | `scorched` | 3 | 3 | Grass damage taken x1.2; Ice damage taken x1.2 | Frosted → Steam, Overgrown → Wildfire |
| **Shrouded** | `shrouded` | 3 | 3 | Acc x0.85 | Radiant → Eclipse |
| **Soaked** | `soaked` | 3 | 4 | Electric damage taken x1.25; Fire damage taken x0.75 | Charged → Conduction, Frosted → Icebound |

- **Charged:** Static crackles in the air.
- **Enchanted:** Glowing runes ward this side against spells and beams. Cast it on your own side.
- **Frosted:** Rime coats the ground. Footing is poor.
- **Glitched:** Corrupted data flickers across this side. Code finds its way in.
- **Haunted:** Restless spirits whisper here, wearing down the will to resist.
- **Hazed:** A psychic fog dulls every mind on this side.
- **Magnetized:** Iron filings cling to everything, weighing creatures down and drawing in current.
- **Overgrown:** Tangled growth slows everyone on this side.
- **Radiant:** Warm light bathes this side, sharpening aim and burning away shadow. Cast it on your own side.
- **Scorched:** Embers smoulder underfoot. Grass and ice suffer.
- **Shrouded:** Thick shadow makes it hard to see what you're aiming at.
- **Soaked:** Ground is flooded. Electric hits harder here, fire fizzles.

## Reactions

Fire immediately when an incoming state meets one already on that side. "All allies" means every creature on the side where the reaction fired.

| Reaction | Inputs | Consumes | Scope | Effects |
|---|---|---|---|---|
| **Conduction** | Charged + Soaked | Charged | That side | Damage (power 60 Electric), scales with stacks consumed → all allies; Inflicts Shock (30%) → all allies |
| **Eclipse** | Shrouded + Radiant | Shrouded, Radiant | Both sides | Inflicts Daze (50%) → everyone |
| **Icebound** | Soaked + Frosted | Soaked | That side | Spd -2 → all allies; Inflicts Chill → all allies |
| **Nightmare** | Haunted + Hazed | Hazed | That side | Damage (power 45 Mental), scales with stacks consumed → all allies; Resolve -2 → all allies |
| **Overload** | Glitched + Charged | Glitched, Charged | That side | Damage (power 45 Virtual), scales with stacks consumed → all allies; Inflicts Shock (40%) → all allies |
| **Railstorm** | Magnetized + Charged | Magnetized | That side | Damage (power 55 Electric), scales with stacks consumed → all allies |
| **Steam** | Scorched + Frosted | Scorched, Frosted | Both sides | Acc -1 → everyone |
| **Wildfire** | Scorched + Overgrown | Overgrown | That side | Damage (power 45 Fire), scales with stacks consumed → all allies; Inflicts Burn → all allies |

- **Conduction:** Current races through the water, shocking everyone standing in it.
- **Eclipse:** Light and shadow collide, and the whole field goes dark and dazzling at once.
- **Icebound:** Standing water freezes solid around their feet.
- **Nightmare:** The spirits slip into fogged minds and the haze turns into terror.
- **Overload:** A surge hits corrupted data and everything shorts out at once.
- **Railstorm:** Current arcs through the magnetized filings, flinging them like shrapnel.
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

Base stats. *Total* sums the six battle stats (HP to Spd); Luck, Resolve and Stamina are listed separately.

| Creature | Types | HP | P.Atk | P.Def | S.Atk | S.Def | Spd | Luck | Resolve | Stamina | Total | Catch | XP |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [Emberkit](#emberkit) | Fire | 45 | 45 | 40 | 60 | 45 | 60 | 55 | 40 | 50 | 295 | 45% | 55 |
| [Frostling](#frostling) | Ice | 50 | 50 | 50 | 45 | 55 | 45 | 50 | 55 | 50 | 295 | 40% | 55 |
| [Mistcoil](#mistcoil) | Water / Ice | 70 | 45 | 55 | 80 | 70 | 80 | 55 | 55 | 60 | 400 | 10% | 160 |
| [Pebblet](#pebblet) | Earth | 60 | 55 | 75 | 30 | 45 | 25 | 40 | 70 | 60 | 290 | 50% | 50 |
| [Sprigling](#sprigling) | Grass | 55 | 45 | 55 | 40 | 60 | 35 | 45 | 60 | 55 | 290 | 50% | 50 |
| [Tidepup](#tidepup) | Water | 50 | 45 | 45 | 50 | 45 | 50 | 50 | 45 | 55 | 285 | 40% | 60 |
| [Torrentusk](#torrentusk) | Water / Earth | 75 | 85 | 70 | 45 | 55 | 55 | 45 | 65 | 70 | 385 | 10% | 160 |
| [Voltmoth](#voltmoth) | Electric | 40 | 40 | 35 | 60 | 40 | 75 | 60 | 40 | 45 | 290 | 40% | 55 |

### Emberkit

`emberkit` · Fire

*Leaves smouldering pawprints wherever it runs.*

- **Base stats:** HP 45 · P.Atk 45 · P.Def 40 · S.Atk 60 · S.Def 45 · Spd 60 · Luck 55 · Resolve 40 · Stamina 50
- **Catch rate:** 45% base · **XP yield:** 55

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Tackle | Neutral | Physical | 40 | 1 | 100% |
| 1 | Ember Flick | Fire | Special | 40 | 2 | 100% |
| 6 | Scorch Field | Fire | Status | — | 4 | — |
| 11 | Flare Burst | Fire | Special | 45 | 7 | 90% |

### Frostling

`frostling` · Ice

*A shy spirit that frosts the ground when startled.*

- **Base stats:** HP 50 · P.Atk 50 · P.Def 50 · S.Atk 45 · S.Def 55 · Spd 45 · Luck 50 · Resolve 55 · Stamina 50
- **Catch rate:** 40% base · **XP yield:** 55

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Frost Nip | Ice | Physical | 40 | 2 | 100% |
| 6 | Rime Veil | Ice | Status | — | 4 | — |
| 14 | Glacier Crash | Ice | Physical | 80 | 9 | 85% |

### Mistcoil

`mistcoil` · Water / Ice

*A serpent of fog that turns battlefields into marshes.*

- **Base stats:** HP 70 · P.Atk 45 · P.Def 55 · S.Atk 80 · S.Def 70 · Spd 80 · Luck 55 · Resolve 55 · Stamina 60
- **Catch rate:** 10% base · **XP yield:** 160
- **Grows from:** Tidepup (Lv 16, Catalyst Affinity)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Tide Beam | Water | Special | 55 | 6 | 100% |
| 1 | Drench | Water | Status | — | 4 | — |
| 1 | Rime Veil | Ice | Status | — | 4 | — |
| 18 | Glacier Crash | Ice | Physical | 80 | 9 | 85% |

### Pebblet

`pebblet` · Earth

*Mistaken for a rock until it headbutts your shin.*

- **Base stats:** HP 60 · P.Atk 55 · P.Def 75 · S.Atk 30 · S.Def 45 · Spd 25 · Luck 40 · Resolve 70 · Stamina 60
- **Catch rate:** 50% base · **XP yield:** 50

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Pebble Toss | Earth | Physical | 40 | 2 | 100% |
| 1 | Brace | Neutral | Status | — | 3 | — |
| 7 | Dust Sweep | Earth | Status | — | 3 | — |
| 13 | Quake Stomp | Earth | Physical | 70 | 9 | 100% |

### Sprigling

`sprigling` · Grass

*A sprout that plants seeds in every footprint.*

- **Base stats:** HP 55 · P.Atk 45 · P.Def 55 · S.Atk 40 · S.Def 60 · Spd 35 · Luck 45 · Resolve 60 · Stamina 55
- **Catch rate:** 50% base · **XP yield:** 50

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Vine Lash | Grass | Physical | 45 | 3 | 100% |
| 4 | Seed Carpet | Grass | Status | — | 4 | — |
| 8 | Regrowth | Grass | Status | — | 6 | — |

### Tidepup

`tidepup` · Water

*A pup that splashes puddles into its foes' paths.*

- **Base stats:** HP 50 · P.Atk 45 · P.Def 45 · S.Atk 50 · S.Def 45 · Spd 50 · Luck 50 · Resolve 45 · Stamina 55
- **Catch rate:** 40% base · **XP yield:** 60
- **Grows into:** Lv 16 → **Torrentusk** (Striker Affinity); Lv 16 → **Mistcoil** (Catalyst Affinity); Lv 16 → **Torrentusk** (default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Tackle | Neutral | Physical | 40 | 1 | 100% |
| 1 | Splash Jab | Water | Physical | 40 | 2 | 100% |
| 5 | Drench | Water | Status | — | 4 | — |
| 9 | Riptide | Water | Physical | 55 | 6 | 95% |
| 12 | Taunting Howl | Neutral | Status | — | 3 | 100% |
| 14 | Tide Beam | Water | Special | 55 | 6 | 100% |

### Torrentusk

`torrentusk` · Water / Earth

*Grew up charging through floods, tusks first.*

- **Base stats:** HP 75 · P.Atk 85 · P.Def 70 · S.Atk 45 · S.Def 55 · Spd 55 · Luck 45 · Resolve 65 · Stamina 70
- **Catch rate:** 10% base · **XP yield:** 160
- **Grows from:** Tidepup (Lv 16, Striker Affinity), Tidepup (Lv 16, default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Splash Jab | Water | Physical | 40 | 2 | 100% |
| 1 | Riptide | Water | Physical | 55 | 6 | 95% |
| 18 | Quake Stomp | Earth | Physical | 70 | 9 | 100% |

### Voltmoth

`voltmoth` · Electric

*Its wingbeats leave the air prickling with static.*

- **Base stats:** HP 40 · P.Atk 40 · P.Def 35 · S.Atk 60 · S.Def 40 · Spd 75 · Luck 60 · Resolve 40 · Stamina 45
- **Catch rate:** 40% base · **XP yield:** 55

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Spark Bite | Electric | Physical | 45 | 3 | 100% |
| 5 | Static Field | Electric | Status | — | 4 | — |
| 12 | Thunder Cascade | Electric | Special | 50 | 7 | 90% |

## Moves

Grouped by type. Physical moves use P.Atk vs P.Def; special moves use S.Atk vs S.Def. *Cost* is energy spent. Effects run top to bottom; `bonus_if_field` modifiers apply to the damage or heal after them. **Scrap** is always available, even without energy.

### Dark moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Dusk Pulse** | `dusk_pulse` | Special | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A ripple of cold shadow.* | — |
| **Shadow Claw** | `shadow_claw` | Physical | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A slash from the darkness.* | — |
| **Shroud** | `shroud` | Status | — | 4 | — | 0 | Enemy side | Applies Shrouded to the enemy side<br>*Smothers the enemy side in shadow.* | — |

### Earth moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Dust Sweep** | `dust_sweep` | Status | — | 3 | — | 0 | Own side | Clears all states from own side<br>*Clears every state from your own side.* | Pebblet |
| **Pebble Toss** | `pebble_toss` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage | Pebblet |
| **Quake Stomp** | `quake_stomp` | Physical | 70 | 9 | 100% | 0 | Everyone | Damage<br>*Shakes the whole field, allies included.* | Pebblet, Torrentusk |

### Electric moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Spark Bite** | `spark_bite` | Physical | 45 | 3 | 100% | 0 | One enemy | Damage; Inflicts Shock (15%) | Voltmoth |
| **Static Field** | `static_field` | Status | — | 4 | — | 0 | Enemy side | Applies Charged to the enemy side<br>*Charges the air over the enemy side.* | Voltmoth |
| **Thunder Cascade** | `thunder_cascade` | Special | 50 | 7 | 90% | 0 | All enemies | x1.4 if the target's side is Charged; Damage | Voltmoth |

### Fire moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Ember Flick** | `ember_flick` | Special | 40 | 2 | 100% | 0 | One enemy | Damage; Inflicts Burn (10%) | Emberkit |
| **Flare Burst** | `flare_burst` | Special | 45 | 7 | 90% | 0 | All enemies | x1.6 if the target's side is Scorched (consumes it); Damage<br>*Hits every foe; far stronger on a Scorched side.* | Emberkit |
| **Scorch Field** | `scorch_field` | Status | — | 4 | — | 0 | Enemy side | Applies Scorched to the enemy side<br>*Sets the enemy side smouldering.* | Emberkit |

### Ghost moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Haunt** | `haunt` | Status | — | 4 | — | 0 | Enemy side | Applies Haunted to the enemy side<br>*Calls restless spirits onto the enemy side.* | — |
| **Spirit Touch** | `spirit_touch` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A chilling touch from beyond.* | — |
| **Wail** | `wail` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A mournful cry that rattles the soul.* | — |

### Grass moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Regrowth** | `regrowth` | Status | — | 6 | — | 0 | Self | x1.5 if own side is Overgrown; Heals 20% max HP<br>*Heals; heals more on your own Overgrown side.* | Sprigling |
| **Seed Carpet** | `seed_carpet` | Status | — | 4 | — | 0 | Enemy side | Applies Overgrown to the enemy side<br>*Grows a thicket on the enemy side.* | Sprigling |
| **Vine Lash** | `vine_lash` | Physical | 45 | 3 | 100% | 0 | One enemy | Damage | Sprigling |

### Ice moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Frost Nip** | `frost_nip` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage; Inflicts Chill (20%) | Frostling |
| **Glacier Crash** | `glacier_crash` | Physical | 80 | 9 | 85% | 0 | One enemy | Damage | Frostling, Mistcoil |
| **Rime Veil** | `rime_veil` | Status | — | 4 | — | 0 | Enemy side | Applies Frosted to the enemy side<br>*Coats the enemy side in frost.* | Frostling, Mistcoil |

### Iron moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Iron Bash** | `iron_bash` | Physical | 50 | 4 | 95% | 0 | One enemy | Damage<br>*A heavy, armoured slam.* | — |
| **Magnet Pulse** | `magnet_pulse` | Special | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A wave of magnetic force.* | — |
| **Magnetize** | `magnetize` | Status | — | 4 | — | 0 | Enemy side | Applies Magnetized to the enemy side<br>*Scatters iron filings across the enemy side.* | — |

### Light moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Flash Strike** | `flash_strike` | Physical | 40 | 2 | 100% | +1 | One enemy | Damage<br>*A strike quick as a flash of light.* | — |
| **Light Beam** | `light_beam` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A focused beam of radiance.* | — |
| **Radiance** | `radiance` | Status | — | 4 | — | 0 | Own side | Applies Radiant to own side<br>*Bathes your own side in warm light.* | — |

### Magic moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Enchant** | `enchant` | Status | — | 4 | — | 0 | Own side | Applies Enchanted to own side<br>*Draws protective runes around your own side.* | — |
| **Hex Bolt** | `hex_bolt` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A crackling bolt of raw arcana.* | — |
| **Rune Strike** | `rune_strike` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A blow carried by a glowing rune.* | — |

### Mental moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Focus Palm** | `focus_palm` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A strike guided by total concentration.* | — |
| **Mind Spike** | `mind_spike` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A piercing psychic jolt.* | — |
| **Psychic Haze** | `psychic_haze` | Status | — | 4 | — | 0 | Enemy side | Applies Hazed to the enemy side<br>*Fills the enemy side with a dulling psychic fog.* | — |

### Neutral moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Brace** | `brace` | Status | — | 3 | — | 0 | Self | P.Def +1; S.Def +1<br>*Raises Physical and Special Defense.* | Pebblet |
| **Scrap** | `scrap` | Physical | 25 | 0 | 100% | 0 | One enemy | Damage<br>*A desperate, free flail. Always available, even with no energy.* | Everyone (fallback) |
| **Tackle** | `tackle` | Physical | 40 | 1 | 100% | 0 | One enemy | Damage | Emberkit, Tidepup |
| **Taunting Howl** | `taunting_howl` | Status | — | 3 | 100% | 0 | All enemies | P.Atk -1<br>*Lowers every foe's Physical Attack.* | Tidepup |

### Virtual moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Byte** | `byte` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A quick, glitching snap.* | — |
| **Corrupt** | `corrupt` | Status | — | 4 | — | 0 | Enemy side | Applies Glitched to the enemy side<br>*Seeds the enemy side with corrupted data.* | — |
| **Data Burst** | `data_burst` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*Floods the target with a blast of raw data.* | — |

### Water moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Drench** | `drench` | Status | — | 4 | — | 0 | Enemy side | Applies Soaked to the enemy side<br>*Floods the enemy side.* | Mistcoil, Tidepup |
| **Riptide** | `riptide` | Physical | 55 | 6 | 95% | 0 | One enemy | x1.5 if the target's side is Soaked (consumes it); Damage<br>*Stronger on a Soaked side, draining the water.* | Tidepup, Torrentusk |
| **Splash Jab** | `splash_jab` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage | Tidepup, Torrentusk |
| **Tide Beam** | `tide_beam` | Special | 55 | 6 | 100% | 0 | One enemy | Damage<br>*A focused jet of water.* | Mistcoil, Tidepup |

## Items

| Item | Id | Category | Price | Target | Effects | Description |
|---|---|---|---|---|---|---|
| **Lure Cage** | `lure_cage` | Capture | 100 | One enemy | Capture x1 | A plain woven cage. Works anywhere. |
| **Salve** | `salve` | Heal | 150 | One ally | Heals 33% max HP | Restores a third of a creature's HP. |
| **Snare Vine** | `snare_vine` | Capture | 250 | One enemy | Capture x0.8, x2.5 on Overgrown | Far more effective on an Overgrown side. |
| **Tide Net** | `tide_net` | Capture | 250 | One enemy | Capture x0.8, x2.5 on Soaked | Far more effective on a Soaked side. |
| **Tonic** | `tonic` | Heal | 150 | One ally | Restores 50% max energy | Restores half of a creature's energy. |

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
| Multi-target damage | x0.75 |
| Round limit (draw) | 200 |
| XP formula | yield x level / 5, x1.5 vs tamers |
| Catch status bonus | x1.5 |
| Max field states per side | 3 |
| Growth Affinity threshold | 30 |
| Underdog extra actions | floor(0.5 per ratio step) per creature |
| Underdog spread reduction | 20% per ratio step, max 50% |
| Underdog stat bonus | 15% per ratio step, max 15% |
| Underdog XP bonus | 50% per ratio step |
| Catch HP weight | 0.8 |
| Resolve resist cap | 30% (average creature: half that) |
| Resolve endure cap | 10%, once per battle |
| Energy pool | 2 x base Stamina x Lv / 100 + 20 |
| Rest restores | 25% of max energy |
| Training points | 1 per level, max 30 per stat, +2 HP per point |

### Bond

Range -100 to 100; starters begin at 20.

| Effect | At most |
|---|---|
| Disobey chance (negative Bond) | 40% at -100 |
| Accuracy and damage penalty | 20% at -100 |
| Lash out chance | 5% at -50 or below |
| XP bonus (positive Bond) | 10% at 100 |

| Happening | Bond |
|---|---|
| Battle Won | +2 |
| Knockout | +1 |
| Healed Item | +1 |
| Rested | +2 |
| Fainted | -4 |
| Overworked | -2 |

### Affinity awards

| Happening | Affinity | Points |
|---|---|---|
| Hit Dealt | Striker | 1 |
| Knockout | Striker | 3 |
| Hit Survived | Warden | 1 |
| Heal | Warden | 2 |
| Field Applied | Catalyst | 2 |
| Reaction Triggered | Catalyst | 4 |
| Field Cashed In | Catalyst | 1 |
| Status Inflicted | Trickster | 2 |
| Stat Lowered | Trickster | 1 |

