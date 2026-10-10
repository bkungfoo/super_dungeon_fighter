# Super Dungeon Fighter: Rules as Implemented

This is the complete rule set the game runs on. Rules marked **(doc)** come
straight from the design document; rules marked **(fill)** fill a gap the
document left open, chosen to keep the document's intent.

## Setup

* 1 to 6 heroes against the AI Dungeon Master on an 8 x 8 grid. **(fill)**
  The document allows 2 to 8 heroes; 6 is the limit that stays readable on a
  phone.
* The Dungeon Master gets summoning points equal to the sum of the heroes'
  levels **(doc)**, multiplied by the chosen difficulty (Normal x1, Hard x1.5,
  Nightmare x2) and plus one point for every two Dark Lord levels. **(fill)**
  That number is also the **dungeon level**, which drives card rarity.
* The DM places walls (free, kept to a few cells, never splitting the board)
  and monsters in the top three rows first; heroes then deploy on the bottom
  two rows. **(doc, with fixed zones)**

## Decks and cards

* Every hero brings a **deck of exactly 30 action cards** and draws an
  opening hand of 5. A card is a skill at a rank (Attack, or Bash [B], ...).
* Each round a hero may play **one card from the hand**. Played cards go to
  the discard pile; at the end of the round the hand refills to 5. When the
  deck runs out the discard pile is reshuffled into it.
* Monsters play straight from their skill list (the Dark Lord's hand is
  unlimited), but obey the same turn rules below.
* **Rewards**: when the party defeats a dungeon, every hero in it receives one
  random card its class can use. The dungeon level sets the rarity odds:

  | Dungeon level | Common | Uncommon | Rare | Epic |
  |---|---|---|---|---|
  | 2 | 45 | 30 | 14 | 0 |
  | 5 | 30 | 30 | 20 | 6 |
  | 10 | 5 | 30 | 30 | 16 |

  (weights: common = max(5, 55 - 5L), uncommon = 30, rare = 10 + 2L,
  epic = max(0, 2L - 4))
* **Rarity** is computed from a card's power score so that cards with higher
  average damage and higher priority are rarer:
  `score = damage x area + status + 0.25 x priority - 0.5 x load time`,
  where damage is the multiplier (or hits x per-hit for Final Slash), area is
  1 for single targets, 1 + radius/2 for radius skills, 2 for Fireball's
  blast (+0.3 for a charge), and status is 0.8 per point of Stun or Down plus
  0.5 for knockback. Thresholds: Uncommon >= 3.2, Rare >= 5.0, Epic >= 6.8.
  The resulting table is printed by the test suite.
* New cards land in the hero's **collection**; the deck builder in town moves
  copies in and out of the 30-card deck.
* Starter decks (30 cards): Warrior 12 Attack, 7 Defend, 5 Grab, 3 Whirlwind
  C, 3 Final Slash C. Knight 10 Attack, 7 Defend, 4 Grab, 5 Bash C, 4 Full
  Swing C. Mage 7 Attack, 6 Defend, 5 Blink, 7 Fireball C, 5 Frost Nova C.

## A round

1. **Start of round.** Face-down charge-up cards gain a load counter. Cards
   with enough counters are *ready* and will fire this round.
2. **Planning.** Every unit secretly plans:
   * a **move** (orthogonal steps within its Move range), and/or
   * a **card**, aimed from the cell it will end the move on.
   * **Instant cards** (no load time: Attack, Defend, Grab, Blink) may be
     combined with a move in the same turn.
   * **Charge-up cards** are played standing still. While the card charges
     the unit may move unless the card says *immobile*. Once the card is
     ready the unit moves and the skill fires in the same turn, aimed from
     the destination. A ready unit cannot play another card that round.
3. **Movement** resolves simultaneously. If two units want the same cell,
   random priority decides and the loser stops short.
4. **Skills** resolve in **priority order** (highest first; ties by die roll,
   with Reset units first). A unit that is stunned or knocked down before its
   own skill fires loses it, so a fast Attack can interrupt a slow Full Swing
   that is firing the same round. Defend is applied before anything else, and
   an Attack aimed at a grabber cancels the Grab.
5. **End of round.** Stun and Down tokens, cooldowns, immobility and
   invulnerability tick down; stamina regenerates; hands refill to 5.

Turn timing: Stun 1 applied this round makes the victim skip the next full
round.

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

* **Stun X**: X tokens; the unit skips X rounds. Tokens are removed at the
  end of each round after the one in which they were applied.
* **Down X**: like Stun but the unit is on the floor. A stunned unit that is
  stunned again is knocked down with the *new* value (Y replaces X).
* Two allies stunning the same target in the same phase count as consecutive
  stuns: Down max(X, Y).
* **Reset**: hitting a downed unit with any Stun or Down skill makes it spring
  back up immediately. It is immune to stun and down for X rounds, acts with
  top priority next round, and its cooldown and immobility are cleared.
  **(fill: the document's Reset paragraph is unfinished; this implements the
  summary's "free move and action to retaliate" as initiative plus immunity.)**
  Damage still applies, so finishing a downed enemy is fine; chipping it is not.

## Skill mechanics

* **Cost**: stamina paid when the card is played; some skills also cost life.
  Stamina regenerates every round (2 or 3 depending on class).
* **Load N**: fires N rounds later in the charged phase at the direction or
  cell chosen now. Skills marked "immobile" lock the user in place while
  loading. Any stun or down interrupts the load. A loading unit cannot play
  another card.
* **Cooldown N**: no skills for N rounds, except chained ones. **Immobile N**:
  no movement for N rounds. **Invulnerable N**: no damage or status.
* **Chains** (doc): after a skill with a chain list resolves, the listed skills
  may be played in the next skill phase even during the cooldown. Their load
  time runs during the cooldown.
* **Multiplier X**: damage = Attack x X. **Knockback N**: pushed N cells away
  from the attacker; each blocked cell deals 2 extra damage. **(fill)**
* **Radius X**: all enemies within X steps (Manhattan). Fireball's blast is the
  3 x 3 square around the target and hits allies too. **(fill)**
* **Charge Z**: dash up to Z cells in a straight line. Pounce stops at the
  first unit and bites it. Final Slash dashes through the lane and splits its
  hits round-robin among every enemy in the lane. **(fill)**
* **Split Hits X / Y**: Final Slash deals X hits of Y x 10% damage. The table's
  Y column (10, 9, 8, 7) is read as damage per hit. **(fill)**

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

| Monster | Value | DM level | Life | Atk | Move | Skills |
|---|---|---|---|---|---|---|
| Goblin | 1 | 1 | 12 | 3 | 3 | Attack, Grab |
| Wolf | 1 | 1 | 10 | 3 | 4 | Attack, Pounce |
| Skeleton | 2 | 1 | 18 | 4 | 2 | Attack, Defend, Whirlwind C |
| Orc | 2 | 2 | 24 | 5 | 2 | Attack, Bash C, Defend |
| Ogre | 4 | 2 | 45 | 8 | 2 | Attack, Full Swing B, Grab |
| Dark Knight | 5 | 3 | 40 | 7 | 2 | Attack, Bash B, Full Swing B, Defend |
| Ofrom Champion (boss) | 8 | 4 | 70 | 9 | 3 | Attack, Final Slash B, Whirlwind B, Defend |

The Dark Lord gains 1 XP per 5 damage dealt to heroes, 5 per hero knocked
out and 10 per party wipe; every 20 XP is a level, unlocking stronger
monsters. **(doc intent, numbers fill)**

## Not implemented (yet)

* Shield Charge (by request).
* Trade skills, crafting, equipment and items.
* A human Dungeon Master (pass-and-play). The engine is written to support it.
