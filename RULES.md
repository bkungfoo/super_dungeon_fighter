# Super Dungeon Fighter: Rules as Implemented

This is the complete rule set the game runs on. Rules marked **(doc)** come
straight from the design document; rules marked **(fill)** fill a gap the
document left open, chosen to keep the document's intent.

## Setup

* One hero (you) against the AI Dungeon Master in a 36 x 36 m arena with
  random box obstacles. **(fill)** The camera follows the hero; the arena is
  larger than the screen.
* The Dungeon Master gets summoning points equal to the hero's level + 1
  **(doc, adapted for a single hero)**, multiplied by the chosen difficulty
  (Normal x1, Hard x1.5, Nightmare x2) plus one point per two Dark Lord
  levels. That number is also the **dungeon level**, which drives card rarity.
* Monsters spawn in the far half of the arena; the hero starts near the bottom.

## Real time

The design document's turns become seconds. All constants live at the top of
`battle_sim.gd`:

| Design value | Real-time value |
|---|---|
| 1 tile | 1.5 m (ranges and radii are Euclidean distances) |
| Load time N | N x 1.2 s of charging (the hero stands still and flashes) |
| Cooldown N | N x 1.2 s unable to use skills |
| Stun X | X x 1.0 s helpless |
| Down X | X x 1.3 s on the floor |
| Immobile N | N x 1.2 s unable to move |
| Invulnerable 1 | 1 s |
| Defend | 2 s of guard |
| Basic attack | one swing every 0.9 s while engaged |
| Knockback N | pushed N m; 2 damage per metre blocked by a wall |

## Controls

* **Tap the ground**: walk there. **Hold**: keep walking toward the finger.
* **Tap an enemy**: engage. The hero walks into range and swings basic attacks
  (x1 damage, Stun 1, free) until told otherwise.
* **Tap a card**: play it. It leaves the hand (the hand refills to 5), its
  stamina cost is paid, and the skill charges. Instant cards are READY at
  once; Defend fires immediately.
* **With a skill READY**, tap an enemy: the hero moves until the skill is in
  range and unleashes it. Melee skills need melee reach; dashes reach their
  charge distance; skills centred on the hero (Whirlwind, Frost Nova) fire
  once the enemy is just inside the area radius; aimed area skills (Fireball)
  fire once the enemy is within range.
* **Double-tap the ground** with an aimable area skill READY (Fireball, Blink)
  to cast it centred there (walking into range first if needed).
* Playing another card replaces a READY skill. Being stunned or knocked down
  interrupts charging; a READY skill survives.

## Decks and cards

* Every hero has a built-in basic Attack plus a **deck of exactly 30 action
  cards** and a hand of 5. A card is a skill at a rank (Bash [B], ...).
* Monsters play straight from their skill list.
* **Rewards**: when you clear a dungeon you receive one random card your class
  can use. The dungeon level sets the rarity odds:

  | Dungeon level | Common | Uncommon | Rare | Epic |
  |---|---|---|---|---|
  | 2 | 45 | 30 | 14 | 0 |
  | 5 | 30 | 30 | 20 | 6 |
  | 10 | 5 | 30 | 30 | 16 |

  (weights: common = max(5, 55 - 5L), uncommon = 30, rare = 10 + 2L,
  epic = max(0, 2L - 4))
* **Rarity** is computed from a card's power score so that cards with higher
  average damage and higher priority are rarer:
  `score = damage x area + status + 0.25 x priority - 0.5 x load time`.
  Thresholds: Uncommon >= 3.2, Rare >= 5.0, Epic >= 6.8. The test suite prints
  the resulting table.
* New cards land in the hero's **collection**; the deck builder in town moves
  copies in and out of the 30-card deck.
* Starter decks (30 cards): Warrior 8 Defend, 7 Grab, 8 Whirlwind C, 7 Final
  Slash C. Knight 8 Defend, 5 Grab, 9 Bash C, 8 Full Swing C. Mage 6 Defend,
  7 Blink, 10 Fireball C, 7 Frost Nova C.

## Counters **(fill)**

The document asks for tic-tac-toe style counters. Three free skills form the
triangle:

| Skill | Beats | Loses to |
|---|---|---|
| Attack (x1, Stun 1) | Grab: an attack aimed at the grabber breaks the grab | Defend: blocked, and the attacker is parried (Stun 1) |
| Grab (x0.5, Down 1) | Defend: unblockable | Attack |
| Defend | Attack | Grab |

Guard-break skills (Full Swing, Whirlwind, Final Slash) are only halved by
Defend and apply no status. Spells (Fireball, Frost Nova) ignore Defend.

## Combo state machine **(doc)**

```
Active --Stun X--> Stunned      Stunned --Stun or Down--> Down
Active --Down X--> Down         Down    --Stun or Down--> Reset --> Active
```

* **Stun X**: helpless for X seconds. **Down X**: on the floor for X x 1.3 s.
* A stunned unit that is stunned again is knocked down with the *new* value
  (Y replaces X). Two hits landing within 0.35 s count as simultaneous and
  use max(X, Y).
* **Reset**: hitting a downed unit with any Stun or Down skill makes it spring
  back up immediately, immune to stun and down for X + 1 seconds, with its
  cooldown and immobility cleared. **(fill: the document's Reset paragraph is
  unfinished; the retaliation is the immediate recovery plus immunity.)**
  Damage still applies, so finishing a downed enemy is fine; chipping it is not.

## Skill mechanics

* **Cost**: stamina paid when the card is played; some skills also cost life.
  Stamina regenerates continuously.
* **Load N**: N x 1.2 s of charging; the hero stands still. Any stun or down
  interrupts it and the card is lost.
* **Cooldown N**: no skills for N x 1.2 s except chained ones. **Immobile N**:
  no movement. **Invulnerable N**: no damage or status.
* **Chains** (doc): after a skill with a chain list fires, the listed cards may
  be played during its cooldown.
* **Multiplier X**: damage = Attack x X. **Knockback N**: pushed N m away from
  the attacker; 2 damage per metre blocked by a wall. **(fill)**
* **Radius X**: all enemies within X x 1.5 m of the caster. Fireball's blast
  is (radius + 0.5) x 1.5 m around the target point and hits everything.
  **(fill)**
* **Charge Z**: dash up to Z x 1.5 m. Pounce stops at the first enemy and
  bites it. Final Slash dashes the whole lane and splits its hits round-robin
  among every enemy it passes. **(fill)**
* **Split Hits X / Y**: Final Slash deals X hits of Y x 10% damage. **(fill)**
* **Priority** no longer orders resolution (everything is real time); it still
  feeds the rarity formula.

## Skill table

Values are per rank C / B / A / S. Priority is the resolution order
(higher fires first). The "Exp" column of the design document is no longer
spent; cards are earned instead.

| Skill | Weapon | Priority | Effect | Rarity C/B/A/S | Cost |
|---|---|---|---|---|---|
| Attack | any | 5 | x1, Stun 1. Chains: Attack, Whirlwind | Common | 1 |
| Defend | any | 7 | Blocks melee; parries Attack | Common | 0 |
| Grab | any | 4 | x0.5, Down 1, unblockable. Chains: Attack | Common | 1 |
| Blink | staff | 6 | Teleport within 3. Chains: Fireball | Common | 2 |
| Bash | blunt | 3 | Load 1, Stun 2/3/4/5, Cooldown 2. Chains: Attack, Whirlwind | C/U/U/R | 2/3/4/5 |
| Full Swing | blunt | 1 | Load 2, x2/3/4/5, Down 2, Knockback 2, Cooldown 2, Immobile 2. Chains: Whirlwind, Defend | U/U/R/R | 2/3/4/5 |
| Final Slash | sword | 2 | Load 2 (immobile), 3/5/7/10 hits of 100/90/80/70%, Charge 4/5/6/7, Cooldown 2 | U/R/R/E | 2/4/6/8 |
| Whirlwind | any melee | 2 | Load 1 (immobile), Radius 2/3/3/4, x1/1/2/2, Down 1, Knockback 2, Invulnerable 1, Cooldown 2, Immobile 2, costs 1 life. Chains: Full Swing, Defend | U/U/R/E | 2/3/4/5 |
| Fireball | staff | 2 | Load 1, range 4, 3x3 blast, x2/3/4/5, ignores Defend. Chains: Blink | U/R/E/E | 3/4/5/6 |
| Frost Nova | staff | 3 | Load 1, Radius 2/2/3/3, Stun 2/3/3/4, Cooldown 2. Chains: Fireball, Blink | U/U/R/R | 4/5/6/7 |
| Pounce | monsters | 4 | Charge 3, x1, Down 1, Cooldown 1 | - | 2 |

**Shield Charge** is intentionally not implemented; its table row is
reserved for a later design pass.

## Heroes

| Class | Weapon | Life | Stam (+regen) | Atk | Move | Card pool |
|---|---|---|---|---|---|---|
| Warrior | sword | 32 | 10 (+2) | 6 | 3 | Attack, Defend, Grab, Whirlwind, Final Slash |
| Knight | mace + shield | 38 | 9 (+2) | 5 | 2 | Attack, Defend, Grab, Bash, Full Swing, Whirlwind |
| Mage | staff | 22 | 14 (+3) | 4 | 3 | Attack, Defend, Blink, Fireball, Frost Nova |

Per level: +4 life, +1 stamina, +1 attack every second level.
Level N needs 4 + 2N XP. Heroes earn XP equal to the summoning value of each
monster they kill, plus 2 for surviving a cleared dungeon. Knocked-out heroes
recover fully in town.

## Monsters

| Monster | Value | DM level | Life | Atk | Swing | Stuns? | Skills |
|---|---|---|---|---|---|---|---|
| Goblin | 1 | 1 | 8 | 2 | 1.6 s | no | Attack, Grab |
| Wolf | 1 | 1 | 7 | 2 | 1.3 s | no | Attack, Pounce |
| Skeleton | 2 | 1 | 14 | 3 | 1.5 s | no | Attack, Defend, Whirlwind C |
| Orc | 2 | 2 | 20 | 4 | 1.5 s | yes | Attack, Bash C, Defend |
| Ogre | 4 | 2 | 40 | 6 | 2.0 s | yes | Attack, Full Swing B, Grab |
| Dark Knight | 5 | 3 | 36 | 6 | 1.4 s | yes | Attack, Bash B, Full Swing B, Defend |
| Ofrom Champion (boss) | 8 | 4 | 70 | 8 | 1.1 s | yes | Attack, Final Slash B, Whirlwind B, Defend |

Low-tier monsters swing slowly and their basic attacks do not stun, so a new
hero is never stun-locked by a pack of goblins. Monsters are slower than the
hero and **loiter until the hero comes within their aggro range** (7 to 11 m)
or one of them is hit; a hit also wakes monsters within 4 m, so you fight the
dungeon one group at a time. **(fill)**

The Dark Lord gains 1 XP per 5 damage dealt to heroes, 5 per hero knocked
out and 10 per party wipe; every 20 XP is a level, unlocking stronger
monsters. **(doc intent, numbers fill)**

## Not implemented (yet)

* Shield Charge (by request).
* Trade skills, crafting, equipment and items.
* Multiple heroes in one run: you control a single hero.
