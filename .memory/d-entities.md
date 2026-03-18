# Entity Design — Current Roster

> Provenance: claude, 2026-03-11, session 41bc0d2b
> Supersedes: `ref-creature-behavior.md` (outdated — called player "walrus")

## Overview

Six entity types on the ice floe. All creatures use `_draw()` procedural rendering, no sprites.

### Categories

| Category | Entities | Role |
|---|---|---|
| **Player** | Seal | Human-controlled |
| **Companion** | Kid (baby seal) | Per-player scoring target, wanders ice, eats fish |
| **Neutral** | Penguin | Fish thief, non-lethal, robbable |
| **Enemy** | Bear | Deadly predator, eats fish, hunts players and kids (disabled — not spawning) |
| **Enemy** | Walrus | Heavy aggressive bully, eats fish, fury-charges nearby seals/penguins |

Collectables (fish) documented separately in `d-collectables.md`.

---

## Seal (player) — `seal.gd`

**Role:** Player-controlled. Slides on ice, collects fish (max 2), delivers to kid to score.

**Movement:**
- ACCEL: 600 px/s², BRAKE_ACCEL: 900 px/s² (when input opposes velocity, dot < -0.3)
- Braking applies force in the **player's input direction** (not auto-brake along velocity) — lets you turn while decelerating
- Friction: 0.996/frame — very icy, long coast. Velocity zeroed below 2 px/s
- No speed cap (friction is the limit)
- CharacterBody2D, MOTION_MODE_FLOATING, radius 28px

**Collisions:**
- **Wall:** `velocity = pre_velocity.bounce(normal) * 0.85`. No stun — velocity reflection is sufficient. (Wall stun removed: created vibration loop when holding input toward wall.)
- **Seal vs seal:** Elastic collision — velocity components along collision normal are swapped. Damping: `0.8 * speed_factor`. Both seals get `_bounce_stun = 0.2 * speed_factor` (input suppressed). Fish knocked loose from other seal if `speed_factor > 0.4`.
- **Seal vs penguin:** Hockey check — penguin launched, seal passes through unaffected. No stun on seal. Position restored after `move_and_slide` so penguin never blocks seal. Robs penguin's fish on contact.
- **Seal vs bear:** Bear is deadly when ACTIVE — instant kill. Seal flung away + `fall_in_water()`.
- **Speed factor:** `clamp(speed / 400, 0.05, 1.0)` — long run-up = powerful hit.
- **Bump cooldown:** 0.15s between CharacterBody2D collisions (prevents double-triggers).

**Fish carrying:**
- Max 2 fish. Each tracked with origin: "ground", "penguin", "opponent".
- `collect_fish()` — ground pickup. `collect_penguin_fish()` — robbed from penguin.
- `deliver_fish()` — pops one fish at kid. +1 score per fish regardless of origin.
- `drop_fish()` — drops ALL carried fish on powerful bounce or water fall. Fish spawn at last known ice position.

**Water/respawn:**
- `fall_in_water()`: drops fish, invisible, 1.5s timer.
- Respawn: near open water edge or hole (away from bears), 1s invincibility flash, velocity/fish state reset, splash effect.

**Oscillation guard:** Child node. Detects stuck-in-loop bouncing (16-frame window, path/spread ratio). Zeros velocity to break out.

---

## Kid (baby seal) — `kid.gd`

**Role:** Per-player scoring target. Baby seal wanders ice, eats nearby fish directly (+1 score), receives deliveries from parent seal.

**Movement:**
- Node2D (not CharacterBody2D — no physics collisions)
- Wander speed: 40 px/s, panic speed: 70 px/s
- Wander targets: biased toward water edges (60%), parent (25%), random ice (15%)
- Stays on ice — turns away from edges, dives if it walks into water/hole
- Bounce velocity from seal bumps (decays at 0.92/frame, stops at unsafe spots)

**Bear interaction:**
- Bear contact within 55px = kid eaten: -5 score, cadaver spawned, kid dives to water for 5s
- When bear within PANIC_DISTANCE (600px): panics, runs away on land biased toward nearest water
- When bear within FLEE_DISTANCE (150px) and near water: dives immediately, hides 5s
- Tremble animation when scared

**Fish eating:**
- Eats landed fish within 70px directly — scores +1, no delivery needed
- Chomp animation on feed

**Diving/resurfacing:**
- Dives: becomes invisible, spawns ripple at dive spot, hides WATER_HIDE_TIME (5s)
- Resurfaces: picks safest water-adjacent spot (farthest from enemies), splash effect

**Visual:**
- Squat oval body, lighter/warmer than parent color. Big dark eyes, whiskers, flippers.
- Grows 0-20% larger as fish_fed increases (visual in-world score indicator)
- Waddle animation (rotation oscillation). Excited waddle when parent approaches with fish.
- Promotes to adult seal appearance on win (growth tween)

---

## Penguin (AI neutral) — `penguin.gd`

**Role:** Fish thief. Wanders ice, detects fish, steals them, escapes via open water. Non-lethal.

**States:** `SWIMMING_IN` → `ACTIVE` → `LEAVING` (with fish) or `IN_WATER` (knocked off)

**Movement modes (ACTIVE):**
| Mode | Speed | Duration | Trigger |
|------|-------|----------|---------|
| WALKING | 40 px/s | 0.5-2s | No fish detected |
| CHARGING | 20 px/s (creep) | 3s | Fish detected, or after walk timer |
| SLIDING | 507 px/s launch, 0.992 friction | Until < 8 px/s | After charge |
| SLIDE_PAUSE | 0 (standing) | 1s | After slide stops |

- Constantly re-aims toward nearest fish during CHARGING
- If fish appears during WALKING, immediately switches to CHARGING
- Wall bounce during any mode: `pre_velocity.bounce(normal) * 0.5-0.6`

**Fish behavior:**
- Detects landed fish within 1000px
- On pickup: switches to LEAVING immediately
- If robbed by seal bump: drops fish, 1s pause (stunned), returns to ACTIVE

**Leaving (with fish):**
- 0.6s pause (still collidable — seal can rob during this window)
- Slide→pause→slide toward random open water edge
- Phase 0: slide to edge (walls still active). Phase 1: swim into ocean (walls disabled)
- **Holes trap leaving penguins** — sinks with spiral animation, fish stolen (gone for good)
- If reaches ocean: fish_stolen signal, respawns after 4s

**Water:**
- Falls off ice edges (but crosses holes freely when ACTIVE — only leaving penguins sink in holes)
- Swim-away animation to nearest screen edge, or sink animation if fell in hole
- Respawn: 3.5s, swims back in through open water edge with waddle animation

**Visual:** Black oval body, white belly, orange beak. Radius 18px. Fish visible in beak when carrying.

**Collision layer:** Layer 2, mask 1|2. Disabled during swimming/in-water.

**Light NPC:** Identified by having `collect_fish()` but NOT `_set_bounce_stun()` — seal treats as pass-through.

---

## Bear (AI threat) — `bear.gd`

**Role:** Deadly late-game predator. Slow, heavy, eats ground fish, hunts players. Leaves after eating 5 fish.

**States:** `SWIMMING_IN` → `ACTIVE` → `LEAVING` → `GONE`

**Movement (ACTIVE):**
- ACCEL: 300 px/s², MAX_SPEED: 180 px/s, friction: 0.994
- AI priority: fish (2000px detect) > nearby players (300px, 80% accel) > slow wander (30% accel)
- Wall bounce: `pre_velocity.bounce(normal) * 0.4` (heavy damping)
- Body collision: barely affected (`velocity *= 0.95`) — bear is a wall to others
- Arena snaps bear back onto ice if it drifts off — never falls in water

**Deadly:**
- `is_deadly()` true when ACTIVE
- Seal collision = instant kill (seal flung away + fall_in_water, -1 score)
- Kid contact within 55px = kid eaten (-5 score, cadaver spawned, kid hides 5s)

**Fish eating:**
- Eats landed fish on contact via `collect_fish()`. Each eat emits `fish_stolen` (fish permanently gone).
- After 5 fish: starts leaving

**Enter/leave:**
- Swim in: tween through open water edge, 2-6s
- Arrive: 1s pause, collisions enabled, splash
- Leave: 1s pause, walls disabled, accelerates toward exit at 60% accel, splash when entering water
- After reaching ocean: state = GONE, invisible, collision disabled. **One bear per match** — never respawns.

**Visual:** Large white circle, radius 50px. Small menacing eyes, black nose, round ears with pink inner. Fish stacked on back when carrying.

**Pacing:** Arrives 35-50s into match. Single appearance per round.

---

## Walrus (enemy) — `walrus.gd`

**Role:** Heavy aggressive enemy. Eats fish, fury-charges nearby seals and penguins. Can be bounced off ice by a fast seal (destroyed). One per match, spawns at 20-30s.

**States:** `SWIMMING_IN` → `ACTIVE` → `LEAVING`

**Movement:**
- ACCEL: 900 px/s² (seal: 600), MAX_SPEED: 320 px/s, FURY_SPEED: 420 px/s
- Friction: 0.990 (seal: 0.996) — stops more efficiently, less slidey
- MASS: 3.0 (seal: 1.0) — mass-weighted elastic collisions
- Radius: 40px. CharacterBody2D, MOTION_MODE_FLOATING.

**Fury mechanic** (aggression radius = 250px):
- **Priority:** Seal (in radius) > Penguin (in radius) > Fish
- **Lock-on:** When target enters fury radius, walrus locks on and charges at 1.5x ACCEL toward target
- **Escape:** Target must leave fury radius AND stay out for FURY_COOLDOWN (1.0s) to break lock
- **Transfer:** If another seal enters fury radius and is closer, walrus switches target. Seal always has priority over penguin.
- **After fury:** Walrus pauses for POST_FURY_PAUSE (1.0s), then returns to hunting fish
- **Visual:** Red glow ring when in fury mode

**Sub-states (ACTIVE):**
| Mode | Behavior |
|---|---|
| HUNTING_FISH | Checks fury radius each frame. Moves toward nearest fish, or wanders. |
| FURY | Charges locked target. Checks escape timer + target transfer. |
| COOLDOWN | Stands still for 1s after fury breaks. |

**Collisions:**
- **Wall:** `pre_velocity.bounce(normal) * 0.7` (heavier damping than seal's 0.85)
- **Walrus vs seal:** Mass-weighted elastic collision (w1=0.5, w2=1.5). Seal bounces hard, walrus barely moves. But high-speed seal can push walrus significantly. Knocks fish loose from seal if speed_factor > 0.4.
- **Walrus vs penguin:** Penguin launched hard (`speed * 2.0`, min 200). Walrus barely slows (`velocity * 0.9`).
- **Off-ice = destroyed:** Unlike bear (snapped back), walrus that goes off ice is queue_free'd. Reward for skilled seal play.

**Fish:** Eats landed fish on contact (same Area2D mechanism as bear). `fish_stolen` signal — fish permanently gone. After 3 fish → starts leaving.

**Enter/leave:** Same swim-in pattern as bear/penguin (tween through open water edge). Leaving: pause 1s, walls disabled, accelerate toward ocean, queue_free on arrival.

**Visual:** Brown oval body (radius 40px), lighter belly, beady eyes, broad snout, prominent white tusks. Fish carried on back.

---

## Fish — see `d-collectables.md`

---

## Interaction Matrix

| | Seal | Penguin | Bear | Walrus | Kid | Fish |
|---|---|---|---|---|---|---|
| **Seal** | Elastic bounce + stun | Hockey check (pass-through) | Killed | Mass-weighted bounce (seal flies) | Bumps kid | Collects (max 2) |
| **Penguin** | Launched | — | — | Launched hard | — | Steals + leaves |
| **Bear** | Kills seal | — | — | — | Eats kid (-5) | Eats (max 5) |
| **Walrus** | Fury-charges, heavy bounce | Fury-charges, launches | — | — | — | Eats (max 3) |
| **Kid** | Bumped | — | Eaten/flees | — | — | Eats nearby (70px) |

## Animal Pacing

```
 0s     Round start — fish spawning begins (first at 3.5s)
~6-10s  First penguin swims in
~16-28s Additional penguins (2-3 total, spaced 10-18s)
20-30s  Walrus arrives (one per match, destroyable)
35-50s  Bear arrives (one per match) [DISABLED]
```

Fish: max 2 on field, 3-7s spawn gaps. Longer gaps create scarcity pressure.
