# Arctic — Project Identity

## What
2D local multiplayer party game. Seals slide on a procedural ice floe, collect fish, feed their baby to score. Heavy ice-physics movement, bump collisions, 10-fish matches.

## Core Principles
- **Ice physics first**: heavy, slidey, inertial movement is the core feel
- **Conflict by design**: fish spawns create contested situations. Carry-home mechanic adds risk.
- **Simple to extend**: 2 players now, architected for 4

## Creatures
- **Seal** (player): slides on ice, collects fish (max 2), delivers to baby seal (kid) to score. Passes through penguins.
- **Kid** (per player): baby seal, wanders ice, grows as it's fed. 10 fish to win.
- **Penguin** (AI neutral): walks slowly, charges then slides fast (~500px). Steals fish, leaves via open water. Robbable by seal bump.
- **Bear** (AI threat): slow, deadly on contact. Eats 5 fish then leaves. Hunts nearby players when no fish around. Arrives late (~40s).

## Shorthands
- **pen** = penguin
- **kid** = baby seal (scoring target, replaces old "home" circle)
- **edge** = any ice boundary (floe perimeter or hole perimeter)
- **open edge** = water-ice boundary, creatures pass through
- **closed edge** = mantinel, solid barrier
- **hole** = water pocket inside the floe

## Key Mechanics
- Speed-dependent bounce: `speed_factor = clamp(speed / 400, 0.05, 1.0)`. Long run-up = powerful hit.
- Fish origin tracking: "ground", "penguin" (robbed from pen), "opponent" (dropped by other seal).
- Animal pacing: gradual introduction. Penguins from ~8s, bear from ~40s.
- Kids: baby seals wander ice at 40px/s, grow as fed. Visual in-world score.
- Penguin movement: walk (40px/s) → charge (3s) → slide (507px/s, 0.992 friction) → 1s pause → repeat. Prefers slides when target exists.

## Files
- `scripts/arena.gd` — main orchestrator: generation, physics, scoring, UI, animal pacing
- `scripts/seal.gd` — player controller, fish carrying, collision
- `scripts/penguin.gd` — AI walk/slide movement, fish stealing, leaving
- `scripts/bear.gd` — AI predator, fish eating, player hunting
- `scripts/kid.gd` — baby seal: wanders ice, eats fish, flees to water, grows when fed
- `scripts/fish.gd` — collectible with arc jump, origin tracking
- `scripts/waves.gd` — animated ocean visuals (wave bands, caustics, foam)
- `scripts/splash.gd` — per-creature water splash particle effects
- `scripts/cadaver.gd` — bone+meat remains when bear kills kid
- `scripts/dive_ripple.gd` — lingering pulsing ripple at kid dive spot

## Arena Topology
- **Ice floe**: procedural convex polygon, the play surface
- **Mantinels**: dark hockey boards on some ice edges — solid barriers, NOT water, NOT water-ice boundary
- **Open edges**: ice edges without mantinels — these ARE the water-ice boundary where creatures enter/exit
- **Ice holes**: water pockets inside the ice floe
- Spawning near water = open edges or ice holes, never near mantinels

## Tech
- Godot 4.6, GDScript, 2D, fullscreen 1920x1080
- Single-screen arena, slight camera drift
- CharacterBody2D with MOTION_MODE_FLOATING for all creatures
- Procedural arena: random ice polygon, wall/open edges, holes, cracks, snow patches

## Status
- Pre-alpha prototype, playable

## Provenance
- **Created:** 2026-03-10
- **Updated:** 2026-03-11 — baby seal (kid) replaces home circles, cadaver, dive ripple, bear kills kid
