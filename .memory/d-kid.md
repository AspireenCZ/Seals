# Design: Walrus Kid (replaces "home base")

## Provenance
- **Created:** 2026-03-11
- **Context:** The moving colored circle "home" is mechanically sound but thematically empty. Reframe: the walrus is a parent feeding its kid.

## Core Idea

The home base becomes a **baby walrus** — small, round, expressive. The parent collects fish and brings them back to feed the kid. Score = fish fed to kid. Match ends when kid is full (10 fish).

This changes nothing mechanically but transforms the emotional read completely: you're not scoring points, you're feeding your baby.

## Visual Design

**Shape:** Small, round, chubby walrus pup. ~60% the size of the parent. No tusks (calves don't have them). Big dark eyes, round snout, stubby flippers.

**Drawing approach:** Same as parent walrus — procedural `_draw()` in GDScript. Body is a squat oval, head is a smaller circle on top. Whisker dots. Two small front flippers pressed to the body.

**Color:** Tinted to match player color (same as current home ring), but the kid's base coat is slightly lighter/warmer than the parent. Subtle — the kid should read as belonging to its player without being a flat colored blob.

**Size progression:** Kid starts small, grows slightly as it eats. At 0 fish: smallest. At 10 fish: ~20% bigger, visibly rounder. Linear interpolation on the scale. Subtle — not ballooning, just a gentle plump-up.

## Behavior

**Movement — same as current home wander, with personality:**
- Waddles instead of gliding: slight oscillating rotation (±8°) synced to movement
- Same speed (~40px/s), same wander logic (pick distant ice point, timer-based direction changes)
- Stays on ice (same containment check as current home)

**Idle animation:**
- When parent is far: looks around (small head rotation, ±15°), occasional body wiggle
- When parent approaches with fish: perks up — slight bounce, faces parent
- After being fed: happy wiggle, brief satisfied pose

**Reaction to danger:**
- Bear nearby: huddles down (scale Y squeeze), trembles slightly
- No gameplay effect — purely visual/emotional. The bear doesn't target kids (too small? not worth it?). Or: open design question — should bear threaten kids?

## Feeding (= current delivery)

Same trigger: parent walrus enters radius around kid. Same `HOME_RADIUS`.

**Visual feedback on feed:**
- Kid does a happy chomp animation (mouth open-close)
- Small particle burst (fish bones? sparkles? — keep it simple)
- Kid's belly visibly rounder (the size progression)

**Score display:** Current HUD score bars remain. The kid's physical size is a secondary, in-world score indicator — you can glance at kids to see who's winning without reading the HUD.

## Naming

- Code: rename `home` → `kid` throughout (home_nodes → kid_nodes, homes → kid_positions, etc.)
- Player-facing: no explicit label needed. The visual reads as "your baby."
- `_generate_homes()` → `_generate_kids()`
- Signal: `fish_delivered` → `fish_fed` (or keep `fish_delivered` — it's internal)

## What Stays the Same

- Wander speed and logic
- Containment to ice polygon
- Delivery radius
- Score mechanics (10 fish to win)
- Placement at opposite sides of ice

## Open Questions

1. **Bear vs kid interaction?** Bear ignoring kids is simpler. Bear threatening kids adds drama but needs a mechanic (kid respawns? kid runs away? parent has to defend?). Suggest: keep it simple for now — bear ignores kids.
2. **Kid collision with other creatures?** Currently home is just a position, no collision. Kid as a visual entity could have a small collider for bump interactions, or stay non-physical like current home. Suggest: non-physical for now.
3. **Kid sound?** Small bark/chirp when fed, whimper when bear is near. Audio is future work — note it, don't block on it.
4. **Kid stolen?** A penguin or opponent could theoretically steal the kid or bump it further away. Very chaotic, maybe fun for a later mode. Not for v1.

## Implementation Scope

- New `kid.gd` script (CharacterBody2D or Node2D with `_draw()`)
- Modify `arena.gd`: replace home generation/update with kid instantiation
- Modify `walrus.gd`: delivery target is kid node instead of position
- Update `arctic-identity.md`: add kid to creature list
- Estimated: medium task, mostly visual work + renaming
