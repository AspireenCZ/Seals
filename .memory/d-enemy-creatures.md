# Enemy Creatures — Design Doc

> Provenance: claude, 2026-03-11, session e0efa864

## Context

Current creature roster:
- **Seal** (player) — slides on ice, collects fish, feeds baby
- **Penguin** (neutral) — walks/slides, steals fish, non-lethal
- **Bear** (threat) — slow, deadly, eats fish off ground, hunts players late-game

Bear is the only enemy. It fills the "slow tank" niche well — you see it coming, the tension is spatial. But the threat palette is one-dimensional: every round plays the same danger. This doc proposes additional enemies that create **distinct gameplay situations**.

## Design Principles

1. **Each enemy = one clear verb.** Bear *crushes*. New enemies should each have their own unmistakable action.
2. **Enemies create dilemmas, not punishment.** The fun is in the decision ("do I go for that fish or avoid the threat?"), not in unavoidable damage.
3. **Visual read at a glance.** At 1920x1080 with radius 18-50px creatures, silhouette and movement pattern must be instantly distinct.
4. **Pacing variety.** Enemies should arrive at different times and create different tempo changes — some ramp tension, some spike it.
5. **Party chaos.** Enemies should sometimes help one player by hurting another. Asymmetric disruption = fun stories.

## Enemy Roster

### 1. Walrus (heavy bully)

**Verb:** *shoves*

**Concept:** Big, tusked, territorial. The walrus claims a patch of ice and aggressively defends it. Shoves seals away on contact — doesn't kill, but sends them flying and scatters their carried fish. A mobile zone-denial threat that's heavy enough to be immovable.

**Behavior:**
- Enters from water, hauls up onto ice (slow, dramatic entrance)
- Claims a territory: wanders slowly in a ~200px radius area, favoring spots near fish or near the baby
- When a seal enters ~180px range: charges in a short burst (~250 px/s, 0.5s) then stops
- Charge hit = seal launched hard (big bounce, drops all carried fish, stunned 0.5s). Walrus barely moves (mass difference)
- Between charges: slow waddle (~60 px/s), head-sweeping idle animation. Tusks visible
- Repositions territory toward areas with fish concentration every ~15s
- Does NOT pick up or eat fish — just guards the area and shoves anyone who approaches

**Pacing:**
- Appears at ~20s. One per round. Stays until round end
- Persistent presence — not a brief visitor but an area you have to plan around

**Visual:** Large (radius ~45px), brown, prominent tusks. Visually imposing next to the small player seals. Slow, heavy movement reads as "don't mess with this."

**Gameplay effect:** Creates a moving exclusion zone. Fish that land in walrus territory become risky to collect. Players must bait the charge and dodge, or wait for walrus to reposition. Unlike bear (which kills), walrus just disrupts — getting shoved is annoying and costly (dropped fish, lost time) but not fatal. Forces players to be strategic about approach angles.

**Interactions:**
- Seal (player): shove on charge contact, drops carried fish, stun
- Penguin: shoved away if in path (penguin tumbles, comedic)
- Bear: walrus and bear ignore each other (both too big to bother)
- Fish: doesn't eat or pick up. Just guards the area they're in
- Baby: doesn't target directly, but may wander near baby's location

---

### 2. Orca (water predator)

**Verb:** *lurks*

**Concept:** Patrols the open water around the ice floe. Seals that fall in (or linger near edges) risk getting eaten instead of safely respawning. Turns the ocean from a mild inconvenience into a genuine hazard.

**Behavior:**
- Visible as a dark shape + dorsal fin circling the floe perimeter (just outside the ice boundary)
- Moves in laps around the floe, ~200 px/s, with occasional pauses
- When a seal enters the water, orca changes course toward them. Seal has a brief grace window (~1.5s) before orca can reach and kill
- Kill = seal flung upward (comedic launch), longer respawn (5s vs normal 2s)
- Does NOT come onto ice. Strictly water-only threat
- Visual: sleek black-and-white shape, dorsal fin breaks the surface. Size ~60px long

**Pacing:**
- Appears at ~25s (before bear). Announced by a splash sound + brief fin visible
- Stays the entire round once appeared. One orca per round

**Gameplay effect:** Edge play becomes risky. Players think twice before taking shortcuts near floe edges. Creates natural "safe zone" in the center. Penguins swimming in/out are immune (too small / orca doesn't care).

**Interactions:**
- Seal (player): can be killed if in water during orca's reach window
- Penguin: ignored
- Bear: ignored (bear swims too — but orca doesn't attack bear)
- Walrus: ignored (too big)
- Fish: fish that slide into water are eaten by orca (removed from play)
- Baby: ignored (baby is on ice)

---

### 3. Skua (aerial thief)

**Verb:** *swoops*

**Concept:** A large seabird that dive-bombs from above to steal fish — but unlike penguins, it targets fish being carried by seals or stored with the baby. It's the "sniper" that punishes loaded players.

**Behavior:**
- Flies in from off-screen, circles briefly at high altitude (shadow on ice, bird visible but small)
- Targets the seal carrying the most fish, or the baby with the most stored fish
- Dive-bombs in a straight line toward target. Fast descent (~400 px/s approach). 0.8s telegraph via shadow growing larger
- On hit: steals 1 fish, immediately flies away off-screen with it (fish is gone from play)
- On miss (target moved): skua lands on ice briefly (~1s, confused), then flies away. Vulnerable to nothing — just a comedic beat
- Cannot be killed or blocked. Pure avoidance challenge

**Pacing:**
- First appears ~30s. Returns every 20-30s (randomized)
- Each visit is one dive attempt, then gone. Brief spike of tension, then calm

**Visual:** Dark bird shape, wingspan ~40px. Casts a circular shadow on ice that grows during dive. Distinct from ground-based creatures.

**Gameplay effect:** Holding fish becomes risky — deliver fast or get robbed. Targets the leader (most fish), so it's a natural catch-up mechanic. Players must watch the sky and the ice simultaneously.

**Interactions:**
- Seal (player): steals 1 carried fish on contact
- Baby: steals 1 stored fish on contact (score goes down!)
- Penguin: ignored
- Bear: ignored
- Walrus: ignored
- Ground fish: ignored (only steals carried/stored)

---

### 4. Fox (ice raider)

**Verb:** *dashes*

**Concept:** Small, fast, agile. The anti-bear. Where bear is slow and deadly, fox is fast and annoying. Sprints across the ice, grabs a ground fish, and bolts. Doesn't kill, but competes fiercely for fish.

**Behavior:**
- Enters from a random floe edge, running fast (~300 px/s max, ACCEL 800 px/s²)
- Beelines to the nearest ground fish. Picks it up on contact
- Once holding fish: immediately runs toward the nearest floe edge to escape
- If no ground fish: sniffs around briefly (wander, 2-3s), then leaves
- If a seal body-checks it (collision at speed): drops the fish, stunned 1.5s, then flees
- Does NOT kill seals. Seal-fox collision = fox is knocked aside (fox is light)
- Can be intercepted — a skilled seal can slam into a fox mid-escape to recover the fish

**Pacing:**
- First appears at ~15s. Recurs every 12-18s
- Fast visits — each fox is on-screen 3-8s max. Frequent but brief

**Visual:** Small (radius ~14px), orange-white, pointy ears. Distinctive trot animation, very different from penguin's waddle. Quick, nervous movement.

**Gameplay effect:** Creates urgent "race to the fish" moments. Unlike penguin (which is slow, then suddenly fast), fox is consistently fast. Players can counter it with skill (body-check), adding a satisfying mechanical interaction. Keeps ground fish from sitting uncollected.

**Interactions:**
- Seal (player): no damage either way. Collision knocks fox aside, fox drops fish if carrying
- Penguin: fox and penguin ignore each other
- Bear: fox flees from bear (if within 200px, fox changes target to nearest edge — self-preservation)
- Walrus: fox flees from walrus similarly
- Fish: picks up 1 ground fish on contact
- Baby: ignored

---

## Pacing Overview (full round timeline)

```
 0s   Round start — fish spawning begins
~6s   First penguin arrives
15s   First fox visit
20s   Walrus hauls up onto ice
25s   Orca appears (stays)
30s   First skua dive
35s   Bear arrives
```

Early game (0-15s): just fish + penguins. Learning the floe, low threat.
Mid game (15-30s): fox + walrus + orca add pressure. Fish competition, zone denial, edge danger.
Late game (30s+): bear + skua make everywhere dangerous. High tension, every decision matters.

## Threat Matrix

| Enemy | Kills? | Steals fish? | Zone | Counter |
|-------|--------|-------------|------|---------|
| Bear | yes | eats ground fish | roaming | avoid |
| Walrus | no (shoves) | no | territorial | bait + dodge |
| Orca | yes | eats water fish | water only | stay on ice |
| Skua | no | steals carried/stored | aerial | move when shadow appears |
| Fox | no | steals ground fish | roaming, brief | body-check |
| Penguin | no | steals ground fish | roaming | rob back |

## Which to build first

**Walrus** — thematically strong (former player species becomes enemy). Mechanically straightforward: ground movement, charge, shove. The "zone denial" role is new and creates interesting decisions immediately.

**Fox** — second. Simplest AI (beeline to fish, grab, flee). Body-check interaction is satisfying and all collision systems exist. Frequent visits keep tempo up.

**Orca** — third. Reuses the water boundary system. Makes the existing "fall in water" mechanic more dramatic. Relatively simple AI (patrol + intercept).

**Skua** — last. Needs new "aerial layer" rendering (shadow + bird above). Mechanically simple but visually new. Catch-up mechanic value is high but less urgent than core threats.

## Open questions

- **Population scaling with player count?** 1-player practice vs 4-player chaos may need different enemy density
- **Should any enemies interact with each other?** Fox fleeing bear/walrus is proposed — any others?
- **Orca + fish in water:** if fish slides off floe, does orca eat it? (proposed yes — removes fish from play, increases scarcity)
- **Skua targeting baby:** stealing from score is punishing. Alternative: skua only targets carried fish, not stored. TBD based on playtesting
- **Walrus territory vs baby:** if walrus parks near baby, delivering fish becomes very hard. Should walrus avoid baby's area, or is that an intended challenge?
- **Sound design:** each enemy needs a distinct audio cue for its arrival/attack. Critical for readability in a busy round
