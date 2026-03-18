# Creature Behavior Reference

## Provenance
- **Created:** 2026-03-11, session bfa57be0
- **Source:** iterative tuning across two sessions

---

## Walrus (player)

### Movement
- ACCEL: 600 px/s², no speed cap (friction handles it)
- Friction: 0.996/frame — very icy, long coast
- Braking: 900 px/s² when input opposes velocity (dot < -0.3)
- Bounce stun: 0.15-0.2s after wall/player bounce (input suppressed)

### Collisions
- **Wall**: `velocity = pre_velocity.bounce(normal) * 0.85`. No speed_factor — same at any speed.
- **Walrus vs walrus**: symmetric bounce scaled by `speed_factor = clamp(speed / 400, 0.05, 1.0)`. High speed = powerful hit. Fish knocked loose if speed_factor > 0.4.
- **Walrus vs penguin**: walrus passes through unaffected. Penguin launched with `abs(my_along) * 3 * speed_factor + speed * 0.8`, min 120. Position restored after move_and_slide so penguin is never an obstacle.
- **Walrus vs bear**: bear is deadly when ACTIVE — instant kill, walrus flung away + fall_in_water.

### Fish carrying
- Max 2 fish. Each has origin: "ground", "penguin", "opponent".
- `collect_fish()` — pickup from ground (origin "ground")
- `collect_penguin_fish()` — awarded on penguin bump (origin "penguin")
- `deliver_fish()` — pops one fish at home zone. +1 score regardless of origin.
- `drop_fish()` — drops ALL fish on powerful bounce or water fall. Fish spawn on nearest safe ice spot.

### Water/respawn
- `fall_in_water()`: drops fish, invisible, 1.5s timer, respawn at safe point.
- Respawn: explicit reset of all fish state, 1s invincibility flash, splash effect.

---

## Penguin (AI neutral)

### States
`SWIMMING_IN → ACTIVE → LEAVING → IN_WATER → (loop)`

### On-ice movement (ACTIVE state)
Two modes, chosen by `_pick_next_mode()`:

**If fish detected (1000px range) → charge immediately:**
1. **CHARGING** (3s): creep at 20 px/s toward target. Re-aims toward fish continuously.
2. **SLIDING**: launch at 507 px/s, friction 0.992/frame. Coast to stop (<8 px/s).
3. **SLIDE_PAUSE** (1s): stand still, re-aim. If fish exists → slide again. If not → walk.

**If no fish → walk:**
1. **WALKING** (0.5-2s): 40 px/s toward wander direction. If fish appears mid-walk → switch to CHARGING immediately.
2. After walk timer → CHARGING toward wander direction.

### Fish behavior
- Detects landed fish within 1000px
- On pickup: `_has_fish = true`, immediately starts LEAVING
- If robbed (walrus bump): `drop_fish()`, 1s stun, back to ACTIVE with `_pick_next_mode()`

### Leaving (with fish)
- 0.6s pause (still collidable so walrus can rob)
- Then: slide→pause→slide cycle aimed at exit point (open water edge)
- No walking phase — slides only
- Walls disabled after pause ends

### Swimming
- Swim in: tween at ~100 px/s (distance / 100), 2-8s duration, waddle animation
- Swim away (fell off ice): tween 3s to nearest screen edge
- Sink (fell in hole): spiral shrink animation 0.8s
- Respawn timer: 3.5s (fall), 4s (escaped with fish)

### Arrive on ice
- 0.8s pause, then `_pick_next_mode()`, splash effect

---

## Bear (AI threat)

### States
`SWIMMING_IN → ACTIVE → LEAVING → GONE`

### Movement (ACTIVE)
- ACCEL: 300 px/s², MAX_SPEED: 180 px/s, friction 0.994
- Priority: fish (400px range) > nearby players (300px range) > wander
- Wall bounce: `pre_velocity.bounce(normal) * 0.4`
- Other bodies: barely affected (`velocity *= 0.95`)

### Fish eating
- Eats landed fish on contact. After 5 fish → starts leaving.
- Each eaten fish emits `fish_stolen` signal.

### Deadly
- `is_deadly()` returns true when ACTIVE
- Walrus collision → walrus dies (fall_in_water)

### Enter/leave
- Swim in: tween at ~150 px/s through open water edge, 2-6s
- Arrive: 1.0s pause, collision enabled
- Leave: 1.0s pause, then walls disabled, moves toward exit at ACCEL * 0.6
- Splash on arrive and when starting to leave

---

## Animal Pacing (arena)

- Match starts: just players + fish
- Fish: max 2 on field, 3-7s gaps between spawns, first at 3.5s
- First penguin: 6-10s
- Next penguins: +10-18s each, 2-3 total
- Bear: 35-50s
- On restart: everything resets, pacing starts fresh
